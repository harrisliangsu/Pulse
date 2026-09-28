import Foundation
import Testing
@testable import Pulse

/// DeepSeek's three ring modes, as every API account's rule. The marks are
/// kept in memory here; nothing is written to disk.
@Suite("Balance ring")
@MainActor
struct BalanceRingTests {
    private let account = AccountKey(.moonshot)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func balance(_ amount: Double, currency: String = "USD") -> ProviderUsage {
        var usage = ProviderUsage(account: account, windows: [], observedAt: start, state: .live,
                                  plan: nil, creditBalance: "\(amount)")
        usage.creditRemaining = .init(amount: amount, currency: currency)
        return usage
    }

    @Test("Since top-up: the first sight is the mark, spending fills the ring, a top-up empties it")
    func sinceTopUp() {
        let baselines = BalanceBaselines(file: nil)
        let first = BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: balance(100), baselines: baselines, now: start)
        #expect(first.windows.first?.usedFraction == 0)
        #expect(first.windows.first?.estimate == .sinceTopUp)
        #expect(first.windows.first?.reportsLength == false)

        let spent = BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: balance(25), baselines: baselines, now: start)
        #expect(spent.windows.first?.usedFraction == 0.75)

        let toppedUp = BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: balance(200), baselines: baselines, now: start)
        #expect(toppedUp.windows.first?.usedFraction == 0)
    }

    @Test("One mark per currency: a CNY peak is not a USD denominator")
    func perCurrency() {
        let baselines = BalanceBaselines(file: nil)
        _ = BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: balance(1_000, currency: "CNY"), baselines: baselines, now: start)
        let usd = BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: balance(10), baselines: baselines, now: start)
        #expect(usd.windows.first?.usedFraction == 0)
    }

    @Test("A budget measures against the reader's figure; none, or a silly one, draws the money alone")
    func budget() {
        let baselines = BalanceBaselines(file: nil)
        let ringed = BalanceRing.applying(basis: .budget, budget: 50, to: balance(20), baselines: baselines, now: start)
        #expect(ringed.windows.first?.usedFraction == 0.6)
        #expect(ringed.windows.first?.estimate == .yourBudget)
        for missing in [nil, 0, -5, Double.infinity] as [Double?] {
            #expect(BalanceRing.applying(basis: .budget, budget: missing, to: balance(20), baselines: baselines, now: start).windows.isEmpty)
        }
    }

    @Test("Balance only draws no ring, and still watches the mark for later")
    func balanceOnly() {
        let baselines = BalanceBaselines(file: nil)
        #expect(BalanceRing.applying(basis: .balanceOnly, budget: nil, to: balance(80), baselines: baselines, now: start).windows.isEmpty)
        let later = BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: balance(40), baselines: baselines, now: start)
        #expect(later.windows.first?.usedFraction == 0.5)
    }

    @Test("A reading with limits of its own, or no reading, is left as it came")
    func untouched() {
        let baselines = BalanceBaselines(file: nil)
        var limited = balance(10)
        limited.windows = [UsageWindow(id: "w", kind: .monthly, scope: nil, usedFraction: 0.2,
                                       windowSeconds: 30 * 86_400, resetsAt: nil, reportsLength: false)]
        #expect(BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: limited, baselines: baselines, now: start) == limited)
        let failed = ProviderUsage.unavailable(account, reason: .unreachable)
        #expect(BalanceRing.applying(basis: .sinceTopUp, budget: nil, to: failed, baselines: baselines, now: start) == failed)
    }

    @Test("Each API account keeps its own basis and budget; DeepSeek's stay where they were")
    func perAccountSettings() {
        let settings = AppSettings()
        settings.setBalanceBasis(.budget, for: account)
        settings.setBalanceBudget(30, for: account)
        #expect(settings.balanceBasis(for: account) == .budget)
        #expect(settings.balanceBudget(for: account) == 30)
        #expect(settings.balanceBasis(for: AccountKey(.openAIPlatform)) == .default)

        settings.setBalanceBasis(.balanceOnly, for: AccountKey(.deepSeek))
        #expect(settings.deepSeekBasis == .balanceOnly)
        #expect(settings.balanceBases[AccountKey(.deepSeek).id] == nil)
    }
}

@Suite("Balance ring never calls an account spent")
@MainActor
struct BalanceRingSpentTests {
    @Test("A zero or negative balance fills the ring but is not the provider saying spent")
    func zeroIsNotSpent() {
        let baselines = BalanceBaselines(file: nil)
        for amount in [0.0, -12.5] {
            var usage = ProviderUsage(account: AccountKey(.moonshot), windows: [], observedAt: nil, state: .live,
                                      plan: nil, creditBalance: nil)
            usage.creditRemaining = .init(amount: amount, currency: "USD")
            let ringed = BalanceRing.applying(basis: .budget, budget: 10, to: usage, baselines: baselines)
            #expect(ringed.windows.first?.usedFraction == 1)
            #expect(ringed.windows.first?.isExhausted == false)
        }
    }
}
