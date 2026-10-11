import Foundation

/// Tint levels are percentages from 0 (no tint) to 100 (Night Shift's warmest setting).
public enum Level {
    public static let range: ClosedRange<Double> = 0...100

    /// Levels below this are applied as "Night Shift off" (v1 used the same cut-off).
    public static let offThreshold: Double = 0.5

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    /// The whole-number percentage shown in the UI.
    public static func display(_ value: Double) -> Int {
        Int(clamp(value).rounded())
    }

    public static func format(_ value: Double) -> String {
        "\(display(value))%"
    }
}

/// How a level moves between two values over time.
public enum Easing: String, Codable, CaseIterable, Sendable {
    /// Constant speed.
    case linear
    /// Starts and finishes gently (smoothstep).
    case smooth

    public func apply(_ t: Double) -> Double {
        let x = min(1, max(0, t.isFinite ? t : 0))
        switch self {
        case .linear: return x
        case .smooth: return x * x * (3 - 2 * x)
        }
    }

    /// Steepest slope of the curve relative to linear (used to pick update intervals).
    public var maxSlope: Double {
        switch self {
        case .linear: return 1
        case .smooth: return 1.5
        }
    }
}

/// A straight (or eased) move from one level to another between two instants.
/// All maths is done from wall-clock dates, so a segment keeps its place across sleep and relaunch.
public struct Segment: Codable, Equatable, Sendable {
    public var from: Double
    public var to: Double
    public var start: Date
    public var duration: TimeInterval
    public var easing: Easing

    public init(from: Double, to: Double, start: Date, duration: TimeInterval, easing: Easing = .linear) {
        self.from = Level.clamp(from)
        self.to = Level.clamp(to)
        self.start = start
        self.duration = max(0, duration.isFinite ? duration : 0)
        self.easing = easing
    }

    /// A segment that just holds one level.
    public static func constant(_ level: Double, since start: Date = .distantPast) -> Segment {
        Segment(from: level, to: level, start: start, duration: 0)
    }

    public var end: Date { start.addingTimeInterval(duration) }

    public func progress(at now: Date) -> Double {
        if duration <= 0 { return now >= start ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }

    public func value(at now: Date) -> Double {
        if now <= start { return from }
        return Level.clamp(from + (to - from) * easing.apply(progress(at: now)))
    }

    /// True while the level is actually changing at `now`.
    public func isMoving(at now: Date) -> Bool {
        duration > 0 && now >= start && now < end && abs(to - from) > 0.0001
    }
}

/// A one-off gradual change the user started, e.g. "from the current level to 100% over 30 minutes".
public struct Ramp: Codable, Equatable, Sendable {
    public enum Origin: Codable, Equatable, Sendable {
        /// Start from whatever the level is when the ramp begins.
        case current
        /// Start from a specific level.
        case fixed(Double)
    }

    public var origin: Origin
    /// The concrete starting level. Fixed origins resolve immediately; `.current` resolves when the ramp begins.
    public var resolvedFrom: Double?
    public var to: Double
    public var start: Date
    public var duration: TimeInterval
    public var easing: Easing

    public init(origin: Origin, to: Double, start: Date, duration: TimeInterval, easing: Easing = .linear) {
        self.origin = origin
        self.to = Level.clamp(to)
        self.start = start
        self.duration = max(0, duration.isFinite ? duration : 0)
        self.easing = easing
        if case .fixed(let level) = origin { resolvedFrom = Level.clamp(level) }
    }

    public var end: Date { start.addingTimeInterval(duration) }

    public func isPending(at now: Date) -> Bool { now < start }
    public func isFinished(at now: Date) -> Bool { now >= end }

    public func progress(at now: Date) -> Double {
        if duration <= 0 { return now >= start ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    /// The ramp's level at `now`, or nil if it has not started (or its origin is not resolved yet).
    public func level(at now: Date) -> Double? {
        guard let segment = segment, now >= start else { return nil }
        return segment.value(at: now)
    }

    public var segment: Segment? {
        guard let from = resolvedFrom else { return nil }
        return Segment(from: from, to: to, start: start, duration: duration, easing: easing)
    }
}

/// Picks how often to push new values to the display while something is moving.
public enum Stepping {
    /// Seconds between updates so each update changes the level by roughly `resolution` percentage points.
    /// Clamped to `[minimum, maximum]` so short ramps stay smooth and long ramps stay cheap.
    public static func interval(for segment: Segment,
                                resolution: Double = 0.25,
                                minimum: TimeInterval = 1,
                                maximum: TimeInterval = 60) -> TimeInterval {
        let delta = abs(segment.to - segment.from)
        guard segment.duration > 0, delta > 0 else { return maximum }
        let fastestRate = delta / segment.duration * segment.easing.maxSlope // points per second
        let interval = resolution / fastestRate
        return min(maximum, max(minimum, interval))
    }

    /// The next instant to re-evaluate a moving segment: one step ahead, but never past its end.
    public static func nextUpdate(for segment: Segment, now: Date, resolution: Double = 0.25) -> Date {
        let step = interval(for: segment, resolution: resolution)
        let next = now.addingTimeInterval(step)
        return min(next, max(segment.end, now.addingTimeInterval(0.05)))
    }
}
