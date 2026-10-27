// Native 2x artwork for the Finder drag-to-install window. No external assets.
import AppKit

let width = 660.0, height = 440.0, scale = 2.0
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let forest = NSColor(srgbRed: 0.133, green: 0.239, blue: 0.169, alpha: 1)
let muted = NSColor(srgbRed: 0.34, green: 0.38, blue: 0.34, alpha: 1)
NSColor(srgbRed: 0.945, green: 0.957, blue: 0.925, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
// Deterministic grain stays below all lettering and native Finder icons.
var noise: UInt64 = 42
for _ in 0..<55000 {
    noise = noise &* 6364136223846793005 &+ 1
    let x = Double((noise >> 16) % 1320) / 2
    noise = noise &* 6364136223846793005 &+ 1
    let y = Double((noise >> 16) % 880) / 2
    forest.withAlphaComponent(0.035).setFill()
    NSBezierPath(rect: NSRect(x: x, y: y, width: 0.5, height: 0.5)).fill()
}
func text(_ value: String, x: Double, top: Double, size: Double, weight: NSFont.Weight = .regular, color: NSColor = forest) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let h = (value as NSString).size(withAttributes: attributes).height
    (value as NSString).draw(at: NSPoint(x: x, y: height - top - h), withAttributes: attributes)
}
text("Glance", x: 48, top: 42, size: 34, weight: .semibold)
text("Make room for what matters.", x: 48, top: 88, size: 15, color: muted)
text("Drag Glance to Applications", x: 48, top: 132, size: 17, weight: .medium)
// Arrow centered between the real draggable app and Applications link.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 288, y: height - 230))
arrow.line(to: NSPoint(x: 372, y: height - 230))
arrow.move(to: NSPoint(x: 358, y: height - 216))
arrow.line(to: NSPoint(x: 372, y: height - 230))
arrow.line(to: NSPoint(x: 358, y: height - 244))
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
forest.withAlphaComponent(0.65).setStroke()
arrow.stroke()
forest.withAlphaComponent(0.14).setFill()
NSBezierPath(rect: NSRect(x: 48, y: height - 330, width: 564, height: 1)).fill()
text("Once copied, open Glance from Applications.", x: 48, top: 351, size: 14, weight: .medium)
text("Then eject this disk. Your notch is ready.", x: 48, top: 377, size: 13, color: muted)
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.dropFirst().first ?? "dist/dmg-background.tiff"
try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Rendered 2x DMG background: \(output)")
