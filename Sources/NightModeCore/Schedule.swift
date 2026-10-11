import Foundation

/// When a scheduled change starts each day.
public enum TimeAnchor: Codable, Equatable, Hashable, Sendable {
    /// A wall-clock time, e.g. 21:00.
    case clock(hour: Int, minute: Int)
    /// Minutes before (negative) or after (positive) sunrise.
    case sunrise(offsetMinutes: Int)
    /// Minutes before (negative) or after (positive) sunset.
    case sunset(offsetMinutes: Int)

    public var isSolar: Bool {
        switch self {
        case .clock: return false
        case .sunrise, .sunset: return true
        }
    }

    /// The instant this anchor falls on during the local day that contains `day`.
    /// Nil when it cannot be computed (sun-relative without a location, or no sunrise/sunset that day).
    public func date(onDayContaining day: Date, calendar: Calendar, location: GeoCoordinate?) -> Date? {
        switch self {
        case .clock(let hour, let minute):
            let start = calendar.startOfDay(for: day)
            return calendar.date(bySettingHour: min(23, max(0, hour)), minute: min(59, max(0, minute)), second: 0,
                                 of: start, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        case .sunrise(let offset):
            guard let location, location.isValid,
                  let rise = Solar.day(containing: day, calendar: calendar, coordinate: location).sunrise else { return nil }
            return rise.addingTimeInterval(TimeInterval(offset) * 60)
        case .sunset(let offset):
            guard let location, location.isValid,
                  let set = Solar.day(containing: day, calendar: calendar, coordinate: location).sunset else { return nil }
            return set.addingTimeInterval(TimeInterval(offset) * 60)
        }
    }
}

/// One daily change: "at 21:00, move to 80% over 120 minutes".
public struct Transition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var anchor: TimeAnchor
    /// Level to reach, 0...100.
    public var target: Double
    /// How long the move takes. 0 means jump.
    public var durationMinutes: Double
    /// Start from this level instead of wherever the schedule was. Nil means continue smoothly.
    public var fixedFrom: Double?
    /// Calendar weekday numbers, 1 = Sunday ... 7 = Saturday. Empty means every day.
    public var weekdays: Set<Int>

    public init(id: UUID = UUID(), isEnabled: Bool = true, anchor: TimeAnchor, target: Double,
                durationMinutes: Double, fixedFrom: Double? = nil, weekdays: Set<Int> = []) {
        self.id = id
        self.isEnabled = isEnabled
        self.anchor = anchor
        self.target = Level.clamp(target)
        self.durationMinutes = max(0, durationMinutes)
        self.fixedFrom = fixedFrom.map(Level.clamp)
        self.weekdays = weekdays
    }

    public func runs(onWeekday weekday: Int) -> Bool {
        weekdays.isEmpty || weekdays.count >= 7 || weekdays.contains(weekday)
    }

    enum CodingKeys: String, CodingKey { case id, isEnabled, anchor, target, durationMinutes, fixedFrom, weekdays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        anchor = try c.decode(TimeAnchor.self, forKey: .anchor)
        target = Level.clamp(try c.decode(Double.self, forKey: .target))
        durationMinutes = max(0, try c.decodeIfPresent(Double.self, forKey: .durationMinutes) ?? 0)
        fixedFrom = try c.decodeIfPresent(Double.self, forKey: .fixedFrom).map(Level.clamp)
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
    }
}

/// Everything a schedule needs to turn its rules into instants.
public struct ScheduleContext: Sendable {
    public var calendar: Calendar
    public var location: GeoCoordinate?

    public init(calendar: Calendar, location: GeoCoordinate?) {
        self.calendar = calendar
        self.location = location
    }
}

/// A transition happening on a particular day.
public struct Occurrence: Equatable, Sendable {
    public var start: Date
    public var transition: Transition
    /// Position in the schedule's list, used to order transitions that start at the same instant.
    public var order: Int

    public var end: Date { start.addingTimeInterval(transition.durationMinutes * 60) }
}

/// Where a schedule stands at some instant.
public struct ScheduleState: Equatable, Sendable {
    public var level: Double
    /// The move currently in effect (it may have finished, in which case the level is its target).
    public var segment: Segment
    public var lastOccurrence: Occurrence?

    public func isRamping(at now: Date) -> Bool { segment.isMoving(at: now) }
}

/// A list of daily transitions. The level at any instant is a pure function of the clock:
/// replay the transitions of the last 8 days in order, each one moving from wherever the previous
/// left off. That makes schedules immune to sleep, missed timers and relaunches.
public struct Schedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var transitions: [Transition]

    public init(isEnabled: Bool = false, transitions: [Transition] = []) {
        self.isEnabled = isEnabled
        self.transitions = transitions
    }

    /// How far back to replay. 8 days covers weekday-specific rules.
    public static let lookback: TimeInterval = 8 * 86_400

    public var hasActiveTransitions: Bool { transitions.contains { $0.isEnabled } }
    public var needsLocation: Bool { transitions.contains { $0.isEnabled && $0.anchor.isSolar } }

    /// All transition starts in `[from, through]`, in time order.
    public func occurrences(from: Date, through: Date, context: ScheduleContext) -> [Occurrence] {
        let enabled = transitions.enumerated().filter { $0.element.isEnabled }
        guard !enabled.isEmpty, from <= through else { return [] }
        let calendar = context.calendar
        // Walk local days by their noon (robust to DST changes at midnight). Start a day early and end
        // a day late so sun offsets that cross midnight are not missed.
        guard var day = noon(of: from.addingTimeInterval(-86_400), calendar: calendar) else { return [] }
        let lastDay = through.addingTimeInterval(2 * 86_400)
        var result: [Occurrence] = []
        var guardCounter = 0
        while day <= lastDay && guardCounter < 400 {
            guardCounter += 1
            let weekday = calendar.component(.weekday, from: day)
            for (order, transition) in enabled where transition.runs(onWeekday: weekday) {
                if let start = transition.anchor.date(onDayContaining: day, calendar: calendar, location: context.location),
                   start >= from, start <= through {
                    result.append(Occurrence(start: start, transition: transition, order: order))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.sorted { ($0.start, $0.order) < ($1.start, $1.order) }
    }

    /// The schedule's level and active move at `t`. Nil if no transition could be placed in the last 8 days.
    public func state(at t: Date, context: ScheduleContext) -> ScheduleState? {
        let past = occurrences(from: t.addingTimeInterval(-Self.lookback), through: t, context: context)
        guard let last = past.last else { return nil }
        // The schedule repeats, so before the first replayed transition we assume the level the most
        // recent one reached. This only matters if the very first replayed move had no fixed start.
        var segment = Segment.constant(last.transition.target)
        for occurrence in past {
            let from = occurrence.transition.fixedFrom ?? segment.value(at: occurrence.start)
            segment = Segment(from: from, to: occurrence.transition.target, start: occurrence.start,
                              duration: occurrence.transition.durationMinutes * 60)
        }
        return ScheduleState(level: segment.value(at: t), segment: segment, lastOccurrence: last)
    }

    /// The first transition that starts strictly after `t` (within the next 8 days).
    public func nextOccurrence(after t: Date, context: ScheduleContext) -> Occurrence? {
        occurrences(from: t, through: t.addingTimeInterval(Self.lookback), context: context)
            .first { $0.start > t }
    }

    /// Samples the schedule's level every `step` seconds, e.g. for a preview chart. Computes the
    /// transitions once and folds through them in a single pass (same result as `state(at:)`).
    public func samples(from: Date, to: Date, step: TimeInterval, context: ScheduleContext) -> [(Date, Double)] {
        guard step > 0, from <= to else { return [] }
        let all = occurrences(from: from.addingTimeInterval(-Self.lookback), through: to, context: context)
        guard !all.isEmpty else {
            var out: [(Date, Double)] = []
            var t = from
            while t <= to { out.append((t, 0)); t = t.addingTimeInterval(step) }
            return out
        }
        // Same starting assumption as state(at:): the level of the most recent transition before the first sample.
        let initial = all.last(where: { $0.start <= from })?.transition.target ?? all[0].transition.target
        var segment = Segment.constant(initial)
        var index = 0
        var out: [(Date, Double)] = []
        var t = from
        while t <= to {
            while index < all.count, all[index].start <= t {
                let occurrence = all[index]
                let start = occurrence.transition.fixedFrom ?? segment.value(at: occurrence.start)
                segment = Segment(from: start, to: occurrence.transition.target, start: occurrence.start,
                                  duration: occurrence.transition.durationMinutes * 60)
                index += 1
            }
            out.append((t, index == 0 ? 0 : segment.value(at: t)))
            t = t.addingTimeInterval(step)
        }
        return out
    }

    private func noon(of date: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: calendar.startOfDay(for: date))
    }

    enum CodingKeys: String, CodingKey { case isEnabled, transitions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        transitions = try c.decodeIfPresent([Transition].self, forKey: .transitions) ?? []
    }
}
