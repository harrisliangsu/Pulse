import Foundation
import Testing
@testable import Pulse

/// Atlas Cloud's account balance.
///
/// **The fixture is second-hand**: written from CodexBar's Atlas Cloud plugin
/// and its docs (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("Atlas Cloud")
struct AtlasCloudTests {
    private let context = ProfileContext(provider: .atlasCloud, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The available balance is money, in the currency stated")
    func balance() throws {
        let usage = AtlasCloudUsageService.reading(from: try fixture("atlas-cloud-balance"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.atlasCloud))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 42.5, currency: "USD"))
        #expect(usage.creditBalance?.contains("42") == true)
        #expect(Provider.atlasCloud.reportsSpendableBalance)
    }

    @Test("A negative balance is kept: it is money owed")
    func negative() {
        let json = #"{"object":"balance","scope":"account","available":{"value":"-3.25","currency":"usd"}}"#
        let usage = AtlasCloudUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.creditRemaining?.amount == -3.25)
    }

    @Test("Anything but an account balance with a number and a currency can't be read", arguments: [
        "not json",
        #"{"object":"balance","scope":"team","available":{"value":"1","currency":"usd"}}"#,
        #"{"object":"balance","scope":"account","available":{"value":"lots","currency":"usd"}}"#,
        #"{"object":"balance","scope":"account","available":{"value":"1","currency":"dollars"}}"#,
        #"{"object":"balance","scope":"account","available":{"value":1,"currency":"usd"}}"#,
        #"{"object":"list"}"#,
    ])
    func unreadable(json: String) {
        let usage = AtlasCloudUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .atlasCloud, credential: "", serverAddress: nil)
        #expect(await AtlasCloudUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
