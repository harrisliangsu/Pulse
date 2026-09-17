import Foundation
import Testing
@testable import Pulse

/// One model's drill-down, reached the way production reaches it: a reader's
/// quarter-hour buckets through the shared `UsageLedgerReader.price`, then
/// `ModelSpendSummary.of`.
///
/// The whole point is that a model's categories and hours are *its own* — two
/// models used on one day must not borrow each other's split, and an agent's
/// whole time of day must never be filed under one model's name.
///
/// Time and calendar are fixed rather than taken from the machine. The bucket
/// formatter still encodes and decodes the same instant, so the round-trip is
/// exact and the day and hour a bucket lands in are deterministic.
@Suite("Model spend summary")
struct ModelSpendSummaryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = Date(timeIntervalSince1970: 1_789_372_800)
    private static let today = calendar.startOfDay(for: now)

    private static func at(daysAgo: Int, hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    /// The same price table a production reader is handed: two raw ids that
    /// publish one display name, and one unrelated model.
    private static let prices: [String: ModelPrice] = [
        "alpha": ModelPrice(input: 1, output: 10, cacheRead: 0.1, cacheWrite: 1, name: "Alpha"),
        "alpha-1": ModelPrice(input: 1, output: 10, cacheRead: 0.1, cacheWrite: 1, name: "Alpha"),
        "alpha-2": ModelPrice(input: 1, output: 10, cacheRead: 0.1, cacheWrite: 1, name: "Alpha"),
        "beta": ModelPrice(input: 2, output: 20, cacheRead: 0, cacheWrite: 0, name: "Beta"),
    ]

    /// Rates chosen so a million tokens of each kind costs its rate in dollars:
    /// input $1, output $2, cache read $3, cache write $4 per million. Distinct
    /// on purpose — a per-kind figure read from the wrong kind is visible.
    private static let ratePrices: [String: ModelPrice] = [
        "rates": ModelPrice(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, name: "Rates"),
        // `cacheRead`/`cacheWrite` absent, so both fall back to the input rate.
        "no-cache": ModelPrice(input: 5, output: 6, cacheRead: nil, cacheWrite: nil, name: "No Cache"),
        // A real published zero: a reading of $0, not a missing price.
        "free": ModelPrice(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, name: "Free"),
    ]

    /// Two raw ids, one display name, rates a hundred-fold apart.
    private static let sharedPrices: [String: ModelPrice] = [
        "cheap": ModelPrice(input: 1, output: 0, cacheRead: 0, cacheWrite: 0, name: "Shared"),
        "dear": ModelPrice(input: 100, output: 0, cacheRead: 0, cacheWrite: 0, name: "Shared"),
    ]

    private static let million = TokenTally(
        input: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000, output: 1_000_000
    )

    /// A reader's running totals, keyed the one way `priced` parses them.
    private static func buckets(
        _ entries: [(Date, [String: TokenTally])]
    ) -> [String: [String: TokenTally]] {
        var buckets: [String: [String: TokenTally]] = [:]
        for (date, models) in entries {
            let key = UsageLedgerReader.slotKey(for: date, calendar: calendar)
            for (model, tally) in models {
                buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally
            }
        }
        return buckets
    }

    /// The production chain for a model: buckets → priced ledger.
    private static func ledger(
        _ entries: [(Date, [String: TokenTally])],
        prices: [String: ModelPrice]? = nil
    ) -> UsageLedger {
        UsageLedgerReader.price(
            Self.buckets(entries), with: prices ?? Self.prices, calendar: calendar
        )
    }

    private static func summary(
        _ ledgers: [SpendAgent: UsageLedger],
        named name: String,
        overLast span: Int?
    ) -> ModelSpendSummary {
        ModelSpendSummary.of(
            ledgers, named: name, overLast: span, now: now, calendar: calendar
        )
    }

    /// A hand-built day, for the mismatched-input regressions the readers
    /// cannot produce.
    private static func dayRecord(_ date: Date, tokens: Int, model: String) -> LedgerDay {
        LedgerDay(
            date: date, tokens: tokens, cost: 0, unpricedTokens: 0,
            models: [model: tokens], tally: TokenTally(input: tokens),
            modelTallies: [model: TokenTally(input: tokens)]
        )
    }

    // MARK: - A model's share is its own

    @Test("Two models on one day do not cross-use each other's categories or hours")
    func modelsDoNotCrossUse() {
        // The day is one `LedgerDay` with both models in it: only the raw id
        // can tell their categories apart, and only the slot can tell their
        // hours.
        let ledger = Self.ledger([
            (Self.at(daysAgo: 0, hour: 10), ["alpha": TokenTally(input: 100)]),
            (Self.at(daysAgo: 0, hour: 11), ["beta": TokenTally(input: 900, output: 5)]),
        ])

        let alpha = Self.summary([.claudeCode: ledger], named: "Alpha", overLast: 7)
        #expect(alpha.tokens == 100)
        #expect(alpha.tally == TokenTally(input: 100))
        // The hour belongs to the model whose bucket it was, not to the day.
        #expect(alpha.hours == [10: 100])

        let beta = Self.summary([.claudeCode: ledger], named: "Beta", overLast: 7)
        #expect(beta.tokens == 905)
        #expect(beta.tally == TokenTally(input: 900, output: 5))
        #expect(beta.hours == [11: 905])
    }

    @Test("One display name sums several raw ids across several agents")
    func severalRawIDsAndAgentsAreOneName() {
        let first = Self.ledger([
            (Self.at(daysAgo: 0, hour: 10), ["alpha-1": TokenTally(input: 100)])
        ])
        let second = Self.ledger([
            (Self.at(daysAgo: 1, hour: 10), ["alpha-2": TokenTally(output: 200)])
        ])
        let ledgers: [SpendAgent: UsageLedger] = [.openCode: first, .kimiCLI: second]

        let summary = Self.summary(ledgers, named: "Alpha", overLast: 7)

        #expect(summary.name == "Alpha")
        #expect(summary.tokens == 300)
        #expect(summary.tally == TokenTally(input: 100, output: 200))
        // Heaviest first.
        #expect(summary.agents.map(\.agent) == [.kimiCLI, .openCode])
        // Each raw id's categories stay with the day it was spent on.
        #expect(summary.days.first { $0.tokens == 100 }?.tally == TokenTally(input: 100))
        #expect(summary.days.first { $0.tokens == 200 }?.tally == TokenTally(output: 200))

        // The drill-down's total is the combined page's own model row, and the
        // parts add up to it.
        let combined = SpendSummary.of(ledgers, overLast: 7, now: Self.now, calendar: Self.calendar)
        #expect(combined.models.first { $0.name == "Alpha" }?.tokens == summary.tokens)
        #expect(summary.days.reduce(0) { $0 + $1.tokens } == summary.tokens)
        #expect(summary.agents.reduce(0) { $0 + $1.tokens } == summary.tokens)
    }

    @Test("Agents with equal tokens are ordered by name")
    func equalAgentsBreakTiesByName() {
        let ledger = Self.ledger([
            (Self.at(daysAgo: 0, hour: 10), ["alpha": TokenTally(input: 100)])
        ])
        let summary = Self.summary(
            [.codex: ledger, .claudeCode: ledger], named: "Alpha", overLast: 7
        )
        #expect(summary.agents.map(\.agent) == [.claudeCode, .codex])
    }

    // MARK: - The span

    @Test("The span is the calendar window, quiet days included; all-time starts at first use")
    func spanBoundariesAndQuietDays() {
        // Alpha is used today, six days ago, seven days ago *just past* the
        // week's cutoff, and nine days ago. Beta appears much earlier, so an
        // all-time window taken from the whole ledger would reach back too far.
        let alpha = Self.ledger([
            (Self.at(daysAgo: 0, hour: 12), ["alpha": TokenTally(input: 10)]),
            (Self.at(daysAgo: 6, hour: 12), ["alpha": TokenTally(input: 20)]),
            (Self.at(daysAgo: 7, hour: 12), ["alpha": TokenTally(input: 5)]),
            (Self.at(daysAgo: 9, hour: 12), ["alpha": TokenTally(input: 40)]),
        ])
        let beta = Self.ledger([
            (Self.at(daysAgo: 20, hour: 12), ["beta": TokenTally(input: 999)])
        ])
        let ledgers: [SpendAgent: UsageLedger] = [.openCode: alpha, .kimiCLI: beta]

        let todayOnly = Self.summary(ledgers, named: "Alpha", overLast: 1)
        #expect(todayOnly.tokens == 10)
        #expect(todayOnly.days.count == 1)

        let week = Self.summary(ledgers, named: "Alpha", overLast: 7)
        // The cutoff is six days back, so the record exactly seven days old is
        // out and the one six days old is in.
        #expect(week.tokens == 30)
        #expect(week.days.count == 7)
        #expect(week.activeDays == 2)
        #expect(week.days.count { $0.tokens == 0 } == 5)

        let all = Self.summary(ledgers, named: "Alpha", overLast: nil)
        // From Alpha's first day, not from the earlier Beta day the ledger also
        // holds.
        #expect(all.days.count == 10)
        #expect(all.days.first?.date == Self.calendar.startOfDay(for: Self.at(daysAgo: 9)))
        #expect(all.tokens == 75)
    }

    @Test("A model with nothing in the span is empty, not a zero-shaped series")
    func nothingInSpanIsEmpty() {
        let ledger = Self.ledger([
            (Self.at(daysAgo: 0, hour: 12), ["alpha": TokenTally(input: 10)])
        ])
        let beyond = Self.summary([.openCode: ledger], named: "beta", overLast: 7)
        #expect(beyond.isEmpty)
        #expect(beyond.days.isEmpty)
        #expect(beyond.tally == nil)
        #expect(beyond.hours == nil)
    }

    // MARK: - What may be added up

    @Test("A provider's statistics are not part of a model's priced answer")
    func providerStatisticsAreExcluded() {
        var ledger = Self.ledger([
            (Self.at(daysAgo: 0, hour: 12), ["alpha": TokenTally(input: 500)])
        ])
        ledger.origin = .providerStatistics

        let summary = Self.summary([.openCode: ledger], named: "Alpha", overLast: 7)
        #expect(summary.isEmpty)
    }

    @Test("An unpriced model still counts its tokens and keeps its categories")
    func unpricedModelsAreCounted() {
        // No price table at all: the model has no display name either, so its
        // raw id is the grouping key.
        let ledger = Self.ledger(
            [(Self.at(daysAgo: 0, hour: 10), ["mystery": TokenTally(input: 5, output: 7)])],
            prices: [:]
        )

        let summary = Self.summary([.openCode: ledger], named: "mystery", overLast: 7)
        #expect(summary.tokens == 12)
        #expect(summary.tally == TokenTally(input: 5, output: 7))
        #expect(summary.hours == [10: 12])
    }

    // MARK: - Money, at each raw id's own rates

    @Test("A model's money is each kind at its own rate, and the parts sum to the total")
    func moneyIsPerKindAndSums() {
        let ledger = Self.ledger(
            [(Self.at(daysAgo: 0, hour: 10), ["rates": Self.million])],
            prices: Self.ratePrices
        )
        let summary = Self.summary([.openCode: ledger], named: "Rates", overLast: 7)

        // $1 input, $4 cache write, $3 cache read, $2 output.
        #expect(summary.costBreakdown == TokenCost(input: 1, cacheWrite: 4, cacheRead: 3, output: 2))
        #expect(summary.cost == 10)
        #expect(summary.unpricedTokens == 0)

        let day = summary.days.first { $0.tokens > 0 }
        #expect(day?.costBreakdown == TokenCost(input: 1, cacheWrite: 4, cacheRead: 3, output: 2))
        #expect(day?.cost == 10)
        #expect(summary.agents.first?.cost == 10)
        #expect(summary.agents.first?.unpricedTokens == 0)

        // Every rollup is the same arithmetic: the day and agent slices add to
        // the model total.
        #expect(abs(summary.days.compactMap(\.cost).reduce(0, +) - (summary.cost ?? -1)) < 1e-12)
        #expect(abs(summary.agents.compactMap(\.cost).reduce(0, +) - (summary.cost ?? -1)) < 1e-12)
    }

    @Test("A missing cache rate falls back to the input rate")
    func cacheRateFallsBack() {
        let ledger = Self.ledger(
            [(Self.at(daysAgo: 0, hour: 10), [
                "no-cache": TokenTally(cacheWrite: 1_000_000, cacheRead: 1_000_000)
            ])],
            prices: Self.ratePrices
        )
        let summary = Self.summary([.openCode: ledger], named: "No Cache", overLast: 7)
        // Both cache kinds are billed at the $5 input rate.
        #expect(summary.costBreakdown == TokenCost(cacheWrite: 5, cacheRead: 5))
        #expect(summary.cost == 10)
    }

    @Test("Two models on one day do not cross money")
    func moneyDoesNotCrossModels() {
        let ledger = Self.ledger([
            (Self.at(daysAgo: 0, hour: 10), ["rates": TokenTally(input: 1_000_000)]),
            (Self.at(daysAgo: 0, hour: 11), ["no-cache": TokenTally(input: 1_000_000)]),
        ], prices: Self.ratePrices)

        #expect(Self.summary([.openCode: ledger], named: "Rates", overLast: 7).costBreakdown == TokenCost(input: 1))
        #expect(Self.summary([.openCode: ledger], named: "No Cache", overLast: 7).costBreakdown == TokenCost(input: 5))
        // The day's own money is both, which is what the models must not share.
        #expect(ledger.days.first { $0.tokens > 0 }?.cost == 6)
    }

    @Test("Two raw ids behind one name are priced separately, never merged onto one rate")
    func oneNameTwoRatesArePricedSeparately() {
        let ledger = Self.ledger([
            (Self.at(daysAgo: 0, hour: 10), ["cheap": TokenTally(input: 1_000_000)]),
            (Self.at(daysAgo: 1, hour: 10), ["dear": TokenTally(input: 1_000_000)]),
        ], prices: Self.sharedPrices)

        let summary = Self.summary([.openCode: ledger], named: "Shared", overLast: 7)
        // $1 + $100, not two million tokens at either rate.
        #expect(summary.cost == 101)
        #expect(summary.costBreakdown == TokenCost(input: 101))
    }

    @Test("Money adds across agents and follows the span")
    func moneyAcrossAgentsAndSpan() {
        let cheap = Self.ledger(
            [(Self.at(daysAgo: 0, hour: 10), ["cheap": TokenTally(input: 1_000_000)])],
            prices: Self.sharedPrices
        )
        let dear = Self.ledger(
            [(Self.at(daysAgo: 6, hour: 10), ["dear": TokenTally(input: 1_000_000)])],
            prices: Self.sharedPrices
        )
        let ledgers: [SpendAgent: UsageLedger] = [.openCode: cheap, .kimiCLI: dear]

        let today = Self.summary(ledgers, named: "Shared", overLast: 1)
        #expect(today.cost == 1)
        #expect(today.unpricedTokens == 0)

        let week = Self.summary(ledgers, named: "Shared", overLast: 7)
        #expect(week.cost == 101)
        #expect(week.agents.first { $0.agent == .kimiCLI }?.cost == 100)
        #expect(week.agents.first { $0.agent == .openCode }?.cost == 1)
    }

    @Test("A model with no price anywhere has no money to show")
    func unpricedHasNoMoney() {
        let ledger = Self.ledger(
            [(Self.at(daysAgo: 0, hour: 10), ["mystery": TokenTally(input: 5, output: 7)])],
            prices: [:]
        )
        let summary = Self.summary([.openCode: ledger], named: "mystery", overLast: 7)

        #expect(summary.cost == nil)
        #expect(summary.costBreakdown == nil)
        #expect(summary.unpricedTokens == 12)
        #expect(summary.days.first { $0.tokens > 0 }?.cost == nil)
        #expect(summary.days.first { $0.tokens > 0 }?.unpricedTokens == 12)
        #expect(summary.agents.first?.cost == nil)
        #expect(summary.agents.first?.unpricedTokens == 12)
    }

    @Test("A part-priced model shows a subtotal and the unpriced remainder")
    func partialMoneyIsASubtotal() {
        // A priced raw id and an unpriced one behind one display name — the
        // case the UI labels as a partial estimate.
        let ledger = UsageLedger(
            origin: .localTranscripts,
            days: [
                LedgerDay(
                    date: Self.today, tokens: 3_000_000, cost: 1, unpricedTokens: 2_000_000,
                    models: ["known": 1_000_000, "unknown": 2_000_000],
                    tally: TokenTally(input: 3_000_000),
                    modelTallies: [
                        "known": TokenTally(input: 1_000_000),
                        "unknown": TokenTally(input: 2_000_000),
                    ],
                    modelCosts: ["known": TokenCost(input: 1)]
                )
            ],
            earliest: Self.today,
            unpricedModels: ["unknown"],
            modelNames: ["known": "Mix", "unknown": "Mix"],
            slots: []
        )
        let summary = Self.summary([.openCode: ledger], named: "Mix", overLast: 7)

        #expect(summary.cost == 1)
        #expect(summary.unpricedTokens == 2_000_000)
        #expect(summary.days.first { $0.tokens > 0 }?.cost == 1)
        #expect(summary.days.first { $0.tokens > 0 }?.unpricedTokens == 2_000_000)
        #expect(summary.agents.first?.cost == 1)
        #expect(summary.agents.first?.unpricedTokens == 2_000_000)
    }

    @Test("A real zero rate is a reading of zero, not a missing price")
    func zeroRateIsNotNil() {
        let ledger = Self.ledger(
            [(Self.at(daysAgo: 0, hour: 10), ["free": TokenTally(input: 1_000_000)])],
            prices: Self.ratePrices
        )
        let summary = Self.summary([.openCode: ledger], named: "Free", overLast: 7)

        #expect(summary.cost == 0)
        #expect(summary.costBreakdown == TokenCost())
        #expect(summary.unpricedTokens == 0)
        #expect(summary.days.first { $0.tokens > 0 }?.cost == 0)
        #expect(summary.agents.first?.cost == 0)
    }

    @Test("Missing or incomplete money metadata is counted, never invented")
    func missingMetaIsCountedNotCosted() {
        // Money was never saved (an old cache): counted, unpriced, not $0.
        let noMoney = UsageLedger(
            origin: .localTranscripts,
            days: [
                LedgerDay(
                    date: Self.today, tokens: 1_000_000, cost: 0, unpricedTokens: 0,
                    models: ["alpha": 1_000_000],
                    tally: TokenTally(input: 1_000_000),
                    modelTallies: ["alpha": TokenTally(input: 1_000_000)]
                )
            ],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: []
        )
        let old = Self.summary([.openCode: noMoney], named: "Alpha", overLast: 7)
        #expect(old.tokens == 1_000_000)
        #expect(old.cost == nil)
        #expect(old.unpricedTokens == 1_000_000)

        // Money present but the category detail does not match the tokens: the
        // split cannot be trusted, so the money is not shown either.
        let mismatched = UsageLedger(
            origin: .localTranscripts,
            days: [
                LedgerDay(
                    date: Self.today, tokens: 500, cost: 0, unpricedTokens: 0,
                    models: ["alpha": 500],
                    tally: TokenTally(input: 100),
                    modelTallies: ["alpha": TokenTally(input: 100)],
                    modelCosts: ["alpha": TokenCost(input: 1)]
                )
            ],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: []
        )
        let incomplete = Self.summary([.openCode: mismatched], named: "Alpha", overLast: 7)
        #expect(incomplete.tokens == 500)
        #expect(incomplete.cost == nil)
        #expect(incomplete.unpricedTokens == 500)
    }

    // MARK: - Old data has no detail, and must say so

    @Test("Without per-model detail the totals stay and categories and hours go missing")
    func missingModelDetailIsNotZero() {
        let real = Self.ledger([
            (Self.at(daysAgo: 0, hour: 10), ["alpha": TokenTally(input: 100)])
        ])
        // The shape a cache written before the detail existed decodes to: the
        // day's model totals are there, the per-model split, slot models and
        // money are not.
        let stripped = UsageLedger(
            origin: .localTranscripts,
            days: real.days.map {
                LedgerDay(
                    date: $0.date, tokens: $0.tokens, cost: $0.cost,
                    unpricedTokens: $0.unpricedTokens, models: $0.models,
                    tally: $0.tally, modelTallies: [:], modelCosts: [:]
                )
            },
            earliest: real.earliest,
            unpricedModels: real.unpricedModels,
            modelNames: real.modelNames,
            slots: real.slots.map {
                .init(start: $0.start, tokens: $0.tokens, cost: $0.cost, models: [:])
            }
        )

        let summary = Self.summary([.openCode: stripped], named: "Alpha", overLast: 7)
        // The token question is still answered...
        #expect(summary.tokens == 100)
        // ...but the split, the hours and the money were never saved, so they
        // are nil rather than a total read as one kind.
        #expect(summary.tally == nil)
        #expect(summary.hours == nil)
        #expect(summary.cost == nil)
        #expect(summary.unpricedTokens == 100)
    }

    @Test("Hours are withheld when the slot buckets do not reconcile with the days")
    func hoursNeedReconciliation() {
        // Both models kept their daily detail, but only `beta` kept slot
        // detail: an hour series built from this would file `beta`'s time of
        // day under `alpha` too.
        let slot = Self.at(daysAgo: 0, hour: 10)
        let ledger = UsageLedger(
            origin: .localTranscripts,
            days: [
                LedgerDay(
                    date: Self.today, tokens: 300, cost: 0, unpricedTokens: 0,
                    models: ["alpha": 100, "beta": 200],
                    tally: TokenTally(input: 300),
                    modelTallies: [
                        "alpha": TokenTally(input: 100),
                        "beta": TokenTally(input: 200),
                    ]
                )
            ],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha", "beta": "Beta"],
            slots: [.init(start: slot, tokens: 300, cost: 0, models: ["beta": TokenTally(input: 200)])]
        )

        let alpha = Self.summary([.openCode: ledger], named: "Alpha", overLast: 7)
        // Its own daily split is intact...
        #expect(alpha.tokens == 100)
        #expect(alpha.tally == TokenTally(input: 100))
        // ...but its hours cannot be told from the agent's, so they are nil.
        #expect(alpha.hours == nil)
    }

    @Test("One agent's overcount cannot cancel another agent's missing detail")
    func crossAgentCancellationWithholdsHours() {
        // A total-only check passes here: the day figures add to 200 and the
        // slot figures add to 200. But A's slots double its own day and B's
        // slots are missing entirely, so the profile is not the model's.
        let slot = Self.at(daysAgo: 0, hour: 10)
        let overcounted = UsageLedger(
            origin: .localTranscripts,
            days: [Self.dayRecord(Self.today, tokens: 100, model: "alpha")],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: [.init(start: slot, tokens: 200, cost: 0, models: ["alpha": TokenTally(input: 200)])]
        )
        let missing = UsageLedger(
            origin: .localTranscripts,
            days: [Self.dayRecord(Self.today, tokens: 100, model: "alpha")],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: [.init(start: slot, tokens: 100, cost: 0, models: [:])]
        )

        let summary = Self.summary(
            [.openCode: overcounted, .kimiCLI: missing], named: "Alpha", overLast: 7
        )
        #expect(summary.tokens == 200)
        #expect(summary.tally == TokenTally(input: 200))
        #expect(summary.hours == nil)
    }

    @Test("Tokens swapped between two days of one agent withhold the hours")
    func crossDayCancellationWithholdsHours() {
        // Day totals add to 200 and slot totals add to 200, so a total-only
        // check passes — but neither day's buckets match that day's own total,
        // so the hours are a redistribution nobody measured.
        let yesterday = Self.calendar.date(byAdding: .day, value: -1, to: Self.today)!
        let ledger = UsageLedger(
            origin: .localTranscripts,
            days: [
                Self.dayRecord(Self.today, tokens: 100, model: "alpha"),
                Self.dayRecord(yesterday, tokens: 100, model: "alpha"),
            ],
            earliest: yesterday,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: [
                .init(
                    start: Self.at(daysAgo: 0, hour: 10), tokens: 50, cost: 0,
                    models: ["alpha": TokenTally(input: 50)]
                ),
                .init(
                    start: Self.at(daysAgo: 1, hour: 10), tokens: 150, cost: 0,
                    models: ["alpha": TokenTally(input: 150)]
                ),
            ]
        )

        let summary = Self.summary([.openCode: ledger], named: "Alpha", overLast: 7)
        #expect(summary.tokens == 200)
        #expect(summary.tally == TokenTally(input: 200))
        #expect(summary.hours == nil)
    }

    @Test("A model whose totals do not match its categories gets no tally")
    func mismatchedTalliesAreNotShown() {
        // The day says 500 tokens but the only split kept adds to 100: reading
        // it would understate the model.
        let ledger = UsageLedger(
            origin: .localTranscripts,
            days: [
                LedgerDay(
                    date: Self.today, tokens: 500, cost: 0, unpricedTokens: 0,
                    models: ["alpha": 500], tally: TokenTally(input: 100),
                    modelTallies: ["alpha": TokenTally(input: 100)]
                )
            ],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: []
        )

        let summary = Self.summary([.openCode: ledger], named: "Alpha", overLast: 7)
        #expect(summary.tokens == 500)
        #expect(summary.tally == nil)
    }

    @Test("Negative or overflowing metadata is counted unpriced, never priced or crashed on")
    func hostileMetadataIsCountedNotCosted() {
        // The three kinds plus the remainder do not fit an Int. Reading
        // `TokenTally.total` at all used to trap.
        let overflowing = UsageLedger(
            origin: .localTranscripts,
            days: [
                LedgerDay(
                    date: Self.today, tokens: 500, cost: 0, unpricedTokens: 0,
                    models: ["alpha": 500],
                    tally: TokenTally(input: Int.max, output: 1),
                    modelTallies: ["alpha": TokenTally(input: Int.max, output: 1)],
                    modelCosts: ["alpha": TokenCost(input: 1)]
                )
            ],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: []
        )
        let overflow = Self.summary([.openCode: overflowing], named: "Alpha", overLast: 7)
        #expect(overflow.tokens == 500)
        #expect(overflow.cost == nil)
        #expect(overflow.tally == nil)
        #expect(overflow.unpricedTokens == 500)

        // A negative remainder used to be clamped to zero, which let the split
        // pass and the money through. It is broken data instead.
        let negative = UsageLedger(
            origin: .localTranscripts,
            days: [
                LedgerDay(
                    date: Self.today, tokens: 500, cost: 0, unpricedTokens: 0,
                    models: ["alpha": 500],
                    tally: TokenTally(input: 500),
                    modelTallies: ["alpha": TokenTally(input: 500)],
                    modelCosts: ["alpha": TokenCost(input: 1)],
                    modelUnclassifiedTokens: ["alpha": -100]
                )
            ],
            earliest: Self.today,
            unpricedModels: [],
            modelNames: ["alpha": "Alpha"],
            slots: []
        )
        let negativeRemainder = Self.summary([.openCode: negative], named: "Alpha", overLast: 7)
        #expect(negativeRemainder.tokens == 500)
        #expect(negativeRemainder.cost == nil)
        #expect(negativeRemainder.tally == nil)
        #expect(negativeRemainder.unpricedTokens == 500)
    }
}

/// The day table's ordering, held to the rule the view relies on: a missing
/// category or price is not a zero, so it never sorts among the zeroes.
@Suite("Model day sorting")
struct ModelSpendSummarySortingTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = Date(timeIntervalSince1970: 1_789_372_800)
    private static let today = calendar.startOfDay(for: now)

    /// A day at a fixed offset, so the date tie-break is deterministic.
    private static func day(_ offset: Int, tokens: Int, tally: TokenTally?) -> ModelSpendSummary.Day {
        ModelSpendSummary.Day(
            date: calendar.date(byAdding: .day, value: offset, to: today)!,
            tokens: tokens,
            tally: tally
        )
    }

    /// A day with a known cost, for the money column.
    private static func costDay(_ offset: Int, cost: Double) -> ModelSpendSummary.Day {
        ModelSpendSummary.Day(
            date: calendar.date(byAdding: .day, value: offset, to: today)!,
            tokens: 1,
            tally: TokenTally(input: 1),
            costBreakdown: TokenCost(input: cost)
        )
    }

    @Test("A missing category sorts last in both directions; a real zero sorts as zero")
    func missingSortsLastAndZeroSorts() {
        // Oldest has a real 0 input, the middle two are tied at 5, and the
        // newest has no split at all.
        let zero = Self.day(0, tokens: 10, tally: TokenTally(input: 0))
        let tiedOlder = Self.day(1, tokens: 20, tally: TokenTally(input: 5))
        let tiedNewer = Self.day(2, tokens: 30, tally: TokenTally(input: 5))
        let missing = Self.day(3, tokens: 40, tally: nil)
        let days = [zero, tiedOlder, tiedNewer, missing]

        let ascending = ModelSpendSummary.sorted(days, by: .input, ascending: true)
        // 0 first, then the two 5s oldest-first, then the nil.
        #expect(ascending.map(\.date) == [zero.date, tiedOlder.date, tiedNewer.date, missing.date])

        let descending = ModelSpendSummary.sorted(days, by: .input, ascending: false)
        // The two 5s newest-first, then the real 0, then the nil last again.
        #expect(descending.map(\.date) == [tiedNewer.date, tiedOlder.date, zero.date, missing.date])
    }

    @Test("The total column is never missing, so a quiet day takes its real place")
    func zeroTotalSortsNormally() {
        let quiet = Self.day(0, tokens: 0, tally: nil)
        let busyOlder = Self.day(1, tokens: 100, tally: nil)
        let busyNewer = Self.day(2, tokens: 100, tally: nil)
        let days = [quiet, busyOlder, busyNewer]

        let ascending = ModelSpendSummary.sorted(days, by: .total, ascending: true)
        #expect(ascending.map(\.date) == [quiet.date, busyOlder.date, busyNewer.date])

        let descending = ModelSpendSummary.sorted(days, by: .total, ascending: false)
        // Equal totals keep a deterministic order, most recent first.
        #expect(descending.map(\.date) == [busyNewer.date, busyOlder.date, quiet.date])
    }

    @Test("The date column has no missing values and follows the arrow")
    func dateColumnFollowsArrow() {
        let oldest = Self.day(0, tokens: 1, tally: TokenTally(input: 1))
        let middle = Self.day(1, tokens: 2, tally: TokenTally(input: 2))
        let newest = Self.day(2, tokens: 3, tally: TokenTally(input: 3))
        let days = [middle, newest, oldest]

        #expect(
            ModelSpendSummary.sorted(days, by: .date, ascending: true).map(\.date)
                == [oldest.date, middle.date, newest.date]
        )
        #expect(
            ModelSpendSummary.sorted(days, by: .date, ascending: false).map(\.date)
                == [newest.date, middle.date, oldest.date]
        )
    }

    @Test("The cost column keeps fractional money, sorts a real zero, and holds nil last")
    func costColumnSortsDecimalsAndNil() {
        let missing = Self.day(0, tokens: 10, tally: nil)     // never priced -> nil
        let zero = Self.costDay(1, cost: 0)                   // a real $0
        let small = Self.costDay(2, cost: 0.001)              // sub-cent, not truncated
        let large = Self.costDay(3, cost: 100.5)
        let days = [missing, large, zero, small]

        let ascending = ModelSpendSummary.sorted(days, by: .cost, ascending: true)
        #expect(ascending.map(\.date) == [zero.date, small.date, large.date, missing.date])

        let descending = ModelSpendSummary.sorted(days, by: .cost, ascending: false)
        #expect(descending.map(\.date) == [large.date, small.date, zero.date, missing.date])
    }

    @Test("Large token counts sort by exact value, not by a widened Double")
    func largeTokenCountsKeepTheirPrecision() {
        // Two adjacent integers above 2^53, which a `Double` cannot tell
        // apart. The larger is the *older* day, so a comparison that ties and
        // falls back to the date breaks the order in one direction and hides
        // the other.
        let low = 9_007_199_254_740_992
        let high = low + 1
        let lowDay = Self.day(0, tokens: low, tally: TokenTally(input: low))
        let highDay = Self.day(1, tokens: high, tally: TokenTally(input: high))
        let days = [lowDay, highDay]

        #expect(
            ModelSpendSummary.sorted(days, by: .total, ascending: true).map(\.tokens)
                == [low, high]
        )
        #expect(
            ModelSpendSummary.sorted(days, by: .total, ascending: false).map(\.tokens)
                == [high, low]
        )
        #expect(
            ModelSpendSummary.sorted(days, by: .input, ascending: true).map(\.tally?.input)
                == [low, high]
        )
        #expect(
            ModelSpendSummary.sorted(days, by: .input, ascending: false).map(\.tally?.input)
                == [high, low]
        )
    }
}
