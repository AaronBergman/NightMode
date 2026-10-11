import XCTest
@testable import NightModeCore

final class EngineTests: XCTestCase {
    let e = env()

    func gentleState(policy: PausePolicy = .untilNextChange) -> EngineState {
        EngineState(schedule: Schedule(isEnabled: true, transitions: Presets.gentleEvening()), pausePolicy: policy)
    }

    func eval(_ s: EngineState, _ time: String, _ environment: EngineEnvironment? = nil) -> Evaluation {
        s.evaluate(now: at(time), env: environment ?? e)
    }

    func step(_ s: inout EngineState, _ time: String, _ environment: EngineEnvironment? = nil) -> Evaluation {
        s.advance(now: at(time), env: environment ?? e)
        return s.evaluate(now: at(time), env: environment ?? e)
    }

    // MARK: Manual

    func testManualLevelAndNudges() {
        var s = EngineState()
        s.setLevel(40, now: at("2026-10-10 21:00"), env: e)
        XCTAssertEqual(eval(s, "2026-10-10 21:00").source, .manual)
        XCTAssertLevel(eval(s, "2026-10-10 21:00").level, 40)
        s.nudge(by: 5, now: at("2026-10-10 21:01"), env: e)
        XCTAssertLevel(s.manualLevel, 45)
        s.nudge(by: -1, now: at("2026-10-10 21:01"), env: e)
        XCTAssertLevel(s.manualLevel, 44)
        s.setLevel(98, now: at("2026-10-10 21:01"), env: e)
        s.nudge(by: 5, now: at("2026-10-10 21:01"), env: e)
        XCTAssertLevel(s.manualLevel, 100)
        s.setLevel(2, now: at("2026-10-10 21:01"), env: e)
        s.nudge(by: -5, now: at("2026-10-10 21:01"), env: e)
        XCTAssertLevel(s.manualLevel, 0)
        XCTAssertNil(eval(s, "2026-10-10 21:01").nextCheck) // nothing scheduled: no timers needed
    }

    func testNudgeRoundsAFractionalLevelFirst() {
        var s = EngineState()
        s.startRamp(origin: .fixed(0), to: 100, start: at("2026-10-10 21:00"), duration: 1000, now: at("2026-10-10 21:00"), env: e)
        // At 21:07:04 the ramp is at 42.4%; +1 gives 43, not 43.4.
        s.nudge(by: 1, now: at("2026-10-10 21:07:04"), env: e)
        XCTAssertLevel(s.manualLevel, 43)
        XCTAssertNil(s.ramp, "a manual change takes over from a running ramp")
    }

    // MARK: Schedule and overrides

    func testAutomationFollowsSchedule() {
        let s = gentleState()
        let r = eval(s, "2026-10-10 20:30")
        XCTAssertLevel(r.level, 20)
        guard case .automation(let status) = r.source else { return XCTFail("expected automation") }
        XCTAssertEqual(status.driver, .schedule)
        XCTAssertTrue(r.isContinuous)
        XCTAssertLessThanOrEqual(r.nextCheck!.timeIntervalSince(at("2026-10-10 20:30")), 60)
        // Holding between changes: the next check is the next scheduled change.
        XCTAssertEqual(eval(s, "2026-10-10 23:30").nextCheck, at("2026-10-11 07:00"))
        XCTAssertFalse(eval(s, "2026-10-10 23:30").isContinuous)
    }

    func testManualChangePausesUntilNextScheduledChange() {
        var s = gentleState()
        s.setLevel(50, now: at("2026-10-10 20:30"), env: e)
        XCTAssertEqual(s.override?.until, at("2026-10-10 22:00"))
        XCTAssertLevel(step(&s, "2026-10-10 21:00").level, 50)
        guard case .override(_, let auto) = eval(s, "2026-10-10 21:00").source else { return XCTFail("expected override") }
        XCTAssertLevel(auto?.level, 40, "override still reports what the schedule would do")
        XCTAssertEqual(eval(s, "2026-10-10 21:00").nextCheck, at("2026-10-10 22:00"))
        // At the next change the schedule takes over again, continuing from its own level (40 -> 70).
        XCTAssertLevel(step(&s, "2026-10-10 22:00").level, 40)
        XCTAssertNil(s.override)
        XCTAssertLevel(step(&s, "2026-10-10 22:30").level, 55)
    }

    func testPausePolicies() {
        var hour = gentleState(policy: .oneHour)
        hour.setLevel(50, now: at("2026-10-10 20:30"), env: e)
        XCTAssertLevel(step(&hour, "2026-10-10 21:29").level, 50)
        XCTAssertLevel(step(&hour, "2026-10-10 21:30").level, 40)

        var resume = gentleState(policy: .untilResume)
        resume.setLevel(50, now: at("2026-10-10 20:30"), env: e)
        XCTAssertLevel(step(&resume, "2026-10-11 09:00").level, 50)
        resume.resumeAutomation()
        XCTAssertLevel(step(&resume, "2026-10-11 09:00").level, 0)
    }

    func testChangingPolicyRecomputesExpiry() {
        var s = gentleState(policy: .untilResume)
        s.setLevel(50, now: at("2026-10-10 20:30"), env: e)
        XCTAssertNil(s.override?.until)
        s.setPausePolicy(.oneHour, env: e)
        XCTAssertEqual(s.override?.until, at("2026-10-10 21:30"))
    }

    func testEditingTransitionsRefreshesOverrideExpiry() {
        var s = gentleState()
        s.setLevel(50, now: at("2026-10-10 20:30"), env: e)
        var edited = Presets.gentleEvening()
        edited[1].anchor = .clock(hour: 21, minute: 15)
        s.setTransitions(edited, now: at("2026-10-10 20:40"), env: e)
        XCTAssertEqual(s.override?.until, at("2026-10-10 21:15"))
    }

    func testDisablingAutomationKeepsTheCurrentLevel() {
        var s = gentleState()
        s.setScheduleEnabled(false, now: at("2026-10-10 22:30"), env: e)
        XCTAssertEqual(eval(s, "2026-10-10 22:31").source, .manual)
        XCTAssertLevel(s.manualLevel, 55)
    }

    func testEnablingAutomationClearsOverrideAndSwitchesOn() {
        var s = gentleState()
        s.setLevel(50, now: at("2026-10-10 20:30"), env: e)
        s.setOn(false)
        s.setScheduleEnabled(true, now: at("2026-10-10 20:31"), env: e)
        XCTAssertNil(s.override)
        XCTAssertTrue(s.isOn)
    }

    func testOverrideFoldsIntoManualWhenAutomationIsSwitchedOffElsewhere() {
        var s = gentleState()
        s.setLevel(50, now: at("2026-10-10 20:30"), env: e)
        s.schedule.isEnabled = false  // e.g. edited directly
        XCTAssertLevel(step(&s, "2026-10-10 20:31").level, 50)
        XCTAssertNil(s.override)
        XCTAssertEqual(s.manualLevel, 50)
    }

    // MARK: Ramps

    func testRampTakesPrecedenceThenHoldsUntilNextChange() {
        var s = gentleState()
        s.startRamp(origin: .current, to: 100, start: at("2026-10-10 20:30"), duration: 1800, now: at("2026-10-10 20:30"), env: e)
        XCTAssertLevel(s.ramp?.resolvedFrom, 20, accuracy: 0.01)
        let mid = step(&s, "2026-10-10 20:45")
        XCTAssertLevel(mid.level, 60)
        XCTAssertTrue(mid.isContinuous)
        XCTAssertEqual(mid.source, .ramp(s.ramp!))
        // Finished: the end level is held as an override until the schedule's next change at 22:00.
        XCTAssertLevel(step(&s, "2026-10-10 21:00").level, 100)
        XCTAssertNil(s.ramp)
        XCTAssertEqual(s.override?.until, at("2026-10-10 22:00"))
        XCTAssertLevel(step(&s, "2026-10-10 21:59").level, 100)
        XCTAssertLevel(step(&s, "2026-10-10 22:30").level, 55)
    }

    func testSleepingThroughRampEndAndNextChange() {
        var s = gentleState()
        s.startRamp(origin: .current, to: 100, start: at("2026-10-10 20:30"), duration: 1800, now: at("2026-10-10 20:30"), env: e)
        // The Mac sleeps from 20:31 to 22:30. On wake one advance() sorts everything out.
        let woke = step(&s, "2026-10-10 22:30")
        XCTAssertNil(s.ramp)
        XCTAssertNil(s.override)
        XCTAssertLevel(woke.level, 55)
    }

    func testSleepingThroughPartOfARampResumesAtTheRightPlace() {
        var s = EngineState()
        s.setLevel(0, now: at("2026-10-10 20:00"), env: e)
        s.startRamp(origin: .current, to: 100, start: at("2026-10-10 20:00"), duration: 3600, now: at("2026-10-10 20:00"), env: e)
        // No ticks at all between 20:00 and 20:45: the level is computed from the clock.
        XCTAssertLevel(step(&s, "2026-10-10 20:45").level, 75)
    }

    func testScheduledRampResolvesCurrentWhenItStarts() {
        var s = EngineState()
        s.setLevel(30, now: at("2026-10-10 21:00"), env: e)
        s.startRamp(origin: .current, to: 90, start: at("2026-10-10 22:00"), duration: 3600, now: at("2026-10-10 21:00"), env: e)
        XCTAssertNil(s.ramp?.resolvedFrom)
        let waiting = eval(s, "2026-10-10 21:10")
        XCTAssertEqual(waiting.nextCheck, at("2026-10-10 22:00"))
        XCTAssertNotNil(waiting.pendingRamp)
        // A manual change before the start does not cancel a pending ramp...
        s.setLevel(10, now: at("2026-10-10 21:30"), env: e)
        XCTAssertNotNil(s.ramp)
        // ...and "current" is whatever the level is when the ramp begins.
        XCTAssertLevel(step(&s, "2026-10-10 22:00").level, 10)
        XCTAssertLevel(s.ramp?.resolvedFrom, 10)
        XCTAssertLevel(step(&s, "2026-10-10 22:30").level, 50)
        XCTAssertLevel(step(&s, "2026-10-10 23:30").level, 90)
        XCTAssertEqual(s.manualLevel, 90)
    }

    func testCancelRampFreezesWhereItIs() {
        var s = EngineState()
        s.startRamp(origin: .fixed(0), to: 100, start: at("2026-10-10 20:00"), duration: 3600, now: at("2026-10-10 20:00"), env: e)
        s.cancelRamp(now: at("2026-10-10 20:15"), env: e)
        XCTAssertNil(s.ramp)
        XCTAssertLevel(eval(s, "2026-10-10 20:16").level, 25)
        // Cancelling a pending ramp just removes it.
        s.startRamp(origin: .fixed(0), to: 100, start: at("2026-10-10 23:00"), duration: 60, now: at("2026-10-10 20:20"), env: e)
        s.cancelRamp(now: at("2026-10-10 20:21"), env: e)
        XCTAssertNil(s.ramp)
        XCTAssertLevel(s.manualLevel, 25)
    }

    // MARK: Off

    func testOffKeepsUnderlyingLevel() {
        var s = EngineState()
        s.setLevel(60, now: at("2026-10-10 21:00"), env: e)
        s.setOn(false)
        let r = eval(s, "2026-10-10 21:00")
        XCTAssertEqual(r.level, 0)
        XCTAssertLevel(r.underlyingLevel, 60)
        XCTAssertEqual(r.source, .off(until: nil))
        // Moving the slider switches NightMode back on.
        s.setLevel(65, now: at("2026-10-10 21:01"), env: e)
        XCTAssertTrue(s.isOn)
    }

    func testOffForAnHour() {
        var s = gentleState()
        s.turnOff(for: 3600, now: at("2026-10-10 22:30"))
        let r = step(&s, "2026-10-10 22:45")
        XCTAssertEqual(r.level, 0)
        XCTAssertEqual(r.source, .off(until: at("2026-10-10 23:30")))
        XCTAssertLessThanOrEqual(r.nextCheck!, at("2026-10-10 23:30"))
        XCTAssertLevel(step(&s, "2026-10-10 23:30").level, 70)
        XCTAssertNil(s.offUntil)
    }

    // MARK: Brightness

    func testFollowBrightness() {
        var s = EngineState()
        s.setBrightnessEnabled(true, now: at("2026-10-10 12:00"), env: env(brightness: 0.35))
        let r = eval(s, "2026-10-10 12:00", env(brightness: 0.35))
        XCTAssertLevel(r.level, 45)
        guard case .automation(let status) = r.source else { return XCTFail() }
        XCTAssertEqual(status.driver, .brightness)
        XCTAssertLevel(eval(s, "2026-10-10 12:00", env(brightness: 0.9)).level, 0)
    }

    func testWarmerOfScheduleAndBrightnessWins() {
        var s = gentleState()
        s.brightness.isEnabled = true
        let bright = eval(s, "2026-10-10 22:30", env(brightness: 0.8))
        XCTAssertLevel(bright.level, 55)
        let dim = eval(s, "2026-10-10 22:30", env(brightness: 0.1))
        XCTAssertLevel(dim.level, 85)
        guard case .automation(let status) = dim.source else { return XCTFail() }
        XCTAssertEqual(status.driver, .brightness)
        XCTAssertFalse(dim.isContinuous)
    }

    func testManualChangeWhileFollowingBrightnessResumesAfterABrightnessChange() {
        var s = EngineState(brightness: BrightnessConfig(isEnabled: true))
        s.setLevel(10, now: at("2026-10-10 12:00"), env: env(brightness: 0.35))
        XCTAssertEqual(s.override?.brightnessAnchor, 0.35)
        XCTAssertNil(s.override?.until)
        XCTAssertLevel(step(&s, "2026-10-10 12:05", env(brightness: 0.45)).level, 10)  // moved 10 points: still paused
        let resumed = step(&s, "2026-10-10 12:06", env(brightness: 0.55))                 // 20 points: resumes
        XCTAssertNil(s.override)
        XCTAssertLevel(resumed.level, 45 - 45 * (0.20 / 0.35))
    }

    func testBrightnessUnavailableFallsBackToManual() {
        var s = EngineState(brightness: BrightnessConfig(isEnabled: true))
        s.setLevel(30, now: at("2026-10-10 12:00"), env: env(brightness: nil))
        XCTAssertNil(s.override, "no automation to pause when brightness cannot be read")
        XCTAssertEqual(eval(s, "2026-10-10 12:00", env(brightness: nil)).source, .manual)
        XCTAssertLevel(eval(s, "2026-10-10 12:00", env(brightness: nil)).level, 30)
    }

    func testAdvanceReportsChanges() {
        var s = gentleState()
        XCTAssertFalse(s.advance(now: at("2026-10-10 20:00"), env: e))
        s.turnOff(for: 60, now: at("2026-10-10 20:00"))
        XCTAssertTrue(s.advance(now: at("2026-10-10 20:02"), env: e))
    }
}
