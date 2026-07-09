import AppKit

/// Geometry of the notch surface on a given screen.
struct NotchGeometry: Equatable {
    /// The physical notch rect in screen coordinates (or a synthetic
    /// top-center rect on displays without a notch).
    var notchRect: CGRect
    var hasPhysicalNotch: Bool

    /// Sizing for each visual state, all anchored to the top-center.
    var idleSize: CGSize { notchRect.size }

    func liveSize(wing: CGFloat = 56) -> CGSize {
        CGSize(width: notchRect.width + wing * 2, height: notchRect.height)
    }

    func peekSize(wing: CGFloat = 150) -> CGSize {
        CGSize(width: notchRect.width + wing * 2, height: notchRect.height)
    }

    static let expandedSize = CGSize(width: 620, height: 205)

    /// The window frame: a fixed region around the notch large enough for
    /// the expanded state. The window never resizes; the visible shape
    /// animates inside it (this avoids window-resize jank entirely).
    var windowFrame: CGRect {
        let width = max(Self.expandedSize.width, notchRect.width) + 80
        let height = Self.expandedSize.height + notchRect.height + 40
        return CGRect(
            x: notchRect.midX - width / 2,
            y: notchRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// Detect the notch on a screen via safe-area / auxiliary-area APIs.
    /// Never assumes a fixed notch size.
    static func forScreen(_ screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = frame.width - leftArea.width - rightArea.width
            let notchHeight = screen.safeAreaInsets.top
            return NotchGeometry(
                notchRect: CGRect(
                    x: frame.minX + leftArea.width,
                    y: frame.maxY - notchHeight,
                    width: notchWidth,
                    height: notchHeight
                ),
                hasPhysicalNotch: true
            )
        }
        // Non-notch display: synthetic compact surface at top-center, sized
        // like a small notch sitting in the menu bar area.
        let menuBarHeight = NSStatusBar.system.thickness + 8
        let syntheticWidth: CGFloat = 190
        return NotchGeometry(
            notchRect: CGRect(
                x: frame.midX - syntheticWidth / 2,
                y: frame.maxY - menuBarHeight,
                width: syntheticWidth,
                height: menuBarHeight
            ),
            hasPhysicalNotch: false
        )
    }

    /// Prefer a screen with a physical notch; fall back to the main screen.
    static func bestScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
