import XCTest
@testable import NightModeCore

final class WarmthPaletteTests: XCTestCase {
    /// Steps between consecutive whole percents, in OKLab.
    private func steps(_ background: WarmthPalette.Background) -> [Double] {
        let table = WarmthPalette.table(for: background)
        return (1...100).map { table[$0].distance(to: table[$0 - 1]) }
    }

    func testEveryOnePercentStepLooksTheSame() {
        for background in WarmthPalette.Background.allCases {
            let s = steps(background)
            let ratio = s.max()! / s.min()!
            print(String(format: "WarmthPalette %@: step mean %.5f, min %.5f, max %.5f, max/min %.5f, 0->1 %.5f, 1->2 %.5f, 99->100 %.5f",
                         "\(background)", s.reduce(0, +) / 100, s.min()!, s.max()!, ratio, s[0], s[1], s[99]))
            XCTAssertLessThan(ratio, 1.05, "\(background): max/min step ratio")
            XCTAssertEqual(s[0], s[1], accuracy: s[1] * 0.05, "\(background): 0->1 matches 1->2")
            XCTAssertEqual(s[99], s[1], accuracy: s[1] * 0.05, "\(background): 99->100 matches 1->2")
        }
    }

    func testStepsAreUniformAfterConversionToSRGB() {
        // What is actually drawn is the sRGB color, so measure the round trip too.
        for background in WarmthPalette.Background.allCases {
            let labs = (0...100).map { ColorMath.oklab(WarmthPalette.srgb(level: Double($0), on: background)) }
            let s = (1...100).map { labs[$0].distance(to: labs[$0 - 1]) }
            XCTAssertLessThan(s.max()! / s.min()!, 1.05, "\(background)")
        }
    }

    func testLevelZeroIsTheNeutralColor() {
        let white = WarmthPalette.srgb(level: 0, on: .dark)
        XCTAssertEqual(white.r, 1, accuracy: 1e-6)
        XCTAssertEqual(white.g, 1, accuracy: 1e-6)
        XCTAssertEqual(white.b, 1, accuracy: 1e-6)
        let black = WarmthPalette.oklab(level: 0, on: .light)
        XCTAssertEqual(black.L, WarmthPalette.lightNeutralL, accuracy: 1e-9)
        XCTAssertEqual(black.chroma, 0, accuracy: 1e-9)
        let gray = WarmthPalette.srgb(level: 0, on: .light)
        XCTAssertEqual(gray.r, gray.g, accuracy: 1e-6)
        XCTAssertEqual(gray.g, gray.b, accuracy: 1e-6)
    }

    func testWarmEndIsTheExaggeratedBlackbody() {
        XCTAssertEqual(WarmthPalette.nightShiftMiredSpan, 203.7, accuracy: 0.1)
        XCTAssertEqual(WarmthPalette.warmestKelvin, 2226, accuracy: 5)
        let expected = ColorMath.oklab(linear: WarmthPalette.blackbodyLinear(kelvin: WarmthPalette.warmestKelvin))
        XCTAssertLessThan(WarmthPalette.oklab(level: 100, on: .dark).distance(to: expected), 1e-6)
        // Candlelight amber, not red: red channel full, green well above half, OKLab hue in the orange-amber band.
        let c = WarmthPalette.srgb(level: 100, on: .dark)
        XCTAssertEqual(c.r, 1, accuracy: 1e-6)
        XCTAssertGreaterThan(c.g, 0.55)
        XCTAssertGreaterThan(WarmthPalette.oklab(level: 100, on: .dark).hueDegrees, 55)
    }

    func testEveryDarkEntryLiesOnThePlanckianLocus() {
        // Each entry must be some blackbody color between the neutral and the warm end (found by bisection on mireds).
        let neutralMired = 1e6 / WarmthPalette.neutralKelvin
        let warmMired = 1e6 / WarmthPalette.warmestKelvin
        let table = WarmthPalette.table(for: .dark)
        func chroma(_ mired: Double) -> Double { ColorMath.oklab(linear: WarmthPalette.blackbodyLinear(kelvin: 1e6 / mired)).chroma }
        for level in stride(from: 5, through: 95, by: 10) {
            var lo = neutralMired, hi = warmMired
            for _ in 0..<60 {
                let mid = (lo + hi) / 2
                if chroma(mid) < table[level].chroma { lo = mid } else { hi = mid }
            }
            let onLocus = ColorMath.oklab(linear: WarmthPalette.blackbodyLinear(kelvin: 1e6 / lo))
            XCTAssertLessThan(table[level].distance(to: onLocus), 1e-6, "level \(level)")
        }
    }

    func testColorsGetSteadilyWarmer() {
        for background in WarmthPalette.Background.allCases {
            let table = WarmthPalette.table(for: background)
            for level in 1...100 {
                XCTAssertGreaterThan(table[level].chroma, table[level - 1].chroma, "\(background) \(level)")
            }
            for level in 5...100 {
                XCTAssertGreaterThan(table[level].hueDegrees, 50, "\(background) \(level) stays warm")
                XCTAssertLessThan(table[level].hueDegrees, 90, "\(background) \(level) stays warm")
            }
        }
        // Dark backgrounds: lightness falls slowly from white; light backgrounds: rises from template black.
        XCTAssertGreaterThan(WarmthPalette.oklab(level: 0, on: .dark).L, WarmthPalette.oklab(level: 100, on: .dark).L)
        XCTAssertLessThan(WarmthPalette.oklab(level: 0, on: .light).L, WarmthPalette.oklab(level: 100, on: .light).L)
    }

    func testEveryColorIsInsideSRGBWithoutClipping() {
        for background in WarmthPalette.Background.allCases {
            for (level, lab) in WarmthPalette.table(for: background).enumerated() {
                let c = ColorMath.linear(lab)
                for v in [c.x, c.y, c.z] {
                    XCTAssertGreaterThanOrEqual(v, -1e-6, "\(background) \(level)")
                    XCTAssertLessThanOrEqual(v, 1 + 1e-6, "\(background) \(level)")
                }
            }
        }
    }

    func testContrastAgainstMenuBars() {
        let darkBars = [SRGB(r: 0, g: 0, b: 0), SRGB(r: 0.2, g: 0.2, b: 0.2)]
        let lightBars = [SRGB(r: 1, g: 1, b: 1), SRGB(r: 0.925, g: 0.925, b: 0.925)]
        var worst = (dark: 21.0, light: 21.0)
        for level in 0...100 {
            for bar in darkBars {
                worst.dark = min(worst.dark, ColorMath.contrastRatio(WarmthPalette.srgb(level: Double(level), on: .dark), bar))
            }
            for bar in lightBars {
                worst.light = min(worst.light, ColorMath.contrastRatio(WarmthPalette.srgb(level: Double(level), on: .light), bar))
            }
        }
        XCTAssertGreaterThan(worst.dark, 4.5)
        XCTAssertGreaterThan(worst.light, 3.5)
    }

    func testFractionalLevelsInterpolate() {
        let a = WarmthPalette.oklab(level: 47, on: .dark), b = WarmthPalette.oklab(level: 48, on: .dark)
        let mid = WarmthPalette.oklab(level: 47.5, on: .dark)
        XCTAssertEqual(mid.distance(to: a), mid.distance(to: b), accuracy: 1e-9)
        XCTAssertEqual(WarmthPalette.oklab(level: -3, on: .dark), WarmthPalette.oklab(level: 0, on: .dark))
        XCTAssertEqual(WarmthPalette.oklab(level: 140, on: .light), WarmthPalette.oklab(level: 100, on: .light))
    }

    func testPlanckianLocusMatchesTheIntegratedLocus() {
        // Reference xy from integrating Planck's law against the CIE 1931 2 degree observer (colour-science 0.4.7).
        let reference: [(Double, Double, Double)] = [(2000, 0.52668, 0.41330), (2226, 0.50300, 0.41526), (2700, 0.45986, 0.41060),
                                                     (4000, 0.38044, 0.37675), (6000, 0.32208, 0.33176), (6500, 0.31353, 0.32363)]
        for (kelvin, x, y) in reference {
            let xy = ColorMath.planckianXY(kelvin: kelvin)
            XCTAssertEqual(xy.x, x, accuracy: 0.0005, "\(kelvin) K")
            XCTAssertEqual(xy.y, y, accuracy: 0.0005, "\(kelvin) K")
        }
    }

    func testOKLabRoundTrip() {
        for c in [SRGB(r: 1, g: 0.5, b: 0.1), SRGB(r: 0.2, g: 0.7, b: 0.9), SRGB(r: 1, g: 1, b: 1)] {
            let back = ColorMath.srgb(ColorMath.oklab(c))
            XCTAssertEqual(back.r, c.r, accuracy: 1e-6)
            XCTAssertEqual(back.g, c.g, accuracy: 1e-6)
            XCTAssertEqual(back.b, c.b, accuracy: 1e-6)
        }
        // Known value: sRGB white is L = 1, a = b = 0.
        let white = ColorMath.oklab(SRGB(r: 1, g: 1, b: 1))
        XCTAssertEqual(white.L, 1, accuracy: 1e-4)
        XCTAssertEqual(white.chroma, 0, accuracy: 1e-4)
    }
}
