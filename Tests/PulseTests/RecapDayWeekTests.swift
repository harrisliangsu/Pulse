import Foundation
import Testing
@testable import Pulse

/// Day and week recaps: where a day or a week begins and ends — across clock
/// changes, a zone that skips midnight, the end of a year and a leap day —
/// which ones the window offers and opens on, how it moves between kinds, and
/// what their decks keep or leave out.
@Suite("Recap days and weeks")
struct RecapDayWeekTests {
    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private static let utc = calendar("UTC")
    private static let newYork = calendar("America/New_York")
    /// Chile moves its clocks at midnight: September 6, 2026 has no 00:00.
    private static let santiago = calendar("America/Santiago")

    private static func at(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in calendar: Calendar = utc
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func hours(_ bounds: (start: Date, end: Date)?) -> Double? {
        bounds.map { $0.end.timeIntervalSince($0.start) / 3600 }
    }

    // MARK: - Bounds

    @Test("A day runs midnight to midnight, and a week seven days")
    func plainBounds() throws {
        let day = try #require(Recap.Period.day(year: 2026, month: 10, day: 18).bounds(calendar: Self.utc))
        #expect(day.start == Self.at(2026, 10, 18, 0))
        #expect(day.end == Self.at(2026, 10, 19, 0))
        let week = try #require(Recap.Period.week(year: 2026, month: 10, day: 12).bounds(calendar: Self.utc))
        #expect(week.start == Self.at(2026, 10, 12, 0))
        #expect(week.end == Self.at(2026, 10, 19, 0))
    }

    @Test("The days the clocks change are 23 and 25 hours, and a week across one is still seven days")
    func clockChanges() throws {
        let calendar = Self.newYork
        #expect(Self.hours(Recap.Period.day(year: 2026, month: 3, day: 8).bounds(calendar: calendar)) == 23)
        #expect(Self.hours(Recap.Period.day(year: 2026, month: 11, day: 1).bounds(calendar: calendar)) == 25)
        #expect(Self.hours(Recap.Period.day(year: 2026, month: 3, day: 9).bounds(calendar: calendar)) == 24)

        let spring = try #require(Recap.Period.week(year: 2026, month: 3, day: 2).bounds(calendar: calendar))
        #expect(spring.end == Self.at(2026, 3, 9, 0, in: calendar))
        let across = try #require(Recap.Period.week(year: 2026, month: 3, day: 5).bounds(calendar: calendar))
        #expect(across.end == Self.at(2026, 3, 12, 0, in: calendar))
        #expect(across.end.timeIntervalSince(across.start) / 3600 == 7 * 24 - 1)
        let autumn = try #require(Recap.Period.week(year: 2026, month: 10, day: 26).bounds(calendar: calendar))
        #expect(autumn.end.timeIntervalSince(autumn.start) / 3600 == 7 * 24 + 1)
    }

    @Test("Where midnight does not exist the day starts at its first hour")
    func skippedMidnight() throws {
        let calendar = Self.santiago
        let day = try #require(Recap.Period.day(year: 2026, month: 9, day: 6).bounds(calendar: calendar))
        #expect(calendar.component(.hour, from: day.start) == 1)
        #expect(calendar.component(.day, from: day.start) == 6)
        #expect(day.end == Self.at(2026, 9, 7, 0, in: calendar))
        // The day before ends where this one begins.
        let before = try #require(Recap.Period.day(year: 2026, month: 9, day: 5).bounds(calendar: calendar))
        #expect(before.end == day.start)
    }

    @Test("A date not on the calendar names no period; a leap day does")
    func invalidDates() {
        #expect(Recap.Period.day(year: 2026, month: 2, day: 30).bounds(calendar: Self.utc) == nil)
        #expect(Recap.Period.week(year: 2026, month: 13, day: 1).bounds(calendar: Self.utc) == nil)
        #expect(Recap.Period.day(year: 2026, month: 4, day: 0).bounds(calendar: Self.utc) == nil)
        #expect(Recap.Period.day(year: 2028, month: 2, day: 29).bounds(calendar: Self.utc) != nil)
        #expect(Recap.Period.day(year: 2026, month: 2, day: 29).bounds(calendar: Self.utc) == nil)
        #expect(Recap.build(.day(year: 2026, month: 2, day: 30), from: [:], prices: [:], now: Self.at(2026, 3, 5), calendar: Self.utc) == nil)
    }

    @Test("The period before a day or a week crosses months, years and leap days")
    func previous() {
        #expect(Recap.Period.day(year: 2026, month: 1, day: 1).previous == .day(year: 2025, month: 12, day: 31))
        #expect(Recap.Period.day(year: 2028, month: 3, day: 1).previous == .day(year: 2028, month: 2, day: 29))
        #expect(Recap.Period.week(year: 2027, month: 1, day: 3).previous == .week(year: 2026, month: 12, day: 27))
        #expect(Recap.Period.week(year: 2026, month: 10, day: 5).previous == .week(year: 2026, month: 9, day: 28))
    }

    // MARK: - Weeks start on the reader's day

    @Test("A week starts on the first weekday asked for")
    func weekStart() {
        // October 18, 2026 is a Sunday.
        let sunday = Self.at(2026, 10, 18, 9)
        #expect(RecapPeriods.weekStart(of: sunday, firstWeekday: 2, calendar: Self.utc) == Self.at(2026, 10, 12, 0))
        #expect(RecapPeriods.weekStart(of: sunday, firstWeekday: 1, calendar: Self.utc) == Self.at(2026, 10, 18, 0))
        #expect(RecapPeriods.weekStart(of: sunday, firstWeekday: 7, calendar: Self.utc) == Self.at(2026, 10, 17, 0))
        #expect(RecapPeriods.weekStart(of: Self.at(2026, 10, 12, 0), firstWeekday: 2, calendar: Self.utc) == Self.at(2026, 10, 12, 0))
        // The calendar's own first weekday is not what decides it.
        var sundayCalendar = Self.utc
        sundayCalendar.firstWeekday = 1
        #expect(RecapPeriods.weekStart(of: sunday, firstWeekday: 2, calendar: sundayCalendar) == Self.at(2026, 10, 12, 0))
    }

    @Test("A week on the day the clocks change starts at that day's midnight")
    func weekStartAcrossClockChange() {
        let calendar = Self.newYork
        // Wednesday March 11, 2026, after the change on Sunday the 8th.
        let start = RecapPeriods.weekStart(of: Self.at(2026, 3, 11, 9, in: calendar), firstWeekday: 1, calendar: calendar)
        #expect(start == Self.at(2026, 3, 8, 0, in: calendar))
        #expect(RecapPeriods.period(.week, containing: Self.at(2026, 3, 8, 3, in: calendar), firstWeekday: 1, calendar: calendar)
                == .week(year: 2026, month: 3, day: 8))
    }

    // MARK: - Offered and opened on

    @Test("Weeks run from the earliest record's to this one, newest first, across the year")
    func offeredWeeks() {
        let earliest = Self.at(2026, 12, 30)
        let now = Self.at(2027, 1, 12)
        #expect(RecapPeriods.weeks(earliest: earliest, now: now, firstWeekday: 2, calendar: Self.utc) == [
            .week(year: 2027, month: 1, day: 11), .week(year: 2027, month: 1, day: 4), .week(year: 2026, month: 12, day: 28),
        ])
        #expect(RecapPeriods.weeks(earliest: earliest, now: now, firstWeekday: 1, calendar: Self.utc) == [
            .week(year: 2027, month: 1, day: 10), .week(year: 2027, month: 1, day: 3), .week(year: 2026, month: 12, day: 27),
        ])
        #expect(RecapPeriods.weeks(earliest: nil, now: now, firstWeekday: 2, calendar: Self.utc) == [.week(year: 2027, month: 1, day: 11)])
    }

    @Test("Days run back to the earliest record's, each once across a clock change")
    func offeredDays() {
        let calendar = Self.newYork
        let days = RecapPeriods.days(
            earliest: Self.at(2026, 3, 7, 22, in: calendar), now: Self.at(2026, 3, 9, 1, in: calendar), calendar: calendar
        )
        #expect(days == [.day(year: 2026, month: 3, day: 9), .day(year: 2026, month: 3, day: 8), .day(year: 2026, month: 3, day: 7)])
        let fall = RecapPeriods.days(
            earliest: Self.at(2026, 10, 31, 8, in: calendar), now: Self.at(2026, 11, 2, 23, in: calendar), calendar: calendar
        )
        #expect(fall == [.day(year: 2026, month: 11, day: 2), .day(year: 2026, month: 11, day: 1), .day(year: 2026, month: 10, day: 31)])
    }

    @Test("A day opens on yesterday until 05:00, today after it, and never before the records")
    func defaultDay() {
        let earliest = Self.at(2026, 1, 1)
        #expect(RecapPeriods.defaultDay(earliest: earliest, now: Self.at(2026, 10, 18, 4, 59), calendar: Self.utc) == .day(year: 2026, month: 10, day: 17))
        #expect(RecapPeriods.defaultDay(earliest: earliest, now: Self.at(2026, 10, 18, 5), calendar: Self.utc) == .day(year: 2026, month: 10, day: 18))
        #expect(RecapPeriods.defaultDay(earliest: Self.at(2026, 10, 18, 1), now: Self.at(2026, 10, 18, 3), calendar: Self.utc)
                == .day(year: 2026, month: 10, day: 18))
        #expect(RecapPeriods.defaultDay(earliest: nil, now: Self.at(2026, 1, 1, 2), calendar: Self.utc) == .day(year: 2025, month: 12, day: 31))
    }

    @Test("A week opens on last week during its first day, and on this one after")
    func defaultWeek() {
        // Monday October 12 and Tuesday the 13th; Sunday the 18th.
        #expect(RecapPeriods.defaultWeek(earliest: nil, now: Self.at(2026, 10, 12, 20), firstWeekday: 2, calendar: Self.utc)
                == .week(year: 2026, month: 10, day: 5))
        #expect(RecapPeriods.defaultWeek(earliest: nil, now: Self.at(2026, 10, 13, 8), firstWeekday: 2, calendar: Self.utc)
                == .week(year: 2026, month: 10, day: 12))
        #expect(RecapPeriods.defaultWeek(earliest: nil, now: Self.at(2026, 10, 18, 8), firstWeekday: 1, calendar: Self.utc)
                == .week(year: 2026, month: 10, day: 11))
        // Records from this Monday: last week is not offered.
        #expect(RecapPeriods.defaultWeek(earliest: Self.at(2026, 10, 12, 9), now: Self.at(2026, 10, 12, 20), firstWeekday: 2, calendar: Self.utc)
                == .week(year: 2026, month: 10, day: 12))
    }

    @Test("Switching kind keeps the last day the period has had")
    func switching() {
        let now = Self.at(2026, 10, 14)
        let earliest = Self.at(2025, 3, 1)
        func switched(_ period: Recap.Period, _ kind: Recap.Period.Kind) -> Recap.Period {
            RecapPeriods.switched(period, to: kind, earliest: earliest, now: now, firstWeekday: 2, calendar: Self.utc)
        }
        #expect(switched(.day(year: 2026, month: 10, day: 14), .week) == .week(year: 2026, month: 10, day: 12))
        // A running week's last day so far is today.
        #expect(switched(.week(year: 2026, month: 10, day: 12), .day) == .day(year: 2026, month: 10, day: 14))
        #expect(switched(.week(year: 2026, month: 9, day: 28), .day) == .day(year: 2026, month: 10, day: 4))
        #expect(switched(.week(year: 2026, month: 9, day: 28), .month) == .month(year: 2026, month: 10))
        #expect(switched(.month(year: 2026, month: 9), .week) == .week(year: 2026, month: 9, day: 28))
        #expect(switched(.month(year: 2026, month: 9), .day) == .day(year: 2026, month: 9, day: 30))
        #expect(switched(.year(2026), .week) == .week(year: 2026, month: 10, day: 12))
        #expect(switched(.day(year: 2025, month: 12, day: 31), .year) == .year(2025))
    }

    @Test("‹ and › step to the day before and after, by date, and stop at either end")
    @MainActor
    func stepping() {
        let days = RecapWindowModel.preview(
            settings: AppSettings(), phase: .ready, period: .day(year: 2026, month: 10, day: 14),
            earliest: Self.at(2026, 10, 12, 0, in: Recap.calendar), now: { Self.at(2026, 10, 15, in: Recap.calendar) }
        )
        #expect(days.neighbour(-1) == .day(year: 2026, month: 10, day: 13))
        #expect(days.neighbour(1) == .day(year: 2026, month: 10, day: 15))
        // Asked for before the read knows the records: listed first in the
        // popup, but stepped through by date.
        let month = RecapWindowModel.preview(
            settings: AppSettings(), phase: .ready, period: .month(year: 2026, month: 9),
            earliest: nil, now: { Self.at(2026, 10, 3, in: Recap.calendar) }
        )
        #expect(month.offered == [.month(year: 2026, month: 9), .month(year: 2026, month: 10)])
        #expect(month.neighbour(-1) == nil)
        #expect(month.neighbour(1) == .month(year: 2026, month: 10))
    }

    @Test("Day and week keys round-trip, and --recap takes them")
    func keys() {
        #expect(Recap.Period.day(year: 2026, month: 10, day: 18).key == "2026-10-18")
        #expect(Recap.Period.week(year: 2026, month: 10, day: 12).key == "week-2026-10-12")
        #expect(Recap.Period(key: "2026-10-18") == .day(year: 2026, month: 10, day: 18))
        #expect(Recap.Period(key: "week-2026-10-12") == .week(year: 2026, month: 10, day: 12))
        #expect(Recap.Period(key: "2026-02-30") == nil)
        #expect(Recap.Period(key: "week-2026-10") == nil)
        #expect(Recap.Period(key: "2026-10-1") == nil)
        #expect(Recap.Period(key: "week-2026") == nil)
        #expect(RecapReport.refusal(arguments: ["Pulse", "--recap", "2026-13-01"]) == 2)
    }

    // MARK: - Built from ledgers

    private static func ledger(_ events: [(Date, Int)], calendar: Calendar) -> UsageLedger {
        var buckets: [String: [String: TokenTally]] = [:]
        for (at, tokens) in events {
            let key = UsageLedgerReader.slotKey(for: at, calendar: calendar)
            buckets[key, default: [:]]["claude"] = (buckets[key]?["claude"] ?? TokenTally()) + TokenTally(input: tokens)
        }
        let prices = ["claude": ModelPrice(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75, name: "Claude")]
        return UsageLedgerReader.price(buckets, with: prices, calendar: calendar)
    }

    @Test("A day holds its own quarter-hours and none of its neighbours'")
    func dayFromLedgers() throws {
        let calendar = Self.utc
        let ledger = Self.ledger([
            (Self.at(2026, 10, 4, 23, 45), 1_000), (Self.at(2026, 10, 5, 0, 0), 100),
            (Self.at(2026, 10, 5, 23, 45), 100), (Self.at(2026, 10, 6, 0, 0), 1_000),
        ], calendar: calendar)
        let recap = try #require(Recap.build(
            .day(year: 2026, month: 10, day: 5), from: [.claudeCode: ledger], prices: [:], now: Self.at(2026, 10, 18), calendar: calendar
        ))
        #expect(recap.tokens == 200)
        #expect(recap.days.count == 1)
        #expect(!recap.isInProgress)
        #expect(recap.previousTokens == 1_000)
        #expect(recap.months.isEmpty)
    }

    @Test("The day the clocks go forward keeps both of its ends")
    func dayAcrossClockChange() throws {
        let calendar = Self.newYork
        let ledger = Self.ledger([
            (Self.at(2026, 3, 8, 0, 30, in: calendar), 10), (Self.at(2026, 3, 8, 23, 30, in: calendar), 20),
            (Self.at(2026, 3, 9, 0, 0, in: calendar), 400),
        ], calendar: calendar)
        let recap = try #require(Recap.build(
            .day(year: 2026, month: 3, day: 8), from: [.claudeCode: ledger], prices: [:],
            now: Self.at(2026, 3, 20, in: calendar), calendar: calendar
        ))
        #expect(recap.tokens == 30)
        #expect(recap.days.count == 1)
    }

    @Test("A running week is set against the same days of the week before; a finished one against all of it")
    func weekFromLedgers() throws {
        let calendar = Self.utc
        let ledger = Self.ledger([
            (Self.at(2026, 10, 5), 10), (Self.at(2026, 10, 7), 20), (Self.at(2026, 10, 8), 900),
            (Self.at(2026, 10, 12), 100), (Self.at(2026, 10, 14), 50),
        ], calendar: calendar)
        let week = Recap.Period.week(year: 2026, month: 10, day: 12)
        let running = try #require(Recap.build(week, from: [.claudeCode: ledger], prices: [:], now: Self.at(2026, 10, 14), calendar: calendar))
        #expect(running.isInProgress)
        #expect(running.days.count == 3)
        #expect(running.tokens == 150)
        #expect(running.previousTokens == 30)
        #expect(running.activeDays == 2)

        let finished = try #require(Recap.build(week, from: [.claudeCode: ledger], prices: [:], now: Self.at(2026, 10, 25), calendar: calendar))
        #expect(!finished.isInProgress)
        #expect(finished.days.count == 7)
        #expect(finished.previousTokens == 930)
        #expect(finished.previousDays == 7)
    }

    // MARK: - The decks

    @Test("A day and a week have no calendar card; a day has no streak and no busiest-day tile")
    func cards() {
        let day = RecapDeck(recap: RecapSamples.day(), monthlyPrice: 200, hidesProjects: false)
        #expect(!day.cards.contains(.calendar))
        #expect(day.cards == [.poster, .opener, .timetable, .payback, .scorecard])
        #expect(day.streak == nil)
        #expect(day.scoreBars.isEmpty)
        #expect(day.tokensPerDay == nil)

        let week = RecapDeck(recap: RecapSamples.week(), monthlyPrice: 200, hidesProjects: false)
        #expect(week.cards == [.poster, .opener, .timetable, .payback, .scorecard])
        #expect(week.streak != nil)
        #expect(week.scoreBars.count == 7)
        #expect(week.scoreAxis.count == 7)
    }

    @Test("A day still running has no change chip; a finished one is set against the day before")
    func dayChange() {
        let running = RecapDeck(recap: RecapSamples.day(isInProgress: true), monthlyPrice: nil, hidesProjects: false)
        #expect(running.change == nil)
        let finished = RecapDeck(recap: RecapSamples.day(), monthlyPrice: nil, hidesProjects: false)
        #expect(finished.change?.versus == String.localized("vs the day before"))
    }

    @Test("A running week draws its days to come as such, not as quiet days")
    func runningWeek() throws {
        let deck = RecapDeck(recap: RecapSamples.week(through: 3), monthlyPrice: nil, hidesProjects: false)
        #expect(deck.scoreBars.count == 7)
        #expect(deck.scoreBars.suffix(4).allSatisfy { $0.slot == .future })
        let agent = try #require(deck.recap.agents.first)
        let marks = RecapInsights(deck.recap).marks(of: agent)
        #expect(marks.count == 7)
        #expect(marks.suffix(4).allSatisfy { $0 == .toCome })
        #expect(deck.change?.versus == String.localized("vs the same days last week"))
    }

    @Test("The plan price is prorated by day: a day is its month's share, a week its days' sum")
    func paidMonths() throws {
        let calendar = Self.utc
        func recap(_ period: Recap.Period, days: [Date], running: Bool = false) -> Recap {
            let bounds = period.bounds(calendar: calendar)!
            return Recap(
                period: period, start: bounds.start, end: bounds.end, isInProgress: running,
                tokens: 100, cost: 10, unpricedTokens: 0, previousTokens: nil, activeDays: days.count, elapsedDays: days.count,
                sessions: 1, days: days.map { Recap.Day(date: $0, tokens: 100 / days.count, cost: nil) }, months: [],
                hours: nil, peakHour: nil, lateShare: nil, latestMinute: nil, lateNights: 0, persona: nil,
                models: [], agents: [], projects: [], cacheHitRate: nil, cacheSavings: nil,
                currentStreak: 0, longestStreak: 0, busiestDay: nil, currency: "USD", isPartial: false, calendar: calendar
            )
        }
        let october = recap(.day(year: 2026, month: 10, day: 18), days: [Self.at(2026, 10, 18, 0)])
        #expect(abs(RecapDeck.paidMonths(october) - 1.0 / 31) < 1e-9)
        let weekDays = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: Self.at(2026, 9, 28, 0))! }
        let across = recap(.week(year: 2026, month: 9, day: 28), days: weekDays)
        #expect(abs(RecapDeck.paidMonths(across) - (3.0 / 30 + 4.0 / 31)) < 1e-9)
        let soFar = recap(.week(year: 2026, month: 9, day: 28), days: Array(weekDays.prefix(2)), running: true)
        #expect(abs(RecapDeck.paidMonths(soFar) - 2.0 / 30) < 1e-9)
        let payback = try #require(RecapDeck.payback(recap: october, monthlyPrice: 31))
        #expect(abs(payback.paid - 1) < 1e-9)
        #expect(abs(payback.multiple - 10) < 1e-9)
    }
}
