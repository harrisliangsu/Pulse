import Foundation
import Testing
@testable import Pulse

/// Vercel AI Gateway's credit balance.
///
/// **The fixture is second-hand**: written from CodexBar's Vercel provider
/// (MIT) and the public API reference it cites, not captured from a live
/// account. It pins the shape Pulse reads; it does not prove the shape is right.
@Suite("Vercel AI Gateway")
struct VercelAIGatewayTests {
    private let context = ProfileContext(provider: .vercelAIGateway, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The balance is read as dollars, with no ring")
    func balance() throws {
        let usage = VercelAIGatewayUsageService.reading(from: try fixture("vercel-ai-gateway-credits"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.vercelAIGateway))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == .init(amount: 95.5, currency: "USD"))
        #expect(usage.creditBalance?.contains("95") == true)
    }

    @Test("Zero and overdrawn balances are readings, not failures", arguments: [
        (#"{"balance":"0","total_used":"1"}"#, 0.0),
        (#"{"balance":"-2.25","total_used":"10"}"#, -2.25),
    ])
    func edges(json: String, amount: Double) {
        let usage = VercelAIGatewayUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.creditRemaining == .init(amount: amount, currency: "USD"))
    }

    @Test("A balance that isn't a decimal string can't be read", arguments: [
        #"{"balance":95.5}"#,
        #"{"balance":"lots"}"#,
        #"{"total_used":"4.50"}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = VercelAIGatewayUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .vercelAIGateway, credential: nil, serverAddress: nil)
        #expect(await VercelAIGatewayUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
