import Foundation
import Testing
@testable import Pulse

/// Which ring the menu bar item speaks for: the rail's own headline figures,
/// the fullest winning, and nothing an unavailable or inferred ring says.
@Suite("Menu bar reading")
struct MenuBarReadingTests {
    private let claude = AccountKey(.claudeCode)
    private let codex = AccountKey(.codex)
    private let cursor = AccountKey(.cursor)

    private func window(_ id: String, _ fraction: Double, estimate: UsageWindow.Estimate? = nil,
                        exhausted: Bool = false) -> UsageWindow {
        UsageWindow(id: id, kind: .weekly, scope: nil, usedFraction: fraction, windowSeconds: 604_800,
                    resetsAt: nil, estimate: estimate, isExhausted: exhausted)
    }

    private func live(_ account: AccountKey, _ windows: [UsageWindow]) -> ProviderUsage {
        ProviderUsage(account: account, windows: windows, observedAt: Date(), state: .live, plan: nil, creditBalance: nil)
    }

    private func tightest(_ readings: [AccountKey: ProviderUsage], order: [AccountKey],
                          pinned: [AccountKey: String] = [:], threshold: Double = 0.8) -> MenuBarReading? {
        MenuBarReading.tightest(
            among: order,
            usage: { readings[$0] ?? .unavailable($0, reason: .loading) },
            pinned: { pinned[$0] },
            warningAt: threshold
        )
    }

    @Test("The fullest ring wins, measured by each ring's own headline")
    func fullestWins() {
        let reading = tightest([
            claude: live(claude, [window("5h", 0.3), window("week", 0.6)]),
            codex: live(codex, [window("week", 0.45)]),
        ], order: [claude, codex])
        #expect(reading?.account == claude)
        #expect(reading?.window?.id == "week")
        #expect(reading?.text(remaining: false) == "60%")
        #expect(reading?.text(remaining: true) == "40%")
        #expect(reading?.isAlert == false)
    }

    @Test("A pinned limit is what that account contributes, as on its ring")
    func pinnedLimitCounts() {
        let reading = tightest([
            claude: live(claude, [window("5h", 0.3), window("week", 0.9)]),
            codex: live(codex, [window("week", 0.5)]),
        ], order: [claude, codex], pinned: [claude: "5h"])
        #expect(reading?.account == codex)
    }

    @Test("An account with no reading, or only an inferred ring, is left out")
    func unavailableAndEstimatedAreLeftOut() {
        let reading = tightest([
            claude: .unavailable(claude, reason: .serverError),
            codex: live(codex, [window("balance", 0.95, estimate: .yourBudget)]),
            cursor: live(cursor, [window("month", 0.2)]),
        ], order: [claude, codex, cursor])
        #expect(reading?.account == cursor)
    }

    @Test("Nothing to show is nothing, not a zero")
    func nothingToShow() {
        #expect(tightest([claude: .unavailable(claude, reason: .loading)], order: [claude]) == nil)
        #expect(tightest([:], order: []) == nil)
    }

    @Test("A tie goes to the account earlier on the rail")
    func tieKeepsRailOrder() {
        let reading = tightest([
            claude: live(claude, [window("week", 0.5)]),
            codex: live(codex, [window("week", 0.5)]),
        ], order: [codex, claude])
        #expect(reading?.account == codex)
    }

    @Test("Red at the warning line, and when the provider says spent", arguments: [
        (0.79, false, false), (0.8, false, true), (0.1, true, true),
    ])
    func alert(fraction: Double, exhausted: Bool, alert: Bool) {
        let reading = tightest([claude: live(claude, [window("week", fraction, exhausted: exhausted)])], order: [claude])
        #expect(reading?.isAlert == alert)
    }

    @Test("A chosen account is shown even when another is fuller")
    func chosenAccountWins() {
        let readings = [
            claude: live(claude, [window("week", 0.9)]),
            codex: live(codex, [window("week", 0.2)]),
        ]
        let reading = MenuBarReading.choose(
            among: [claude, codex], chosen: codex,
            usage: { readings[$0]! }, pinned: { _ in nil }, warningAt: 0.8
        )
        #expect(reading?.account == codex)
        #expect(reading?.text(remaining: false) == "20%")
    }

    @Test("A chosen account taken off the rail falls back to the fullest ring")
    func chosenOffRailFallsBack() {
        let readings = [claude: live(claude, [window("week", 0.9)])]
        let reading = MenuBarReading.choose(
            among: [claude], chosen: codex,
            usage: { readings[$0] ?? .unavailable($0, reason: .loading) }, pinned: { _ in nil }, warningAt: 0.8
        )
        #expect(reading?.account == claude)
    }

    @Test("A chosen account with no reading says so with a dash, not a zero")
    func chosenWithoutReading() {
        let reading = MenuBarReading.choose(
            among: [claude], chosen: claude,
            usage: { .unavailable($0, reason: .serverError) }, pinned: { _ in nil }, warningAt: 0.8
        )
        #expect(reading?.window == nil)
        #expect(reading?.text(remaining: false) == "–")
        #expect(reading?.ringFraction(remaining: false) == nil)
    }

    @Test("An inferred ring shows the money instead of its percentage")
    func inferredShowsMoney() {
        var usage = live(codex, [window("balance", 0.6, estimate: .sinceTopUp)])
        usage.creditRemaining = .init(amount: 12.5, currency: "USD")
        let reading = MenuBarReading.of(codex, usage: usage, pinned: nil, warningAt: 0.8)
        #expect(reading.window == nil)
        #expect(reading.money == usage.creditRemaining?.railText())
        #expect(reading.text(remaining: false) == reading.money)
    }

    @Test("The ring draws what the rail draws: left while left is on, full when spent")
    func ringFraction() {
        let partly = MenuBarReading.of(claude, usage: live(claude, [window("week", 0.3)]), pinned: nil, warningAt: 0.8)
        #expect(partly.ringFraction(remaining: false) == 0.3)
        #expect(abs((partly.ringFraction(remaining: true) ?? 0) - 0.7) < 1e-9)
        let spent = MenuBarReading.of(claude, usage: live(claude, [window("week", 1, exhausted: true)]), pinned: nil, warningAt: 0.8)
        #expect(spent.ringFraction(remaining: true) == 1)
    }

    private func timed(_ kind: UsageWindow.Kind, _ fraction: Double, scope: String? = nil) -> UsageWindow {
        UsageWindow(id: "\(kind)\(scope ?? "")", kind: kind, scope: scope, usedFraction: fraction,
                    windowSeconds: 604_800, resetsAt: nil)
    }

    @Test("Split takes the account-wide five-hour and weekly limits, shortest first")
    func splitPicksTimedLimits() {
        let usage = live(claude, [timed(.weekly, 0.15), timed(.weekly, 0.0, scope: "Fable"), timed(.fiveHour, 0.9)])
        let reading = MenuBarReading.of(claude, usage: usage, pinned: nil, warningAt: 0.8)
        #expect(reading.split.map(\.window.kind) == [.fiveHour, .weekly])
        #expect(reading.split.map(\.window.scope) == [nil, nil])
        // Red on its own: the spent five hours, not the quiet week.
        #expect(reading.split.map(\.isAlert) == [true, false])
    }

    @Test("An account with one timed limit has nothing to split")
    func splitNeedsTwo() {
        let reading = MenuBarReading.of(codex, usage: live(codex, [timed(.weekly, 0.08)]), pinned: nil, warningAt: 0.8)
        #expect(reading.split.count == 1)
        let scoped = MenuBarReading.of(cursor, usage: live(cursor, [
            timed(.monthly, 0.1, scope: "Cursor Models"), timed(.monthly, 0.2, scope: "Other Models"),
        ]), pinned: nil, warningAt: 0.8)
        #expect(scoped.split.isEmpty)
    }

    @Test("The short names", arguments: [UsageWindow.Kind.fiveHour, .weekly, .monthly, .daily])
    func shortNames(kind: UsageWindow.Kind) {
        #expect(!MenuBarReading.shortName(kind).isEmpty)
    }
}

