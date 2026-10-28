import AppKit
import ApplicationServices
import CoreGraphics

let targets: Set<String> = [
    "com.grammarly.ProjectLlama", "com.writedock.app", "local.WriteDock", "com.writedock.WriteDock",
    "com.microsoft.Outlook", "com.microsoft.teams", "com.microsoft.teams2", "com.tinyspeck.slackmacgap"
]
let apps = NSWorkspace.shared.runningApplications.filter {
    targets.contains($0.bundleIdentifier ?? "") || $0.bundleURL?.lastPathComponent == "WriteDock.app"
}
// Do not read kCGWindowName; retain IDs/layer/owner pid only.
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var result: [String: Any] = [
    "accessibilityTrustedForThisHelper": AXIsProcessTrusted(),
    "screenCaptureAllowedForThisHelper": CGPreflightScreenCaptureAccess(),
    "helperPID": ProcessInfo.processInfo.processIdentifier,
    "scope": "Metadata only. Permissions apply to this executable/launching context, not proof of WriteDock permission.",
    "applications": apps.map { app -> [String: Any] in
        let appWindows = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier) }
        return [
            "bundleID": app.bundleIdentifier ?? "unknown", "pid": app.processIdentifier,
            "windowIDs": appWindows.compactMap { $0[kCGWindowNumber as String] as? Int },
            "windowLayers": appWindows.compactMap { $0[kCGWindowLayer as String] as? Int }
        ]
    }
]
if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
