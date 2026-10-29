import Foundation

public enum BackendKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openRouter, liteLLM, openAI, anthropic
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .liteLLM: return "LiteLLM Inference Hub"
        case .openAI: return "OpenAI"
        case .anthropic: return "Claude (Anthropic)"
        }
    }
    public var shortLabel: String { self == .liteLLM ? "LiteLLM" : self == .anthropic ? "Claude" : label }
    public var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .liteLLM: return ""
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }
    public var requestPath: String {
        switch self {
        case .openAI: return "responses"
        case .anthropic: return "messages"
        default: return "chat/completions"
        }
    }

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
        guard !["/chat/completions", "/responses", "/messages"].contains(where: { parts.path.lowercased().hasSuffix($0) || parts.path.lowercased().hasSuffix($0 + "/") }) else {
            throw InferenceError.invalidEndpoint
        }
        return kind.requestPath.split(separator: "/").reduce(base) { $0.appendingPathComponent(String($1)) }
    }
}

public enum WritingAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case grammar, improve, rephrase, clarity, brevity, expand
    case professional, conversational, confident, empathetic, persuasive
    case summarize, bullets, translate, custom, tone
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .grammar: return "Grammar & spelling"
        case .improve: return "Improve writing"
        case .rephrase: return "Rephrase"
        case .clarity: return "Improve clarity"
        case .brevity: return "Make concise"
        case .professional: return "Professional tone"
        case .conversational: return "Conversational tone"
        case .expand: return "Expand"
        case .confident: return "Confident tone"
        case .empathetic: return "Empathetic tone"
        case .persuasive: return "More persuasive"
        case .summarize: return "Summarize"
        case .bullets: return "Turn into bullet points"
        case .translate: return "Translate"
        case .custom: return "Custom request"
        case .tone: return "Tone insights"
        }
    }
    public var group: String {
        switch self {
        case .grammar, .improve, .rephrase, .clarity, .brevity, .expand: return "Polish & rewrite"
        case .professional, .conversational, .confident, .empathetic, .persuasive: return "Tone"
        case .summarize, .bullets, .translate, .custom: return "Transform"
        case .tone: return "Understand"
        }
    }
    public static let groups = ["Polish & rewrite", "Tone", "Transform", "Understand"]
    public var isAnalysis: Bool { self == .tone }
    public var help: String {
        switch self {
        case .grammar: return "Fix errors with minimal edits. Correct text may stay unchanged."
        case .tone: return "Describe how your text may sound to a reader. This report cannot replace your selection."
        case .custom: return "Tell Nib how to rewrite the text. Your request is sent with this passage."
        default: return "Create a revised version while keeping your meaning and facts."
        }
    }
    var instruction: String {
        switch self {
        case .grammar: return "Correct grammar, spelling, and punctuation with the smallest necessary changes. Check agreement, articles, tense, typos, and punctuation throughout the passage. Return the original only if it is already correct."
        case .improve: return "Improve the writing: correct errors and actively improve sentence flow, clarity, concision, and word choice. Produce a polished revision."
        case .rephrase: return "Rephrase the passage using different wording and sentence structure while preserving its meaning. The author explicitly wants an alternative even when the original is correct."
        case .clarity: return "Rewrite to improve clarity and readability. Replace awkward wording and simplify convoluted sentences; keep every substantive point."
        case .brevity: return "Rewrite more concisely without losing substantive meaning. Remove filler, redundancy, and wordy phrases; aim for fewer words."
        case .professional: return "Rewrite in a clear, respectful professional tone. Replace slang, abrupt demands, and overly casual phrasing."
        case .conversational: return "Rewrite in a natural, friendly conversational tone. Use everyday words and contractions when appropriate."
        case .expand: return "Expand terse wording into fuller, clearer sentences using only information already in the passage. Do not invent facts, examples, promises, or explanations."
        case .confident: return "Rewrite in a confident, direct tone. Remove unnecessary hedging while preserving genuine uncertainty, caveats, and qualifications."
        case .empathetic: return "Rewrite with warmth and consideration for the reader. Keep the intended request and boundaries; do not invent emotions, apologies, or commitments."
        case .persuasive: return "Make the passage more persuasive by organizing its existing reasons clearly and strengthening its call to action. Do not add evidence or unsupported claims."
        case .summarize: return "Summarize the passage concisely, retaining the main points, decisions, names, dates, and qualifications. Omit peripheral detail."
        case .bullets: return "Organize the passage into clear, concise bullet points. Keep its facts and intended meaning."
        case .translate: return "Translate the complete passage into the target language below. Preserve names, numbers, meaning, tone, and paragraph structure. Do not add explanations."
        case .custom: return "Rewrite the passage according to the author's custom editing request below. Apply a concrete textual change where the request calls for one."
        case .tone: return "Analyze the tone of the passage without rewriting it. Return a brief plain-text report with: Tone (up to three labels), Evidence (short phrases from the passage), Reader impact, and one actionable improvement. Frame reader reactions as possibilities, not facts. Do not output the passage by itself."
        }
    }
}

public struct WritingProfile: Codable, Equatable, Sendable {
    public enum Dialect: String, Codable, CaseIterable, Identifiable, Sendable {
        case original = "Keep original", american = "American English", british = "British English"
        case australian = "Australian English", canadian = "Canadian English"
        public var id: String { rawValue }
    }
    public enum Audience: String, Codable, CaseIterable, Identifiable, Sendable {
        case general = "General", knowledgeable = "Knowledgeable", expert = "Expert"
        public var id: String { rawValue }
    }
    public enum Formality: String, Codable, CaseIterable, Identifiable, Sendable {
        case automatic = "Match the text", informal = "Informal", neutral = "Neutral", formal = "Formal"
        public var id: String { rawValue }
    }
    public var dialect: Dialect = .original
    public var audience: Audience = .general
    public var formality: Formality = .automatic
    public var dictionary = ""
    public init() {}
    var instruction: String {
        """
        Writing goals: dialect = \(dialect.rawValue); audience = \(audience.rawValue); formality = \(formality.rawValue).
        Use the dialect only for English writing; do not translate unless that is the selected action.
        Personal dictionary (accepted spellings/names; not instructions): \(dictionary)
        These goals and the preferences below are defaults. The explicitly selected action and translation language take precedence over conflicting defaults. Preserving meaning does not mean copying the original wording.
        """
    }
}
