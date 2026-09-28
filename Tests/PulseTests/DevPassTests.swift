import Foundation
import Testing
@testable import Pulse

/// DevPass's plan credits, premium week and key limit.
///
/// **The fixture is second-hand**: written from CodexBar's DevPass provider
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("DevPass")
struct DevPassTests {
    private let context = ProfileContext(provider: .devPass, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The premium week and the cycle's credits are read from their decimal strings")
    func allowances() throws {
        let usage = DevPassUsageService.reading(from: try fixture("devpass-key"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.devPass))
        #expect(usage.plan == "Pro")
        #expect(usage.windows.map(\.kind) == [.weekly, .credits])
        #expect(abs(usage.windows[0].usedFraction - 5 / 35.55) < 0.000_001)
        #expect(abs(usage.windows[1].usedFraction - 25 / 237) < 0.000_001)
        #expect(usage.windows[0].reportsLength)
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-10-01T12:00:00.000Z"))
        // No cycle end is reported; none is inferred.
        #expect(!usage.windows[1].reportsLength)
        #expect(usage.windows[1].resetsAt == nil)
    }

    @Test("A key limit is drawn against all-time spend, with no clock")
    func keyLimit() {
        let json = #"{"data":{"devPlan":"none","usage":"12.5","limit":"50"}}"#
        let usage = DevPassUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.kind) == [.spend])
        #expect(usage.windows.first?.usedFraction == 0.25)
        #expect(usage.windows.first?.resetsAt == nil)
        #expect(usage.plan == nil)
    }

    @Test("Pay as you go with no key limit has no plan")
    func payAsYouGo() {
        let json = #"{"data":{"devPlan":"none","usage":"31.42","limit":null}}"#
        let usage = DevPassUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noPlan))
    }

    @Test("Zero allowances and bad amounts are left off, not drawn")
    func noFigures() {
        let json = #"""
        {"data":{"devPlan":"lite","usage":"1","limit":null,
         "devPlanCreditsUsed":"-4","devPlanCreditsLimit":"100",
         "devPlanPremiumCreditsUsed":"0.00","devPlanPremiumWeeklyLimit":"0","devPlanPremiumWeekResetsAt":null}}
        """#
        let usage = DevPassUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply without a known plan can't be read", arguments: [
        #"{"data":{"devPlan":"enterprise"}}"#,
        #"{"data":{}}"#,
        #"{"devPlan":"pro"}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = DevPassUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .devPass, credential: nil, serverAddress: nil)
        #expect(await DevPassUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
