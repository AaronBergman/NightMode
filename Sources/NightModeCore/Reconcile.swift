import Foundation

/// What to do when Night Shift's real state stops matching what NightMode last applied
/// (someone used Control Center or System Settings, or macOS ended "on until tomorrow").
public enum ExternalChangeReaction: Equatable, Sendable {
    /// Nothing meaningful changed.
    case ignore
    /// Treat the new level as a manual change.
    case adopt(Double)
    /// Put NightMode's level back.
    case reassert
}

public enum ExternalChangePolicy {
    /// Differences up to this many points are rounding noise.
    public static let tolerance: Double = 0.6
    /// How close to macOS's daily Night Shift end time a switch-off must be to count as automatic.
    public static let dayStartWindow: TimeInterval = 180

    /// - Parameters:
    ///   - expected: the level NightMode last applied.
    ///   - actual: the level Night Shift reports now (0 when Night Shift is off).
    ///   - source: why NightMode is at its current level.
    ///   - systemDayStart: the end of macOS's own Night Shift window (hour, minute), if known.
    public static func react(expected: Double, actual: Double, source: LevelSource, now: Date,
                             calendar: Calendar, systemDayStart: (hour: Int, minute: Int)?) -> ExternalChangeReaction {
        let expectedOff = expected < Level.offThreshold
        let actualOff = actual < Level.offThreshold
        if expectedOff && actualOff { return .ignore }
        if !expectedOff && !actualOff && abs(expected - actual) <= tolerance { return .ignore }

        let automationInCharge: Bool
        switch source {
        case .ramp, .automation, .override: automationInCharge = true
        case .manual, .off: automationInCharge = false
        }
        // macOS switches a manually enabled Night Shift off at its "day start" time. When NightMode's
        // automation is in charge that is not a user decision, so put the level back.
        if automationInCharge, actualOff, !expectedOff, let dayStart = systemDayStart,
           isNear(now, hour: dayStart.hour, minute: dayStart.minute, calendar: calendar, window: dayStartWindow) {
            return .reassert
        }
        return .adopt(actual)
    }

    static func isNear(_ date: Date, hour: Int, minute: Int, calendar: Calendar, window: TimeInterval) -> Bool {
        for dayOffset in [-1, 0, 1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: date),
                  let mark = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))
            else { continue }
            if abs(mark.timeIntervalSince(date)) <= window { return true }
        }
        return false
    }
}

/// How to start up without a visible jump.
public enum LaunchReconciliation {
    public enum Action: Equatable, Sendable {
        /// Take Night Shift's current level as the manual level (no change on screen).
        case adoptActual
        /// Move the screen to NightMode's computed level (gently).
        case applyEvaluation
    }

    public static func decide(evaluation: Evaluation, actual: Double, tintWasTurnedOffOnQuit: Bool) -> Action {
        if tintWasTurnedOffOnQuit && actual < Level.offThreshold { return .applyEvaluation }
        switch evaluation.source {
        case .manual:
            return .adoptActual
        case .off:
            return actual >= Level.offThreshold ? .adoptActual : .applyEvaluation
        case .ramp, .override, .automation:
            return .applyEvaluation
        }
    }
}
