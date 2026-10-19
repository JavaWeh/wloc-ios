import Foundation

struct ParsedLocation: Equatable {
    var coordinate: Coordinate
    var name: String
    var system: CoordinateSystem
    var source: String
    var warning: String?
}

enum MapLinkParser {
    private static let number = #"([+-]?(?:\d+(?:\.\d*)?|\.\d+))"#

    static func firstURL(in text: String) -> URL? {
        guard let hit = captures(#"(?:https?://|iosamap://)[^\s<>\"“”]+"#, in: text).first?.first else { return nil }
        let clean = hit.trimmingCharacters(in: CharacterSet(charactersIn: "，。；)]}）"))
        return URL(string: clean)
    }

    static func networkAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        if ["maps.apple.com", "maps.apple", "maps.app.goo.gl", "goo.gl", "maps.google.com", "maps.google.cn"].contains(host) { return true }
        if host == "google.com" || host == "www.google.com" || host == "google.cn" || host == "www.google.cn" { return url.path.hasPrefix("/maps") }
        return host == "amap.com" || host.hasSuffix(".amap.com") || host == "gaode.com" || host.hasSuffix(".gaode.com")
    }

    static func parse(_ text: String) throws -> ParsedLocation? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = firstURL(in: text) else {
            if let pair = pair(text, exact: true) {
                return try result(pair, name: "", source: "经纬度", system: .wgs84)
            }
            return nil
        }
        let scheme = url.scheme?.lowercased()
        var secureParts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if scheme == "http" { secureParts?.scheme = "https" }
        guard scheme == "iosamap" || secureParts?.url.map(networkAllowed) == true else { throw WLocError.unsupportedLink }
        let host = url.host?.lowercased() ?? ""
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { items.first(where: { $0.name.lowercased() == key })?.value }
        let isApple = host == "maps.apple.com" || host == "maps.apple"
        let isAMap = scheme == "iosamap" || host == "amap.com" || host.hasSuffix(".amap.com") || host.hasSuffix(".gaode.com") || host == "gaode.com"
        let name = value("name") ?? value("poiname") ?? ""
        if isApple {
            for key in ["coordinate", "ll"] {
                if let raw = value(key), let coordinate = pair(raw, exact: true) {
                    let qname = value("q").flatMap { pair($0, exact: true) == nil ? $0 : nil } ?? ""
                    return try result(coordinate, name: name.isEmpty ? qname : name, source: "苹果地图",
                                      system: coordinate.inChinaBounds ? .gcj02 : .wgs84,
                                      warning: coordinate.inChinaBounds ? "国内苹果地图暂按 GCJ-02 识别，请核对；港澳台或 WGS-84 链接请切换坐标系。" : nil)
                }
            }
        } else if isAMap {
            let system: CoordinateSystem = value("coordinate")?.lowercased() == "wgs84" ? .wgs84 : .gcj02
            for key in ["position", "lnglat"] {
                if let raw = value(key), let reversed = pair(raw, exact: true) {
                    return try result(Coordinate(latitude: reversed.longitude, longitude: reversed.latitude), name: name, source: "高德地图", system: system)
                }
            }
            if let lat = value("lat").flatMap(Double.init), let lon = (value("lon") ?? value("lng")).flatMap(Double.init) {
                return try result(Coordinate(latitude: lat, longitude: lon), name: name, source: "高德地图", system: system)
            }
            for key in ["p", "q"] {
                if let raw = value(key) {
                    let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                    let offset = key == "p" ? 1 : 0
                    if parts.count >= offset+2, let lat = Double(parts[offset]), let lon = Double(parts[offset+1]) {
                        return try result(Coordinate(latitude: lat, longitude: lon), name: parts.count > offset+2 ? parts[offset+2] : name,
                                          source: "高德地图", system: system)
                    }
                }
            }
        } else {
            for key in ["query", "q", "destination", "daddr"] {
                if let raw = value(key), let coordinate = pair(raw, exact: true) {
                    return try result(coordinate, name: name, source: "Google Maps", system: .wgs84,
                                      warning: coordinate.inChinaBounds ? "Google 国内道路坐标可能为 GCJ-02，请对照原地图确认坐标系。" : nil)
                }
            }
            let decoded = url.absoluteString.removingPercentEncoding ?? url.absoluteString
            let pins = captures("!3d" + number + "!4d" + number, in: decoded)
            if pins.count > 1 { throw WLocError.parseFailed }
            let pathParts = url.pathComponents
            let placeName = pathParts.firstIndex(of: "place").flatMap { $0+1 < pathParts.count ? pathParts[$0+1] : nil }?.replacingOccurrences(of: "+", with: " ") ?? name
            if let pin = pins.first, let lat = Double(pin[1]), let lon = Double(pin[2]) {
                return try result(Coordinate(latitude: lat, longitude: lon), name: placeName, source: "Google Maps 地点坐标", system: .wgs84,
                                  warning: Coordinate(latitude: lat, longitude: lon).inChinaBounds ? "Google 国内道路坐标可能为 GCJ-02，请核对。" : nil)
            }
            if let camera = captures("@" + number + "," + number, in: decoded).first,
               let lat = Double(camera[1]), let lon = Double(camera[2]) {
                return try result(Coordinate(latitude: lat, longitude: lon), name: placeName, source: "Google Maps 地图中心", system: .wgs84,
                                  warning: "链接仅包含地图视口中心，可能不是地点针脚。请在地图中仔细核对后再收藏。")
            }
        }
        return nil
    }

    private static func result(_ coordinate: Coordinate, name: String, source: String, system: CoordinateSystem, warning: String? = nil) throws -> ParsedLocation {
        try validateCoordinates(coordinate.latitude, coordinate.longitude)
        return ParsedLocation(coordinate: coordinate, name: name, system: system, source: source, warning: warning)
    }
    private static func pair(_ value: String, exact: Bool) -> Coordinate? {
        let pattern = (exact ? "^\\s*" : "") + number + "\\s*[,，]\\s*" + number + (exact ? "\\s*$" : "")
        guard let hit = captures(pattern, in: value).first, let lat = Double(hit[1]), let lon = Double(hit[2]) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }
    static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
        }
    }
}

final class MapLinkResolver {
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        }
    }
    deinit { session.invalidateAndCancel() }
    func resolve(_ text: String) async throws -> ParsedLocation {
        if let hit = try MapLinkParser.parse(text) { return hit }
        guard let original = MapLinkParser.firstURL(in: text), var parts = URLComponents(url: original, resolvingAgainstBaseURL: false) else { throw WLocError.parseFailed }
        if parts.scheme == "http" { parts.scheme = "https" }
        guard var current = parts.url, MapLinkParser.networkAllowed(current) else { throw WLocError.parseFailed }
        for _ in 0..<5 {
            try Task.checkCancellation()
            guard MapLinkParser.networkAllowed(current) else { throw WLocError.unsupportedLink }
            var request = URLRequest(url: current)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { break }
            if (300...399).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current)?.absoluteURL {
                guard MapLinkParser.networkAllowed(next) else { throw WLocError.unsupportedLink }
                if let hit = try MapLinkParser.parse(next.absoluteString) { return hit }
                current = next
                continue
            }
            guard response.statusCode == 200, data.count <= 512*1024 else { break }
            let html = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "&amp;", with: "&")
            let patterns = [#"<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)"#,
                            #"<meta[^>]+property=["']og:url["'][^>]+content=["']([^"']+)"#,
                            #"(?:window\.location(?:\.href)?|location\.replace)\s*(?:=|\()\s*["']([^"']+)"#]
            var next: URL?
            for pattern in patterns {
                if let candidate = MapLinkParser.captures(pattern, in: html).first?[1],
                   let url = URL(string: candidate, relativeTo: current)?.absoluteURL, MapLinkParser.networkAllowed(url) {
                    if let hit = try MapLinkParser.parse(url.absoluteString) { return hit }
                    if url != current { next = url; break }
                }
            }
            guard let next else { break }
            current = next
        }
        throw WLocError.parseFailed
    }
}
