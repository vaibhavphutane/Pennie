import Foundation
import AppKit
import ApplicationServices

@MainActor
final class SyntheticEditor: AccessibilityAccess {
    let application = EditorApplication(name: "Fixture", bundleID: "test.editor", processID: 987_001)
    let element = AXUIElementCreateApplication(987_001)
    var focused = AXUIElementCreateApplication(987_001)
    var isTrusted = true
    var text = "This are a draft. 👋\nNext line."
    var selection: CFRange? = CFRange(location: 4, length: 0)
    var selectedOverride: String?
    var readable = true
    var protected = false
    var multipleSelections = false
    var writable: Set<String> = [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute, kAXValueAttribute]
    var textWrites = [String]()
    var rangeWrites = 0
    var textReads = 0
    var ignoreTextWrites = false
    var writeError: AXError = .success
    var onSelect: (() -> Void)?
    var onWait: (() -> Void)?
    var frontmostApplication: EditorApplication? { application }
    func activate(processID: pid_t, bundleID: String) -> Bool {
        processID == application.processID && bundleID == application.bundleID
    }
    func focusedElement(processID: pid_t, timeout: Float) -> AXUIElement? { focused }
    func pid(_ element: AXUIElement) -> pid_t? { application.processID }
    func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
        switch key as String {
        case kAXRoleAttribute: return kAXTextAreaRole as CFString
        case kAXSubroleAttribute: return (protected ? kAXSecureTextFieldSubrole : "") as CFString
        case "AXEditable", kAXEnabledAttribute: return kCFBooleanTrue
        case kAXValueAttribute:
            textReads += 1
            return readable ? text as CFString : nil
        case kAXSelectedTextAttribute:
            textReads += 1
            if let selectedOverride { return selectedOverride as CFString }
            guard let selection else { return nil }
            let ns = text as NSString
            guard selection.location >= 0, selection.length >= 0, selection.location <= ns.length,
                  selection.length <= ns.length - selection.location else { return nil }
            return ns.substring(with: NSRange(location: selection.location, length: selection.length)) as CFString
        case kAXSelectedTextRangeAttribute:
            guard var selection else { return nil }
            return AXValueCreate(.cfRange, &selection)
        case kAXSelectedTextRangesAttribute: return (multipleSelections ? [0, 1] : [0]) as CFArray
        case kAXPositionAttribute:
            var point = CGPoint(x: 100, y: 100); return AXValueCreate(.cgPoint, &point)
        case kAXSizeAttribute:
            var size = CGSize(width: 500, height: 100); return AXValueCreate(.cgSize, &size)
        default: return nil
        }
    }
    func parameterizedAttribute(_ element: AXUIElement, _ key: CFString, _ parameter: CFTypeRef) -> CFTypeRef? { nil }
    func isSettable(_ element: AXUIElement, _ key: CFString) -> Bool { writable.contains(key as String) }
    func setAttribute(_ element: AXUIElement, _ key: CFString, _ value: CFTypeRef) -> AXError {
        guard isSettable(element, key) else { return .attributeUnsupported }
        if key as String == kAXSelectedTextRangeAttribute {
            var range = CFRange()
            let axValue = unsafeBitCast(value, to: AXValue.self)
            guard AXValueGetValue(axValue, .cfRange, &range) else { return .illegalArgument }
            selection = range; rangeWrites += 1; onSelect?()
            return .success
        }
        textWrites.append(key as String)
        guard !ignoreTextWrites else { return writeError }
        guard let replacement = value as? String else { return .illegalArgument }
        if key as String == kAXValueAttribute { text = replacement; selection = CFRange(location: replacement.utf16.count, length: 0) }
        else if let selection {
            text = (text as NSString).replacingCharacters(in: NSRange(location: selection.location, length: selection.length), with: replacement)
        }
        return writeError
    }
    func wait(nanoseconds: UInt64) async throws { onWait?(); try Task.checkCancellation() }
}

@main struct AXChecks {
    @MainActor static func main() async throws {
        typealias B = AccessibilityBridge
        var checks = 0
        func check(_ ok: Bool, _ label: String) {
            precondition(ok, label)
            checks += 1
            print("PASS: \(label)")
        }
        let source = "Hi 👋, teh team.\nNext line."
        let r = (source as NSString).range(of: "teh")
        check(B.replacementPlan(context: source, range: CFRange(location: r.location, length: r.length), selected: "teh", replacement: "the") == "Hi 👋, the team.\nNext line.", "UTF-16 replacement preserves emoji, surrounding text, and newline")
        check(B.replacementPlan(context: source, range: CFRange(location: r.location, length: r.length), selected: "THE", replacement: "the") == nil, "stale selected text rejected")
        check(B.replacementPlan(context: source, range: CFRange(location: -1, length: 3), selected: "Hi ", replacement: "") == nil, "negative start rejected")
        check(B.replacementPlan(context: source, range: CFRange(location: 0, length: -1), selected: "", replacement: "") == nil, "negative length rejected")
        check(B.replacementPlan(context: source, range: CFRange(location: Int.max, length: 1), selected: "", replacement: "") == nil, "overflowing location rejected without trap")
        check(B.replacementPlan(context: source, range: CFRange(location: 1, length: Int.max), selected: "", replacement: "") == nil, "overflowing end rejected without trap")
        check(B.replacementPlan(context: source, range: CFRange(location: 0, length: 0), selected: "", replacement: "insertion") == nil, "empty selection rejected")
        check(B.replacementPlan(context: "👋", range: CFRange(location: 0, length: 1), selected: "�", replacement: "X") == nil, "split surrogate rejected")
        check(B.replacementPlan(context: "e\u{301}", range: CFRange(location: 0, length: 1), selected: "e", replacement: "x") == nil, "split combining sequence rejected")
        check(B.replacementPlan(context: "hello", range: CFRange(location: 0, length: 5), selected: "hello", replacement: "👋") == "👋", "whole selected text can become Unicode")
        check(B.replacementPlan(context: "foo bar", range: CFRange(location: 4, length: 3), selected: "bar", replacement: "longer words") == "foo longer words", "replacement length may differ from selection")
        check(B.replacementPlan(context: "foo bar", range: CFRange(location: 4, length: 4), selected: "bar", replacement: "x") == nil, "out-of-bounds selection rejected")

        func fixture() -> (SyntheticEditor, B) {
            let editor = SyntheticEditor()
            return (editor, B(access: editor))
        }
        func capture(_ bridge: B) throws -> TextCapture { try bridge.capture(allowedBundleIDs: ["test.editor"]) }
        func rejects(_ expected: CaptureError, _ label: String, _ operation: () async throws -> Void) async {
            do { try await operation(); check(false, label) }
            catch { check(error as? CaptureError == expected, label) }
        }
        let rewritten = "This is a draft. 👋\nNext line."
        do {
            let (editor, bridge) = fixture()
            let anchor = bridge.focusedEditor(allowedBundleIDs: ["test.editor"])!
            check(editor.textReads == 0, "widget tracking reads no draft text")
            let draft = try bridge.capture(allowedBundleIDs: ["test.editor"], from: anchor)
            check(draft.isWholeDraft && draft.text == editor.text && editor.rangeWrites == 0 && editor.textWrites.isEmpty,
                  "opening the widget captures a whole draft without selecting or changing it")
            try await bridge.replace(capture: draft, with: rewritten)
            check(editor.text == rewritten && editor.selection?.location == rewritten.utf16.count && editor.selection?.length == 0,
                  "whole draft replacement updates the text and verifies the UTF-16 caret")
            check(editor.textWrites == [kAXSelectedTextAttribute], "whole draft uses one selected-text write when supported")
        }
        do {
            let (editor, bridge) = fixture()
            editor.selection = nil; editor.writable = [kAXValueAttribute]
            let draft = try capture(bridge)
            try await bridge.replace(capture: draft, with: rewritten)
            check(draft.isWholeDraft && editor.text == rewritten && editor.textWrites == [kAXValueAttribute],
                  "editor without a selected range loads and replaces a writable whole draft")
        }
        do {
            let (editor, bridge) = fixture()
            editor.selection = CFRange(location: 5, length: 3)
            let passage = try capture(bridge)
            try await bridge.replace(capture: passage, with: "is")
            check(!passage.isWholeDraft && passage.text == "are" && editor.text == rewritten,
                  "nonempty selection replaces only that passage and preserves surrounding text")
        }
        do {
            let (editor, bridge) = fixture()
            editor.selection = CFRange(location: 5, length: 3); editor.writable = [kAXValueAttribute]
            let passage = try capture(bridge)
            await rejects(.replacementUnsupported, "partial selection never falls back to a whole-value write") {
                try await bridge.replace(capture: passage, with: "is")
            }
            check(editor.textWrites.isEmpty, "unsupported partial edit leaves the field untouched")
        }
        for change in ["text", "caret", "field", "multiple", "protected"] {
            let (editor, bridge) = fixture()
            let draft = try capture(bridge)
            switch change {
            case "text": editor.text += " New typing."
            case "caret": editor.selection = CFRange(location: 0, length: 0)
            case "field": editor.focused = AXUIElementCreateApplication(987_002)
            case "multiple": editor.multipleSelections = true
            default: editor.protected = true
            }
            await rejects(change == "protected" ? .protectedField : .stale, "changed \(change) prevents draft replacement") {
                try await bridge.replace(capture: draft, with: rewritten)
            }
            check(editor.textWrites.isEmpty && editor.rangeWrites == 0, "changed \(change) causes no mutation")
        }
        do {
            let (editor, bridge) = fixture()
            let anchor = bridge.focusedEditor(allowedBundleIDs: ["test.editor"])!
            editor.focused = AXUIElementCreateApplication(987_002)
            await rejects(.stale, "stale widget anchor cannot capture a different field") {
                _ = try bridge.capture(allowedBundleIDs: ["test.editor"], from: anchor)
            }
            check(editor.textReads == 0, "stale anchor rejected before reading text")
        }
        for kind in ["empty", "long", "protected", "unreadable", "unranged-selection", "multiple", "permission"] {
            let (editor, bridge) = fixture()
            let expected: CaptureError
            switch kind {
            case "empty": editor.text = "  \n"; expected = .noSelection
            case "long": editor.text = String(repeating: "x", count: 12_001); expected = .tooLong
            case "protected": editor.protected = true; expected = .protectedField
            case "unreadable": editor.readable = false; expected = .unsupported
            case "unranged-selection": editor.selection = nil; editor.selectedOverride = "are"; expected = .unsupported
            case "multiple": editor.multipleSelections = true; expected = .unsupported
            default: editor.isTrusted = false; expected = .permission
            }
            await rejects(expected, "\(kind) capture fails without broadening scope") { _ = try capture(bridge) }
        }
        do {
            let (editor, bridge) = fixture()
            let draft = try capture(bridge)
            editor.onSelect = { editor.text += " Concurrent edit." }
            await rejects(.stale, "typing during whole-draft selection prevents the text write") {
                try await bridge.replace(capture: draft, with: rewritten)
            }
            check(editor.textWrites.isEmpty, "concurrent typing is preserved")
        }
        for reportsError in [false, true] {
            let (editor, bridge) = fixture()
            let draft = try capture(bridge)
            editor.ignoreTextWrites = !reportsError
            editor.writeError = reportsError ? .cannotComplete : .success
            await rejects(.writeUncertain, "failed or unconfirmed write reports uncertainty") {
                try await bridge.replace(capture: draft, with: rewritten)
            }
            check(editor.textWrites.count == 1, "uncertain write is never retried or followed by a whole-value write")
        }
        do {
            let (editor, bridge) = fixture()
            let draft = try capture(bridge)
            let task = Task { try await bridge.replace(capture: draft, with: rewritten) }
            task.cancel()
            do { try await task.value; check(false, "cancelled write must fail") }
            catch { check(error is CancellationError && editor.textWrites.isEmpty, "cancellation before mutation preserves the draft") }
        }
        print("\(checks) checks passed")
        print("DIAGNOSTICS FOR TEST HELPER PROCESS (not the installed Pennie app):")
        print(B.diagnostics())
    }
}
