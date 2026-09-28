import Foundation
import Testing
@testable import Pulse

/// Factory's two billings: the token-rate-limits windows and the older
/// Standard/Premium allowances.
///
/// **The fixtures are second-hand**: written from CodexBar's Factory provider
/// and its tests (MIT), not captured from a live account. They pin the shapes
/// Pulse reads; they do not prove the shapes are right.
@Suite("Factory")
struct FactoryTests {
    private let context = ProfileContext(provider: .factory, credential: "fk-key", serverAddress: nil)
    /// Before every reset in the fixtures, so none of them has passed.
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func limits(_ json: String) -> ProviderUsage? {
        FactoryUsageService.limitsReading(from: Data(json.utf8), plan: nil, context: context, now: now)
    }

    private func allowances(_ json: String) -> ProviderUsage {
        FactoryUsageService.allowanceReading(from: Data(json.utf8), plan: nil, context: context, now: now)
    }

    // MARK: - Who is asking

    @Test("The plan's name and the user's id come from auth/me")
    func account() throws {
        let identity = FactoryUsageService.account(from: try fixture("factory-auth-me"))
        #expect(identity.plan == "Team")
        #expect(identity.userID == "user_123")
    }

    @Test("Without a plan name, the tier stands in; without either, nothing does")
    func tier() {
        let tierOnly = #"{"organization":{"subscription":{"factoryTier":"enterprise"}}}"#
        #expect(FactoryUsageService.account(from: Data(tierOnly.utf8)).plan == "Enterprise")
        let unreadable = FactoryUsageService.account(from: Data("not json".utf8))
        #expect(unreadable.plan == nil && unreadable.userID == nil)
    }

    // MARK: - The token-rate-limits billing

    @Test("Both pools are read as reported, Standard first, each shortest first")
    func tokenRateLimits() throws {
        let usage = try #require(FactoryUsageService.limitsReading(
            from: try fixture("factory-billing-limits"), plan: "Team", context: context, now: now))

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.factory))
        #expect(usage.plan == "Team")
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly, .monthly, .fiveHour, .weekly, .monthly])
        #expect(usage.windows.map(\.usedFraction) == [0.12, 0.34, 0.56, 0.07, 0.08, 0.09])
        #expect(usage.windows.map(\.scope) == [nil, nil, nil, "Core", "Core", "Core"])
        #expect(Set(usage.windows.map(\.id)).count == 6)
    }

    @Test("Each window's reset: seconds remaining, then an end in milliseconds or ISO 8601")
    func resets() throws {
        let usage = try #require(FactoryUsageService.limitsReading(
            from: try fixture("factory-billing-limits"), plan: nil, context: context, now: now))
        #expect(usage.windows[0].resetsAt == now.addingTimeInterval(3_600))
        #expect(usage.windows[1].resetsAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(usage.windows[2].resetsAt == ProfileHTTP.date("2026-10-20T00:00:00Z"))
        // A billing month is not a stated length; five hours and a week are.
        #expect(usage.windows.map(\.reportsLength) == [true, true, false, true, true, false])
    }

    @Test("The extra-usage balance is money, in US cents")
    func extraUsage() throws {
        let usage = try #require(FactoryUsageService.limitsReading(
            from: try fixture("factory-billing-limits"), plan: nil, context: context, now: now))
        #expect(usage.creditRemaining == .init(amount: 25, currency: "USD"))
        #expect(usage.creditBalance?.contains("25") == true)
    }

    @Test("No extra usage offered and none bought: no balance at all, rather than a zero")
    func noExtraUsage() throws {
        let json = #"{"usesTokenRateLimitsBilling":true,"extraUsageBalanceCents":0,"extraUsageAllowed":false,"#
            + #""limits":{"standard":{"fiveHour":{"usedPercent":40,"secondsRemaining":60}}}}"#
        let usage = try #require(limits(json))
        #expect(usage.creditBalance == nil)
        #expect(usage.creditRemaining == nil)
        #expect(usage.windows.map(\.usedFraction) == [0.4])
    }

    @Test("A window whose stated end has passed is left off, not drawn at zero")
    func endedWindow() throws {
        let json = #"{"usesTokenRateLimitsBilling":true,"limits":{"standard":{"#
            + #""fiveHour":{"usedPercent":80,"windowEnd":1700000000},"#
            + #""weekly":{"usedPercent":30,"secondsRemaining":86400}}}}"#
        let usage = try #require(limits(json))
        #expect(usage.windows.map(\.kind) == [.weekly])
    }

    @Test("A Core pool with nothing in it and no clock is not drawn")
    func emptyCore() throws {
        let json = #"{"usesTokenRateLimitsBilling":true,"limits":{"#
            + #""standard":{"weekly":{"usedPercent":30,"secondsRemaining":86400}},"#
            + #""core":{"fiveHour":{"usedPercent":0},"weekly":{"usedPercent":0},"monthly":{"usedPercent":0}}}}"#
        let usage = try #require(limits(json))
        #expect(usage.windows.allSatisfy { $0.scope == nil })
    }

    @Test("A spent limit says so")
    func exhausted() throws {
        let json = #"{"usesTokenRateLimitsBilling":true,"limits":{"standard":{"#
            + #""fiveHour":{"usedPercent":100,"secondsRemaining":600}}}}"#
        #expect(try #require(limits(json)).windows.first?.isExhausted == true)
    }

    @Test("An account not on the newer billing is sent to the older route", arguments: [
        #"{"usesTokenRateLimitsBilling":false,"limits":{"standard":{"weekly":{"usedPercent":3}}}}"#,
        #"{"usesTokenRateLimitsBilling":true}"#,
        #"{"extraUsageBalanceCents":0}"#,
        "not json",
    ])
    func notOnTokenRateLimits(json: String) {
        #expect(limits(json) == nil)
    }

    @Test("Figures that aren't figures are left off, and nothing left is no limits")
    func noFigures() throws {
        let json = #"{"usesTokenRateLimitsBilling":true,"limits":{"standard":{"#
            + #""fiveHour":{"usedPercent":-5,"secondsRemaining":60},"weekly":{"secondsRemaining":60}}}}"#
        #expect(try #require(limits(json)).state == .unavailable(.noLimitsReported))
    }

    // MARK: - The older billing

    @Test("Standard and Premium are read from Factory's own ratio, over the stated period")
    func allowances() throws {
        let usage = FactoryUsageService.allowanceReading(
            from: try fixture("factory-subscription-usage"), plan: "Team", context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.plan == "Team")
        #expect(usage.windows.map(\.scope) == ["Standard", "Premium"])
        #expect(usage.windows.map(\.usedFraction) == [0.1, 0.2])
        #expect(usage.windows.allSatisfy { $0.kind == .monthly })
        // Milliseconds; both ends are stated, so the period's length is too.
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_702_592_000))
        #expect(usage.windows[0].windowSeconds == 30 * 86_400)
        #expect(usage.windows[0].reportsLength)
    }

    @Test("Without a start, the period's length is a sort key, not a claim")
    func noStart() {
        let json = #"{"usage":{"endDate":1702592000000,"standard":{"usedRatio":0.5}}}"#
        let window = allowances(json).windows.first
        #expect(window?.usedFraction == 0.5)
        #expect(window?.reportsLength == false)
    }

    @Test("A zero ratio beside tokens used and a real allowance is a lagging cache: the counts are read")
    func laggingRatio() {
        let json = #"{"usage":{"standard":{"userTokens":5000000,"totalAllowance":20000000,"usedRatio":0}}}"#
        #expect(allowances(json).windows.first?.usedFraction == 0.25)
    }

    @Test("A ratio out of scale is not read; the counts are, when both are reported")
    func ratioOutOfScale() {
        let counted = #"{"usage":{"standard":{"userTokens":50,"totalAllowance":100,"usedRatio":1.5}}}"#
        #expect(allowances(counted).windows.first?.usedFraction == 0.5)
        // CodexBar reads 10.0 as ten percent when there's no allowance. The
        // scale is a guess, so here it is nothing.
        let guessed = #"{"usage":{"standard":{"userTokens":0,"totalAllowance":0,"usedRatio":10.0}}}"#
        #expect(allowances(guessed).state == .unavailable(.noLimitsReported))
    }

    @Test("An \"unlimited\" allowance draws no ring, rather than one against a figure nobody gave")
    func unlimited() {
        let json = #"{"usage":{"standard":{"userTokens":50000000,"totalAllowance":2000000000000}}}"#
        #expect(allowances(json).state == .unavailable(.noLimitsReported))
    }

    @Test("A pool the plan doesn't have is left off, not drawn at zero")
    func absentPool() {
        let json = #"{"usage":{"standard":{"usedRatio":0.3},"premium":{"userTokens":0,"totalAllowance":0,"usedRatio":0}}}"#
        #expect(allowances(json).windows.map(\.scope) == ["Standard"])
    }

    @Test("A reply that can't be read", arguments: ["not json", "{}", #"{"usage":null}"#])
    func unreadable(json: String) {
        #expect(allowances(json).state == .unavailable(.unreadableReply))
    }

    // MARK: - Credential and statuses

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .factory, credential: " \n", serverAddress: nil)
        #expect(await FactoryUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }

    @Test("Statuses mean what they mean everywhere", arguments: [
        (401, ProviderUsage.Unavailability.apiKeyRefused), (403, .apiKeyRefused),
        (429, .rateLimited), (500, .serverError), (404, .serverError),
    ])
    func statuses(status: Int, reason: ProviderUsage.Unavailability) {
        #expect(ProfileHTTP.classify(.init(data: Data(), status: status)) == .failure(reason))
    }
}
