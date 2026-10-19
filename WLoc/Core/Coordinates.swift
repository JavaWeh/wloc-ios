// SPDX-License-Identifier: AGPL-3.0-or-later
// Formulas ported from ios151/wloc worker/src/gcj-browser.js; see THIRD_PARTY.md.
import Foundation

struct Coordinate: Equatable, Codable {
    var latitude: Double
    var longitude: Double
    var text: String { String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude) }
    var inChinaBounds: Bool { (72.004...137.8347).contains(longitude) && (0.8293...55.8271).contains(latitude) }
}

enum CoordinateSystem: String, CaseIterable, Identifiable {
    case wgs84 = "WGS-84", gcj02 = "GCJ-02", bd09 = "BD-09"
    var id: String { rawValue }
    func toWGS(_ c: Coordinate) -> Coordinate {
        switch self {
        case .wgs84: return c
        case .gcj02: return Coordinates.gcjToWGS(c)
        case .bd09:
            let x = c.longitude - 0.0065, y = c.latitude - 0.006
            let z = sqrt(x*x + y*y) - 0.00002 * sin(y * .pi * 3000 / 180)
            let theta = atan2(y,x) - 0.000003 * cos(x * .pi * 3000 / 180)
            return Coordinates.gcjToWGS(Coordinate(latitude: z*sin(theta), longitude: z*cos(theta)))
        }
    }
}

enum Coordinates {
    static func wgsToGCJ(_ c: Coordinate) -> Coordinate {
        guard c.inChinaBounds else { return c }
        let x = c.longitude - 105, y = c.latitude - 35
        var lat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        lat += (20*sin(6*x * .pi) + 20*sin(2*x * .pi))*2/3
        lat += (20*sin(y * .pi) + 40*sin(y/3 * .pi))*2/3
        lat += (160*sin(y/12 * .pi) + 320*sin(y * .pi/30))*2/3
        var lon = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        lon += (20*sin(6*x * .pi) + 20*sin(2*x * .pi))*2/3
        lon += (20*sin(x * .pi) + 40*sin(x/3 * .pi))*2/3
        lon += (150*sin(x/12 * .pi) + 300*sin(x/30 * .pi))*2/3
        let rad = c.latitude/180 * .pi
        let magic = 1 - 0.00669342162296594323 * pow(sin(rad),2)
        lat = lat*180 / ((6378245*(1-0.00669342162296594323)/(magic*sqrt(magic))) * .pi)
        lon = lon*180 / ((6378245/sqrt(magic))*cos(rad) * .pi)
        return Coordinate(latitude: c.latitude+lat, longitude: c.longitude+lon)
    }
    static func gcjToWGS(_ c: Coordinate) -> Coordinate {
        guard c.inChinaBounds else { return c }
        var guess = c
        for _ in 0..<8 {
            let g = wgsToGCJ(guess)
            let dlat = g.latitude-c.latitude, dlon = g.longitude-c.longitude
            guess.latitude -= dlat
            guess.longitude -= dlon
            if abs(dlat)<1e-9 && abs(dlon)<1e-9 { break }
        }
        return guess
    }
}
