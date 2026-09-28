import Foundation
import Testing
@testable import Pulse

/// Raycast AI's credits.
///
/// **The fixture is second-hand**: written from CodexBar's Raycast plugin
/// (MIT), not captured from a live account. It pins the shape Pulse reads; it
/// does not prove the shape is right.
@Suite("Raycast AI")
struct RaycastAITests {
    private let context = ProfileContext(provider: .raycastAI, credential: "__raycast_session=abc", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Credits are read as used out of the total, numbers or numeric strings")
    func credits() throws {
        let usage = RaycastAIUsageService.reading(from: try fixture("raycast-ai-credits"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.raycastAI))
        #expect(usage.plan == "Pro+")
        let window = try #require(usage.windows.first)
        #expect(window.kind == .credits)
        #expect(window.usedFraction == 0.25)
        #expect(window.resetsAt == ProfileHTTP.date("2026-07-01T00:00:00Z"))
        #expect(!window.reportsLength)
    }

    @Test("A remainder with no total, or a total of zero, draws nothing", arguments: [
        #"{"remaining_balance_credits":50}"#,
        #"{"remaining_balance_credits":0,"total_balance_credits":0}"#,
        #"{"remaining_balance_credits":-1,"total_balance_credits":100}"#,
    ])
    func noFigures(json: String) {
        let usage = RaycastAIUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that isn't an object can't be read", arguments: ["not json", "[]"])
    func unreadable(json: String) {
        let usage = RaycastAIUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .raycastAI, credential: "", serverAddress: nil)
        #expect(await RaycastAIUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }

    @Test("Only the session and CSRF cookies are kept, and the session is required")
    func cookies() {
        guard case .sessionCookie(let host, let names) = ProviderProfile.raycastAI.credential else {
            Issue.record("Raycast AI should read a browser session")
            return
        }
        #expect(host == "www.raycast.com")
        #expect(ProviderProfile.keep("x=1; csrf_token=t; __raycast_session=s", cookies: names)
            == "csrf_token=t; __raycast_session=s")
        #expect(ProviderProfile.keep("csrf_token=t", cookies: names) == nil)
    }
}
