import Foundation
import NightModeCore

/// A short human description of what NightMode is doing.
public struct StatusSummary: Equatable {
    public var title: String
    public var detail: String?
    /// SF Symbol name.
    public var symbol: String
}

enum Fmt {
    static func time(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = calendar.timeZone
        let clock = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(clock)"
        }
        let weekday = DateFormatter()
        weekday.setLocalizedDateFormatFromTemplate("EEE")
        weekday.timeZone = calendar.timeZone
        return "\(weekday.string(from: date)) \(clock)"
    }

    static func clock(hour: Int, minute: Int, calendar: Calendar) -> String {
        var comps = DateComponents()
        comps.year = 2001
        comps.month = 1
        comps.day = 1
        comps.hour = hour
        comps.minute = minute
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    static func minutes(_ minutes: Double) -> String {
        duration(minutes * 60)
    }

    static func percent(_ level: Double) -> String { Level.format(level) }
}

extension AppModel {
    public func summary() -> StatusSummary {
        Self.summary(for: evaluation, now: now, calendar: calendar, brightnessAvailable: brightness != nil)
    }

    static func summary(for evaluation: Evaluation, now: Date, calendar: Calendar, brightnessAvailable: Bool) -> StatusSummary {
        func at(_ date: Date) -> String { Fmt.time(date, now: now, calendar: calendar) }
        var summary: StatusSummary
        switch evaluation.source {
        case .off(let until):
            if let until {
                summary = StatusSummary(title: "Off until \(at(until))", detail: "Then back to \(Fmt.percent(evaluation.underlyingLevel)) or whatever automation says.", symbol: "moon.zzz")
            } else {
                summary = StatusSummary(title: "Off", detail: "Use the switch or any level control to turn NightMode back on.", symbol: "power")
            }
        case .manual:
            summary = StatusSummary(title: "Manual", detail: nil, symbol: "hand.point.up.left")
        case .ramp(let ramp):
            let from = ramp.resolvedFrom ?? evaluation.level
            let verb = ramp.to >= from ? "Warming" : "Cooling"
            summary = StatusSummary(title: "\(verb) to \(Fmt.percent(ramp.to)) by \(at(ramp.end))",
                                    detail: "Ramp from \(Fmt.percent(from)), \(Fmt.duration(ramp.remaining(at: now))) left.",
                                    symbol: ramp.to >= from ? "arrow.up.right" : "arrow.down.right")
        case .override(let override, let auto):
            var resumes: [String] = []
            if let until = override.until { resumes.append("at \(at(until))") }
            if override.brightnessAnchor != nil { resumes.append("when brightness changes") }
            let title = resumes.isEmpty ? "Automation paused until you resume" : "Automation paused, resumes \(resumes.joined(separator: " or "))"
            var detail: String?
            if let auto { detail = "Automation would be at \(Fmt.percent(auto.level)) now." }
            summary = StatusSummary(title: title, detail: detail, symbol: "pause.circle")
        case .automation(let status):
            summary = automationSummary(status, now: now, calendar: calendar)
        }
        if let pending = evaluation.pendingRamp, evaluation.source != .off(until: nil) {
            let ramp = "Ramp to \(Fmt.percent(pending.to)) starts at \(at(pending.start))."
            summary.detail = [summary.detail, ramp].compactMap { $0 }.joined(separator: " ")
        }
        return summary
    }

    static func automationSummary(_ status: AutomationStatus, now: Date, calendar: Calendar) -> StatusSummary {
        func at(_ date: Date) -> String { Fmt.time(date, now: now, calendar: calendar) }
        let both = status.scheduleLevel != nil && status.brightnessLevel != nil
        var detail: String?
        if both, let s = status.scheduleLevel, let b = status.brightnessLevel {
            detail = "Schedule \(Fmt.percent(s)), brightness \(Fmt.percent(b)): using the warmer."
        }
        switch status.driver {
        case .schedule:
            if let state = status.scheduleState, state.isRamping(at: now) {
                let verb = state.segment.to >= state.segment.from ? "warming" : "cooling"
                return StatusSummary(title: "Schedule: \(verb) to \(Fmt.percent(state.segment.to)) by \(at(state.segment.end))",
                                     detail: detail, symbol: "clock")
            }
            var title = "Schedule: holding \(Fmt.percent(status.level))"
            if let next = status.nextScheduleChange {
                title += ", next \(Fmt.percent(next.transition.target)) at \(at(next.start))"
            }
            return StatusSummary(title: title, detail: detail, symbol: "clock")
        case .brightness:
            return StatusSummary(title: "Following brightness", detail: detail, symbol: "sun.max")
        }
    }
}
