// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Where a recap's ledgers come from: the one path `--recap` and the recap
/// window share, so neither counts the Token spend records a different way.
///
/// **It reads exactly as the Token spend pane does** — `AgentLedgers.scan`, the
/// agents present on this Mac, `ModelPrices` — and it reuses the scan
/// `SpendWarmer` keeps while Token spend is on when that is fresh
/// (`SpendWarmer.paneFreshness`), so opening the window on a Mac that has been
/// reading for a while is not a second read. **Nothing here switches reading on**
/// or checks that it is: whoever calls this has already decided that.
enum RecapSource {
    struct Loaded: Sendable {
        let ledgers: [SpendAgent: UsageLedger]
        let prices: [String: ModelPrice]
        /// The earliest day any record is for, or nil when there is none.
        let earliest: Date?
    }

    /// Main-actor only because `SpendWarmer`'s freshness rule is; the reads
    /// themselves run on `AgentLedgers`' actor.
    @MainActor
    static func load(
        progress: @MainActor @Sendable (AgentLedgers.Progress) -> Void = { _ in }
    ) async throws -> Loaded {
        let snapshot: AgentLedgers.Snapshot
        if let kept = await AgentLedgers.shared.keptSnapshot(),
           Date().timeIntervalSince(kept.at) < SpendWarmer.paneFreshness {
            snapshot = kept.snapshot
        } else {
            snapshot = try await AgentLedgers.shared.scan(progress: progress)
        }
        try Task.checkCancellation()
        let prices = await ModelPrices.shared.prices()
        return Loaded(ledgers: snapshot.ledgers, prices: prices, earliest: RecapPeriods.earliest(in: snapshot.ledgers))
    }

    /// One period's recap, worked out off the main actor: a year over a large
    /// history is a few hundred milliseconds of arithmetic.
    static func build(_ period: Recap.Period, from loaded: Loaded, now: Date = Date()) async -> Recap? {
        Recap.build(period, from: loaded.ledgers, prices: loaded.prices, now: now)
    }
}
