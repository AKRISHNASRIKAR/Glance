#!/usr/bin/env swift
// Generates Glance's app icon (.icns) and menu bar glyph (.pdf) from vector
// drawing code, so the mark can be regenerated or tweaked without a design
// tool. Run: swift scripts/generate-icons.swift
//
// App icon: a midnight teal-to-navy rounded screen with a top-attached notch
// and a live dot/equalizer. The menu bar keeps its monochrome capsule mark.

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

private func drawAppIcon(context ctx: CGContext, size: CGFloat, variant: String = "midnight") {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    let space = CGColorSpaceCreateDeviceRGB()
    let tile = CGRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
    let radius = size * 0.19
    let outline = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.025,
                  color: CGColor(red: 0.03, green: 0.08, blue: 0.06, alpha: 0.3))
    ctx.addPath(outline)
    ctx.setFillColor(CGColor(red: 0.2, green: 0.32, blue: 0.26, alpha: 1))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0)
    ctx.addPath(outline)
    ctx.clip()

    let palette: [CGColor]
    switch variant {
    case "midnight": palette = [CGColor(red: 0.18, green: 0.34, blue: 0.35, alpha: 1), CGColor(red: 0.10, green: 0.20, blue: 0.25, alpha: 1), CGColor(red: 0.055, green: 0.10, blue: 0.145, alpha: 1)]
    case "indigo": palette = [CGColor(red: 0.24, green: 0.23, blue: 0.44, alpha: 1), CGColor(red: 0.12, green: 0.13, blue: 0.25, alpha: 1), CGColor(red: 0.04, green: 0.065, blue: 0.11, alpha: 1)]
    case "graphite", "orbit": palette = Array(repeating: CGColor(red: 0.085, green: 0.095, blue: 0.105, alpha: 1), count: 3)
    case "porcelain": palette = Array(repeating: CGColor(red: 0.87, green: 0.89, blue: 0.84, alpha: 1), count: 3)
    default: palette = [CGColor(red: 0.75, green: 0.85, blue: 0.65, alpha: 1), CGColor(red: 0.31, green: 0.53, blue: 0.43, alpha: 1), CGColor(red: 0.20, green: 0.24, blue: 0.32, alpha: 1)]
    }
    let colors = palette as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.48, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY),
                           end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.84, green: 0.77, blue: 0.92, alpha: 0.6),
        CGColor(red: 0.84, green: 0.77, blue: 0.92, alpha: 0)
    ] as CFArray, locations: [0, 1])!
    if variant == "sage" { ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.maxX, y: tile.minY), startRadius: 0,
                           endCenter: CGPoint(x: tile.maxX, y: tile.minY), endRadius: size * 0.9, options: []) }

    if variant == "orbit" {
        let orbit = CGMutablePath()
        orbit.addArc(center: CGPoint(x: size * 0.5, y: size * 0.5), radius: size * 0.23,
                     startAngle: .pi * 0.62, endAngle: .pi * 2.38, clockwise: false)
        ctx.addPath(orbit)
        ctx.setStrokeColor(CGColor(red: 0.74, green: 0.88, blue: 0.63, alpha: 1))
        ctx.setLineWidth(size * 0.045)
        ctx.setLineCap(.round)
        ctx.strokePath()
        let cutout = CGRect(x: size * 0.42, y: size * 0.69, width: size * 0.16, height: size * 0.10)
        ctx.addPath(CGPath(roundedRect: cutout, cornerWidth: size * 0.03, cornerHeight: size * 0.03, transform: nil))
        ctx.setFillColor(CGColor(red: 0.74, green: 0.88, blue: 0.63, alpha: 1))
        ctx.fillPath()
        ctx.fillEllipse(in: CGRect(x: size * 0.477, y: size * 0.477, width: size * 0.046, height: size * 0.046))
        return
    }

    // A camera notch, attached to the screen's top edge, with square top
    // corners and rounded lower corners (the same silhouette as Glance).
    let notchWidth = size * 0.48
    let notchHeight = size * 0.20
    let notchRadius = size * 0.055
    let left = size / 2 - notchWidth / 2
    let right = size / 2 + notchWidth / 2
    let top = tile.maxY + size * 0.01
    let bottom = tile.maxY - notchHeight
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: left, y: top))
    notch.addLine(to: CGPoint(x: right, y: top))
    notch.addLine(to: CGPoint(x: right, y: bottom + notchRadius))
    notch.addQuadCurve(to: CGPoint(x: right - notchRadius, y: bottom), control: CGPoint(x: right, y: bottom))
    notch.addLine(to: CGPoint(x: left + notchRadius, y: bottom))
    notch.addQuadCurve(to: CGPoint(x: left, y: bottom + notchRadius), control: CGPoint(x: left, y: bottom))
    notch.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.009), blur: size * 0.018,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.2))
    ctx.addPath(notch)
    ctx.setFillColor(CGColor(red: 0.035, green: 0.065, blue: 0.055, alpha: 1))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0)

    // Quiet activity mark in the notch: one live dot and three small bars.
    ctx.setFillColor(CGColor(red: 0.74, green: 0.88, blue: 0.63, alpha: 1))
    let dotSize = size * 0.033
    ctx.fillEllipse(in: CGRect(x: size * 0.37 - dotSize / 2, y: bottom + notchHeight * 0.45 - dotSize / 2,
                              width: dotSize, height: dotSize))
    for (index, height) in [0.025, 0.055, 0.038].enumerated() {
        let bar = CGRect(x: size * (0.565 + Double(index) * 0.022),
                         y: bottom + notchHeight * 0.45 - size * height / 2,
                         width: size * 0.01, height: size * height)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: size * 0.005, cornerHeight: size * 0.005, transform: nil))
        ctx.fillPath()
    }
    ctx.addPath(outline)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.setLineWidth(size * 0.002)
    ctx.strokePath()
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

if CommandLine.arguments.contains("--variants") {
    let directory = repoRoot.appendingPathComponent("Resources/IconVariants")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for variant in ["midnight", "indigo", "graphite", "porcelain", "orbit"] {
        let png = renderPNG(size: 512) { context, size in drawAppIcon(context: context, size: size, variant: variant) }
        try png.write(to: directory.appendingPathComponent("\(variant).png"))
    }
    let variants = ["midnight", "indigo", "graphite", "porcelain", "orbit"]
    let names = ["1. Midnight · gradient", "2. Indigo · gradient", "3. Graphite · flat", "4. Porcelain · flat", "5. Orbit · alternative"]
    let sheet = renderPNG(size: 1024) { context, _ in
        context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let positions: [CGPoint] = [CGPoint(x: 40, y: 590), CGPoint(x: 370, y: 590), CGPoint(x: 700, y: 590), CGPoint(x: 205, y: 190), CGPoint(x: 535, y: 190)]
        for index in variants.indices {
            context.saveGState()
            context.translateBy(x: positions[index].x, y: positions[index].y)
            drawAppIcon(context: context, size: 280, variant: variants[index])
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (names[index] as NSString).draw(at: CGPoint(x: 15, y: -25), withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.darkGray])
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
        }
    }
    try sheet.write(to: directory.appendingPathComponent("comparison.png"))
    print("Generated icon options in \(directory.path)")
    exit(0)
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
