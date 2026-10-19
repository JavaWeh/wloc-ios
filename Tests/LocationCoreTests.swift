import XCTest
@testable import WLocCore

final class LocationCoreTests: XCTestCase {
    private let key = "0123456789abcdef0123456789abcdef"
    private let config = #"{"bridge":"wloc-native-v2","enabled":true,"latitude":-33.86,"longitude":151.2,"horizontalAccuracy":39}"#

    func testPairingUsesFixedLocalEndpointAndRejectsInvalidKeys() throws {
        let connection = try Connection(key: key)
        XCTAssertEqual(connection.url(for: "config").absoluteString, "https://gs-loc.apple.com/wloc-native/v1/config")
        for key in ["", "short", "0123456789abcdef&key=wrong", "密钥密钥密钥密钥密钥密钥密钥密钥"] {
            XCTAssertThrowsError(try Connection(key: key))
        }
    }
    func testValidZeroNegativeCoordinatesAndInvalidBounds() throws {
        try Place(name: "Origin", latitude: 0, longitude: 0).validate()
        try Place(name: "Edge", latitude: -90, longitude: -180).validate()
        for latitude in [Double.nan, .infinity, 90.1, -90.1] {
            XCTAssertThrowsError(try Place(name: "Bad", latitude: latitude, longitude: 0).validate())
        }
        XCTAssertThrowsError(try Place(name: "Bad", latitude: 0, longitude: 181).validate())
        XCTAssertThrowsError(try Place(name: "", latitude: 0, longitude: 0).validate())
        XCTAssertThrowsError(try Place(name: "Bad", latitude: 0, longitude: 0, horizontalAccuracy: 0.1).validate())
    }
    func testProbeSendsNoCredentialsAndConfigReadUsesHeader() async throws {
        var calls = 0
        let client = try client { request in
            calls += 1
            if request.url!.path.hasSuffix("/health") {
                XCTAssertNil(request.value(forHTTPHeaderField: "X-WLoc-Key"))
                XCTAssertNil(request.httpBody)
                return (200, #"{"bridge":"wloc-native-v2"}"#)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-WLoc-Key"), self.key)
            XCTAssertNil(request.url?.query)
            return (200, self.config)
        }
        let saved = try await client.fetch()
        XCTAssertEqual(saved.longitude, 151.2)
        XCTAssertEqual(calls, 2)
    }
    func testMissingBridgePreventsCoordinateOrKeyTransmission() async throws {
        var calls = 0
        let client = try client { request in
            calls += 1
            XCTAssertTrue(request.url!.path.hasSuffix("/health"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-WLoc-Key"))
            return (200, "<html>Not the local bridge</html>")
        }
        do {
            _ = try await client.apply(Place(name: "Test", latitude: -33.86, longitude: 151.2))
            XCTFail("Must reject a missing bridge")
        } catch WLocError.bridgeMissing { }
        XCTAssertEqual(calls, 1)
    }
    func testApplyPersistsFullLocalTargetAndVerifiesIt() async throws {
        let client = try client { request in
            if request.url!.path.hasSuffix("/health") { return (200, #"{"bridge":"wloc-native-v2"}"#) }
            XCTAssertEqual(request.httpMethod, "POST")
            let payload = try self.body(request)
            XCTAssertEqual(payload["latitude"] as? Double, -33.86)
            XCTAssertEqual(payload["longitude"] as? Double, 151.2)
            XCTAssertEqual(payload["enabled"] as? Bool, true)
            return (200, self.config)
        }
        let saved = try await client.apply(Place(name: "Test", latitude: -33.86, longitude: 151.2))
        XCTAssertTrue(saved.enabled)
    }
    func testDisableUsesDistinctEndpoint() async throws {
        let client = try client { request in
            if request.url!.path.hasSuffix("/health") { return (200, #"{"bridge":"wloc-native-v2"}"#) }
            XCTAssertTrue(request.url!.path.hasSuffix("/disable"))
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, #"{"bridge":"wloc-native-v2","enabled":false,"latitude":0,"longitude":0}"#)
        }
        let saved = try await client.disable()
        XCTAssertFalse(saved.enabled)
    }
    func testWrongPairingKeyAndInvalidServerResponseAreRejected() async throws {
        for (status, payload) in [(403, "{}"), (200, "{}"), (200, #"{"bridge":"wloc-native-v2","enabled":true,"latitude":91,"longitude":2}"#)] {
            let client = try client { request in
                request.url!.path.hasSuffix("/health") ? (200, #"{"bridge":"wloc-native-v2"}"#) : (status, payload)
            }
            do { _ = try await client.fetch(); XCTFail("Must reject invalid response") }
            catch { XCTAssertTrue(error is WLocError) }
        }
    }
    func testSaveMismatchIsNotReportedAsSuccess() async throws {
        let client = try client { request in
            request.url!.path.hasSuffix("/health") ? (200, #"{"bridge":"wloc-native-v2"}"#) : (200, self.config)
        }
        do {
            _ = try await client.apply(Place(name: "Other", latitude: 1, longitude: 2))
            XCTFail("Must verify saved coordinate")
        } catch WLocError.verification { }
    }

    func testAppleModernAndLegacyMapLinks() throws {
        let modern = try XCTUnwrap(MapLinkParser.parse("https://maps.apple.com/place?coordinate=37.3349,-122.00902&name=Apple%20Park"))
        XCTAssertEqual(modern.coordinate.latitude, 37.3349)
        XCTAssertEqual(modern.name, "Apple Park")
        XCTAssertEqual(modern.system, .wgs84)
        let legacy = try XCTUnwrap(MapLinkParser.parse("http://maps.apple.com/?ll=39.9,116.4&q=Test"))
        XCTAssertEqual(legacy.name, "Test")
        XCTAssertEqual(legacy.system, .gcj02)
        XCTAssertNotNil(legacy.warning)
    }
    func testAMapCoordinateOrderAndExplicitWGS() throws {
        let uri = try XCTUnwrap(MapLinkParser.parse("https://uri.amap.com/marker?position=116.4,39.9&name=Office"))
        XCTAssertEqual(uri.coordinate, Coordinate(latitude: 39.9, longitude: 116.4))
        XCTAssertEqual(uri.system, .gcj02)
        let wgs = try XCTUnwrap(MapLinkParser.parse("http://uri.amap.com/marker?position=116.4,39.9&coordinate=wgs84"))
        XCTAssertEqual(wgs.system, .wgs84)
        let share = try XCTUnwrap(MapLinkParser.parse("https://m.amap.com/?p=B012,39.9,116.4,Company"))
        XCTAssertEqual(share.coordinate, uri.coordinate)
        XCTAssertEqual(share.name, "Company")
        let newer = try XCTUnwrap(MapLinkParser.parse("https://m.amap.com/?q=39.9,116.4,Company"))
        XCTAssertEqual(newer.coordinate, uri.coordinate)
    }
    func testGooglePinWinsOverCameraAndQueryCoordinatesWork() throws {
        let link = "https://www.google.com/maps/place/Office/@1.1,2.2,16z/data=!3m1!3d37.3349!4d-122.00902"
        let hit = try XCTUnwrap(MapLinkParser.parse(link))
        XCTAssertEqual(hit.coordinate.latitude, 37.3349)
        XCTAssertEqual(hit.coordinate.longitude, -122.00902)
        XCTAssertEqual(hit.name, "Office")
        let query = try XCTUnwrap(MapLinkParser.parse("https://www.google.com/maps/search/?api=1&query=37.3349%2C-122.00902"))
        XCTAssertEqual(query.coordinate, hit.coordinate)
    }
    func testGoogleCameraIsExplicitlyMarkedAndRoutesAreRejected() throws {
        let hit = try XCTUnwrap(MapLinkParser.parse("https://www.google.com/maps/@37.3,-122.0,15z"))
        XCTAssertTrue(hit.source.contains("地图中心"))
        XCTAssertNotNil(hit.warning)
        XCTAssertThrowsError(try MapLinkParser.parse("https://www.google.com/maps/dir/data=!3d1!4d2!3d3!4d4"))
    }
    func testParserRejectsWrongHostAndGarbageButAllowsZeroAndNegatives() throws {
        XCTAssertThrowsError(try MapLinkParser.parse("https://maps.apple.com.evil.test/?ll=1,2"))
        XCTAssertThrowsError(try MapLinkParser.parse("https://maps.apple.com/?ll=91,116"))
        XCTAssertNil(try MapLinkParser.parse("https://maps.apple.com/?scroll=1.5,2.5"))
        XCTAssertNil(try MapLinkParser.parse("height 12.12345, animation 13.12345"))
        let zero = try XCTUnwrap(MapLinkParser.parse("0,0"))
        XCTAssertEqual(zero.coordinate, Coordinate(latitude: 0, longitude: 0))
        let negative = try XCTUnwrap(MapLinkParser.parse("-33.86,151.2"))
        XCTAssertEqual(negative.coordinate.latitude, -33.86)
    }
    func testCoordinateConversionMatchesReferenceAndRoundTrips() {
        let wgs = Coordinate(latitude: 39.9, longitude: 116.4)
        let gcj = Coordinates.wgsToGCJ(wgs)
        XCTAssertEqual(gcj.latitude, 39.9014035298494, accuracy: 1e-9)
        XCTAssertEqual(gcj.longitude, 116.406242784911, accuracy: 1e-9)
        let reverted = CoordinateSystem.gcj02.toWGS(gcj)
        XCTAssertEqual(reverted.latitude, wgs.latitude, accuracy: 1e-8)
        XCTAssertEqual(reverted.longitude, wgs.longitude, accuracy: 1e-8)
        let abroad = Coordinate(latitude: -33.86, longitude: 151.2)
        XCTAssertEqual(Coordinates.gcjToWGS(abroad), abroad)
    }
    func testNetworkAllowlistBlocksPrivateTargetsAndCredentialURLs() {
        for string in ["http://maps.apple.com/a", "https://127.0.0.1/a", "https://localhost/a",
                       "https://maps.apple.com.evil.test/a", "https://user:pass@maps.apple.com/a",
                       "https://maps.apple.com:8443/a", "https://www.google.com/account"] {
            XCTAssertFalse(MapLinkParser.networkAllowed(URL(string: string)!))
        }
        XCTAssertTrue(MapLinkParser.networkAllowed(URL(string: "https://maps.app.goo.gl/abc")!))
    }
    func testShortLinkExpansionNeverParsesRandomBodyNumbers() async throws {
        StubProtocol.handler = { request in
            (200, "<html>animation=[12.12345,13.12345]</html>")
        }
        let resolver = MapLinkResolver(session: stubSession())
        do { _ = try await resolver.resolve("https://maps.app.goo.gl/abc"); XCTFail("No coordinate should be guessed") }
        catch WLocError.parseFailed { }
    }
    func testShortLinkCanResolveCanonicalMapURL() async throws {
        StubProtocol.handler = { _ in
            (200, #"<html><link rel="canonical" href="https://maps.apple.com/place?coordinate=37.3349,-122.00902&amp;name=Park"></html>"#)
        }
        let hit = try await MapLinkResolver(session: stubSession()).resolve("https://maps.apple/abc")
        XCTAssertEqual(hit.name, "Park")
        XCTAssertEqual(hit.coordinate.latitude, 37.3349)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data(), buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                collected.append(contentsOf: buffer.prefix(count))
            }
            data = collected
        } else { throw WLocError.invalidResponse }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, String)) throws -> LocationClient {
        StubProtocol.handler = handler
        return LocationClient(connection: try Connection(key: key), session: stubSession())
    }
}

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, text) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
