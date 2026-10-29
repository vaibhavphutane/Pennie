#if WIDGET_CHECKS
import Foundation
import CoreGraphics

@main
struct WidgetPlacementChecks {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label); count += 1
        }
        let main = CGRect(x: 0, y: 24, width: 1440, height: 850)
        let left = CGRect(x: -1600, y: -200, width: 1600, height: 1000)
        let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let ax = CGRect(x: -1200, y: 300, width: 600, height: 140)
        let cocoa = FloatingPlacement.cocoaRect(fromAX: ax, primaryTop: 900)
        check(cocoa == CGRect(x: -1200, y: 460, width: 600, height: 140), "AX-to-AppKit conversion preserves a negative-X display")
        check(FloatingPlacement.visibleScreen(for: cocoa, screens: [main, left]) == left, "left display selected")
        let top = FloatingPlacement.cocoaRect(fromAX: CGRect(x: 40, y: -600, width: 300, height: 100), primaryTop: 900)
        check(FloatingPlacement.visibleScreen(for: top, screens: [main, above]) == above, "display above primary selected")
        let straddle = CGRect(x: -100, y: 400, width: 500, height: 100)
        check(FloatingPlacement.visibleScreen(for: straddle, screens: [left, main]) == main, "largest field intersection wins")
        check(FloatingPlacement.visibleScreen(for: CGRect(x: 4000, y: 4000, width: 20, height: 20), screens: [main]) == nil, "offscreen field hidden")
        check(FloatingPlacement.visibleScreen(for: .null, screens: [main]) == nil, "invalid AX frame hidden")
        check(FloatingPlacement.widgetFrame(editor: .infinite, screen: main) == nil, "infinite field rejected")
        check(FloatingPlacement.widgetFrame(editor: CGRect(x: 0, y: 0, width: 10, height: 10), screen: main) == nil, "field outside visible screen rejected")
        let editor = CGRect(x: 500, y: 300, width: 400, height: 150)
        let right = FloatingPlacement.widgetFrame(editor: editor, screen: main)!
        check(right.minX > editor.maxX, "prefer outside-right placement")
        let atRightEdge = CGRect(x: 1100, y: 300, width: 340, height: 150)
        check(FloatingPlacement.widgetFrame(editor: atRightEdge, screen: main)!.maxX < atRightEdge.minX, "flip outside-left at right edge")
        for screen in [main, left, above, CGRect(x: -30, y: -20, width: 72, height: 80)] {
            let docked = FloatingPlacement.dockedWidgetFrame(screen: screen)!
            check(screen.contains(docked), "docked fallback remains entirely on screen")
            check(docked.size == CGSize(width: 72, height: 80), "docked launcher retains its clickable size")
        }
        check(FloatingPlacement.dockedWidgetFrame(screen: .null) == nil, "docked fallback rejects null display")
        check(FloatingPlacement.dockedWidgetFrame(screen: CGRect(x: 0, y: 0, width: 71, height: 80)) == nil, "docked fallback rejects display narrower than launcher")
        for screen in [main, left, above, CGRect(x: 0, y: 0, width: 320, height: 480)] {
            for field in [screen, CGRect(x: screen.minX + 4, y: screen.maxY - 10, width: 200, height: 100), CGRect(x: screen.maxX - 200, y: screen.minY - 80, width: 300, height: 150)] {
                let widget = FloatingPlacement.widgetFrame(editor: field, screen: screen)!
                check(screen.contains(widget), "widget stays within visible screen")
                let card = FloatingPlacement.cardFrame(widget: widget, screen: screen, size: CGSize(width: 368, height: 610))
                check(screen.contains(card), "card stays within visible screen including small display")
            }
        }
        print("PASS: \(count) widget placement checks (multiple displays, clipping, edge flipping, invalid/offscreen frames).")
    }
}
#endif
