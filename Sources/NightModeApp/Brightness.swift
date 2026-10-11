import AppKit
import CoreGraphics

/// Reads the built-in display's brightness (0...1, the position of the brightness slider).
public protocol BrightnessReader: AnyObject {
    /// The API exists on this Mac (the reading itself can still be unavailable, e.g. lid closed).
    var isSupported: Bool { get }
    var unsupportedReason: String? { get }
    func read() -> Double?
}

/// Uses `DisplayServicesGetBrightness` from the private DisplayServices framework, which is how
/// brightness is read on Apple Silicon (the old IOKit route no longer works there). Loaded with
/// dlopen so a missing symbol degrades to "unsupported" instead of failing to launch.
public final class DisplayServicesBrightness: BrightnessReader {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private let getBrightness: GetBrightness?
    public private(set) var unsupportedReason: String?

    public init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
           let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        } else {
            getBrightness = nil
            unsupportedReason = "This Mac does not offer a way to read display brightness (DisplayServices is missing)."
        }
        if getBrightness != nil, Self.builtInDisplay() == nil {
            // Not fatal: a closed lid or a desktop Mac. read() simply returns nil until a built-in display appears.
            unsupportedReason = nil
        }
    }

    public var isSupported: Bool { getBrightness != nil }

    public func read() -> Double? {
        guard let getBrightness, let display = Self.builtInDisplay() else { return nil }
        var value: Float = -1
        guard getBrightness(display, &value) == 0, value.isFinite, value >= 0, value <= 1.001 else { return nil }
        return Double(min(1, max(0, value)))
    }

    /// The built-in display, if it is on.
    public static func builtInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}

public final class MockBrightnessReader: BrightnessReader {
    public var value: Double?
    public var isSupported = true
    public var unsupportedReason: String?
    public init(_ value: Double?) { self.value = value }
    public func read() -> Double? { value }
}
