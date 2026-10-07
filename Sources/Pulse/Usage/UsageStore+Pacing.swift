// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The rules that decide when a pass runs and what it asks, none of which read
/// the store's state: each is `nonisolated`, pure, and takes its clock and its
/// cadence as arguments, so `RefreshPacingTests` pins them without a store.
extension UsageStore {
    /// How long the loop's one timer waits: until the soonest primary account
    /// is due, never under fifteen seconds.
    ///
    /// **No primary account is not no cadence.** Added accounts and extensions
    /// are read on every tick, so a rail of only those still runs on the
    /// interval the user chose — it fell to the adaptive one, and "every
    /// minute" waited half an hour while Settings said a minute.
    nonisolated static func timerWait(primaryWaits: [TimeInterval], fixed: TimeInterval?, adaptive: TimeInterval) -> TimeInterval {
        max(primaryWaits.min() ?? fixed ?? adaptive, 15)
    }

    /// A second of slack, so a timer that fires a hair early does not skip the
    /// very provider it woke up for and sleep another full interval.
    nonisolated static let dueSlack: TimeInterval = 1

    /// Which providers a pass should ask.
    ///
    /// **`dueOnly` is true for exactly one caller: the timer.** Everything else
    /// that reaches `refresh()` is something happening — a setting changed, a
    /// window reset, the display woke, the pointer arrived at a rail whose
    /// figures are older than they should be — and each of those is a reason to
    /// go and look *now*, whatever the cadence says.
    ///
    /// Getting that backwards is not a slow refresh, it is a control that does
    /// nothing: switching DeepSeek between "since top-up" and "balance only"
    /// changes what the reading means, and a pass that skipped it because it
    /// had been asked a minute ago left the old ring on screen.
    ///
    /// `nonisolated static` and pure, so the rule is arguable: it reads none of
    /// the store's state, the clock is passed in, and so is the cadence — which
    /// is the store's own `interval(for:)` in production.
    nonisolated static func providersToAsk(
        from accounts: [AccountKey],
        dueOnly: Bool,
        askedAt: [String: Date],
        interval: (Provider) -> TimeInterval,
        now: Date
    ) -> Set<Provider> {
        Set(
            accounts
                .filter(\.isPrimary)
                .map(\.provider)
                .filter { provider in
                    guard dueOnly else { return true }
                    guard let asked = askedAt[AccountKey(provider).id] else { return true }
                    return now.timeIntervalSince(asked) >= interval(provider) - dueSlack
                }
        )
    }

    /// Longer than any pass can honestly take: every request in one carries a
    /// timeout of its own, and the whole set runs side by side. Past this the
    /// pass is not slow, it is gone — and since `scheduleNext` only runs when a
    /// pass *finishes*, a lost one takes the whole loop with it and nothing
    /// ever asks again.
    static let passCeiling: TimeInterval = 180

    /// One provider's answer for a pass: what the service returned and what
    /// the cache made of it.
    ///
    /// **One collection, not two.** The commit loop and the "did anything
    /// move" question used to be asked of two hand-written lists of the same
    /// providers, and adding Devin to one while forgetting the other left its
    /// moves unable to shorten the interval. Asked of the same rows, they
    /// cannot disagree.
    struct BatchResult: Sendable {
        let provider: Provider
        let raw: ProviderUsage
        let fetched: ProviderUsage
    }

    /// Whether any provider that was actually asked reported different windows
    /// from the reading already on screen.
    ///
    /// Only providers represented in `results` are considered, and `results`
    /// holds exactly the ones this pass asked. `observedAt` is deliberately
    /// ignored: it moves on every successful fetch, so including it would
    /// report a change every pass and the loop would never slow down.
    nonisolated static func didAnythingMove(
        _ results: [BatchResult],
        previous: [String: ProviderUsage]
    ) -> Bool {
        results.contains { result in
            previous[AccountKey(result.provider).id]?.windows != result.fetched.windows
        }
    }
}
