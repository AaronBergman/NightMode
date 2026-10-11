import Foundation

/// A place on Earth. Latitude north positive, longitude east positive (degrees).
public struct GeoCoordinate: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

/// Sunrise and sunset from the NOAA solar calculator equations (the same maths as the NOAA
/// spreadsheet and the `astral` Python package). Accurate to about a minute at normal latitudes.
/// Computed locally: no network, no location permission.
public enum Solar {
    public enum Polar: Equatable, Sendable {
        /// The sun stays up all day (midnight sun).
        case alwaysUp
        /// The sun never rises (polar night).
        case alwaysDown
    }

    public struct Day: Equatable, Sendable {
        public var sunrise: Date?
        public var sunset: Date?
        public var solarNoon: Date
        /// Set when there is no sunrise or sunset on this day.
        public var polar: Polar?
    }

    /// Standard "official" zenith: 90 degrees plus refraction and the sun's radius.
    static let zenith = 90.833

    /// Sun times for the local calendar day (in `calendar.timeZone`) that contains `date`.
    public static func day(containing date: Date, calendar: Calendar, coordinate: GeoCoordinate) -> Day {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        let localNoon = calendar.date(from: comps) ?? date

        // Solar noon nearest to local clock noon, refined once with parameters at that instant.
        var noon = solarNoon(near: localNoon, longitude: coordinate.longitude)
        noon = solarNoon(near: noon, longitude: coordinate.longitude)

        // Sunrise and sunset each get their own pass (declination changes a little over the day).
        let first = hourAngleMinutes(at: noon, latitude: coordinate.latitude)
        switch first {
        case .polar(let polar):
            return Day(sunrise: nil, sunset: nil, solarNoon: noon, polar: polar)
        case .minutes(let halfDay):
            let roughRise = noon.addingTimeInterval(-halfDay * 60)
            let roughSet = noon.addingTimeInterval(halfDay * 60)
            let rise = refine(event: roughRise, noonNear: noon, latitude: coordinate.latitude, longitude: coordinate.longitude, rising: true)
            let set = refine(event: roughSet, noonNear: noon, latitude: coordinate.latitude, longitude: coordinate.longitude, rising: false)
            return Day(sunrise: rise ?? roughRise, sunset: set ?? roughSet, solarNoon: noon, polar: nil)
        }
    }

    // MARK: - NOAA equations

    struct Parameters {
        var declination: Double  // radians
        var equationOfTime: Double  // minutes
    }

    static func julianCentury(_ date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        return (julianDay - 2_451_545) / 36_525
    }

    static func parameters(at date: Date) -> Parameters {
        let t = julianCentury(date)
        let meanLong = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnom = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccent = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let mRad = meanAnom.radians
        let center = sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * mRad) * (0.019993 - 0.000101 * t)
            + sin(3 * mRad) * 0.000289
        let trueLong = meanLong + center
        let omega = 125.04 - 1934.136 * t
        let appLong = trueLong - 0.00569 - 0.00478 * sin(omega.radians)
        let meanObliq = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliq = meanObliq + 0.00256 * cos(omega.radians)
        let declination = asin(sin(obliq.radians) * sin(appLong.radians))
        let y = pow(tan(obliq.radians / 2), 2)
        let l0 = meanLong.radians
        let eqTime = 4 * (y * sin(2 * l0)
            - 2 * eccent * sin(mRad)
            + 4 * eccent * y * sin(mRad) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * eccent * eccent * sin(2 * mRad)).degrees
        return Parameters(declination: declination, equationOfTime: eqTime)
    }

    static func solarNoon(near anchor: Date, longitude: Double) -> Date {
        let eq = parameters(at: anchor).equationOfTime
        let utcMidnight = floor(anchor.timeIntervalSince1970 / 86_400) * 86_400
        var noon = utcMidnight + (720 - 4 * longitude - eq) * 60
        let a = anchor.timeIntervalSince1970
        while noon - a > 43_200 { noon -= 86_400 }
        while noon - a < -43_200 { noon += 86_400 }
        return Date(timeIntervalSince1970: noon)
    }

    enum HourAngle {
        case minutes(Double)  // half of the daylight span, in minutes
        case polar(Polar)
    }

    static func hourAngleMinutes(at date: Date, latitude: Double) -> HourAngle {
        let decl = parameters(at: date).declination
        let lat = latitude.radians
        let cosH = (cos(zenith.radians) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
        if cosH > 1 { return .polar(.alwaysDown) }
        if cosH < -1 { return .polar(.alwaysUp) }
        return .minutes(acos(cosH).degrees * 4)
    }

    /// One more pass using the declination and equation of time at the event itself.
    static func refine(event: Date, noonNear: Date, latitude: Double, longitude: Double, rising: Bool) -> Date? {
        let params = parameters(at: event)
        let lat = latitude.radians
        let cosH = (cos(zenith.radians) - sin(lat) * sin(params.declination)) / (cos(lat) * cos(params.declination))
        guard cosH >= -1, cosH <= 1 else { return nil }
        let halfDay = acos(cosH).degrees * 4
        let utcMidnight = floor(noonNear.timeIntervalSince1970 / 86_400) * 86_400
        var noon = utcMidnight + (720 - 4 * longitude - params.equationOfTime) * 60
        let a = noonNear.timeIntervalSince1970
        while noon - a > 43_200 { noon -= 86_400 }
        while noon - a < -43_200 { noon += 86_400 }
        return Date(timeIntervalSince1970: noon + (rising ? -halfDay : halfDay) * 60)
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
