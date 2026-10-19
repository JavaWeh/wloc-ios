import XCTest
@testable import WLocCore

final class LocationCoreTests: XCTestCase {
    func testPageAndConfigLinkResolveToSameRoutes() throws {
        let page = try Connection(link: "https://example.com/picker/?token=abc")
        let config = try Connection(link: "https://example.com/picker/loc.json?token=abc")
        XCTAssertEqual(page, config)
        XCTAssertEqual(try page.url(for: "set").path, "/picker/set")
        XCTAssertEqual(try page.url(for: "enable").path, "/picker/enable")
        XCTAssertEqual(try page.url(for: "loc.json").path, "/picker/loc.json")
    }

    func testTokenAndGatewayQuerySurviveEncoding() throws {
        let connection = try Connection(link: "https://example.com/?token=a%2Bb%20%26%3F&gateway=one")
        let url = try connection.url(for: "set")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "token" })?.value, "a+b &?")
        XCTAssertEqual(items.first(where: { $0.name == "gateway" })?.value, "one")
        XCTAssertFalse(connection.displayAddress.contains("token"))
    }

    func testRejectsUnsafeOrAmbiguousConnections() {
        for link in ["http://example.com/?token=a", "https://example.com/", "https://example.com/?token=",
                     "https://example.com/?token=a&token=b", "https://user:pass@example.com/?token=a",
                     "https://example.com/?token=a#fragment"] {
            XCTAssertThrowsError(try Connection(link: link), link)
        }
    }

    func testCoordinateValidationIncludesZeroAndNegativeButRejectsNonFinite() throws {
        try Place(name: "Zero", latitude: 0, longitude: 0).validate()
        try Place(name: "South", latitude: -90, longitude: -180).validate()
        for latitude in [Double.nan, Double.infinity, -90.1, 90.1] {
            XCTAssertThrowsError(try Place(name: "Bad", latitude: latitude, longitude: 0).validate())
        }
        XCTAssertThrowsError(try Place(name: "Bad", latitude: 0, longitude: 181).validate())
        XCTAssertThrowsError(try Place(name: " ", latitude: 0, longitude: 0).validate())
        XCTAssertThrowsError(try Place(name: "Bad", latitude: 0, longitude: 0, horizontalAccuracy: 0).validate())
    }

    func testApplyUsesUpstreamPayloadAndValidatesReturnedCoordinate() async throws {
        let place = Place(name: "Test", latitude: -33.86, longitude: 151.2)
        let client = try makeClient { request in
            XCTAssertEqual(request.url?.path, "/set")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let payload = try self.body(request)
            XCTAssertEqual(payload["lat"] as? Double, -33.86)
            XCTAssertEqual(payload["lng"] as? Double, 151.2)
            XCTAssertNil(payload["latitude"])
            XCTAssertNil(payload["altitude"], "Existing altitude must be preserved")
            return (200, #"{"enabled":true,"latitude":-33.86,"longitude":151.2,"altitude":530}"#)
        }
        let saved = try await client.apply(place)
        XCTAssertTrue(saved.matches(place))
    }

    func testDisableUsesFalseAndAcceptsFullConfig() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.url?.path, "/enable")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(try self.body(request)["enabled"] as? Bool, false)
            return (200, #"{"enabled":false,"latitude":1,"longitude":2}"#)
        }
        let disabled = try await client.disable()
        XCTAssertFalse(disabled.enabled)
    }

    func testReadBypassesCacheAndCarriesToken() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/loc.json")
            XCTAssertEqual(request.url?.query, "token=test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache, no-store")
            return (200, #"{"enabled":true,"latitude":0,"longitude":0}"#)
        }
        let remote = try await client.fetch()
        XCTAssertEqual(remote.latitude, 0)
    }

    func testRejectsHTTPErrorHTMLAndInvalidRemoteData() async throws {
        for (status, json) in [(403, "{}"), (302, ""), (200, "<html>Login</html>"),
                               (200, #"{"latitude":1,"longitude":2}"#),
                               (200, #"{"enabled":true,"latitude":99,"longitude":2}"#)] {
            let client = try makeClient { _ in (status, json) }
            do { _ = try await client.fetch(); XCTFail("Should reject \(status): \(json)") }
            catch { XCTAssertTrue(error is WLocError) }
        }
    }

    func testRejectsSaveResponseThatDoesNotConfirmRequestedLocation() async throws {
        let client = try makeClient { _ in (200, #"{"enabled":true,"latitude":1,"longitude":2}"#) }
        do {
            _ = try await client.apply(Place(name: "Other", latitude: 3, longitude: 4))
            XCTFail("Mismatched coordinates must not be reported as saved")
        } catch WLocError.verification { }
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                collected.append(contentsOf: buffer.prefix(count))
            }
            data = collected
        } else { throw WLocError.invalidResponse }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeClient(_ handler: @escaping (URLRequest) throws -> (Int, String)) throws -> LocationClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return LocationClient(connection: try Connection(link: "https://example.com/?token=test"),
                              session: URLSession(configuration: config))
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
