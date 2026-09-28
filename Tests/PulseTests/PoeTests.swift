import Foundation
import Testing
@testable import Pulse

/// Poe's point balance.
///
/// **The fixture is second-hand**: written from CodexBar's Poe plugin and its
/// docs (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Poe")
struct PoeTests {
    private let context = ProfileContext(provider: .poe, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The point balance is shown, with no ring and no money")
    func balance() throws {
        let usage = PoeUsageService.reading(from: try fixture("poe-current-balance"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.poe))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditBalance?.contains("567") == true)
        #expect(usage.creditRemaining == nil)
        #expect(!Provider.poe.reportsSpendableBalance)
    }

    @Test("A numeric string is a balance too")
    func string() {
        let usage = PoeUsageService.reading(from: Data(#"{"current_point_balance":" 250 "}"#.utf8), context: context)
        #expect(usage.creditBalance?.contains("250") == true)
    }

    @Test("A reply with no balance can't be read", arguments: [
        "not json", "[]", "{}", #"{"current_point_balance":"many"}"#, #"{"current_point_balance":null}"#,
    ])
    func unreadable(json: String) {
        let usage = PoeUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .poe, credential: nil, serverAddress: nil)
        #expect(await PoeUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
