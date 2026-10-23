// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation

/// The floating summary beside the usage panel.
///
/// Arithmetic over a snapshot the pane already holds. Nothing here opens a
/// store: the window asks `AgentLedgers` for the scan it kept, and only
/// Refresh reads again.
enum SpendGlance {
    /// How many agents the summary lists. The rest stay on the Settings page.
    static let agentLimit = 8
    /// The mini chart's length. The year-long Token activity chart stays in Settings.
    static let activityDays = 14

    /// The chart button on the usage card. Reading has to be on, and something
    /// has to be able to open the window. Otherwise there is no button, and
    /// the controller refuses to open one.
    static func showsEntry(reading: Bool, canOpen: Bool) -> Bool {
        reading && canOpen
    }

    /// What the headline may say about money. The same three answers as the
    /// Settings total: no figure when every token is unpriced, a marked
    /// partial when some are, and a real zero when a published rate is zero.
    enum Estimate: Equatable, Sendable {
        case none
        case unavailable
        case amount(Double, partial: Bool)

        static func of(_ summary: SpendSummary) -> Self {
            guard summary.tokens > 0 || summary.cost > 0 else { return .none }
            if summary.tokens > 0, summary.unpricedTokens == summary.tokens { return .unavailable }
            let partial = summary.unpricedTokens > 0 || summary.hasPartialCounts
            return .amount(summary.cost, partial: partial)
        }
    }

    struct AgentRow: Equatable, Sendable {
        let name: String
        let tokens: Int
        /// Nil when none of this agent's tokens had a price. A published zero stays zero.
        let cost: Double?
        let unpricedTokens: Int
        /// Share of the heaviest row, so the longest bar is the first.
        let share: Double
    }

    /// Heaviest first, ties by name, capped at `limit`. An agent with no tokens
    /// in the span is not a row.
    static func topAgents(_ summary: SpendSummary, limit: Int = agentLimit) -> [AgentRow] {
        let ranked = summary.agents
            .filter { $0.tokens > 0 }
            .sorted { lhs, rhs in
                if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
                return lhs.agent.displayName < rhs.agent.displayName
            }
        let heaviest = ranked.first?.tokens ?? 0
        return ranked.prefix(limit).map { agent in
            AgentRow(
                name: agent.agent.displayName,
                tokens: agent.tokens,
                cost: UsageLedger.shownCost(agent.cost, tokens: agent.tokens, unpriced: agent.unpricedTokens),
                unpricedTokens: agent.unpricedTokens,
                share: heaviest > 0 ? Double(agent.tokens) / Double(heaviest) : 0
            )
        }
    }

    /// The label in the header. A custom range names its days, because this
    /// window has no date fields under the menu the way Settings does.
    static func spanTitle(
        _ span: SpendSpan,
        custom: ClosedRange<Date>,
        calendar: Calendar = .current,
        locale: Locale = LocalizationSource.locale,
        bundle: Bundle = LocalizationSource.bundle
    ) -> String {
        guard span == .custom else { return span.title(in: bundle) }
        let style = Date.FormatStyle().month(.abbreviated).day().year().locale(locale)
        let first = calendar.startOfDay(for: custom.lowerBound)
        let last = calendar.startOfDay(for: custom.upperBound)
        let start = first.formatted(style)
        if calendar.isDate(first, inSameDayAs: last) { return start }
        return String(localized: "\(start) - \(last.formatted(style))", bundle: bundle)
    }
}

/// The last two weeks, one figure per calendar day.
///
/// Independent of the span picker, the way Token activity is: the headline
/// follows Settings, and this chart is the recent shape beside it. A day
/// before the first record is `nil` — not a zero — and a day after that
/// record with no tokens is a real zero. A provider's own statistics are
/// left out, the same gate as every Token spend total.
struct SpendGlanceActivity: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        let date: Date
        /// Nil before the first record. A measured quiet day is zero.
        let tokens: Int?
    }

    var days: [Day] = []
    var hasPartialCounts = false

    var isEmpty: Bool { days.isEmpty }

    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(SpendGlance.activityDays - 1), to: today) else {
            return Self()
        }
        let windowStart = calendar.startOfDay(for: start)

        var tokensByDay: [Date: Int] = [:]
        var partial = false
        var first: Date?
        for ledger in ledgers.values {
            guard ledger.origin.supportsTokenSpend else { continue }
            var contributes = false
            for day in ledger.days where day.tokens > 0 {
                let date = calendar.startOfDay(for: day.date)
                first = min(first ?? date, date)
                guard date >= windowStart, date <= today else { continue }
                tokensByDay[date, default: 0] += day.tokens
                contributes = true
            }
            if contributes, ledger.hasPartialCounts { partial = true }
        }
        guard let first, first <= today else { return Self() }

        var days: [Day] = []
        var cursor = windowStart
        for _ in 0..<SpendGlance.activityDays {
            let date = calendar.startOfDay(for: cursor)
            guard date <= today else { break }
            if date >= calendar.startOfDay(for: first) {
                days.append(Day(date: date, tokens: tokensByDay[date] ?? 0))
            } else {
                days.append(Day(date: date, tokens: nil))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            cursor = next
        }
        return Self(days: days, hasPartialCounts: partial)
    }
}

/// Where the summary window sits: on the side the provider card opens, clear
/// of that card, and inside the screen.
enum SpendGlancePlacement {
    static let gap: CGFloat = 12
    static let size = CGSize(width: 360, height: 560)

    static func frame(
        rail: CGRect,
        edge: PanelEdge,
        screen: CGRect,
        size: CGSize = size,
        cardClearance: CGFloat
    ) -> CGRect {
        let room = screen.insetBy(dx: 8, dy: 8)
        let preferred = beside(rail: rail, edge: edge, size: size, clearance: cardClearance)
        if room.contains(preferred) { return preferred }
        let flipped = beside(rail: rail, edge: edge.opposite, size: size, clearance: gap)
        if room.contains(flipped) { return flipped }
        return clamp(preferred, to: room)
    }

    /// The card opens away from the edge the rail's back faces.
    private static func beside(rail: CGRect, edge: PanelEdge, size: CGSize, clearance: CGFloat) -> CGRect {
        switch edge {
        case .left:
            return CGRect(
                x: rail.maxX + clearance,
                y: rail.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .right:
            return CGRect(
                x: rail.minX - clearance - size.width,
                y: rail.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .top:
            return CGRect(
                x: rail.midX - size.width / 2,
                y: rail.minY - clearance - size.height,
                width: size.width,
                height: size.height
            )
        case .bottom:
            return CGRect(
                x: rail.midX - size.width / 2,
                y: rail.maxY + clearance,
                width: size.width,
                height: size.height
            )
        }
    }

    private static func clamp(_ frame: CGRect, to room: CGRect) -> CGRect {
        var frame = frame
        frame.size.width = min(frame.width, room.width)
        frame.size.height = min(frame.height, room.height)
        if frame.maxX > room.maxX { frame.origin.x = room.maxX - frame.width }
        if frame.minX < room.minX { frame.origin.x = room.minX }
        if frame.maxY > room.maxY { frame.origin.y = room.maxY - frame.height }
        if frame.minY < room.minY { frame.origin.y = room.minY }
        return frame
    }
}

private extension PanelEdge {
    /// The side with the screen behind the rail.
    var opposite: PanelEdge {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }
}

/// Whether this window reads, reuses, or lets a snapshot go.
///
/// The same fences as `SpendReadState`: one read id, a cancelled predecessor
/// cannot publish, and Refresh is the only pass that bypasses the agent caches.
struct SpendGlanceRead {
    struct Request: Hashable {
        let isEnabled: Bool
        let isOpen: Bool
        let rescan: Int
    }

    enum Action: Equatable {
        case retain
        case release
        case scan(id: UUID, refresh: Bool)
    }

    private(set) var snapshot: AgentLedgers.Snapshot?
    private(set) var snapshotID: UUID?
    private var readID: UUID?
    private var consumedRescan = 0

    mutating func prepare(_ request: Request) -> Action {
        readID = nil
        guard request.isEnabled, request.isOpen else {
            snapshot = nil
            snapshotID = nil
            return .release
        }
        let refresh = request.rescan != consumedRescan
        guard snapshot == nil || refresh else { return .retain }
        snapshot = nil
        snapshotID = nil
        consumedRescan = request.rescan
        let id = UUID()
        readID = id
        return .scan(id: id, refresh: refresh)
    }

    func isCurrent(_ id: UUID) -> Bool { readID == id }

    @discardableResult
    mutating func complete(_ snapshot: AgentLedgers.Snapshot, for id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        self.snapshot = snapshot
        snapshotID = UUID()
        return true
    }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        readID = nil
        return true
    }
}

/// The strings the share image draws. Built from the summary on screen, so a
/// path or an address would have to be put here on purpose — the session list
/// is not one of these fields.
struct SpendGlancePicture: Equatable, Sendable {
    struct Agent: Equatable, Sendable {
        var name: String
        var tokens: String
        var cost: String?
        var share: Double
    }

    struct Bar: Equatable, Sendable {
        /// Nil draws a gap. Zero draws the quiet mark.
        var tokens: Int?
        var share: Double
    }

    var brand = "Blinky"
    var span = ""
    var tokens = ""
    var cost: String?
    var costNote: String?
    var agentsTitle = ""
    var agents: [Agent] = []
    var activityTitle = ""
    var bars: [Bar] = []
    var footnotes: [String] = []

    /// Every piece of text the image paints, in the order the poster reads them.
    var drawnText: [String] {
        var lines = [brand, span, tokens]
        if let cost { lines.append(cost) }
        if let costNote { lines.append(costNote) }
        if !agents.isEmpty { lines.append(agentsTitle) }
        for agent in agents {
            lines.append(agent.name)
            lines.append(agent.tokens)
            if let cost = agent.cost { lines.append(cost) }
        }
        if !bars.isEmpty { lines.append(activityTitle) }
        lines.append(contentsOf: footnotes)
        lines.append(brand)
        return lines
    }

    static func make(
        span: SpendSpan,
        custom: ClosedRange<Date>,
        summary: SpendSummary,
        activity: SpendGlanceActivity,
        observedAt: Date?,
        hasReadLimitations: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = LocalizationSource.locale,
        bundle: Bundle = LocalizationSource.bundle
    ) -> Self {
        let units = LocalizationSource.myriadUnits(for: locale)
        var picture = Self()
        picture.span = SpendGlance.spanTitle(
            span, custom: custom, calendar: calendar, locale: locale, bundle: bundle
        )
        picture.tokens = String(
            localized: "\(TokenCount.short(summary.tokens, units: units)) tokens",
            bundle: bundle
        )
        switch SpendGlance.Estimate.of(summary) {
        case .none:
            if summary.tokens == 0 {
                picture.tokens = String(localized: "Nothing in this span", bundle: bundle)
            }
        case .unavailable:
            picture.costNote = String(localized: "Estimate unavailable", bundle: bundle)
        case .amount(let amount, let partial):
            picture.cost = SpendFormat.money(amount, locale: locale)
            if partial { picture.costNote = String(localized: "Partial estimate", bundle: bundle) }
        }
        let rows = SpendGlance.topAgents(summary)
        if !rows.isEmpty {
            picture.agentsTitle = String(localized: "By agent", bundle: bundle)
            picture.agents = rows.map { row in
                Agent(
                    name: row.name,
                    tokens: TokenCount.short(row.tokens, units: units),
                    cost: row.cost.map { cost in
                        let money = SpendFormat.money(cost, locale: locale)
                        return row.unpricedTokens > 0 ? "\(money)*" : money
                    },
                    share: row.share
                )
            }
        }
        if !activity.isEmpty {
            picture.activityTitle = String(
                localized: "Last \("\(SpendGlance.activityDays)") days",
                bundle: bundle
            )
            let busiest = activity.days.compactMap(\.tokens).max() ?? 0
            picture.bars = activity.days.map { day in
                Bar(
                    tokens: day.tokens,
                    share: day.tokens.map { busiest > 0 ? Double($0) / Double(busiest) : 0 } ?? 0
                )
            }
        }
        if let observedAt {
            picture.footnotes.append(UsageDetailCard.updatedText(
                observedAt, now: now, locale: locale, bundle: bundle
            ))
        }
        if summary.hasPartialCounts || activity.hasPartialCounts {
            picture.footnotes.append(String(localized: "Counts may be incomplete.", bundle: bundle))
        }
        if hasReadLimitations {
            picture.footnotes.append(String(localized: "Some compressed records could not be read.", bundle: bundle))
        }
        return picture
    }
}
