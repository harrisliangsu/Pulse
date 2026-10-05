import AppKit
import SwiftUI
import Foundation
import Testing
@testable import Pulse

/// What the recap window offers and decides, on a fixed clock and a UTC
/// calendar: which periods, which one it opens on, what a typed price means,
/// and when the "recap is ready" notification may be said.
@Suite("Recap window")
struct RecapWindowTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func month(_ year: Int, _ month: Int) -> Recap.Period { .month(year: year, month: month) }

    // MARK: - Which periods

    @Test("Months run from the earliest record to now, newest first")
    func offeredMonths() {
        let months = RecapPeriods.months(earliest: Self.at(2026, 7, 20), now: Self.at(2026, 10, 5), calendar: Self.calendar)
        #expect(months == [Self.month(2026, 10), Self.month(2026, 9), Self.month(2026, 8), Self.month(2026, 7)])
    }

    @Test("Months cross a year boundary without skipping")
    func monthsAcrossYears() {
        let months = RecapPeriods.months(earliest: Self.at(2025, 11, 3), now: Self.at(2026, 2, 9), calendar: Self.calendar)
        #expect(months == [Self.month(2026, 2), Self.month(2026, 1), Self.month(2025, 12), Self.month(2025, 11)])
    }

    @Test("With no record known only this month is offered, and a future record offers nothing later")
    func offeredWithoutRecords() {
        let now = Self.at(2026, 10, 5)
        #expect(RecapPeriods.months(earliest: nil, now: now, calendar: Self.calendar) == [Self.month(2026, 10)])
        #expect(RecapPeriods.months(earliest: Self.at(2027, 3, 1), now: now, calendar: Self.calendar) == [Self.month(2026, 10)])
        #expect(RecapPeriods.years(earliest: nil, now: now, calendar: Self.calendar) == [.year(2026)])
    }

    @Test("Years run from the earliest record's year to this one")
    func offeredYears() {
        let years = RecapPeriods.years(earliest: Self.at(2024, 12, 31), now: Self.at(2026, 10, 5), calendar: Self.calendar)
        #expect(years == [.year(2026), .year(2025), .year(2024)])
    }

    // MARK: - Which one it opens on

    @Test("The first seven days open on the month that just ended; after that, the running one")
    func defaultMonth() {
        let earliest = Self.at(2026, 1, 10)
        func open(_ day: Int) -> Recap.Period {
            RecapPeriods.defaultMonth(earliest: earliest, now: Self.at(2026, 10, day), calendar: Self.calendar)
        }
        #expect(open(1) == Self.month(2026, 9))
        #expect(open(7) == Self.month(2026, 9))
        #expect(open(8) == Self.month(2026, 10))
        #expect(open(31) == Self.month(2026, 10))
    }

    @Test("In January the month that just ended is December of the year before")
    func defaultMonthInJanuary() {
        let open = RecapPeriods.defaultMonth(earliest: Self.at(2025, 3, 1), now: Self.at(2026, 1, 4), calendar: Self.calendar)
        #expect(open == Self.month(2025, 12))
    }

    @Test("The default never falls before the earliest record")
    func defaultMonthIsClamped() {
        // Records begin on October 1; asked on the 3rd, September is not offered.
        let open = RecapPeriods.defaultMonth(earliest: Self.at(2026, 10, 1), now: Self.at(2026, 10, 3), calendar: Self.calendar)
        #expect(open == Self.month(2026, 10))
        // And with nothing known it is simply the rule.
        #expect(RecapPeriods.defaultMonth(earliest: nil, now: Self.at(2026, 10, 3), calendar: Self.calendar) == Self.month(2026, 9))
        #expect(RecapPeriods.defaultMonth(earliest: nil, now: Self.at(2026, 10, 9), calendar: Self.calendar) == Self.month(2026, 10))
    }

    @Test("The year opens on the one that just ended during the first week of January only")
    func defaultYear() {
        let earliest = Self.at(2024, 5, 1)
        func open(_ month: Int, _ day: Int) -> Recap.Period {
            RecapPeriods.defaultYear(earliest: earliest, now: Self.at(2026, month, day), calendar: Self.calendar)
        }
        #expect(open(1, 3) == .year(2025))
        #expect(open(1, 7) == .year(2025))
        #expect(open(1, 8) == .year(2026))
        #expect(open(10, 3) == .year(2026))
    }

    @Test("Switching kind keeps the year, and lands on the last offered month of it")
    func switchingKind() {
        let now = Self.at(2026, 10, 5)
        let earliest = Self.at(2025, 3, 1)
        #expect(RecapPeriods.switched(Self.month(2025, 6), earliest: earliest, now: now, calendar: Self.calendar) == .year(2025))
        #expect(RecapPeriods.switched(.year(2025), earliest: earliest, now: now, calendar: Self.calendar) == Self.month(2025, 12))
        // The running year ends on the running month.
        #expect(RecapPeriods.switched(.year(2026), earliest: earliest, now: now, calendar: Self.calendar) == Self.month(2026, 10))
    }

    @Test("A period's key round-trips")
    func periodKey() {
        #expect(Self.month(2026, 9).key == "2026-09")
        #expect(Recap.Period(key: "2026-09") == Self.month(2026, 9))
        #expect(Recap.Period.year(2026).key == "2026")
        #expect(Recap.Period(key: "2026") == .year(2026))
        #expect(Recap.Period(key: "soon") == nil)
    }

    // MARK: - The price

    @Test("Nothing typed is no price, and so is zero")
    func emptyPrice() {
        let us = Locale(identifier: "en_US")
        #expect(RecapPrice.entry("", locale: us) == .none)
        #expect(RecapPrice.entry("   ", locale: us) == .none)
        #expect(RecapPrice.entry("0", locale: us) == .none)
        #expect(RecapPrice.entry("$", locale: us) == .none)
    }

    @Test("An amount is read the way it was typed, with or without the dollar sign")
    func typedPrice() {
        let us = Locale(identifier: "en_US")
        #expect(RecapPrice.entry("200", locale: us) == .amount(200))
        #expect(RecapPrice.entry("$20", locale: us) == .amount(20))
        #expect(RecapPrice.entry(" 17.5 ", locale: us) == .amount(17.5))
        #expect(RecapPrice.entry("1,200", locale: us) == .amount(1200))
        #expect(RecapPrice.entry("12,5", locale: Locale(identifier: "de_DE")) == .amount(12.5))
    }

    @Test("A negative amount, a word and more than the maximum are refused")
    func refusedPrice() {
        let us = Locale(identifier: "en_US")
        #expect(RecapPrice.entry("-5", locale: us) == .refused)
        #expect(RecapPrice.entry("1.2.3", locale: us) == .refused)
        #expect(RecapPrice.entry("10001", locale: us) == .refused)
        #expect(RecapPrice.entry("10000", locale: us) == .amount(10_000))
    }

    @Test("The kept price is nil unless it is a positive amount within range")
    func normalizedPrice() {
        #expect(RecapPrice.normalized(nil) == nil)
        #expect(RecapPrice.normalized(0) == nil)
        #expect(RecapPrice.normalized(-1) == nil)
        #expect(RecapPrice.normalized(.infinity) == nil)
        #expect(RecapPrice.normalized(.nan) == nil)
        #expect(RecapPrice.normalized(20_000) == nil)
        #expect(RecapPrice.normalized(20) == 20)
        #expect(RecapPrice.text(17.5, locale: Locale(identifier: "en_US")) == "17.5")
        #expect(RecapPrice.text(1200, locale: Locale(identifier: "en_US")) == "1200")
        #expect(RecapPrice.text(nil) == "")
    }

    @Test("The settings keep, clear and persist the recap choices")
    @MainActor
    func settingsPersist() {
        let keys = ["settings.recapMonthlyPrice", "settings.recapHidesProjects", "settings.alertsOnRecap", "settings.recapAnnouncedMonth"]
        defer { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

        let settings = AppSettings()
        #expect(settings.recapMonthlyPrice == nil)
        #expect(!settings.recapHidesProjects, "names are shown unless the reader hides them")
        #expect(!settings.alertsOnRecap, "off by default")

        settings.recapMonthlyPrice = 200
        #expect(UserDefaults.standard.double(forKey: "settings.recapMonthlyPrice") == 200)
        settings.recapMonthlyPrice = -3
        #expect(settings.recapMonthlyPrice == nil)
        #expect(UserDefaults.standard.object(forKey: "settings.recapMonthlyPrice") == nil, "a refused price is not left on disk")
        settings.recapMonthlyPrice = 20
        settings.recapMonthlyPrice = 0
        #expect(settings.recapMonthlyPrice == nil)
        #expect(UserDefaults.standard.object(forKey: "settings.recapMonthlyPrice") == nil)

        settings.recapHidesProjects = true
        #expect(UserDefaults.standard.bool(forKey: "settings.recapHidesProjects"))

        var changes = 0
        settings.onRecapAlertChange = { changes += 1 }
        settings.alertsOnRecap = true
        settings.alertsOnRecap = true
        #expect(changes == 1)
        #expect(settings.wantsAlerts, "permission is worth asking for")
        #expect(!settings.wantsUsageAlerts, "and no reading is tracked for it")
    }

    // MARK: - The notification

    private let september = Recap.Period.month(year: 2026, month: 9)

    @Test("On the 1st, with records last month and nothing announced, September is announced")
    func announcesOnTheFirst() {
        let due = RecapNoticeRule.due(
            now: Self.at(2026, 10, 1, 9), announced: nil, tokens: { _ in 1_000 }, calendar: Self.calendar
        )
        #expect(due == september)
    }

    @Test("Once per month: the one already announced is not announced again")
    func onlyOncePerMonth() {
        for day in 1...3 {
            let due = RecapNoticeRule.due(
                now: Self.at(2026, 10, day), announced: september, tokens: { _ in 1_000 }, calendar: Self.calendar
            )
            #expect(due == nil, "day \(day)")
        }
        // The next month is news again.
        let next = RecapNoticeRule.due(
            now: Self.at(2026, 11, 2), announced: september, tokens: { _ in 1_000 }, calendar: Self.calendar
        )
        #expect(next == .month(year: 2026, month: 10))
    }

    @Test("Only for a month that had records")
    func onlyWithRecords() {
        let now = Self.at(2026, 10, 1)
        #expect(RecapNoticeRule.due(now: now, announced: nil, tokens: { _ in 0 }, calendar: Self.calendar) == nil)
        // Nothing read yet is not "no records": nothing is said either way.
        #expect(RecapNoticeRule.due(now: now, announced: nil, tokens: { _ in nil }, calendar: Self.calendar) == nil)
    }

    @Test("Only in the first days of a month, and only about the month before")
    func onlyInTheWindow() {
        func due(_ month: Int, _ day: Int) -> Recap.Period? {
            RecapNoticeRule.due(now: Self.at(2026, month, day), announced: nil, tokens: { _ in 1 }, calendar: Self.calendar)
        }
        #expect(due(10, 3) == september)
        #expect(due(10, 4) == nil)
        #expect(due(10, 15) == nil)
        #expect(due(1, 2) == .month(year: 2025, month: 12))
    }

    @Test("The tokens are asked about the month announced, and only inside the window")
    func asksAboutLastMonth() {
        var asked: [Recap.Period] = []
        _ = RecapNoticeRule.due(now: Self.at(2026, 10, 2), announced: nil, tokens: { asked.append($0); return 1 }, calendar: Self.calendar)
        #expect(asked == [september])
        asked = []
        _ = RecapNoticeRule.due(now: Self.at(2026, 10, 20), announced: nil, tokens: { asked.append($0); return 1 }, calendar: Self.calendar)
        #expect(asked.isEmpty, "outside the window nothing is even counted")
    }

    @Test("A notification's identifier names its month, so a click can open it")
    func identifierRoundTrip() {
        let identifier = RecapNoticeRule.identifier(for: september)
        #expect(identifier == "recap-ready-2026-09")
        #expect(RecapNoticeRule.period(fromIdentifier: identifier) == september)
        #expect(RecapNoticeRule.period(fromIdentifier: "acct|window|spent") == nil)
        #expect(RecapNoticeRule.period(fromIdentifier: "recap-ready-never") == nil)
    }

    // MARK: - The window's own state

    @Test("With Token spend reading off the window reads nothing and says so")
    @MainActor
    func readingOffReadsNothing() {
        let settings = AppSettings()
        #expect(!settings.readsTokenSpend)
        let model = RecapWindowModel(settings: settings, now: { Self.at(2026, 10, 3) })
        #expect(model.phase == .needsReading)
        model.begin(on: nil)
        #expect(model.phase == .needsReading)
        #expect(model.recap == nil)
        #expect(model.deck == nil)
    }

    @Test("The card on screen is kept by identity, and falls back to the first when it goes")
    @MainActor
    func cardIsKeptByIdentity() {
        let settings = AppSettings()
        let model = RecapWindowModel.preview(
            settings: settings, phase: .ready, period: .month(year: 2026, month: 9),
            recap: RecapSamples.month(), card: .scorecard
        )
        let deck = RecapDeck(recap: RecapSamples.month(), monthlyPrice: nil, hidesProjects: false)
        #expect(model.currentCard(in: deck) == .scorecard)
        // The same card with a price typed: a payback card now sits before it.
        let priced = RecapDeck(recap: RecapSamples.month(), monthlyPrice: 200, hidesProjects: false)
        #expect(priced.cards.contains(.payback))
        #expect(model.currentCard(in: priced) == .scorecard)
        // A card the deck does not have is the first one.
        model.card = .yearCalendar
        #expect(model.currentCard(in: deck) == deck.cards.first)
    }

    @Test("Stepping stops at both ends of the deck")
    @MainActor
    func steppingStopsAtTheEnds() {
        let model = RecapWindowModel.preview(
            settings: AppSettings(), phase: .ready, period: .month(year: 2026, month: 9), recap: RecapSamples.month()
        )
        let deck = RecapDeck(recap: RecapSamples.month(), monthlyPrice: nil, hidesProjects: false)
        model.step(-1, in: deck)
        #expect(model.currentCard(in: deck) == deck.cards[0])
        model.step(1, in: deck)
        #expect(model.currentCard(in: deck) == deck.cards[1])
        for _ in 0..<deck.cards.count + 3 { model.step(1, in: deck) }
        #expect(model.currentCard(in: deck) == deck.cards.last)
    }

    @Test("Month and Year choices list their own periods, with an asked-for one kept")
    @MainActor
    func offeredFollowsKind() {
        let model = RecapWindowModel.preview(
            settings: AppSettings(), phase: .ready, period: .month(year: 2024, month: 2), recap: nil,
            earliest: Self.at(2026, 9, 1), now: { Self.at(2026, 10, 3) }
        )
        // Asked for a month before the earliest record: still listed, first.
        #expect(model.offered.first == .month(year: 2024, month: 2))
        #expect(model.offered.contains(.month(year: 2026, month: 9)))
        #expect(!model.isYear)
    }

    // MARK: - The keys

    @Test("← and → turn the page alone, and not while a field is being edited")
    @MainActor
    func arrowKeys() throws {
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
            ))
        }
        #expect(RecapWindow.direction(of: try key(123), editing: false) == -1)
        #expect(RecapWindow.direction(of: try key(124), editing: false) == 1)
        #expect(RecapWindow.direction(of: try key(124), editing: true) == nil)
        #expect(RecapWindow.direction(of: try key(124, .command), editing: false) == nil)
        #expect(RecapWindow.direction(of: try key(124, .shift), editing: false) == nil)
        #expect(RecapWindow.direction(of: try key(0), editing: false) == nil)
    }
}

/// The recap window's own chrome drawn to PNG, for a person to look at.
///
///     PULSE_RECAP_WINDOW_PREVIEW=/tmp/recap-window swift test --filter RecapWindowRenderTests
///
/// Hosted in a window that is never shown and drawn with `cacheDisplay`, which —
/// unlike `ImageRenderer` — also draws AppKit-backed controls (the pickers, the
/// field, the switch). It pins nothing about pixels.
@MainActor
@Suite("Recap window render", .serialized)
struct RecapWindowRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_RECAP_WINDOW_PREVIEW"] != nil))
    func renderTheStates() throws {
        let destination = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_RECAP_WINDOW_PREVIEW"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { LocalizationSource.use(.system) }

        let september = Recap.Period.month(year: 2026, month: 9)
        let cases: [(String, AppLanguage, RecapWindowModel)] = [
            ("ready-en", .english, .preview(settings: AppSettings(), phase: .ready, period: september, recap: RecapSamples.month())),
            ("ready-zh-Hans", .chineseSimplified, .preview(settings: AppSettings(), phase: .ready, period: september, recap: RecapSamples.month())),
            ("ready-year-en", .english, .preview(settings: AppSettings(), phase: .ready, period: .year(2026), recap: RecapSamples.year())),
            ("scorecard-ja", .japanese, .preview(settings: AppSettings(), phase: .ready, period: september, recap: RecapSamples.month(), card: .scorecard)),
            ("reading-off-en", .english, .preview(settings: AppSettings(), phase: .needsReading, period: september)),
            ("reading-off-zh-Hans", .chineseSimplified, .preview(settings: AppSettings(), phase: .needsReading, period: september)),
            ("loading-en", .english, .preview(
                settings: AppSettings(), phase: .loading, period: september,
                progress: .init(agent: "Claude Code", index: 3, total: 12))),
            ("loading-first-en", .english, .preview(settings: AppSettings(), phase: .loading, period: september)),
            ("empty-en", .english, .preview(settings: AppSettings(), phase: .ready, period: .month(year: 2026, month: 8), earliest: Date())),
            ("empty-ko", .korean, .preview(settings: AppSettings(), phase: .ready, period: .month(year: 2026, month: 8), earliest: Date())),
            ("failed-en", .english, .preview(settings: AppSettings(), phase: .failed, period: september)),
        ]

        for (name, language, model) in cases {
            LocalizationSource.use(language)
            let settings = model.settings
            let hosting = NSHostingView(rootView: RecapWindowView(model: model, settings: settings, openTokenSpend: {}))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 940, height: 800), styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentView = hosting
            window.setContentSize(NSSize(width: 940, height: 800))
            hosting.layoutSubtreeIfNeeded()
            // One turn of the run loop so SwiftUI has laid the content out.
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: destination.appendingPathComponent("\(name).png"))
        }
    }
}
