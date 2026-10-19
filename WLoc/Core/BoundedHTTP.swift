import Foundation

extension URLSession {
    /// Read incrementally and cancel the transfer as soon as the cap is reached.
    func boundedData(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        precondition(maximumBytes > 0)
        let (bytes, response) = try await bytes(for: request)
        defer { bytes.task.cancel() }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw WLocError.responseTooLarge }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, 8192))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw WLocError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
    }
}
