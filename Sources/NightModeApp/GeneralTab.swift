import SwiftUI
import NightModeCore

struct GeneralTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let prefs = model.state.prefs
        Form {
            Section("Startup") {
                Toggle("Launch NightMode at login", isOn: Binding(get: { model.loginItem.isOn }, set: { model.setLaunchAtLogin($0) }))
                switch model.loginItem {
                case .requiresApproval:
                    HStack {
                        Text("macOS is waiting for you to allow NightMode in Login Items.").foregroundColor(.orange)
                        Button("Open Login Items") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                case .unavailable(let reason):
                    Text(reason).foregroundColor(.orange)
                default:
                    EmptyView()
                }
                if let error = model.lastError {
                    Text(error).foregroundColor(.red)
                }
            }

            Section("Menu bar") {
                Toggle("Show the percentage next to the icon",
                       isOn: Binding(get: { prefs.showPercentInMenuBar }, set: { v in model.updatePreferences { $0.showPercentInMenuBar = v } }))
                Text("The icon shows the warmth Night Shift is adding, exaggerated so it reads at menu bar size: white at 0%, warming through cream and peach to candlelight amber at 100% (black to dark amber on a light menu bar), in evenly sized steps. A plain outline means NightMode is off; a small dot means automation is paused.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Keyboard shortcuts") {
                Toggle("Enable system-wide shortcuts",
                       isOn: Binding(get: { prefs.hotkeysEnabled }, set: { v in model.updatePreferences { $0.hotkeysEnabled = v } }))
                ForEach(HotKeyCenter.standardShortcuts(warmer: {}, cooler: {}, toggle: {}), id: \.display) { shortcut in
                    LabeledContent(shortcut.description) {
                        Text(shortcut.display).font(.body.monospaced())
                    }
                }
                .opacity(prefs.hotkeysEnabled ? 1 : 0.5)
                if !model.hotKeyFailures.isEmpty {
                    Text("Already used by another app: \(model.hotKeyFailures.joined(separator: ", "))").foregroundColor(.orange)
                }
            }

            Section {
                Picker("Pause automation", selection: Binding(get: { model.state.engine.pausePolicy }, set: { model.setPausePolicy($0) })) {
                    Text("Until the next scheduled change").tag(PausePolicy.untilNextChange)
                    Text("For one hour").tag(PausePolicy.oneHour)
                    Text("Until I choose Resume Automation").tag(PausePolicy.untilResume)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Manual changes while automation is on")
            } footer: {
                Text("Using the slider, a level button, a nudge or a shortcut while the schedule or brightness following is on pauses automation at your level. With \u{201C}until the next scheduled change\u{201D}, brightness following also resumes once the brightness moves by 15 points or more. Resume any time from the menu.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Quitting") {
                Picker("When NightMode quits", selection: Binding(get: { prefs.quitBehavior }, set: { v in model.updatePreferences { $0.quitBehavior = v } })) {
                    Text("Leave the tint as it is").tag(QuitBehavior.leaveTint)
                    Text("Turn the tint off").tag(QuitBehavior.turnTintOff)
                }
                .pickerStyle(.radioGroup)
                Text("Night Shift is a system setting, so the tint stays when NightMode quits or crashes unless you choose to turn it off. Schedules and ramps continue from the right place when NightMode starts again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Night Shift") {
                LabeledContent("Status") {
                    if let status = model.nightShift {
                        Text(status.isEnabled ? "On at \(Level.format(status.level))" : "Off")
                    } else {
                        Text(model.backend.unavailableReason ?? "Unknown")
                    }
                }
                if let range = model.backend.temperatureRange {
                    LabeledContent("Range on this Mac") {
                        Text("100% is about \(Int(range.warmest))K, the warmest Night Shift allows")
                    }
                }
                if let status = model.nightShift {
                    LabeledContent("macOS Night Shift schedule") {
                        HStack {
                            Text(status.systemScheduleName)
                            if status.hasSystemSchedule {
                                Button("Turn Off") { model.turnOffSystemNightShiftSchedule() }
                            }
                        }
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") { Text(AppInfo.version) }
                LabeledContent("Source and help") {
                    Link("github.com/AaronBergman/NightMode", destination: AppInfo.repositoryURL)
                }
            }
        }
        .formStyle(.grouped)
    }
}
