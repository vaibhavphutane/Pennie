import AppKit
import Carbon
import Combine
import SwiftUI
import WriteDockCore

@MainActor
final class EditorState: ObservableObject {
    let settings: AppSettings
    let allowsInference: Bool
    @Published var source = "" { didSet { if oldValue != source { sourceChanged() } } }
    @Published var suggestion = ""
    @Published var action: WritingAction = .grammar {
        didSet {
            if oldValue != action {
                resetResult()
                status = "Selected \(action.label). Press Send to request a result."
            }
        }
    }
    @Published var customInstruction = "" { didSet { if oldValue != customInstruction { resetResult() } } }
    @Published var targetLanguage = "English" { didSet { if oldValue != targetLanguage { resetResult() } } }
    @Published var showChanges = false
    @Published var hasResponse = false
    @Published var status = "Select text in Outlook, Teams, or Slack and press ⌘⇧G, or paste text here."
    @Published var busy = false
    @Published var replacing = false
    @Published var origin = "Scratchpad"
    @Published var accepted = false
    var capture: TextCapture?
    var request: Task<Void, Never>?
    private var generation = UUID()
    private let bridge = AccessibilityBridge()
    private var settingsSubscriptions = Set<AnyCancellable>()
    init(settings: AppSettings, allowsInference: Bool = true) {
        self.settings = settings
        self.allowsInference = allowsInference
        Publishers.CombineLatest4(settings.$backend, settings.$openRouter, settings.$liteLLM, settings.$preferences)
            .dropFirst().sink { [weak self] _ in self?.resetResult() }.store(in: &settingsSubscriptions)
        Publishers.CombineLatest(settings.$openAI, settings.$anthropic)
            .dropFirst().sink { [weak self] _ in self?.resetResult() }.store(in: &settingsSubscriptions)
        settings.$writingProfile.dropFirst().sink { [weak self] _ in self?.resetResult() }.store(in: &settingsSubscriptions)
    }
    var outcome: SuggestionOutcome { SuggestionOutcome.classify(source: source, result: suggestion, action: action) }
    var canApplyResult: Bool { !suggestion.isEmpty && outcome == .changed && !action.isAnalysis }
    var canSend: Bool {
        allowsInference && !busy && !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && source.utf16.count <= 12_000 &&
        (action != .custom || (!customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && customInstruction.count <= 1_000)) &&
        (action != .translate || (!targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetLanguage.count <= 80))
    }
    var resultTitle: String {
        if outcome == .unchanged { return "UNCHANGED TEXT" }
        if action.isAnalysis { return "TONE INSIGHTS" }
        return accepted ? "ACCEPTED SUGGESTION" : "SUGGESTION"
    }

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
    func captureFromWidget(_ anchor: EditorAnchor) {
        guard !busy else { return }
        resetResult(); capture = nil
        do {
            guard let current = bridge.focusedEditor(allowedBundleIDs: settings.allowedApps), current.isSameField(as: anchor) else { throw CaptureError.stale }
            do {
                let selected = try bridge.capture(allowedBundleIDs: settings.allowedApps)
                capture = selected; source = selected.text; origin = selected.appName
                status = "Selection captured. Review it before sending."
            } catch CaptureError.noSelection {
                source = try bridge.readDraft(from: anchor, allowedBundleIDs: settings.allowedApps)
                origin = anchor.appName + " · draft"
                status = "Draft preview. Copy the result back, or select text in your app for direct replacement."
            }
        } catch { source = ""; origin = anchor.appName; status = error.localizedDescription }
    }
    func resetResult() {
        guard !replacing else { return }
        request?.cancel(); request = nil; generation = UUID()
        busy = false; suggestion = ""; accepted = false; hasResponse = false; showChanges = false
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
    func send(regenerate: Bool = false) {
        guard allowsInference, !busy else { return }
        resetResult()
        let text = source, config = settings.config, preferences = settings.preferences, selectedAction = action
        let profile = settings.writingProfile, custom = customInstruction, language = targetLanguage
        let id = generation
        busy = true; status = "Requesting \(selectedAction.label.lowercased()) from \(config.kind.label)…"
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try CredentialStore.read(config.kind, config.baseURL)
                let output = try await InferenceClient().rewrite(text: text, action: selectedAction, preferences: preferences, config: config, apiKey: key,
                    profile: profile, customInstruction: custom, targetLanguage: language, regenerate: regenerate)
                guard !Task.isCancelled, self.generation == id else { return }
                self.receive(output)
            } catch {
                guard self.generation == id else { return }
                self.status = Task.isCancelled ? "Request cancelled." : error.localizedDescription
            }
            if self.generation == id { self.busy = false; self.request = nil }
        }
    }
    func receive(_ output: String) {
        suggestion = output; hasResponse = true; accepted = false
        switch outcome {
        case .unchanged:
            status = action == .grammar
                ? "The model returned unchanged text. There is no edit to apply. If you expected a correction, try Improve writing, Regenerate, or the sample test in Settings."
                : "The model echoed the input without completing this action. Nothing was changed. Try Regenerate or another model; Settings has a sample test."
        case .analysis: status = "Tone report ready. This is feedback, not replacement text."
        case .changed: status = "Review the result or Show changes, then Accept and Replace. Your source app has not changed."
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
        guard canApplyResult, !busy else { return }
        accepted = true
        status = capture == nil ? "Accepted. Use Copy to paste it into your app." : "Accepted. Replace will recheck the original selection before applying."
    }
    func replace() {
        guard let capture, canApplyResult, accepted, !busy else { return }
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
                NibMascot(size: 54, animated: false)
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
                    Text(state.suggestion.isEmpty ? "SUGGESTION" : state.resultTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        if state.suggestion.isEmpty {
                            Text("Your suggestion will appear here.").foregroundStyle(.secondary).padding(14)
                        } else { SuggestionText(state: state).font(.system(size: 15)).padding(14) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.teal.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(0.18)))
                    if state.canApplyResult {
                        Toggle("Show changes · added / removed", isOn: $state.showChanges).font(.caption)
                    }
                    HStack {
                        Button("Accept") { state.accept() }.disabled(!state.canApplyResult || state.busy || state.accepted)
                        Button("Replace selection") { state.replace() }.disabled(state.capture == nil || !state.accepted || state.busy || !state.canApplyResult)
                        Button("Copy") { state.copy() }.disabled(state.suggestion.isEmpty || state.busy)
                        Button("Dismiss") { state.resetResult(); state.status = "Suggestion dismissed." }.disabled(state.suggestion.isEmpty || state.busy)
                    }.controlSize(.small)
                }
            }.frame(minHeight: 260)
            ActionDetails(state: state)
            HStack {
                WritingActionPicker(state: state).frame(maxWidth: 360)
                if state.hasResponse {
                    Button("Regenerate") { state.send(regenerate: true) }.disabled(!state.canSend)
                }
                Spacer()
                if state.busy {
                    ProgressView().controlSize(.small)
                    if !state.replacing { Button("Cancel") { state.cancel() } }
                }
                Button("Send to \(settings.backend.label)") { state.send() }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(!state.canSend)
            }
            Text(state.action.help).font(.caption).foregroundStyle(.secondary)
            Text(state.status).font(.callout).textSelection(.enabled).frame(minHeight: 35, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 3) {
                Text("Destination: \(settings.provider.baseURL.isEmpty ? "configure in Settings" : settings.provider.baseURL) · Model: \(settings.provider.model.isEmpty ? "not configured" : settings.provider.model)")
                Text("Send or Regenerate submits this text, your request, goals, dictionary, and preferences. No text history is saved.")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 850, minHeight: 660)
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
    var floatingWidget: FloatingWidgetController?
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
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
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
        let widgetItem = NSMenuItem(title: "Pause floating widget", action: #selector(toggleWidget), keyEquivalent: "")
        widgetItem.target = self
        statusMenu.insertItem(widgetItem, at: 2)
        let arguments = CommandLine.arguments
        let diagnosticsURL: URL?
        if let index = arguments.firstIndex(of: "--widget-diagnostics"), arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/") {
            diagnosticsURL = URL(fileURLWithPath: arguments[index + 1])
        } else { diagnosticsURL = nil }
        floatingWidget = FloatingWidgetController(state: state, settings: settings, diagnosticsURL: diagnosticsURL, openEditor: { [weak self] in self?.show() }, openSettings: { [weak self] in self?.openSettings() })
        if !CommandLine.arguments.contains("--render-preview") {
            floatingWidget?.start()
        }
        shortcut.callback = { [weak self] in Task { @MainActor in self?.capture() } }
        if !shortcut.register() { state.status = "⌘⇧G is in use by another application. Use the WriteDock menu bar capture action or Paste text." }
        if CommandLine.arguments.contains("--show-settings") { openSettings() } else { show() }
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
    @objc func show() {
        floatingWidget?.dismiss(clear: false)
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    @objc func toggleWidget(_ sender: NSMenuItem) {
        settings.widgetEnabled.toggle(); settings.save()
        sender.title = settings.widgetEnabled ? "Pause floating widget" : "Resume floating widget"
        floatingWidget?.refresh()
    }
    @objc func capture() {
        if state.busy { return }
        floatingWidget?.dismiss(clear: false)
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
        floatingWidget?.dismiss(clear: false)
        state.cancel()
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            settingsWindow?.minSize = NSSize(width: 580, height: 580)
            settingsWindow?.title = "WriteDock Settings"; settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(settings: settings)); settingsWindow?.center()
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { floatingWidget?.stop(); state.request?.cancel(); CredentialStore.clearSession(); settings.save() }
}

@main
struct WriteDockApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check-configured-backend") {
            _ = NSApplication.shared
            Task { @MainActor in
                let passed = await BackendDiagnostics.run()
                CredentialStore.clearSession()
                exit(passed ? 0 : 1)
            }
            NSApp.run()
            return
        }
        if CommandLine.arguments.contains("--check-settings-migration") {
            let legacy = #"{"backend":"openRouter","openRouter":{"baseURL":"https://openrouter.ai/api/v1","model":"existing-model"},"liteLLM":{"baseURL":"https://gateway.example/v1","model":"deployment"},"preferences":"Keep paragraphs","allowedApps":["com.tinyspeck.slackmacgap"],"nearSelection":true}"#
            do {
                let saved = try JSONDecoder().decode(AppSettings.Saved.self, from: Data(legacy.utf8))
                precondition(saved.openAI == nil && saved.anthropic == nil && saved.openRouter.model == "existing-model")
                let settings = AppSettings(loadSaved: false)
                for kind in BackendKind.allCases {
                    settings.backend = kind
                    settings.provider.model = kind.rawValue + "-model"
                }
                for kind in BackendKind.allCases {
                    settings.backend = kind
                    precondition(settings.provider.model == kind.rawValue + "-model")
                }
                print("PASS: old two-provider settings decode intact; four provider configurations stay independent. No saved preferences changed.")
            } catch { fputs("FAIL: settings migration\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--check-widget-state") {
            _ = NSApplication.shared
            WidgetStateChecks.run()
            return
        }
        if CommandLine.arguments.contains("--render-widget-preview") {
            _ = NSApplication.shared
            do {
                try WidgetPreview.render(to: URL(fileURLWithPath: "docs/evidence/widget-preview.png"))
                print("Rendered local widget preview; no capture or inference.")
            } catch { fputs("Preview failed: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--check-keychain") {
            let endpoint = "https://keychain-check.invalid/" + UUID().uuidString
            do {
                defer { for kind in BackendKind.allCases { try? CredentialStore.delete(kind, endpoint) } }
                guard try !CredentialStore.contains(.liteLLM, endpoint) else { throw CredentialStore.StoreError.failure(-1) }
                try CredentialStore.write("  local-test-fixture\n", kind: .liteLLM, baseURL: endpoint)
                guard try CredentialStore.contains(.liteLLM, endpoint) else { throw CredentialStore.StoreError.failure(-1) }
                let before = CredentialStore.keychainReadCount
                for _ in 0..<100 {
                    guard try CredentialStore.read(.liteLLM, endpoint) == "local-test-fixture" else { throw CredentialStore.StoreError.failure(-1) }
                }
                guard CredentialStore.keychainReadCount == before else { throw CredentialStore.StoreError.failure(-1) }
                CredentialStore.clearSession()
                guard try CredentialStore.read(.liteLLM, endpoint) == "local-test-fixture" else { throw CredentialStore.StoreError.failure(-1) }
                guard CredentialStore.keychainReadCount == before + 1 else { throw CredentialStore.StoreError.failure(-1) }
                guard try CredentialStore.read(.liteLLM, endpoint) == "local-test-fixture" else { throw CredentialStore.StoreError.failure(-1) }
                guard CredentialStore.keychainReadCount == before + 1 else { throw CredentialStore.StoreError.failure(-1) }
                guard try CredentialStore.read(.liteLLM, endpoint) == "local-test-fixture" else { throw CredentialStore.StoreError.failure(-1) }
                guard try !CredentialStore.contains(.openRouter, endpoint) else { throw CredentialStore.StoreError.failure(-1) }
                guard try !CredentialStore.contains(.liteLLM, endpoint + "/changed") else { throw CredentialStore.StoreError.failure(-1) }
                guard try CredentialStore.read(.openRouter, endpoint).isEmpty else { throw CredentialStore.StoreError.failure(-1) }
                guard try CredentialStore.read(.liteLLM, endpoint + "/changed").isEmpty else { throw CredentialStore.StoreError.failure(-1) }
                for kind in [BackendKind.openAI, .anthropic] {
                    try CredentialStore.write("fixture-" + kind.rawValue, kind: kind, baseURL: endpoint)
                }
                CredentialStore.clearSession()
                for kind in [BackendKind.openAI, .anthropic] {
                    guard try CredentialStore.read(kind, endpoint) == "fixture-" + kind.rawValue else { throw CredentialStore.StoreError.failure(-1) }
                }
                for invalidKey in [" \n ", "part\none", "part\rsecond"] {
                    do {
                        try CredentialStore.write(invalidKey, kind: .liteLLM, baseURL: endpoint)
                        throw CredentialStore.StoreError.failure(-1)
                    } catch CredentialStore.StoreError.invalidKey { }
                }
                guard try CredentialStore.read(.liteLLM, endpoint) == "local-test-fixture" else { throw CredentialStore.StoreError.failure(-1) }
                try CredentialStore.delete(.liteLLM, endpoint)
                guard try CredentialStore.read(.liteLLM, endpoint).isEmpty else { throw CredentialStore.StoreError.failure(-1) }
                guard try !CredentialStore.contains(.liteLLM, endpoint) else { throw CredentialStore.StoreError.failure(-1) }
                print("PASS: 100 cached key reads require zero Keychain reads; session reset reads once then caches. Presence, trimming, provider/URL isolation, invalid-key rejection, and deletion passed; temporary fixture removed.")
            } catch { fputs("FAIL: Keychain check: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            print(AccessibilityBridge.diagnostics())
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.applicationIconImage = Bundle.main.url(forResource: "Nib", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) ?? MascotAsset.image
        if CommandLine.arguments.contains("--settings-preview") {
            let delegate = SettingsPreviewDelegate(); app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if CommandLine.arguments.contains("--writing-preview") {
            let delegate = WritingPreviewDelegate(); app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if CommandLine.arguments.contains("--widget-demo") {
            let delegate = WidgetDemoDelegate(); app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
