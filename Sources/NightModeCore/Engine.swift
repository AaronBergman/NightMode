import Foundation

/// What a manual change does while automation (schedule or brightness) is on.
public enum PausePolicy: String, Codable, CaseIterable, Sendable {
    /// Hold the manual level until the next scheduled change starts (or, when following brightness,
    /// until the brightness moves noticeably).
    case untilNextChange
    /// Hold the manual level for one hour.
    case oneHour
    /// Hold the manual level until "Resume Automation" is chosen.
    case untilResume
}

/// A manual level that temporarily pauses automation.
public struct Override: Codable, Equatable, Sendable {
    public var level: Double
    public var since: Date
    /// Automation resumes at this instant. Nil means no time limit.
    public var until: Date?
    /// Automation also resumes once display brightness moves this far from the anchor.
    public var brightnessAnchor: Double?

    public init(level: Double, since: Date, until: Date?, brightnessAnchor: Double?) {
        self.level = Level.clamp(level)
        self.since = since
        self.until = until
        self.brightnessAnchor = brightnessAnchor
    }
}

/// Inputs from the outside world. Injected so the engine is testable with fixed clocks and fake sensors.
public struct EngineEnvironment: Sendable {
    public var calendar: Calendar
    public var location: GeoCoordinate?
    /// Built-in display brightness 0...1, or nil if it cannot be read.
    public var brightness: Double?

    public init(calendar: Calendar, location: GeoCoordinate?, brightness: Double?) {
        self.calendar = calendar
        self.location = location
        self.brightness = brightness
    }

    public var scheduleContext: ScheduleContext { ScheduleContext(calendar: calendar, location: location) }
}

/// Which automation input is setting the level.
public enum Driver: String, Equatable, Sendable {
    case schedule
    case brightness
}

public struct AutomationStatus: Equatable, Sendable {
    public var scheduleLevel: Double?
    public var brightnessLevel: Double?
    public var scheduleState: ScheduleState?
    public var nextScheduleChange: Occurrence?
    public var driver: Driver
    public var level: Double

    public init(scheduleLevel: Double?, brightnessLevel: Double?, scheduleState: ScheduleState?,
                nextScheduleChange: Occurrence?, driver: Driver, level: Double) {
        self.scheduleLevel = scheduleLevel
        self.brightnessLevel = brightnessLevel
        self.scheduleState = scheduleState
        self.nextScheduleChange = nextScheduleChange
        self.driver = driver
        self.level = level
    }
}

/// Why the level is what it is.
public enum LevelSource: Equatable, Sendable {
    /// NightMode is switched off (until a time, or until switched back on).
    case off(until: Date?)
    /// No automation: the level is whatever was set by hand.
    case manual
    /// A one-off ramp is running.
    case ramp(Ramp)
    /// A manual change is pausing automation. Carries what automation would do, if anything.
    case override(Override, AutomationStatus?)
    /// The schedule and/or brightness curve is in control.
    case automation(AutomationStatus)
}

public struct Evaluation: Equatable, Sendable {
    /// The level to show right now.
    public var level: Double
    /// The level ignoring "off" (shown on the slider while NightMode is off).
    public var underlyingLevel: Double
    public var source: LevelSource
    /// When the result may change by itself (a ramp step, a scheduled change, an expiry). Nil if never.
    public var nextCheck: Date?
    /// True while the level is moving continuously (ramps): apply directly, no extra smoothing.
    public var isContinuous: Bool
    /// A ramp that is set to start later.
    public var pendingRamp: Ramp?

    public init(level: Double, underlyingLevel: Double, source: LevelSource, nextCheck: Date?,
                isContinuous: Bool, pendingRamp: Ramp?) {
        self.level = level
        self.underlyingLevel = underlyingLevel
        self.source = source
        self.nextCheck = nextCheck
        self.isContinuous = isContinuous
        self.pendingRamp = pendingRamp
    }
}

/// The full automation state. Everything is plain data with absolute dates, so it can be saved and
/// restored at any time and evaluated for any instant.
///
/// Precedence, highest first:
/// 1. Off (switched off, or "off for an hour").
/// 2. A running one-off ramp.
/// 3. An override: a manual change made while automation is on. It pauses automation per `pausePolicy`.
/// 4. Automation: the schedule and the brightness curve. When both are on, the warmer one wins.
/// 5. The manual level.
public struct EngineState: Codable, Equatable, Sendable {
    public var isOn: Bool
    public var offUntil: Date?
    public var manualLevel: Double
    public var ramp: Ramp?
    public var override: Override?
    public var schedule: Schedule
    public var brightness: BrightnessConfig
    public var pausePolicy: PausePolicy

    /// Following brightness resumes after a manual change once brightness moves this much (15 points).
    public static let brightnessResumeThreshold: Double = 0.15

    public init(isOn: Bool = true, offUntil: Date? = nil, manualLevel: Double = 0, ramp: Ramp? = nil,
                override: Override? = nil, schedule: Schedule = Schedule(), brightness: BrightnessConfig = BrightnessConfig(),
                pausePolicy: PausePolicy = .untilNextChange) {
        self.isOn = isOn
        self.offUntil = offUntil
        self.manualLevel = Level.clamp(manualLevel)
        self.ramp = ramp
        self.override = override
        self.schedule = schedule
        self.brightness = brightness
        self.pausePolicy = pausePolicy
    }

    /// Automation is configured (regardless of whether its inputs are available right now).
    public var isAutomationEnabled: Bool {
        (schedule.isEnabled && schedule.hasActiveTransitions) || brightness.isEnabled
    }

    /// Automation is configured and has something to work with right now.
    public func isAutomationActive(_ env: EngineEnvironment) -> Bool {
        (schedule.isEnabled && schedule.hasActiveTransitions) || (brightness.isEnabled && env.brightness != nil)
    }

    // MARK: - Evaluation

    public func evaluate(now: Date, env: EngineEnvironment) -> Evaluation {
        var base = evaluateIgnoringOff(now: now, env: env)
        if !isOn {
            base.source = .off(until: nil)
            base.level = 0
            base.isContinuous = false
            return base
        }
        if let until = offUntil, now < until {
            base.source = .off(until: until)
            base.level = 0
            base.isContinuous = false
            base.nextCheck = min(base.nextCheck ?? until, until)
            return base
        }
        return base
    }

    /// The level NightMode would show if it were on.
    public func evaluateIgnoringOff(now: Date, env: EngineEnvironment) -> Evaluation {
        var checks: [Date] = []
        var pending: Ramp?

        if var ramp {
            if ramp.isPending(at: now) {
                pending = ramp
                checks.append(ramp.start)
            } else {
                if ramp.resolvedFrom == nil {
                    var without = self
                    without.ramp = nil
                    ramp.resolvedFrom = without.evaluateIgnoringOff(now: ramp.start, env: env).level
                }
                if let segment = ramp.segment {
                    if !ramp.isFinished(at: now) {
                        let level = segment.value(at: now)
                        return Evaluation(level: level, underlyingLevel: level, source: .ramp(ramp),
                                          nextCheck: Stepping.nextUpdate(for: segment, now: now),
                                          isContinuous: true, pendingRamp: nil)
                    }
                    // Finished but not folded in by advance() yet: hold its target.
                    return Evaluation(level: ramp.to, underlyingLevel: ramp.to, source: .ramp(ramp),
                                      nextCheck: now, isContinuous: false, pendingRamp: nil)
                }
            }
        }

        let auto = automation(now: now, env: env)

        if let override {
            if let until = override.until { checks.append(until) }
            return Evaluation(level: override.level, underlyingLevel: override.level,
                              source: .override(override, auto?.status), nextCheck: checks.min(),
                              isContinuous: false, pendingRamp: pending)
        }

        if let auto {
            if let next = auto.nextCheck { checks.append(next) }
            return Evaluation(level: auto.status.level, underlyingLevel: auto.status.level,
                              source: .automation(auto.status), nextCheck: checks.min(),
                              isContinuous: auto.continuous, pendingRamp: pending)
        }

        return Evaluation(level: manualLevel, underlyingLevel: manualLevel, source: .manual,
                          nextCheck: checks.min(), isContinuous: false, pendingRamp: pending)
    }

    struct AutomationResult {
        var status: AutomationStatus
        var nextCheck: Date?
        var continuous: Bool
    }

    func automation(now: Date, env: EngineEnvironment) -> AutomationResult? {
        var scheduleLevel: Double?
        var state: ScheduleState?
        var next: Occurrence?
        if schedule.isEnabled && schedule.hasActiveTransitions {
            let context = env.scheduleContext
            state = schedule.state(at: now, context: context)
            scheduleLevel = state?.level
            next = schedule.nextOccurrence(after: now, context: context)
        }
        var brightnessLevel: Double?
        if brightness.isEnabled, let b = env.brightness {
            brightnessLevel = brightness.curve.level(forBrightness: b)
        }
        guard scheduleLevel != nil || brightnessLevel != nil else { return nil }

        let s = scheduleLevel ?? -1
        let b = brightnessLevel ?? -1
        let driver: Driver = s >= b ? .schedule : .brightness
        let level = max(s, b)

        var nextCheck = next?.start
        var continuous = false
        if let state, state.isRamping(at: now) {
            let step = Stepping.nextUpdate(for: state.segment, now: now)
            nextCheck = min(nextCheck ?? step, step)
            continuous = driver == .schedule
        }
        let status = AutomationStatus(scheduleLevel: scheduleLevel, brightnessLevel: brightnessLevel,
                                      scheduleState: state, nextScheduleChange: next, driver: driver, level: level)
        return AutomationResult(status: status, nextCheck: nextCheck, continuous: continuous)
    }

    // MARK: - Time passing

    /// Applies everything that happens by itself with time: expiring "off for an hour", starting and
    /// finishing ramps, expiring overrides. Call before `evaluate`. Returns true if anything changed.
    @discardableResult
    public mutating func advance(now: Date, env: EngineEnvironment) -> Bool {
        let before = self

        if let until = offUntil, now >= until { offUntil = nil }

        if var ramp {
            if ramp.resolvedFrom == nil, now >= ramp.start {
                var without = self
                without.ramp = nil
                ramp.resolvedFrom = without.evaluateIgnoringOff(now: ramp.start, env: env).level
                self.ramp = ramp
            }
            if ramp.resolvedFrom != nil, ramp.isFinished(at: now) {
                self.ramp = nil
                // The ramp's end level is held from the moment it ended. If the Mac slept through the
                // next scheduled change too, the hold has already expired and automation takes over.
                hold(level: ramp.to, at: ramp.end, env: env)
            }
        }

        if let override {
            if let until = override.until, now >= until {
                self.override = nil
            } else if let anchor = override.brightnessAnchor, let b = env.brightness,
                      abs(b - anchor) >= Self.brightnessResumeThreshold {
                self.override = nil
            } else if !isAutomationEnabled {
                manualLevel = override.level
                self.override = nil
            }
        }

        return self != before
    }

    // MARK: - User actions

    /// A manual level change (slider, preset, nudge, shortcut). Switches NightMode on, takes over from
    /// a running ramp, and pauses automation per `pausePolicy`.
    public mutating func setLevel(_ level: Double, now: Date, env: EngineEnvironment) {
        let value = Level.clamp(level)
        if let ramp, !ramp.isPending(at: now) { self.ramp = nil }
        isOn = true
        offUntil = nil
        hold(level: value, at: now, env: env)
    }

    /// Nudge from the level currently shown (rounded to a whole percent first).
    public mutating func nudge(by delta: Double, now: Date, env: EngineEnvironment) {
        let base = evaluateIgnoringOff(now: now, env: env).level.rounded()
        setLevel(base + delta, now: now, env: env)
    }

    public mutating func startRamp(origin: Ramp.Origin, to target: Double, start: Date, duration: TimeInterval,
                                   easing: Easing = .linear, now: Date, env: EngineEnvironment) {
        var ramp = Ramp(origin: origin, to: target, start: start, duration: duration, easing: easing)
        if ramp.resolvedFrom == nil, start <= now {
            ramp.resolvedFrom = evaluateIgnoringOff(now: now, env: env).level
        }
        self.ramp = ramp
        isOn = true
        offUntil = nil
    }

    /// Stops a running ramp where it is (that level is then held like a manual change), or removes a pending one.
    public mutating func cancelRamp(now: Date, env: EngineEnvironment) {
        guard let ramp else { return }
        self.ramp = nil
        if !ramp.isPending(at: now) {
            var probe = self
            probe.ramp = ramp
            let level = probe.evaluateIgnoringOff(now: now, env: env).level
            hold(level: level, at: now, env: env)
        }
    }

    public mutating func resumeAutomation() {
        override = nil
    }

    public mutating func setOn(_ on: Bool) {
        isOn = on
        offUntil = nil
    }

    public mutating func turnOff(for duration: TimeInterval, now: Date) {
        isOn = true
        offUntil = now.addingTimeInterval(max(0, duration))
    }

    public mutating func setScheduleEnabled(_ enabled: Bool, now: Date, env: EngineEnvironment) {
        let previous = evaluateIgnoringOff(now: now, env: env).level
        schedule.isEnabled = enabled
        automationChanged(turnedOn: enabled, previousLevel: previous)
    }

    public mutating func setBrightnessEnabled(_ enabled: Bool, now: Date, env: EngineEnvironment) {
        let previous = evaluateIgnoringOff(now: now, env: env).level
        brightness.isEnabled = enabled
        automationChanged(turnedOn: enabled, previousLevel: previous)
    }

    /// Replaces the schedule's transitions (keeps any running ramp; refreshes an override's expiry).
    public mutating func setTransitions(_ transitions: [Transition], now: Date, env: EngineEnvironment) {
        let previous = evaluateIgnoringOff(now: now, env: env).level
        schedule.transitions = transitions
        if !isAutomationEnabled {
            manualLevel = previous
            override = nil
        } else {
            refreshOverrideExpiry(env: env)
        }
    }

    public mutating func setPausePolicy(_ policy: PausePolicy, env: EngineEnvironment) {
        pausePolicy = policy
        refreshOverrideExpiry(env: env)
    }

    // MARK: - Helpers

    mutating func automationChanged(turnedOn: Bool, previousLevel: Double) {
        if turnedOn {
            // A fresh start: automation takes over right away.
            override = nil
            isOn = true
            offUntil = nil
        } else if !isAutomationEnabled {
            // Back to manual without a jump: keep whatever level automation had reached.
            manualLevel = previousLevel
            override = nil
        }
    }

    mutating func hold(level: Double, at time: Date, env: EngineEnvironment) {
        manualLevel = Level.clamp(level)
        override = isAutomationActive(env) ? makeOverride(level: level, at: time, env: env) : nil
    }

    func makeOverride(level: Double, at time: Date, env: EngineEnvironment) -> Override {
        switch pausePolicy {
        case .untilNextChange:
            var until: Date?
            if schedule.isEnabled && schedule.hasActiveTransitions {
                until = schedule.nextOccurrence(after: time, context: env.scheduleContext)?.start
            }
            let anchor = brightness.isEnabled ? env.brightness : nil
            return Override(level: level, since: time, until: until, brightnessAnchor: anchor)
        case .oneHour:
            return Override(level: level, since: time, until: time.addingTimeInterval(3600), brightnessAnchor: nil)
        case .untilResume:
            return Override(level: level, since: time, until: nil, brightnessAnchor: nil)
        }
    }

    mutating func refreshOverrideExpiry(env: EngineEnvironment) {
        guard let current = override else { return }
        var fresh = makeOverride(level: current.level, at: current.since, env: env)
        if current.brightnessAnchor != nil, fresh.brightnessAnchor != nil {
            fresh.brightnessAnchor = current.brightnessAnchor
        }
        override = fresh
    }

    // MARK: - Codable (tolerant of missing keys so future versions can add fields)

    enum CodingKeys: String, CodingKey {
        case isOn, offUntil, manualLevel, ramp, override, schedule, brightness, pausePolicy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? true
        offUntil = try c.decodeIfPresent(Date.self, forKey: .offUntil)
        manualLevel = Level.clamp(try c.decodeIfPresent(Double.self, forKey: .manualLevel) ?? 0)
        ramp = try? c.decodeIfPresent(Ramp.self, forKey: .ramp)
        override = try? c.decodeIfPresent(Override.self, forKey: .override)
        schedule = (try? c.decodeIfPresent(Schedule.self, forKey: .schedule)) ?? Schedule()
        brightness = (try? c.decodeIfPresent(BrightnessConfig.self, forKey: .brightness)) ?? BrightnessConfig()
        pausePolicy = (try? c.decodeIfPresent(PausePolicy.self, forKey: .pausePolicy)) ?? .untilNextChange
    }
}
