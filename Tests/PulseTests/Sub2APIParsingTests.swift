import Foundation
import Testing
@testable import Pulse

/// sub2api is the first provider whose **address** is the reader's, so half of
/// these are about where a key is allowed to go rather than about what came
/// back. The rest are about the reply carrying four unrelated shapes through
/// one route: a wallet with no allowance behind it, a total quota, a
/// subscription's periods, and rolling rate limits.
@Suite("sub2api parsing")
struct Sub2APIParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static func reply(_ name: String) throws -> Sub2APIUsageService.Reply {
        try JSONDecoder().decode(Sub2APIUsageService.Reply.self, from: try fixture(name))
    }

    // MARK: - The address

    /// The rules themselves live in `GatewayAddressTests`; what is sub2api's
    /// alone is the route it ends at and the two suffixes a reader may already
    /// have typed — the deployment's root, or the line they tested with curl.
    @Test("The route is appended once, however much of it was typed")
    func routeIsAppendedOnce() throws {
        let expected = "https://sub.example.com/v1/usage"
        for typed in [
            "sub.example.com",
            "https://sub.example.com",
            "https://sub.example.com/",
            "https://sub.example.com/v1",
            "https://sub.example.com/v1/",
            "https://sub.example.com/v1/usage",
            "https://sub.example.com/v1/usage/",
        ] {
            let url = try #require(Sub2APIUsageService.usageURL(from: typed), "\(typed)")
            #expect(url.absoluteString == expected, "\(typed)")
        }
    }

    /// The shared boundary is still in force through this provider's own
    /// entry point, not only when called directly.
    @Test("An address the shared rule refuses is refused here too")
    func sharedRuleApplies() {
        #expect(Sub2APIUsageService.usageURL(from: "http://sub.example.com") == nil)
        #expect(Sub2APIUsageService.usageURL(from: "https://user:pw@evil.example/") == nil)
    }

    // MARK: - The wallet

    /// The shape the request in issue #40 actually answers with: money, and no
    /// allowance anywhere in the reply.
    @Test("A wallet group reports money and draws no percentage")
    func walletReportsMoneyAndNoWindows() throws {
        let reply = try Self.reply("sub2api-wallet")
        let wallet = try #require(Sub2APIUsageService.wallet(from: reply))

        #expect(wallet.currency == "USD")
        #expect(abs(wallet.amount - 16.33538288) < 0.000001)
        // **No window at all.** There is no denominator in this reply, and
        // Pulse does not invent one.
        #expect(Sub2APIUsageService.windows(from: reply).isEmpty)
    }

    /// `remaining` means the remainder *of something* wherever there is a
    /// quota or a subscription for it to be the remainder of. Read as money
    /// there, a key with 37.5 of its allowance left would show "$37.50" in the
    /// place a wallet's balance goes.
    @Test("Root remaining is money only when there is nothing for it to remain from")
    func remainingIsNotAlwaysMoney() throws {
        #expect(Sub2APIUsageService.wallet(from: try Self.reply("sub2api-quota")) == nil)
        #expect(Sub2APIUsageService.wallet(from: try Self.reply("sub2api-subscription")) == nil)
    }

    /// A deployment selling "credits" or "points" reports a unit that is not a
    /// currency, and formatting those as dollars puts the wrong name on the
    /// figure.
    @Test("A unit that is not a currency code reports no money")
    func unknownUnitIsNotMoney() throws {
        let reply = try JSONDecoder().decode(
            Sub2APIUsageService.Reply.self,
            from: Data(#"{"balance": 500, "unit": "credits"}"#.utf8)
        )
        #expect(Sub2APIUsageService.currency(reply) == nil)
        #expect(Sub2APIUsageService.wallet(from: reply) == nil)
    }

    @Test("A missing unit is USD, which is what the dashboard assumes")
    func missingUnitIsUSD() throws {
        let reply = try JSONDecoder().decode(
            Sub2APIUsageService.Reply.self, from: Data(#"{"balance": 5}"#.utf8)
        )
        #expect(Sub2APIUsageService.currency(reply) == "USD")
    }

    // MARK: - The windows

    @Test("A quota and its rate limits become windows, shortest first")
    func quotaAndRateLimitsBecomeWindows() throws {
        let windows = Sub2APIUsageService.windows(from: try Self.reply("sub2api-quota"))

        #expect(windows.map(\.id) == ["rate.5h", "rate.7d", "quota"])
        #expect(windows[0].kind == .fiveHour)
        #expect(windows[1].kind == .weekly)
        #expect(windows[2].kind == .spend)
        #expect(abs(windows[2].usedFraction - 0.25) < 0.0001)
    }

    /// The window label is the length — "5h" is a statement, not a sort key —
    /// so these are the only windows here a clock may be drawn for.
    @Test("A rate limit states its own length and reset; a quota states neither")
    func onlyRateLimitsReportTheirLength() throws {
        let windows = Sub2APIUsageService.windows(from: try Self.reply("sub2api-quota"))

        #expect(windows[0].reportsLength)
        #expect(windows[0].windowSeconds == 5 * 3_600)
        #expect(windows[0].resetsAt != nil)

        #expect(!windows[2].reportsLength)
        #expect(windows[2].resetsAt == nil)
    }

    /// The reply names three periods and never says when any of them turns
    /// over, so a countdown would be counting to a moment sub2api did not give.
    @Test("Subscription periods state no reset and no length")
    func subscriptionPeriodsHaveNoClock() throws {
        let windows = Sub2APIUsageService.windows(from: try Self.reply("sub2api-subscription"))

        // The monthly limit is zero in the fixture, which is not a limit.
        #expect(windows.map(\.id) == ["subscription.daily", "subscription.weekly"])
        #expect(windows.allSatisfy { !$0.reportsLength })
        #expect(windows.allSatisfy { $0.resetsAt == nil })
        #expect(abs(windows[0].usedFraction - 0.32) < 0.0001)
    }

    /// Dividing by it gives infinity, which clamps to a full ring — an account
    /// reported as spent on the strength of a field left blank.
    @Test("A limit that is missing, zero or not finite produces no window")
    func absentLimitProducesNoWindow() {
        #expect(Sub2APIUsageService.fraction(used: 5, limit: nil) == nil)
        #expect(Sub2APIUsageService.fraction(used: 5, limit: 0) == nil)
        #expect(Sub2APIUsageService.fraction(used: 5, limit: .infinity) == nil)
        #expect(Sub2APIUsageService.fraction(used: nil, limit: 10) == nil)
    }

    /// The deployment's own remainder, not the arithmetic: a field that is
    /// absent has said nothing, and reading silence as zero marks a limit
    /// spent that may not be.
    @Test("Spent comes from the reported remainder, and absence is not zero")
    func spentComesFromTheProvider() {
        #expect(Sub2APIUsageService.isSpent(nil) == false)
        #expect(Sub2APIUsageService.isSpent(0.5) == false)
        #expect(Sub2APIUsageService.isSpent(0) == true)
        #expect(Sub2APIUsageService.isSpent(-1) == true)
    }

    /// A deployment reporting a window Pulse has no word for is read rather
    /// than dropped: the label carries both the count and the unit.
    @Test("Window labels are read as a count and a unit")
    func windowLabelsAreParsed() {
        #expect(Sub2APIUsageService.seconds(of: "5h") == 5 * 3_600)
        #expect(Sub2APIUsageService.seconds(of: "1d") == 86_400)
        #expect(Sub2APIUsageService.seconds(of: "7D") == 7 * 86_400)
        #expect(Sub2APIUsageService.seconds(of: "30m") == nil, "m could be a minute or a month")
        #expect(Sub2APIUsageService.seconds(of: "week") == nil)
        #expect(Sub2APIUsageService.seconds(of: "0h") == nil)
        #expect(Sub2APIUsageService.kind(ofLength: 3 * 3_600) == .other(seconds: 3 * 3_600))
    }

    /// It answers 200 and says no in the body, so nothing upstream of the
    /// reply can tell this from a working key.
    @Test("A key the deployment rejects is flagged in the body, not the status")
    func refusalIsInTheBody() throws {
        #expect(try Self.reply("sub2api-refused").isValid == false)
    }
}
