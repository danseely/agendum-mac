import Foundation

/// URLProtocol-based test stub. Tests register a handler closure that maps each
/// outgoing `URLRequest` to a `(status, headers, body)` tuple — no network.
///
/// Thread-safe (Sendable closure stored behind an `NSLock`). The handler is
/// global state because URLProtocol subclass init signatures are fixed by
/// Foundation; tests should set + reset around their scope.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, headers: [String: String], body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?

    static func setHandler(_ handler: Handler?) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
    }

    static func currentHandler() -> Handler? {
        lock.lock(); defer { lock.unlock() }
        return _handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.currentHandler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let (status, headers, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "about:blank")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Returns a `URLSession` configured to route all requests through the stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// Sendable, lock-protected wrapper that lets test bodies tally and inspect the
/// requests their handler received.
final class RecordedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        _items.append(request)
    }

    var all: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    var count: Int { all.count }
}
