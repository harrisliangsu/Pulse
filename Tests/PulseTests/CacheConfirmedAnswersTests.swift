import Foundation
import Testing
@testable import Pulse

/// Answers the cache must pass through rather than cover with banked figures:
/// a service confirming there is no plan, and a credential that is gone.
@Suite("Cache: confirmed answers")
struct CacheConfirmedAnswersTests {
    private func banked(_ account: AccountKey, in cache: UsageCache) async {
        let window = UsageWindow(id: "w", kind: .monthly, scope: nil, usedFraction: 0.4,
                                 windowSeconds: 0, resetsAt: nil, reportsLength: false)
        let live = ProviderUsage(account: account, windows: [window], observedAt: Date(),
                                 state: .live, plan: nil, creditBalance: nil)
        _ = await cache.reconciled(live)
    }

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "CacheConfirmedAnswers-\(UUID().uuidString).json")
    }

    @Test("A confirmed absence of a plan drops the old figures, now and on the next launch", arguments: [
        (Provider.zai, ProviderUsage.Unavailability.zaiNoCodingPlan),
        (.xiaomiMiMo, .xiaomiNoCodingPlan),
        (.grokBot, .grokBotNotIncluded),
        (.qoder, .qoderNoCredits),
        (.stepFun, .stepFunNoPlan),
    ])
    func noPlanDropsBankedFigures(provider: Provider, reason: ProviderUsage.Unavailability) async {
        let file = scratch()
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        let account = AccountKey(provider)
        await banked(account, in: cache)

        let shown = await cache.reconciled(.unavailable(account, reason: reason))
        #expect(shown.state == .unavailable(reason))
        #expect(await cache.lastReading(for: account) == nil)
    }

    @Test("Xiaomi's cleared session asks to sign in instead of showing stale figures")
    func xiaomiSessionMissing() async {
        let file = scratch()
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        let account = AccountKey(.xiaomiMiMo)
        await banked(account, in: cache)

        let shown = await cache.reconciled(.unavailable(account, reason: .xiaomiSessionMissing))
        #expect(shown.state == .unavailable(.xiaomiSessionMissing))
    }

    @Test("A failed request still falls back to the banked figures")
    func failureStillFallsBack() async {
        let file = scratch()
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        let account = AccountKey(.zai)
        await banked(account, in: cache)

        let shown = await cache.reconciled(.unavailable(account, reason: .unreachable))
        #expect(shown.state == .stale)
    }
}
