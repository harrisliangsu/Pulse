import Foundation
import Testing
@testable import Pulse

/// Synthetic's quota lanes.
///
/// **The fixture is second-hand**: written from CodexBar's Synthetic plugin
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("Synthetic")
struct SyntheticTests {
    private let context = ProfileContext(provider: .synthetic, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The three named lanes are read as reported, shortest first")
    func lanes() throws {
        let usage = SyntheticUsageService.reading(from: try fixture("synthetic-quotas"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.synthetic))
        #expect(usage.plan == "Starter")
        #expect(usage.windows.map(\.kind) == [.other(seconds: 3_600), .fiveHour, .weekly])
        // 2 of 250 searches; 150 of 750 spent (600 left); 98% left of the week.
        #expect(usage.windows.map(\.usedFraction) == [0.008, 0.2, 0.02])
        #expect(usage.windows[0].scope == "Search")
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-04-17T04:30:01.494Z"))
    }

    @Test("A regeneration tick is not a reset")
    func ticksAreNotResets() throws {
        let usage = SyntheticUsageService.reading(from: try fixture("synthetic-quotas"), context: context)
        #expect(usage.windows.filter { $0.kind == .fiveHour || $0.kind == .weekly }.allSatisfy { $0.resetsAt == nil })
    }

    @Test("The slots may sit under data, and a weekly lane may state only dollars")
    func wrappedAndDollars() {
        let json = #"{"data":{"weeklyTokenLimit":{"maxCredits":"$36.00","remainingCredits":"$27.00"}}}"#
        let usage = SyntheticUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.kind) == [.weekly])
        #expect(usage.windows.map(\.usedFraction) == [0.25])
    }

    @Test("A lane that says it is limited is spent")
    func limited() {
        let json = #"{"rollingFiveHourLimit":{"remaining":700,"max":750,"limited":true}}"#
        let usage = SyntheticUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.first?.isExhausted == true)
    }

    @Test("A reply that isn't an object can't be read", arguments: ["not json", "[1,2]"])
    func unreadable(json: String) {
        let usage = SyntheticUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("Figures that aren't figures are left off; generic quota lists are not guessed at")
    func noFigures() {
        let json = #"""
        {"rollingFiveHourLimit":{"remaining":-5,"max":750},
         "weeklyTokenLimit":{"percentRemaining":140},
         "search":{"hourly":{"limit":0,"requests":2}},
         "quotas":[{"name":"Monthly","limit":1000,"used":250}]}
        """#
        let usage = SyntheticUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .synthetic, credential: nil, serverAddress: nil)
        #expect(await SyntheticUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
