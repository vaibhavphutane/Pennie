import Foundation

public enum BackendKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openRouter, liteLLM
    public var id: String { rawValue }
    public var label: String { self == .openRouter ? "OpenRouter" : "LiteLLM Inference Hub" }
    public var defaultBaseURL: String { self == .openRouter ? "https://openrouter.ai/api/v1" : "" }
}

/// Non-secret settings only. Keys are deliberately not part of this Codable value.
public struct BackendConfig: Codable, Equatable, Sendable {
    public var kind: BackendKind
    public var baseURL: String
    public var model: String

    public init(kind: BackendKind, baseURL: String, model: String) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
    }

    /// The URL must be an API prefix, for example https://host/v1.
    public func completionsURL() throws -> URL {
        guard !baseURL.isEmpty,
              baseURL == baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: baseURL),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port!),
              let base = parts.url else { throw InferenceError.invalidEndpoint }
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard scheme == "https" || (scheme == "http" && loopback) else {
            throw InferenceError.invalidEndpoint
        }
        guard !parts.path.lowercased().contains("/chat/completions") else {
            throw InferenceError.invalidEndpoint
        }
        return base.appendingPathComponent("chat").appendingPathComponent("completions")
    }
}

public enum WritingAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case grammar, clarity, brevity, professional, conversational
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .grammar: return "Grammar & spelling"
        case .clarity: return "Improve clarity"
        case .brevity: return "Make concise"
        case .professional: return "Professional tone"
        case .conversational: return "Conversational tone"
        }
    }
    var instruction: String {
        switch self {
        case .grammar: return "Correct grammar, spelling, and punctuation with the smallest necessary changes."
        case .clarity: return "Rewrite to improve clarity and readability."
        case .brevity: return "Rewrite more concisely without losing substantive meaning."
        case .professional: return "Rewrite in a clear, respectful professional tone."
        case .conversational: return "Rewrite in a natural, friendly conversational tone."
        }
    }
}
