import AppKit
import ApplicationServices

/// An in-memory snapshot. Only `text` is eligible for submission to the selected backend.
public struct TextCapture {
    public let text: String
    public let appName: String
    public let bundleID: String
    /// Global AX screen coordinates, origin at the primary display’s top-left.
    public let bounds: CGRect?
    fileprivate let element: AXUIElement
    fileprivate let processID: pid_t
    fileprivate let range: CFRange
    fileprivate let context: String?
}

/// Metadata only. Creating an anchor never reads AXValue or AXSelectedText.
public struct EditorAnchor {
    public let appName: String
    public let bundleID: String
    public let processID: pid_t
    public let bounds: CGRect
    fileprivate let element: AXUIElement
    public func isSameField(as other: EditorAnchor) -> Bool {
        processID == other.processID && CFEqual(element, other.element)
    }
}

public enum CaptureError: LocalizedError {
    case permission, disallowed, noSelection, protectedField, unsupported, tooLong
    case stale, replacementUnsupported, unverifiable, writeUncertain, caretUncertain

    public var errorDescription: String? {
        switch self {
        case .permission: return "Enable WriteDock in System Settings → Privacy & Security → Accessibility, then try again."
        case .disallowed: return "Select text in an enabled application first. You can also paste text into WriteDock."
        case .noSelection: return "Select the text you want to improve, then press the shortcut again."
        case .protectedField: return "This field is protected or read-only. WriteDock will not capture it."
        case .unsupported: return "This editor does not expose an accessible text selection. Copy the selection and paste it into WriteDock."
        case .tooLong: return "Select at most 12,000 UTF-16 characters at a time."
        case .stale: return "The source text, selection, or focus changed. Capture it again before replacing."
        case .replacementUnsupported: return "This editor does not support verified selection replacement. Copy the suggestion and paste it into the selected text yourself."
        case .unverifiable: return "The editor does not expose enough context to verify replacement safely. Use Copy and paste manually."
        case .writeUncertain: return "The editor may have changed, but replacement could not be verified. Check the source before retrying; WriteDock will not retry automatically."
        case .caretUncertain: return "The replacement was verified, but the cursor position could not be confirmed. Check the editor before continuing."
        }
    }
}

/// Public Accessibility API only. No global typing monitor, whole-field writes, or synthetic paste.
@MainActor
public final class AccessibilityBridge {
    public static var isTrusted: Bool { AXIsProcessTrusted() }
    public init() {}

    public static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func focusedEditor(allowedBundleIDs: Set<String>) -> EditorAnchor? {
        guard Self.isTrusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundle = app.bundleIdentifier, allowedBundleIDs.contains(bundle) else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.12)
        guard let element = Self.focusedElement(application), Self.pid(element) == app.processIdentifier else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.12)
        guard (try? Self.checkEditable(element)) != nil,
              (Self.attribute(element, "AXHidden" as CFString) as? Bool) != true,
              var frame = Self.elementFrame(element), frame.width >= 20, frame.height >= 12 else { return nil }
        if let window = Self.elementAttribute(element, kAXWindowAttribute as CFString) {
            AXUIElementSetMessagingTimeout(window, 0.12)
            guard (Self.attribute(window, kAXMinimizedAttribute as CFString) as? Bool) != true else { return nil }
            if let windowFrame = Self.elementFrame(window) { frame = frame.intersection(windowFrame) }
        }
        guard !frame.isEmpty, !frame.isNull else { return nil }
        return EditorAnchor(appName: app.localizedName ?? bundle, bundleID: bundle, processID: app.processIdentifier, bounds: frame, element: element)
    }

    /// Called only on a widget click. A draft without a selection is preview/copy only.
    public func readDraft(from anchor: EditorAnchor, allowedBundleIDs: Set<String>) throws -> String {
        guard let current = focusedEditor(allowedBundleIDs: allowedBundleIDs), current.isSameField(as: anchor) else { throw CaptureError.stale }
        guard !Self.hasMultipleSelections(current.element) else { throw CaptureError.unsupported }
        // Never silently broaden a nonempty selection into the full field if capture failed.
        guard let range = Self.selectedRange(current.element), range.length == 0 else { throw CaptureError.unsupported }
        guard let value = Self.string(current.element, kAXValueAttribute as CFString), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureError.noSelection }
        guard value.utf16.count <= 12_000 else { throw CaptureError.tooLong }
        return value
    }

    private static func elementAttribute(_ element: AXUIElement, _ key: CFString) -> AXUIElement? {
        guard let raw = attribute(element, key), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute as CFString), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute as CFString), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let p = unsafeBitCast(position, to: AXValue.self), s = unsafeBitCast(size, to: AXValue.self)
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetType(p) == .cgPoint, AXValueGetValue(p, .cgPoint, &point),
              AXValueGetType(s) == .cgSize, AXValueGetValue(s, .cgSize, &extent),
              point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    public func capture(allowedBundleIDs: Set<String>) throws -> TextCapture {
        guard Self.isTrusted else { throw CaptureError.permission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundle = app.bundleIdentifier,
              allowedBundleIDs.contains(bundle) else { throw CaptureError.disallowed }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let element = Self.focusedElement(application) else { throw CaptureError.unsupported }
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard Self.pid(element) == app.processIdentifier else { throw CaptureError.stale }
        try Self.checkEditable(element)
        guard !Self.hasMultipleSelections(element) else { throw CaptureError.unsupported }
        guard let range = Self.selectedRange(element), range.location >= 0, range.length > 0 else {
            throw CaptureError.noSelection
        }
        guard range.length <= 12_000 else { throw CaptureError.tooLong }
        let rawContext = Self.string(element, kAXValueAttribute as CFString)
        // A bounded context is retained in memory for stale detection; never sent to inference.
        let context = rawContext.flatMap { ($0 as NSString).length <= 12_000 ? $0 : nil }
        guard let selected = Self.selectedText(element, range: range), !selected.isEmpty,
              (selected as NSString).length == range.length else { throw CaptureError.unsupported }
        if let context {
            guard Self.replacementPlan(context: context, range: range, selected: selected, replacement: selected) != nil else {
                throw CaptureError.stale
            }
        }
        return TextCapture(text: selected, appName: app.localizedName ?? bundle, bundleID: bundle,
                           bounds: Self.bounds(element, range: range), element: element,
                           processID: app.processIdentifier, range: range, context: context)
    }

    public func replace(capture: TextCapture, with replacement: String) async throws {
        guard Self.isTrusted else { throw CaptureError.permission }
        guard !replacement.isEmpty, (replacement as NSString).length <= 24_000 else { throw CaptureError.tooLong }
        guard let context = capture.context, Self.valid(capture.range, in: context) else { throw CaptureError.unverifiable }
        guard let app = NSRunningApplication(processIdentifier: capture.processID),
              app.bundleIdentifier == capture.bundleID, !app.isTerminated else { throw CaptureError.stale }
        guard Self.isSettable(capture.element, kAXSelectedTextAttribute as CFString),
              Self.isSettable(capture.element, kAXSelectedTextRangeAttribute as CFString) else {
            throw CaptureError.replacementUnsupported
        }
        guard app.activate(options: []) else { throw CaptureError.stale }
        try await Task.sleep(nanoseconds: 180_000_000)
        try Task.checkCancellation()
        let application = AXUIElementCreateApplication(capture.processID)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == capture.processID,
              let focused = Self.focusedElement(application), CFEqual(focused, capture.element),
              Self.pid(focused) == capture.processID,
              let currentRange = Self.selectedRange(focused), Self.equal(currentRange, capture.range),
              !Self.hasMultipleSelections(focused),
              Self.string(focused, kAXValueAttribute as CFString) == context,
              Self.selectedText(focused, range: currentRange) == capture.text else { throw CaptureError.stale }
        try Self.checkEditable(focused)
        guard let expected = Self.replacementPlan(context: context, range: capture.range, selected: capture.text, replacement: replacement) else { throw CaptureError.stale }
        try Task.checkCancellation()
        // Exactly one mutation. Never fall back to AXValue or retry after an uncertain write.
        guard AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success else {
            throw CaptureError.writeUncertain
        }
        // Do not honor cancellation between the mutation and readback: report its actual outcome.
        var verified = false
        for _ in 0..<4 {
            if Self.string(focused, kAXValueAttribute as CFString) == expected { verified = true; break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard verified else { throw CaptureError.writeUncertain }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == capture.processID,
              let stillFocused = Self.focusedElement(application), CFEqual(stillFocused, focused),
              Self.string(focused, kAXValueAttribute as CFString) == expected else { throw CaptureError.caretUncertain }
        var caret = CFRange(location: capture.range.location + (replacement as NSString).length, length: 0)
        guard let value = AXValueCreate(.cfRange, &caret),
              AXUIElementSetAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw CaptureError.caretUncertain
        }
        for _ in 0..<4 {
            if let actual = Self.selectedRange(focused), Self.equal(actual, caret),
               Self.string(focused, kAXValueAttribute as CFString) == expected,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == capture.processID,
               let finalFocus = Self.focusedElement(application), CFEqual(finalFocus, focused) { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CaptureError.caretUncertain
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

    private static func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value
    }
    private static func string(_ element: AXUIElement, _ key: CFString) -> String? {
        attribute(element, key) as? String
    }
    private static func focusedElement(_ application: AXUIElement) -> AXUIElement? {
        guard let value = attribute(application, kAXFocusedUIElementAttribute as CFString),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    private static func pid(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }
    private static func isSettable(_ element: AXUIElement, _ key: CFString) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, key, &result) == .success && result.boolValue
    }
    private static func checkEditable(_ element: AXUIElement) throws {
        let role = string(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = string(element, kAXSubroleAttribute as CFString) ?? ""
        guard [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role),
              subrole != kAXSecureTextFieldSubrole,
              (attribute(element, "AXProtectedContent" as CFString) as? Bool) != true,
              (attribute(element, kAXEnabledAttribute as CFString) as? Bool) != false,
              (attribute(element, "AXEditable" as CFString) as? Bool) != false else { throw CaptureError.protectedField }
        let explicitEditable = (attribute(element, "AXEditable" as CFString) as? Bool) == true
        guard explicitEditable || isSettable(element, kAXSelectedTextAttribute as CFString) || isSettable(element, kAXValueAttribute as CFString) else {
            throw CaptureError.protectedField
        }
    }
    private static func hasMultipleSelections(_ element: AXUIElement) -> Bool {
        guard let ranges = attribute(element, kAXSelectedTextRangesAttribute as CFString) as? [Any] else { return false }
        return ranges.count > 1
    }
    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }
    private static func selectedText(_ element: AXUIElement, range: CFRange) -> String? {
        if let text = string(element, kAXSelectedTextAttribute as CFString) { return text }
        var copy = range
        guard let param = AXValueCreate(.cfRange, &copy) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, param, &raw) == .success else { return nil }
        return raw as? String
    }
    private static func bounds(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var copy = range
        guard let param = AXValueCreate(.cfRange, &copy) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, param, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
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
    private static func equal(_ a: CFRange, _ b: CFRange) -> Bool { a.location == b.location && a.length == b.length }
}
