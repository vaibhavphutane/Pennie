import AppKit
import PennieCore

/// Explicit sample-only checks. Never captures a document, writes preferences, or prints keys.
@MainActor
enum BackendDiagnostics {
    static let sample = "This are a example. I has recieved teh message."
    static func sampleResult(config: BackendConfig) async throws -> String {
        let key = try CredentialStore.read(config.kind, config.baseURL)
        return try await InferenceClient().rewrite(text: sample, action: .grammar, config: config, apiKey: key)
    }
    static func run() async -> Bool {
        let settings = AppSettings(), config = settings.config
        let samples: [(WritingAction, String)] = [
            (.grammar, sample),
            (.improve, "Due to the fact that the review was done, we are now in a position to ship."),
            (.rephrase, "Please send the report tomorrow."),
            (.clarity, "The review of the plan by the team resulted in the approval of it."),
            (.brevity, "At this point in time, we are working together in order to finish the report."),
            (.expand, "Report ready. Review by Friday."),
            (.professional, "Hey, send me that report ASAP."),
            (.conversational, "I would like to inquire whether you are available for a brief discussion."),
            (.confident, "I think maybe we could perhaps schedule a review on Friday."),
            (.empathetic, "Your request is late. You will have to wait until Monday."),
            (.persuasive, "Please review the report today. Your review will help us meet Friday's deadline."),
            (.summarize, "The team reviewed the report on Monday. They found two errors. The errors were fixed on Tuesday. The final review is scheduled for Friday."),
            (.bullets, "The report is ready. The review is on Friday. The launch is on Monday."),
            (.translate, "The report is ready for review."),
            (.custom, "The report is ready."),
            (.tone, "Send the report now. This delay is unacceptable.")
        ]
        do {
            let key = try CredentialStore.read(config.kind, config.baseURL)
            print("Synthetic live checks: \(config.kind.label), model \(config.model). No captured text or writing preferences used.")
            var passed = 0
            for (action, text) in samples {
                let output = try await InferenceClient().rewrite(text: text, action: action, config: config, apiKey: key,
                    customInstruction: "Turn this statement into a question asking whether the report is ready.", targetLanguage: "French")
                let changed = SuggestionOutcome.classify(source: text, result: output, action: action) != .unchanged
                if changed { passed += 1 }
                print("\(changed ? "PASS" : "UNCHANGED") \(action.rawValue): \(output.replacingOccurrences(of: "\n", with: " | "))")
                fflush(stdout)
            }
            print("\(passed)/\(samples.count) actions produced distinct results. Distinct text alone is not a quality guarantee.")
            return passed == samples.count
        } catch {
            print("Live check incomplete: \(error.localizedDescription)")
            return false
        }
    }
}
