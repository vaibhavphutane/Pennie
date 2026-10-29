import AppKit
import ApplicationServices

/// An in-memory snapshot. Only `text` is eligible for submission to the selected backend.
public struct TextCapture {
    public let text: String
    public let appName: String
    public let bundleID: String
    /// Global AX screen coordinates, origin at the primary display’s top-left.
    public let bounds: CGRect?
    let element: AXUIElement
    let processID: pid_t
    let range: CFRange
    let context: String?
    let originalSelection: CFRange?
    public let isWholeDraft: Bool
}

/// Metadata only. Creating an anchor never reads AXValue or AXSelectedText.
public struct EditorAnchor {
    public let appName: String
    public let bundleID: String
    public let processID: pid_t
    public let bounds: CGRect
    let element: AXUIElement
    public func isSameField(as other: EditorAnchor) -> Bool {
        processID == other.processID && CFEqual(element, other.element)
    }
}

public enum CaptureError: LocalizedError, Equatable {
    case permission, disallowed, noSelection, protectedField, unsupported, tooLong
    case stale, replacementUnsupported, unverifiable, writeUncertain, caretUncertain

    public var errorDescription: String? {
        switch self {
        case .permission: return "Enable Pennie in System Settings → Privacy & Security → Accessibility, then try again."
        case .disallowed: return "Click a text box in an enabled application first. You can also paste text into Pennie."
        case .noSelection: return "This text box is empty. Write a draft, then open Pennie again."
        case .protectedField: return "This field is protected or read-only. Pennie will not capture it."
        case .unsupported: return "This editor does not expose readable draft text. Copy your text and paste it into Pennie."
        case .tooLong: return "Use at most 12,000 UTF-16 characters at a time. Select a shorter passage for a longer draft."
        case .stale: return "The source text, selection, or focus changed. Capture it again before replacing."
        case .replacementUnsupported: return "This editor does not support verified text replacement. Copy the suggestion and paste it into the selected text yourself."
        case .unverifiable: return "The editor does not expose enough context to verify replacement safely. Use Copy and paste manually."
        case .writeUncertain: return "The editor may have changed, but replacement could not be verified. Check the source before retrying; Pennie will not retry automatically."
        case .caretUncertain: return "The replacement was verified, but the cursor position could not be confirmed. Check the editor before continuing."
        }
    }
}

@MainActor
protocol TextAccess {
    func capture(allowedBundleIDs: Set<String>, from anchor: EditorAnchor?) throws -> TextCapture
    func replace(capture: TextCapture, with replacement: String) async throws
}

/// Public Accessibility API only. Reads happen on capture; writes happen on Accept.
/// No global typing monitor or synthetic paste.
@MainActor
public final class AccessibilityBridge: TextAccess {
    public static var isTrusted: Bool { AXIsProcessTrusted() }
    private let access: any AccessibilityAccess
    public convenience init() { self.init(access: SystemAccessibilityAccess()) }
    init(access: any AccessibilityAccess) { self.access = access }

    public static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func focusedEditor(allowedBundleIDs: Set<String>) -> EditorAnchor? {
        guard access.isTrusted, let app = access.frontmostApplication,
              app.processID != ProcessInfo.processInfo.processIdentifier,
              allowedBundleIDs.contains(app.bundleID),
              let element = access.focusedElement(processID: app.processID, timeout: 0.12),
              access.pid(element) == app.processID else { return nil }
        guard (try? checkEditable(element)) != nil,
              (access.attribute(element, "AXHidden" as CFString) as? Bool) != true,
              var frame = elementFrame(element), frame.width >= 20, frame.height >= 12 else { return nil }
        if let window = elementAttribute(element, kAXWindowAttribute as CFString) {
            AXUIElementSetMessagingTimeout(window, 0.12)
            guard (access.attribute(window, kAXMinimizedAttribute as CFString) as? Bool) != true else { return nil }
            if let windowFrame = elementFrame(window) { frame = frame.intersection(windowFrame) }
        }
        guard !frame.isEmpty, !frame.isNull else { return nil }
        return EditorAnchor(appName: app.name, bundleID: app.bundleID, processID: app.processID, bounds: frame, element: element)
    }

    private func elementAttribute(_ element: AXUIElement, _ key: CFString) -> AXUIElement? {
        guard let raw = access.attribute(element, key), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = access.attribute(element, kAXPositionAttribute as CFString), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = access.attribute(element, kAXSizeAttribute as CFString), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let p = unsafeBitCast(position, to: AXValue.self), s = unsafeBitCast(size, to: AXValue.self)
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetType(p) == .cgPoint, AXValueGetValue(p, .cgPoint, &point),
              AXValueGetType(s) == .cgSize, AXValueGetValue(s, .cgSize, &extent),
              point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// Capture the selected passage, or the entire draft when there is no selection.
    /// The anchor is checked before reading text, even when the widget was clicked late.
    public func capture(allowedBundleIDs: Set<String>, from anchor: EditorAnchor? = nil) throws -> TextCapture {
        guard access.isTrusted else { throw CaptureError.permission }
        guard let app = access.frontmostApplication,
              app.processID != ProcessInfo.processInfo.processIdentifier,
              allowedBundleIDs.contains(app.bundleID) else { throw CaptureError.disallowed }
        guard let element = access.focusedElement(processID: app.processID, timeout: 0.5) else { throw CaptureError.unsupported }
        guard access.pid(element) == app.processID else { throw CaptureError.stale }
        if let anchor {
            guard anchor.processID == app.processID, CFEqual(anchor.element, element) else { throw CaptureError.stale }
        }
        try checkEditable(element)
        guard !hasMultipleSelections(element) else { throw CaptureError.unsupported }
        let selection = selectedRange(element)
        if let selection, selection.location < 0 || selection.length < 0 { throw CaptureError.unsupported }
        let rawContext = string(element, kAXValueAttribute as CFString)
        // A bounded context is retained in memory for stale detection; never sent to inference.
        let context = rawContext.flatMap { $0.utf16.count <= 12_000 ? $0 : nil }
        let text: String, range: CFRange, isWholeDraft: Bool
        if let selection, selection.length > 0 {
            guard selection.length <= 12_000 else { throw CaptureError.tooLong }
            guard let selected = selectedText(element, range: selection), !selected.isEmpty,
                  selected.utf16.count == selection.length else { throw CaptureError.unsupported }
            text = selected; range = selection; isWholeDraft = false
        } else {
            // An editor with selected text but no usable range must never broaden to a full draft.
            guard (string(element, kAXSelectedTextAttribute as CFString) ?? "").isEmpty else { throw CaptureError.unsupported }
            guard let draft = rawContext else { throw CaptureError.unsupported }
            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureError.noSelection }
            guard draft.utf16.count <= 12_000 else { throw CaptureError.tooLong }
            if let selection, !Self.valid(selection, in: draft) { throw CaptureError.stale }
            text = draft; range = CFRange(location: 0, length: draft.utf16.count); isWholeDraft = true
        }
        if let context {
            guard Self.replacementPlan(context: context, range: range, selected: text, replacement: text) != nil else { throw CaptureError.stale }
        }
        return TextCapture(text: text, appName: app.name, bundleID: app.bundleID,
                           bounds: isWholeDraft ? elementFrame(element) : bounds(element, range: range),
                           element: element, processID: app.processID, range: range, context: context,
                           originalSelection: selection, isWholeDraft: isWholeDraft)
    }

    public func replace(capture: TextCapture, with replacement: String) async throws {
        guard access.isTrusted else { throw CaptureError.permission }
        guard !replacement.isEmpty, replacement.utf16.count <= 24_000 else { throw CaptureError.tooLong }
        guard let context = capture.context, Self.valid(capture.range, in: context) else { throw CaptureError.unverifiable }
        let canSelect = access.isSettable(capture.element, kAXSelectedTextRangeAttribute as CFString)
        let useSelectedText = capture.originalSelection != nil &&
            access.isSettable(capture.element, kAXSelectedTextAttribute as CFString) && canSelect
        // Whole-value writes are allowed only for a captured whole draft, never a partial selection.
        guard useSelectedText || (capture.isWholeDraft && access.isSettable(capture.element, kAXValueAttribute as CFString)) else {
            throw CaptureError.replacementUnsupported
        }
        guard access.activate(processID: capture.processID, bundleID: capture.bundleID) else { throw CaptureError.stale }
        try await access.wait(nanoseconds: 180_000_000)
        try Task.checkCancellation()
        guard matches(capture, context: context, selection: capture.originalSelection) else { throw CaptureError.stale }
        try checkEditable(capture.element)
        guard let expected = Self.replacementPlan(context: context, range: capture.range, selected: capture.text, replacement: replacement) else { throw CaptureError.stale }
        if useSelectedText && capture.isWholeDraft {
            // Select the captured draft only after checking that its contents and caret are unchanged.
            guard setRange(capture.range, on: capture.element) == .success else { throw CaptureError.replacementUnsupported }
            for _ in 0..<4 {
                if matches(capture, context: context, selection: capture.range) { break }
                try await access.wait(nanoseconds: 50_000_000)
            }
        }
        let expectedSelection = useSelectedText ? capture.range : capture.originalSelection
        guard matches(capture, context: context, selection: expectedSelection),
              !useSelectedText || selectedText(capture.element, range: capture.range) == capture.text else { throw CaptureError.stale }
        try checkEditable(capture.element)
        try Task.checkCancellation()
        // Exactly one text write. Never retry or switch write methods after an uncertain result.
        let attribute = useSelectedText ? kAXSelectedTextAttribute : kAXValueAttribute
        guard access.setAttribute(capture.element, attribute as CFString, replacement as CFString) == .success else {
            throw CaptureError.writeUncertain
        }
        // Do not honor cancellation between the mutation and readback: report its actual outcome.
        var verified = false
        for _ in 0..<4 {
            if string(capture.element, kAXValueAttribute as CFString) == expected { verified = true; break }
            try? await access.wait(nanoseconds: 50_000_000)
        }
        guard verified else { throw CaptureError.writeUncertain }
        let caret = CFRange(location: capture.range.location + replacement.utf16.count, length: 0)
        guard isFocused(capture), string(capture.element, kAXValueAttribute as CFString) == expected else { throw CaptureError.caretUncertain }
        if !Self.equal(selectedRange(capture.element), caret) {
            guard canSelect, setRange(caret, on: capture.element) == .success else { throw CaptureError.caretUncertain }
        }
        for _ in 0..<4 {
            if matches(capture, context: expected, selection: caret) { return }
            try? await access.wait(nanoseconds: 50_000_000)
        }
        throw CaptureError.caretUncertain
    }

    private func isFocused(_ capture: TextCapture) -> Bool {
        guard let app = access.frontmostApplication, app.processID == capture.processID, app.bundleID == capture.bundleID,
              let focused = access.focusedElement(processID: capture.processID, timeout: 0.5),
              CFEqual(focused, capture.element), access.pid(focused) == capture.processID else { return false }
        return true
    }
    private func matches(_ capture: TextCapture, context: String, selection: CFRange?) -> Bool {
        isFocused(capture) && !hasMultipleSelections(capture.element) &&
        string(capture.element, kAXValueAttribute as CFString) == context &&
        Self.equal(selectedRange(capture.element), selection)
    }
    private func setRange(_ range: CFRange, on element: AXUIElement) -> AXError {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return .illegalArgument }
        return access.setAttribute(element, kAXSelectedTextRangeAttribute as CFString, value)
    }

    /// Pure guard used by the mutation path. UTF-16 ranges must align to Swift string boundaries.
    nonisolated public static func replacementPlan(context: String, range: CFRange, selected: String, replacement: String) -> String? {
        guard valid(range, in: context), range.length > 0 else { return nil }
        let nsRange = NSRange(location: range.location, length: range.length)
        // Foundation's NSRange conversion can admit an index inside a surrogate pair.
        // Require both ends to coincide with actual extended-grapheme boundaries.
        let boundaries = Set(context.indices.map { $0.utf16Offset(in: context) } + [(context as NSString).length])
        guard boundaries.contains(nsRange.location), boundaries.contains(nsRange.location + nsRange.length),
              (context as NSString).substring(with: nsRange) == selected else { return nil }
        return (context as NSString).replacingCharacters(in: nsRange, with: replacement)
    }

    /// Metadata only: no field names, window titles, selected text, or credentials.
    public static func diagnostics() -> String {
        let ids = ["com.microsoft.Outlook", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap"]
        var lines = ["Accessibility trusted: \(isTrusted)", "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for id in ids {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let bundle = url.flatMap(Bundle.init(url:))
            let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "not installed"
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            lines.append("\(id): \(version); running=\(running)")
        }
        return lines.joined(separator: "\n")
    }

    private func string(_ element: AXUIElement, _ key: CFString) -> String? {
        access.attribute(element, key) as? String
    }
    private func checkEditable(_ element: AXUIElement) throws {
        let role = string(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = string(element, kAXSubroleAttribute as CFString) ?? ""
        guard [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role),
              subrole != kAXSecureTextFieldSubrole,
              (access.attribute(element, "AXProtectedContent" as CFString) as? Bool) != true,
              (access.attribute(element, kAXEnabledAttribute as CFString) as? Bool) != false,
              (access.attribute(element, "AXEditable" as CFString) as? Bool) != false else { throw CaptureError.protectedField }
        let explicitEditable = (access.attribute(element, "AXEditable" as CFString) as? Bool) == true
        guard explicitEditable || access.isSettable(element, kAXSelectedTextAttribute as CFString) || access.isSettable(element, kAXValueAttribute as CFString) else {
            throw CaptureError.protectedField
        }
    }
    private func hasMultipleSelections(_ element: AXUIElement) -> Bool {
        guard let ranges = access.attribute(element, kAXSelectedTextRangesAttribute as CFString) as? [Any] else { return false }
        return ranges.count > 1
    }
    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let raw = access.attribute(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }
    private func selectedText(_ element: AXUIElement, range: CFRange) -> String? {
        if let text = string(element, kAXSelectedTextAttribute as CFString) { return text }
        var copy = range
        guard let param = AXValueCreate(.cfRange, &copy) else { return nil }
        return access.parameterizedAttribute(element, kAXStringForRangeParameterizedAttribute as CFString, param) as? String
    }
    private func bounds(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var copy = range
        guard let param = AXValueCreate(.cfRange, &copy) else { return nil }
        guard let raw = access.parameterizedAttribute(element, kAXBoundsForRangeParameterizedAttribute as CFString, param),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect),
              !rect.isEmpty, !rect.isInfinite, !rect.isNull,
              rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
        return rect
    }
    nonisolated private static func valid(_ range: CFRange, in text: String) -> Bool {
        let count = (text as NSString).length
        return range.location >= 0 && range.length >= 0 && range.location <= count && range.length <= count - range.location
    }
    private static func equal(_ a: CFRange?, _ b: CFRange?) -> Bool {
        switch (a, b) {
        case let (a?, b?): return a.location == b.location && a.length == b.length
        case (nil, nil): return true
        default: return false
        }
    }
}
