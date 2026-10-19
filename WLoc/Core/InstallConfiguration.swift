import Foundation

struct InstallConfiguration {
    let connection: Connection
    let revision: String
    init(connection: Connection, revision: String) throws {
        guard revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw WLocError.scriptRevisionMissing }
        guard connection.version == .localV3 else { throw WLocError.installationFailed }
        self.connection = connection
        self.revision = revision
    }
    var fileName: String { "WLoc-\(connection.client.title.replacingOccurrences(of: " ", with: "-"))-\(connection.key.prefix(6)).\(connection.client.fileExtension)" }
    static let hosts = ["gs-loc.apple.com", "gs-loc-cn.apple.com", "gsp-ssl.ls.apple.com", "bluedot.is.autonavi.com", "bluedot.is.autonavi.com.gds.alibabadns.com"]
    static let wlocPattern = #"^https?:\/\/(?:gs-loc(?:-cn)?\.apple\.com|gsp-ssl\.ls\.apple\.com|bluedot\.is\.autonavi\.com(?:\.gds\.alibabadns\.com)?)\/clls\/wloc"#
    var controlPattern: String {
        // This EXACT secret match is the authorization boundary, including on QX.
        let prefix = #"^https:\/\/gs-loc\.apple\.com\/wloc-native\/v3\/"#
        if connection.client == .quantumultX { return prefix + connection.key + #"\/(?:config|disable)$"# }
        return prefix + #"(?:health|"# + connection.key + #"\/(?:config|disable))$"#
    }
    var readControlPattern: String {
        #"^https:\/\/gs-loc\.apple\.com\/wloc-native\/v3\/(?:health|"# + connection.key + #"\/status)$"#
    }
    var controlPatterns: [String] {
        connection.client == .quantumultX ? [readControlPattern, controlPattern] : [controlPattern]
    }
    var content: String {
        let client = connection.client
        let base = "https://raw.githubusercontent.com/JavaWeh/wloc-ios/\(revision)/ProxyClients/v3/"
        let control = base + client.rawValue + "-control.js"
        let response = base + "response.js"
        let prepare = base + "prepare.js"
        let title = "WLoc Native · \(client.title)"
        let description = "本机常用定位；专属配置含配对信息，请勿分享。停用旧定位组件；不包含证书。"
        let hosts = Self.hosts.joined(separator: ", ")
        let pattern = Self.wlocPattern
        switch client {
        case .surge, .shadowrocket:
            return """
            #!name=\(title)
            #!desc=\(description)
            #!homepage=https://github.com/JavaWeh/wloc-ios
            [Script]
            WLoc Native Control = type=http-request,pattern=\(controlPattern),requires-body=1,max-size=16384,timeout=10,script-path=\(control)
            WLoc Native Prepare = type=http-request,pattern=\(pattern),requires-body=0,timeout=3,script-path=\(prepare)
            WLoc Native Response = type=http-response,pattern=\(pattern),requires-body=1,binary-body-mode=1,max-size=0,timeout=30,script-path=\(response)
            [MITM]
            hostname = %APPEND% \(hosts)

            """
        case .loon:
            return """
            #!name=\(title)
            #!desc=\(description)
            [Script]
            http-request \(controlPattern) script-path=\(control),requires-body=true,timeout=10,tag=WLoc Native Control
            http-request \(pattern) script-path=\(prepare),requires-body=false,timeout=3,tag=WLoc Native Prepare
            http-response \(pattern) script-path=\(response),requires-body=true,binary-body-mode=true,timeout=30,tag=WLoc Native Response
            [MITM]
            hostname = \(hosts)

            """
        case .stash:
            return """
            name: '\(title)'
            desc: '\(description)'
            http:
              script:
                - match: '\(controlPattern)'
                  name: wloc-v3-control
                  type: request
                  require-body: true
                  max-size: 16384
                  timeout: 10
                - match: '\(pattern)'
                  name: wloc-v3-prepare
                  type: request
                  timeout: 3
                - match: '\(pattern)'
                  name: wloc-v3-response
                  type: response
                  require-body: true
                  binary-mode: true
                  max-size: 0
                  timeout: 30
              mitm:
            \(Self.hosts.map { "    - " + $0 }.joined(separator: "\n"))
            script-providers:
              wloc-v3-control:
                url: \(control)
                interval: 86400
              wloc-v3-prepare:
                url: \(prepare)
                interval: 86400
              wloc-v3-response:
                url: \(response)
                interval: 86400

            """
        case .quantumultX:
            return """
            #!name=\(title)
            #!desc=\(description)
            [rewrite_local]
            \(readControlPattern) url script-echo-response \(control)
            \(controlPattern) url script-analyze-echo-response \(control)
            \(pattern) url script-request-header \(prepare)
            \(pattern) url script-response-body \(response)
            [mitm]
            hostname = \(hosts)

            """
        }
    }
}
