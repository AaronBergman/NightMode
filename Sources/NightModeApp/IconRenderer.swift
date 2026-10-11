import AppKit
import NightModeCore

/// Draws the menu bar icon and supplies the level color used by the readouts.
///
/// The color comes from `WarmthPalette`: the white point Night Shift is producing, exaggerated so it reads at
/// menu bar size, in evenly spaced perceptual steps. On a dark menu bar 0% is plain white and 100% is candlelight
/// amber; on a light menu bar 0% is template black and 100% is a dark amber. The filled glyph is drawn the same
/// way at every level, including 0%, so there is no jump between 0% and 1%. Only "off" uses the outline glyph.
public enum IconRenderer {
    public static let size = NSSize(width: 20, height: 18)

    public static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]).map {
            $0 == .darkAqua || $0 == .vibrantDark
        } ?? false
    }

    /// The level color for a dark or light background, in sRGB.
    public static func tintColor(level: Double, dark: Bool) -> NSColor {
        let c = WarmthPalette.srgb(level: level, on: dark ? .dark : .light)
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// The level color, resolved against whatever appearance it is drawn in (for text that can move between
    /// light and dark surfaces, such as the menu bar title).
    public static func dynamicTintColor(level: Double) -> NSColor {
        NSColor(name: nil) { appearance in tintColor(level: level, dark: isDark(appearance)) }
    }

    /// The menu bar image.
    /// - Parameters:
    ///   - level: the level on screen.
    ///   - off: NightMode is switched off (draws the plain outline).
    ///   - paused: automation is paused by a manual change (adds a small dot).
    public static func image(level: Double, off: Bool, paused: Bool = false) -> NSImage {
        if off {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let image = NSImage(systemSymbolName: "sunset", accessibilityDescription: "NightMode, off")?
                .withSymbolConfiguration(config) ?? NSImage(size: size)
            image.isTemplate = true
            return image
        }
        // Drawn lazily, so the color always matches the appearance of the bar it is drawn into.
        let image = NSImage(size: size, flipped: false) { rect in
            let dark = isDark(NSAppearance.currentDrawing())
            let color = tintColor(level: level, dark: dark)
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            guard let symbol = NSImage(systemSymbolName: "sunset.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return false }
            let s = symbol.size
            let origin = NSPoint(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2)
            symbol.draw(in: NSRect(origin: origin, size: s))
            if paused {
                let dot = NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 4.5, height: 4.5)
                tintColor(level: 0, dark: dark).withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "NightMode, \(Level.format(level))"
        return image
    }
}
