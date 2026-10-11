import Foundation

/// An approximate location from the system time zone, read from the tz database's `zone.tab`
/// (which lists a reference city's coordinates for every zone). Needs no location permission.
/// Good to within roughly half an hour of sunset for most places; users can type exact coordinates.
public enum TimeZoneLocation {
    public static let defaultZoneTabPaths = ["/usr/share/zoneinfo/zone.tab", "/usr/share/zoneinfo/zone1970.tab"]

    public static func location(forTimeZone identifier: String, zoneTabPaths: [String] = defaultZoneTabPaths) -> NamedLocation? {
        for path in zoneTabPaths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            if let coordinate = parseZoneTab(text)[identifier] {
                return NamedLocation(name: cityName(forTimeZone: identifier), coordinate: coordinate)
            }
        }
        return nil
    }

    /// "America/Los_Angeles" -> "Los Angeles".
    public static func cityName(forTimeZone identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Maps zone identifiers to coordinates. Lines look like `US\t+404251-0740023\tAmerica/New_York\t...`.
    public static func parseZoneTab(_ text: String) -> [String: GeoCoordinate] {
        var result: [String: GeoCoordinate] = [:]
        for line in text.split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, let coordinate = parseISO6709(String(fields[1])) else { continue }
            result[String(fields[2])] = coordinate
        }
        return result
    }

    /// Parses `+DDMM+DDDMM` or `+DDMMSS+DDDMMSS`.
    public static func parseISO6709(_ text: String) -> GeoCoordinate? {
        let chars = Array(text)
        guard chars.count >= 11, chars[0] == "+" || chars[0] == "-" else { return nil }
        guard let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" }) else { return nil }
        let latPart = String(chars[0..<split])
        let lonPart = String(chars[split...])
        guard let lat = parseAngle(latPart, degreeDigits: 2), let lon = parseAngle(lonPart, degreeDigits: 3) else { return nil }
        let coordinate = GeoCoordinate(latitude: lat, longitude: lon)
        return coordinate.isValid ? coordinate : nil
    }

    static func parseAngle(_ text: String, degreeDigits: Int) -> Double? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = Array(text.dropFirst())
        guard digits.allSatisfy(\.isNumber), digits.count == degreeDigits + 2 || digits.count == degreeDigits + 4 else { return nil }
        func number(_ range: Range<Int>) -> Double { Double(String(digits[range])) ?? 0 }
        var value = number(0..<degreeDigits) + number(degreeDigits..<degreeDigits + 2) / 60
        if digits.count == degreeDigits + 4 { value += number(degreeDigits + 2..<degreeDigits + 4) / 3600 }
        return sign == "-" ? -value : value
    }
}
