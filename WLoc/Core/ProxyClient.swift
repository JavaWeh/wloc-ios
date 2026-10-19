import Foundation

enum ProxyClient: String, CaseIterable, Codable, Identifiable, Hashable {
    case surge, loon, stash, quantumultX, shadowrocket
    var id: String { rawValue }
    var title: String {
        switch self {
        case .surge: return "Surge"
        case .loon: return "Loon"
        case .stash: return "Stash"
        case .quantumultX: return "Quantumult X"
        case .shadowrocket: return "Shadowrocket"
        }
    }
    var fileExtension: String {
        switch self {
        case .surge, .shadowrocket: return "sgmodule"
        case .loon: return "lnplugin"
        case .stash: return "stoverride"
        case .quantumultX: return "snippet"
        }
    }
    var scheme: String { self == .quantumultX ? "quantumult-x" : rawValue }
    // Remote rewrite references in QX keep their download URL; prefer a local import.
    var prefersFileImport: Bool { self == .quantumultX || self == .shadowrocket }
    var importInstructions: String {
        switch self {
        case .surge: return "Surge → 模块：导入专属 sgmodule，启用后停用旧定位模块。"
        case .loon: return "Loon → 插件：导入专属 lnplugin，启用插件、脚本和 MITM。"
        case .stash: return "Stash → 覆写：导入专属 stoverride，并启用覆写和 MITM。"
        case .quantumultX: return "Quantumult X → 重写：导入本地 snippet（可先保存到文件），启用重写和 MitM。临时地址引用不适合长期更新，请优先本地文件。"
        case .shadowrocket: return "Shadowrocket → 配置 → 模块：导入专属 sgmodule 并启用。快捷安装入口尚待真机验证。"
        }
    }
    func importURL(resource: URL) throws -> URL {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = ""
        let parameter: String
        switch self {
        case .surge: parts.path = "/install-module"; parameter = "url"
        case .loon: parts.host = "import"; parameter = "plugin"
        case .stash: parts.host = "install-override"; parameter = "url"
        case .shadowrocket: parts.host = "install"; parameter = "module"
        case .quantumultX: parts.path = "/add-resource"; parameter = "remote-resource"
        }
        var value = resource.absoluteString
        if self == .quantumultX {
            let data = try JSONSerialization.data(withJSONObject: ["rewrite_remote": [value + ", tag=WLoc Native, enabled=true"]], options: [.sortedKeys])
            value = String(decoding: data, as: UTF8.self)
        }
        parts.queryItems = [URLQueryItem(name: parameter, value: value)]
        // URLComponents leaves '+' literal in query values; encode it for form-style decoders.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw WLocError.installationFailed }
        return url
    }
}
