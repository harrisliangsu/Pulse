import Foundation
import Testing
@testable import Pulse

/// Which calendar days each Token spend span counts, and that the reader's own
/// dates are kept and counted as asked.
@Suite("Spend span bounds")
struct SpendSpanBoundsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: "\(text)T00:00:00Z")!
    }

    private var noCustom: ClosedRange<Date> { day("2026-01-01")...day("2026-01-01") }

    @Test("Rolling spans end today; calendar periods start at their own first day")
    func presets() {
        let now = day("2026-03-15").addingTimeInterval(13 * 3_600)
        func bounds(_ span: SpendSpan) -> (Date?, Date?) {
            let b = span.bounds(custom: noCustom, now: now, calendar: calendar)
            return (b.from, b.until)
        }
        #expect(bounds(.today) == (day("2026-03-15"), nil))
        #expect(bounds(.week) == (day("2026-03-09"), nil))
        #expect(bounds(.month) == (day("2026-02-14"), nil))
        #expect(bounds(.thisMonth) == (day("2026-03-01"), nil))
        // Last month is a closed month, stopping before this one.
        #expect(bounds(.lastMonth) == (day("2026-02-01"), day("2026-03-01")))
        #expect(bounds(.thisYear) == (day("2026-01-01"), nil))
        #expect(bounds(.all) == (nil, nil))
    }

    @Test("Last month in January is the previous December")
    func lastMonthAcrossTheYear() {
        let b = SpendSpan.lastMonth.bounds(custom: noCustom, now: day("2026-01-10"), calendar: calendar)
        #expect(b.from == day("2025-12-01"))
        #expect(b.until == day("2026-01-01"))
    }

    @Test("A custom range counts its first and last day, and one day is drawn by the hour")
    func customRange() {
        let range = day("2026-02-03").addingTimeInterval(5 * 3_600)...day("2026-02-10").addingTimeInterval(20 * 3_600)
        let b = SpendSpan.custom.bounds(custom: range, now: day("2026-03-15"), calendar: calendar)
        #expect(b.from == day("2026-02-03"))
        #expect(b.until == day("2026-02-11"))
        #expect(!SpendSpan.custom.isOneDay(custom: range, calendar: calendar))
        #expect(SpendSpan.custom.isOneDay(custom: day("2026-02-03")...day("2026-02-03"), calendar: calendar))
        #expect(SpendSpan.today.isOneDay(custom: range, calendar: calendar))
        #expect(!SpendSpan.thisMonth.isOneDay(custom: range, calendar: calendar))
    }

    @Test("A summary over last month counts that month and nothing after it")
    func summaryOverLastMonth() {
        let ledger = UsageLedger(
            days: [
                .init(date: day("2026-01-31"), tokens: 1, cost: 0, unpricedTokens: 1, models: ["m": 1]),
                .init(date: day("2026-02-10"), tokens: 10, cost: 0, unpricedTokens: 10, models: ["m": 10]),
                .init(date: day("2026-03-02"), tokens: 100, cost: 0, unpricedTokens: 100, models: ["m": 100]),
            ],
            earliest: day("2026-01-31"), unpricedModels: ["m"], modelNames: [:], slots: []
        )
        let now = day("2026-03-15")
        let b = SpendSpan.lastMonth.bounds(custom: noCustom, now: now, calendar: calendar)
        let summary = SpendSummary.of([.codex: ledger], starting: b.from, before: b.until, now: now, calendar: calendar)
        #expect(summary.tokens == 10)
        #expect(summary.days.count == 28)
        let model = ModelSpendSummary.of([.codex: ledger], named: "m", from: b.from, until: b.until, now: now, calendar: calendar)
        #expect(model.tokens == 10)
        #expect(model.days.count == 28)
    }

    @Test("The custom range is kept, and a stored range that cannot be drawn is not")
    func customRangeIsKept() {
        let (defaults, cleanup) = TestDefaults.make("spendCustomDays")
        defer { cleanup() }
        #expect(AppSettings.storedSpendCustomDays(in: defaults) == nil)

        let range = day("2026-02-03")...day("2026-02-10")
        AppSettings.storeSpendCustomDays(range, in: defaults)
        #expect(AppSettings.storedSpendCustomDays(in: defaults) == range)

        defaults.set([2.0, 1.0], forKey: "settings.spendCustomDays")
        #expect(AppSettings.storedSpendCustomDays(in: defaults) == nil)
        defaults.set("nonsense", forKey: "settings.spendCustomDays")
        #expect(AppSettings.storedSpendCustomDays(in: defaults) == nil)
    }
}
