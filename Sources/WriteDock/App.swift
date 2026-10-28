import AppKit
import Carbon
import SwiftUI
import WriteDockCore

@MainActor
final class EditorState: ObservableObject {
    let settings: AppSettings
    @Published var source = ""
    @Published var suggestion = ""
    @Published var action: WritingAction = .grammar
    @Published var status = "Select text in Outlook, Teams, or Slack and press ⌘⇧G, or paste text here."
    @Published var busy = false
    @Published var replacing = false
    @Published var origin = "Scratchpad"
    @Published var accepted = false
    var capture: TextCapture?
    var request: Task<Void, Never>?
    private var generation = UUID()
    private let bridge = AccessibilityBridge()
    init(settings: AppSettings) { self.settings = settings }

    func captureSelection() -> CGRect? {
        resetResult()
        do {
            let value = try bridge.capture(allowedBundleIDs: settings.allowedApps)
            capture = value; source = value.text; origin = value.appName
            status = "Review the exact text below. Nothing has been sent."
            return value.bounds
        } catch {
            capture = nil; source = ""; origin = "Scratchpad"
            status = error.localizedDescription + " Copy the selection yourself, then use Paste text."
            return nil
        }
    }
    func resetResult() {
        guard !replacing else { return }
        request?.cancel(); request = nil; generation = UUID()
        busy = false; suggestion = ""; accepted = false
    }
    func sourceChanged() {
        resetResult()
        // Edited/redacted input cannot overwrite the original selection automatically.
        if capture?.text != source { capture = nil; origin = "Scratchpad" }
    }
    func paste() {
        resetResult(); capture = nil; origin = "Scratchpad"
        source = NSPasteboard.general.string(forType: .string) ?? ""
        status = "Review or redact this text before sending."
    }
    func send() {
        resetResult()
        let text = source, config = settings.config, preferences = settings.preferences, selectedAction = action
        let id = generation
        busy = true; status = "Requesting \(selectedAction.label.lowercased()) from \(config.kind.label)…"
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try CredentialStore.read(config.kind, config.baseURL)
                let output = try await InferenceClient().rewrite(text: text, action: selectedAction, preferences: preferences, config: config, apiKey: key)
                guard !Task.isCancelled, self.generation == id else { return }
                self.suggestion = output
                self.status = output == text ? "No changes suggested." : "Review the suggestion. Your source application has not changed."
            } catch {
                guard self.generation == id else { return }
                self.status = Task.isCancelled ? "Request cancelled." : error.localizedDescription
            }
            if self.generation == id { self.busy = false; self.request = nil }
        }
    }
    func cancel() {
        guard !replacing else { return }
        resetResult(); status = "Request cancelled. No replacement was made."
    }
    func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(suggestion, forType: .string)
        status = "Suggestion copied. Paste into your chosen selection and review its formatting."
    }
    func accept() {
        accepted = true
        status = capture == nil ? "Accepted. Use Copy to paste it into your app." : "Accepted. Replace will recheck the original selection before applying."
    }
    func replace() {
        guard let capture, !suggestion.isEmpty, suggestion != source, !busy else { return }
        guard settings.allowedApps.contains(capture.bundleID) else {
            self.capture = nil; status = "Capture is disabled for this application. Use Copy if you want to paste manually."
            return
        }
        let replacement = suggestion
        busy = true; replacing = true
        request = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.bridge.replace(capture: capture, with: replacement)
                self.capture = nil
                self.status = "Replacement and cursor position verified. Review rich formatting in the source app."
            } catch { self.capture = nil; self.status = error.localizedDescription }
            self.replacing = false; self.busy = false; self.request = nil
        }
    }
}

struct EditorView: View {
    @ObservedObject var state: EditorState
    @ObservedObject var settings: AppSettings
    let showSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "pencil.and.outline").font(.system(size: 26, weight: .semibold)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("WriteDock").font(.title2.bold())
                    Text("A little polish. Still your voice.").foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: showSettings) { Label("Settings", systemImage: "gearshape") }
                    .disabled(state.replacing)
            }
            HStack {
                Label(state.origin, systemImage: "text.cursor").font(.caption.weight(.medium))
                Spacer()
                Text("⌘⇧G · Capture selection").font(.caption).foregroundStyle(.secondary)
                Button("Paste text") { state.paste() }.disabled(state.busy)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TEXT TO SEND").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextEditor(text: $state.source).font(.system(size: 15)).padding(10)
                        .background(.background).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                        .disabled(state.busy)
                    Text("\(state.source.utf16.count) / 12,000 characters · Edit or redact before sending")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.accepted ? "ACCEPTED SUGGESTION" : "SUGGESTION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        Text(state.suggestion.isEmpty ? "Your suggestion will appear here." : state.suggestion)
                            .foregroundStyle(state.suggestion.isEmpty ? .secondary : .primary)
                            .font(.system(size: 15)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.teal.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(0.18)))
                    HStack {
                        Button("Accept") { state.accept() }.disabled(state.suggestion.isEmpty || state.busy || state.accepted)
                        Button("Replace selection") { state.replace() }.disabled(state.capture == nil || !state.accepted || state.busy || state.suggestion == state.source)
                        Button("Copy") { state.copy() }.disabled(state.suggestion.isEmpty || state.busy)
                        Button("Dismiss") { state.resetResult(); state.status = "Suggestion dismissed." }.disabled(state.suggestion.isEmpty || state.busy)
                    }.controlSize(.small)
                }
            }.frame(minHeight: 260)
            HStack {
                Picker("Action", selection: $state.action) {
                    ForEach(WritingAction.allCases) { Text($0.label).tag($0) }
                }.frame(maxWidth: 330).disabled(state.busy)
                Spacer()
                if state.busy {
                    ProgressView().controlSize(.small)
                    if !state.replacing { Button("Cancel") { state.cancel() } }
                }
                Button("Send to \(settings.backend.label)") { state.send() }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(state.busy || state.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.source.utf16.count > 12_000)
            }
            Text(state.status).font(.callout).textSelection(.enabled).frame(minHeight: 35, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 3) {
                Text("Destination: \(settings.provider.baseURL.isEmpty ? "configure in Settings" : settings.provider.baseURL) · Model: \(settings.provider.model.isEmpty ? "not configured" : settings.provider.model)")
                Text("Only this text and your writing preferences are sent when you press Send. No text history is saved.")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 850, minHeight: 560)
            .onChange(of: state.source) { _ in state.sourceChanged() }
            .onChange(of: state.action) { _ in state.resetResult() }
            .onChange(of: settings.config) { _ in
                state.resetResult()
                if !state.replacing { state.status = "Backend settings changed. Review the destination before sending." }
            }
            .onChange(of: settings.preferences) { _ in state.resetResult() }
    }
}

final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var callback: () -> Void = {}
    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().callback()
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { return false }
        return RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x57444F43, id: 1), GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    deinit { if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var state = EditorState(settings: settings)
    var window: NSWindow!
    var settingsWindow: NSWindow?
    var menuItem: NSStatusItem!
    let shortcut = GlobalShortcut()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu(); let root = NSMenuItem(); appMenu.addItem(root)
        let menu = NSMenu(); root.submenu = menu
        menu.addItem(withTitle: "About WriteDock", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit WriteDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "Edit"; appMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (name, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = appMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 610), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "WriteDock"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(state: state, settings: settings, showSettings: { [weak self] in self?.openSettings() }))
        window.center()
        menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuItem.button?.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "WriteDock")
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle: "Open WriteDock", action: #selector(show), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Capture selection (⌘⇧G)", action: #selector(capture), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        statusMenu.addItem(.separator()); statusMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menuItem.menu = statusMenu
        shortcut.callback = { [weak self] in Task { @MainActor in self?.capture() } }
        if !shortcut.register() { state.status = "⌘⇧G is in use by another application. Use the WriteDock menu bar capture action or Paste text." }
        show()
        if CommandLine.arguments.contains("--render-preview") {
            state.source = "This are a example. I has recieved teh message.\n\nCan you send the updated timeline tommorow?"
            // A local UI fixture, not a provider result. Never written into settings or sent anywhere.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.state.suggestion = "This is an example. I have received the message.\n\nCan you send the updated timeline tomorrow?"
                self.state.status = "Local UI preview fixture · no inference request was made."
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let view = self.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let data = bitmap.representation(using: .png, properties: [:]) {
                            try? data.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/evidence/app-preview.png"))
                        }
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
    @objc func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func capture() {
        if state.busy { return }
        let bounds = state.captureSelection()
        if settings.nearSelection, let bounds, let screen = NSScreen.screens.first(where: { screen in
            guard let first = NSScreen.screens.first else { return false }
            let cocoaPoint = NSPoint(x: bounds.midX, y: first.frame.maxY - bounds.midY)
            return screen.frame.contains(cocoaPoint)
        }), let first = NSScreen.screens.first {
            let visible = screen.visibleFrame
            let x = min(max(bounds.minX, visible.minX), max(visible.minX, visible.maxX - window.frame.width))
            let y = min(max(first.frame.maxY - bounds.maxY - window.frame.height - 8, visible.minY), max(visible.minY, visible.maxY - window.frame.height))
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        show()
    }
    @objc func openSettings() {
        guard !state.replacing else { return }
        state.cancel()
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settingsWindow?.title = "WriteDock Settings"; settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(settings: settings)); settingsWindow?.center()
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { state.request?.cancel(); settings.save() }
}

@main
struct WriteDockApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check-keychain") {
            let endpoint = "https://keychain-check.invalid/" + UUID().uuidString
            do {
                defer { try? CredentialStore.delete(.liteLLM, endpoint) }
                try CredentialStore.write("local-test-fixture", kind: .liteLLM, baseURL: endpoint)
                guard try CredentialStore.read(.liteLLM, endpoint) == "local-test-fixture" else { throw CredentialStore.StoreError.failure(-1) }
                guard try CredentialStore.read(.openRouter, endpoint).isEmpty else { throw CredentialStore.StoreError.failure(-1) }
                guard try CredentialStore.read(.liteLLM, endpoint + "/changed").isEmpty else { throw CredentialStore.StoreError.failure(-1) }
                try CredentialStore.delete(.liteLLM, endpoint)
                guard try CredentialStore.read(.liteLLM, endpoint).isEmpty else { throw CredentialStore.StoreError.failure(-1) }
                print("PASS: Keychain write/read, backend isolation, endpoint isolation, and delete (temporary fixture removed).")
            } catch { fputs("FAIL: Keychain check: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            print(AccessibilityBridge.diagnostics())
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
