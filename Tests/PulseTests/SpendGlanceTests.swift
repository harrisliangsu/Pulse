// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation
import Testing
@testable import Pulse

/// The floating Token spend summary: its two-week chart, the money it may
/// say, where the window sits, and that a cancelled read cannot publish.
/// Synthetic ledgers only.
///
/// Sentence assertions name the English table. `String.localized` follows
/// the process language, which another suite changes while these run.
@Suite("Token spend glance")
struct SpendGlanceTests {
    private static let english = LocalizationSource.bundle(for: .english)
    private static let englishLocale = Locale(identifier: "en_US")
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
        // The expectation macro cannot call a mutating method, so the result is taken first.
        let staleComplete = state.complete(
            .init(ledgers: [.codex: Self.ledger([Self.day(0, tokens: 1)])]),
            for: first.id
        )
        #expect(!staleComplete)
        #expect(state.snapshot == nil)
        let staleFinish = state.finish(first.id)
        #expect(!staleFinish)

        state.complete(.init(ledgers: [.claudeCode: Self.ledger([Self.day(0, tokens: 8)])]), for: rescan.id)
        let finished = state.finish(rescan.id)
        #expect(finished)
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
        let empty = SpendSummary()
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
        let picture = Self.picture(summary: summary, activity: activity)
        let drawn = picture.drawnText.joined(separator: "\n")
        #expect(!drawn.contains("/Users"))
        #expect(!drawn.contains("secret.jsonl"))
        #expect(!drawn.contains("@"))
        #expect(!drawn.contains("rollout-secret"))
        #expect(picture.agents.map(\.name) == ["Codex"])
        #expect(picture.bars.count == SpendGlance.activityDays)
        #expect(picture.brand == "Blinky")
        #expect(picture.span == "Last 7 days")
    }

    @Test("The poster always names Blinky, and leaves out an empty agents list and an empty chart")
    func posterOmitsEmptySections() {
        let empty = Self.picture()
        #expect(empty.brand == "Blinky")
        #expect(empty.drawnText.first == "Blinky")
        #expect(empty.drawnText.last == "Blinky")
        #expect(empty.span == "Last 7 days")
        #expect(empty.tokens == "Nothing in this span")
        #expect(empty.cost == nil)
        #expect(empty.costNote == nil)
        #expect(empty.agents.isEmpty)
        #expect(empty.agentsTitle.isEmpty)
        #expect(empty.bars.isEmpty)
        #expect(empty.activityTitle.isEmpty)
        #expect(empty.footnotes.isEmpty)
        #expect(!empty.drawnText.contains("By agent"))
        #expect(!empty.drawnText.contains("Last 14 days"))

        var priced = SpendSummary()
        priced.tokens = 8
        priced.cost = 1
        let noAgents = Self.picture(summary: priced)
        #expect(noAgents.brand == "Blinky")
        #expect(noAgents.tokens == "8 tokens")
        #expect(noAgents.cost == SpendFormat.money(1, locale: Self.englishLocale) as String?)
        #expect(noAgents.costNote == nil)
        #expect(noAgents.agents.isEmpty)
        #expect(!noAgents.drawnText.contains("By agent"))
    }

    @Test("A priced poster shows the span, the tokens, the cost, the agents, and fourteen bars")
    func posterShowsThePricedSummary() {
        let ledger = Self.ledger([Self.day(2, tokens: 10, cost: 1), Self.day(0, tokens: 30, cost: 2)])
        let summary = SpendSummary.of([.codex: ledger], overLast: nil, now: Self.today, calendar: Self.calendar)
        let activity = SpendGlanceActivity.of([.codex: ledger], now: Self.today, calendar: Self.calendar)
        let picture = Self.picture(summary: summary, activity: activity)
        #expect(summary.tokens == 40)
        #expect(picture.brand == "Blinky")
        #expect(picture.span == "Last 7 days")
        #expect(picture.tokens == "40 tokens")
        #expect(picture.cost == SpendFormat.money(summary.cost, locale: Self.englishLocale) as String?)
        #expect(picture.costNote == nil)
        #expect(picture.agentsTitle == "By agent")
        #expect(picture.agents.map(\.name) == ["Codex"])
        #expect(picture.agents.first?.tokens == "40")
        #expect(picture.agents.first?.cost == SpendFormat.money(summary.cost, locale: Self.englishLocale) as String?)
        #expect(picture.bars.contains { $0.tokens == nil })
        #expect(picture.activityTitle == "Last 14 days")
        #expect(picture.bars.count == SpendGlance.activityDays)
        #expect(picture.bars.map(\.tokens) == activity.days.map(\.tokens))
        #expect(picture.bars.map(\.share).max() == 1 as Double?)
        #expect(picture.bars.filter { $0.tokens == nil }.allSatisfy { $0.share == 0 })
        #expect(picture.drawnText.contains("By agent"))
        #expect(picture.drawnText.contains("Last 14 days"))
        #expect(picture.drawnText.first == "Blinky")
        #expect(picture.drawnText.last == "Blinky")
    }

    @Test("The poster says when a cost is unavailable or only partial")
    func posterNotesTheEstimate() {
        var unavailable = SpendSummary()
        unavailable.tokens = 20
        unavailable.unpricedTokens = 20
        unavailable.cost = 0
        unavailable.agents = [.init(agent: .codex, tokens: 20, cost: 0, unpricedTokens: 20)]
        let missing = Self.picture(summary: unavailable)
        #expect(missing.brand == "Blinky")
        #expect(missing.span == "Last 7 days")
        #expect(missing.tokens == "20 tokens")
        #expect(missing.cost == nil)
        #expect(missing.costNote == "Estimate unavailable")
        #expect(missing.agentsTitle == "By agent")
        #expect(missing.agents.map(\.name) == ["Codex"])
        #expect(missing.agents.first?.cost == nil)

        var partial = SpendSummary()
        partial.tokens = 20
        partial.unpricedTokens = 5
        partial.cost = 1.5
        partial.agents = [.init(agent: .codex, tokens: 20, cost: 1.5, unpricedTokens: 5)]
        let mixed = Self.picture(summary: partial)
        let money = SpendFormat.money(1.5, locale: Self.englishLocale)
        #expect(mixed.cost == money as String?)
        #expect(mixed.costNote == "Partial estimate")
        #expect(mixed.agents.first?.cost == "\(money)*" as String?)
        #expect(mixed.brand == "Blinky")
    }

    @Test("The poster footnotes a partial count and a record it could not read")
    func posterFootnotesLimits() {
        let activity = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(1, tokens: 12)], partial: true)],
            now: Self.today,
            calendar: Self.calendar
        )
        var summary = SpendSummary()
        summary.tokens = 12
        summary.cost = 1
        let partialChart = Self.picture(summary: summary, activity: activity)
        #expect(partialChart.bars.count == SpendGlance.activityDays)
        #expect(partialChart.activityTitle == "Last 14 days")
        #expect(partialChart.costNote == nil)
        #expect(partialChart.footnotes == ["Counts may be incomplete."])
        #expect(partialChart.brand == "Blinky")

        var incomplete = summary
        incomplete.hasPartialCounts = true
        let both = Self.picture(
            summary: incomplete,
            activity: activity,
            observedAt: Self.today,
            limitations: true
        )
        #expect(both.costNote == "Partial estimate")
        #expect(both.footnotes == [
            "Updated just now",
            "Counts may be incomplete.",
            "Some compressed records could not be read.",
        ])
        #expect(both.drawnText.first == "Blinky")
        #expect(both.drawnText.last == "Blinky")
    }

    @Test("The chart button exists only while reading is on, and off cannot open the summary")
    @MainActor
    func entryStaysClosedWhileReadingIsOff() async throws {
        #expect(SpendGlance.showsEntry(reading: true, canOpen: true))
        #expect(!SpendGlance.showsEntry(reading: false, canOpen: true))
        #expect(!SpendGlance.showsEntry(reading: true, canOpen: false))
        #expect(!SpendGlance.showsEntry(reading: false, canOpen: false))

        let name = "pulse-spend-glance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(readsTokenSpend: false, defaults: defaults)
        let model = SpendGlanceModel(settings: settings)
        model.isOpen = true
        #expect(!model.loadKey.isEnabled)
        #expect(model.summaryRequest == nil)
        await model.load()
        #expect(model.read.snapshot == nil)
        #expect(!model.figuresReady)

        settings.readsTokenSpend = true
        model.isOpen = false
        #expect(model.loadKey.isEnabled)
        #expect(model.summaryRequest == nil)
        await model.load()
        #expect(model.read.snapshot == nil)
        #expect(!model.figuresReady)

        settings.readsTokenSpend = false
        let controller = SpendGlanceController(settings: settings)
        controller.toggle()
        controller.show()
        #expect(!controller.isOpen)
    }

    private static func picture(
        summary: SpendSummary = SpendSummary(),
        activity: SpendGlanceActivity = SpendGlanceActivity(),
        observedAt: Date? = nil,
        limitations: Bool = false
    ) -> SpendGlancePicture {
        SpendGlancePicture.make(
            span: .week,
            custom: today...today,
            summary: summary,
            activity: activity,
            observedAt: observedAt,
            hasReadLimitations: limitations,
            now: today,
            calendar: calendar,
            locale: englishLocale,
            bundle: english
        )
    }
}
