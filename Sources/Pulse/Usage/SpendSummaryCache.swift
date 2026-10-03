// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Window-owned derived figures. Computation runs off the main actor; only one
/// overview, one agent and one model are kept, without retaining source ledgers.
actor SpendSummaryCache {
    struct Window: Hashable, Sendable {
        let snapshot: UUID
        let days: Int?
        let today: Date
        let calendar: Calendar
        let language: String
    }

    struct Request: Hashable, Sendable {
        let window: Window
        let agent: SpendAgent?
        let model: String?

        /// Every result includes its parent summaries. Returning from a model
        /// can show that parent immediately, preserving the model-list scroll
        /// target. Other models, agents and windows must wait for their figures.
        func canDisplay(_ other: Request) -> Bool {
            agent == other.agent && (model == nil || model == other.model)
                && window.days == other.window.days && window.today == other.window.today
                && window.calendar == other.window.calendar
                && window.language == other.window.language
        }
    }

    struct Result: Sendable {
        let overview: SpendSummary
        let agent: SpendSummary
        let model: ModelSpendSummary
    }

    private var window: Window?
    private var overview = SpendSummary()
    private var agent: (key: SpendAgent, summary: SpendSummary)?
    private var model: (agent: SpendAgent?, name: String, summary: ModelSpendSummary)?

    func summaries(for request: Request, ledgers: [SpendAgent: UsageLedger]) throws -> Result {
        try Task.checkCancellation()
        let next = request.window
        if window != next {
            let summary = SpendSummary.of(ledgers, overLast: next.days, now: next.today, calendar: next.calendar)
            try Task.checkCancellation()
            overview = summary
            agent = nil
            model = nil
            window = next
        }
        let scoped = request.agent.map { selected in ledgers.filter { $0.key == selected } } ?? ledgers
        if let selected = request.agent, agent?.key != selected {
            let summary = SpendSummary.of(scoped, overLast: next.days, now: next.today, calendar: next.calendar)
            try Task.checkCancellation()
            agent = (selected, summary)
        }
        if let name = request.model, model?.name != name || model?.agent != request.agent {
            let summary = ModelSpendSummary.of(scoped, named: name, overLast: next.days, now: next.today, calendar: next.calendar)
            try Task.checkCancellation()
            model = (request.agent, name, summary)
        }
        return Result(
            overview: overview,
            agent: request.agent == nil ? SpendSummary() : agent?.summary ?? SpendSummary(),
            model: request.model == nil ? ModelSpendSummary() : model?.summary ?? ModelSpendSummary()
        )
    }
}
