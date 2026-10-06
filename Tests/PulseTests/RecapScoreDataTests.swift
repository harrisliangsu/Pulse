import Foundation
import Testing
@testable import Pulse

/// What the scorecard's small charts are built from: which slot is future,
/// quiet or busiest, and when a figure is left out rather than drawn as a zero.
@Suite("Recap scorecard data")
struct RecapScoreDataTests {
    private static func deck(_ recap: Recap) -> RecapDeck {
        RecapDeck(recap: recap, monthlyPrice: 200, hidesProjects: false)
    }

    @Test("The stamp is the period as an id")
    func stamp() {
        #expect(Self.deck(RecapSamples.month()).scoreStamp == "NO. 2026·09")
        #expect(Self.deck(RecapSamples.year()).scoreStamp == "NO. 2025")
    }

    @Test("A finished month has a bar per day: quiet days grey, one busiest, none to come")
    func finishedMonthBars() {
        let bars = Self.deck(RecapSamples.month()).scoreBars
        #expect(bars.count == 30)
        #expect(!bars.contains { $0.slot == .future })
        // Days 4, 10 and 11 are quiet in the sample.
        #expect(bars[3].slot == .quiet && bars[9].slot == .quiet && bars[10].slot == .quiet)
        #expect(bars.filter(\.isBusiest).count == 1)
        #expect(bars.filter { $0.slot == .active }.count == 27)
        // The busiest day is the 17th, the fullest bar.
        #expect(bars[16].isBusiest && bars[16].fraction == 1)
        #expect(bars.allSatisfy { $0.slot == .active ? $0.fraction > 0 : $0.fraction == 0 })
    }

    @Test("A month still running leaves the days to come as future, not as quiet")
    func runningMonthBars() {
        let recap = RecapSamples.month(isInProgress: true, throughDay: 12)
        let deck = Self.deck(recap)
        let bars = deck.scoreBars
        #expect(bars.count == 30)
        #expect(bars[11].slot != .future)
        #expect(bars[12...].allSatisfy { $0.slot == .future })
        #expect(deck.scoreAxis.map(\.label) == ["1", "10", "20", "30"])
    }

    @Test("A year has twelve bars, the months to come future, the busiest month ink")
    func yearBars() {
        let bars = Self.deck(RecapSamples.year()).scoreBars
        #expect(bars.count == 12)
        #expect(bars.filter(\.isBusiest).count == 1)
        // September is the sample's busiest month.
        #expect(bars[8].isBusiest)

        let running = Self.deck(RecapSamples.year(throughMonth: 7)).scoreBars
        #expect(running.prefix(7).allSatisfy { $0.slot == .active })
        #expect(running.dropFirst(7).allSatisfy { $0.slot == .future })
    }

    @Test("A running year's cost line stops at the last month it has had")
    func runningYearCostSeries() {
        #expect(Self.deck(RecapSamples.year(throughMonth: 7)).costSeries.count == 7)
        #expect(Self.deck(RecapSamples.year()).costSeries.count == 12)
    }

    @Test("No tokens in any slot, no strip")
    func emptyStrip() {
        #expect(Self.deck(RecapSamples.empty).scoreBars.isEmpty)
        #expect(Self.deck(RecapSamples.empty).scoreBusiestNote == nil)
    }

    @Test("Sessions per active day is rounded, and absent where it would be zero")
    func sessionsPerDay() {
        // 412 sessions over 27 days.
        #expect(Self.deck(RecapSamples.month()).sessionsPerActiveDay == 15)
        #expect(Self.deck(RecapSamples.empty).sessionsPerActiveDay == nil)
    }

    @Test("The change is on the same stretch of the period before, and absent without one")
    func sameSpanChange() throws {
        let change = try #require(Self.deck(RecapSamples.month()).sameSpanChange)
        #expect(change.arrow == "↑")
        #expect(change.percent == "38%")
        #expect(Self.deck(RecapSamples.empty).sameSpanChange == nil)
    }

    @Test("Tools: three as they are, more as two and the rest grouped")
    func agents() {
        // The sample has five: Claude Code, Codex, then three small ones.
        let agents = Self.deck(RecapSamples.month()).scoreAgents
        #expect(agents.count == 3)
        #expect(agents.map(\.tone) == [.lime, .ink, .grey])
        #expect(abs(agents.reduce(0) { $0 + $1.share } - 1) < 0.001)
        #expect(Self.deck(RecapSamples.month(hasAgents: false)).scoreAgents.isEmpty)
    }
}
