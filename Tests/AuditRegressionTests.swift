import XCTest
@testable import WLocCore

final class AuditRegressionTests: XCTestCase {
    func testGoogleSearchTextCannotInjectCameraOrPinCoordinates() throws {
        XCTAssertNil(try MapLinkParser.parse("https://www.google.com/maps/search/?q=Office%40-33.86,151.2"))
        XCTAssertNil(try MapLinkParser.parse("https://www.google.com/maps/search/?q=Office!3d1!4d2"))
        XCTAssertNil(try MapLinkParser.parse("https://www.google.com/maps/#@1,2"))
        let pin = try XCTUnwrap(MapLinkParser.parse("https://www.google.com/maps/place/Office/data=!3d-33.86!4d151.2?q=Office%40-1,2"))
        XCTAssertEqual(pin.coordinate, Coordinate(latitude: -33.86, longitude: 151.2))
    }
    func testGooglePlaceIDCannotBeReplacedWithFallbackCoordinate() {
        XCTAssertThrowsError(try MapLinkParser.parse("https://www.google.com/maps/search/?api=1&query=1,2&query_place_id=ChIJDifferentPlace"))
        XCTAssertThrowsError(try MapLinkParser.parse("https://www.google.com/maps/dir/?api=1&destination=1,2&destination_place_id=ChIJDifferentPlace"))
    }
    func testEditingOrFailingNewInputClearsPreviousCoordinateAndName() {
        var draft = MapImportDraft()
        draft.select(location(name: "Old place"))
        XCTAssertNotNil(draft.normalized)
        let oldToken = draft.revision
        draft.reset()
        XCTAssertNil(draft.normalized)
        XCTAssertEqual(draft.name, "")
        XCTAssertFalse(draft.accept(location(name: "Late old result"), for: oldToken))
        XCTAssertNil(draft.normalized)
        XCTAssertTrue(draft.accept(location(name: ""), for: draft.revision))
        XCTAssertEqual(draft.name, "", "Coordinate-only input must not inherit a previous place's name")
    }
    func testManualMapSelectionSupersedesPendingLinkResult() {
        var draft = MapImportDraft()
        let pending = draft.reset()
        var selected = location(name: "Map selection")
        selected.coordinate.latitude = 2
        draft.select(selected)
        XCTAssertFalse(draft.accept(location(name: "Old link"), for: pending))
        XCTAssertEqual(draft.normalized?.latitude, 2)
        XCTAssertEqual(draft.name, "Map selection")
    }
    func testUnrepresentableAccuracyIsRejected() {
        XCTAssertThrowsError(try Place(name: "Bad", latitude: 1, longitude: 2, horizontalAccuracy: 1e300).validate())
        XCTAssertThrowsError(try Place(name: "Bad", latitude: 1, longitude: 2, horizontalAccuracy: 1_000_001).validate())
    }
    func testCorruptFavoritesAreBackedUpBeforeAnyReplacement() throws {
        try withDirectory { directory in
            let file = directory.appendingPathComponent("places.json")
            let damaged = Data("{truncated-json".utf8)
            try damaged.write(to: file)
            let store = FavoritesStore(file: file)
            XCTAssertTrue(try store.load().isEmpty)
            let backup = try XCTUnwrap(store.recoveryFile)
            XCTAssertEqual(try Data(contentsOf: backup), damaged)
            XCTAssertEqual(try Data(contentsOf: file), damaged)
            let place = Place(name: "New", latitude: 0, longitude: 0)
            try store.save([place])
            XCTAssertEqual(try JSONDecoder().decode([Place].self, from: Data(contentsOf: file)), [place])
            XCTAssertEqual(try Data(contentsOf: backup), damaged)
        }
    }
    func testUnreadableFavoritesCannotBeOverwritten() throws {
        try withDirectory { directory in
            let file = directory.appendingPathComponent("places.json")
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            let store = FavoritesStore(file: file)
            XCTAssertThrowsError(try store.load())
            XCTAssertFalse(store.canWrite)
            XCTAssertThrowsError(try store.save([Place(name: "New", latitude: 1, longitude: 2)]))
            XCTAssertEqual(try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, true)
        }
    }
    func testDuplicateFavoriteIdentifiersDoNotReachDisk() throws {
        try withDirectory { directory in
            let file = directory.appendingPathComponent("places.json")
            let store = FavoritesStore(file: file)
            _ = try store.load()
            let place = Place(name: "Same ID", latitude: 1, longitude: 2)
            XCTAssertThrowsError(try store.save([place, place]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }
    func testOversizedDeclaredResponseIsRejectedEvenWithSmallBody() async throws {
        // Foundation buffers a small declared-length body before yielding AsyncBytes.
        // Finish this fixture to isolate header validation from streaming cancellation.
        try await checkBoundedResponse(headers: ["Content-Length": "1048576"], data: Data([65]), finish: true)
    }
    func testOversizedChunkedResponseCancelsBeforeTransferCompletes() async throws {
        try await checkBoundedResponse(headers: [:], data: Data(repeating: 65, count: 1025))
    }

    private func checkBoundedResponse(headers: [String: String], data: Data, finish: Bool = false) async throws {
        let stopped = finish ? nil : expectation(description: "Oversized transfer cancelled")
        AuditProtocol.spec = (headers, data, finish)
        AuditProtocol.onStop = { stopped?.fulfill() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuditProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let read = Task { try await session.boundedData(for: URLRequest(url: URL(string: "https://maps.apple.com/oversized")!), maximumBytes: 1024) }
        let timeout = Task { try await Task.sleep(nanoseconds: 3_000_000_000); read.cancel() }
        defer { timeout.cancel() }
        do { _ = try await read.value; XCTFail("Oversized response must fail") }
        catch WLocError.responseTooLarge { }
        catch { XCTFail("Expected responseTooLarge, got \(error)") }
        if let stopped { await fulfillment(of: [stopped], timeout: 2) }
    }
    private func location(name: String) -> ParsedLocation {
        ParsedLocation(coordinate: Coordinate(latitude: 1, longitude: 2), name: name, system: .wgs84, source: "Test", warning: nil)
    }
    private func withDirectory(_ operation: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WLocAudit-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }
}

private final class AuditProtocol: URLProtocol {
    static var spec: (headers: [String: String], data: Data, finish: Bool) = ([:], Data(), false)
    static var onStop: (() -> Void)?
    private var stop: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        stop = Self.onStop
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: Self.spec.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !Self.spec.data.isEmpty { client?.urlProtocol(self, didLoad: Self.spec.data) }
        if Self.spec.finish { client?.urlProtocolDidFinishLoading(self) }
        // Streaming fixture never finishes: the reader must cancel before the sender does.
    }
    override func stopLoading() { stop?(); stop = nil }
}
