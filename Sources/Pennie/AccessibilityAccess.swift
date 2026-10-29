import AppKit
import ApplicationServices

struct EditorApplication {
    let name: String
    let bundleID: String
    let processID: pid_t
}

/// The OS boundary is injectable so capture and write verification can be exercised
/// against synthetic editors without touching another application's drafts.
@MainActor
protocol AccessibilityAccess {
    var isTrusted: Bool { get }
    var frontmostApplication: EditorApplication? { get }
    func activate(processID: pid_t, bundleID: String) -> Bool
    func focusedElement(processID: pid_t, timeout: Float) -> AXUIElement?
    func pid(_ element: AXUIElement) -> pid_t?
    func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef?
    func parameterizedAttribute(_ element: AXUIElement, _ key: CFString, _ parameter: CFTypeRef) -> CFTypeRef?
    func isSettable(_ element: AXUIElement, _ key: CFString) -> Bool
    func setAttribute(_ element: AXUIElement, _ key: CFString, _ value: CFTypeRef) -> AXError
    func wait(nanoseconds: UInt64) async throws
}

@MainActor
struct SystemAccessibilityAccess: AccessibilityAccess {
    var isTrusted: Bool { AXIsProcessTrusted() }
    var frontmostApplication: EditorApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        return EditorApplication(name: app.localizedName ?? bundleID, bundleID: bundleID, processID: app.processIdentifier)
    }
    func activate(processID: pid_t, bundleID: String) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: processID),
              app.bundleIdentifier == bundleID, !app.isTerminated else { return false }
        return app.activate(options: [])
    }
    func focusedElement(processID: pid_t, timeout: Float) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, timeout)
        guard let raw = attribute(application, kAXFocusedUIElementAttribute as CFString),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }
    func pid(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }
    func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value
    }
    func parameterizedAttribute(_ element: AXUIElement, _ key: CFString, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, key, parameter, &value) == .success else { return nil }
        return value
    }
    func isSettable(_ element: AXUIElement, _ key: CFString) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, key, &result) == .success && result.boolValue
    }
    func setAttribute(_ element: AXUIElement, _ key: CFString, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, key, value)
    }
    func wait(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}
