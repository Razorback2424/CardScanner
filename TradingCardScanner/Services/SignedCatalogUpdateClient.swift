import Foundation

enum SignedCatalogUpdateError: Error, Sendable {
    case invalidURL, unexpectedNotModified, invalidResponse
    case badResponse(Int), payloadTooLarge
}

enum SignedCatalogFetchResult<Envelope: Sendable>: Sendable {
    case fetched(Envelope), notModified
}

/// Transport only. Signature, revision and registry validation remain with the
/// game contract. Validators are cleared when that contract rejects a response.
actor SignedCatalogUpdateClient<Envelope: Decodable & Sendable> {
    private let endpoint: URL
    private let configuration: URLSessionConfiguration
    private let maximumBytes: Int
    private var etag: String?
    private var modified: String?

    init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral,
         maximumBytes: Int = 48 * 1_024 * 1_024) throws {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil,
              endpoint.port == nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil else { throw SignedCatalogUpdateError.invalidURL }
        precondition(maximumBytes > 0 && maximumBytes <= 48 * 1_024 * 1_024)
        self.endpoint = endpoint
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.maximumBytes = maximumBytes
    }

    func fetch() async throws -> SignedCatalogFetchResult<Envelope> {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        for attempt in 0...2 {
            try Task.checkCancellation()
            if attempt > 0 { try await Task.sleep(for: .seconds(Double(attempt))) }
            do {
                let transfer = BoundedCatalogTransfer(maximumBytes: maximumBytes)
                let (data, response) = try await withTaskCancellationHandler {
                    try await transfer.read(request, configuration: configuration)
                } onCancel: { transfer.cancel() }
                guard let http = response as? HTTPURLResponse, http.url == endpoint else {
                    throw SignedCatalogUpdateError.invalidResponse
                }
                if http.statusCode == 304 {
                    guard etag != nil || modified != nil else { throw SignedCatalogUpdateError.unexpectedNotModified }
                    return .notModified
                }
                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode >= 500 && attempt < 2 { continue }
                    throw SignedCatalogUpdateError.badResponse(http.statusCode)
                }
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                etag = http.value(forHTTPHeaderField: "ETag")
                modified = http.value(forHTTPHeaderField: "Last-Modified")
                return .fetched(envelope)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if error is URLError, attempt < 2 { continue }
                throw error
            }
        }
        throw SignedCatalogUpdateError.invalidResponse
    }

    func resetConditionalState() { etag = nil; modified = nil }
}

/// Bounds bytes while receiving them, including responses without Content-Length.
/// One transfer owns one session; completion/cancellation tears both down once.
private final class BoundedCatalogTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var bytes = Data()
    private var response: URLResponse?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    func read(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !finished else {
                lock.unlock(); continuation.resume(throwing: CancellationError()); return
            }
            self.continuation = continuation
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: request)
            self.task = task
            lock.unlock()
            task.resume()
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation, session = session
        self.continuation = nil; self.session = nil; self.task = nil; bytes = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard response.expectedContentLength <= maximumBytes else {
            completionHandler(.cancel); finish(.failure(SignedCatalogUpdateError.payloadTooLarge)); return
        }
        lock.lock(); self.response = response; let finished = finished; lock.unlock()
        completionHandler(finished ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= maximumBytes - bytes.count else {
            lock.unlock(); finish(.failure(SignedCatalogUpdateError.payloadTooLarge)); return
        }
        bytes.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let data = bytes, response = response
        lock.unlock()
        if let response { finish(.success((data, response))) }
        else { finish(.failure(SignedCatalogUpdateError.invalidResponse)) }
    }
}
