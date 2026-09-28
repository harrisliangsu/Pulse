import Foundation
import Testing
@testable import Pulse

/// Answers as the console would, told apart by the session's value.
private final class SakanaStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let scenario = cookie.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
        let tab = request.url?.query == "tab=payAsYouGo"
        let (status, body): (Int, String) = switch (scenario, tab) {
        case ("signedOut", _): (307, "")
        case ("expired", _): (401, "")
        case ("noTab", true): (500, "")
        case (_, true): (200, SakanaTests.payAsYouGo)
        default: (200, SakanaTests.billing)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Sakana AI's billing page.
///
/// **The fixtures are second-hand**: the markup is written from CodexBar's
/// Sakana provider and its tests (MIT), not captured from a signed-in
/// console. They pin the shape Pulse reads; they do not prove the shape is
/// right. They are inline rather than in `Fixtures/` because they are HTML.
@Suite("Sakana AI")
struct SakanaTests {
    private let context = ProfileContext(provider: .sakana, credential: "x", serverAddress: nil)

    /// Resets as the server renders them: in UTC.
    static let billing = """
    <main>
      <div data-slot="card-title"><span>Standard</span><span>$20/mo</span></div>
      <div data-slot="card-title">Usage limit</div>
      <p class="font-medium text-sm">5-hour</p>
      <p class="text-muted-foreground text-xs tabular-nums">Resets on June 23, 2026 at 2:53 PM</p>
      <button aria-label="The 5-hour window starts with your first request."></button>
      <p class="text-muted-foreground text-sm">92% used</p>
      <p class="font-medium text-sm">Weekly</p>
      <p class="text-muted-foreground text-xs tabular-nums">Resets on June 29, 2026 at 12:00 AM</p>
      <button aria-label="Weekly usage resets every Monday at 00:00 UTC."></button>
      <p class="text-muted-foreground text-sm">32% used</p>
    </main>
    """

    static let payAsYouGo = """
    <main>
      <h2 class="font-semibold text-base">Credit balance</h2>
      <button aria-label="Credit updates may be delayed."></button>
      <p class="font-semibold text-3xl tabular-nums">$1,212.34</p>
      <h2 class="font-semibold">Usage</h2>
      <span class="text-muted-foreground text-sm">Total<!-- -->: <!-- -->$5.67</span>
    </main>
    """

    private static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SakanaStub.self]
        return URLSession(configuration: configuration)
    }

    private func fetch(_ scenario: String) async -> ProviderUsage {
        let header = "theme=dark; __Secure-authjs.session-token=\(scenario)"
        let context = ProfileContext(provider: .sakana, credential: header, serverAddress: nil)
        return await SakanaUsageService.fetch(context, session: session())
    }

    @Test("Both limits are read as stated, resets in UTC, with the plan and the balance")
    func page() throws {
        let usage = SakanaUsageService.reading(
            from: Data(Self.billing.utf8), payAsYouGo: Data(Self.payAsYouGo.utf8), context: context
        )

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.sakana))
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(usage.windows.map(\.usedFraction) == [0.92, 0.32])
        #expect(usage.windows.allSatisfy { $0.reportsLength })
        #expect(usage.windows[0].resetsAt == Self.utc(2026, 6, 23, 14, 53))
        #expect(usage.windows[1].resetsAt == Self.utc(2026, 6, 29, 0, 0))
        #expect(usage.plan == "Standard")
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 1_212.34, currency: "USD"))
        #expect(usage.creditBalance == SakanaUsageService.money(1_212.34))
    }

    @Test("A reset that doesn't read as a date is left off, not the limit")
    func unreadableReset() throws {
        let html = Self.billing.replacingOccurrences(of: "June 23, 2026 at 2:53 PM", with: "soon-ish")
        let usage = SakanaUsageService.reading(from: Data(html.utf8), context: context)
        #expect(usage.windows.first?.usedFraction == 0.92)
        #expect(usage.windows.first?.resetsAt == nil)
    }

    @Test("A limit with no figure is left off; the other stands")
    func missingFigure() {
        let html = Self.billing.replacingOccurrences(of: "92% used", with: "")
        let usage = SakanaUsageService.reading(from: Data(html.utf8), context: context)
        #expect(usage.windows.map(\.kind) == [.weekly])
    }

    @Test("A balance not stated in dollars is left off, not given a currency")
    func balanceWithoutCurrency() {
        let tab = Self.payAsYouGo.replacingOccurrences(of: "$1,212.34", with: "1,212.34")
        #expect(SakanaUsageService.creditBalance(in: tab) == nil)
        #expect(SakanaUsageService.creditBalance(in: Self.billing) == nil)
    }

    @Test("A page with neither limit nor balance can't be read", arguments: ["<main>Billing</main>", ""])
    func unreadable(html: String) {
        let usage = SakanaUsageService.reading(from: Data(html.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No session, or one without the sign-in cookie, is asked for, not sent", arguments: [
        nil, "", "theme=dark; other=1",
    ])
    func missingSession(header: String?) async {
        let context = ProfileContext(provider: .sakana, credential: header, serverAddress: nil)
        #expect(await SakanaUsageService.fetch(context).state == .unavailable(.sessionMissing))
    }

    @Test("A redirect to sign in, or a refusal, is an expired session", arguments: ["signedOut", "expired"])
    func expired(scenario: String) async {
        #expect(await fetch(scenario).state == .unavailable(.sessionExpired))
    }

    @Test("Both pages read: limits and balance")
    func fetched() async {
        let usage = await fetch("good")
        #expect(usage.windows.count == 2)
        #expect(usage.creditRemaining?.amount == 1_212.34)
    }

    @Test("A balance tab that fails leaves the limits standing")
    func balanceTabFails() async {
        let usage = await fetch("noTab")
        #expect(usage.state == .live)
        #expect(usage.windows.count == 2)
        #expect(usage.creditBalance == nil)
    }
}
