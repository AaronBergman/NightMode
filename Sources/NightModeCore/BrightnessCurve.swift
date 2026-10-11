import Foundation

/// One point of the brightness-to-tint mapping.
public struct CurvePoint: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Display brightness, 0...1 (the position of the system brightness slider).
    public var brightness: Double
    /// Tint level at that brightness, 0...100.
    public var level: Double

    public init(id: UUID = UUID(), brightness: Double, level: Double) {
        self.id = id
        self.brightness = min(1, max(0, brightness))
        self.level = Level.clamp(level)
    }
}

/// Maps display brightness to a tint level: piecewise linear between points, flat beyond the ends.
public struct BrightnessCurve: Codable, Equatable, Sendable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points
    }

    /// Dim screen, warm tint; bright screen, no tint.
    public static let standard = BrightnessCurve(points: [
        CurvePoint(brightness: 0.10, level: 85),
        CurvePoint(brightness: 0.35, level: 45),
        CurvePoint(brightness: 0.70, level: 0),
    ])

    public var sortedPoints: [CurvePoint] {
        points.sorted { $0.brightness < $1.brightness }
    }

    public func level(forBrightness rawBrightness: Double) -> Double {
        let b = min(1, max(0, rawBrightness.isFinite ? rawBrightness : 0))
        let pts = sortedPoints
        guard let first = pts.first, let last = pts.last else { return 0 }
        if b <= first.brightness { return first.level }
        if b >= last.brightness { return last.level }
        for (a, c) in zip(pts, pts.dropFirst()) where b <= c.brightness {
            let span = c.brightness - a.brightness
            if span <= 0 { return c.level }
            return Level.clamp(a.level + (c.level - a.level) * (b - a.brightness) / span)
        }
        return last.level
    }
}

public struct BrightnessConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var curve: BrightnessCurve

    public init(isEnabled: Bool = false, curve: BrightnessCurve = .standard) {
        self.isEnabled = isEnabled
        self.curve = curve
    }

    enum CodingKeys: String, CodingKey { case isEnabled, curve }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        curve = try c.decodeIfPresent(BrightnessCurve.self, forKey: .curve) ?? .standard
    }
}
