import AppKit
import NightModeCore

public struct ClockTime: Equatable, Sendable {
    public var hour: Int
    public var minute: Int
}

/// Night Shift's state as reported by CoreBrightness.
public struct NightShiftStatus: Equatable, Sendable {
    public var isEnabled: Bool
    /// 0...1
    public var strength: Double
    /// macOS's own schedule: 0 off, 1 sunset to sunrise, 2 custom.
    public var scheduleMode: Int
    public var nightStart: ClockTime
    public var dayStart: ClockTime

    /// NightMode's level for this state: 0 when off.
    public var level: Double { isEnabled ? Level.clamp(strength * 100) : 0 }

    public var hasSystemSchedule: Bool { scheduleMode != 0 }

    public var systemScheduleName: String {
        switch scheduleMode {
        case 1: return "Sunset to Sunrise"
        case 2: return "Custom"
        default: return "Off"
        }
    }
}

/// Something that can tint the screen. The real one drives Night Shift; tests and screenshots use a mock.
public protocol TintBackend: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func readStatus() -> NightShiftStatus?
    /// 0...100. Levels below `Level.offThreshold` switch Night Shift off.
    func apply(level: Double)
    /// Switches macOS's own Night Shift schedule off so it does not fight NightMode.
    func turnOffSystemSchedule()
    /// Kelvin at 100% and at 0% strength, if known.
    var temperatureRange: (warmest: Double, coolest: Double)? { get }
    /// Called (on the main queue) when Night Shift's on/off state or schedule changes, from any app.
    var onStatusChange: (() -> Void)? { get set }
}

/// Drives Night Shift through CoreBrightness's `CBBlueLightClient` (a private framework, the same
/// one System Settings and Control Center use). Every call is guarded, so a future macOS that
/// changes the class makes NightMode report "unavailable" instead of crashing.
public final class NightShiftBackend: TintBackend {
    private let client: NSObject?
    public private(set) var unavailableReason: String?
    public var onStatusChange: (() -> Void)?

    public init() {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"), bundle.load(),
              let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            client = nil
            unavailableReason = "This version of macOS does not expose Night Shift controls (CoreBrightness could not be loaded)."
            return
        }
        let client = cls.init()
        self.client = client
        let required = ["getBlueLightStatus:", "getStrength:", "setStrength:commit:", "setEnabled:"]
        if let missing = required.first(where: { !client.responds(to: NSSelectorFromString($0)) }) {
            unavailableReason = "Night Shift's controls changed in this version of macOS (missing \(missing))."
            return
        }
        if let supported = callBool("supported"), !supported {
            unavailableReason = "Night Shift is not supported on this Mac or display."
            return
        }
        installNotificationBlock()
    }

    public var isAvailable: Bool { client != nil && unavailableReason == nil }

    public func readStatus() -> NightShiftStatus? {
        guard isAvailable, let client else { return nil }
        // struct { BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode;
        //          struct { struct {int hour, minute} from, to } schedule; uint64 disableFlags; BOOL available; }
        var buffer = [UInt8](repeating: 0, count: 64)
        let sel = NSSelectorFromString("getBlueLightStatus:")
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, raw.baseAddress!)
        }
        guard ok else { return nil }
        func int32(at offset: Int) -> Int {
            buffer.withUnsafeBytes { Int($0.load(fromByteOffset: offset, as: Int32.self)) }
        }
        var strength: Float = 0
        let strengthSel = NSSelectorFromString("getStrength:")
        typealias StrengthFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool
        _ = unsafeBitCast(client.method(for: strengthSel), to: StrengthFn.self)(client, strengthSel, &strength)
        return NightShiftStatus(isEnabled: buffer[1] != 0,
                                strength: Double(min(1, max(0, strength.isFinite ? strength : 0))),
                                scheduleMode: int32(at: 4),
                                nightStart: ClockTime(hour: int32(at: 8), minute: int32(at: 12)),
                                dayStart: ClockTime(hour: int32(at: 16), minute: int32(at: 20)))
    }

    public func apply(level: Double) {
        guard isAvailable, let client else { return }
        let value = Level.clamp(level)
        let enabled = readStatus()?.isEnabled ?? false
        if value < Level.offThreshold {
            if enabled { setEnabled(client, false) }
        } else {
            // Strength first, then enable, so switching on never flashes the previous strength.
            let sel = NSSelectorFromString("setStrength:commit:")
            typealias Fn = @convention(c) (AnyObject, Selector, Float, Bool) -> Bool
            _ = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, Float(value / 100), true)
            if !enabled { setEnabled(client, true) }
        }
    }

    public func turnOffSystemSchedule() {
        guard isAvailable, let client else { return }
        let sel = NSSelectorFromString("setMode:")
        guard client.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Int32) -> Bool
        _ = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, 0)
    }

    public var temperatureRange: (warmest: Double, coolest: Double)? {
        guard isAvailable, let client else { return nil }
        let sel = NSSelectorFromString("getCCTRange:")
        guard client.responds(to: sel) else { return nil }
        var range = [Float](repeating: 0, count: 4)
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let ok = range.withUnsafeMutableBytes { unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, $0.baseAddress!) }
        guard ok, range[0] > 1000, range[1] > range[0] else { return nil }
        return (Double(range[0]), Double(range[1]))
    }

    // MARK: - Private

    private func setEnabled(_ client: NSObject, _ on: Bool) {
        let sel = NSSelectorFromString("setEnabled:")
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, on)
    }

    private func callBool(_ name: String) -> Bool? {
        guard let client else { return nil }
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel)
    }

    private func installNotificationBlock() {
        guard let client else { return }
        let sel = NSSelectorFromString("setStatusNotificationBlock:")
        guard client.responds(to: sel) else { return }
        let block: @convention(block) () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.onStatusChange?() }
        }
        typealias Fn = @convention(c) (AnyObject, Selector, @convention(block) () -> Void) -> Void
        unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, block)
        let enable = NSSelectorFromString("enableNotifications")
        if client.responds(to: enable) { _ = client.perform(enable) }
    }
}

/// An in-memory stand-in used by screenshots and tests. Never touches the real display.
public final class MockTintBackend: TintBackend {
    public var status: NightShiftStatus
    public var applied: [Double] = []
    public var isAvailable = true
    public var unavailableReason: String?
    public var onStatusChange: (() -> Void)?
    public var temperatureRange: (warmest: Double, coolest: Double)? = (2700, 6000)

    public init(level: Double = 0) {
        status = NightShiftStatus(isEnabled: level >= Level.offThreshold, strength: level / 100, scheduleMode: 0,
                                  nightStart: ClockTime(hour: 22, minute: 0), dayStart: ClockTime(hour: 7, minute: 0))
    }

    public func readStatus() -> NightShiftStatus? { status }

    public func apply(level: Double) {
        applied.append(level)
        if level < Level.offThreshold {
            status.isEnabled = false
        } else {
            status.strength = level / 100
            status.isEnabled = true
        }
    }

    public func turnOffSystemSchedule() { status.scheduleMode = 0 }
}
