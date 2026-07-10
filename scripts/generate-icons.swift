#!/usr/bin/env swift
// Generates Glance's app icon (.icns) and menu bar glyph (.pdf) from vector
// drawing code, so the mark can be regenerated or tweaked without a design
// tool. Run: swift scripts/generate-icons.swift
//
// Mark: a capsule (the notch itself) with a centered indicator dot — the
// same green "device in use" dot macOS shows beside a real notch, doubling
// as a nod to "Live Activity". Full color for the Dock/Finder app icon,
// monochrome silhouette (dot included) for the menu bar template image.

import AppKit
import CoreGraphics
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

// MARK: - Shared geometry

/// Pill (capsule) + centered dot, normalized to a unit canvas (0...1).
private struct Mark {
    static let pillWidth: CGFloat = 0.62
    static let pillHeight: CGFloat = 0.22
    static let dotRadius: CGFloat = 0.052
}

private func pillPath(in rect: CGRect) -> CGPath {
    let w = rect.width * Mark.pillWidth
    let h = rect.width * Mark.pillHeight
    let pillRect = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    return CGPath(roundedRect: pillRect, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
}

private func dotPath(in rect: CGRect) -> CGPath {
    let r = rect.width * Mark.dotRadius
    let dotRect = CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)
    return CGPath(ellipseIn: dotRect, transform: nil)
}

// MARK: - App icon (full color, squircle background)

private func drawAppIcon(context ctx: CGContext, size: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.saveGState()

    // Squircle background (macOS Big Sur+ corner ratio).
    let cornerRadius = size * 0.2237
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }

    // Soft green glow behind the dot.
    let dot = dotPath(in: rect).boundingBox
    let glowCenter = CGPoint(x: dot.midX, y: dot.midY)
    let glowColors = [
        CGColor(red: 0.19, green: 0.84, blue: 0.35, alpha: 0.55),
        CGColor(red: 0.19, green: 0.84, blue: 0.35, alpha: 0),
    ] as CFArray
    if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: glowCenter, startRadius: 0,
            endCenter: glowCenter, endRadius: size * 0.22,
            options: []
        )
    }

    // Pill: translucent glass fill + light stroke.
    let pill = pillPath(in: rect)
    ctx.addPath(pill)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fillPath()
    ctx.addPath(pill)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.65))
    ctx.setLineWidth(size * 0.014)
    ctx.strokePath()

    // Dot: solid system green, the focal point.
    ctx.addPath(dotPath(in: rect))
    ctx.setFillColor(CGColor(red: 0.19, green: 0.84, blue: 0.35, alpha: 1))
    ctx.fillPath()

    ctx.restoreGState()
}

private func renderPNG(size: Int, draw: (CGContext, CGFloat) -> Void) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("could not create bitmap context") }

    draw(ctx, CGFloat(size))

    guard let cgImage = ctx.makeImage() else { fatalError("could not render image") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode png")
    }
    return data
}

// MARK: - iconset -> icns

let iconsetSizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let resourcesDir = repoRoot.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for entry in iconsetSizes {
    let data = renderPNG(size: entry.px) { ctx, size in drawAppIcon(context: ctx, size: size) }
    try data.write(to: iconsetDir.appendingPathComponent("\(entry.name).png"))
}

let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconsetDir)
print("Wrote \(icnsURL.path)")

// Also drop a 1024 PNG alongside for READMEs / GitHub release notes.
let previewData = renderPNG(size: 1024) { ctx, size in drawAppIcon(context: ctx, size: size) }
try previewData.write(to: resourcesDir.appendingPathComponent("AppIcon-preview.png"))

// MARK: - Menu bar glyph (monochrome template PDF)

let menuBarSize: CGFloat = 18
let menuBarRect = CGRect(x: 0, y: 0, width: menuBarSize, height: menuBarSize)
// Lives directly in the Glance target so it ships as an SwiftPM resource
// (Bundle.module), not copied into the app bundle by make-app.sh.
let glanceResourcesDir = repoRoot.appendingPathComponent("Sources/Glance/Resources")
try? FileManager.default.createDirectory(at: glanceResourcesDir, withIntermediateDirectories: true)
let menuBarURL = glanceResourcesDir.appendingPathComponent("MenuBarIcon.pdf")

guard let pdfConsumer = CGDataConsumer(url: menuBarURL as CFURL),
      let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: nil, nil) else {
    fatalError("could not create PDF context")
}

var mediaBox = menuBarRect
pdfContext.beginPage(mediaBox: &mediaBox)

// Solid capsule with a punched-out center dot — a single black shape
// (alpha only) that NSStatusItem tints automatically as a template image.
// Taller proportions than the app icon mark so it stays legible at 16-18pt.
let barWidth = menuBarRect.width * 0.86
let barHeight = menuBarRect.width * 0.46
let barRect = CGRect(
    x: menuBarRect.midX - barWidth / 2, y: menuBarRect.midY - barHeight / 2,
    width: barWidth, height: barHeight
)
let barPath = CGPath(roundedRect: barRect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil)

let holeRadius = menuBarRect.width * 0.10
let holeRect = CGRect(
    x: menuBarRect.midX - holeRadius, y: menuBarRect.midY - holeRadius,
    width: holeRadius * 2, height: holeRadius * 2
)
let holePath = CGPath(ellipseIn: holeRect, transform: nil)

pdfContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
pdfContext.addPath(barPath)
pdfContext.addPath(holePath)
pdfContext.fillPath(using: .evenOdd)

pdfContext.endPage()
pdfContext.closePDF()
print("Wrote \(menuBarURL.path)")
