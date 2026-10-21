// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension Recap.Period {
    /// "2026-10-18" for a day, "week-2026-10-12" for the week starting then,
    /// "2026-09" for a month, "2026" for a year: the form `--recap` takes, the
    /// period in an exported file's name, and what is remembered about which
    /// month was announced.
    var key: String {
        switch self {
        case .day(let year, let month, let day): String(format: "%04d-%02d-%02d", year, month, day)
        case .week(let year, let month, let day): String(format: "week-%04d-%02d-%02d", year, month, day)
        case .month(let year, let month): String(format: "%04d-%02d", year, month)
        case .year(let year): String(format: "%04d", year)
        }
    }

    init?(key: String) {
        guard let period = RecapReport.period(from: key) else { return nil }
        self = period
    }

    var isYear: Bool {
        if case .year = self { return true }
        return false
    }

    /// The year the period starts in: a week from December 28 is that year's.
    var year: Int {
        switch self {
        case .day(let year, _, _), .week(let year, _, _), .month(let year, _), .year(let year): year
        }
    }

    /// The day or week whose first day is `date` in `calendar`.
    static func day(of date: Date, calendar: Calendar) -> Recap.Period? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return .day(year: year, month: month, day: day)
    }

    static func week(startingOn date: Date, calendar: Calendar) -> Recap.Period? {
        guard case .day(let year, let month, let day) = day(of: date, calendar: calendar) else { return nil }
        return .week(year: year, month: month, day: day)
    }
}

/// Which periods the recap window offers and which one it opens on.
///
/// **Offered: every month, and every year, from the earliest record on this
/// Mac to now** — nothing before it (an empty September 2019 is not a recap)
/// and nothing after (a month that has not started is not one either). Newest
/// first. With no record known yet only the default is offered.
///
/// **Opened on: the month (or year) that just finished during its first seven
/// days, the running one after that.** On October 3 the person asking is
/// almost certainly asking about September: October has three days in it and
/// the card would say so. From the 8th the running month has enough in it to
/// be the thing they mean. Where the default would fall before the earliest
/// record it moves up to it; until that record is known the rule stands alone.
///
/// **Days and weeks** follow the same rule at their scale: every day, and every
/// week, from the earliest record's to today's; opened on yesterday until 05:00
/// and today after it, and on last week during a week's first day. Weeks start
/// on the reader's own first weekday (`firstWeekday`).
enum RecapPeriods {
    /// The first days of a month (or year) in which the one just finished is
    /// what "the recap" means.
    static let earlyDays = 7

    /// `year * 12 + (month - 1)`, so months can be counted and compared.
    private static func index(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1
    }

    private static func month(at index: Int) -> Recap.Period {
        .month(year: index / 12, month: index % 12 + 1)
    }

    /// Months with records possible, newest first.
    static func months(earliest: Date?, now: Date = Date(), calendar: Calendar = Recap.calendar) -> [Recap.Period] {
        let current = index(now, calendar: calendar)
        let first = earliest.map { min(index($0, calendar: calendar), current) } ?? current
        return (first...current).reversed().map(month(at:))
    }

    /// Years with records possible, newest first.
    static func years(earliest: Date?, now: Date = Date(), calendar: Calendar = Recap.calendar) -> [Recap.Period] {
        let current = calendar.component(.year, from: now)
        let first = earliest.map { min(calendar.component(.year, from: $0), current) } ?? current
        return (first...current).reversed().map { .year($0) }
    }

    /// The month to open on: see the type's note.
    static func defaultMonth(earliest: Date?, now: Date = Date(), calendar: Calendar = Recap.calendar) -> Recap.Period {
        let current = index(now, calendar: calendar)
        let early = calendar.component(.day, from: now) <= earlyDays
        let wanted = early ? current - 1 : current
        // Nothing known about the first record is not a floor at this month.
        let floor = earliest.map { min(index($0, calendar: calendar), current) } ?? wanted
        return month(at: max(wanted, floor))
    }

    /// The year to open on.
    static func defaultYear(earliest: Date?, now: Date = Date(), calendar: Calendar = Recap.calendar) -> Recap.Period {
        let current = calendar.component(.year, from: now)
        let parts = calendar.dateComponents([.month, .day], from: now)
        let early = parts.month == 1 && (parts.day ?? 1) <= earlyDays
        let wanted = early ? current - 1 : current
        let floor = earliest.map { min(calendar.component(.year, from: $0), current) } ?? wanted
        return .year(max(wanted, floor))
    }

    // MARK: Days and weeks

    /// The day the reader's week starts on, 1 = Sunday … 7 = Saturday: what
    /// their region, or the first day of the week chosen in System Settings,
    /// says. Only the weekday is taken from `Calendar.current`; the days are
    /// still counted in `Recap.calendar`, so an era of another calendar cannot
    /// rename the year.
    static var firstWeekday: Int { Calendar.current.firstWeekday }

    /// The local midnight that begins the week `date` falls in, weeks starting
    /// on `firstWeekday`. Counted back in days from the day's own start, not
    /// with `dateInterval(of: .weekOfYear)`, whose answer also depends on the
    /// calendar's rule for the first week of a year.
    static func weekStart(of date: Date, firstWeekday: Int = firstWeekday, calendar: Calendar = Recap.calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let first = (1...7).contains(firstWeekday) ? firstWeekday : 1
        let back = (calendar.component(.weekday, from: day) - first + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day).map { calendar.startOfDay(for: $0) } ?? day
    }

    /// The period of a kind that `date` falls in.
    static func period(
        _ kind: Recap.Period.Kind, containing date: Date,
        firstWeekday: Int = firstWeekday, calendar: Calendar = Recap.calendar
    ) -> Recap.Period? {
        switch kind {
        case .day:
            return Recap.Period.day(of: calendar.startOfDay(for: date), calendar: calendar)
        case .week:
            return Recap.Period.week(startingOn: weekStart(of: date, firstWeekday: firstWeekday, calendar: calendar), calendar: calendar)
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { return nil }
            return .month(year: year, month: month)
        case .year:
            return .year(calendar.component(.year, from: date))
        }
    }

    /// Local midnights from `last` back to `first`, `step` days apart, newest
    /// first. Midnight to midnight by days, so a clock change does not drift
    /// the list off its days.
    private static func midnights(from last: Date, back first: Date, step: Int, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = last
        while cursor >= first {
            result.append(cursor)
            guard let earlier = calendar.date(byAdding: .day, value: -step, to: cursor).map({ calendar.startOfDay(for: $0) }),
                  earlier < cursor else { break }
            cursor = earlier
        }
        return result
    }

    /// Days with records possible, newest first: today back to the earliest
    /// record's day.
    static func days(earliest: Date?, now: Date = Date(), calendar: Calendar = Recap.calendar) -> [Recap.Period] {
        let today = calendar.startOfDay(for: now)
        let first = earliest.map { min(calendar.startOfDay(for: $0), today) } ?? today
        return midnights(from: today, back: first, step: 1, calendar: calendar)
            .compactMap { Recap.Period.day(of: $0, calendar: calendar) }
    }

    /// Weeks with records possible, newest first: this week back to the one
    /// the earliest record falls in.
    static func weeks(
        earliest: Date?, now: Date = Date(), firstWeekday: Int = firstWeekday, calendar: Calendar = Recap.calendar
    ) -> [Recap.Period] {
        let current = weekStart(of: now, firstWeekday: firstWeekday, calendar: calendar)
        let first = earliest.map { min(weekStart(of: $0, firstWeekday: firstWeekday, calendar: calendar), current) } ?? current
        return midnights(from: current, back: first, step: 7, calendar: calendar)
            .compactMap { Recap.Period.week(startingOn: $0, calendar: calendar) }
    }

    /// The day to open on: today, except before 05:00 (`Recap.nightEndsAtHour`),
    /// when the work being asked about is the day that just ended — the rule
    /// that gives a stretch begun after midnight to the evening before.
    static func defaultDay(earliest: Date?, now: Date = Date(), calendar: Calendar = Recap.calendar) -> Recap.Period {
        let today = calendar.startOfDay(for: now)
        var wanted = today
        if calendar.component(.hour, from: now) < Recap.nightEndsAtHour,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            wanted = calendar.startOfDay(for: yesterday)
        }
        if let earliest { wanted = max(wanted, min(calendar.startOfDay(for: earliest), today)) }
        return Recap.Period.day(of: wanted, calendar: calendar) ?? .day(year: 2026, month: 1, day: 1)
    }

    /// The week to open on: the one that just ended on the first day of a
    /// week, this one from its second day — a week's first day is to it what
    /// a month's first seven days are to a month.
    static func defaultWeek(
        earliest: Date?, now: Date = Date(), firstWeekday: Int = firstWeekday, calendar: Calendar = Recap.calendar
    ) -> Recap.Period {
        let current = weekStart(of: now, firstWeekday: firstWeekday, calendar: calendar)
        var wanted = current
        if calendar.isDate(now, inSameDayAs: current),
           let before = calendar.date(byAdding: .day, value: -7, to: current) {
            wanted = calendar.startOfDay(for: before)
        }
        if let earliest {
            wanted = max(wanted, min(weekStart(of: earliest, firstWeekday: firstWeekday, calendar: calendar), current))
        }
        return Recap.Period.week(startingOn: wanted, calendar: calendar) ?? .week(year: 2026, month: 1, day: 1)
    }

    // MARK: Any kind

    /// The periods of a kind the window offers, newest first.
    static func offered(
        _ kind: Recap.Period.Kind, earliest: Date?, now: Date = Date(),
        firstWeekday: Int = firstWeekday, calendar: Calendar = Recap.calendar
    ) -> [Recap.Period] {
        switch kind {
        case .day: days(earliest: earliest, now: now, calendar: calendar)
        case .week: weeks(earliest: earliest, now: now, firstWeekday: firstWeekday, calendar: calendar)
        case .month: months(earliest: earliest, now: now, calendar: calendar)
        case .year: years(earliest: earliest, now: now, calendar: calendar)
        }
    }

    /// The period of a kind the window opens on.
    static func defaultPeriod(
        _ kind: Recap.Period.Kind, earliest: Date?, now: Date = Date(),
        firstWeekday: Int = firstWeekday, calendar: Calendar = Recap.calendar
    ) -> Recap.Period {
        switch kind {
        case .day: defaultDay(earliest: earliest, now: now, calendar: calendar)
        case .week: defaultWeek(earliest: earliest, now: now, firstWeekday: firstWeekday, calendar: calendar)
        case .month: defaultMonth(earliest: earliest, now: now, calendar: calendar)
        case .year: defaultYear(earliest: earliest, now: now, calendar: calendar)
        }
    }

    /// The period of another kind that goes with this one: the one holding
    /// this period's last day, or today while this period runs. So a month
    /// becomes its year and a year its last month so far, as before, a day
    /// becomes its week, and a week its last day so far.
    static func switched(
        _ period: Recap.Period, to kind: Recap.Period.Kind, earliest: Date?, now: Date = Date(),
        firstWeekday: Int = firstWeekday, calendar: Calendar = Recap.calendar
    ) -> Recap.Period {
        guard period.kind != kind, let bounds = period.bounds(calendar: calendar) else { return period }
        let last = calendar.date(byAdding: .day, value: -1, to: bounds.end).map { calendar.startOfDay(for: $0) } ?? bounds.start
        let anchor = max(bounds.start, min(last, calendar.startOfDay(for: now)))
        return self.period(kind, containing: anchor, firstWeekday: firstWeekday, calendar: calendar)
            ?? defaultPeriod(kind, earliest: earliest, now: now, firstWeekday: firstWeekday, calendar: calendar)
    }

    /// No recap is offered before this: a bogus timestamp in some store (an
    /// epoch of zero, a clock that was wrong) must not turn into hundreds of
    /// empty months in the picker.
    static func floor(calendar: Calendar = Recap.calendar) -> Date? {
        calendar.date(from: DateComponents(year: 2020, month: 1, day: 1))
    }

    /// The earliest day any ledger the Token spend pane may show holds a
    /// record for, and not before `floor`. A provider's own statistics
    /// (`UsageLedger.Origin.supportsTokenSpend`) are not records of this Mac's
    /// work and do not decide where the recap begins.
    static func earliest(in ledgers: [SpendAgent: UsageLedger], calendar: Calendar = Recap.calendar) -> Date? {
        let found = ledgers.values
            .filter { $0.origin.supportsTokenSpend }
            .compactMap { $0.earliest ?? $0.days.first?.date }
            .min()
        guard let found else { return nil }
        return floor(calendar: calendar).map { max(found, $0) } ?? found
    }
}

/// The monthly subscription price typed into the recap window, as text and as
/// the figure it stands for.
///
/// **Strict, and no locale guessing.** After trimming whitespace and one
/// leading "$", the text is either plain digits with an optional "." or ","
/// and one or two decimals ("20", "12.5", "12,5" is 12.5), or digits grouped by
/// "," in valid groups of three with an optional ".dd" ("1,200", "1,200.50").
/// Anything else — a word, "1e3", "20 USD", "-5", "1,2,3", three decimals — is
/// refused and the field goes back to what was kept, rather than being read as
/// some other number by a formatter's idea of the locale.
///
/// **Nothing is not zero.** Empty clears it, and so does 0: a price of nothing
/// is not a subscription, and `RecapDeck.payback` would draw no card for it
/// either way. More than `maximum` is refused too.
enum RecapPrice {
    /// A month's price in US dollars. Well past anything sold, and low enough
    /// that a stray extra digit is refused rather than drawn on a card.
    static let maximum = 10_000.0

    enum Entry: Equatable {
        case none
        case amount(Double)
        case refused
    }

    static func entry(_ typed: String) -> Entry {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .none }
        if text.hasPrefix("$") {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let number: String
        if let plain = text.wholeMatch(of: /([0-9]+)(?:[.,]([0-9]{1,2}))?/) {
            number = plain.1 + (plain.2.map { "." + $0 } ?? "")
        } else if let grouped = text.wholeMatch(of: /([0-9]{1,3}(?:,[0-9]{3})+)(?:\.([0-9]{1,2}))?/) {
            number = grouped.1.replacingOccurrences(of: ",", with: "") + (grouped.2.map { "." + $0 } ?? "")
        } else {
            return .refused
        }

        guard let value = Double(number), value.isFinite, value <= maximum else { return .refused }
        return value == 0 ? .none : .amount(value)
    }

    /// What the settings keep: nil unless it is a positive amount within range.
    static func normalized(_ amount: Double?) -> Double? {
        guard let amount, amount.isFinite, amount > 0, amount <= maximum else { return nil }
        return amount
    }

    /// The figure as the field shows it: no grouping, at most two decimals.
    static func text(_ amount: Double?, locale: Locale = LocalizationSource.locale) -> String {
        guard let amount = normalized(amount) else { return "" }
        return amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }
}

/// When Pulse says "your September recap is ready", and what it says it about.
///
/// Pure: the caller hands over the date, what was already announced and the
/// token count of the month in question, so every rule is decidable from its
/// arguments. See [notifications.md](../../Docs/notifications.md#the-monthly-recap).
///
/// - **Only in the first `windowDays` days of a month**, and only about the
///   month before. On the 1st is what was asked for; the days after it are for
///   a Mac that was asleep, shut or not running on the 1st. After them the
///   moment is gone and a notification would be news from the past.
/// - **Once per month.** The month announced is remembered, so a relaunch, a
///   second tick or switching the setting off and on again says nothing more.
/// - **Only when the month had records** — which Pulse has seen, in the scan
///   it already holds. Without a scan (`tokens` returns nil) nothing is said
///   and nothing is remembered: "no records" is not something Pulse witnessed.
enum RecapNoticeRule {
    static let windowDays = 3
    /// The notification's identifier, so a click can tell which month it is for.
    static let identifierPrefix = "recap-ready-"

    /// The month a notification may be about today, or nil outside the window.
    static func candidate(now: Date, calendar: Calendar = Recap.calendar) -> Recap.Period? {
        guard calendar.component(.day, from: now) <= windowDays,
              let previous = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        let parts = calendar.dateComponents([.year, .month], from: previous)
        guard let year = parts.year, let month = parts.month else { return nil }
        return .month(year: year, month: month)
    }

    /// The month to announce now, or nil for nothing to say.
    static func due(
        now: Date,
        announced: Recap.Period?,
        tokens: (Recap.Period) -> Int?,
        calendar: Calendar = Recap.calendar
    ) -> Recap.Period? {
        guard let month = candidate(now: now, calendar: calendar), announced != month,
              let counted = tokens(month), counted > 0 else { return nil }
        return month
    }

    static func identifier(for period: Recap.Period) -> String { identifierPrefix + period.key }

    static func period(fromIdentifier identifier: String) -> Recap.Period? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return Recap.Period(key: String(identifier.dropFirst(identifierPrefix.count)))
    }
}
