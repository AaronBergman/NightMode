import XCTest
import NightModeCore
@testable import NightModeApp

final class AppModelTests: XCTestCase {
    let la = TimeZone(identifier: "America/Los_Angeles")!

    func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = la
        f.dateFormat = text.count > 16 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    func makeModel(at time: String, backendLevel: Double, state: AppState = AppState(), brightness: Double? = 0.8)
        -> (AppModel, MockTintBackend) {
        let backend = MockTintBackend(level: backendLevel)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = la
        let now = date(time)
        let model = AppModel(backend: backend, brightnessReader: MockBrightnessReader(brightness), loginItems: MockLoginItem(),
                             store: nil, initialState: state, clock: { now }, calendar: { cal })
        return (model, backend)
    }

    func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testLaunchAdoptsCurrentTintWithoutWriting() {
        let (model, backend) = makeModel(at: "2026-10-10 21:00", backendLevel: 40)
        model.start()
        spin(0.2)
        XCTAssertEqual(model.state.engine.manualLevel, 40, accuracy: 0.01)
        XCTAssertEqual(model.displayedLevel, 40, accuracy: 0.01)
        XCTAssertTrue(backend.applied.isEmpty, "adopting the current level must not touch the display: \(backend.applied)")
    }

    func testLaunchWithScheduleGlidesInsteadOfJumping() {
        var state = AppState()
        state.engine.schedule.isEnabled = true  // Gentle evening: 55% at 22:30
        let (model, backend) = makeModel(at: "2026-10-10 22:30", backendLevel: 0, state: state)
        model.start()
        spin(2.5)
        XCTAssertEqual(backend.applied.last ?? -1, 55, accuracy: 0.01)
        XCTAssertGreaterThan(backend.applied.count, 10, "expected a fade, got \(backend.applied.count) writes")
        XCTAssertLessThan(backend.applied.first ?? 100, 10, "the fade should start near the current level")
        XCTAssertEqual(backend.applied, backend.applied.sorted(), "the fade should only go up")
    }

    func testNudgesAndPresetsReachTheDisplay() {
        let (model, backend) = makeModel(at: "2026-10-10 21:00", backendLevel: 40)
        model.start()
        model.nudge(1)
        XCTAssertEqual(backend.status.level, 41, accuracy: 0.01)
        model.nudge(-5)  // 5 points fades over 0.35 s
        spin(0.6)
        XCTAssertEqual(backend.status.level, 36, accuracy: 0.01)
        model.setLevel(0, style: .immediate)
        XCTAssertFalse(backend.status.isEnabled, "0% switches Night Shift off")
        model.setLevel(75, style: .quick)
        spin(0.6)
        XCTAssertEqual(backend.status.level, 75, accuracy: 0.01)
    }

    func testOnOffSwitchRemembersLevel() {
        let (model, backend) = makeModel(at: "2026-10-10 21:00", backendLevel: 60)
        model.start()
        model.setOn(false)
        spin(0.6)
        XCTAssertFalse(backend.status.isEnabled)
        XCTAssertTrue(model.isOff)
        XCTAssertEqual(model.evaluation.underlyingLevel, 60, accuracy: 0.01)
        model.setOn(true)
        spin(0.6)
        XCTAssertEqual(backend.status.level, 60, accuracy: 0.01)
    }

    func testOutsideChangeIsAdoptedAsManual() {
        let (model, backend) = makeModel(at: "2026-10-10 21:00", backendLevel: 40)
        model.start()
        backend.status.isEnabled = false  // someone used Control Center
        XCTAssertTrue(model.checkForExternalChange())
        XCTAssertEqual(model.state.engine.manualLevel, 0)
        XCTAssertEqual(model.displayedLevel, 0)
    }

    func testMorningSwitchOffIsReassertedWhileAutomationIsInCharge() {
        var state = AppState()
        state.engine.schedule = Schedule(isEnabled: true, transitions: [
            NightModeCore.Transition(anchor: .clock(hour: 21, minute: 0), target: 50, durationMinutes: 0),
            NightModeCore.Transition(anchor: .clock(hour: 9, minute: 0), target: 0, durationMinutes: 0),
        ])
        let (model, backend) = makeModel(at: "2026-10-11 07:00:30", backendLevel: 50, state: state)
        model.start()
        XCTAssertEqual(model.evaluation.level, 50, accuracy: 0.01)
        backend.status.isEnabled = false  // macOS ends "on until tomorrow" at 07:00
        XCTAssertTrue(model.checkForExternalChange())
        XCTAssertTrue(backend.status.isEnabled)
        XCTAssertEqual(backend.status.level, 50, accuracy: 0.01)
        XCTAssertNil(model.state.engine.override)
    }

    func testQuitCanTurnTintOffAndNextLaunchRestoresIt() {
        var state = AppState()
        state.prefs.quitBehavior = .turnTintOff
        let (model, backend) = makeModel(at: "2026-10-10 21:00", backendLevel: 30, state: state)
        model.start()
        model.prepareForQuit()
        XCTAssertFalse(backend.status.isEnabled)
        XCTAssertTrue(model.state.tintWasTurnedOffOnQuit)

        let (next, nextBackend) = makeModel(at: "2026-10-10 21:05", backendLevel: 0, state: model.state)
        next.start()
        spin(1.5)
        XCTAssertEqual(nextBackend.status.level, 30, accuracy: 0.01)
        XCTAssertFalse(next.state.tintWasTurnedOffOnQuit)
    }

    func testPresetsConfigureAutomation() {
        let (model, _) = makeModel(at: "2026-10-10 22:30", backendLevel: 0)
        model.start()
        let deep = Presets.recommended.first { $0.id == "deep-night" }!
        model.applyPreset(deep)
        XCTAssertTrue(model.state.engine.schedule.isEnabled)
        XCTAssertNotNil(model.scheduleUndo)
        XCTAssertEqual(model.selectedTab, .schedule)
        model.undoScheduleReplacement()
        XCTAssertFalse(model.state.engine.schedule.isEnabled)
        XCTAssertTrue(AppModel.sameContent(model.state.engine.schedule.transitions, Presets.gentleEvening()))

        let gradual = Presets.recommended.first { $0.id == "gradual-100" }!
        model.applyPreset(gradual)
        XCTAssertEqual(model.state.engine.ramp?.to, 100)
        XCTAssertEqual(model.state.engine.ramp?.duration, 1800)
    }

    func testStatusSummaries() {
        var state = AppState()
        state.engine.schedule.isEnabled = true
        let (model, _) = makeModel(at: "2026-10-10 22:30", backendLevel: 55, state: state)
        model.start()
        XCTAssertTrue(model.summary().title.hasPrefix("Schedule: warming to 70% by"), model.summary().title)
        model.nudge(5)
        XCTAssertTrue(model.summary().title.hasPrefix("Automation paused, resumes at"), model.summary().title)
    }
}

final class IconTests: XCTestCase {
    func testTintColorsComeFromThePaletteAndStayOpaque() {
        for level in stride(from: 0.0, through: 100, by: 5) {
            for dark in [false, true] {
                let color = IconRenderer.tintColor(level: level, dark: dark)
                let expected = WarmthPalette.srgb(level: level, on: dark ? .dark : .light)
                XCTAssertEqual(color.colorSpace, .sRGB)
                XCTAssertEqual(color.alphaComponent, 1)
                XCTAssertEqual(color.redComponent, expected.r, accuracy: 1e-6)
                XCTAssertEqual(color.greenComponent, expected.g, accuracy: 1e-6)
                XCTAssertEqual(color.blueComponent, expected.b, accuracy: 1e-6)
            }
        }
        // 0% on a dark bar is the same white a template icon renders, so 0% to 1% is not a jump.
        let white = IconRenderer.tintColor(level: 0, dark: true)
        XCTAssertEqual(white.redComponent + white.greenComponent + white.blueComponent, 3, accuracy: 1e-6)
    }

    func testSameGlyphAtEveryLevelAndOutlineOnlyWhenOff() {
        XCTAssertFalse(IconRenderer.image(level: 0, off: false).isTemplate, "0% draws the same filled glyph as 1%")
        XCTAssertFalse(IconRenderer.image(level: 1, off: false).isTemplate)
        XCTAssertFalse(IconRenderer.image(level: 100, off: false).isTemplate)
        XCTAssertTrue(IconRenderer.image(level: 30, off: true).isTemplate, "off uses the plain outline")
    }

    func testDynamicColorFollowsAppearance() {
        let dynamic = IconRenderer.dynamicTintColor(level: 60)
        for (name, dark) in [(NSAppearance.Name.darkAqua, true), (.aqua, false)] {
            var resolved: NSColor?
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                resolved = dynamic.usingColorSpace(.sRGB)
            }
            let expected = WarmthPalette.srgb(level: 60, on: dark ? .dark : .light)
            XCTAssertEqual(resolved!.redComponent, expected.r, accuracy: 1e-3, "\(name)")
            XCTAssertEqual(resolved!.blueComponent, expected.b, accuracy: 1e-3, "\(name)")
        }
    }
}
