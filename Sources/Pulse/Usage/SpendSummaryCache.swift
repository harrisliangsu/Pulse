// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Window-owned derived figures. Computation runs off the main actor; only one
/// overview, one agent and one model are kept, without retaining source ledgers.
actor SpendSummaryCache {
    struct Window: Hashable, Sendable {
        let snapshot: UUID
        /// The first local midnight counted, or nil for everything on record.
        let from: Date?
        /// The local midnight counting stops before, or nil for through today.
        let until: Date?
        let today: Date
        let calendar: Calendar
        let language: String

        init(snapshot: UUID, from: Date?, until: Date?, today: Date, calendar: Calendar, language: String) {
            self.snapshot = snapshot
            self.from = from
            self.until = until
            self.today = today
            self.calendar = calendar
            self.language = language
        }

        /// The last `days` calendar days through `today`, as
        /// `SpendSummary.of(_:overLast:)` counts them; nil is everything.
        init(snapshot: UUID, days: Int?, today: Date, calendar: Calendar, language: String) {
            let start = calendar.startOfDay(for: today)
            self.init(snapshot: snapshot,
                      from: days.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: start) },
                      until: nil, today: today, calendar: calendar, language: language)
        }
    }

    struct Request: Hashable, Sendable {
        let window: Window
        let agent: SpendAgent?
        let model: String?

        /// Whether `other`'s figures may stay on screen while this request's
        /// are added up.
        ///
        /// The same agent and model, over any span: a new span keeps the old
        /// figures for the milliseconds its own take, as it did when this was
        /// arithmetic on the main thread — a spinner there made a span change
        /// look like a rescan, and dropped the scroll position. Every result
        /// includes its parent summaries, so returning from a model shows that
        /// parent at once, keeping the model list's scroll target. A different
        /// agent or model waits: its screen is another screen, and the old
        /// figures would read as its own.
        func canKeepShowing(_ other: Request) -> Bool {
            agent == other.agent && (model == nil || model == other.model)
        }
    }

    /// What the year-long activity chart depends on. No span and no model: the
    /// chart always covers the last twelve months, so changing the picker
    /// leaves it alone.
    private struct ActivityKey: Hashable {
        let snapshot: UUID
        let today: Date
        let calendar: Calendar
        let agent: SpendAgent?
    }

    struct Result: Sendable {
        let overview: SpendSummary
        let agent: SpendSummary
        let model: ModelSpendSummary
        /// The twelve months to today, over everything and over `request.agent`.
        let activity: TokenActivity
    }

    private var window: Window?
    private var overview = SpendSummary()
    private var agent: (key: SpendAgent, summary: SpendSummary)?
    private var model: (agent: SpendAgent?, name: String, summary: ModelSpendSummary)?
    private var activity: (key: ActivityKey, value: TokenActivity)?

    func summaries(for request: Request, ledgers: [SpendAgent: UsageLedger]) throws -> Result {
        try Task.checkCancellation()
        let next = request.window
        if window != next {
            let summary = SpendSummary.of(ledgers, starting: next.from, before: next.until, now: next.today, calendar: next.calendar)
            try Task.checkCancellation()
            overview = summary
            agent = nil
            model = nil
            window = next
        }
        let scoped = request.agent.map { selected in ledgers.filter { $0.key == selected } } ?? ledgers
        if let selected = request.agent, agent?.key != selected {
            let summary = SpendSummary.of(scoped, starting: next.from, before: next.until, now: next.today, calendar: next.calendar)
            try Task.checkCancellation()
            agent = (selected, summary)
        }
        if let name = request.model, model?.name != name || model?.agent != request.agent {
            let summary = ModelSpendSummary.of(scoped, named: name, from: next.from, until: next.until, now: next.today, calendar: next.calendar)
            try Task.checkCancellation()
            model = (request.agent, name, summary)
        }
        let activityKey = ActivityKey(snapshot: next.snapshot, today: next.today, calendar: next.calendar, agent: request.agent)
        if activity?.key != activityKey {
            let series = TokenActivity.of(scoped, now: next.today, calendar: next.calendar)
            try Task.checkCancellation()
            activity = (activityKey, series)
        }
        return Result(
            overview: overview,
            agent: request.agent == nil ? SpendSummary() : agent?.summary ?? SpendSummary(),
            model: request.model == nil ? ModelSpendSummary() : model?.summary ?? ModelSpendSummary(),
            activity: activity?.value ?? TokenActivity()
        )
    }
}
