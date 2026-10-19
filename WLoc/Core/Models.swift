import Foundation

enum WLocError: LocalizedError {
    case invalidEndpoint, missingToken, invalidCoordinate, invalidName, invalidAccuracy
    case http(Int), invalidResponse, redirect, verification

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请输入有效的 HTTPS 选点网页或 loc.json 地址。"
        case .missingToken: return "地址中缺少 token，请粘贴完整的选点链接。"
        case .invalidCoordinate: return "纬度须在 -90～90，经度须在 -180～180，且必须是有效数字。"
        case .invalidName: return "请填写地点名称。"
        case .invalidAccuracy: return "精度须为至少 1 米的有效数字。"
        case .http(401), .http(403): return "服务拒绝访问，请检查 token 是否正确或已被停用。"
        case .http(404): return "找不到接口，请检查服务地址是否与现有选点网页一致。"
        case .http(let status): return "请求失败（HTTP \(status)），请稍后重试。"
        case .invalidResponse: return "服务返回的数据无法识别，请确认使用参考项目的选点服务。"
        case .redirect: return "服务发生重定向。请填写最终 HTTPS 地址，避免携带 token 跳转。"
        case .verification: return "服务返回的坐标与提交内容不一致，请刷新后检查。"
        }
    }
}

/// Credentials are persisted only in Keychain by the app layer.
struct Connection: Codable, Equatable {
    let baseURL: URL
    let token: String
    let extraQuery: [String: String]

    init(link: String) throws {
        guard var parts = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil else {
            throw WLocError.invalidEndpoint
        }
        let items = parts.queryItems ?? []
        let tokens = items.filter { $0.name == "token" }
        guard tokens.count == 1, let token = tokens.first?.value, !token.isEmpty else {
            throw WLocError.missingToken
        }
        self.token = token
        var query: [String: String] = [:]
        for item in items where item.name != "token" { query[item.name] = item.value ?? "" }
        extraQuery = query
        parts.query = nil
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/loc.json") { path = String(path.dropLast(9)) }
        parts.path = path
        guard let url = parts.url else { throw WLocError.invalidEndpoint }
        baseURL = url
    }

    var displayAddress: String { baseURL.absoluteString }

    func url(for route: String) throws -> URL {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WLocError.invalidEndpoint
        }
        parts.path = baseURL.path + "/" + route
        parts.queryItems = extraQuery.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        } + [URLQueryItem(name: "token", value: token)]
        // URLSearchParams on the upstream server decodes a literal + as a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw WLocError.invalidEndpoint }
        return url
    }
}

struct Place: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double = 39

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WLocError.invalidName }
        try validateCoordinates(latitude, longitude)
        guard horizontalAccuracy.isFinite, horizontalAccuracy >= 1 else { throw WLocError.invalidAccuracy }
    }

    var coordinateText: String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}

func validateCoordinates(_ latitude: Double, _ longitude: Double) throws {
    guard latitude.isFinite, longitude.isFinite,
          (-90...90).contains(latitude), (-180...180).contains(longitude) else {
        throw WLocError.invalidCoordinate
    }
}

struct RemoteLocation: Codable, Equatable {
    var enabled: Bool
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double?

    // Optional accuracy is allowed on older deployments; enabled and coordinates are required.
    func validate() throws { try validateCoordinates(latitude, longitude) }

    func matches(_ place: Place) -> Bool {
        enabled && abs(latitude - place.latitude) < 0.000001 && abs(longitude - place.longitude) < 0.000001
    }

    var coordinateText: String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}

