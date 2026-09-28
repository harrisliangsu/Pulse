import Foundation
import Testing
@testable import Pulse

/// Stands in for the TypeSafe console: a billing page that lists one chunk,
/// the chunk that names the live action id, and the action itself, which
/// answers 404 to any other id. Every request is written down.
private final class TypeSafeFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var liveAction = String(repeating: "b", count: 40)
    nonisolated(unsafe) static var result = Data()
    nonisolated(unsafe) static var log: [String] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let (live, result) = Self.lock.withLock {
            Self.log.append("\(method) \(path)")
            return (Self.liveAction, Self.result)
        }
        var status = 200
        var body = Data()
        switch (method, path) {
        case ("GET", "/settings/billing"):
            body = Data(#"<html><script src="/_next/static/chunks/app.js"></script></html>"#.utf8)
        case ("GET", "/_next/static/chunks/app.js"):
            body = Data(("\"" + live + "\",c.callServer,void 0,c.findSourceMapURL,\"getBillingOverviewResult\"").utf8)
        case ("POST", "/settings/billing"):
            if request.value(forHTTPHeaderField: "Next-Action") == live,
               request.value(forHTTPHeaderField: "Cookie") == "session=fixture" {
                body = Data(#"0:{"a":"$@1"}"#.utf8) + Data("\n1:".utf8) + result
            } else {
                status = 404
            }
        default:
            status = 404
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// TypeSafe's billing balance, read through the console's server action.
///
/// **The fixture is second-hand**: written from CodexBar's TypeSafe plugin and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right. The console exchange is a
/// stub, not observed.
@Suite("TypeSafe", .serialized)
struct TypeSafeTests {
    private let context = ProfileContext(provider: .typeSafe, credential: "session=fixture", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func actionReply(_ result: Data) -> Data {
        Data(#"0:{"a":"$@1"}"#.utf8) + Data("\n1:".utf8) + result
    }

    @Test("The balance is read in dollars from the action's result line, with no ring")
    func balance() throws {
        let usage = TypeSafeUsageService.reading(from: actionReply(try fixture("typesafe-billing-result")), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.typeSafe))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 4.98, currency: "USD"))
        #expect(usage.creditBalance == TypeSafeUsageService.money(4.98))
        #expect(usage.plan == "Free")
    }

    @Test("A zero balance stays zero")
    func zero() {
        let usage = TypeSafeUsageService.reading(
            from: actionReply(Data(#"{"ok":true,"data":{"billing":{"balance":0,"spent":3,"plan":"pro_monthly"}}}"#.utf8)),
            context: context
        )
        #expect(usage.creditRemaining?.amount == 0)
        #expect(usage.plan == "Pro Monthly")
    }

    @Test("A result that isn't one can't be read", arguments: [
        #"0:{"a":"$@1"}"#,
        #"1:{"ok":true,"data":{}}"#,
        #"1:{"ok":true,"data":{"billing":{"balance":null}}}"#,
        #"1:{"ok":true,"data":{"billing":{"balance":"bad"}}}"#,
        "not a reply",
    ])
    func unreadable(body: String) {
        let usage = TypeSafeUsageService.reading(from: Data(body.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A result that says it failed is the service's error")
    func failed() {
        let usage = TypeSafeUsageService.reading(from: Data(#"1:{"ok":false}"#.utf8), context: context)
        #expect(usage.state == .unavailable(.serverError))
    }

    @Test("The sign-in page, escaped or not, is a lapsed session")
    func loginLanding() {
        let landing = #"<script>self.__next_f.push([1,"0:{\"f\":[[[\"\",{\"children\":[\"(auth)\",{\"children\":[\"login\",{\"children\":[\"__PAGE__\",{}]}]}]}]]}"])</script>"#
        #expect(TypeSafeUsageService.isLoginLanding(landing))
        #expect(TypeSafeUsageService.isLoginLanding(#"["(auth)",{"children":["login""#))
        #expect(!TypeSafeUsageService.isLoginLanding(#"["(dashboard)",{"children":["settings""#))
        #expect(TypeSafeUsageService.reading(from: Data(landing.utf8), context: context).state
            == .unavailable(.sessionExpired))
    }

    @Test("Only the console's own scripts are opened, once each")
    func chunks() {
        let page = #"""
        <script src="/_next/static/chunks/a.js"></script>
        <script async src='https://console.typesafe.ai/_next/static/chunks/b.js?v=2'></script>
        <script src="/_next/static/chunks/a.js"></script>
        <script src="https://cdn.example.com/evil.js"></script>
        <script src="//console.typesafe.ai.example.com/x.js"></script>
        <script src="/styles.css"></script>
        """#
        #expect(TypeSafeUsageService.chunkURLs(inPage: page).map(\.absoluteString) == [
            "https://console.typesafe.ai/_next/static/chunks/a.js",
            "https://console.typesafe.ai/_next/static/chunks/b.js?v=2",
        ])
    }

    @Test("The action id is the one named beside the billing call")
    func actionID() {
        let id = String(repeating: "f", count: 40)
        #expect(TypeSafeUsageService.actionID(inChunk: #"x("\#(id)",c.callServer,void 0,c.findSourceMapURL,"getBillingOverviewResult")"#) == id)
        #expect(TypeSafeUsageService.actionID(inChunk: #""abc123","getBillingOverviewResult""#) == nil)
        #expect(TypeSafeUsageService.actionID(inChunk: "console.log('fixture')") == nil)
    }

    @Test("A pasted header may carry its name")
    func pasted() {
        #expect(TypeSafeUsageService.cookieHeader("Cookie: a=1; b=2") == "a=1; b=2")
        #expect(TypeSafeUsageService.cookieHeader(" a=1 ") == "a=1")
    }

    @Test("The action id is found once, kept, and found again when it goes stale")
    func discovery() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TypeSafeFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        let result = try fixture("typesafe-billing-result")
        TypeSafeFixtureProtocol.lock.withLock {
            TypeSafeFixtureProtocol.result = result
            TypeSafeFixtureProtocol.log = []
            TypeSafeFixtureProtocol.liveAction = String(repeating: "b", count: 40)
        }
        // Far enough ahead that nothing another run cached is still trusted.
        let start = Date().addingTimeInterval(1_000 * 86_400)

        let first = await TypeSafeUsageService.fetch(context, session: session, now: start)
        #expect(first.creditRemaining?.amount == 4.98)
        let second = await TypeSafeUsageService.fetch(context, session: session, now: start.addingTimeInterval(60))
        #expect(second.creditRemaining?.amount == 4.98)

        TypeSafeFixtureProtocol.lock.withLock { TypeSafeFixtureProtocol.liveAction = String(repeating: "c", count: 40) }
        let third = await TypeSafeUsageService.fetch(context, session: session, now: start.addingTimeInterval(120))
        #expect(third.creditRemaining?.amount == 4.98)

        let log = TypeSafeFixtureProtocol.lock.withLock { TypeSafeFixtureProtocol.log }
        #expect(log == [
            "GET /settings/billing", "GET /_next/static/chunks/app.js", "POST /settings/billing",
            "POST /settings/billing",
            "POST /settings/billing", "GET /settings/billing", "GET /_next/static/chunks/app.js", "POST /settings/billing",
        ])
    }

    @Test("No header is asked for, not sent")
    func missing() async {
        let empty = ProfileContext(provider: .typeSafe, credential: "Cookie: ", serverAddress: nil)
        #expect(await TypeSafeUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }
}
