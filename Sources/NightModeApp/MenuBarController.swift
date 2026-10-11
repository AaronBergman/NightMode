import AppKit
import Combine
import NightModeCore

/// The status item, its tinted icon, and the menu.
public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let autosaveName = "NightModeStatusItem"

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let panel: ControlPanelView
    private var cancellables: Set<AnyCancellable> = []
    private var updateScheduled = false
    private var appearanceObservation: NSKeyValueObservation?
    private var lastIconKey = ""
    private let openOptions: (OptionsTab?) -> Void
    private let showAbout: () -> Void

    private let resumeItem = NSMenuItem(title: "Resume Automation", action: #selector(resume), keyEquivalent: "")
    private let cancelRampItem = NSMenuItem(title: "Cancel Ramp", action: #selector(cancelRamp), keyEquivalent: "")
    private let offItem = NSMenuItem(title: "Turn Off for 1 Hour", action: #selector(toggleOffForHour), keyEquivalent: "")
    private let scheduleItem = NSMenuItem(title: "Daily Schedule", action: #selector(toggleSchedule), keyEquivalent: "")
    private let brightnessItem = NSMenuItem(title: "Follow Brightness", action: #selector(toggleBrightness), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    public init(model: AppModel, openOptions: @escaping (OptionsTab?) -> Void, showAbout: @escaping () -> Void) {
        self.model = model
        self.openOptions = openOptions
        self.showAbout = showAbout
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.autosaveName
        panel = ControlPanelView(model: model)
        super.init()
        buildMenu()
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityTitle("NightMode")
        // Redraw the colored icon when the menu bar switches between light and dark.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.lastIconKey = ""
            self?.scheduleUpdate()
        }
        model.objectWillChange.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &cancellables)
        update()
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        let panelItem = NSMenuItem()
        panelItem.view = panel
        menu.addItem(panelItem)
        menu.addItem(.separator())

        for item in [resumeItem, cancelRampItem] {
            item.target = self
            menu.addItem(item)
        }

        let gradual = NSMenuItem(title: "Gradual Change", action: nil, keyEquivalent: "")
        gradual.submenu = gradualMenu()
        menu.addItem(gradual)

        offItem.target = self
        menu.addItem(offItem)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Automation", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "Automation", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        menu.addItem(header)
        for item in [scheduleItem, brightnessItem] {
            item.target = self
            menu.addItem(item)
        }
        let options = NSMenuItem(title: "Dynamic Options\u{2026}", action: #selector(openDynamicOptions), keyEquivalent: ",")
        options.target = self
        menu.addItem(options)
        menu.addItem(.separator())

        loginItem.target = self
        menu.addItem(loginItem)
        let about = NSMenuItem(title: "About NightMode", action: #selector(about), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit NightMode", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func gradualMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        func header(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
        }
        func ramp(_ title: String, to target: Double, minutes: Double) {
            let item = NSMenuItem(title: title, action: #selector(quickRamp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [target, minutes]
            item.indentationLevel = 1
            sub.addItem(item)
        }
        header("To 100% from the current level")
        ramp("Over 15 Minutes", to: 100, minutes: 15)
        ramp("Over 30 Minutes", to: 100, minutes: 30)
        ramp("Over 1 Hour", to: 100, minutes: 60)
        ramp("Over 2 Hours", to: 100, minutes: 120)
        sub.addItem(.separator())
        header("To 0% from the current level")
        ramp("Over 5 Minutes", to: 0, minutes: 5)
        ramp("Over 15 Minutes", to: 0, minutes: 15)
        ramp("Over 30 Minutes", to: 0, minutes: 30)
        sub.addItem(.separator())
        let custom = NSMenuItem(title: "Custom Ramp\u{2026}", action: #selector(customRamp), keyEquivalent: "")
        custom.target = self
        sub.addItem(custom)
        return sub
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        model.resync()
        update()
    }

    // MARK: - Updating

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.updateScheduled = false
            self?.update()
        }
    }

    public func update() {
        updateIcon()
        panel.update()

        let source = model.evaluation.source
        if case .override = source { resumeItem.isHidden = false } else { resumeItem.isHidden = true }
        if case .ramp = source {
            cancelRampItem.isHidden = false
            cancelRampItem.title = "Cancel Ramp"
        } else if model.evaluation.pendingRamp != nil {
            cancelRampItem.isHidden = false
            cancelRampItem.title = "Cancel Scheduled Ramp"
        } else {
            cancelRampItem.isHidden = true
        }
        if case .off(let until) = source, until != nil {
            offItem.title = "Turn Back On Now"
        } else {
            offItem.title = "Turn Off for 1 Hour"
        }
        offItem.isEnabled = model.backend.isAvailable

        let engine = model.state.engine
        scheduleItem.state = engine.schedule.isEnabled ? .on : .off
        brightnessItem.state = engine.brightness.isEnabled ? .on : .off
        brightnessItem.isEnabled = model.brightnessReader.isSupported
        brightnessItem.toolTip = model.brightnessReader.isSupported ? nil : model.brightnessReader.unsupportedReason
        loginItem.state = model.loginItem.isOn ? .on : .off
        if case .unavailable(let reason) = model.loginItem {
            loginItem.isEnabled = false
            loginItem.toolTip = reason
        } else {
            loginItem.isEnabled = true
            loginItem.toolTip = model.loginItem == .requiresApproval ? "Waiting for approval in System Settings > General > Login Items." : nil
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let off = model.isOff
        var paused = false
        if case .override = model.evaluation.source { paused = true }
        let level = model.displayedLevel
        let showPercent = model.state.prefs.showPercentInMenuBar
        let key = "\(off)|\(paused)|\(String(format: "%.1f", level))|\(showPercent)"
        guard key != lastIconKey else { return }
        lastIconKey = key
        button.image = IconRenderer.image(level: level, off: off, paused: paused)
        if showPercent {
            button.title = off ? "" : " \(Level.format(level))"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        } else {
            button.title = ""
        }
        button.toolTip = off ? "NightMode: off" : "NightMode: \(Level.format(level))"
    }

    // MARK: - Actions

    @objc private func resume() { model.resumeAutomation() }
    @objc private func cancelRamp() { model.cancelRamp() }

    @objc private func toggleOffForHour() {
        if case .off(let until) = model.evaluation.source, until != nil {
            model.setOn(true)
        } else {
            model.turnOffForAnHour()
        }
    }

    @objc private func toggleSchedule() {
        model.setScheduleEnabled(!model.state.engine.schedule.isEnabled)
        if model.state.engine.schedule.isEnabled && !model.state.engine.schedule.hasActiveTransitions {
            openOptions(.schedule)
        }
    }

    @objc private func toggleBrightness() { model.setBrightnessEnabled(!model.state.engine.brightness.isEnabled) }
    @objc private func toggleLogin() { model.setLaunchAtLogin(!model.loginItem.isOn) }
    @objc private func openDynamicOptions() { openOptions(nil) }
    @objc private func customRamp() { openOptions(.ramp) }
    @objc private func about() { showAbout() }

    @objc private func quickRamp(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Double], values.count == 2 else { return }
        model.startRamp(origin: .current, to: values[0], minutes: values[1], start: nil, easing: .linear)
    }
}
