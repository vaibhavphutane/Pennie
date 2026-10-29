#if LOOPBACK_CHECKS
import Foundation

/// Actual URLSession transport checks, using only a caller-started loopback fixture.
@main
struct LoopbackChecks {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: " + name) }
        checks += 1
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 2, let port = Int(CommandLine.arguments[1]), (1...65535).contains(port) else {
            fatalError("Usage: pennie-loopback-checks <loopback-port>")
        }
        let root = "http://127.0.0.1:\(port)"
        let client = InferenceClient()
        // Each fixture output depends on the requested action; the server validates the exact
        // model ID and provider-specific headers before responding. No credentials are persisted.
        let actions: [(WritingAction, String, String)] = [
            (.grammar, "This are a example. I has recieved teh message. 👩🏽‍💻\n\nCafé.", "This is an example. I have received the message. 👩🏽‍💻\n\nCafé."),
            (.clarity, "We waited due to the fact that it rained.", "We waited because it rained."),
            (.brevity, "We work at this point in time in order to finish.", "We work now to finish."),
            (.professional, "Hey team, please respond ASAP.", "Hello team, please respond as soon as possible."),
            (.conversational, "Dear team, I would like to meet.", "Hi team, I'd like to meet.")
        ]
        for kind in BackendKind.allCases {
            let route = kind.rawValue
            let config = BackendConfig(kind: kind, baseURL: root + "/\(route)/v1", model: "mock-editor")
            for (action, text, expected) in actions {
                let result = try await client.rewrite(text: text, action: action, preferences: "Preserve paragraphs.", config: config, apiKey: "local-test")
                check(result == expected, "\(kind.rawValue) / \(action.rawValue) exact text response")
            }
            let failures: [(String, InferenceError)] = [
                ("auth", .authentication), ("rate", .rateLimited(retryAfterSeconds: 5)),
                ("model", .modelUnavailable), ("server", .serviceUnavailable),
                ("malformed", .invalidResponse), ("truncated", .truncatedResponse),
                ("redirect", .redirectRefused), ("refusal", .contentRefused), ("tools", .invalidResponse), ("empty", .invalidResponse)
            ]
            for (path, expected) in failures {
                let errorConfig = BackendConfig(kind: kind, baseURL: root + "/\(path)/v1", model: "mock-editor")
                do {
                    _ = try await client.rewrite(text: "Helo", action: .grammar, config: errorConfig, apiKey: "local-test")
                    fatalError("Expected \(path) fixture failure")
                } catch {
                    check(error as? InferenceError == expected, "\(kind.rawValue) / \(path) HTTP error mapping")
                }
            }
            var wrongModel = config
            wrongModel.model = "wrong-alias"
            do {
                _ = try await client.rewrite(text: "Helo", action: .grammar, config: wrongModel, apiKey: "local-test")
                fatalError("Expected wrong model to fail")
            } catch { check(error as? InferenceError == .modelUnavailable, "exact model ID delivered to server") }
            do {
                _ = try await client.rewrite(text: "Helo", action: .grammar, config: config, apiKey: "incorrect-test-key")
                fatalError("Expected wrong key to fail")
            } catch { check(error as? InferenceError == .authentication, "authorization header delivered to server") }
        }
        print("PASS: \(checks) real URLSession loopback checks; four backends, five actions, exact model and auth headers, HTTP 401/429/404/503, malformed/truncated responses, redirect refusal. No external inference requests.")
    }
}
#endif
