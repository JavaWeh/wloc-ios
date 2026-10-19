import Foundation
import Network
import Security

enum InstallSecret {
    static func make() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw WLocError.installationFailed }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct InstallDownloadSession {
    let token: String
    let fileName: String
    let content: Data
    let expiresAt: Date
    private(set) var active = true
    private(set) var downloads = 0
    var path: String { "/\(token)/\(fileName)" }
    mutating func stop() { active = false }
    mutating func response(to header: String, now: Date = Date()) -> Data {
        let first = header.components(separatedBy: "\r\n").first ?? ""
        let fields = first.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var status = "404 Not Found", payload = Data(), headOnly = false
        if !active || now >= expiresAt { status = "410 Gone" }
        else if fields.count != 3 || !["HTTP/1.1", "HTTP/1.0"].contains(fields[2]) { status = "400 Bad Request" }
        else if fields[1] == path {
            if fields[0] == "GET" || fields[0] == "HEAD" {
                if downloads < 16 {
                    status = "200 OK"; payload = content; headOnly = fields[0] == "HEAD"
                    if !headOnly { downloads += 1 }
                } else { status = "429 Too Many Requests" }
            } else { status = "405 Method Not Allowed" }
        }
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n"
        return Data(headers.utf8) + (headOnly ? Data() : payload)
    }
}

/// An expiring, loopback-only file transfer. Never used to serve coordinates or scripts.
// Every mutable field and Network callback is confined to `queue`; callers only
// cross that boundary through start/stop. This is a queue-backed Sendable type.
final class InstallHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "WLoc.install-download")
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var session: InstallDownloadSession?
    private var pending: CheckedContinuation<URL, Error>?
    private var expiry: DispatchWorkItem?

    func start(content: Data, fileName: String, lifetime: TimeInterval = 120) async throws -> URL {
        let token = try InstallSecret.make()
        guard fileName.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { throw WLocError.installationFailed }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.shutdown()
                self.pending = continuation
                self.session = InstallDownloadSession(token: token, fileName: fileName, content: content,
                                                     expiresAt: Date().addingTimeInterval(min(max(lifetime, 0.05), 120)))
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters, on: .any)
                    self.listener = listener
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.stateUpdateHandler = { [weak self, weak listener] state in
                        guard let self, let listener else { return }
                        switch state {
                        case .ready:
                            guard let port = listener.port, let session = self.session else { self.shutdown(); return }
                            let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(session.path)")!
                            let ready = self.pending; self.pending = nil; ready?.resume(returning: url)
                        case .failed: self.shutdown()
                        default: break
                        }
                    }
                    listener.start(queue: self.queue)
                    let expiry = DispatchWorkItem { [weak self] in self?.shutdown() }
                    self.expiry = expiry
                    self.queue.asyncAfter(deadline: .now() + min(max(lifetime, 0.05), 120), execute: expiry)
                } catch { self.shutdown() }
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { self.shutdown(); continuation.resume() }
        }
    }
    private func shutdown() {
        expiry?.cancel(); expiry = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
        session?.stop(); session = nil
        let waiting = pending; pending = nil
        waiting?.resume(throwing: WLocError.installationFailed)
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 8, session != nil else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.clients.removeValue(forKey: id); connection.stateUpdateHandler = nil }
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak connection] in connection?.cancel() }
        receive(connection, data: Data())
    }
    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var data = data
            if let chunk { data.append(chunk) }
            guard data.count <= 8192 else { connection.cancel(); return }
            if let end = data.range(of: Data("\r\n\r\n".utf8)) {
                guard var session = self.session else { connection.cancel(); return }
                let response = session.response(to: String(decoding: data[..<end.upperBound], as: UTF8.self))
                self.session = session
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if complete || error != nil { connection.cancel() }
            else { self.receive(connection, data: data) }
        }
    }
    deinit { expiry?.cancel(); listener?.cancel(); for connection in clients.values { connection.cancel() } }
}
