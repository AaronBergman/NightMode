import Foundation
import XCTest
@testable import NightModeCore

enum TZ {
    static let la = TimeZone(identifier: "America/Los_Angeles")!
}

func calendar(_ tz: TimeZone = TZ.la) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal
}

/// "2026-10-10 21:30" (or with seconds) in the given zone.
func at(_ text: String, _ tz: TimeZone = TZ.la) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = text.count > 16 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
    guard let d = f.date(from: text) else { fatalError("bad date \(text)") }
    return d
}

func env(brightness: Double? = nil, location: GeoCoordinate? = nil, tz: TimeZone = TZ.la) -> EngineEnvironment {
    EngineEnvironment(calendar: calendar(tz), location: location, brightness: brightness)
}

func XCTAssertLevel(_ value: Double?, _ expected: Double, accuracy: Double = 0.01,
                    _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let value else { return XCTFail("nil level, expected \(expected) \(message)", file: file, line: line) }
    XCTAssertEqual(value, expected, accuracy: accuracy, message, file: file, line: line)
}
