import Foundation
import Testing
@testable import Pulse

/// xKiro's usage: plan windows, free tokens and the wallet.
///
/// **The fixture is second-hand**: written from CodexBar's xKiro plugin and
/// tests (MIT) and from the example reply in xKiro's own docs
/// (docs.xkiro.com/api/usage), not captured from a live account. It pins the
/// shape Pulse reads; it does not prove the shape is right.
@Suite("xKiro")
struct XKiroTests {
    private let context = ProfileContext(provider: .xKiro, credential: "key", serverAddress: nil)
    private let now = ProfileHTTP.date("2026-09-24T10:00:00Z")!

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Plan windows, free tokens and the wallet are read as reported")
    func usage() throws {
        let usage = XKiroUsageService.reading(from: try fixture("xkiro-usage"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.xKiro))
        #expect(usage.plan == "Ultra")
        #expect(usage.windows.map(\.kind) == [.fiveHour, .daily, .weekly])
        #expect(usage.windows[0].usedFraction == 0.25)
        #expect(usage.windows[2].usedFraction == 0.25)
        #expect(usage.windows[1].usedFraction == 412_030.0 / 300_000_000)
        #expect(usage.windows[0].resetsAt == now.addingTimeInterval(5_005))
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 683.95, currency: "USD"))
        #expect(usage.creditBalance?.contains("683") == true)
    }

    @Test("Free tokens reset at midnight UTC, as xKiro documents")
    func freeTokenReset() throws {
        let usage = XKiroUsageService.reading(from: try fixture("xkiro-usage"), context: context, now: now)
        #expect(usage.windows[1].resetsAt == ProfileHTTP.date("2026-09-25T00:00:00Z"))
    }

    @Test("An unlimited daily allowance draws nothing; the wallet alone is still a reading")
    func unlimited() {
        let json = #"{"object":"usage","plan":null,"windows":[],"free_tokens":{"used_today":5,"limit_per_day":null},"wallet":{"balance_usd":"4.812300"}}"#
        let usage = XKiroUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.windows.isEmpty)
        #expect(usage.plan == nil)
        #expect(usage.creditRemaining?.amount == 4.8123)
    }

    @Test("Windows with no cap, a negative spend or an unnameable length are left off")
    func noFigures() {
        let json = #"""
        {"object":"usage","windows":[{"window_sec":18000,"spent_usd":"1","cap_usd":"0"},
        {"window_sec":604800,"spent_usd":"-1","cap_usd":"10"},{"window_sec":5400,"spent_usd":"1","cap_usd":"10"}],
        "free_tokens":{"used_today":-1,"limit_per_day":100}}
        """#
        let usage = XKiroUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that isn't a usage object can't be read", arguments: ["not json", "{}", #"{"object":"list"}"#])
    func unreadable(json: String) {
        let usage = XKiroUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .xKiro, credential: nil, serverAddress: nil)
        #expect(await XKiroUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
