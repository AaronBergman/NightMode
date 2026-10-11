import Foundation

/// A place with a human-readable name, used for sunrise and sunset.
public struct NamedLocation: Codable, Equatable, Sendable {
    public var name: String
    public var coordinate: GeoCoordinate

    public init(name: String, coordinate: GeoCoordinate) {
        self.name = name
        self.coordinate = coordinate
    }
}

/// The last values used in the Ramp form, so it reopens the way it was left.
public struct RampDraft: Codable, Equatable, Sendable {
    public var fromCurrent: Bool = true
    public var fromLevel: Double = 0
    public var toLevel: Double = 100
    public var minutes: Double = 30
    public var startNow: Bool = true
    public var startHour: Int = 21
    public var startMinute: Int = 0
    public var easing: Easing = .linear

    public init() {}

    enum CodingKeys: String, CodingKey { case fromCurrent, fromLevel, toLevel, minutes, startNow, startHour, startMinute, easing }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromCurrent = try c.decodeIfPresent(Bool.self, forKey: .fromCurrent) ?? true
        fromLevel = try c.decodeIfPresent(Double.self, forKey: .fromLevel) ?? 0
        toLevel = try c.decodeIfPresent(Double.self, forKey: .toLevel) ?? 100
        minutes = try c.decodeIfPresent(Double.self, forKey: .minutes) ?? 30
        startNow = try c.decodeIfPresent(Bool.self, forKey: .startNow) ?? true
        startHour = try c.decodeIfPresent(Int.self, forKey: .startHour) ?? 21
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? 0
        easing = (try? c.decodeIfPresent(Easing.self, forKey: .easing)) ?? .linear
    }
}

public enum QuitBehavior: String, Codable, CaseIterable, Sendable {
    /// Leave Night Shift exactly as it is (it is a system setting and persists).
    case leaveTint
    /// Switch Night Shift off when NightMode quits.
    case turnTintOff
}

public struct Preferences: Codable, Equatable, Sendable {
    public var showPercentInMenuBar: Bool = false
    public var hotkeysEnabled: Bool = true
    public var quitBehavior: QuitBehavior = .leaveTint
    /// A location typed in by the user. Nil means "approximate from the time zone".
    public var manualLocation: NamedLocation?
    public var rampDraft = RampDraft()

    public init() {}

    enum CodingKeys: String, CodingKey { case showPercentInMenuBar, hotkeysEnabled, quitBehavior, manualLocation, rampDraft }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPercentInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showPercentInMenuBar) ?? false
        hotkeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled) ?? true
        quitBehavior = (try? c.decodeIfPresent(QuitBehavior.self, forKey: .quitBehavior)) ?? .leaveTint
        manualLocation = try? c.decodeIfPresent(NamedLocation.self, forKey: .manualLocation)
        rampDraft = (try? c.decodeIfPresent(RampDraft.self, forKey: .rampDraft)) ?? RampDraft()
    }
}

/// Everything NightMode saves.
public struct AppState: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int = AppState.currentVersion
    public var engine: EngineState
    public var prefs: Preferences
    /// Set when the "turn the tint off when quitting" option switched Night Shift off, so the next
    /// launch restores the level instead of adopting "off".
    public var tintWasTurnedOffOnQuit: Bool = false

    public init(engine: EngineState = AppState.defaultEngine(), prefs: Preferences = Preferences()) {
        self.engine = engine
        self.prefs = prefs
    }

    /// First-run state: everything off, with the "Gentle evening" schedule ready to switch on.
    public static func defaultEngine() -> EngineState {
        EngineState(schedule: Schedule(isEnabled: false, transitions: Presets.gentleEvening()))
    }

    enum CodingKeys: String, CodingKey { case version, engine, prefs, tintWasTurnedOffOnQuit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? AppState.currentVersion
        engine = (try? c.decodeIfPresent(EngineState.self, forKey: .engine)) ?? AppState.defaultEngine()
        prefs = (try? c.decodeIfPresent(Preferences.self, forKey: .prefs)) ?? Preferences()
        tintWasTurnedOffOnQuit = try c.decodeIfPresent(Bool.self, forKey: .tintWasTurnedOffOnQuit) ?? false
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> AppState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(AppState.self, from: data)
    }
}
