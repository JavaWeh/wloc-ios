import Foundation

enum WLocError: LocalizedError {
    case invalidEndpoint, missingToken, invalidCoordinate, invalidName, invalidAccuracy
    case http(Int), invalidResponse, redirect, verification, bridgeMissing, parseFailed, unsupportedLink
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint, .unsupportedLink: return "支持苹果地图、高德、Google Maps 链接，或直接输入纬度,经度。"
        case .missingToken: return "配对密钥须为 16～128 个英文字母或数字，请使用 App 生成的密钥。"
        case .invalidCoordinate: return "纬度须在 -90～90，经度须在 -180～180，且必须是有效数字。"
        case .invalidName: return "请填写地点名称。"
        case .invalidAccuracy: return "水平精度须为至少 1 米的有效数字。"
        case .http(401), .http(403): return "配对密钥不一致，请把 App 中的密钥填入 Surge 配套模块的 key 参数。"
        case .http(let code): return "Surge 本机接口请求失败（HTTP \(code)），请检查配套模块和 MITM。"
        case .invalidResponse, .bridgeMissing: return "未检测到 WLoc 本机桥接。请启动 Surge，安装并启用本 App 的配套模块，确认 MITM 证书已信任。无需部署后台。"
        case .redirect: return "接口发生意外跳转，已停止请求。"
        case .verification: return "返回坐标与提交内容不一致，请刷新后检查。"
        case .parseFailed: return "未找到可靠坐标。可展开短链重试，或使用 App 地图选点、手填经纬度。"
        }
    }
}

struct Connection: Codable, Equatable {
    static let bridge = "wloc-native-v2"
    let key: String
    init(key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(clean.count),
              clean.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else {
            throw WLocError.missingToken
        }
        self.key = clean
    }
    var displayAddress: String { "Surge 本机 · 无后台" }
    func url(for route: String) -> URL {
        URL(string: "https://gs-loc.apple.com/wloc-native/v1/" + route)!
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
    var coordinateText: String { Coordinate(latitude: latitude, longitude: longitude).text }
}

func validateCoordinates(_ latitude: Double, _ longitude: Double) throws {
    guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
        throw WLocError.invalidCoordinate
    }
}

struct RemoteLocation: Codable, Equatable {
    var enabled: Bool
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double?
    func validate() throws { try validateCoordinates(latitude, longitude) }
    func matches(_ place: Place) -> Bool {
        enabled && abs(latitude - place.latitude) < 0.000001 && abs(longitude - place.longitude) < 0.000001
    }
    var coordinateText: String { Coordinate(latitude: latitude, longitude: longitude).text }
}

