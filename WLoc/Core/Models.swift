import Foundation

enum WLocError: LocalizedError {
    case invalidEndpoint, missingToken, invalidCoordinate, invalidName, invalidAccuracy
    case http(Int), invalidResponse, redirect, verification, bridgeMissing, parseFailed, unsupportedLink
    case responseTooLarge, invalidFavorites, storageReadOnly
    case wrongClient, appUnavailable, installationExpired, installationFailed, scriptRevisionMissing
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint, .unsupportedLink: return "支持苹果地图、高德、Google Maps 链接，或直接输入纬度,经度。"
        case .missingToken: return "配对密钥须为 16～128 个英文字母或数字，请使用 App 生成的密钥。"
        case .invalidCoordinate: return "纬度须在 -90～90，经度须在 -180～180，且必须是有效数字。"
        case .invalidName: return "请填写地点名称。"
        case .invalidAccuracy: return "水平精度须为 1～1,000,000 米的有效数字。"
        case .http(401), .http(403): return "配对密钥不一致，请重新导入当前工具的专属配置，并停用旧定位组件。"
        case .http(404): return "专属配置未启用或配对信息不一致，请重新安装当前工具的专属配置。"
        case .http(let code): return "本机接口请求失败（HTTP \(code)），请检查配套组件和 MITM。"
        case .invalidResponse, .bridgeMissing: return "未检测到 WLoc 本机桥接。请启动所选工具，安装并启用配套组件，确认 MITM 证书已信任。"
        case .redirect: return "接口发生意外跳转，已停止请求。"
        case .verification: return "返回坐标与提交内容不一致，请刷新后检查。"
        case .parseFailed: return "未找到可靠坐标。可展开短链重试，或使用 App 地图选点、手填经纬度。"
        case .responseTooLarge: return "返回的数据过大，已停止下载。请使用完整地图链接或手动选点。"
        case .invalidFavorites: return "收藏文件包含无效坐标或重复编号。"
        case .storageReadOnly: return "原收藏文件无法读取或备份，已停止写入以避免覆盖，请检查设备储存空间。"
        case .wrongClient: return "当前响应来自其他代理工具，请运行所选工具，或切换到对应的配对记录。"
        case .appUnavailable: return "未能打开所选工具，请确认已安装；也可导出专属配置文件后手动导入。"
        case .installationExpired: return "临时安装服务已结束，请返回重新开始，或导出专属配置文件。"
        case .installationFailed: return "临时安装服务无法启动，请使用导出专属配置文件。"
        case .scriptRevisionMissing: return "此构建缺少固定脚本版本，请使用仓库 Actions 生成的 IPA。"
        }
    }
}

struct Connection: Codable, Equatable {
    static let bridge = "wloc-native-v2"
    static let modernBridge = "wloc-native-v3"
    let key: String
    let client: ProxyClient
    let version: BridgeVersion
    init(key: String, client: ProxyClient = .surge, version: BridgeVersion = .legacyV1) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(clean.count),
              clean.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else {
            throw WLocError.missingToken
        }
        self.key = clean
        self.client = client
        self.version = version
    }
    private enum CodingKeys: String, CodingKey { case key, client, version }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(key: values.decode(String.self, forKey: .key),
                      client: values.decodeIfPresent(ProxyClient.self, forKey: .client) ?? .surge,
                      version: values.decodeIfPresent(BridgeVersion.self, forKey: .version) ?? .legacyV1)
    }
    var expectedBridge: String { version == .legacyV1 ? Self.bridge : Self.modernBridge }
    var displayAddress: String { "\(client.title) 本机 · 无后台" }
    func url(for route: String) -> URL {
        let path = version == .legacyV1 ? "v1/\(route)" : "v3/" + (route == "health" ? route : "\(key)/\(route)")
        return URL(string: "https://gs-loc.apple.com/wloc-native/" + path)!
    }
}

enum BridgeVersion: String, Codable { case legacyV1, localV3 }

struct PairingProfiles: Codable, Equatable {
    var selected: ProxyClient = .surge
    var connections: [String: Connection] = [:]
    var pending: [String: Connection] = [:]
    var verified: Set<ProxyClient> = []
    var current: Connection? { verified.contains(selected) ? connections[selected.rawValue] : nil }
    mutating func set(_ connection: Connection, verified isVerified: Bool) {
        connections[connection.client.rawValue] = connection
        if isVerified { verified.insert(connection.client) } else { verified.remove(connection.client) }
        if isVerified { pending.removeValue(forKey: connection.client.rawValue) }
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
        guard horizontalAccuracy.isFinite, (1...1_000_000).contains(horizontalAccuracy) else { throw WLocError.invalidAccuracy }
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

