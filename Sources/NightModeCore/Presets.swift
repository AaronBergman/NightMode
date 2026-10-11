import Foundation

/// Recommended one-click configurations shown in the Dynamic Options window.
public struct Preset: Identifiable, Sendable {
    public enum Action: Sendable {
        /// Start a one-off ramp right away.
        case ramp(origin: Ramp.Origin, to: Double, minutes: Double, easing: Easing)
        /// Replace the daily schedule with these transitions and switch it on.
        case schedule([Transition])
        /// Switch on brightness following with this curve.
        case followBrightness(BrightnessCurve)
    }

    public var id: String
    public var title: String
    public var summary: String
    /// SF Symbol name.
    public var symbol: String
    public var action: Action
    public var needsLocation: Bool = false
}

public enum Presets {
    public static func gentleEvening() -> [Transition] {
        [
            Transition(anchor: .clock(hour: 20, minute: 0), target: 40, durationMinutes: 60),
            Transition(anchor: .clock(hour: 22, minute: 0), target: 70, durationMinutes: 60),
            Transition(anchor: .clock(hour: 7, minute: 0), target: 0, durationMinutes: 30),
        ]
    }

    public static func sunsetToSunrise() -> [Transition] {
        [
            Transition(anchor: .sunset(offsetMinutes: -30), target: 50, durationMinutes: 90),
            Transition(anchor: .clock(hour: 23, minute: 0), target: 80, durationMinutes: 60),
            Transition(anchor: .sunrise(offsetMinutes: 0), target: 0, durationMinutes: 45),
        ]
    }

    public static func deepNight() -> [Transition] {
        [
            Transition(anchor: .clock(hour: 21, minute: 0), target: 60, durationMinutes: 60),
            Transition(anchor: .clock(hour: 23, minute: 0), target: 100, durationMinutes: 90),
            Transition(anchor: .clock(hour: 7, minute: 0), target: 0, durationMinutes: 30),
        ]
    }

    public static let recommended: [Preset] = [
        Preset(id: "gradual-100", title: "Gradual to 100%",
               summary: "From the current level to 100% over 30 minutes, starting now.",
               symbol: "arrow.up.right", action: .ramp(origin: .current, to: 100, minutes: 30, easing: .linear)),
        Preset(id: "gentle-evening", title: "Gentle evening",
               summary: "Daily: 40% by 21:00, 70% by 23:00, back to 0% by 07:30.",
               symbol: "sunset", action: .schedule(gentleEvening())),
        Preset(id: "sun", title: "Sunset to sunrise",
               summary: "Daily: warms from 30 min before sunset, 80% by midnight, clears after sunrise.",
               symbol: "sun.horizon", action: .schedule(sunsetToSunrise()), needsLocation: true),
        Preset(id: "brightness", title: "Follow brightness",
               summary: "The dimmer the screen, the warmer the tint (full tint at very low brightness).",
               symbol: "sun.max", action: .followBrightness(.standard)),
        Preset(id: "deep-night", title: "Deep night",
               summary: "Daily: 60% by 22:00, 100% by 00:30, back to 0% by 07:30.",
               symbol: "moon.stars", action: .schedule(deepNight())),
        Preset(id: "fade-out", title: "Fade out",
               summary: "From the current level to 0% over 15 minutes, starting now.",
               symbol: "arrow.down.right", action: .ramp(origin: .current, to: 0, minutes: 15, easing: .smooth)),
    ]
}
