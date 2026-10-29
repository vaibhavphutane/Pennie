import AppKit

// Package the existing Nib artwork into standard macOS icon sizes.
guard CommandLine.arguments.count == 3,
      let nib = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: swift scripts/make-app-icon.swift <Nib.png> <output.iconset>")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let edge = CGFloat(pixels)
        NSColor(calibratedRed: 0.89, green: 0.97, blue: 0.93, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: edge * 0.04, y: edge * 0.04, width: edge * 0.92, height: edge * 0.92),
            xRadius: edge * 0.20, yRadius: edge * 0.20).fill()
        nib.draw(in: CGRect(x: edge * 0.04, y: edge * 0.04, width: edge * 0.92, height: edge * 0.92))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
