import Foundation
import Testing
@testable import Pulse

/// The xAI developer platform's prepaid balance.
///
/// **The fixture is second-hand**: built from CodexBar's xAI provider and its
/// docs (MIT), not captured from a live account.
@Suite("xAI API")
struct XAIAPITests {
    private let context = ProfileContext(provider: .xaiAPI, credential: "team:key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The inverted cent ledger is read as dollars left, with no ring")
    func balance() throws {
        let usage = XAIAPIUsageService.reading(from: try fixture("xai-api-prepaid-balance"), context: context)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == .init(amount: 12.34, currency: "USD"))
        #expect(usage.creditBalance != nil)
    }

    @Test("A total that isn't a cent amount is not a zero balance", arguments: [
        #"{"total":{"val":"12.3.4"}}"#, #"{"total":{"val":""}}"#, #"{"total":{}}"#, #"{}"#, "nope",
    ])
    func unreadable(json: String) {
        #expect(XAIAPIUsageService.reading(from: Data(json.utf8), context: context).state == .unavailable(.unreadableReply))
    }

    @Test("TeamID:ManagementKey is split once, and a team id can't leave the path")
    func credential() throws {
        let parsed = try #require(XAIAPIUsageService.credential(" team-1 : xai-key:with:colons "))
        #expect(parsed.team == "team-1")
        #expect(parsed.key == "xai-key:with:colons")
        #expect(XAIAPIUsageService.credential("no-colon") == nil)
        #expect(XAIAPIUsageService.credential(":key") == nil)
        #expect(XAIAPIUsageService.credential("a/b:key") == nil)
        #expect(XAIAPIUsageService.credential("..:key") == nil)
        #expect(XAIAPIUsageService.endpoint(team: "team 1")?.absoluteString
                == "https://management-api.x.ai/v1/billing/teams/team%201/prepaid/balance")
    }

    @Test("Nothing usable is never sent")
    func missing() async {
        let empty = ProfileContext(provider: .xaiAPI, credential: " ", serverAddress: nil)
        #expect(await XAIAPIUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
        let malformed = ProfileContext(provider: .xaiAPI, credential: "just-a-key", serverAddress: nil)
        #expect(await XAIAPIUsageService.fetch(malformed).state == .unavailable(.apiKeyRefused))
    }
}
