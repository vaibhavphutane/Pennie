import Foundation
import CoreGraphics

/// Pure placement logic shared by the overlay and tests. All outputs are AppKit coordinates.
public enum FloatingPlacement {
    /// Visible launcher when an app does not expose usable editor geometry.
    public static func dockedWidgetFrame(screen: CGRect) -> CGRect? {
        guard valid(screen), screen.width >= 72, screen.height >= 80 else { return nil }
        return clamp(CGRect(x: screen.maxX - 92, y: screen.minY + 20, width: 72, height: 80), to: screen)
    }
    public static func cocoaRect(fromAX rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func visibleScreen(for rect: CGRect, screens: [CGRect]) -> CGRect? {
        guard valid(rect) else { return nil }
        return screens.filter { valid($0) && $0.intersects(rect) }.max {
            area($0.intersection(rect)) < area($1.intersection(rect))
        }
    }

    public static func widgetFrame(editor: CGRect, screen: CGRect) -> CGRect? {
        guard valid(editor), valid(screen), editor.intersects(screen), screen.width >= 72, screen.height >= 80 else { return nil }
        let field = editor.intersection(screen)
        let size = CGSize(width: 72, height: 80)
        let x: CGFloat
        if field.maxX + 6 + size.width <= screen.maxX { x = field.maxX + 6 }
        else if field.minX - size.width - 6 >= screen.minX { x = field.minX - size.width - 6 }
        else { x = field.maxX - size.width - 6 }
        return clamp(CGRect(origin: CGPoint(x: x, y: field.minY + 2), size: size), to: screen)
    }

    public static func cardFrame(widget: CGRect, screen: CGRect, size: CGSize) -> CGRect {
        let x = widget.minX - size.width - 10 >= screen.minX ? widget.minX - size.width - 10 : widget.maxX + 10
        return clamp(CGRect(origin: CGPoint(x: x, y: widget.maxY - size.height), size: size), to: screen)
    }

    private static func clamp(_ rect: CGRect, to screen: CGRect) -> CGRect {
        let width = min(rect.width, screen.width), height = min(rect.height, screen.height)
        return CGRect(x: max(screen.minX, min(rect.minX, screen.maxX - width)),
                      y: max(screen.minY, min(rect.minY, screen.maxY - height)), width: width, height: height)
    }
    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isEmpty && !rect.isNull && !rect.isInfinite && rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}
