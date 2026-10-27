// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GlanceKit", targets: ["GlanceKit"]),
        .executable(name: "Glance", targets: ["Glance"]),
        .executable(name: "GlanceBrowserBridge", targets: ["GlanceBrowserBridge"]),
    ],
    targets: [
        // GlanceKit: engines, models, providers. Headless and fully testable —
        // no dependency on the notch UI.
        .target(
            name: "GlanceKit",
            path: "Sources/GlanceKit"
        ),
        // Glance: the macOS app (AppKit notch window + SwiftUI content).
        .executableTarget(
            name: "Glance",
            dependencies: ["GlanceKit"],
            path: "Sources/Glance",
            resources: [.copy("Resources/MenuBarIcon.pdf")]
        ),
        .executableTarget(name: "GlanceBrowserBridge", dependencies: ["GlanceKit"], path: "Sources/GlanceBrowserBridge"),
        .executableTarget(name: "GlanceBrowserHarness", dependencies: ["GlanceKit"], path: "browser-extension/native-tests"),
        .testTarget(
            name: "GlanceKitTests",
            dependencies: ["GlanceKit"],
            path: "Tests/GlanceKitTests"
        ),
    ]
)
