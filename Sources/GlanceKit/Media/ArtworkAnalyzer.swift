import CoreGraphics
import Foundation
import ImageIO

/// Result of analyzing one piece of album artwork.
public struct ArtworkAnalysis: Equatable, Sendable {
    /// Perceptual average luminance, 0 (black) … 1 (white).
    public let averageLuminance: Double
    /// Luminance spread — busy artwork needs more overlay for legible text.
    public let luminanceVariance: Double
    /// Recommended dark-overlay opacity (0…1) for readable foreground text.
    public let recommendedOverlayOpacity: Double

    public init(averageLuminance: Double, luminanceVariance: Double, recommendedOverlayOpacity: Double) {
        self.averageLuminance = averageLuminance
        self.luminanceVariance = luminanceVariance
        self.recommendedOverlayOpacity = recommendedOverlayOpacity
    }
}

/// Adaptive contrast engine for Artwork mode.
///
/// Performance contract: analysis downsamples to a 16×16 thumbnail (256
/// pixels) via ImageIO, runs once per artwork, and is cached by artwork
/// identifier — a track change costs one tiny decode, not repeated
/// per-frame image work.
public final class ArtworkAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: ArtworkAnalysis] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit: Int

    public init(cacheLimit: Int = 24) {
        self.cacheLimit = cacheLimit
    }

    /// Analyze artwork bytes, using the cache when the identifier was seen
    /// before.
    public func analyze(artworkID: String, data: Data) -> ArtworkAnalysis? {
        if let cached = cachedAnalysis(for: artworkID) { return cached }
        guard let thumbnail = Self.downsampledImage(from: data, maxPixel: 16) else { return nil }
        let analysis = Self.analyze(image: thumbnail)
        store(analysis, for: artworkID)
        return analysis
    }

    public func cachedAnalysis(for artworkID: String) -> ArtworkAnalysis? {
        lock.lock(); defer { lock.unlock() }
        return cache[artworkID]
    }

    private func store(_ analysis: ArtworkAnalysis, for id: String) {
        lock.lock(); defer { lock.unlock() }
        if cache[id] == nil {
            cacheOrder.append(id)
            if cacheOrder.count > cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache[evicted] = nil
            }
        }
        cache[id] = analysis
    }

    // MARK: Pure analysis (testable with synthetic images)

    /// Map luminance statistics to an overlay opacity:
    /// - dark artwork  (L ≈ 0.1) → light overlay (~0.25)
    /// - bright artwork (L ≈ 0.9) → strong overlay (~0.62)
    /// - high variance (busy art) adds up to +0.1.
    public static func overlayOpacity(forLuminance luminance: Double, variance: Double) -> Double {
        let base = 0.20 + 0.47 * min(max(luminance, 0), 1)
        let busyBoost = min(variance * 1.2, 0.10)
        return min(max(base + busyBoost, 0.15), 0.75)
    }

    public static func analyze(image: CGImage) -> ArtworkAnalysis {
        let width = min(image.width, 16)
        let height = min(image.height, 16)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ArtworkAnalysis(averageLuminance: 0.5, luminanceVariance: 0, recommendedOverlayOpacity: 0.45)
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0.0
        var sumSquares = 0.0
        let count = width * height
        for i in 0..<count {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            // Rec. 709 luma.
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            sum += luma
            sumSquares += luma * luma
        }
        let mean = sum / Double(count)
        let variance = max(sumSquares / Double(count) - mean * mean, 0)
        return ArtworkAnalysis(
            averageLuminance: mean,
            luminanceVariance: variance,
            recommendedOverlayOpacity: overlayOpacity(forLuminance: mean, variance: variance)
        )
    }

    static func downsampledImage(from data: Data, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
