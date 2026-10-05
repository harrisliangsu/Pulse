import Testing
@testable import Pulse

@Suite("Indexed model pricing")
struct ModelPriceLookupTests {
    private let maker = ModelPrice(input: 2, output: 4, cacheRead: 1, cacheWrite: 3, name: "Maker")
    private let plan = ModelPrice(input: 8, output: 9, cacheRead: nil, cacheWrite: nil, name: "Plan")

    @Test("Repeated exact, folded, alias and vendor lookups preserve pricing precedence")
    func precedence() {
        let table = [
            "gpt-5.6-sol": maker, "MiniMax-M3": maker,
            "opencode-go|gpt-5-6-sol-medium": plan,
            "opencode-go|plan-only": plan, "kilo|plan-only": maker,
            "opencode-go|kimi-k3": plan,
        ]
        var lookup = ModelPriceLookup(table)
        for _ in 0..<3 {
            #expect(lookup.price(for: "gpt-5.6-sol") == maker)
            #expect(lookup.price(for: "gpt-5-6-sol-medium", vendor: "opencode-go") == maker)
            #expect(lookup.price(for: "MINIMAX-M3") == maker)
            #expect(lookup.price(for: "plan-only") == nil)
            #expect(lookup.price(for: "plan-only", vendor: "opencode-go") == plan)
            #expect(lookup.price(for: "PLAN-ONLY", vendor: "opencode-go") == plan)
            #expect(lookup.price(for: "plan-only", vendor: "kilo") == maker)
            #expect(lookup.price(for: "k3-256k", vendor: "opencode-go") == plan)
            #expect(lookup.price(for: "unpublished", vendor: "opencode-go") == nil)
        }
    }

    @Test("New price snapshots cannot inherit a hit or miss from an older table")
    func replacement() {
        var old = ModelPriceLookup(["priced": maker])
        #expect(old.price(for: "priced") == maker)
        #expect(old.price(for: "new") == nil)
        var next = ModelPriceLookup(["priced": plan, "new": maker])
        #expect(next.price(for: "priced") == plan)
        #expect(next.price(for: "new") == maker)
        var offline = ModelPriceLookup([:])
        #expect(offline.price(for: "priced") == nil)
        #expect(old.price(for: "priced") == maker)
    }
}
