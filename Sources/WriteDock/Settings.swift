import AppKit
import CryptoKit
import Security
import SwiftUI
import WriteDockCore

struct ProviderSettings: Codable {
    var baseURL: String
    var model: String = ""
}

final class AppSettings: ObservableObject {
    @Published var backend: BackendKind = .openRouter
    @Published var openRouter = ProviderSettings(baseURL: "https://openrouter.ai/api/v1")
    @Published var liteLLM = ProviderSettings(baseURL: "")
    @Published var preferences = "Use American English. Preserve meaning, names, facts, and paragraph breaks."
    @Published var allowedApps: Set<String> = ["com.microsoft.Outlook", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap"]
    @Published var nearSelection = true
    static let apps = [("Microsoft Outlook", "com.microsoft.Outlook"), ("Microsoft Teams", "com.microsoft.teams2"), ("Microsoft Teams classic", "com.microsoft.teams"), ("Slack", "com.tinyspeck.slackmacgap"), ("TextEdit (for testing)", "com.apple.TextEdit")]
    struct Saved: Codable {
        var backend: BackendKind
        var openRouter: ProviderSettings
        var liteLLM: ProviderSettings
        var preferences: String
        var allowedApps: Set<String>
        var nearSelection: Bool
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"), let s = try? JSONDecoder().decode(Saved.self, from: data) {
            backend = s.backend; openRouter = s.openRouter; liteLLM = s.liteLLM; preferences = s.preferences
            allowedApps = s.allowedApps; nearSelection = s.nearSelection
        }
    }
    var provider: ProviderSettings { backend == .openRouter ? openRouter : liteLLM }
    var config: BackendConfig { BackendConfig(kind: backend, baseURL: provider.baseURL, model: provider.model) }
    func save() {
        let value = Saved(backend: backend, openRouter: openRouter, liteLLM: liteLLM, preferences: preferences, allowedApps: allowedApps, nearSelection: nearSelection)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "settings") }
    }
}

enum CredentialStore {
    // Bind each credential to its backend AND exact endpoint. Editing the URL never sends an old key to a new host.
    static func account(_ kind: BackendKind, _ baseURL: String) -> String {
        let digest = SHA256.hash(data: Data(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return kind.rawValue + ":" + digest.map { String(format: "%02x", $0) }.joined()
    }
    static func query(_ kind: BackendKind, _ baseURL: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.WriteDock.backend", kSecAttrAccount as String: account(kind, baseURL)]
    }
    static func read(_ kind: BackendKind, _ baseURL: String) throws -> String {
        var q = query(kind, baseURL); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw StoreError.failure(status) }
        return key
    }
    static func write(_ key: String, kind: BackendKind, baseURL: String) throws {
        let q = query(kind, baseURL)
        let changes = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(q as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = q; item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.failure(status) }
    }
    static func delete(_ kind: BackendKind, _ baseURL: String) throws {
        let status = SecItemDelete(query(kind, baseURL) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.failure(status) }
    }
    enum StoreError: LocalizedError {
        case failure(OSStatus)
        var errorDescription: String? { "Keychain could not complete the operation. Unlock your login keychain and try again." }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var key = ""
    @State private var notice = "Keys are stored in macOS Keychain, separately for each backend and URL."
    var body: some View {
        Form {
            Picker("Active backend", selection: $settings.backend) {
                ForEach(BackendKind.allCases) { Text($0.label).tag($0) }
            }
            TextField("API base URL", text: Binding(get: { settings.provider.baseURL }, set: {
                if settings.backend == .openRouter { settings.openRouter.baseURL = $0 } else { settings.liteLLM.baseURL = $0 }
            }))
            TextField("Model ID", text: Binding(get: { settings.provider.model }, set: {
                if settings.backend == .openRouter { settings.openRouter.model = $0 } else { settings.liteLLM.model = $0 }
            }))
            Text("Use the exact OpenRouter model ID or LiteLLM deployment alias. The base URL must exclude /chat/completions.").font(.caption).foregroundStyle(.secondary)
            SecureField("New API key (leave blank to keep saved key)", text: $key)
            HStack {
                Button("Save settings & key") {
                    do {
                        _ = try settings.config.completionsURL()
                        if !key.isEmpty { try CredentialStore.write(key, kind: settings.backend, baseURL: settings.provider.baseURL); key = "" }
                        settings.save(); notice = "Saved. You can switch backends here without restarting."
                    } catch { notice = error.localizedDescription }
                }
                Button("Remove saved key") {
                    do { try CredentialStore.delete(settings.backend, settings.provider.baseURL); notice = "Key removed for this backend and URL." }
                    catch { notice = error.localizedDescription }
                }
            }
            Text(notice).font(.caption)
            TextField("Writing preferences", text: $settings.preferences, axis: .vertical).lineLimit(2...4)
            Section("Capture from these applications") {
                ForEach(AppSettings.apps, id: \.1) { name, id in
                    Toggle(name, isOn: Binding(get: { settings.allowedApps.contains(id) }, set: { enabled in
                        if enabled { settings.allowedApps.insert(id) } else { settings.allowedApps.remove(id) }; settings.save()
                    }))
                }
            }
            Toggle("Place preview near the selected text when bounds are available", isOn: $settings.nearSelection)
            Text("Select text, then press ⌘⇧G. Capture stays on this Mac until you press Send. No background typing collection or automatic submission.").font(.callout)
            Button("Enable Accessibility…") { AccessibilityBridge.requestPermission() }
            Text("HTTPS is required for remote endpoints. HTTP is permitted only on localhost for local gateways. Your endpoint receives the preview text, action, and writing preferences.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).padding().frame(width: 620, height: 700)
        .onChange(of: settings.backend) { _ in key = ""; settings.save() }
        .onChange(of: settings.provider.baseURL) { _ in key = "" }
        .onDisappear { settings.save(); key = "" }
    }
}
