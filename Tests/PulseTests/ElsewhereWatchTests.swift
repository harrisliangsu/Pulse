import Foundation
import Testing
@testable import Pulse

/// A limit spent where this Mac's logs cannot see takes the value estimate off
/// it — never reading the real transcripts or writing the real file here.
@MainActor
@Suite("Used elsewhere")
struct ElsewhereWatchTests {
    private static let resets = Date().addingTimeInterval(3 * 3600)

    private static func reading(_ used: Double, at: Date, resets: Date = resets) -> ProviderUsage {
        let window = UsageWindow(id: "claudeCode.session.all", kind: .fiveHour, scope: nil, usedFraction: used,
                                 windowSeconds: 5 * 3600, resetsAt: resets)
        return ProviderUsage(account: AccountKey(.claudeCode), windows: [window], observedAt: at,
                             state: .live, plan: nil, creditBalance: nil)
    }

    private static func watch(localCost: Double, tokens: Double = 0) -> ElsewhereWatch {
        ElsewhereWatch(file: nil, localCost: { _, _, _ in (localCost, tokens) })
    }

    private static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("Two points gone with nothing spent here marks the cycle")
    func riseWithNothingBehindIt() async {
        let watch = Self.watch(localCost: 0)
        let start = Date().addingTimeInterval(-600)
        watch.observe(Self.reading(0.10, at: start), as: AccountKey(.claudeCode))
        watch.observe(Self.reading(0.12, at: start.addingTimeInterval(300)), as: AccountKey(.claudeCode))
        await Self.settle()
        let window = Self.reading(0.12, at: Date()).windows[0]
        #expect(watch.usedElsewhere(window, account: AccountKey(.claudeCode)))

        // The next cycle starts clean.
        let next = Self.reading(0.01, at: Date(), resets: Self.resets.addingTimeInterval(5 * 3600)).windows[0]
        #expect(!watch.usedElsewhere(next, account: AccountKey(.claudeCode)))
    }

    @Test("A rise this Mac paid for, or a one-point tick, marks nothing")
    func explainedRises() async {
        let paid = Self.watch(localCost: 3)
        let tick = Self.watch(localCost: 0)
        let start = Date().addingTimeInterval(-600)
        for (watch, after) in [(paid, 0.13), (tick, 0.11)] {
            watch.observe(Self.reading(0.10, at: start), as: AccountKey(.claudeCode))
            watch.observe(Self.reading(after, at: start.addingTimeInterval(300)), as: AccountKey(.claudeCode))
        }
        await Self.settle()
        let window = Self.reading(0.13, at: Date()).windows[0]
        #expect(!paid.usedElsewhere(window, account: AccountKey(.claudeCode)))
        #expect(!tick.usedElsewhere(window, account: AccountKey(.claudeCode)))
    }

    @Test("The rule itself")
    func rule() {
        #expect(ElsewhereWatch.spentElsewhere(rise: 0.02, localCost: 0))
        #expect(!ElsewhereWatch.spentElsewhere(rise: 0.01, localCost: 0))
        #expect(!ElsewhereWatch.spentElsewhere(rise: 0.05, localCost: 1))
        // Work here on a model with no price — or before prices were fetched.
        #expect(!ElsewhereWatch.spentElsewhere(rise: 0.05, localCost: 0, localTokens: 40_000))
    }
}
