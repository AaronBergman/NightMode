import SwiftUI
import Charts
import NightModeCore

struct ScheduleTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let schedule = model.state.engine.schedule
        Form {
            Section {
                Toggle("Use the daily schedule", isOn: Binding(get: { schedule.isEnabled }, set: { model.setScheduleEnabled($0) }))
                    .disabled(!model.backend.isAvailable)
                if let status = model.nightShift, status.hasSystemSchedule {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("macOS's own Night Shift schedule is on (\(status.systemScheduleName)). It switches Night Shift on and off by itself, which fights NightMode's schedule.")
                        Spacer()
                        Button("Turn It Off") { model.turnOffSystemNightShiftSchedule() }
                    }
                    .font(.callout)
                }
            } header: {
                Text("Daily schedule")
            } footer: {
                Text("Each change starts at its time and moves to its level over its duration, starting from wherever the schedule was. Between changes the level holds. Everything is computed from the clock, so sleep and restarts never throw it off.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Today") {
                SchedulePreviewChart(schedule: schedule, context: ScheduleContext(calendar: model.calendar, location: model.effectiveLocation?.coordinate),
                                     now: minuteFloor(model.now), calendar: model.calendar)
                    .equatable()
                    .padding(.top, 14)
                    .frame(height: 164)
                    .opacity(schedule.isEnabled ? 1 : 0.45)
            }

            Section {
                ForEach(sortedIDs(schedule), id: \.self) { id in
                    TransitionRow(model: model, transition: binding(for: id), onDelete: { delete(id) })
                }
                HStack {
                    Button {
                        var list = schedule.transitions
                        list.append(Transition(anchor: .clock(hour: 22, minute: 0), target: 60, durationMinutes: 60))
                        model.setTransitions(list)
                    } label: {
                        Label("Add Change", systemImage: "plus")
                    }
                    Spacer()
                    Menu("Load Preset") {
                        Button("Gentle evening") { model.setTransitions(Presets.gentleEvening()) }
                        Button("Sunset to sunrise") { model.setTransitions(Presets.sunsetToSunrise()) }
                        Button("Deep night") { model.setTransitions(Presets.deepNight()) }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Changes")
            }

            Section("Location for sunrise and sunset") {
                LocationEditor(model: model)
            }
        }
        .formStyle(.grouped)
    }

    private func minuteFloor(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    /// Rows in time-of-day order (sun times use today's values, or typical ones without a location).
    private func sortedIDs(_ schedule: Schedule) -> [UUID] {
        let cal = model.calendar
        let location = model.effectiveLocation?.coordinate
        let today = model.now
        func key(_ t: NightModeCore.Transition) -> Double {
            if let date = t.anchor.date(onDayContaining: today, calendar: cal, location: location) {
                let c = cal.dateComponents([.hour, .minute], from: date)
                return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }
            switch t.anchor {
            case .clock(let h, let m): return Double(h * 60 + m)
            case .sunrise(let o): return Double(6 * 60 + o)
            case .sunset(let o): return Double(18 * 60 + o)
            }
        }
        // Morning changes (before noon) sort after evening ones, so a night reads top to bottom.
        func nightOrder(_ t: NightModeCore.Transition) -> Double {
            let k = key(t)
            return k < 12 * 60 ? k + 24 * 60 : k
        }
        return schedule.transitions.sorted { nightOrder($0) < nightOrder($1) }.map(\.id)
    }

    private func binding(for id: UUID) -> Binding<NightModeCore.Transition> {
        Binding(get: {
            model.state.engine.schedule.transitions.first { $0.id == id }
                ?? Transition(id: id, anchor: .clock(hour: 0, minute: 0), target: 0, durationMinutes: 0)
        }, set: { newValue in
            var list = model.state.engine.schedule.transitions
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            list[index] = newValue
            model.setTransitions(list)
        })
    }

    private func delete(_ id: UUID) {
        model.setTransitions(model.state.engine.schedule.transitions.filter { $0.id != id })
    }
}

struct TransitionRow: View {
    @ObservedObject var model: AppModel
    @Binding var transition: NightModeCore.Transition
    let onDelete: () -> Void

    private enum Kind: String { case clock, sunset, sunrise }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: $transition.isEnabled).labelsHidden()
                Picker("When", selection: kind) {
                    Text("At a time").tag(Kind.clock)
                    Text("Sunset").tag(Kind.sunset)
                    Text("Sunrise").tag(Kind.sunrise)
                }
                .labelsHidden()
                .frame(width: 110)
                switch transition.anchor {
                case .clock:
                    DatePicker("Time", selection: clockTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .fixedSize()
                case .sunset, .sunrise:
                    Stepper(value: offset, in: -240...240, step: 5) {
                        Text(offsetText).monospacedDigit()
                    }
                    if let date = todaysDate {
                        Text("(today \(Fmt.time(date, now: model.now, calendar: model.calendar)))").foregroundColor(.secondary)
                    } else if model.effectiveLocation == nil {
                        Text("needs a location").foregroundColor(.orange)
                    }
                }
                Spacer()
                DaysMenu(weekdays: $transition.weekdays, calendar: model.calendar)
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete this change")
            }
            HStack(spacing: 8) {
                Text("go to")
                Slider(value: Binding(get: { transition.target }, set: { transition.target = $0.rounded() }), in: 0...100)
                    .frame(width: 170)
                Text(Level.format(transition.target)).monospacedDigit().frame(width: 40, alignment: .trailing)
                Text("over")
                TextField("Minutes", value: Binding(get: { Int(transition.durationMinutes.rounded()) },
                                                    set: { transition.durationMinutes = Double(max(0, min(1440, $0))) }), format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                Text("min")
                Menu(fromText) {
                    Button("Continue from where it is") { transition.fixedFrom = nil }
                    Divider()
                    ForEach([0.0, 25, 50, 75, 100], id: \.self) { value in
                        Button("Jump to \(Level.format(value)) first") { transition.fixedFrom = value }
                    }
                }
                .fixedSize()
                .help("Where the change starts from")
                Spacer(minLength: 0)
            }
            .disabled(!transition.isEnabled)
            .foregroundColor(transition.isEnabled ? .primary : .secondary)
        }
        .padding(.vertical, 6)
    }

    private var fromText: String {
        transition.fixedFrom.map { "from \(Level.format($0))" } ?? "from where it is"
    }

    private var todaysDate: Date? {
        transition.anchor.date(onDayContaining: model.now, calendar: model.calendar, location: model.effectiveLocation?.coordinate)
    }

    private var kind: Binding<Kind> {
        Binding(get: {
            switch transition.anchor {
            case .clock: return .clock
            case .sunset: return .sunset
            case .sunrise: return .sunrise
            }
        }, set: { newKind in
            switch newKind {
            case .clock:
                let fallback = todaysDate.map { model.calendar.dateComponents([.hour, .minute], from: $0) }
                transition.anchor = .clock(hour: fallback?.hour ?? 21, minute: ((fallback?.minute ?? 0) / 5) * 5)
            case .sunset: transition.anchor = .sunset(offsetMinutes: 0)
            case .sunrise: transition.anchor = .sunrise(offsetMinutes: 0)
            }
        })
    }

    private var clockTime: Binding<Date> {
        Binding(get: {
            guard case .clock(let h, let m) = transition.anchor else { return model.now }
            return model.calendar.date(bySettingHour: h, minute: m, second: 0, of: model.now) ?? model.now
        }, set: { date in
            let c = model.calendar.dateComponents([.hour, .minute], from: date)
            transition.anchor = .clock(hour: c.hour ?? 0, minute: c.minute ?? 0)
        })
    }

    private var offset: Binding<Int> {
        Binding(get: {
            switch transition.anchor {
            case .sunset(let o), .sunrise(let o): return o
            case .clock: return 0
            }
        }, set: { value in
            switch transition.anchor {
            case .sunset: transition.anchor = .sunset(offsetMinutes: value)
            case .sunrise: transition.anchor = .sunrise(offsetMinutes: value)
            case .clock: break
            }
        })
    }

    private var offsetText: String {
        let o = offset.wrappedValue
        if o == 0 { return "exactly" }
        return o < 0 ? "\(Fmt.minutes(Double(-o))) before" : "\(Fmt.minutes(Double(o))) after"
    }
}

struct DaysMenu: View {
    @Binding var weekdays: Set<Int>
    let calendar: Calendar

    var body: some View {
        Menu(label) {
            Button("Every Day") { weekdays = [] }
            Button("Weekdays") { weekdays = [2, 3, 4, 5, 6] }
            Button("Weekends") { weekdays = [1, 7] }
            Divider()
            ForEach(orderedDays, id: \.self) { day in
                Toggle(calendar.weekdaySymbols[day - 1], isOn: Binding(get: { isOn(day) }, set: { set(day, $0) }))
            }
        }
        .fixedSize()
        .help("Which days this change runs")
    }

    private var orderedDays: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func isOn(_ day: Int) -> Bool { weekdays.isEmpty || weekdays.contains(day) }

    private func set(_ day: Int, _ on: Bool) {
        var days = weekdays.isEmpty ? Set(1...7) : weekdays
        if on { days.insert(day) } else { days.remove(day) }
        weekdays = days.count == 7 ? [] : days
    }

    private var label: String {
        if weekdays.isEmpty || weekdays.count == 7 { return "Every day" }
        if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        return orderedDays.filter { weekdays.contains($0) }.map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}

/// A 24-hour preview of the schedule for today. Equatable so it only redraws when its inputs change.
struct SchedulePreviewChart: View, Equatable {
    let schedule: Schedule
    let context: ScheduleContext
    let now: Date
    let calendar: Calendar

    static func == (a: SchedulePreviewChart, b: SchedulePreviewChart) -> Bool {
        a.schedule.transitions == b.schedule.transitions && a.now == b.now
            && a.context.location == b.context.location && a.calendar.timeZone == b.calendar.timeZone
    }

    struct Point: Identifiable {
        let date: Date
        let level: Double
        var id: Date { date }
    }

    var body: some View {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let active = Schedule(isEnabled: true, transitions: schedule.transitions)
        let points = active.samples(from: start, to: end, step: 300, context: context).map { Point(date: $0.0, level: $0.1) }
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Level", point.level))
                    .foregroundStyle(LinearGradient(colors: [Color.orange.opacity(0.45), Color.orange.opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("Level", point.level))
                    .foregroundStyle(Color.orange)
            }
            RuleMark(x: .value("Now", now))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center) {
                    Text("now").font(.caption2).foregroundColor(.secondary)
                }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .environment(\.timeZone, calendar.timeZone)
    }
}

struct LocationEditor: View {
    @ObservedObject var model: AppModel
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let location = model.effectiveLocation {
                let isManual = model.state.prefs.manualLocation != nil
                Text("\(location.name) (\(String(format: "%.2f, %.2f", location.coordinate.latitude, location.coordinate.longitude)))\(isManual ? "" : ", approximated from your time zone")")
                let day = Solar.day(containing: model.now, calendar: model.calendar, coordinate: location.coordinate)
                Text(sunText(day)).foregroundColor(.secondary)
            } else {
                Text("No location yet. Sun-relative changes are skipped until you enter one.").foregroundColor(.orange)
            }
            HStack(spacing: 8) {
                TextField("Latitude", value: $latitude, format: .number.precision(.fractionLength(0...4)), prompt: Text("Latitude"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                TextField("Longitude", value: $longitude, format: .number.precision(.fractionLength(0...4)), prompt: Text("Longitude"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                TextField("Name", text: $name, prompt: Text("Name (optional)"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Button("Use These") {
                    guard let latitude, let longitude else { return }
                    let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
                    guard coordinate.isValid else { return }
                    model.setManualLocation(NamedLocation(name: name.isEmpty ? "Custom location" : name, coordinate: coordinate))
                }
                .disabled(!isValidEntry)
                if model.state.prefs.manualLocation != nil {
                    Button("Use Time Zone") { model.setManualLocation(nil) }
                }
            }
            .labelsHidden()
            Text("Coordinates are used only on this Mac to compute sunrise and sunset. No location permission is needed. Tip: right-click a place in Maps to copy its coordinates.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isValidEntry: Bool {
        guard let latitude, let longitude else { return false }
        return GeoCoordinate(latitude: latitude, longitude: longitude).isValid
    }

    private func sunText(_ day: Solar.Day) -> String {
        switch day.polar {
        case .alwaysUp: return "Today: the sun does not set."
        case .alwaysDown: return "Today: the sun does not rise."
        case nil:
            let rise = day.sunrise.map { Fmt.time($0, now: model.now, calendar: model.calendar) } ?? "none"
            let set = day.sunset.map { Fmt.time($0, now: model.now, calendar: model.calendar) } ?? "none"
            return "Today: sunrise \(rise), sunset \(set)."
        }
    }
}
