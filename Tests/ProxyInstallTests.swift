import XCTest
@testable import WLocCore

final class ProxyInstallTests: XCTestCase {
    private let key = "0123456789abcdef0123456789abcdef"
    private let revision = String(repeating: "a", count: 40)

    func testLegacyConnectionDecodesWithoutReinstallation() throws {
        let old = try JSONDecoder().decode(Connection.self, from: Data(#"{"key":"0123456789abcdef0123456789abcdef"}"#.utf8))
        XCTAssertEqual(old.client, .surge)
        XCTAssertEqual(old.version, .legacyV1)
        XCTAssertEqual(old.expectedBridge, "wloc-native-v2")
        XCTAssertEqual(old.url(for: "config").path, "/wloc-native/v1/config")
        XCTAssertThrowsError(try JSONDecoder().decode(Connection.self, from: Data(#"{"key":"short"}"#.utf8)))
    }
    func testProfilesKeepIndependentCredentialsAndPendingUpgrade() throws {
        var profiles = PairingProfiles()
        let old = try Connection(key: key)
        profiles.set(old, verified: true)
        let upgraded = try Connection(key: String(repeating: "b", count: 64), client: .surge, version: .localV3)
        profiles.pending["surge"] = upgraded
        XCTAssertEqual(profiles.current, old, "Preparing an installation must not discard a working legacy pairing")
        let loon = try Connection(key: String(repeating: "c", count: 64), client: .loon, version: .localV3)
        profiles.set(loon, verified: true)
        profiles.selected = .loon
        XCTAssertEqual(profiles.current, loon)
        profiles.set(upgraded, verified: true)
        XCTAssertNil(profiles.pending["surge"])
        XCTAssertEqual(profiles.connections["loon"], loon)
        XCTAssertEqual(try JSONDecoder().decode(PairingProfiles.self, from: JSONEncoder().encode(profiles)), profiles)
    }
    func testGeneratedCredentialsAreIndependentAndValid() throws {
        let secrets = try ProxyClient.allCases.map { _ in try InstallSecret.make() }
        XCTAssertEqual(Set(secrets).count, 5)
        for secret in secrets { XCTAssertEqual(secret.count, 64); _ = try Connection(key: secret) }
    }
    func testAllConfigurationFormatsHaveExactCredentialGateAndPinnedSources() throws {
        var fixtures: [[String: Any]] = []
        for client in ProxyClient.allCases {
            let connection = try Connection(key: key, client: client, version: .localV3)
            let configuration = try InstallConfiguration(connection: connection, revision: revision)
            let text = configuration.content
            XCTAssertTrue(configuration.fileName.hasSuffix("." + client.fileExtension))
            XCTAssertTrue(text.contains(configuration.controlPattern))
            let regexes = try configuration.controlPatterns.map { try NSRegularExpression(pattern: $0) }
            func matches(_ url: URL) -> Bool { regexes.contains { $0.firstMatch(in: url.absoluteString, range: NSRange(location: 0, length: (url.absoluteString as NSString).length)) != nil } }
            XCTAssertTrue(matches(connection.url(for: "health")))
            XCTAssertTrue(matches(connection.url(for: "config")))
            XCTAssertTrue(matches(connection.url(for: "disable")))
            XCTAssertFalse(matches(try Connection(key: String(repeating: "b", count: 32), client: client, version: .localV3).url(for: "config")))
            XCTAssertFalse(matches(URL(string: connection.url(for: "config").absoluteString + "?extra=1")!))
            XCTAssertFalse(matches(URL(string: "https://gs-loc.apple.com.evil.test/wloc-native/v3/health")!))
            XCTAssertTrue(text.contains("/\(revision)/ProxyClients/v3/\(client.rawValue)-control.js"))
            XCTAssertTrue(text.contains("/\(revision)/ProxyClients/v3/response.js"))
            for host in InstallConfiguration.hosts { XCTAssertTrue(text.contains(host)) }
            for forbidden in ["127.0.0.1", "localhost", "configUrl", "[Proxy]", "[Proxy Group]", "ca-p12", "#!arguments", "$argument"] {
                XCTAssertFalse(text.contains(forbidden), "Unexpected configuration field: \(forbidden)")
            }
            let runtimeURLs = MapLinkParser.captures(#"https://raw\.githubusercontent\.com/[^\s,]+"#, in: text)
            XCTAssertEqual(runtimeURLs.count, client == .quantumultX ? 4 : 3)
            if client == .quantumultX {
                XCTAssertTrue(matches(connection.url(for: "status")))
                XCTAssertTrue(text.contains(configuration.readControlPattern + " url script-echo-response"))
                XCTAssertTrue(text.contains(configuration.controlPattern + " url script-analyze-echo-response"))
            }
            fixtures.append(["client": client.rawValue, "patterns": configuration.controlPatterns, "content": text, "fileName": configuration.fileName])
        }
        if let folder = ProcessInfo.processInfo.environment["WLOC_EXPORT_FIXTURES"] {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: fixtures, options: [.sortedKeys]).write(to: directory.appendingPathComponent("configurations.json"))
        }
    }
    func testConfigurationsRejectUnpinnedRevisionAndLegacyConnection() throws {
        let modern = try Connection(key: key, version: .localV3)
        for value in ["main", "", "../main", String(repeating: "a", count: 39), String(repeating: "z", count: 40)] {
            XCTAssertThrowsError(try InstallConfiguration(connection: modern, revision: value))
        }
        XCTAssertThrowsError(try InstallConfiguration(connection: Connection(key: key), revision: revision))
    }
    func testImportLinksRoundTripSpecialCharactersAndOnlyAppendResources() throws {
        let resource = URL(string: "http://127.0.0.1:12345/token/file.snippet?one=1&two=a%2Bb#part")!
        for client in ProxyClient.allCases {
            let url = try client.importURL(resource: resource)
            XCTAssertEqual(url.scheme, client.scheme)
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let item = try XCTUnwrap(parts.queryItems?.first)
            if client == .quantumultX {
                XCTAssertEqual(parts.path, "/add-resource")
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(item.value!.utf8)) as? [String: [String]])
                XCTAssertEqual(json.keys.sorted(), ["rewrite_remote"])
                XCTAssertEqual(json["rewrite_remote"]?.first, resource.absoluteString + ", tag=WLoc Native, enabled=true")
            } else { XCTAssertEqual(item.value, resource.absoluteString) }
        }
    }
    func testDownloadSessionRejectsWrongTokenTraversalAndUnexpectedMethods() {
        var session = InstallDownloadSession(token: "token", fileName: "file.sgmodule", content: Data("PRIVATE".utf8), expiresAt: .distantFuture)
        for request in ["GET /wrong/file.sgmodule HTTP/1.1", "GET /token/../file.sgmodule HTTP/1.1", "GET /token/file.sgmodule?x=1 HTTP/1.1", "GET /token/%66ile.sgmodule HTTP/1.1"] {
            let result = String(decoding: session.response(to: request + "\r\n\r\n"), as: UTF8.self)
            XCTAssertTrue(result.hasPrefix("HTTP/1.1 404")); XCTAssertFalse(result.contains("PRIVATE"))
        }
        XCTAssertTrue(String(decoding: session.response(to: "POST /token/file.sgmodule HTTP/1.1\r\n\r\n"), as: UTF8.self).hasPrefix("HTTP/1.1 405"))
        XCTAssertTrue(String(decoding: session.response(to: "malformed"), as: UTF8.self).hasPrefix("HTTP/1.1 400"))
    }
    func testDownloadSessionAllowsHeadAndRetriesButExpiresAndStops() {
        let now = Date()
        var session = InstallDownloadSession(token: "token", fileName: "file.sgmodule", content: Data("PRIVATE".utf8), expiresAt: now.addingTimeInterval(10))
        let head = String(decoding: session.response(to: "HEAD /token/file.sgmodule HTTP/1.1", now: now), as: UTF8.self)
        XCTAssertTrue(head.contains("Content-Length: 7")); XCTAssertFalse(head.contains("PRIVATE"))
        for _ in 0..<16 { XCTAssertTrue(String(decoding: session.response(to: "GET /token/file.sgmodule HTTP/1.1", now: now), as: UTF8.self).hasSuffix("PRIVATE")) }
        XCTAssertTrue(String(decoding: session.response(to: "GET /token/file.sgmodule HTTP/1.1", now: now), as: UTF8.self).contains("429 Too Many Requests"))
        XCTAssertTrue(String(decoding: session.response(to: "GET /token/file.sgmodule HTTP/1.1", now: now.addingTimeInterval(11)), as: UTF8.self).contains("410 Gone"))
        session.stop()
        XCTAssertTrue(String(decoding: session.response(to: "GET /token/file.sgmodule HTTP/1.1", now: now), as: UTF8.self).contains("410 Gone"))
    }
    func testLoopbackServerDownloadsAndStopsOnBackgroundExpirationPath() async throws {
        let server = InstallHTTPServer()
        let url = try await server.start(content: Data("CONFIG".utf8), fileName: "file.sgmodule")
        let session = localSession()
        do {
            XCTAssertEqual(url.host, "127.0.0.1"); XCTAssertNotNil(url.port)
            let (data, response) = try await session.data(from: url)
            XCTAssertEqual(data, Data("CONFIG".utf8)); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let (_, missing) = try await session.data(from: url.deletingLastPathComponent().appendingPathComponent("missing"))
            XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
            await server.stop() // The same operation used by UIKit's expiration handler.
            do { _ = try await session.data(from: url); XCTFail("Stopped listener must refuse requests") } catch { }
        } catch { await server.stop(); session.invalidateAndCancel(); throw error }
        session.invalidateAndCancel()
    }
    func testLoopbackServerTimerExpiresAndRejectsInvalidFileName() async throws {
        let server = InstallHTTPServer()
        do { _ = try await server.start(content: Data(), fileName: "../bad"); XCTFail("Traversal file name must fail") } catch { }
        let url = try await server.start(content: Data("CONFIG".utf8), fileName: "file.sgmodule", lifetime: 0.1)
        try await Task.sleep(nanoseconds: 350_000_000)
        let session = localSession()
        do { _ = try await session.data(from: url); XCTFail("Expired listener must refuse requests") } catch { }
        await server.stop(); session.invalidateAndCancel()
    }
    func testModernProbeSendsNoCredentialAndVerifiesClientBeforeConfig() async throws {
        var calls = 0
        ModernInstallProtocol.handler = { request in
            calls += 1
            if request.url!.lastPathComponent == "health" {
                XCTAssertNil(request.value(forHTTPHeaderField: "X-WLoc-Key"))
                XCTAssertFalse(request.url!.absoluteString.contains(self.key))
                return #"{"bridge":"wloc-native-v3","client":"loon"}"#
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-WLoc-Key"), self.key)
            XCTAssertEqual(request.url!.path, "/wloc-native/v3/\(self.key)/config")
            return #"{"bridge":"wloc-native-v3","client":"loon","enabled":false,"latitude":0,"longitude":0}"#
        }
        let client = LocationClient(connection: try Connection(key: key, client: .loon, version: .localV3), session: stubSession())
        let result = try await client.fetch()
        XCTAssertFalse(result.enabled)
        XCTAssertEqual(calls, 2)
    }
    func testWrongClientAndMissingBridgeNeverReceiveCredentials() async throws {
        for payload in [#"{"bridge":"wloc-native-v3","client":"stash"}"#, #"{"bridge":"other"}"#] {
            var calls = 0
            ModernInstallProtocol.handler = { request in calls += 1; XCTAssertNil(request.value(forHTTPHeaderField: "X-WLoc-Key")); return payload }
            let client = LocationClient(connection: try Connection(key: key, client: .loon, version: .localV3), session: stubSession())
            do { _ = try await client.fetch(); XCTFail("Must reject wrong identity") }
            catch WLocError.wrongClient { } catch WLocError.bridgeMissing { }
            XCTAssertEqual(calls, 1)
        }
    }
    func testQuantumultXUsesSeparateHeaderOnlyReadRoute() async throws {
        var routes: [String] = []
        ModernInstallProtocol.handler = { request in
            routes.append(request.url!.lastPathComponent)
            XCTAssertNil(request.httpBody)
            if request.url!.lastPathComponent == "health" { return #"{"bridge":"wloc-native-v3","client":"quantumultX"}"# }
            XCTAssertEqual(request.url!.lastPathComponent, "status")
            return #"{"bridge":"wloc-native-v3","client":"quantumultX","enabled":false,"latitude":0,"longitude":0}"#
        }
        let client = LocationClient(connection: try Connection(key: key, client: .quantumultX, version: .localV3), session: stubSession())
        _ = try await client.fetch()
        XCTAssertEqual(routes, ["health", "status"])
    }
    private func localSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2; config.timeoutIntervalForResource = 3
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }
    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ModernInstallProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class ModernInstallProtocol: URLProtocol {
    static var handler: ((URLRequest) -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.handler!(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
