import XCTest
@testable import NightModeCore

final class PersistenceTests: XCTestCase {
    func testRoundTrip() throws {
        var state = AppState()
        state.engine.setLevel(37, now: at("2026-10-10 21:00"), env: env())
        state.engine.startRamp(origin: .current, to: 90, start: at("2026-10-10 22:00"), duration: 1800,
                               easing: .smooth, now: at("2026-10-10 21:00"), env: env())
        state.engine.schedule = Schedule(isEnabled: true, transitions: Presets.sunsetToSunrise())
        state.engine.brightness = BrightnessConfig(isEnabled: true, curve: .standard)
        state.engine.pausePolicy = .oneHour
        state.engine.override = Override(level: 12, since: at("2026-10-10 21:00"), until: at("2026-10-10 22:00"), brightnessAnchor: 0.4)
        state.prefs.manualLocation = NamedLocation(name: "Somewhere", coordinate: GeoCoordinate(latitude: 1, longitude: 2))
        state.prefs.rampDraft.minutes = 45
        state.prefs.quitBehavior = .turnTintOff
        state.tintWasTurnedOffOnQuit = true
        let decoded = try AppState.decode(state.encoded())
        XCTAssertEqual(decoded, state)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let empty = try AppState.decode(Data("{}".utf8))
        XCTAssertEqual(empty.engine.manualLevel, 0)
        XCTAssertTrue(empty.engine.isOn)
        XCTAssertEqual(empty.engine.schedule.transitions.count, 3, "first run comes with the Gentle evening schedule, switched off")
        XCTAssertFalse(empty.engine.schedule.isEnabled)
        XCTAssertTrue(empty.prefs.hotkeysEnabled)

        let partial = try AppState.decode(Data(#"{"engine":{"manualLevel":33,"pausePolicy":"somethingNew"},"future":1}"#.utf8))
        XCTAssertEqual(partial.engine.manualLevel, 33)
        XCTAssertEqual(partial.engine.pausePolicy, .untilNextChange)
    }

    func testISO6709Parsing() {
        let ny = TimeZoneLocation.parseISO6709("+404251-0740023")!
        XCTAssertEqual(ny.latitude, 40 + 42 / 60.0 + 51 / 3600.0, accuracy: 1e-9)
        XCTAssertEqual(ny.longitude, -(74 + 0 / 60.0 + 23 / 3600.0), accuracy: 1e-9)
        let short = TimeZoneLocation.parseISO6709("-3352+15113")!
        XCTAssertEqual(short.latitude, -(33 + 52 / 60.0), accuracy: 1e-9)
        XCTAssertEqual(short.longitude, 151 + 13 / 60.0, accuracy: 1e-9)
        XCTAssertNil(TimeZoneLocation.parseISO6709("garbage"))
        XCTAssertNil(TimeZoneLocation.parseISO6709("+9999+99999"))
    }

    func testZoneTabParsingAndSystemFile() {
        let text = "# comment\nUS\t+340308-1181434\tAmerica/Los_Angeles\tPacific\nXX\tbad\tNowhere/Bad\n"
        let parsed = TimeZoneLocation.parseZoneTab(text)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed["America/Los_Angeles"]!.latitude, 34.0522, accuracy: 0.01)
        XCTAssertEqual(TimeZoneLocation.cityName(forTimeZone: "America/Los_Angeles"), "Los Angeles")
        // The real file shipped with macOS.
        let la = TimeZoneLocation.location(forTimeZone: "America/Los_Angeles")
        XCTAssertNotNil(la)
        XCTAssertEqual(la?.coordinate.longitude ?? 0, -118.24, accuracy: 0.05)
        XCTAssertNil(TimeZoneLocation.location(forTimeZone: "Not/AZone"))
    }

    func testPresetsAreSane() {
        XCTAssertEqual(Set(Presets.recommended.map(\.id)).count, Presets.recommended.count)
        for preset in Presets.recommended {
            if case .schedule(let transitions) = preset.action {
                XCTAssertFalse(transitions.isEmpty)
                XCTAssertEqual(preset.needsLocation, transitions.contains { $0.anchor.isSolar }, preset.id)
            }
        }
    }
}
