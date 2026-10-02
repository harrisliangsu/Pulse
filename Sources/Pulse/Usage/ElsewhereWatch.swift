// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Notices a limit being spent where this Mac's logs cannot see it — another
/// computer on the same account, or claude.ai — so the value estimate can
/// stand down instead of dividing a part of the spending by the whole of the
/// percentage.
///
/// **The evidence is a rise with nothing behind it.** Between two live
/// readings of one window in one cycle, the percentage climbed at least
/// `minimumRise` while this Mac's logs show next to nothing spent from a
/// little before the first reading (`lag`: a request's percentage can land a
/// reading late) to the second. Two points, not one: the providers report
/// whole percentages, and a one-point tick can come from a sliver of work.
/// Once seen, the cycle stays marked until the window resets — work that
/// stopped being visible did not stop counting.
///
/// What this cannot see is the two machines working at the same time: the
/// local spend is then real, only short. That case keeps an estimate that is
/// too low, and the caption under the estimate still says so.
@MainActor
@Observable
final class ElsewhereWatch {
    nonisolated static let minimumRise = 0.02
    /// Less than this spent locally while the percentage rose two points is
    /// nothing — a two-point rise is dollars on every plan Pulse has seen.
    nonisolated static let quietSpend = 0.05
    static let lag: TimeInterval = 15 * 60
    /// Resets are reported to the second and drift by a fraction of one
    /// between readings; a cycle is the same cycle within this.
    private static let sameCycle: TimeInterval = 120

    private struct Point {
        let fraction: Double
        let at: Date
        let resetsAt: Date
    }

    /// The cycle each window was seen spent elsewhere in, by its reset.
    private(set) var cycles: [String: Date] = [:]
    @ObservationIgnored private var last: [String: Point] = [:]
    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let localCost: @Sendable (Provider, Date, Date) async -> (cost: Double, tokens: Double)

    static let shared = ElsewhereWatch(file: PulseStorage.directory.appending(path: "used-elsewhere.json"))

    init(
        file: URL?,
        localCost: @escaping @Sendable (Provider, Date, Date) async -> (cost: Double, tokens: Double) = { provider, start, end in
            let ledger = await UsageLedgerReader.shared.ledger(for: provider, refresh: true)
            return (ledger.cost(from: start, to: end), ledger.tokens(from: start, to: end))
        }
    ) {
        self.file = file
        self.localCost = localCost
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Date].self, from: data) {
            cycles = saved.filter { $0.value > Date() }
        }
    }

    /// Whether the rise between two readings had nothing on this Mac behind it.
    /// **Tokens as well as money.** A model with no published price spends
    /// nothing in dollars however hard it works, and a first launch offline
    /// has no prices at all — measured in money alone, a day's real work here
    /// read as somebody else's.
    nonisolated static func spentElsewhere(rise: Double, localCost: Double, localTokens: Double = 0) -> Bool {
        rise >= minimumRise - 1e-9 && localCost < quietSpend && localTokens < quietTokens
    }

    /// Fewer tokens than this in the span is no work at all: a single request
    /// re-reads its whole context, tens of thousands of tokens.
    nonisolated static let quietTokens = 1_000.0

    /// Takes a live reading in. Only the providers whose spending Pulse reads
    /// from this Mac's transcripts, and only account-wide windows — the ones
    /// the estimate is made for.
    func observe(_ reading: ProviderUsage, as account: AccountKey, now: Date = Date()) {
        guard account.provider.keepsLocalTranscripts,
              case .live = reading.state,
              let observedAt = reading.observedAt else { return }
        for window in reading.windows where window.scope == nil {
            guard let resets = window.resetsAt, resets > now else { continue }
            let key = Self.key(account, window.id)
            let point = Point(fraction: window.usedFraction, at: observedAt, resetsAt: resets)
            defer { last[key] = point }
            guard let previous = last[key],
                  abs(previous.resetsAt.timeIntervalSince(resets)) < Self.sameCycle,
                  observedAt > previous.at,
                  point.fraction - previous.fraction >= Self.minimumRise - 1e-9,
                  !isMarked(key, resets: resets) else { continue }

            let rise = point.fraction - previous.fraction
            let provider = account.provider
            let from = previous.at.addingTimeInterval(-Self.lag)
            Task { [localCost] in
                let local = await localCost(provider, from, observedAt)
                guard Self.spentElsewhere(rise: rise, localCost: local.cost, localTokens: local.tokens) else { return }
                self.mark(key, resets: resets)
            }
        }
    }

    /// Whether this window's current cycle has been seen spent elsewhere.
    func usedElsewhere(_ window: UsageWindow, account: AccountKey) -> Bool {
        guard let resets = window.resetsAt else { return false }
        return isMarked(Self.key(account, window.id), resets: resets)
    }

    private func isMarked(_ key: String, resets: Date) -> Bool {
        cycles[key].map { abs($0.timeIntervalSince(resets)) < Self.sameCycle } ?? false
    }

    private func mark(_ key: String, resets: Date) {
        cycles = cycles.filter { $0.value > Date() }
        cycles[key] = resets
        guard let file, let data = try? JSONEncoder().encode(cycles) else { return }
        PulseStorage.prepare()
        try? data.write(to: file, options: .atomic)
    }

    private static func key(_ account: AccountKey, _ window: String) -> String {
        "\(account.id)|\(window)"
    }
}
