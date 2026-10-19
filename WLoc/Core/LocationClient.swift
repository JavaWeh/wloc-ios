import Foundation

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
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
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        }
    }

    deinit { session.invalidateAndCancel() }

    func fetch() async throws -> RemoteLocation { try await request("loc.json") }

    func apply(_ place: Place) async throws -> RemoteLocation {
        try place.validate()
        // Upstream expects lat/lng (not latitude/longitude). Saving also sets enabled=true.
        let body = try JSONEncoder().encode(SetPayload(lat: place.latitude, lng: place.longitude,
                                                       horizontalAccuracy: place.horizontalAccuracy.rounded()))
        let location = try await request("set", body: body)
        guard location.matches(place) else { throw WLocError.verification }
        return location
    }

    func disable() async throws -> RemoteLocation {
        let location = try await request("enable", body: Data(#"{"enabled":false}"#.utf8))
        guard !location.enabled else { throw WLocError.verification }
        return location
    }

    private struct SetPayload: Encodable {
        let lat: Double
        let lng: Double
        let horizontalAccuracy: Double
    }

    private func request(_ route: String, body: Data? = nil) async throws -> RemoteLocation {
        var request = URLRequest(url: try connection.url(for: route))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw WLocError.invalidResponse }
        if (300...399).contains(response.statusCode) { throw WLocError.redirect }
        guard (200...299).contains(response.statusCode) else { throw WLocError.http(response.statusCode) }
        let location: RemoteLocation
        do {
            location = try JSONDecoder().decode(RemoteLocation.self, from: data)
            try location.validate()
        } catch { throw WLocError.invalidResponse }
        return location
    }
}
