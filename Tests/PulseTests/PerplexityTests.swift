import Foundation
import Testing
@testable import Pulse

/// Answers as Perplexity would, told apart by the session's value.
private final class PerplexityStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let status = switch cookie {
        case "__Secure-next-auth.session-token=signedOut": 302
        case "__Secure-next-auth.session-token=expired": 403
        default: 200
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: status == 200 ? PerplexityTests.credits : Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Perplexity's credits.
///
/// **The fixture is second-hand**: written from CodexBar's Perplexity plugin
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("Perplexity")
struct PerplexityTests {
    static let credits: Data = {
        let url = Bundle.module.url(forResource: "perplexity-credits", withExtension: "json", subdirectory: "Fixtures")!
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    /// Before every expiry in the fixtures.
    private let now = Date(timeIntervalSince1970: 1_788_000_000)
    private let context = ProfileContext(provider: .perplexity, credential: "x", serverAddress: nil)

    private func read(_ json: String) -> ProviderUsage {
        PerplexityUsageService.reading(from: Data(json.utf8), context: context, now: now)
    }

    @Test("The subscription's credit, when it is the only credit, and the balance in dollars")
    func recurringOnly() throws {
        let usage = PerplexityUsageService.reading(from: Self.credits, context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.perplexity))
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.kind == .credits)
        #expect(window.usedFraction == 180.0 / 500.0)
        #expect(!window.reportsLength)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_790_812_800))
        // Cents, as dollars.
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 3.2, currency: "USD"))
        #expect(usage.creditBalance == PerplexityUsageService.money(3.2))
    }

    @Test("Beside a bonus or a purchase, which grant was spent isn't stated: no ring, the balance stands", arguments: [
        #"{"balance_cents":7250,"renewal_date_ts":1790812800,"current_period_purchased_cents":0,"credit_grants":[{"type":"recurring","amount_cents":10000},{"type":"promotional","amount_cents":20000,"expires_at_ts":1800000000}],"total_usage_cents":2750}"#,
        #"{"balance_cents":0,"renewal_date_ts":1790812800,"current_period_purchased_cents":3000,"credit_grants":[{"type":"recurring","amount_cents":5000}],"total_usage_cents":8000}"#,
    ])
    func mixedPools(json: String) {
        let usage = read(json)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining != nil)
    }

    @Test("A bonus that has lapsed is no longer beside it")
    func lapsedBonus() {
        let usage = read(#"{"balance_cents":100,"credit_grants":[{"type":"recurring","amount_cents":1000},{"type":"promotional","amount_cents":500,"expires_at_ts":1700000000}],"total_usage_cents":250}"#)
        #expect(usage.windows.map(\.usedFraction) == [0.25])
    }

    @Test("No subscription credit: no ring, never a full one standing in")
    func noRecurring() {
        let usage = read(#"{"balance_cents":0,"renewal_date_ts":1790812800,"current_period_purchased_cents":0,"credit_grants":[],"total_usage_cents":0}"#)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining?.amount == 0)
    }

    @Test("Camel-case spellings are read too")
    func camelCase() {
        let usage = read(#"{"balanceCents":500,"renewalDateTs":1790812800,"creditGrants":[{"type":"recurring","amountCents":500}],"totalUsageCents":100}"#)
        #expect(usage.windows.map(\.usedFraction) == [0.2])
        #expect(usage.creditRemaining?.amount == 5)
    }

    @Test("A reply that isn't a credits reply can't be read", arguments: ["not json", "{}", #"{"balance_cents":5}"#])
    func unreadable(json: String) {
        #expect(read(json).state == .unavailable(.unreadableReply))
    }

    @Test("Figures that aren't figures are left off, and nothing left is no limits")
    func noFigures() {
        let usage = read(#"{"balance_cents":-4,"credit_grants":[{"type":"recurring","amount_cents":500}],"total_usage_cents":-1}"#)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No session, or one without the sign-in cookie, is asked for, not sent", arguments: [
        nil, "", "next-auth.csrf-token=abc",
    ])
    func missingSession(header: String?) async {
        let context = ProfileContext(provider: .perplexity, credential: header, serverAddress: nil)
        #expect(await PerplexityUsageService.fetch(context).state == .unavailable(.sessionMissing))
    }

    @Test("Only the sign-in cookie is sent, and a redirect or refusal is an expired session", arguments: [
        ("signedOut", ProviderUsage.State.unavailable(.sessionExpired)),
        ("expired", .unavailable(.sessionExpired)),
        ("good", .live),
    ])
    func fetched(scenario: String, state: ProviderUsage.State) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PerplexityStub.self]
        let header = "__cf_bm=x; __Secure-next-auth.session-token=\(scenario); theme=dark"
        let context = ProfileContext(provider: .perplexity, credential: header, serverAddress: nil)
        let usage = await PerplexityUsageService.fetch(context, session: URLSession(configuration: configuration))
        #expect(usage.state == state)
    }
}
