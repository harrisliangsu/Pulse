import Foundation
import Testing
@testable import Pulse

/// What a limit is worth: the spend inside the window, up to the moment its
/// percentage was read, over that percentage.
@Suite("Budget estimate")
struct BudgetEstimateTests {
    private static let opened = Date(timeIntervalSince1970: 1_790_000_100) // 100 s into a quarter-hour
    private static let quarter: TimeInterval = 15 * 60

    private static func ledger(_ slots: [(TimeInterval, Double)]) -> UsageLedger {
        UsageLedger(
            days: [], earliest: nil, unpricedModels: [], modelNames: [:],
            slots: slots.map { offset, cost in
                UsageLedger.Slot(start: Date(timeIntervalSince1970: 1_790_000_000 + offset), tokens: 1, cost: cost)
            }
        )
    }

    private static func window(used: Double) -> UsageWindow {
        UsageWindow(id: "test.five", kind: .fiveHour, scope: nil, usedFraction: used,
                    windowSeconds: 5 * 3600, resetsAt: opened.addingTimeInterval(5 * 3600))
    }

    @Test("The quarter-hour a window opened in counts for its share inside the window")
    func openingQuarterCounts() {
        // 900 s quarter, window opened 100 s in: 800/900 of it is inside.
        let ledger = Self.ledger([(0, 9), (Self.quarter, 1)])
        let estimate = BudgetEstimator.estimate(
            for: Self.window(used: 0.1), ledger: ledger,
            observedAt: Self.opened.addingTimeInterval(3600), now: Self.opened.addingTimeInterval(3600)
        )
        #expect(abs((estimate?.spent ?? 0) - (8 + 1)) < 1e-9)
        #expect(abs((estimate?.full ?? 0) - 90) < 1e-9)
    }

    @Test("Work after the percentage was read is not set against it")
    func spendStopsAtTheReading() {
        let ledger = Self.ledger([(0, 0), (Self.quarter, 5), (4 * Self.quarter, 50)])
        let read = Self.opened.addingTimeInterval(2 * Self.quarter)
        let estimate = BudgetEstimator.estimate(
            for: Self.window(used: 0.1), ledger: ledger,
            observedAt: read, now: read.addingTimeInterval(3600)
        )
        #expect(abs((estimate?.spent ?? 0) - 5) < 1e-9)
    }

    @Test("Too little used, or a reading from before the window, gives no estimate")
    func withheld() {
        let ledger = Self.ledger([(0, 1), (Self.quarter, 5)])
        let later = Self.opened.addingTimeInterval(3600)
        #expect(BudgetEstimator.estimate(for: Self.window(used: 0.04), ledger: ledger, observedAt: later, now: later) == nil)
        #expect(BudgetEstimator.estimate(for: Self.window(used: 0.05), ledger: ledger, observedAt: later, now: later) != nil)
        #expect(BudgetEstimator.estimate(
            for: Self.window(used: 0.1), ledger: ledger,
            observedAt: Self.opened.addingTimeInterval(-60), now: later
        ) == nil)
    }

    @Test("A window whose length only orders the rows gives no estimate")
    func unstatedLength() {
        let ledger = Self.ledger([(0, 1), (Self.quarter, 5)])
        let later = Self.opened.addingTimeInterval(3600)
        var window = Self.window(used: 0.5)
        #expect(BudgetEstimator.estimate(for: window, ledger: ledger, observedAt: later, now: later) != nil)
        window.reportsLength = false
        #expect(BudgetEstimator.estimate(for: window, ledger: ledger, observedAt: later, now: later) == nil)
    }
}
