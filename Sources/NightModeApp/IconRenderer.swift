import AppKit
import NightModeCore

/// Draws the menu bar icon: the plain template sunset glyph at 0%, and a filled sunset tinted with
/// an exaggerated version of the screen tint above 0% (amber at low levels, deep orange-red at 100%),
/// so the level reads at a glance. Colors adapt to light and dark menu bars at draw time.
public enum IconRenderer {
    public static let size = NSSize(width: 20, height: 18)

    /// Exaggerated tint color for a level, tuned for contrast on light or dark backgrounds.
    public static func tintColor(level: Double, dark: Bool) -> NSColor {
        let t = pow(Level.clamp(level) / 100, 0.55)  // stretch the low end so 5% is already clearly colored
        let hue = 0.128 - 0.118 * t                     // 46 deg amber -> 3.6 deg red-orange
        let saturation = 0.78 + 0.22 * t
        let brightness = dark ? 1.0 - 0.06 * t : 0.74 - 0.12 * t
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    /// The menu bar image.
    /// - Parameters:
    ///   - level: the level on screen.
    ///   - off: NightMode is switched off (draws the plain outline).
    ///   - paused: automation is paused by a manual change (adds a small dot).
    public static func image(level: Double, off: Bool, paused: Bool = false) -> NSImage {
        if off || level < Level.offThreshold {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let image = NSImage(systemSymbolName: "sunset", accessibilityDescription: "NightMode, off")?
                .withSymbolConfiguration(config) ?? NSImage(size: size)
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: size, flipped: false) { rect in
            let appearance = NSAppearance.currentDrawing()
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]).map {
                $0 == .darkAqua || $0 == .vibrantDark
            } ?? false
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
                (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "NightMode, \(Level.format(level))"
        return image
    }
}
