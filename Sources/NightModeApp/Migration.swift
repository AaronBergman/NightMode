import AppKit

/// One-time cleanup when upgrading from NightMode 1.x (bundle id `com.nightmode.app`, started at
/// login by a LaunchAgent plist written by its install script).
enum Migration {
    static let legacyBundleID = "com.nightmode.app"
    static let legacyAgentLabel = "com.nightmode.app"
    static let doneKey = "NightMode.migratedFromV1"

    static var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyAgentLabel).plist")
    }

    struct Report {
        var movedStatusItemPosition = false
        var replacedLaunchAgent = false
        var terminatedLegacyApp = false
        var notes: [String] = []
    }

    /// Safe to call on every launch; does nothing once everything is migrated.
    @discardableResult
    static func run(defaults: UserDefaults = .standard, loginItems: LoginItemControlling) -> Report {
        var report = Report()

        // 1. Keep the menu bar icon where the user put it.
        let newKey = "NSStatusItem Preferred Position \(MenuBarController.autosaveName)"
        if defaults.object(forKey: newKey) == nil,
           let legacy = UserDefaults(suiteName: legacyBundleID),
           let position = legacy.object(forKey: "NSStatusItem Preferred Position Item-0") {
            defaults.set(position, forKey: newKey)
            report.movedStatusItemPosition = true
        }

        // 2. Replace the old LaunchAgent with a proper login item, so exactly one copy starts at login.
        //    The plist goes to the Trash (recoverable). We do not `launchctl bootout` it: if this very
        //    process was started by that agent, booting it out would quit us. It is simply not loaded
        //    again at the next login.
        //    If registering fails, the old agent stays: it points at the same app path, so it still
        //    launches this version at login, and the single-instance check prevents duplicates.
        if FileManager.default.fileExists(atPath: legacyAgentURL.path) {
            do {
                try loginItems.set(true)
            } catch {
                report.notes.append("Could not register the login item: \(error.localizedDescription)")
            }
            if loginItems.state.isOn {
                do {
                    try FileManager.default.trashItem(at: legacyAgentURL, resultingItemURL: nil)
                    report.replacedLaunchAgent = true
                    report.notes.append("Launch at login now uses Login Items; the old LaunchAgent is in the Trash.")
                } catch {
                    report.notes.append("Could not move the old LaunchAgent to the Trash: \(error.localizedDescription)")
                }
            } else {
                report.notes.append("Kept the old LaunchAgent because the login item is not active (\(loginItems.state)).")
            }
        }

        // 3. Never let two NightModes fight over Night Shift.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID) {
            app.terminate()
            report.terminatedLegacyApp = true
        }

        defaults.set(true, forKey: doneKey)
        return report
    }
}
