import XCTest
@testable import NightModeCore

final class RampTests: XCTestCase {
    func testLevelClamp() {
        XCTAssertEqual(Level.clamp(-5), 0)
        XCTAssertEqual(Level.clamp(150), 100)
        XCTAssertEqual(Level.clamp(.nan), 0)
        XCTAssertEqual(Level.display(42.5), 43)
        XCTAssertEqual(Level.format(7.2), "7%")
    }

    func testEasing() {
        XCTAssertEqual(Easing.linear.apply(0.25), 0.25)
        XCTAssertEqual(Easing.smooth.apply(0), 0)
        XCTAssertEqual(Easing.smooth.apply(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Easing.smooth.apply(1), 1)
        XCTAssertLessThan(Easing.smooth.apply(0.1), 0.1) // gentle start
        XCTAssertEqual(Easing.smooth.apply(2), 1) // clamped
    }

    func testSegmentFollowsWallClock() {
        let start = at("2026-10-10 21:00")
        let s = Segment(from: 20, to: 80, start: start, duration: 3600)
        XCTAssertLevel(s.value(at: start.addingTimeInterval(-10)), 20)
        XCTAssertLevel(s.value(at: start), 20)
        XCTAssertLevel(s.value(at: start.addingTimeInterval(900)), 35)
        XCTAssertLevel(s.value(at: start.addingTimeInterval(1800)), 50)
        XCTAssertLevel(s.value(at: start.addingTimeInterval(3600)), 80)
        XCTAssertLevel(s.value(at: start.addingTimeInterval(99_999)), 80)
        XCTAssertTrue(s.isMoving(at: start.addingTimeInterval(1)))
        XCTAssertFalse(s.isMoving(at: start.addingTimeInterval(3600)))
    }

    func testZeroDurationSegmentJumps() {
        let start = at("2026-10-10 21:00")
        let s = Segment(from: 10, to: 90, start: start, duration: 0)
        XCTAssertLevel(s.value(at: start.addingTimeInterval(-1)), 10)
        XCTAssertLevel(s.value(at: start.addingTimeInterval(0.001)), 90)
        XCTAssertFalse(s.isMoving(at: start))
    }

    func testRampPendingRunningFinished() {
        let start = at("2026-10-10 22:00")
        let r = Ramp(origin: .fixed(10), to: 100, start: start, duration: 1800)
        XCTAssertTrue(r.isPending(at: start.addingTimeInterval(-1)))
        XCTAssertNil(r.level(at: start.addingTimeInterval(-1)))
        XCTAssertLevel(r.level(at: start.addingTimeInterval(900)), 55)
        XCTAssertEqual(r.progress(at: start.addingTimeInterval(450)), 0.25, accuracy: 1e-9)
        XCTAssertEqual(r.remaining(at: start.addingTimeInterval(900)), 900, accuracy: 1e-9)
        XCTAssertTrue(r.isFinished(at: start.addingTimeInterval(1800)))
        XCTAssertLevel(r.level(at: start.addingTimeInterval(5000)), 100)
    }

    func testRampFromCurrentIsUnresolvedUntilSet() {
        let r = Ramp(origin: .current, to: 100, start: at("2026-10-10 22:00"), duration: 60)
        XCTAssertNil(r.resolvedFrom)
        XCTAssertNil(r.level(at: at("2026-10-10 22:00:30")))
    }

    func testSteppingIntervals() {
        let t0 = at("2026-10-10 21:00")
        // 0 -> 100 over 30 min: 0.0556 points/s, 0.25 points per step -> 4.5 s.
        let thirty = Segment(from: 0, to: 100, start: t0, duration: 1800)
        XCTAssertEqual(Stepping.interval(for: thirty), 4.5, accuracy: 0.001)
        // Very fast ramps are capped at 1 s per update, very slow ones at 60 s.
        XCTAssertEqual(Stepping.interval(for: Segment(from: 0, to: 100, start: t0, duration: 60)), 1)
        XCTAssertEqual(Stepping.interval(for: Segment(from: 0, to: 5, start: t0, duration: 86_400)), 60)
        // Smooth easing is steeper in the middle, so steps are 1.5x more frequent.
        let smooth = Segment(from: 0, to: 100, start: t0, duration: 1800, easing: .smooth)
        XCTAssertEqual(Stepping.interval(for: smooth), 3.0, accuracy: 0.001)
        // The next update never overshoots the end.
        let short = Segment(from: 0, to: 100, start: t0, duration: 2)
        XCTAssertEqual(Stepping.nextUpdate(for: short, now: t0.addingTimeInterval(1.5)), short.end)
    }
}
