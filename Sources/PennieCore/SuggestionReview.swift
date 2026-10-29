import Foundation

public enum SuggestionOutcome: Equatable, Sendable {
    case changed, unchanged, analysis
    public static func classify(source: String, result: String, action: WritingAction) -> Self {
        if source.trimmingCharacters(in: .whitespacesAndNewlines) == result.trimmingCharacters(in: .whitespacesAndNewlines) { return .unchanged }
        return action.isAnalysis ? .analysis : .changed
    }
}

/// Review-only differences. The untouched provider output is used for replacement/copy.
public struct SuggestionDiff: Sendable {
    public struct Span: Equatable, Sendable {
        public enum Kind: Sendable { case unchanged, removed, added }
        public var text: String
        public let kind: Kind
    }
    public let spans: [Span]
    public init(source: String, result: String) {
        let before = Self.tokens(source), after = Self.tokens(result)
        var output: [Span] = []
        func append(_ text: String, _ kind: Span.Kind) {
            guard !text.isEmpty else { return }
            if output.last?.kind == kind { output[output.count - 1].text += text }
            else { output.append(Span(text: text, kind: kind)) }
        }
        // Bound work for large or punctuation-heavy passages. The coarser fallback remains exact.
        if before.count + after.count > 2_000 {
            var prefix = 0, suffix = 0
            while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
            while suffix < min(before.count, after.count) - prefix,
                  before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
            append(before.prefix(prefix).joined(), .unchanged)
            append(before[prefix..<(before.count - suffix)].joined(), .removed)
            append(after[prefix..<(after.count - suffix)].joined(), .added)
            append(before.suffix(suffix).joined(), .unchanged)
        } else {
            let changes = after.difference(from: before)
            var removals = Set<Int>(), insertions = Set<Int>()
            for change in changes {
                switch change {
                case .remove(let offset, _, _): removals.insert(offset)
                case .insert(let offset, _, _): insertions.insert(offset)
                }
            }
            var i = 0, j = 0
            while i < before.count || j < after.count {
                if removals.contains(i), i < before.count { append(before[i], .removed); i += 1 }
                else if insertions.contains(j), j < after.count { append(after[j], .added); j += 1 }
                else if i < before.count, j < after.count { append(after[j], .unchanged); i += 1; j += 1 }
                else { break }
            }
        }
        spans = output
    }
    private static func tokens(_ text: String) -> [String] {
        var tokens: [String] = [], current = "", lastKind = -1
        for character in text {
            let kind = character.isWhitespace ? 0 : character.isLetter || character.isNumber ? 1 : 2
            if kind != lastKind || kind == 2 {
                if !current.isEmpty { tokens.append(current) }; current = ""
            }
            current.append(character); lastKind = kind
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
