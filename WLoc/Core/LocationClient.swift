import Foundation

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class LocationClient {
    private let session: URLSession
    private let connection: Connection
    init(connection: Connection, session: URLSession? = nil) {
        self.connection = connection
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        }
    }
    deinit { session.invalidateAndCancel() }

    // No coordinates or key are sent until the local module identifies itself.
    private func probe() async throws {
        let data = try await request("health", authenticated: false)
        try checkIdentity(data)
    }
    func fetch() async throws -> RemoteLocation {
        try await probe()
        let readRoute = connection.version == .localV3 && connection.client == .quantumultX ? "status" : "config"
        let data = try await request(readRoute)
        return try decode(data)
    }
    func apply(_ place: Place) async throws -> RemoteLocation {
        try place.validate()
        try await probe()
        let payload = try JSONEncoder().encode(RemoteLocation(enabled: true, latitude: place.latitude,
                                longitude: place.longitude, horizontalAccuracy: place.horizontalAccuracy.rounded()))
        let data = try await request("config", body: payload)
        let saved = try decode(data)
        guard saved.matches(place) else { throw WLocError.verification }
        return saved
    }
    func disable() async throws -> RemoteLocation {
        try await probe()
        let data = try await request("disable", body: Data("{}".utf8))
        let saved = try decode(data)
        guard !saved.enabled else { throw WLocError.verification }
        return saved
    }
    private func decode(_ data: Data) throws -> RemoteLocation {
        try checkIdentity(data)
        do {
            let location = try JSONDecoder().decode(RemoteLocation.self, from: data)
            try location.validate()
            return location
        } catch { throw WLocError.invalidResponse }
    }
    private func checkIdentity(_ data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["bridge"] as? String == connection.expectedBridge else { throw WLocError.bridgeMissing }
        if connection.version == .localV3, json["client"] as? String != connection.client.rawValue { throw WLocError.wrongClient }
    }
    private func request(_ route: String, body: Data? = nil, authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: connection.url(for: route))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if authenticated { request.setValue(connection.key, forHTTPHeaderField: "X-WLoc-Key") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.boundedData(for: request, maximumBytes: 65536)
        guard let http = response as? HTTPURLResponse else { throw WLocError.bridgeMissing }
        guard !(300...399).contains(http.statusCode) else { throw WLocError.redirect }
        guard (200...299).contains(http.statusCode) else { throw WLocError.http(http.statusCode) }
        guard data.count <= 65536 else { throw WLocError.invalidResponse }
        return data
    }
}
