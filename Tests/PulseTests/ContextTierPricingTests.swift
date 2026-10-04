import Foundation
import Testing
@testable import Pulse

/// A request whose context passed a model's long-context threshold is billed
/// at that tier, all of it; the rest at the base rates.
@Suite("Long-context tiers")
struct ContextTierPricingTests {
    /// gpt-5.5's shape on models.dev.
    private let price = ModelPrice(
        input: 5, output: 30, cacheRead: 0.5, cacheWrite: nil, name: nil,
        tiers: [ModelPrice.ContextTier(threshold: 272_000, input: 10, output: 45, cacheRead: 1, cacheWrite: nil)]
    )

    @Test("models.dev tiers are read, with 272001 meaning over 272,000")
    func parsed() throws {
        let cost: [String: Any] = [
            "input": 5, "output": 30,
            "tiers": [["input": 10, "output": 45, "cache_read": 1, "tier": ["type": "context", "size": 272_001]]],
        ]
        let tier = try #require(ModelPrices.tiers(in: cost)?.first)
        #expect(tier.threshold == 272_000)
        #expect(tier.input == 10 && tier.cacheRead == 1)
        // Where only `context_over_200k` is stated, it is a 200K tier.
        let over = ModelPrices.tiers(in: ["context_over_200k": ["input": 6, "output": 22.5]])
        #expect(over?.first?.threshold == 200_000)
        #expect(ModelPrices.tiers(in: ["input": 1, "output": 2]) == nil)
    }

    @Test("A request over the threshold is priced at the tier, whole; one under it at the base")
    func priced() {
        let short = TokenTally(input: 1_000_000, cacheRead: 0, output: 0).request(context: 100_000)
        let long = TokenTally(input: 1_000_000, cacheRead: 0, output: 0).request(context: 300_000)
        #expect(abs(short.cost(at: price) - 5) < 1e-9)
        #expect(abs(long.cost(at: price) - 10) < 1e-9)
        // Added up in one quarter-hour, each still pays its own rate.
        #expect(abs((short + long).cost(at: price) - 15) < 1e-9)
        // A model with no tier pays its base rate for both.
        let flat = ModelPrice(input: 5, output: 30, cacheRead: 0.5, cacheWrite: nil, name: nil)
        #expect(abs((short + long).cost(at: flat) - 10) < 1e-9)
    }

    @Test("A request between two kept sizes is not priced at a tier it may not have reached")
    func neverEarly() {
        // 262,144 sits between the 256K and 272K bands: a 260K request is in
        // the 256K band and is not moved to a 262,144 tier.
        let odd = ModelPrice(
            input: 1, output: 1, cacheRead: nil, cacheWrite: nil, name: nil,
            tiers: [ModelPrice.ContextTier(threshold: 262_144, input: 9, output: 9, cacheRead: nil, cacheWrite: nil)]
        )
        let tally = TokenTally(input: 1_000_000).request(context: 260_000)
        #expect(abs(tally.cost(at: odd) - 1) < 1e-9)
    }

    @Test("Codex: a reading whose request input passed 272K lands in that band")
    func codexBand() async {
        let lines = [
            #"{"timestamp":"2026-01-02T09:00:00Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
            #"{"timestamp":"2026-01-02T09:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300000,"cached_input_tokens":0,"output_tokens":10,"total_tokens":300010},"last_token_usage":{"input_tokens":300000,"cached_input_tokens":0,"output_tokens":10,"total_tokens":300010}}}}"#,
        ]
        let file = URL.temporaryDirectory.appending(path: "codex-band-\(UUID()).jsonl")
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let tally = await UsageLedgerReader().parse(file, provider: .codex)
            .allDays.values.flatMap(\.values).reduce(TokenTally(), +)
        #expect(tally.contextBands.keys.sorted() == [272_000])
        #expect(tally.contextBands[272_000]?.total == 300_010)
    }

    @Test("Only what is not zero is written, and it reads back whole")
    func sparseEncoding() throws {
        let tally = TokenTally(input: 3, output: 4).request(context: 210_000)
        let data = try JSONEncoder().encode(tally)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("cacheRead"))
        #expect(try JSONDecoder().decode(TokenTally.self, from: data) == tally)
    }
}
