// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The last twelve months of work, one number per calendar day — what the Token
/// spend pane's "Token activity" chart draws as a grid, as weekly bars and as a
/// running total.
///
/// **Independent of the span picker.** The picker decides what the headline and
/// the tables add up; this always covers the year to today, so a quiet week does
/// not empty a chart whose whole job is the long view. It is built from the same
/// ledgers the pane already holds (`LedgerDay` is one row per local midnight,
/// priced or not), so there is no further read of any store.
///
/// **A day nobody worked is quiet; a day nothing was recorded for is not drawn.**
/// Days before the first record Pulse has (across the agents counted) and days
/// after today are `nil` in `Week.days`: no cell, no bar, no point. Only days from
/// the first record on can be quiet, and only those carry a zero.
///
/// **The window is the last twelve months in at most 53 week columns.** It
/// starts at `today − 1 year + 1 day`, pulled forward when that would need a
/// 54th column, and each column starts on the calendar's own first weekday. The
/// first and last columns are partial; nothing is drawn for the days outside the
/// window, so the total is exactly the drawn days.
struct TokenActivity: Equatable, Sendable {
    /// One drawn day.
    struct Day: Equatable, Sendable {
        let date: Date
        let tokens: Int
    }

    /// One column of the grid: seven positions from the calendar's first weekday.
    struct Week: Equatable, Sendable, Identifiable {
        /// The first day of the column, which may be before the window.
        let start: Date
        /// Exactly seven entries; nil where nothing is drawn.
        let days: [Day?]

        var id: Date { start }
        var drawn: [Day] { days.compactMap { $0 } }
        var hasData: Bool { days.contains { $0 != nil } }
        var tokens: Int { drawn.reduce(0) { $0 + $1.tokens } }
        /// The drawn range, for a label: partial weeks are clipped to it.
        var range: ClosedRange<Date>? {
            guard let first = drawn.first, let last = drawn.last else { return nil }
            return first.date...last.date
        }
    }

    /// One point of the running total. `position` is in week columns, so the
    /// three views share one horizontal scale and one set of month labels.
    struct Point: Equatable, Sendable {
        let date: Date
        let running: Int
        let position: Double
    }

    /// A month label under the chart: the column it starts in, and a date in it.
    struct Mark: Equatable, Sendable {
        let column: Int
        let date: Date
    }

    /// The columns, oldest first. Empty when there is no record at all.
    var weeks: [Week] = []
    /// Every drawn day's tokens, added up.
    var total = 0
    /// Drawn days with work on them.
    var activeDays = 0
    /// The three upper bounds of colour steps 1–3 (a fourth step is anything
    /// above the last): the quartiles of the days with work, so one huge day
    /// does not flatten the rest of the year into the palest step.
    var cuts: [Int] = []
    /// Whether a ledger that contributed to the window may be missing counts.
    var hasPartialCounts = false

    var isEmpty: Bool { weeks.isEmpty }
    var columnCount: Int { weeks.count }

    /// 0 for a quiet day, 1–4 for a day with work, by quartile of the busy days.
    func step(for tokens: Int) -> Int {
        guard tokens > 0 else { return 0 }
        return 1 + cuts.count { tokens > $0 }
    }

    /// The running total, one point per drawn day.
    var points: [Point] {
        var running = 0
        var result: [Point] = []
        for (column, week) in weeks.enumerated() {
            for (row, day) in week.days.enumerated() {
                guard let day else { continue }
                running += day.tokens
                result.append(Point(date: day.date, running: running, position: Double(column) + (Double(row) + 0.5) / 7))
            }
        }
        return result
    }

    /// Month labels: the first column in which each month begins. A label is
    /// dropped when the next one is closer than `minimumGap` columns (a month
    /// is never shorter than four), and the last when fewer than that remain,
    /// so no label crowds its neighbour or runs off the right edge.
    func monthMarks(calendar: Calendar, minimumGap: Int = 4) -> [Mark] {
        var marks: [Mark] = []
        var previous: Int?
        for (column, week) in weeks.enumerated() {
            guard let first = week.drawn.first else { continue }
            let month = calendar.component(.month, from: first.date)
            if month != previous { marks.append(Mark(column: column, date: first.date)) }
            previous = month
        }
        var kept: [Mark] = []
        for (index, mark) in marks.enumerated() {
            let next = index + 1 < marks.count ? marks[index + 1].column : weeks.count
            if next - mark.column >= minimumGap { kept.append(mark) }
        }
        return kept
    }

    /// The window `of` draws for a given day: first drawn day and the first
    /// column's start. Exposed for the tests.
    static func window(today: Date, calendar: Calendar) -> (start: Date, gridStart: Date) {
        let weekStart = { (date: Date) in calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date }
        let year = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        let candidate = calendar.date(byAdding: .day, value: 1, to: year) ?? year
        let longest = calendar.date(byAdding: .weekOfYear, value: -52, to: weekStart(today)) ?? candidate
        let start = max(candidate, longest)
        return (start, weekStart(start))
    }

    /// The year to `now`, from the ledgers' own day rows.
    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TokenActivity {
        let today = calendar.startOfDay(for: now)
        let (start, gridStart) = window(today: today, calendar: calendar)

        var tokensByDay: [Date: Int] = [:]
        var partial = false
        var first: Date?
        for ledger in ledgers.values {
            guard !Task.isCancelled else { return TokenActivity() }
            // The same gate the whole pane applies: a provider's own
            // statistics carry no money and are not counted anywhere here.
            guard ledger.origin.supportsTokenSpend else { continue }
            var contributes = false
            for day in ledger.days where day.tokens > 0 {
                let date = calendar.startOfDay(for: day.date)
                first = min(first ?? date, date)
                guard date >= start, date <= today else { continue }
                tokensByDay[date, default: 0] += day.tokens
                contributes = true
            }
            if contributes, ledger.hasPartialCounts { partial = true }
        }
        // Nothing at all, or only work in the future: nothing to draw.
        guard let first, first <= today else { return TokenActivity() }
        let firstDrawn = max(first, start)

        var activity = TokenActivity()
        var cursor = gridStart
        while cursor <= today {
            var days: [Day?] = []
            var date = cursor
            for _ in 0..<7 {
                if date >= firstDrawn, date <= today {
                    days.append(Day(date: date, tokens: tokensByDay[date] ?? 0))
                } else {
                    days.append(nil)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
            while days.count < 7 { days.append(nil) }
            activity.weeks.append(Week(start: cursor, days: days))
            cursor = date
        }

        let busy = activity.weeks.flatMap(\.drawn).map(\.tokens).filter { $0 > 0 }.sorted()
        activity.total = busy.reduce(0, +)
        activity.activeDays = busy.count
        if !busy.isEmpty {
            activity.cuts = (1...3).map { quarter in
                busy[min(busy.count - 1, max((busy.count * quarter + 3) / 4 - 1, 0))]
            }
        }
        activity.hasPartialCounts = partial
        return activity
    }
}
