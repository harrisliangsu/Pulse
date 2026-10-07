import Foundation
import Testing
@testable import Pulse

/// The detailed card's cache hit rate: cache reads over every input token,
/// and nothing at all where the records cannot vouch for their split.
struct CacheHitRateTests {
    /// Yesterday, so `day(1)` is today: a span is counted back from today.
    private let start = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!

    private func day(_ offset: Int, _ tally: TokenTally, unclassified: Int = 0) -> LedgerDay {
        var day = LedgerDay(date: Calendar.current.date(byAdding: .day, value: offset, to: start)!,
                            tokens: tally.total + unclassified, cost: 0, unpricedTokens: 0, models: [:])
        day.tally = tally
        return day
    }

    private func ledger(_ days: [LedgerDay]) -> UsageLedger {
        UsageLedger(days: days, earliest: days.first?.date, unpricedModels: [], modelNames: [:], slots: [])
    }

    @Test func readsOverEveryInputTokenWithOutputLeftOut() throws {
        // Claude Code's shape: fresh input, cache written, cache read.
        let rate = try #require(ledger([
            day(0, TokenTally(input: 100, cacheWrite: 100, cacheRead: 600, output: 5_000)),
            day(1, TokenTally(input: 50, cacheWrite: 50, cacheRead: 100, output: 0)),
        ]).cacheHitRate(overLast: 31))
        #expect(abs(rate - 0.7) < 0.0001)
    }

    @Test func codexWritesNoCacheAndStillHasARate() throws {
        let rate = try #require(ledger([day(0, TokenTally(input: 250, cacheWrite: 0, cacheRead: 750, output: 40))])
            .cacheHitRate(overLast: 31))
        #expect(abs(rate - 0.75) < 0.0001)
    }

    @Test func onlyTheSpanCounts() throws {
        let rate = try #require(ledger([
            day(0, TokenTally(input: 1_000, cacheRead: 0)),
            day(1, TokenTally(input: 10, cacheRead: 90)),
        ]).cacheHitRate(overLast: 1))
        #expect(abs(rate - 0.9) < 0.0001)
    }

    @Test func aSpanIsCalendarDaysNotTheLastRecords() {
        // Last used ten days ago: the last week is quiet, not the week before
        // the break.
        let stale = ledger([
            day(-10, TokenTally(input: 10, cacheRead: 90)),
            day(-9, TokenTally(input: 10, cacheRead: 90)),
        ])
        #expect(stale.total(overLast: 7).tokens == 0)
        #expect(stale.cacheHitRate(overLast: 7) == nil)
        #expect(stale.recent(7).count == 7)
        #expect(stale.total(overLast: 31).tokens == 200)
        // A ledger younger than the span starts at its first day.
        #expect(ledger([day(1, TokenTally(input: 1))]).recent(31).count == 1)
    }

    @Test func aModelThatNeverNamedTheCacheIsLeftOut() throws {
        // One model through a compatible endpoint that writes no cache field,
        // one through Anthropic: the rate is the second's alone.
        let silent = TokenTally(input: 900, repliesWithoutCacheFields: 3)
        let cached = TokenTally(input: 10, cacheRead: 90)
        var mixed = LedgerDay(date: day(1, TokenTally()).date, tokens: 1_000, cost: 0, unpricedTokens: 0,
                              models: ["gateway": 900, "claude": 100])
        mixed.tally = silent + cached
        mixed.modelTallies = ["gateway": silent, "claude": cached]
        let rate = try #require(ledger([mixed]).cacheHitRate(overLast: 31))
        #expect(abs(rate - 0.9) < 0.0001)
        #expect(ledger([mixed]).cacheHitRatesByModel(overLast: 31).map(\.name) == ["claude"])

        var only = day(1, silent)
        only.modelTallies = ["gateway": silent]
        #expect(ledger([only]).cacheHitRate(overLast: 31) == nil)
    }

    @Test func tokensNoKindCanClaimWithholdIt() {
        #expect(ledger([day(0, TokenTally(input: 10, cacheRead: 90), unclassified: 500)]).cacheHitRate(overLast: 31) == nil)
    }

    @Test func countsThatMayBeShortWithholdIt() {
        var partial = ledger([day(0, TokenTally(input: 10, cacheRead: 90))])
        partial.hasPartialCounts = true
        #expect(partial.cacheHitRate(overLast: 31) == nil)
    }

    @Test func noInputIsNoRate() {
        #expect(ledger([day(0, TokenTally(output: 100))]).cacheHitRate(overLast: 31) == nil)
        #expect(UsageLedger.empty.cacheHitRate(overLast: 31) == nil)
    }

    @Test func addingAgentsKeepsTheirKinds() throws {
        let added = UsageLedger.adding([
            ledger([day(0, TokenTally(input: 10, cacheRead: 30))]),
            ledger([day(0, TokenTally(input: 30, cacheRead: 30))]),
        ])
        #expect(added.days.first?.tally == TokenTally(input: 40, cacheRead: 60))
        #expect(abs(try #require(added.cacheHitRate(overLast: 31)) - 0.6) < 0.0001)
    }

    // MARK: By model

    private func modelDay(_ offset: Int, _ tallies: [String: TokenTally],
                          untallied: [String: Int] = [:], unclassified: [String: Int] = [:]) -> LedgerDay {
        var models = tallies.mapValues(\.total)
        for (raw, tokens) in untallied { models[raw, default: 0] += tokens }
        for (raw, tokens) in unclassified { models[raw, default: 0] += tokens }
        var day = LedgerDay(date: Calendar.current.date(byAdding: .day, value: offset, to: start)!,
                            tokens: models.values.reduce(0, +), cost: 0, unpricedTokens: 0, models: models)
        day.modelTallies = tallies
        day.modelUnclassifiedTokens = unclassified
        return day
    }

    @Test func eachModelHasItsOwnRateMostInputFirst() {
        let rates = ledger([
            modelDay(0, ["opus": TokenTally(input: 10, cacheWrite: 10, cacheRead: 80, output: 999),
                         "haiku": TokenTally(input: 30, cacheRead: 10)]),
            modelDay(1, ["opus": TokenTally(input: 50, cacheRead: 50)]),
        ]).cacheHitRatesByModel(overLast: 31)
        #expect(rates.map(\.name) == ["opus", "haiku"])
        #expect(rates.map(\.inputTokens) == [200, 40])
        #expect(abs(rates[0].rate - 0.65) < 0.0001)
        #expect(abs(rates[1].rate - 0.25) < 0.0001)
    }

    @Test func rawIdsOfOneModelAreOneLine() throws {
        var grouped = ledger([modelDay(0, ["claude-opus-5-20260101": TokenTally(input: 10, cacheRead: 30),
                                           "claude-opus-5": TokenTally(input: 10, cacheRead: 50)])])
        grouped.modelNames = ["claude-opus-5-20260101": "Claude Opus 5", "claude-opus-5": "Claude Opus 5"]
        let rates = grouped.cacheHitRatesByModel(overLast: 31)
        #expect(rates.count == 1)
        #expect(rates.first?.name == "Claude Opus 5")
        #expect(abs(try #require(rates.first).rate - 0.8) < 0.0001)
    }

    @Test func aModelWithAnyUnvouchedTokensIsLeftOut() {
        let rates = ledger([
            modelDay(0, ["opus": TokenTally(input: 10, cacheRead: 90), "sonnet": TokenTally(input: 10, cacheRead: 90)]),
            // A day that counted sonnet with no split kept, and gpt with a bare total.
            modelDay(1, ["opus": TokenTally(input: 10, cacheRead: 90)], untallied: ["sonnet": 40]),
            modelDay(2, ["gpt": TokenTally(input: 5, cacheRead: 5)], unclassified: ["gpt": 20]),
        ]).cacheHitRatesByModel(overLast: 31)
        #expect(rates.map(\.name) == ["opus"])
    }

    @Test func countsThatMayBeShortListNoModel() {
        var partial = ledger([modelDay(0, ["opus": TokenTally(input: 10, cacheRead: 90)])])
        partial.hasPartialCounts = true
        #expect(partial.cacheHitRatesByModel(overLast: 31).isEmpty)
    }
}
