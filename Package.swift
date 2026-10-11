// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NightMode",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NightMode", targets: ["NightMode"]),
        .executable(name: "RenderScreenshots", targets: ["RenderScreenshots"]),
    ],
    targets: [
        // Pure logic: ramps, schedules, solar math, brightness curves, precedence engine.
        // Foundation only, fully unit tested with injected dates.
        .target(name: "NightModeCore"),
        // AppKit + SwiftUI app: menu bar item, Dynamic Options window, Night Shift bridge.
        .target(name: "NightModeApp", dependencies: ["NightModeCore"]),
        // Thin executable that boots the app.
        .executableTarget(name: "NightMode", dependencies: ["NightModeApp"]),
        // Renders README screenshots offscreen (no windows are shown).
        .executableTarget(name: "RenderScreenshots", dependencies: ["NightModeApp", "NightModeCore"]),
        .testTarget(name: "NightModeCoreTests", dependencies: ["NightModeCore"]),
        // App-level behavior against a mock Night Shift backend (never touches the real display).
        .testTarget(name: "NightModeAppTests", dependencies: ["NightModeApp", "NightModeCore"]),
    ]
)
