// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Testing
@testable import Pulse

/// Which limit the card's exhaustion line and the remaining-time notices may use.
@Suite("Exhaustion estimate windows")
struct ExhaustionEstimateTests {
    private static func window(
        _ id: String,
        kind: UsageWindow.Kind,
        seconds: Int,
        reportsLength: Bool = true
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: 0.4,
            windowSeconds: seconds,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
            reportsLength: reportsLength
        )
    }

    @Test("A weekly limit is the only one used, including when a five-hour window is beside it")
    func weeklyBeatsFiveHour() {
        let five = Self.window("5h", kind: .fiveHour, seconds: 18_000)
        let week = Self.window("week", kind: .weekly, seconds: 604_800)
        let chosen = ExhaustionEstimate.windows(in: [five, week])
        #expect(chosen.map(\.id) == ["week"])
        #expect(ExhaustionEstimate.includes(week, among: [five, week]))
        #expect(!ExhaustionEstimate.includes(five, among: [five, week]))
    }

    @Test("Every weekly limit is kept, and a longer month does not replace them")
    func everyWeekly() {
        let first = Self.window("a", kind: .weekly, seconds: 604_800)
        let second = Self.window("b", kind: .weekly, seconds: 604_800, reportsLength: false)
        let month = Self.window("month", kind: .monthly, seconds: 30 * 86_400)
        #expect(ExhaustionEstimate.windows(in: [month, first, second]).map(\.id) == ["a", "b"])
    }

    @Test("Without a weekly limit, the longest stated limit is the one")
    func longestFallback() {
        let day = Self.window("day", kind: .daily, seconds: 86_400)
        let month = Self.window("month", kind: .monthly, seconds: 30 * 86_400)
        #expect(ExhaustionEstimate.windows(in: [day, month]).map(\.id) == ["month"])

        let onlyDay = ExhaustionEstimate.windows(in: [day])
        #expect(onlyDay.map(\.id) == ["day"])
    }

    @Test("Equal lengths keep the earlier id")
    func tieKeepsTheEarlierId() {
        let later = Self.window("b", kind: .daily, seconds: 86_400)
        let earlier = Self.window("a", kind: .monthly, seconds: 86_400)
        #expect(ExhaustionEstimate.windows(in: [later, earlier]).map(\.id) == ["a"])
    }

    @Test("A five-hour window is never the fallback, including when its kind is not five hours")
    func fiveHourOnlyIsNothing() {
        let five = Self.window("5h", kind: .fiveHour, seconds: 18_000)
        #expect(ExhaustionEstimate.windows(in: [five]).isEmpty)

        let mislabelled = Self.window("odd", kind: .daily, seconds: ExhaustionEstimate.fiveHourSeconds)
        let week = Self.window("week", kind: .weekly, seconds: 604_800, reportsLength: false)
        #expect(ExhaustionEstimate.windows(in: [mislabelled]).isEmpty)
        // A weekly row is still the weekly row when it states no length, so a
        // five-hour sibling is not promoted into its place.
        #expect(ExhaustionEstimate.windows(in: [mislabelled, week]).map(\.id) == ["week"])
    }

    @Test("Balance, a top-up, messages, and spend are not a limit to estimate")
    func moneyAndPacksAreOut() {
        let balance = Self.window("balance", kind: .balance, seconds: 365 * 86_400)
        let pack = Self.window("pack", kind: .topUp, seconds: 365 * 86_400)
        let messages = Self.window("messages", kind: .messages, seconds: 86_400)
        let spend = Self.window("spend", kind: .spend, seconds: 30 * 86_400)
        let five = Self.window("5h", kind: .fiveHour, seconds: 18_000)
        #expect(ExhaustionEstimate.windows(in: [balance, pack, messages, spend, five]).isEmpty)

        let day = Self.window("day", kind: .daily, seconds: 86_400)
        #expect(ExhaustionEstimate.windows(in: [balance, pack, messages, spend, day]).map(\.id) == ["day"])
    }

    @Test("A length that was only chosen for sorting is not the fallback")
    func unstatedLengthIsNotAPace() {
        let sorted = Self.window("sorted", kind: .monthly, seconds: 30 * 86_400, reportsLength: false)
        let day = Self.window("day", kind: .daily, seconds: 86_400)
        #expect(ExhaustionEstimate.windows(in: [sorted]).isEmpty)
        #expect(ExhaustionEstimate.windows(in: [sorted, day]).map(\.id) == ["day"])
    }
}
