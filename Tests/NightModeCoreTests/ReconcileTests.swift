import XCTest
@testable import NightModeCore

final class ReconcileTests: XCTestCase {
    let cal = calendar()
    let automation = LevelSource.automation(AutomationStatus(scheduleLevel: 40, brightnessLevel: nil, scheduleState: nil,
                                                              nextScheduleChange: nil, driver: .schedule, level: 40))

    func react(_ expected: Double, _ actual: Double, _ source: LevelSource, _ time: String) -> ExternalChangeReaction {
        ExternalChangePolicy.react(expected: expected, actual: actual, source: source, now: at(time),
                                   calendar: cal, systemDayStart: (7, 0))
    }

    func testSmallDifferencesAreIgnored() {
        XCTAssertEqual(react(40, 40.4, .manual, "2026-10-10 21:00"), .ignore)
        XCTAssertEqual(react(0, 0, .manual, "2026-10-10 21:00"), .ignore)
        XCTAssertEqual(react(0.2, 0, .manual, "2026-10-10 21:00"), .ignore)
    }

    func testExternalChangesAreAdoptedAsManual() {
        XCTAssertEqual(react(40, 0, .manual, "2026-10-10 21:00"), .adopt(0))
        XCTAssertEqual(react(40, 70, automation, "2026-10-10 21:00"), .adopt(70))
        XCTAssertEqual(react(0, 30, .off(until: nil), "2026-10-10 21:00"), .adopt(30))
        XCTAssertEqual(react(40, 0, automation, "2026-10-11 15:00"), .adopt(0))
    }

    func testMacOSMorningSwitchOffIsUndoneOnlyWhenAutomationIsInCharge() {
        XCTAssertEqual(react(40, 0, automation, "2026-10-11 07:00:20"), .reassert)
        XCTAssertEqual(react(40, 0, automation, "2026-10-11 06:58"), .reassert)
        // In plain manual mode NightMode does what v1 did: it reflects the switch-off.
        XCTAssertEqual(react(40, 0, .manual, "2026-10-11 07:00:20"), .adopt(0))
    }

    func testLaunchDecisions() {
        let manual = Evaluation(level: 40, underlyingLevel: 40, source: .manual, nextCheck: nil, isContinuous: false, pendingRamp: nil)
        XCTAssertEqual(LaunchReconciliation.decide(evaluation: manual, actual: 25, tintWasTurnedOffOnQuit: false), .adoptActual)
        XCTAssertEqual(LaunchReconciliation.decide(evaluation: manual, actual: 0, tintWasTurnedOffOnQuit: true), .applyEvaluation)
        var auto = manual
        auto.source = automation
        XCTAssertEqual(LaunchReconciliation.decide(evaluation: auto, actual: 0, tintWasTurnedOffOnQuit: false), .applyEvaluation)
        var off = manual
        off.source = .off(until: nil)
        XCTAssertEqual(LaunchReconciliation.decide(evaluation: off, actual: 30, tintWasTurnedOffOnQuit: false), .adoptActual)
        XCTAssertEqual(LaunchReconciliation.decide(evaluation: off, actual: 0, tintWasTurnedOffOnQuit: false), .applyEvaluation)
    }
}
