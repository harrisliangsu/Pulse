import Foundation
import Testing
@testable import Pulse

/// LLM API Key Proxy's quota groups.
///
/// **The fixture is second-hand**: written from CodexBar's LLM Proxy plugin
/// and its tests (MIT), not captured from a live proxy. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("LLM API Key Proxy")
struct LLMProxyTests {
    private let context = ProfileContext(provider: .llmProxy, credential: "key", serverAddress: "http://192.168.1.10:8000/v1")

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Each quota group is its own row, scoped by upstream and group")
    func groups() throws {
        let usage = LLMProxyUsageService.reading(from: try fixture("llm-proxy-quota-stats"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.llmProxy))
        #expect(usage.windows.map(\.scope) == ["anthropic", "gemini_cli · gemini-2.5-pro", "openai"])
        #expect(usage.windows.map(\.usedFraction) == [0.2, 1, 0.58])
        #expect(usage.windows.map(\.kind) == [.credits, .credits, .credits])
        #expect(usage.windows[1].isExhausted)
        #expect(usage.windows[1].resetsAt == ProfileHTTP.date("2026-05-18T08:00:00.123Z"))
        #expect(usage.windows[2].resetsAt == ProfileHTTP.date("2026-05-18T12:00:00Z"))
        // No group states its period.
        #expect(usage.windows.allSatisfy { !$0.reportsLength })
    }

    @Test("Requests, tokens and cost are spend with no limit, and are left off")
    func spendLeftOff() throws {
        let usage = LLMProxyUsageService.reading(from: try fixture("llm-proxy-quota-stats"), context: context)
        #expect(usage.windows.count == 3)
        #expect(usage.creditBalance == nil)
    }

    @Test("A malformed group list is left out without failing the rest")
    func malformedGroups() {
        let json = #"{"providers":{"a":{"quota_groups":"nope"},"b":{"quota_groups":[{"remaining_percent":90}]}}}"#
        let usage = LLMProxyUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.scope) == ["b"])
    }

    @Test("Figures outside 0–100 are left off, and nothing left is no limits")
    func noFigures() {
        let json = #"{"providers":{"a":{"quota_groups":[{"remaining_percent":-1},{"remaining_percent":150},{}]},"b":{}}}"#
        let usage = LLMProxyUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply with no providers can't be read", arguments: ["not json", "[]", "{}"])
    func unreadable(json: String) {
        let usage = LLMProxyUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key, no address, or an address that may not carry one: nothing is sent")
    func credentials() async {
        let noKey = ProfileContext(provider: .llmProxy, credential: nil, serverAddress: "https://proxy.example.com")
        #expect(await LLMProxyUsageService.fetch(noKey).state == .unavailable(.apiKeyMissing))
        let noAddress = ProfileContext(provider: .llmProxy, credential: "key", serverAddress: nil)
        #expect(await LLMProxyUsageService.fetch(noAddress).state == .unavailable(.serverAddressMissing))
        let plainHTTP = ProfileContext(provider: .llmProxy, credential: "key", serverAddress: "http://proxy.example.com")
        #expect(await LLMProxyUsageService.fetch(plainHTTP).state == .unavailable(.serverAddressRefused))
    }

    @Test("The service root and its /v1 base lead to the same route")
    func route() {
        let root = GatewayAddress.url(from: "https://proxy.example.com", path: "/v1/quota-stats", trimming: ["/v1"])
        let versioned = GatewayAddress.url(from: "https://proxy.example.com/v1", path: "/v1/quota-stats", trimming: ["/v1"])
        #expect(root?.absoluteString == "https://proxy.example.com/v1/quota-stats")
        #expect(versioned == root)
    }
}
