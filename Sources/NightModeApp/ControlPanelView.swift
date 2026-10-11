import AppKit
import NightModeCore

/// The control block at the top of the menu: on/off switch, readout with -5/-1/+1/+5 nudges,
/// slider, 0/25/50/75/100 presets and a one-line status. Plain AppKit controls, which work
/// reliably inside an NSMenu (clicking them keeps the menu open, so nudges can be repeated).
public final class ControlPanelView: NSView {
    public static let width: CGFloat = 300
    public static let height: CGFloat = 186

    private weak var model: AppModel?
    private let titleLabel = NSTextField(labelWithString: "NightMode")
    private let powerSwitch = NSSwitch()
    private let readout = NSTextField(labelWithString: "0%")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let presets = NSSegmentedControl()
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var nudgeButtons: [NSButton] = []
    /// While the slider is being dragged, don't push values back into it (avoids knob jitter).
    private var lastSliderInteraction = Date.distantPast

    public override var isFlipped: Bool { true }

    public init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        build()
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        let inset: CGFloat = 16
        let inner = Self.width - inset * 2

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.frame = NSRect(x: inset, y: 12, width: 160, height: 18)
        addSubview(titleLabel)

        powerSwitch.controlSize = .small
        powerSwitch.target = self
        powerSwitch.action = #selector(powerChanged)
        powerSwitch.sizeToFit()
        powerSwitch.frame.origin = NSPoint(x: Self.width - inset - powerSwitch.frame.width, y: 11)
        powerSwitch.setAccessibilityLabel("NightMode on or off")
        addSubview(powerSwitch)

        // Readout with nudges on either side.
        let buttonWidth: CGFloat = 40
        let buttonY: CGFloat = 44
        let specs: [(String, Double, String)] = [("\u{2212}5", -5, "5 percent cooler"), ("\u{2212}1", -1, "1 percent cooler"),
                                                 ("+1", 1, "1 percent warmer"), ("+5", 5, "5 percent warmer")]
        for (index, spec) in specs.enumerated() {
            let button = NSButton(title: spec.0, target: self, action: #selector(nudge(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.tag = Int(spec.1)
            button.setAccessibilityLabel(spec.2)
            button.toolTip = spec.2.prefix(1).uppercased() + spec.2.dropFirst()
            let x: CGFloat
            switch index {
            case 0: x = inset - 4
            case 1: x = inset - 4 + buttonWidth + 2
            case 2: x = Self.width - inset + 4 - 2 * buttonWidth - 2
            default: x = Self.width - inset + 4 - buttonWidth
            }
            button.frame = NSRect(x: x, y: buttonY, width: buttonWidth, height: 24)
            addSubview(button)
            nudgeButtons.append(button)
        }
        readout.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        readout.alignment = .center
        readout.frame = NSRect(x: inset + 2 * buttonWidth, y: 39, width: inner - 4 * buttonWidth, height: 32)
        readout.setAccessibilityLabel("Current level")
        addSubview(readout)

        // Slider between a small and a large sun.
        let less = NSImageView(frame: NSRect(x: inset - 2, y: 84, width: 18, height: 18))
        less.image = NSImage(systemSymbolName: "sun.min", accessibilityDescription: "Less warm")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        less.contentTintColor = .tertiaryLabelColor
        addSubview(less)
        slider.frame = NSRect(x: inset + 20, y: 83, width: inner - 42, height: 20)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.setAccessibilityLabel("Warmth")
        addSubview(slider)
        let more = NSImageView(frame: NSRect(x: Self.width - inset - 18, y: 84, width: 20, height: 18))
        more.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "More warm")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        more.contentTintColor = .secondaryLabelColor
        addSubview(more)

        // Presets.
        presets.segmentCount = 5
        for (index, value) in [0, 25, 50, 75, 100].enumerated() {
            presets.setLabel("\(value)", forSegment: index)
            presets.setWidth((inner - 8) / 5, forSegment: index)
            presets.setToolTip("Set \(value)%", forSegment: index)
        }
        presets.trackingMode = .momentary
        presets.segmentStyle = .rounded
        presets.controlSize = .small
        presets.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        presets.target = self
        presets.action = #selector(presetChosen(_:))
        presets.frame = NSRect(x: inset, y: 115, width: inner, height: 24)
        presets.setAccessibilityLabel("Preset levels")
        addSubview(presets)

        // Status line.
        statusIcon.frame = NSRect(x: inset, y: 152, width: 14, height: 14)
        statusIcon.contentTintColor = .secondaryLabelColor
        addSubview(statusIcon)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.frame = NSRect(x: inset + 20, y: 151, width: inner - 20, height: 32)
        addSubview(statusLabel)
    }

    /// Pulls everything from the model. Cheap enough to call on every change.
    public func update() {
        guard let model else { return }
        let off = model.isOff
        let shown = off ? model.evaluation.underlyingLevel : model.displayedLevel
        powerSwitch.state = off ? .off : .on
        if Date().timeIntervalSince(lastSliderInteraction) > 0.4 { slider.doubleValue = shown }
        if off {
            readout.stringValue = "Off"
            readout.textColor = .secondaryLabelColor
        } else {
            readout.stringValue = Level.format(model.displayedLevel)
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            readout.textColor = model.displayedLevel < Level.offThreshold ? .labelColor : IconRenderer.tintColor(level: model.displayedLevel, dark: dark)
        }
        let enabled = model.backend.isAvailable
        for control in [slider, presets, powerSwitch] as [NSControl] + nudgeButtons { control.isEnabled = enabled }

        if !enabled {
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            statusLabel.stringValue = model.backend.unavailableReason ?? "Night Shift is not available."
            return
        }
        let summary = model.summary()
        statusIcon.image = NSImage(systemSymbolName: summary.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        statusLabel.stringValue = summary.title
        statusLabel.toolTip = summary.detail
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        update()
    }

    // MARK: - Actions

    @objc private func powerChanged() {
        model?.setOn(powerSwitch.state == .on)
    }

    @objc private func nudge(_ sender: NSButton) {
        model?.nudge(Double(sender.tag))
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        lastSliderInteraction = Date()
        model?.setLevel(sender.doubleValue.rounded(), style: .immediate)
    }

    @objc private func presetChosen(_ sender: NSSegmentedControl) {
        let values: [Double] = [0, 25, 50, 75, 100]
        guard sender.selectedSegment >= 0, sender.selectedSegment < values.count else { return }
        model?.setLevel(values[sender.selectedSegment], style: .quick)
    }
}
