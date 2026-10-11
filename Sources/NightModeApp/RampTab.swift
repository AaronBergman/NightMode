import SwiftUI
import NightModeCore

/// A labeled 0...100 slider with a numeric field.
struct LevelRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: 0...100)
            TextField(title, value: Binding(get: { Int(value.rounded()) }, set: { value = Level.clamp(Double($0)) }), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
            Text("%").foregroundColor(.secondary)
        }
    }
}

/// Minutes with a stepper and quick picks.
struct MinutesRow: View {
    let title: String
    @Binding var minutes: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            ForEach([15.0, 30, 60, 120], id: \.self) { quick in
                Button(Fmt.minutes(quick)) { minutes = quick }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(minutes == quick ? .accentColor : nil)
            }
            TextField(title, value: Binding(get: { Int(minutes.rounded()) }, set: { minutes = Double(max(1, min(1440, $0))) }), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
            Stepper(title, value: $minutes, in: 1...1440, step: minutes >= 60 ? 15 : 5)
                .labelsHidden()
            Text("min").foregroundColor(.secondary)
        }
    }
}

struct RampTab: View {
    @ObservedObject var model: AppModel

    private var draft: Binding<RampDraft> {
        Binding(get: { model.state.prefs.rampDraft },
                set: { newValue in model.updatePreferences { $0.rampDraft = newValue } })
    }

    var body: some View {
        Form {
            if let ramp = model.state.engine.ramp {
                Section("Active ramp") { ActiveRampView(model: model, ramp: ramp) }
            }
            Section {
                Picker("Start from", selection: draft.fromCurrent) {
                    Text("The current level (\(Level.format(model.evaluation.underlyingLevel)))").tag(true)
                    Text("A set level").tag(false)
                }
                .pickerStyle(.segmented)
                if !draft.wrappedValue.fromCurrent {
                    LevelRow(title: "From", value: draft.fromLevel)
                }
                LevelRow(title: "To", value: draft.toLevel)
                MinutesRow(title: "Over", minutes: draft.minutes)
                Picker("Starts", selection: draft.startNow) {
                    Text("Now").tag(true)
                    Text("At a set time").tag(false)
                }
                .pickerStyle(.segmented)
                if !draft.wrappedValue.startNow {
                    DatePicker("Start time", selection: startTime, displayedComponents: .hourAndMinute)
                }
                Picker("Pace", selection: draft.easing) {
                    Text("Steady").tag(Easing.linear)
                    Text("Gentle start and finish").tag(Easing.smooth)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Gradual change")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text(planDescription).foregroundColor(.secondary)
                    Spacer()
                    Button("Start Ramp") { model.startRampFromDraft() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.backend.isAvailable)
                }
                .padding(.top, 4)
            }
            Section {
                Text("Ramps follow the clock, not a counter, so they keep their place through sleep, restarts and quitting. When a ramp finishes, its level is held like a manual change. Moving the slider or picking a level replaces a running ramp; Stop Here freezes it where it is. The Gradual Change submenu in the menu bar has one-click versions.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private var startTime: Binding<Date> {
        Binding(get: {
            let d = model.state.prefs.rampDraft
            return model.calendar.date(bySettingHour: d.startHour, minute: d.startMinute, second: 0, of: model.now) ?? model.now
        }, set: { date in
            let comps = model.calendar.dateComponents([.hour, .minute], from: date)
            model.updatePreferences {
                $0.rampDraft.startHour = comps.hour ?? 21
                $0.rampDraft.startMinute = comps.minute ?? 0
            }
        })
    }

    private var planDescription: String {
        let d = model.state.prefs.rampDraft
        let to = Level.format(d.toLevel)
        let over = Fmt.minutes(d.minutes)
        if d.startNow {
            let from = d.fromCurrent ? Level.format(model.evaluation.underlyingLevel) : Level.format(d.fromLevel)
            let end = model.now.addingTimeInterval(d.minutes * 60)
            return "From \(from) to \(to) over \(over), done at \(Fmt.time(end, now: model.now, calendar: model.calendar))."
        }
        let start = model.nextOccurrence(hour: d.startHour, minute: d.startMinute)
        let from = d.fromCurrent ? "the level at that moment" : Level.format(d.fromLevel)
        return "At \(Fmt.time(start, now: model.now, calendar: model.calendar)), from \(from) to \(to) over \(over)."
    }
}

struct ActiveRampView: View {
    @ObservedObject var model: AppModel
    let ramp: Ramp

    var body: some View {
        let now = model.now
        VStack(alignment: .leading, spacing: 8) {
            if ramp.isPending(at: now) {
                Text("Starts at \(Fmt.time(ramp.start, now: now, calendar: model.calendar)), going to \(Level.format(ramp.to)) over \(Fmt.duration(ramp.duration)).")
            } else {
                ProgressView(value: ramp.progress(at: now))
                Text("\(Level.format(ramp.resolvedFrom ?? 0)) to \(Level.format(ramp.to)): now \(Level.format(model.displayedLevel)), \(Fmt.duration(ramp.remaining(at: now))) left, done at \(Fmt.time(ramp.end, now: now, calendar: model.calendar)).")
                    .monospacedDigit()
            }
            HStack {
                Spacer()
                Button(ramp.isPending(at: now) ? "Cancel Scheduled Ramp" : "Stop Here") { model.cancelRamp() }
            }
        }
    }
}
