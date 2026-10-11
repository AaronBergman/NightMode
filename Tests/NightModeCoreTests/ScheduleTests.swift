import XCTest
@testable import NightModeCore

final class ScheduleTests: XCTestCase {
    let la = ScheduleContext(calendar: calendar(), location: GeoCoordinate(latitude: 34.0522, longitude: -118.2437))
    let gentle = Schedule(isEnabled: true, transitions: Presets.gentleEvening())

    func level(_ schedule: Schedule, _ time: String) -> Double? {
        schedule.state(at: at(time), context: la)?.level
    }

    func testGentleEveningThroughADay() {
        // 20:00 -> 40% over 60 min, 22:00 -> 70% over 60 min, 07:00 -> 0% over 30 min.
        XCTAssertLevel(level(gentle, "2026-10-10 19:00"), 0)
        XCTAssertLevel(level(gentle, "2026-10-10 20:00"), 0)
        XCTAssertLevel(level(gentle, "2026-10-10 20:30"), 20)
        XCTAssertLevel(level(gentle, "2026-10-10 21:00"), 40)
        XCTAssertLevel(level(gentle, "2026-10-10 21:59"), 40)
        XCTAssertLevel(level(gentle, "2026-10-10 22:30"), 55)
        XCTAssertLevel(level(gentle, "2026-10-10 23:30"), 70)
        XCTAssertLevel(level(gentle, "2026-10-11 03:00"), 70)
        XCTAssertLevel(level(gentle, "2026-10-11 07:15"), 35)
        XCTAssertLevel(level(gentle, "2026-10-11 08:00"), 0)
    }

    func testStateReportsRampingSegment() {
        let state = gentle.state(at: at("2026-10-10 22:30"), context: la)!
        XCTAssertTrue(state.isRamping(at: at("2026-10-10 22:30")))
        XCTAssertEqual(state.segment.start, at("2026-10-10 22:00"))
        XCTAssertEqual(state.segment.end, at("2026-10-10 23:00"))
        XCTAssertLevel(state.segment.from, 40)
        XCTAssertLevel(state.segment.to, 70)
        XCTAssertFalse(gentle.state(at: at("2026-10-10 23:30"), context: la)!.isRamping(at: at("2026-10-10 23:30")))
    }

    func testOverlappingTransitionInterruptsFromCurrentValue() {
        let s = Schedule(isEnabled: true, transitions: [
            Transition(anchor: .clock(hour: 21, minute: 0), target: 100, durationMinutes: 120),
            Transition(anchor: .clock(hour: 22, minute: 0), target: 0, durationMinutes: 60),
        ])
        XCTAssertLevel(level(s, "2026-10-10 21:30"), 25)
        XCTAssertLevel(level(s, "2026-10-10 22:00"), 50)  // B starts from A's current value...
        XCTAssertLevel(level(s, "2026-10-10 22:30"), 25)  // ...and heads to 0
        XCTAssertLevel(level(s, "2026-10-10 23:30"), 0)
    }

    func testFixedFromJumpsThenRamps() {
        let s = Schedule(isEnabled: true, transitions: [
            Transition(anchor: .clock(hour: 21, minute: 0), target: 60, durationMinutes: 60, fixedFrom: 30),
            Transition(anchor: .clock(hour: 6, minute: 0), target: 0, durationMinutes: 0),
        ])
        XCTAssertLevel(level(s, "2026-10-10 20:59"), 0)
        XCTAssertLevel(level(s, "2026-10-10 21:00"), 30)
        XCTAssertLevel(level(s, "2026-10-10 21:30"), 45)
        XCTAssertLevel(level(s, "2026-10-11 05:59"), 60)
        XCTAssertLevel(level(s, "2026-10-11 06:00:01"), 0)
    }

    func testWeekdayFilter() {
        // 2026-10-09 is a Friday, 2026-10-10 a Saturday.
        let s = Schedule(isEnabled: true, transitions: [
            Transition(anchor: .clock(hour: 22, minute: 0), target: 80, durationMinutes: 0, weekdays: [2, 3, 4, 5, 6]),
            Transition(anchor: .clock(hour: 7, minute: 0), target: 0, durationMinutes: 0),
        ])
        XCTAssertLevel(level(s, "2026-10-09 23:00"), 80)
        XCTAssertLevel(level(s, "2026-10-10 23:00"), 0)
        XCTAssertTrue(Transition(anchor: .clock(hour: 1, minute: 0), target: 1, durationMinutes: 0).runs(onWeekday: 3))
    }

    func testNextOccurrence() {
        XCTAssertEqual(gentle.nextOccurrence(after: at("2026-10-10 20:30"), context: la)?.start, at("2026-10-10 22:00"))
        XCTAssertEqual(gentle.nextOccurrence(after: at("2026-10-10 23:30"), context: la)?.start, at("2026-10-11 07:00"))
        // Strictly after: an occurrence exactly at `t` is not "next".
        XCTAssertEqual(gentle.nextOccurrence(after: at("2026-10-10 22:00"), context: la)?.start, at("2026-10-11 07:00"))
    }

    func testDaylightSavingSpringForwardAndFallBack() {
        let s = Schedule(isEnabled: true, transitions: [
            Transition(anchor: .clock(hour: 2, minute: 30), target: 50, durationMinutes: 0),
            Transition(anchor: .clock(hour: 1, minute: 30), target: 10, durationMinutes: 0),
        ])
        // 2026-03-08: 02:30 does not exist in Los Angeles; the change happens at 03:00 instead, once.
        let spring = s.occurrences(from: at("2026-03-08 00:00"), through: at("2026-03-08 23:59"), context: la)
        XCTAssertEqual(spring.count, 2)
        XCTAssertEqual(spring.last?.start, at("2026-03-08 03:00"))
        // 2026-11-01: 01:30 happens twice; the change runs once, at the first one (PDT, 08:30 UTC).
        let fall = s.occurrences(from: at("2026-11-01 00:00"), through: at("2026-11-01 23:59"), context: la)
        XCTAssertEqual(fall.count, 2)
        XCTAssertEqual(fall.first?.start.timeIntervalSince1970, 1793521800) // 2026-11-01T08:30:00Z
    }

    func testSunRelativeTransitions() {
        let s = Schedule(isEnabled: true, transitions: [
            Transition(anchor: .sunset(offsetMinutes: -30), target: 50, durationMinutes: 60),
            Transition(anchor: .sunrise(offsetMinutes: 0), target: 0, durationMinutes: 0),
        ])
        let occ = s.occurrences(from: at("2026-06-21 00:00"), through: at("2026-06-21 23:59"), context: la)
        XCTAssertEqual(occ.count, 2)
        // astral: LA sunrise 1782045738, sunset 1782097646 on 2026-06-21.
        XCTAssertEqual(occ[0].start.timeIntervalSince1970, 1782045738, accuracy: 90)
        XCTAssertEqual(occ[1].start.timeIntervalSince1970, 1782097646 - 1800, accuracy: 90)
        // Without a location, sun-relative transitions are skipped, so this schedule has no state.
        let noLocation = ScheduleContext(calendar: calendar(), location: nil)
        XCTAssertNil(s.state(at: at("2026-06-21 22:00"), context: noLocation))
        XCTAssertTrue(s.needsLocation)
    }

    func testPolarDaysSkipSunTransitionsButKeepClockOnes() {
        let tz = TimeZone(identifier: "Europe/Oslo")!
        let tromso = ScheduleContext(calendar: calendar(tz), location: GeoCoordinate(latitude: 69.6492, longitude: 18.9553))
        let s = Schedule(isEnabled: true, transitions: [
            Transition(anchor: .sunset(offsetMinutes: 0), target: 60, durationMinutes: 0),
            Transition(anchor: .clock(hour: 22, minute: 0), target: 80, durationMinutes: 0),
            Transition(anchor: .clock(hour: 7, minute: 0), target: 0, durationMinutes: 0),
        ])
        let occ = s.occurrences(from: at("2026-06-21 00:00", tz), through: at("2026-06-21 23:59", tz), context: tromso)
        XCTAssertEqual(occ.count, 2) // no sunset during midnight sun
        XCTAssertLevel(s.state(at: at("2026-06-21 23:00", tz), context: tromso)?.level, 80)
    }

    func testDisabledTransitionsAreIgnored() {
        var s = gentle
        for i in s.transitions.indices { s.transitions[i].isEnabled = false }
        XCTAssertFalse(s.hasActiveTransitions)
        XCTAssertNil(s.state(at: at("2026-10-10 22:30"), context: la))
        XCTAssertNil(s.nextOccurrence(after: at("2026-10-10 22:30"), context: la))
    }

    func testFastSamplerMatchesStateAtEveryPoint() {
        for schedule in [gentle, Schedule(isEnabled: true, transitions: Presets.sunsetToSunrise()),
                         Schedule(isEnabled: true, transitions: Presets.deepNight())] {
            let samples = schedule.samples(from: at("2026-10-10 00:00"), to: at("2026-10-11 00:00"), step: 300, context: la)
            XCTAssertEqual(samples.count, 289)
            for (date, value) in samples {
                XCTAssertLevel(value, schedule.state(at: date, context: la)?.level ?? 0, accuracy: 1e-9)
            }
        }
    }

    func testSamplesForPreviewChart() {
        let samples = gentle.samples(from: at("2026-10-10 00:00"), to: at("2026-10-10 23:59"), step: 900, context: la)
        XCTAssertEqual(samples.count, 96)
        XCTAssertLevel(samples.first(where: { $0.0 == at("2026-10-10 20:30") })?.1, 20)
    }
}
