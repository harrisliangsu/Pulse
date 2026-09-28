import Foundation
import Testing
@testable import Pulse

/// v0's billing allowance and rate limit.
///
/// **The fixtures are second-hand**: written from CodexBar's v0 provider and
/// its tests (MIT), not captured from a live account. They pin the shape Pulse
/// reads; they do not prove the shape is right.
@Suite("v0")
struct V0Tests {
    private let context = ProfileContext(provider: .v0, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Token billing and the rate limit are read as size less remainder")
    func tokenBilling() throws {
        let usage = V0UsageService.reading(
            billing: try fixture("v0-billing-token"),
            rateLimit: try fixture("v0-rate-limits"),
            context: context
        )

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.v0))
        #expect(usage.windows.map(\.kind) == [.messages, .credits])
        #expect(usage.windows.map(\.usedFraction) == [0.2, 0.25])
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_800_001_800))
        #expect(usage.windows[1].resetsAt == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(usage.windows.allSatisfy { !$0.reportsLength })
        // The on-demand balance is in no named unit: left out.
        #expect(usage.creditBalance == nil)
    }

    @Test("Legacy billing with no remainder has no share used, and is left off")
    func legacyWithoutRemainder() throws {
        let usage = V0UsageService.reading(
            billing: try fixture("v0-billing-legacy"),
            rateLimit: try fixture("v0-rate-limits"),
            context: context
        )
        #expect(usage.windows.map(\.kind) == [.messages])
    }

    @Test("Legacy billing with a remainder is read")
    func legacy() {
        let json = #"{"billingType":"legacy","data":{"limit":200,"remaining":50,"reset":1800000000000}}"#
        let usage = V0UsageService.reading(billing: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.usedFraction) == [0.75])
        // Milliseconds are read as milliseconds.
        #expect(usage.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test("Nothing with a remainder is no limits, not zero")
    func noFigures() throws {
        let usage = V0UsageService.reading(billing: try fixture("v0-billing-legacy"), rateLimit: nil, context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A billing reply of neither shape can't be read", arguments: [
        #"{"billingType":"prepaid","data":{"limit":1}}"#,
        #"{"data":{"limit":1,"remaining":1}}"#,
        #"{"billingType":"token","data":{"balance":"none"}}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = V0UsageService.reading(billing: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A reset of zero is no reset", arguments: [0.0, -5.0])
    func zeroReset(stamp: Double) {
        #expect(V0UsageService.date(stamp) == nil)
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .v0, credential: " ", serverAddress: nil)
        #expect(await V0UsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
