// Renders Resources/AppIcon.icns offscreen (no windows). Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("NightMode.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)
    // macOS icon grid: 824 pt rounded square centred in 1024, with a soft shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Dusk sky: indigo at the top, plum, then a warm orange horizon.
    let gradient = NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.11, blue: 0.30, alpha: 1),
                                       NSColor(srgbRed: 0.42, green: 0.20, blue: 0.45, alpha: 1),
                                       NSColor(srgbRed: 0.97, green: 0.52, blue: 0.24, alpha: 1)],
                              atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    gradient.draw(in: path, angle: -90)
    // The sunset glyph, warm white.
    let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 1, green: 0.93, blue: 0.80, alpha: 1)]))
    let symbol = NSImage(systemSymbolName: "sunset.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let size = symbol.size
    symbol.draw(in: NSRect(x: 512 - size.width / 2, y: 470 - size.height / 2, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(1024).write(to: root.appendingPathComponent("docs/images/icon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and docs/images/icon.png" : "iconutil failed")
