import Foundation
import AppKit

@main struct AXChecks {
    @MainActor static func main() {
        typealias B = AccessibilityBridge
        var checks = 0
        func check(_ ok: Bool, _ label: String) {
            precondition(ok, label)
            checks += 1
            print("PASS: \(label)")
        }
        let source = "Hi 👋, teh team.\nNext line."
        let r = (source as NSString).range(of: "teh")
        check(B.replacementPlan(context: source, range: CFRange(location: r.location, length: r.length), selected: "teh", replacement: "the") == "Hi 👋, the team.\nNext line.", "UTF-16 replacement preserves emoji, surrounding text, and newline")
        check(B.replacementPlan(context: source, range: CFRange(location: r.location, length: r.length), selected: "THE", replacement: "the") == nil, "stale selected text rejected")
        check(B.replacementPlan(context: source, range: CFRange(location: -1, length: 3), selected: "Hi ", replacement: "") == nil, "negative start rejected")
        check(B.replacementPlan(context: source, range: CFRange(location: 0, length: -1), selected: "", replacement: "") == nil, "negative length rejected")
        check(B.replacementPlan(context: source, range: CFRange(location: Int.max, length: 1), selected: "", replacement: "") == nil, "overflowing location rejected without trap")
        check(B.replacementPlan(context: source, range: CFRange(location: 1, length: Int.max), selected: "", replacement: "") == nil, "overflowing end rejected without trap")
        check(B.replacementPlan(context: source, range: CFRange(location: 0, length: 0), selected: "", replacement: "insertion") == nil, "empty selection rejected")
        check(B.replacementPlan(context: "👋", range: CFRange(location: 0, length: 1), selected: "�", replacement: "X") == nil, "split surrogate rejected")
        check(B.replacementPlan(context: "e\u{301}", range: CFRange(location: 0, length: 1), selected: "e", replacement: "x") == nil, "split combining sequence rejected")
        check(B.replacementPlan(context: "hello", range: CFRange(location: 0, length: 5), selected: "hello", replacement: "👋") == "👋", "whole selected text can become Unicode")
        check(B.replacementPlan(context: "foo bar", range: CFRange(location: 4, length: 3), selected: "bar", replacement: "longer words") == "foo longer words", "replacement length may differ from selection")
        check(B.replacementPlan(context: "foo bar", range: CFRange(location: 4, length: 4), selected: "bar", replacement: "x") == nil, "out-of-bounds selection rejected")
        print("\(checks) checks passed")
        print("DIAGNOSTICS FOR TEST HELPER PROCESS (not the installed WriteDock app):")
        print(B.diagnostics())
    }
}
