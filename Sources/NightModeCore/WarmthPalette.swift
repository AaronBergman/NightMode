import Foundation

/// A color in OKLab (Bjorn Ottosson, 2020). OKLab is close to perceptually uniform, so the Euclidean
/// distance between two colors approximates how different they look.
public struct OKLab: Equatable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    public var chroma: Double { (a * a + b * b).squareRoot() }

    /// Hue angle in degrees, 0 to 360.
    public var hueDegrees: Double {
        let h = atan2(b, a) * 180 / .pi
        return h < 0 ? h + 360 : h
    }

    public func distance(to other: OKLab) -> Double {
        let dL = L - other.L, da = a - other.a, db = b - other.b
        return (dL * dL + da * da + db * db).squareRoot()
    }

    public static func mix(_ x: OKLab, _ y: OKLab, _ t: Double) -> OKLab {
        OKLab(L: x.L + (y.L - x.L) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }
}

/// Gamma-encoded sRGB, components 0 to 1.
public struct SRGB: Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Small, dependency-free color science: the Planckian locus, sRGB, OKLab and WCAG contrast.
public enum ColorMath {
    /// CIE 1931 xy chromaticity of a blackbody radiator, from Krystek's (1985) rational approximation of the
    /// Planckian locus in CIE 1960 uv, valid from 1000 K to 15000 K. It matches the locus integrated from Planck's
    /// law and the CIE 1931 2 degree observer to within 0.0004 in x and y from 2000 K to 7000 K. (It is used
    /// instead of the Kim et al. cubic spline because it is one smooth formula: the spline's small seam at 4000 K
    /// showed up as a visible irregularity in the evenly spaced steps.)
    public static func planckianXY(kelvin: Double) -> (x: Double, y: Double) {
        let t = min(15000, max(1000, kelvin))
        let t2 = t * t
        let u = (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t2) / (1 + 8.42420235e-4 * t + 7.08145163e-7 * t2)
        let v = (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t2) / (1 - 2.89741816e-5 * t + 1.61456053e-7 * t2)
        let d = 2 * u - 8 * v + 4
        return (3 * u / d, 2 * v / d)
    }

    /// Linear sRGB (D65) of the chromaticity x, y at luminance Y = 1. Components can fall outside 0 to 1.
    public static func linearSRGB(x: Double, y: Double) -> SIMD3<Double> {
        let X = x / y, Y = 1.0, Z = (1 - x - y) / y
        return SIMD3(3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z,
                     -0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z,
                     0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z)
    }

    public static func oklab(linear c: SIMD3<Double>) -> OKLab {
        let l = 0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z
        let m = 0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z
        let s = 0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return OKLab(L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                     a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                     b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    /// Linear sRGB of an OKLab color. Components can fall outside 0 to 1 for out-of-gamut colors.
    public static func linear(_ lab: OKLab) -> SIMD3<Double> {
        let l_ = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m_ = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s_ = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// sRGB transfer function (linear to gamma-encoded), clamped to 0 to 1.
    public static func encode(_ v: Double) -> Double {
        let c = min(1, max(0, v))
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    public static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    public static func srgb(_ lab: OKLab) -> SRGB {
        let c = linear(lab)
        return SRGB(r: encode(c.x), g: encode(c.y), b: encode(c.z))
    }

    public static func oklab(_ c: SRGB) -> OKLab {
        oklab(linear: SIMD3(decode(c.r), decode(c.g), decode(c.b)))
    }

    /// WCAG 2 relative luminance.
    public static func relativeLuminance(_ c: SRGB) -> Double {
        0.2126 * decode(c.r) + 0.7152 * decode(c.g) + 0.0722 * decode(c.b)
    }

    /// WCAG 2 contrast ratio, 1 to 21.
    public static func contrastRatio(_ x: SRGB, _ y: SRGB) -> Double {
        let a = relativeLuminance(x), b = relativeLuminance(y)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The colors NightMode uses to show its level (menu bar icon and the big percentage readouts).
///
/// The hue track is physical: the color at a level is the white point of a blackbody (the Planckian locus),
/// which is what Night Shift moves the screen along. It runs from neutral white (6500 K) toward a warm end that
/// exaggerates Night Shift's real range (6000 K to 2700 K, a 204 mired shift) by `exaggeration`, so a tint that
/// is subtle on a whole screen still reads on a 16 point glyph. With the default 1.45 the 100% color is the
/// blackbody at about 2230 K: candlelight amber, not red.
///
/// The spacing is perceptual: the curve is re-parameterized by cumulative OKLab distance, so every 1% step is
/// the same visual change (0 to 1% looks like 1 to 2% and like 99 to 100%). The result is a 101-entry table per
/// background, computed once.
///
/// On dark backgrounds the track starts at white. On light backgrounds it starts at the near-black of a
/// template icon and moves toward a darkened version of the same hues, keeping at least 4.4:1 contrast against
/// white and 3.8:1 against a light gray menu bar (WCAG's bar for graphics and large text is 3:1).
public enum WarmthPalette {
    public enum Background: CaseIterable {
        case dark
        case light
    }

    /// The neutral white point (level 0).
    public static let neutralKelvin = 6500.0
    /// Night Shift's range on current Macs (`getCCTRange:`), used only to size the warm end.
    public static let nightShiftCoolestKelvin = 6000.0
    public static let nightShiftWarmestKelvin = 2700.0
    /// How strongly the icon exaggerates Night Shift's real shift (in mireds).
    public static let exaggeration = 1.45

    /// Light backgrounds: OKLab lightness of the neutral (template black) and of the warm end, and the warm
    /// end's chroma (chosen to stay inside sRGB along the whole track).
    static let lightNeutralL = 0.24
    static let lightWarmL = 0.58
    static let lightWarmChroma = 0.13

    static let pathSamples = 4000

    public static var nightShiftMiredSpan: Double { 1e6 / nightShiftWarmestKelvin - 1e6 / nightShiftCoolestKelvin }

    /// Color temperature of the 100% color.
    public static var warmestKelvin: Double { 1e6 / (1e6 / neutralKelvin + exaggeration * nightShiftMiredSpan) }

    /// Blackbody color at `kelvin` in linear sRGB, white-balanced so `neutralKelvin` is exactly (1, 1, 1), and
    /// scaled so the brightest channel is 1.
    public static func blackbodyLinear(kelvin: Double) -> SIMD3<Double> {
        let neutral = ColorMath.planckianXY(kelvin: neutralKelvin)
        let white = ColorMath.linearSRGB(x: neutral.x, y: neutral.y)
        let xy = ColorMath.planckianXY(kelvin: kelvin)
        var c = ColorMath.linearSRGB(x: xy.x, y: xy.y) / white
        c = SIMD3(Swift.max(0, c.x), Swift.max(0, c.y), Swift.max(0, c.z))
        return c / Swift.max(c.x, c.y, c.z)
    }

    /// The color for a level (0 to 100, fractional levels interpolate) on a background.
    public static func oklab(level: Double, on background: Background) -> OKLab {
        let table = self.table(for: background)
        let position = Swift.min(100, Swift.max(0, level))
        let lower = Int(position.rounded(.down))
        if lower >= 100 { return table[100] }
        return OKLab.mix(table[lower], table[lower + 1], position - Double(lower))
    }

    public static func srgb(level: Double, on background: Background) -> SRGB {
        ColorMath.srgb(oklab(level: level, on: background))
    }

    /// 101 entries, one per whole percent.
    public static func table(for background: Background) -> [OKLab] {
        switch background {
        case .dark: return darkTable
        case .light: return lightTable
        }
    }

    private static let darkTable = buildTable(.dark)
    private static let lightTable = buildTable(.light)

    /// The track before re-parameterization: `s` runs from 0 (neutral) to 1 (warmest), linear in mireds.
    static func path(_ background: Background, _ s: Double) -> OKLab {
        let mired = 1e6 / neutralKelvin + s * exaggeration * nightShiftMiredSpan
        let lab = ColorMath.oklab(linear: blackbodyLinear(kelvin: 1e6 / mired))
        switch background {
        case .dark:
            return lab
        case .light:
            // Same hue track, chroma scaled to fit a dark range, lightness rising with chroma from template black.
            // (Measured from the neutral's own OKLab value, so level 0 is exactly gray even with rounding.)
            let neutral = ColorMath.oklab(linear: SIMD3(1, 1, 1))
            let warm = ColorMath.oklab(linear: blackbodyLinear(kelvin: warmestKelvin))
            let da = lab.a - neutral.a, db = lab.b - neutral.b
            let warmChroma = ((warm.a - neutral.a) * (warm.a - neutral.a) + (warm.b - neutral.b) * (warm.b - neutral.b)).squareRoot()
            let fraction = (da * da + db * db).squareRoot() / warmChroma
            let scale = lightWarmChroma / warmChroma
            return OKLab(L: lightNeutralL + (lightWarmL - lightNeutralL) * fraction, a: da * scale, b: db * scale)
        }
    }

    /// Samples the track densely, measures cumulative OKLab distance, and picks the 101 parameters that split it
    /// into equal-length steps.
    static func buildTable(_ background: Background) -> [OKLab] {
        let n = pathSamples
        var params = [Double](repeating: 0, count: n + 1)
        var cumulative = [Double](repeating: 0, count: n + 1)
        var previous = path(background, 0)
        for i in 1...n {
            let s = Double(i) / Double(n)
            let point = path(background, s)
            params[i] = s
            cumulative[i] = cumulative[i - 1] + point.distance(to: previous)
            previous = point
        }
        let total = cumulative[n]
        var table: [OKLab] = []
        table.reserveCapacity(101)
        var segment = 0
        for step in 0...100 {
            let target = total * Double(step) / 100
            while segment < n - 1 && cumulative[segment + 1] < target { segment += 1 }
            let span = cumulative[segment + 1] - cumulative[segment]
            let t = span > 0 ? (target - cumulative[segment]) / span : 0
            let s = params[segment] + (params[segment + 1] - params[segment]) * Swift.min(1, Swift.max(0, t))
            table.append(path(background, s))
        }
        return table
    }
}
