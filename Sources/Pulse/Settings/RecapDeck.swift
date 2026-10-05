// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One card of a recap. Each is 1080 × 1920, drawn by `RecapCardView`.
enum RecapCard: String, Hashable, CaseIterable, Sendable {
    /// The dense one-page summary. Stands alone, so it is not numbered.
    case poster
    /// The month number or the year, and the agents that did the work.
    case opener
    /// A month: every day of it, one cell each.
    case calendar
    /// A year: every month of it as a small calendar.
    case yearCalendar
    /// A year: one bar per month.
    case months
    /// Peak hour, and the 24 hours as rows.
    case timetable
    /// What the period cost at API prices against the subscription price.
    case payback
    /// The closing scorecard.
    case scorecard
}

/// Cost against what the reader pays: the figure on the payback card, the
/// poster's lime tile and the scorecard.
struct RecapPayback: Equatable, Sendable {
    /// What the period's work would have cost at API prices.
    let used: Double
    /// The monthly price the reader typed, times the months the period spans.
    let paid: Double
    /// Months of subscription the period covers: 1 for a month recap.
    let months: Int

    /// `used / paid`, under 1 when the subscription cost more than the work did.
    var multiple: Double { used / paid }
}

/// The cards a `Recap` gets, in order, and the facts they share.
///
/// **A card whose data is missing is left out, never drawn empty or with a
/// zero.** No agents, no opener; no hour shape (`Recap.hours` is nil where a
/// store only has session-level timing), no timetable; no cost or no price, no
/// payback. An empty recap gets no deck at all. The page counter ("01 / 05")
/// counts the numbered cards the deck really has.
struct RecapDeck: Sendable {
    let recap: Recap
    /// What the reader pays a month, in `recap.currency`. Nil when they have
    /// not typed one.
    let monthlyPrice: Double?
    /// Replaces project names with "Project 1", "Project 2"… for a card that
    /// is about to be shared.
    let hidesProjects: Bool
    let payback: RecapPayback?
    let cards: [RecapCard]

    init(recap: Recap, monthlyPrice: Double?, hidesProjects: Bool) {
        self.recap = recap
        self.monthlyPrice = monthlyPrice
        self.hidesProjects = hidesProjects
        let payback = Self.payback(recap: recap, monthlyPrice: monthlyPrice)
        self.payback = payback
        self.cards = Self.cards(recap: recap, hasPayback: payback != nil)
    }

    /// Whether the recap is a year's.
    var isYear: Bool {
        if case .year = recap.period { return true }
        return false
    }

    /// The numbered cards: everything but the poster.
    var stories: [RecapCard] { cards.filter { $0 != .poster } }

    /// "01 / 05" for a numbered card; nil for the poster and for a card the
    /// deck does not hold.
    func page(of card: RecapCard) -> (number: Int, count: Int)? {
        guard let index = stories.firstIndex(of: card) else { return nil }
        return (index + 1, stories.count)
    }

    /// The label for one project, which is "Project 2" when names are hidden.
    func projectName(_ index: Int, _ project: Recap.ProjectShare) -> String {
        hidesProjects ? String.localized("Project \("\(index + 1)")") : project.name
    }

    // MARK: - Rules

    private static func cards(recap: Recap, hasPayback: Bool) -> [RecapCard] {
        guard !recap.isEmpty else { return [] }
        var cards: [RecapCard] = [.poster]
        if !recap.agents.isEmpty { cards.append(.opener) }

        switch recap.period {
        case .month:
            if recap.days.contains(where: { $0.tokens > 0 }) { cards.append(.calendar) }
        case .year:
            if recap.days.contains(where: { $0.tokens > 0 }) { cards.append(.yearCalendar) }
            if recap.months.count == 12, recap.months.contains(where: { $0.tokens > 0 }) { cards.append(.months) }
        }

        if let hours = recap.hours, hours.count == 24, recap.peakHour != nil, hours.contains(where: { $0 > 0 }) {
            cards.append(.timetable)
        }
        if hasPayback { cards.append(.payback) }
        cards.append(.scorecard)
        return cards
    }

    /// Needs a priced period and a price. A price of nothing is not a
    /// subscription, and a period priced at nothing has no payback to state.
    static func payback(recap: Recap, monthlyPrice: Double?) -> RecapPayback? {
        guard let cost = recap.cost, cost > 0, let price = monthlyPrice, price > 0 else { return nil }
        let months = paidMonths(recap)
        return RecapPayback(used: cost, paid: price * Double(months), months: months)
    }

    /// Months of subscription the period spans. A month is one; a year is
    /// twelve, or as many as have started when it is still running.
    static func paidMonths(_ recap: Recap) -> Int {
        guard case .year = recap.period else { return 1 }
        guard recap.isInProgress else { return 12 }
        let lastDay = recap.end.addingTimeInterval(-1)
        return max(1, Calendar.current.component(.month, from: lastDay))
    }
}
