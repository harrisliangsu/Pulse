import Foundation

/// Kimi's CLI, which writes the raw exchange to `wire.jsonl`.
///
/// ```json
/// { "timestamp": …,
///   "message": { "payload": { "token_usage": {
///     "input_other": 4340, "output": 38,
///     "input_cache_read": 9216, "input_cache_creation": 0 } } } }
/// ```
///
/// **`input_other` is fresh input**, as the name says: the cache figures are
/// counted beside it rather than inside it, which is the same arrangement
/// Claude Code uses and the opposite of Codex's.
///
/// **It names no model, anywhere.** Neither the wire log nor the session state
/// carries one, so its tokens are counted and never costed — the same answer
/// Pulse gives for any model with no published price, arrived at one step
/// earlier. The id below is a placeholder so the buckets have a key, and is
/// deliberately one no price list can match.
enum KimiCLIStore {
    static func ledger(at root: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var buckets: [String: [String: TokenTally]] = [:]
        var sessions: [UsageLedger.Session] = []

        let manager = FileManager.default
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: nil) else { return .empty }

        for case let file as URL in walker where file.lastPathComponent == "wire.jsonl" {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }

            var tokens = 0
            var cost = 0.0
            var first: Date?
            var last: Date?
            var sessionSlots: [String: (tokens: Int, cost: Double)] = [:]
            let model = "kimi (unnamed)"

            for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = root["message"] as? [String: Any],
                      let payload = message["payload"] as? [String: Any]
                else { continue }

                guard let usage = payload["token_usage"] as? [String: Any] else { continue }

                let tally = TokenTally(
                    input: int(usage["input_other"]),
                    cacheWrite: int(usage["input_cache_creation"]),
                    cacheRead: int(usage["input_cache_read"]),
                    output: int(usage["output"])
                )
                guard tally.total > 0 else { continue }

                let seconds = (root["timestamp"] as? Double)
                    ?? (root["timestamp"] as? Int).map(Double.init)
                    ?? 0
                guard seconds > 0 else { continue }

                let at = Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
                first = min(first ?? at, at)
                last = max(last ?? at, at)

                let key = UsageLedgerReader.slotKey(for: at)
                let money = ModelPrices.price(for: model, in: prices).map { tally.cost(at: $0) } ?? 0
                buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally
                tokens += tally.total
                cost += money

                var slot = sessionSlots[key] ?? (tokens: 0, cost: 0)
                slot.tokens += tally.total
                slot.cost += money
                sessionSlots[key] = slot
            }

            guard tokens > 0, let first, let last else { continue }
            sessions.append(
                UsageLedger.Session(
                    id: file.path,
                    name: file.deletingLastPathComponent().lastPathComponent,
                    // The session's own state file keeps the title beside the
                    // wire log. Neither carries a working directory.
                    title: Self.title(besideWire: file),
                    project: nil,
                    start: first, end: last, tokens: tokens, cost: cost,
                    slots: UsageLedgerReader.sessionSlots(sessionSlots)
                )
            )
        }

        guard !buckets.isEmpty else { return .empty }
        var ledger = UsageLedgerReader.price(buckets, with: prices)
        ledger.sessions = sessions.sorted { $0.end > $1.end }
        return ledger
    }

    private static func title(besideWire file: URL) -> String? {
        let state = file.deletingLastPathComponent().appending(path: "state.json")
        guard
            let data = try? Data(contentsOf: state),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let custom = root["custom_title"] as? String
        else { return nil }
        return UsageLedgerReader.title(from: custom)
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
