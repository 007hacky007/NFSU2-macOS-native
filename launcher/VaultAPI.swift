import Foundation

struct VaultRemote {
    let revision: String
    let saved: Date
    let earlier: Date?
}
struct VaultDownload {
    let remote: VaultRemote
    let box: Data
}
struct VaultConflict: LocalizedError {
    var errorDescription: String? { "The cloud changed since you checked. Check again before choosing which copy to use." }
}

// One bounded request per instance. Redirects cannot forward the bearer token to another endpoint.
private final class VaultRequest: NSObject, URLSessionDataDelegate {
    private let done = DispatchSemaphore(value: 0)
    private var bytes = Data()
    private var response: HTTPURLResponse?
    private var failure: Error?
    func run(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 35
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request); task.resume()
        done.wait(); session.finishTasksAndInvalidate()
        if let error = failure { throw error }
        guard let response = response else { throw SaveError("The cloud server did not return an HTTP response.") }
        return (response,bytes)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= VaultCrypto.maxBox else {
            failure = SaveError("The cloud server's response is too large."); completionHandler(.cancel); return
        }
        self.response = http; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= VaultCrypto.maxBox else { failure = SaveError("The cloud server's response is too large."); dataTask.cancel(); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil { failure = error }; done.signal()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct VaultAPI {
    let endpoint: URL
    let token: String
    static func endpoint(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text), let host = c.host,
              !text.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              c.user == nil, c.password == nil, c.fragment == nil, c.query == nil,
              c.port == nil || (1...65535).contains(c.port!),
              c.scheme == "https" || (c.scheme == "http" && loopback(host)), let url = c.url else {
            throw SaveError("Use an https:// vault URL. Plain HTTP is allowed only for loopback testing.")
        }
        return url
    }
    private static func loopback(_ host: String) -> Bool {
        if ["localhost","::1","[::1]"].contains(host.lowercased()) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && (UInt($0) ?? 256) <= 255 }
    }
    static func defaultEndpoint(server: String) -> String {
        guard var c = URLComponents(string: server), c.scheme == "wss" || c.scheme == "ws" else { return "" }
        c.scheme = c.scheme == "wss" ? "https" : "http"; c.path = "/vault"; c.query = nil; c.fragment = nil
        return c.string ?? ""
    }
    private func request(_ method: String, box: Data? = nil, revision: String? = nil) throws -> (HTTPURLResponse, Data) {
        _ = try Self.endpoint(endpoint.absoluteString)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method; request.httpBody = box
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("NFSU2-Native-Saves", forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if method == "PUT" {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(revision ?? "*", forHTTPHeaderField: revision == nil ? "If-None-Match" : "If-Match")
        }
        return try VaultRequest().run(request)
    }
    private func remote(_ response: HTTPURLResponse) throws -> VaultRemote {
        guard let rev = response.value(forHTTPHeaderField: "ETag"), rev.range(of: "^\"[0-9a-fA-F]{16}\"$", options: .regularExpression) != nil,
              let savedText = response.value(forHTTPHeaderField: "X-Vault-Saved"), let saved = Double(savedText), saved.isFinite, saved > 0 else {
            throw SaveError("The cloud server returned incomplete version information.")
        }
        let earlier = response.value(forHTTPHeaderField: "X-Vault-Earlier").flatMap(Double.init).flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        return VaultRemote(revision: rev, saved: Date(timeIntervalSince1970: saved / 1000), earlier: earlier)
    }
    private func check(_ response: HTTPURLResponse) throws {
        if response.statusCode == 412 { throw VaultConflict() }
        guard (200...299).contains(response.statusCode) else {
            let detail: String
            switch response.statusCode {
            case 429: detail = "The server asks you to wait before trying again."
            case 413: detail = "The encrypted save exceeds the server limit."
            case 507: detail = "The cloud server is out of storage."
            case 503: detail = "The server is not accepting more cloud saves right now."
            default: detail = "Cloud request failed (HTTP \(response.statusCode))."
            }
            throw SaveError(detail)
        }
    }
    func get() throws -> VaultDownload? {
        let (response, data) = try request("GET")
        if response.statusCode == 404 { return nil }
        try check(response)
        guard (29...VaultCrypto.maxBox).contains(data.count) else { throw SaveError("The cloud server returned an invalid encrypted save.") }
        return VaultDownload(remote: try remote(response), box: data)
    }
    func put(_ box: Data, revision: String?) throws -> VaultRemote {
        guard (29...VaultCrypto.maxBox).contains(box.count) else { throw SaveError("Encrypted save size is outside the server limit.") }
        let (response, _) = try request("PUT", box: box, revision: revision)
        try check(response); return try remote(response)
    }
}
