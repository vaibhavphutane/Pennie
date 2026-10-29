import AppKit
import CryptoKit
import Security
import SwiftUI
import PennieCore

struct ProviderSettings: Codable {
    var baseURL: String
    var model: String = ""
}

final class AppSettings: ObservableObject {
    @Published var backend: BackendKind = .openRouter
    @Published var openRouter = ProviderSettings(baseURL: "https://openrouter.ai/api/v1")
    @Published var liteLLM = ProviderSettings(baseURL: "")
    @Published var openAI = ProviderSettings(baseURL: BackendKind.openAI.defaultBaseURL)
    @Published var anthropic = ProviderSettings(baseURL: BackendKind.anthropic.defaultBaseURL)
    @Published var writingProfile = WritingProfile()
    @Published var preferences = "Use American English. Preserve meaning, names, facts, and paragraph breaks."
    @Published var allowedApps: Set<String> = ["com.microsoft.Outlook", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap"]
    @Published var nearSelection = true
    @Published var widgetEnabled = true
    @Published var animateMascot = true
    @Published var pausedWidgetApps: Set<String> = []
    @Published var widgetStatus = "Switch to Slack, Teams, or Outlook to show Pennie."
    static let apps = [("Microsoft Outlook", "com.microsoft.Outlook"), ("Microsoft Teams", "com.microsoft.teams2"), ("Microsoft Teams classic", "com.microsoft.teams"), ("Slack", "com.tinyspeck.slackmacgap"), ("TextEdit (for testing)", "com.apple.TextEdit")]
    struct Saved: Codable {
        var backend: BackendKind
        var openRouter: ProviderSettings
        var liteLLM: ProviderSettings
        var openAI: ProviderSettings?
        var anthropic: ProviderSettings?
        var writingProfile: WritingProfile?
        var preferences: String
        var allowedApps: Set<String>
        var nearSelection: Bool
    }
    init(loadSaved: Bool = true) {
        guard loadSaved else { return }
        pausedWidgetApps = Set(UserDefaults.standard.stringArray(forKey: "pausedWidgetApps") ?? [])
        if UserDefaults.standard.object(forKey: "widgetEnabled") != nil {
            widgetEnabled = UserDefaults.standard.bool(forKey: "widgetEnabled")
        }
        if UserDefaults.standard.object(forKey: "animateMascot") != nil {
            animateMascot = UserDefaults.standard.bool(forKey: "animateMascot")
        }
        if let data = UserDefaults.standard.data(forKey: "settings"), let s = try? JSONDecoder().decode(Saved.self, from: data) {
            writingProfile = s.writingProfile ?? WritingProfile()
            backend = s.backend; openRouter = s.openRouter; liteLLM = s.liteLLM; preferences = s.preferences
            openAI = s.openAI ?? ProviderSettings(baseURL: BackendKind.openAI.defaultBaseURL)
            anthropic = s.anthropic ?? ProviderSettings(baseURL: BackendKind.anthropic.defaultBaseURL)
            allowedApps = s.allowedApps; nearSelection = s.nearSelection
        }
    }
    var provider: ProviderSettings {
        get {
            switch backend {
            case .openRouter: return openRouter
            case .liteLLM: return liteLLM
            case .openAI: return openAI
            case .anthropic: return anthropic
            }
        }
        set {
            switch backend {
            case .openRouter: openRouter = newValue
            case .liteLLM: liteLLM = newValue
            case .openAI: openAI = newValue
            case .anthropic: anthropic = newValue
            }
        }
    }
    var config: BackendConfig { BackendConfig(kind: backend, baseURL: provider.baseURL, model: provider.model) }
    func save() {
        UserDefaults.standard.set(Array(pausedWidgetApps).sorted(), forKey: "pausedWidgetApps")
        UserDefaults.standard.set(widgetEnabled, forKey: "widgetEnabled")
        UserDefaults.standard.set(animateMascot, forKey: "animateMascot")
        let value = Saved(backend: backend, openRouter: openRouter, liteLLM: liteLLM, openAI: openAI, anthropic: anthropic, writingProfile: writingProfile, preferences: preferences, allowedApps: allowedApps, nearSelection: nearSelection)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "settings") }
    }
}

@MainActor
enum CredentialStore {
    private static var sessionKeys: [String: String] = [:]
    private(set) static var keychainReadCount = 0
    static func clearSession() { sessionKeys.removeAll() }
    // Bind each credential to its backend AND exact endpoint. Editing the URL never sends an old key to a new host.
    static func account(_ kind: BackendKind, _ baseURL: String) -> String {
        let digest = SHA256.hash(data: Data(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return kind.rawValue + ":" + digest.map { String(format: "%02x", $0) }.joined()
    }
    static func query(_ kind: BackendKind, _ baseURL: String) -> [String: Any] {
        // Keep the original service so the Pennie rename can reuse saved credentials.
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.WriteDock.backend", kSecAttrAccount as String: account(kind, baseURL)]
    }
    static func read(_ kind: BackendKind, _ baseURL: String) throws -> String {
        if let key = sessionKeys[account(kind, baseURL)] { return key }
        return try copyKey(kind, baseURL, allowAuthentication: false)
    }
    /// Only this explicit Settings action can ask macOS to authorize reading a saved key.
    static func unlock(_ kind: BackendKind, _ baseURL: String) throws {
        _ = try copyKey(kind, baseURL, allowAuthentication: true)
    }
    private static func copyKey(_ kind: BackendKind, _ baseURL: String, allowAuthentication: Bool) throws -> String {
        var q = query(kind, baseURL); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        // Legacy login-Keychain ACLs still need the explicit no-UI policy.
        // Authorization is allowed only for the user-invoked Unlock saved key action.
        if !allowAuthentication { q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        keychainReadCount += 1
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) { throw StoreError.authorizationRequired }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw StoreError.failure(status) }
        if !key.isEmpty { sessionKeys[account(kind, baseURL)] = key }
        return key
    }
    /// Query item existence without retrieving a stored secret into the Settings view.
    static func contains(_ kind: BackendKind, _ baseURL: String) throws -> Bool {
        if sessionKeys[account(kind, baseURL)] != nil { return true }
        var q = query(kind, baseURL)
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) { throw StoreError.authorizationRequired }
        guard status == errSecSuccess else { throw StoreError.failure(status) }
        return true
    }
    static func write(_ key: String, kind: BackendKind, baseURL: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw StoreError.invalidKey
        }
        let q = query(kind, baseURL)
        let changes = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(q as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = q; item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.failure(status) }
        sessionKeys[account(kind, baseURL)] = key
    }
    static func delete(_ kind: BackendKind, _ baseURL: String) throws {
        sessionKeys.removeValue(forKey: account(kind, baseURL))
        let status = SecItemDelete(query(kind, baseURL) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.failure(status) }
    }
    enum StoreError: LocalizedError {
        case failure(OSStatus)
        case invalidKey, authorizationRequired
        var errorDescription: String? {
            switch self {
            case .authorizationRequired: return "Keychain access needs approval. In Settings, click Unlock saved key once, or paste and save your API key again. No password dialog will open automatically."
            case .failure: return "Keychain could not complete the operation. Unlock your login keychain and try again."
            case .invalidKey: return "Paste a nonempty API key without line breaks inside it."
            }
        }
    }
}

private struct SettingsInput: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).padding(10)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.45)))
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var previewOnly = false
    @State private var key = ""
    @State private var keySaved: Bool?
    @State private var notice = ""
    @State private var noticeIsError = false
    @State private var accessibilityTrusted = AccessibilityBridge.isTrusted
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var testID = UUID()
    @FocusState private var keyFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    PennieMascot(size: 48, animated: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pennie Settings").font(.title2.bold())
                        Text(ProductIdentity.tagline).foregroundStyle(.secondary)
                    }
                }
                Text(ProductIdentity.story).font(.callout).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Active backend", selection: $settings.backend) {
                            ForEach(BackendKind.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.menu)
                        inputLabel("API base URL")
                        TextField("https://your-gateway/v1", text: Binding(get: { settings.provider.baseURL }, set: {
                            settings.provider.baseURL = $0
                        })).accessibilityLabel("API base URL").modifier(SettingsInput())
                        inputLabel("Model ID")
                        TextField("Enter the exact model ID or deployment alias", text: Binding(get: { settings.provider.model }, set: {
                            settings.provider.model = $0
                        })).accessibilityLabel("Model ID").modifier(SettingsInput())
                        Text("Use your backend's model ID. Enter the API prefix, without /chat/completions, /responses, or /messages.").font(.caption).foregroundStyle(.secondary)
                        inputLabel("API key")
                        HStack(spacing: 10) {
                            SecureField("Paste your API key here", text: $key)
                                .accessibilityLabel("New API key").focused($keyFocused).modifier(SettingsInput())
                            Button("Paste key") {
                                key = NSPasteboard.general.string(forType: .string) ?? ""
                                keyFocused = true
                                notice = key.isEmpty ? "Copy your API key first, then click Paste key." : "Key pasted. Click Save settings & key to store it."
                                noticeIsError = key.isEmpty
                            }.disabled(previewOnly)
                        }
                        Label(keySaved == true ? "API key saved in Keychain for this backend and URL" : keySaved == false ? "No API key saved for this backend and URL" : "Keychain status unavailable",
                              systemImage: keySaved == true ? "checkmark.shield.fill" : "key")
                            .font(.caption).foregroundStyle(keySaved == true ? Color.green : Color.secondary)
                        Text("The key field clears after saving. Leave it blank to keep a saved key. Keys are never shown here.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Save settings & key", action: saveConnection).buttonStyle(.borderedProminent)
                            Button("Unlock saved key") {
                                do {
                                    try CredentialStore.unlock(settings.backend, settings.provider.baseURL)
                                    refreshKeyStatus(); notice = "Saved key unlocked for this session. You can request corrections without repeated Keychain prompts."; noticeIsError = false
                                } catch { notice = error.localizedDescription; noticeIsError = true }
                            }.disabled(keySaved == false)
                            Button("Remove saved key") {
                                do {
                                    try CredentialStore.delete(settings.backend, settings.provider.baseURL)
                                    keySaved = false; key = ""; notice = "Key removed for this backend and URL."; noticeIsError = false
                                } catch { notice = error.localizedDescription; noticeIsError = true }
                            }.disabled(keySaved != true)
                        }.disabled(previewOnly)
                        if !notice.isEmpty {
                            Text(notice).font(.callout).foregroundStyle(noticeIsError ? Color.red : Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Saved keys are reused in memory for this session. If macOS needs approval, use Unlock saved key; corrections never open a Keychain password dialog automatically. Use the sample test below to check inference.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        HStack {
                            Button(testing ? "Testing…" : "Test correction with sample text", action: testConnection)
                                .disabled(testing || previewOnly)
                            if testing { Button("Cancel test") { cancelTest() } }
                        }
                        Text("Sends only: “\(BackendDiagnostics.sample)” to the selected model. Uses your account's inference quota. No draft text or personal preferences are included.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Pennie beside your words") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(accessibilityTrusted ? "Accessibility access is enabled" : "Accessibility access is needed to capture text",
                              systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
                        HStack {
                            Button("Enable Accessibility…") { AccessibilityBridge.requestPermission() }
                            Button("Check again") { accessibilityTrusted = AccessibilityBridge.isTrusted }
                        }.disabled(previewOnly)
                        Toggle("Show Pennie beside supported editors", isOn: $settings.widgetEnabled)
                        Toggle("Animate Pennie", isOn: $settings.animateMascot)
                        if !settings.pausedWidgetApps.isEmpty {
                            Button("Resume Pennie in paused apps (\(settings.pausedWidgetApps.count))") {
                                settings.pausedWidgetApps.removeAll(); persist()
                            }
                        }
                        Text("Pennie follows a detected editor. If the editor cannot be detected, look in the lower-right corner of the display. Click Pennie for capture guidance or open the editor to paste text. An API key is not needed to show Pennie.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(settings.widgetStatus).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Capture from these applications") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AppSettings.apps, id: \.1) { name, id in
                            Toggle(name, isOn: Binding(get: { settings.allowedApps.contains(id) }, set: { enabled in
                                if enabled { settings.allowedApps.insert(id) } else { settings.allowedApps.remove(id) }; persist()
                            }))
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Writing goals & personal dictionary") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("English dialect", selection: $settings.writingProfile.dialect) {
                            ForEach(WritingProfile.Dialect.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Audience", selection: $settings.writingProfile.audience) {
                            ForEach(WritingProfile.Audience.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Default formality", selection: $settings.writingProfile.formality) {
                            ForEach(WritingProfile.Formality.allCases) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Names and spellings to keep (up to 2,000 characters)", text: $settings.writingProfile.dictionary, axis: .vertical)
                            .lineLimit(2...4).modifier(SettingsInput()).accessibilityLabel("Personal dictionary")
                        Text("Goals and dictionary entries are sent with each request. The selected writing action takes priority over conflicting defaults. Dictionary guidance depends on your model.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                VStack(alignment: .leading, spacing: 8) {
                    inputLabel("Writing preferences")
                    TextField("Describe your writing preferences", text: $settings.preferences, axis: .vertical)
                        .lineLimit(3...6).modifier(SettingsInput())
                }
                Toggle("Place the full editor near the selection when possible", isOn: $settings.nearSelection)
                Text("Click a text box, then click Pennie or press ⌘⇧G to load its draft. Select a passage first to edit only that part. Accept updates the original text box. Review your words and choose the action button, such as Fix grammar, to send a request. Your model receives the preview text, action, custom request or target language, goals, dictionary, and preferences. Remote endpoints require HTTPS; localhost may use HTTP.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 540)
        .onAppear { refreshKeyStatus(); accessibilityTrusted = AccessibilityBridge.isTrusted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AccessibilityBridge.isTrusted
        }
        .onChange(of: settings.backend) { _ in cancelTest(); key = ""; notice = ""; refreshKeyStatus(); persist() }
        .onChange(of: settings.provider.baseURL) { _ in cancelTest(); key = ""; notice = ""; refreshKeyStatus() }
        .onChange(of: settings.provider.model) { _ in cancelTest(); notice = "" }
        .onChange(of: settings.writingProfile) { _ in persist() }
        .onChange(of: settings.widgetEnabled) { _ in persist() }
        .onChange(of: settings.animateMascot) { _ in persist() }
        .onDisappear { cancelTest(); persist(); key = "" }
    }
    private func cancelTest() {
        testTask?.cancel(); testTask = nil; testing = false; testID = UUID()
    }
    private func testConnection() {
        guard !previewOnly, !testing else { return }
        guard key.isEmpty else { notice = "Save the new key before testing."; noticeIsError = true; return }
        cancelTest(); testing = true; noticeIsError = false; notice = "Testing a grammar correction using the sample shown below…"
        let config = settings.config, id = testID
        testTask = Task { @MainActor in
            do {
                let output = try await BackendDiagnostics.sampleResult(config: config)
                guard !Task.isCancelled, id == testID else { return }
                if SuggestionOutcome.classify(source: BackendDiagnostics.sample, result: output, action: .grammar) == .unchanged {
                    notice = "Connected, but the model echoed the incorrect sample. Try another model or check the gateway's routing."; noticeIsError = true
                } else {
                    notice = "Connected. Sample result: \(output)"; noticeIsError = false
                }
            } catch {
                guard !Task.isCancelled, id == testID else { return }
                notice = error.localizedDescription; noticeIsError = true
            }
            if id == testID { testing = false; testTask = nil }
        }
    }
    private func inputLabel(_ text: String) -> some View { Text(text).font(.headline) }
    private func persist() { if !previewOnly { settings.save() } }
    private func refreshKeyStatus() {
        guard !previewOnly else { keySaved = false; return }
        do { keySaved = try CredentialStore.contains(settings.backend, settings.provider.baseURL) }
        catch { keySaved = nil; notice = error.localizedDescription; noticeIsError = true }
    }
    private func saveConnection() {
        do {
            _ = try settings.config.completionsURL()
            let wroteKey = !key.isEmpty
            if wroteKey {
                try CredentialStore.write(key, kind: settings.backend, baseURL: settings.provider.baseURL)
                key = ""
            }
            keySaved = try CredentialStore.contains(settings.backend, settings.provider.baseURL)
            persist(); noticeIsError = false
            var message = wroteKey ? "API key saved securely. The key field has been cleared." : "Settings saved."
            if keySaved != true { message += " No API key is saved yet; paste it above and save." }
            if settings.provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message += " Enter a Model ID to finish setup."
            } else if keySaved == true { message += " Ready to request a correction." }
            notice = message
        } catch { notice = error.localizedDescription; noticeIsError = true }
    }
}

/// Editable UI fixture with ephemeral settings; never reads or writes provider credentials.
@MainActor
final class SettingsPreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings(loadSaved: false)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window?.title = "Pennie Settings Preview"
        window?.contentView = NSHostingView(rootView: SettingsView(settings: settings, previewOnly: true))
        window?.center(); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
