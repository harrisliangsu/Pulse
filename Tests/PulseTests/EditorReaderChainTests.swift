import Foundation
import Testing
@testable import Pulse

/// The production chain the readers feed: normalized records into
/// `AgentUsageLedger.build`, then `SpendSummary` and `ModelSpendSummary`. The
/// money, the session window and the treatment of unclassified and aggregate
/// work are all checked here, with fixed dates on a UTC calendar.
@Suite("Editor reader production chain")
struct EditorReaderChainTests {
    private static var calendar: Calendar { EditorTestSupport.calendar }
    private static let now = EditorTestSupport.now
    private static let namespace = SpendAgent.openCode.rawValue

    private static func at(daysAgo: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private static func record(
        _ model: String,
        _ tally: TokenTally,
        at date: Date,
        session: String? = nil,
        unclassified: Int = 0,
        aggregate: Bool = false
    ) -> AgentUsageRecord {
        AgentUsageRecord(
            timestamp: date,
            model: model,
            tally: tally,
            sessionID: session,
            unclassifiedTokens: unclassified,
            isAggregate: aggregate
        )
    }

    @Test("Classified records price through the shared path and window by their own buckets")
    func moneyAndWindow() throws {
        let records = [
            Self.record(
                "gpt-5",
                TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40),
                at: Self.at(daysAgo: 0, hour: 9), session: "s1"
            ),
            Self.record("gpt-5", TokenTally(input: 900), at: Self.at(daysAgo: 1, hour: 10), session: "s1"),
        ]
        let ledger = AgentUsageLedger.build(
            records, prices: EditorTestSupport.prices,
            namespace: Self.namespace, calendar: Self.calendar
        )

        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(summary.tokens == 1090)
        // 100*.001 + 20*.001 + 30*.0001 + 40*.01 + 900*.001 = 1.423
        #expect(abs(summary.cost - 1.423) < 1e-9)
        #expect(summary.tally == TokenTally(input: 1000, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(summary.sessions.count == 1)
        #expect(summary.sessions.first?.session.tokens == 1090)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "GPT-5", overLast: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(model.tokens == 1090)
        #expect(abs((model.cost ?? -1) - 1.423) < 1e-9)

        // A one-day window keeps today's record and the session's own in-window
        // half — the summary and the row agree.
        let today = SpendSummary.of(
            [.openCode: ledger], overLast: 1, now: Self.now, calendar: Self.calendar
        )
        #expect(today.tokens == 190)
        #expect(today.sessions.first?.session.tokens == 190)
    }

    @Test("A partial record marks the ledger and both summaries partial")
    func partialCountsPropagate() {
        var record = Self.record(
            "gpt-5", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9), session: "s1"
        )
        record.isPartial = true

        let ledger = AgentUsageLedger.build(
            [record], prices: EditorTestSupport.prices,
            namespace: Self.namespace, calendar: Self.calendar
        )
        #expect(ledger.hasPartialCounts)

        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(summary.hasPartialCounts)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "GPT-5", overLast: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(model.hasPartialCounts)
    }

    @Test("Unclassified work is counted but never priced, and aggregate work keeps no hours")
    func unclassifiedAndAggregate() throws {
        let records = [
            // A bare total on a priced model: tokens, no money.
            Self.record("gpt-5", TokenTally(), at: Self.at(daysAgo: 0, hour: 9),
                        session: "s3", unclassified: 500),
            // One session-level total: counted, unpriced, and no hour profile.
            Self.record("auto", TokenTally(), at: Self.at(daysAgo: 0, hour: 9),
                        session: "s4", unclassified: 1000, aggregate: true),
            // A real model Pulse has no price for is counted, never costed.
            Self.record("mystery", TokenTally(input: 10), at: Self.at(daysAgo: 0, hour: 9)),
        ]
        let ledger = AgentUsageLedger.build(
            records, prices: EditorTestSupport.prices,
            namespace: Self.namespace, calendar: Self.calendar
        )

        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 1510)
        #expect(ledger.days.reduce(0.0) { $0 + $1.cost } == 0)
        #expect(ledger.hasAggregateTiming)

        let eventSession = try #require(ledger.sessions.first { $0.id == "\(Self.namespace)#s3" })
        #expect(eventSession.tokens == 500)
        // A dated event still carries its own unclassified tokens in a slot.
        #expect(eventSession.slots.reduce(0) { $0 + $1.tokens } == 500)

        let aggregateSession = try #require(ledger.sessions.first { $0.id == "\(Self.namespace)#s4" })
        #expect(aggregateSession.tokens == 1000)
        #expect(aggregateSession.slots.isEmpty)

        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(summary.tokens == 1510)
        #expect(summary.cost == 0)
        // The 1500 unclassified tokens and the 10 unpriced ones are counted as
        // unpriced tokens, never as a kind and never as money.
        #expect(summary.unpricedTokens == 1510)
    }
}
