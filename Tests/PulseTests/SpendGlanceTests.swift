// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation
import Testing
@testable import Pulse

/// The floating Token spend summary: its two-week chart, the money it may
/// say, where the window sits, and that a cancelled read cannot publish.
/// Synthetic ledgers only.
@Suite("Token spend glance")
struct SpendGlanceTests {
    private static let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))

    private static func day(_ daysAgo: Int, tokens: Int, cost: Double = 1) -> LedgerDay {
        LedgerDay(
            date: calendar.date(byAdding: .day, value: -daysAgo, to: today)!,
            tokens: tokens,
            cost: cost,
            unpricedTokens: 0,
            models: tokens > 0 ? ["m": tokens] : [:]
        )
    }

    private static func ledger(
        _ days: [LedgerDay],
        origin: UsageLedger.Origin = .localTranscripts,
        partial: Bool = false
    ) -> UsageLedger {
        var ledger = UsageLedger(
            origin: origin,
            days: days,
            earliest: days.first?.date,
            unpricedModels: [],
            modelNames: [:],
            slots: []
        )
        ledger.hasPartialCounts = partial
        return ledger
    }

    private func request(enabled: Bool = true, open: Bool = true, rescan: Int = 0) -> SpendGlanceRead.Request {
        .init(isEnabled: enabled, isOpen: open, rescan: rescan)
    }

    private func scan(_ action: SpendGlanceRead.Action) throws -> (id: UUID, refresh: Bool) {
        let read: (UUID, Bool)? = if case .scan(let id, let refresh) = action { (id, refresh) } else { nil }
        return try #require(read)
    }

    @Test("Opening asks for a cache-backed read, and a second look reuses it")
    func openingDoesNotForceARescan() throws {
        var state = SpendGlanceRead()
        let first = try scan(state.prepare(request()))
        #expect(!first.refresh)
        state.complete(.init(ledgers: [.codex: Self.ledger([Self.day(0, tokens: 40)])], notes: [.codex: ["unreadable"]]), for: first.id)
        state.finish(first.id)
        #expect(state.prepare(request()) == .retain)
        #expect(state.snapshot?.ledgers[.codex]?.allTime.tokens == 40)
        #expect(state.snapshot?.notes[.codex] == ["unreadable"])
    }

    @Test("Closing or switching reading off releases the snapshot", arguments: [false, true])
    func inactiveReleases(disable: Bool) {
        var state = SpendGlanceRead()
        _ = state.prepare(request())
        let action = state.prepare(request(enabled: !disable, open: disable))
        #expect(action == .release)
        #expect(state.snapshot == nil)
        #expect(state.snapshotID == nil)
    }

    @Test("Refresh is the only forced read, and a late result cannot land")
    func refreshAndStaleResult() throws {
        var state = SpendGlanceRead()
        let first = try scan(state.prepare(request()))
        state.complete(.init(), for: first.id)
        state.finish(first.id)

        let rescan = try scan(state.prepare(request(rescan: 1)))
        #expect(rescan.refresh)
        #expect(state.snapshot == nil)
        #expect(!state.complete(.init(ledgers: [.codex: Self.ledger([Self.day(0, tokens: 1)])]), for: first.id))
        #expect(state.snapshot == nil)
        #expect(!state.finish(first.id))

        state.complete(.init(ledgers: [.claudeCode: Self.ledger([Self.day(0, tokens: 8)])]), for: rescan.id)
        #expect(state.finish(rescan.id))
        #expect(state.prepare(request(rescan: 1)) == .retain)
        #expect(state.snapshot?.ledgers[.claudeCode]?.allTime.tokens == 8)

        let dropped = try scan(state.prepare(request(rescan: 2)))
        state.finish(dropped.id)
        let retry = try scan(state.prepare(request(rescan: 2)))
        #expect(!retry.refresh)
    }

    @Test("The mini chart is the last 14 midnights, with gaps before the first record")
    func activityWindow() {
        let activity = SpendGlanceActivity.of(
            [
                .codex: Self.ledger([Self.day(2, tokens: 10), Self.day(0, tokens: 4)]),
                .claudeCode: Self.ledger([Self.day(0, tokens: 6)]),
            ],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(activity.days.count == SpendGlance.activityDays)
        #expect(activity.days.allSatisfy { $0.date == Self.calendar.startOfDay(for: $0.date) })
        #expect(activity.days.first?.date == Self.calendar.date(byAdding: .day, value: -13, to: Self.today))
        #expect(activity.days.last?.date == Self.today)
        #expect(activity.days.last?.tokens == 10)
        let nils = activity.days.filter { $0.tokens == nil }
        #expect(nils.count == 11)
        let quiet = activity.days.filter { $0.tokens == 0 }
        #expect(quiet.count == 1)
        #expect(!activity.hasPartialCounts)
        #expect(activity.days.contains { $0.date == Self.calendar.date(byAdding: .day, value: -20, to: Self.today)! } == false)
    }

    @Test("A day before any record is not drawn as zero, and statistics are left out")
    func activityWithholds() {
        let onlyZero = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(0, tokens: 0)])],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(onlyZero.isEmpty)

        let statistics = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(0, tokens: 80)], origin: .providerStatistics)],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(statistics.isEmpty)

        let oldPartial = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(30, tokens: 12)], partial: true)],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(!oldPartial.isEmpty)
        #expect(oldPartial.days.allSatisfy { $0.tokens == 0 })
        #expect(!oldPartial.hasPartialCounts)

        let recentPartial = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(1, tokens: 12)], partial: true)],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(recentPartial.hasPartialCounts)
    }

    @Test("Money follows the Settings total: unavailable, partial, or a real zero")
    func estimate() {
        var empty = SpendSummary()
        #expect(SpendGlance.Estimate.of(empty) == .none)

        var unpriced = SpendSummary()
        unpriced.tokens = 20
        unpriced.unpricedTokens = 20
        unpriced.cost = 0
        #expect(SpendGlance.Estimate.of(unpriced) == .unavailable)

        var partial = SpendSummary()
        partial.tokens = 20
        partial.unpricedTokens = 5
        partial.cost = 1.5
        #expect(SpendGlance.Estimate.of(partial) == .amount(1.5, partial: true))

        var incomplete = SpendSummary()
        incomplete.tokens = 20
        incomplete.cost = 2
        incomplete.hasPartialCounts = true
        #expect(SpendGlance.Estimate.of(incomplete) == .amount(2, partial: true))

        var free = SpendSummary()
        free.tokens = 20
        free.cost = 0
        #expect(SpendGlance.Estimate.of(free) == .amount(0, partial: false))
    }

    @Test("Agents are heaviest first, ties by name, and the list stops at eight")
    func topAgents() {
        var summary = SpendSummary()
        summary.agents = [
            .init(agent: .codex, tokens: 5, cost: 1, unpricedTokens: 0),
            .init(agent: .claudeCode, tokens: 5, cost: 1, unpricedTokens: 5),
            .init(agent: .grok, tokens: 9, cost: 3, unpricedTokens: 1),
            .init(agent: .kimiCLI, tokens: 0, cost: 0, unpricedTokens: 0),
        ]
        let rows = SpendGlance.topAgents(summary)
        #expect(rows.map(\.name) == ["Grok Build", "Claude Code", "Codex"])
        #expect(rows[0].share == 1)
        #expect(rows[0].cost == 3)
        #expect(rows[1].cost == nil)
        #expect(rows[2].share == 5.0 / 9.0)

        let agents = Array(SpendAgent.allCases.prefix(9))
        summary.agents = agents.enumerated().map { index, agent in
            .init(agent: agent, tokens: 100 - index, cost: 1, unpricedTokens: 0)
        }
        let capped = SpendGlance.topAgents(summary)
        #expect(capped.count == SpendGlance.agentLimit)
        #expect(capped.first?.tokens == 100)
        #expect(capped.last?.tokens == 93)
    }

    @Test("A right-hand rail keeps the window on the card's side, inside the screen")
    func placement() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rail = CGRect(x: 1360, y: 200, width: 64, height: 420)
        let frame = SpendGlancePlacement.frame(rail: rail, edge: .right, screen: screen, cardClearance: 270)
        #expect(frame.maxX <= rail.minX - 270)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))

        let cramped = CGRect(x: 20, y: 200, width: 64, height: 420)
        let flipped = SpendGlancePlacement.frame(rail: cramped, edge: .right, screen: screen, cardClearance: 400)
        #expect(flipped.minX >= cramped.maxX)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(flipped))
    }

    @Test("The share image's text is the summary, not a path or an address")
    func shareOmitsPrivateText() throws {
        var ledger = Self.ledger([Self.day(0, tokens: 30, cost: 2)])
        ledger.sessions = [
            UsageLedger.Session(
                id: "/Users/ada/Library/secret.jsonl",
                name: "rollout-secret",
                title: "ada@example.com",
                project: nil,
                start: Self.today,
                end: Self.today,
                tokens: 30,
                cost: 2
            )
        ]
        let summary = SpendSummary.of([.codex: ledger], overLast: nil, now: Self.today, calendar: Self.calendar)
        #expect(summary.sessions.contains { $0.session.id.contains("/Users/ada") })
        let activity = SpendGlanceActivity.of([.codex: ledger], now: Self.today, calendar: Self.calendar)
        let picture = SpendGlancePicture.make(
            span: .week,
            custom: Self.today...Self.today,
            summary: summary,
            activity: activity,
            observedAt: nil,
            hasReadLimitations: false,
            now: Self.today,
            calendar: Self.calendar
        )
        let drawn = picture.drawnText.joined(separator: "\n")
        #expect(!drawn.contains("/Users"))
        #expect(!drawn.contains("secret.jsonl"))
        #expect(!drawn.contains("@"))
        #expect(!drawn.contains("rollout-secret"))
        #expect(picture.agents.map(\.name) == ["Codex"])
        #expect(picture.bars.count == SpendGlance.activityDays)
        #expect(picture.brand == "Blinky")
        #expect(picture.span == SpendSpan.week.title)
    }
}
