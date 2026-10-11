import XCTest
@testable import NightModeCore

/// Ground truth generated with the `astral` Python package (an independent NOAA implementation):
/// astral.sun.sunrise / sunset for each city and local date, as Unix timestamps.
final class SolarTests: XCTestCase {
    static let truth: [(String, Double, Double, String, String, Double, Double)] = [
        ("LosAngeles", 34.0522, -118.2437, "America/Los_Angeles", "2026-03-08", 1772979162, 1773021304),
        ("LosAngeles", 34.0522, -118.2437, "America/Los_Angeles", "2026-03-20", 1774014996, 1774058673),
        ("LosAngeles", 34.0522, -118.2437, "America/Los_Angeles", "2026-06-21", 1782045738, 1782097646),
        ("LosAngeles", 34.0522, -118.2437, "America/Los_Angeles", "2026-09-22", 1790084485, 1790128154),
        ("LosAngeles", 34.0522, -118.2437, "America/Los_Angeles", "2026-11-01", 1793542375, 1793581179),
        ("LosAngeles", 34.0522, -118.2437, "America/Los_Angeles", "2026-12-21", 1797864895, 1797900449),
        ("NewYork", 40.7128, -74.006, "America/New_York", "2026-03-08", 1772968746, 1773010498),
        ("NewYork", 40.7128, -74.006, "America/New_York", "2026-03-20", 1774004370, 1774048077),
        ("NewYork", 40.7128, -74.006, "America/New_York", "2026-06-21", 1782033917, 1782088229),
        ("NewYork", 40.7128, -74.006, "America/New_York", "2026-09-22", 1790073832, 1790117570),
        ("NewYork", 40.7128, -74.006, "America/New_York", "2026-11-01", 1793532398, 1793569916),
        ("NewYork", 40.7128, -74.006, "America/New_York", "2026-12-21", 1797855411, 1797888693),
        ("London", 51.5074, -0.1278, "Europe/London", "2026-03-08", 1772951445, 1772992361),
        ("London", 51.5074, -0.1278, "Europe/London", "2026-03-20", 1773986619, 1774030394),
        ("London", 51.5074, -0.1278, "Europe/London", "2026-06-21", 1782013407, 1782073272),
        ("London", 51.5074, -0.1278, "Europe/London", "2026-09-22", 1790056006, 1790099924),
        ("London", 51.5074, -0.1278, "Europe/London", "2026-11-01", 1793516050, 1793550790),
        ("London", 51.5074, -0.1278, "Europe/London", "2026-12-21", 1797840246, 1797868383),
        ("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-03-08", 1772912921, 1772958166),
        ("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-03-20", 1773950289, 1773994003),
        ("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-06-21", 1781989211, 1782024815),
        ("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-09-22", 1790019934, 1790063463),
        ("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-11-01", 1793472920, 1793521355),
        ("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-12-21", 1797792053, 1797843911),
        ("Reykjavik", 64.1466, -21.9426, "Atlantic/Reykjavik", "2026-03-08", 1772957484, 1772996824),
        ("Reykjavik", 64.1466, -21.9426, "Atlantic/Reykjavik", "2026-03-20", 1773991739, 1774035782),
        ("Reykjavik", 64.1466, -21.9426, "Atlantic/Reykjavik", "2026-06-21", 1782010580, 1782000158),
        ("Reykjavik", 64.1466, -21.9426, "Atlantic/Reykjavik", "2026-09-22", 1790061063, 1790105295),
        ("Reykjavik", 64.1466, -21.9426, "Atlantic/Reykjavik", "2026-11-01", 1793524285, 1793553005),
        ("Reykjavik", 64.1466, -21.9426, "Atlantic/Reykjavik", "2026-12-21", 1797852191, 1797866913),
        ("Quito", -0.1807, -78.4678, "America/Guayaquil", "2026-03-08", 1772968883, 1773012463),
        ("Quito", -0.1807, -78.4678, "America/Guayaquil", "2026-03-20", 1774005489, 1774049059),
        ("Quito", -0.1807, -78.4678, "America/Guayaquil", "2026-06-21", 1782040353, 1782083935),
        ("Quito", -0.1807, -78.4678, "America/Guayaquil", "2026-09-22", 1790075008, 1790118576),
        ("Quito", -0.1807, -78.4678, "America/Guayaquil", "2026-11-01", 1793530437, 1793574050),
        ("Quito", -0.1807, -78.4678, "America/Guayaquil", "2026-12-21", 1797851290, 1797894956),
        ("Tokyo", 35.6762, 139.6503, "Asia/Tokyo", "2026-03-08", 1772917370, 1772959330),
        ("Tokyo", 35.6762, 139.6503, "Asia/Tokyo", "2026-03-20", 1773953158, 1773996749),
        ("Tokyo", 35.6762, 139.6503, "Asia/Tokyo", "2026-06-21", 1781983564, 1782036012),
        ("Tokyo", 35.6762, 139.6503, "Asia/Tokyo", "2026-09-22", 1790022551, 1790066327),
        ("Tokyo", 35.6762, 139.6503, "Asia/Tokyo", "2026-11-01", 1793480587, 1793519179),
        ("Tokyo", 35.6762, 139.6503, "Asia/Tokyo", "2026-12-21", 1797803235, 1797838277),
        ("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-03-08", 1772988364, 1773031101),
        ("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-03-20", 1774024522, 1774068144),
        ("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-06-21", 1782057036, 1782105365),
        ("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-09-22", 1790094031, 1790137632),
        ("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-11-01", 1793550884, 1793591695),
        ("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-12-21", 1797872688, 1797911678),
    ]

    func testMatchesAstralWithinNinetySeconds() {
        var worst = 0.0
        for (name, lat, lon, tzID, day, rise, set) in Self.truth {
            let tz = TimeZone(identifier: tzID)!
            let result = Solar.day(containing: at(day + " 12:00", tz), calendar: calendar(tz),
                                   coordinate: GeoCoordinate(latitude: lat, longitude: lon))
            XCTAssertNil(result.polar, name)
            guard let r = result.sunrise, let s = result.sunset else { XCTFail("missing \(name) \(day)"); continue }
            XCTAssertEqual(r.timeIntervalSince1970, rise, accuracy: 90, "sunrise \(name) \(day)")
            if set < rise {
                // Sunset after midnight (Reykjavik in June): astral returns the one on this calendar date,
                // which belongs to the previous evening. NightMode wants this evening's, about a day later.
                XCTAssertGreaterThan(s, result.solarNoon, "sunset \(name) \(day)")
                XCTAssertEqual(s.timeIntervalSince1970 - set, 86_400, accuracy: 600, "late sunset \(name) \(day)")
                worst = max(worst, abs(r.timeIntervalSince1970 - rise))
                continue
            }
            XCTAssertEqual(s.timeIntervalSince1970, set, accuracy: 90, "sunset \(name) \(day)")
            worst = max(worst, abs(r.timeIntervalSince1970 - rise), abs(s.timeIntervalSince1970 - set))
        }
        print("Solar: worst difference vs astral = \(worst) s over \(Self.truth.count) city-days")
    }

    func testAnyTimeOfDayGivesSameLocalDay() {
        let tz = TimeZone(identifier: "Australia/Sydney")!
        let coordinate = GeoCoordinate(latitude: -33.8688, longitude: 151.2093)
        let morning = Solar.day(containing: at("2026-06-21 00:10", tz), calendar: calendar(tz), coordinate: coordinate)
        let night = Solar.day(containing: at("2026-06-21 23:50", tz), calendar: calendar(tz), coordinate: coordinate)
        XCTAssertEqual(morning.sunrise, night.sunrise)
        XCTAssertEqual(morning.sunset, night.sunset)
    }

    func testPolarNightAndMidnightSun() {
        let tz = TimeZone(identifier: "Europe/Oslo")!
        let tromso = GeoCoordinate(latitude: 69.6492, longitude: 18.9553)
        let winter = Solar.day(containing: at("2026-12-21 12:00", tz), calendar: calendar(tz), coordinate: tromso)
        XCTAssertEqual(winter.polar, .alwaysDown)
        XCTAssertNil(winter.sunrise)
        let summer = Solar.day(containing: at("2026-06-21 12:00", tz), calendar: calendar(tz), coordinate: tromso)
        XCTAssertEqual(summer.polar, .alwaysUp)
        XCTAssertNil(summer.sunset)
    }
}
