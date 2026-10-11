import AppKit
import NightModeCore

public enum AppInfo {
    public static let repositoryURL = URL(string: "https://github.com/AaronBergman/NightMode")!
    public static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? "dev"
    }
}

public enum NightModeMain {
    public static func run() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var menuBar: MenuBarController?
    private var options: OptionsWindowController?
    private let hotKeys = HotKeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }
        let loginItems = SystemLoginItem()
        let store = StateStore()
        let firstRun = store.load() == nil && !Self.hasLegacyInstall()
        let report = Migration.run(loginItems: loginItems)
        for note in report.notes { NSLog("NightMode migration: %@", note) }

        let model = AppModel(backend: NightShiftBackend(), brightnessReader: DisplayServicesBrightness(),
                             loginItems: loginItems, store: store)
        self.model = model
        model.onPreferencesChanged = { [weak self] in self?.applyPreferences() }
        menuBar = MenuBarController(model: model,
                                    openOptions: { [weak self] tab in self?.showOptions(tab) },
                                    showAbout: { [weak self] in self?.showAbout() })
        model.start()
        applyPreferences()
        if firstRun {
            // A brand-new user double-clicked the app: show where the controls are.
            showOptions(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForQuit()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again (Finder, Spotlight) shows the options window.
        showOptions(nil)
        return true
    }

    private func applyPreferences() {
        guard let model else { return }
        if model.state.prefs.hotkeysEnabled {
            hotKeys.register(HotKeyCenter.standardShortcuts(
                warmer: { [weak model] in model?.nudge(5) },
                cooler: { [weak model] in model?.nudge(-5) },
                toggle: { [weak model] in model?.toggleOn() }))
        } else {
            hotKeys.unregisterAll()
        }
        model.hotKeyFailures = hotKeys.failed
        menuBar?.update()
    }

    private func showOptions(_ tab: OptionsTab?) {
        guard let model else { return }
        if let tab { model.selectedTab = tab }
        if options == nil { options = OptionsWindowController(model: model) }
        options?.show()
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(
            string: "Fine-grained control of Night Shift: precise levels, gradual ramps, daily schedules and brightness following.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(string: "github.com/AaronBergman/NightMode",
                                          attributes: [.font: NSFont.systemFont(ofSize: 11), .link: AppInfo.repositoryURL]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func anotherInstanceIsRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != me }
    }

    private static func hasLegacyInstall() -> Bool {
        FileManager.default.fileExists(atPath: Migration.legacyAgentURL.path)
            || UserDefaults(suiteName: Migration.legacyBundleID)?.dictionaryRepresentation()
                .keys.contains(where: { $0.hasPrefix("NSStatusItem") }) == true
            || UserDefaults.standard.bool(forKey: Migration.doneKey)
    }
}

/// `NightMode.app/Contents/MacOS/NightMode --self-test`: prints what NightMode can see. Read-only.
enum SelfTest {
    static func run() {
        print("NightMode \(AppInfo.version) self-test (read-only, changes nothing)")
        let backend = NightShiftBackend()
        print("Night Shift available: \(backend.isAvailable)\(backend.unavailableReason.map { " (\($0))" } ?? "")")
        if let status = backend.readStatus() {
            print("Night Shift: \(status.isEnabled ? "on" : "off"), strength \(String(format: "%.3f", status.strength)), NightMode level \(Level.format(status.level))")
            print("macOS Night Shift schedule: \(status.systemScheduleName) (\(status.nightStart.hour):\(String(format: "%02d", status.nightStart.minute)) to \(status.dayStart.hour):\(String(format: "%02d", status.dayStart.minute)))")
        }
        if let range = backend.temperatureRange {
            print("Color temperature range: \(Int(range.warmest))K (100%) to \(Int(range.coolest))K (0%)")
        }
        let brightness = DisplayServicesBrightness()
        let display = DisplayServicesBrightness.builtInDisplay().map { String($0) } ?? "none"
        let reading = brightness.read().map { String(format: "%.3f", $0) } ?? "unavailable"
        print("Brightness API: \(brightness.isSupported ? "present" : "missing"), built-in display: \(display), reading: \(reading)")
        let zone = TimeZone.current.identifier
        if let location = TimeZoneLocation.location(forTimeZone: zone) {
            let day = Solar.day(containing: Date(), calendar: .current, coordinate: location.coordinate)
            let f = DateFormatter()
            f.timeStyle = .short
            print("Time zone \(zone): approximate location \(location.name) (\(String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude)))")
            print("Today: sunrise \(day.sunrise.map(f.string) ?? "none"), sunset \(day.sunset.map(f.string) ?? "none")")
        } else {
            print("Time zone \(zone): no approximate location")
        }
        if let saved = StateStore().load() {
            let e = saved.engine
            print("Saved state: on \(e.isOn), manual level \(Level.format(e.manualLevel)), schedule \(e.schedule.isEnabled ? "on" : "off") (\(e.schedule.transitions.count) changes), follow brightness \(e.brightness.isEnabled ? "on" : "off")")
        } else {
            print("Saved state: none yet")
        }
        print("Launch at login: \(SystemLoginItem().state)")
    }
}
