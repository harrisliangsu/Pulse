import Foundation
import Testing
@testable import Pulse

/// Hyper's Hypercredit balance.
///
/// **The fixture is second-hand**: written from CodexBar's Hyper plugin and
/// its docs (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Hyper")
struct HyperTests {
    private let context = ProfileContext(provider: .hyper, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The balance is shown in Hypercredits, with no ring and no money")
    func balance() throws {
        let usage = HyperUsageService.reading(from: try fixture("hyper-credits"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.hyper))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditBalance?.hasSuffix(" HC") == true)
        #expect(usage.creditBalance?.contains("234") == true)
        // Not a currency, so nothing may compare it against one.
        #expect(usage.creditRemaining == nil)
        #expect(!Provider.hyper.reportsSpendableBalance)
    }

    @Test("A zero balance is a balance", arguments: [#"{"balance":0}"#])
    func zero(json: String) {
        let usage = HyperUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.creditBalance == "0 HC")
    }

    @Test("A balance that isn't one can't be read", arguments: [
        "not json", "[]", #"{"balance":-1}"#, #"{"balance":"12"}"#, #"{}"#,
    ])
    func unreadable(json: String) {
        let usage = HyperUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .hyper, credential: nil, serverAddress: nil)
        #expect(await HyperUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
