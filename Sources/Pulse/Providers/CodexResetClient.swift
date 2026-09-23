import Foundation

/// Reads the public Codex Resets status document.
///
/// The same data the site's MCP server exposes, fetched over HTTP so Pulse
/// does not have to run an MCP client. Rate limits, challenges and outages
/// come back as a failed reply; the caller keeps whatever it last showed.
enum CodexResetClient {
    static let endpoint = URL(string: "https://codex-resets.com/api/v1/status")!

    static func fetch(etag: String?, session: URLSession = NetworkSession.shared) async -> CodexResetReply {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pulse", forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

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
