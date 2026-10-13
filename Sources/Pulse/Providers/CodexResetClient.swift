import Foundation

/// Reads the public Codex Resets status document.
///
/// The same data the site's MCP server exposes, fetched over HTTP so Pulse
/// does not have to run an MCP client. Rate limits, challenges and outages
/// come back as a failed reply; the caller keeps whatever it last showed.
enum CodexResetClient {
    /// The public site. The card's link opens this. `endpoint` is the status
    /// document, and is not a page.
    static let site = URL(string: "https://codex-resets.com")!
    static let endpoint = URL(string: "https://codex-resets.com/api/v1/status")!

    /// The status request.
    ///
    /// `cachePolicy` ignores the shared session's cache. The document is
    /// served with `Cache-Control: max-age=14400`, and the default policy
    /// treats that copy as fresh for four hours: the poller's own wait is
    /// shorter, but the session never sends it, `If-None-Match` included.
    /// A scheduled time then keeps counting down after the announcement has
    /// already replaced it. The server can still answer 304.
    static func request(etag: String?) -> URLRequest {
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pulse", forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    static func fetch(etag: String?, session: URLSession = NetworkSession.shared) async -> CodexResetReply {
        let request = request(etag: etag)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return CodexResetReply(payload: .failed, etag: nil, maxAge: nil, retryAfter: nil)
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                guard let name = key as? String else { continue }
                if let text = value as? String {
                    headers[name] = text
                } else if let number = value as? NSNumber {
                    headers[name] = number.stringValue
                }
            }
            return CodexResetReply.interpret(statusCode: http.statusCode, headers: headers, body: data)
        } catch {
            return CodexResetReply(payload: .failed, etag: nil, maxAge: nil, retryAfter: nil)
        }
    }
}
