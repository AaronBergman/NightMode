import XCTest
@testable import NightModeCore

final class BrightnessCurveTests: XCTestCase {
    func testStandardCurve() {
        let c = BrightnessCurve.standard  // (10% -> 85), (35% -> 45), (70% -> 0)
        XCTAssertLevel(c.level(forBrightness: 0), 85)
        XCTAssertLevel(c.level(forBrightness: 0.10), 85)
        XCTAssertLevel(c.level(forBrightness: 0.225), 65)
        XCTAssertLevel(c.level(forBrightness: 0.35), 45)
        XCTAssertLevel(c.level(forBrightness: 0.525), 22.5)
        XCTAssertLevel(c.level(forBrightness: 0.70), 0)
        XCTAssertLevel(c.level(forBrightness: 1), 0)
    }

    func testUnsortedPointsAndClamping() {
        let c = BrightnessCurve(points: [
            CurvePoint(brightness: 0.8, level: 10),
            CurvePoint(brightness: 0.2, level: 90),
        ])
        XCTAssertLevel(c.level(forBrightness: 0.5), 50)
        XCTAssertLevel(c.level(forBrightness: -3), 90)
        XCTAssertLevel(c.level(forBrightness: .nan), 90)
        XCTAssertLevel(c.level(forBrightness: 7), 10)
    }

    func testDegenerateCurves() {
        XCTAssertEqual(BrightnessCurve(points: []).level(forBrightness: 0.5), 0)
        XCTAssertLevel(BrightnessCurve(points: [CurvePoint(brightness: 0.5, level: 33)]).level(forBrightness: 0.9), 33)
        // Two points at the same brightness: a step, no division by zero.
        let step = BrightnessCurve(points: [CurvePoint(brightness: 0.5, level: 80), CurvePoint(brightness: 0.5, level: 20)])
        XCTAssertTrue(step.level(forBrightness: 0.5).isFinite)
    }

    func testPointInitClamps() {
        let p = CurvePoint(brightness: 1.5, level: 140)
        XCTAssertEqual(p.brightness, 1)
        XCTAssertEqual(p.level, 100)
    }
}
