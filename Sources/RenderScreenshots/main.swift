// Renders the README images into docs/images, entirely offscreen: windows are created but never
// shown, and the app runs against MockTintBackend, so the real display is never touched.
//   swift run RenderScreenshots
import AppKit
import SwiftUI
import NightModeCore
import NightModeApp

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/images")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let la = TimeZone(identifier: "America/Los_Angeles")!
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = la
NSTimeZone.default = la

func date(_ text: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = la
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: text)!
}

func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

func makeModel(at time: String, level: Double, brightness: Double? = 0.62, configure: (inout AppState) -> Void) -> AppModel {
    var state = AppState()
    configure(&state)
    let now = date(time)
    let model = AppModel(backend: MockTintBackend(level: level), brightnessReader: MockBrightnessReader(brightness),
                         loginItems: MockLoginItem(.enabled), store: nil, initialState: state,
                         clock: { now }, calendar: { calendar })
    model.start()
    spin(3)  // let any fade finish
    return model
}

func render(_ view: NSView, size: NSSize, dark: Bool, scale: CGFloat = 2) -> NSBitmapImageRep {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.isReleasedWhenClosed = false
    view.frame = NSRect(origin: .zero, size: size)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    spin(0.6)
    view.layoutSubtreeIfNeeded()
    view.display()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// Draws a window frame (title bar with traffic lights, rounded corners, shadow) around a rendered content image.
func framed(_ content: NSBitmapImageRep, title: String, dark: Bool, scale: CGFloat = 2) -> NSBitmapImageRep {
    let titleBar: CGFloat = 28
    let margin: CGFloat = 40
    let size = NSSize(width: content.size.width + margin * 2, height: content.size.height + titleBar + margin * 2)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let windowRect = NSRect(x: margin, y: margin, width: content.size.width, height: content.size.height + titleBar)
    let path = NSBezierPath(roundedRect: windowRect, xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    path.addClip()
    content.draw(in: NSRect(x: margin, y: margin, width: content.size.width, height: content.size.height))
    let bar = NSRect(x: margin, y: margin + content.size.height, width: content.size.width, height: titleBar)
    (dark ? NSColor(white: 0.21, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
    bar.fill()
    for (i, color) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                       NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: bar.minX + 14 + CGFloat(i) * 20, y: bar.midY - 6, width: 12, height: 12)).fill()
    }
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                .foregroundColor: dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.25, alpha: 1)]
    let text = NSAttributedString(string: title, attributes: attrs)
    text.draw(at: NSPoint(x: bar.midX - text.size().width / 2, y: bar.midY - text.size().height / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    let url = outDir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote docs/images/\(name) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

// MARK: - Menu

/// A faithful mock of the open menu: the real ControlPanelView plus drawn menu rows, under a strip of menu bar.
final class MenuMock: NSView {
    let model: AppModel
    let dark: Bool
    let panel: ControlPanelView
    static let rows: [(String, String, Bool, Bool)] = [  // title, shortcut, checked, isHeader
        ("-", "", false, false),
        ("Gradual Change", "\u{25B8}", false, false),
        ("Turn Off for 1 Hour", "", false, false),
        ("-", "", false, false),
        ("Automation", "", false, true),
        ("Daily Schedule", "", true, false),
        ("Follow Brightness", "", false, false),
        ("Dynamic Options\u{2026}", "\u{2318},", false, false),
        ("-", "", false, false),
        ("Launch at Login", "", true, false),
        ("About NightMode", "", false, false),
        ("Quit NightMode", "\u{2318}Q", false, false),
    ]

    init(model: AppModel, dark: Bool) {
        self.model = model
        self.dark = dark
        panel = ControlPanelView(model: model)
        super.init(frame: .zero)
        addSubview(panel)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    static var menuHeight: CGFloat {
        ControlPanelView.height + rows.reduce(0) { $0 + ($1.0 == "-" ? 11 : 22) } + 10
    }

    override func layout() {
        super.layout()
        panel.frame = NSRect(x: bounds.width - ControlPanelView.width - 24, y: 24 + 8 + 5, width: ControlPanelView.width, height: ControlPanelView.height)
        panel.update()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Desktop-ish backdrop and menu bar strip.
        (dark ? NSColor(srgbRed: 0.12, green: 0.13, blue: 0.20, alpha: 1) : NSColor(srgbRed: 0.80, green: 0.85, blue: 0.93, alpha: 1)).setFill()
        bounds.fill()
        (dark ? NSColor(white: 0.12, alpha: 0.92) : NSColor(white: 0.97, alpha: 0.92)).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 24).fill()
        let fg = dark ? NSColor.white : NSColor.black
        let clock = NSAttributedString(string: "Sat Oct 10  10:15 PM", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: fg])
        clock.draw(at: NSPoint(x: bounds.width - clock.size().width - 14, y: 4))
        var x = bounds.width - clock.size().width - 30
        for symbol in ["battery.75percent", "wifi"] {
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular).applying(.init(paletteColors: [fg])))!
            x -= img.size.width + 14
            img.draw(in: NSRect(x: x, y: 12 - img.size.height / 2, width: img.size.width, height: img.size.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        // NightMode's item, highlighted because its menu is open.
        let icon = IconRenderer.image(level: model.displayedLevel, off: model.isOff)
        x -= icon.size.width + 20
        let iconBox = NSRect(x: x - 6, y: 2, width: icon.size.width + 12, height: 20)
        (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.12)).setFill()
        NSBezierPath(roundedRect: iconBox, xRadius: 5, yRadius: 5).fill()
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            icon.draw(in: NSRect(x: x, y: 3, width: icon.size.width, height: icon.size.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        // Menu body.
        let menuRect = NSRect(x: bounds.width - ControlPanelView.width - 24, y: 24 + 5, width: ControlPanelView.width, height: Self.menuHeight)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        (dark ? NSColor(white: 0.19, alpha: 1) : NSColor(white: 0.965, alpha: 1)).setFill()
        NSBezierPath(roundedRect: menuRect, xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.12)).setStroke()
        NSBezierPath(roundedRect: menuRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()

        var y = menuRect.minY + 8 + ControlPanelView.height
        let secondary = dark ? NSColor(white: 1, alpha: 0.5) : NSColor(white: 0, alpha: 0.5)
        for row in Self.rows {
            if row.0 == "-" {
                (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.1)).setFill()
                NSRect(x: menuRect.minX + 14, y: y + 5, width: menuRect.width - 28, height: 1).fill()
                y += 11
                continue
            }
            let font = row.3 ? NSFont.systemFont(ofSize: 11, weight: .semibold) : NSFont.menuFont(ofSize: 13)
            let color = row.3 ? secondary : fg
            if row.2 {
                let check = NSAttributedString(string: "\u{2713}", attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: fg])
                check.draw(at: NSPoint(x: menuRect.minX + 12, y: y + 2))
            }
            NSAttributedString(string: row.0, attributes: [.font: font, .foregroundColor: color])
                .draw(at: NSPoint(x: menuRect.minX + 28, y: y + (row.3 ? 5 : 2)))
            if !row.1.isEmpty {
                let s = NSAttributedString(string: row.1, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: secondary])
                s.draw(at: NSPoint(x: menuRect.maxX - 16 - s.size().width, y: y + 2))
            }
            y += 22
        }
    }
}

// MARK: - Icon strip

func iconStrip() -> NSBitmapImageRep {
    // nil = NightMode switched off (outline glyph).
    let levels: [Double?] = [nil, 0, 1, 2, 5, 10, 25, 50, 75, 100]
    let cell: CGFloat = 52
    let bar: CGFloat = 30
    let size = NSSize(width: CGFloat(levels.count) * cell, height: 2 * bar + 26)
    let scale: CGFloat = 3
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    for (row, dark) in [(0, false), (1, true)] {
        let y = 26 + CGFloat(row) * bar
        (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSRect(x: 0, y: y, width: size.width, height: bar).fill()
        for (i, level) in levels.enumerated() {
            let icon = IconRenderer.image(level: level ?? 0, off: level == nil)
            let rect = NSRect(x: CGFloat(i) * cell + (cell - icon.size.width) / 2, y: y + (bar - icon.size.height) / 2,
                              width: icon.size.width, height: icon.size.height)
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                if icon.isTemplate {
                    // How the menu bar renders a template image: plain white or black.
                    let tinted = icon.copy() as! NSImage
                    tinted.lockFocus()
                    IconRenderer.tintColor(level: 0, dark: dark).set()
                    NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                    tinted.unlockFocus()
                    tinted.draw(in: rect)
                } else {
                    icon.draw(in: rect)
                }
            }
        }
    }
    for (i, level) in levels.enumerated() {
        let text = level.map { "\(Int($0))%" } ?? "off"
        let label = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                                 .foregroundColor: NSColor(white: 0.42, alpha: 1)])
        label.draw(at: NSPoint(x: CGFloat(i) * cell + (cell - label.size().width) / 2, y: 6))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Scenes

// Gentle evening is on; at 22:15 it is warming from 40% to 70% (47.5% now).
let evening = makeModel(at: "2026-10-10 22:15", level: 47.5) { $0.engine.schedule.isEnabled = true }
for dark in [true, false] {
    let size = NSSize(width: 420, height: 24 + 5 + MenuMock.menuHeight + 30)
    save(render(MenuMock(model: evening, dark: dark), size: size, dark: dark), "menu-\(dark ? "dark" : "light").png")
}

func optionsShot(_ model: AppModel, tab: OptionsTab, name: String, dark: Bool = true, height: CGFloat = 780) {
    model.selectedTab = tab
    let host = NSHostingView(rootView: OptionsView(model: model))
    let content = render(host, size: NSSize(width: 700, height: height), dark: dark)
    save(framed(content, title: "NightMode Dynamic Options", dark: dark), name)
}

optionsShot(evening, tab: .schedule, name: "options-schedule.png", height: 1290)

// A "Gradual to 100%" ramp started at 22:05 from 40%: at 22:15 it is at 60%.
let ramping = makeModel(at: "2026-10-10 22:15", level: 60) { state in
    state.engine.manualLevel = 40
    state.engine.ramp = Ramp(origin: .fixed(40), to: 100, start: date("2026-10-10 22:05"), duration: 1800)
}
optionsShot(ramping, tab: .ramp, name: "options-ramp.png", height: 1010)

// Following brightness with the screen at 30%.
let dim = makeModel(at: "2026-10-10 22:15", level: 51, brightness: 0.30) { $0.engine.brightness.isEnabled = true }
optionsShot(dim, tab: .brightness, name: "options-brightness.png", height: 1160)
optionsShot(dim, tab: .general, name: "options-general.png", dark: false, height: 1240)

save(iconStrip(), "icon-levels.png")
print("done")
