import Foundation
import Testing
@testable import Pulse

/// ZenMux's subscription quotas and pay-as-you-go balance.
///
/// **The fixtures are second-hand**: written from CodexBar's ZenMux provider
/// and its tests (MIT), not captured from a live account. They pin the shape
/// Pulse reads; they do not prove the shape is right.
@Suite("ZenMux")
struct ZenMuxTests {
    private let context = ProfileContext(provider: .zenMux, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Both rolling quotas are read as the fractions ZenMux reports")
    func quotas() throws {
        let usage = ZenMuxUsageService.reading(from: try fixture("zenmux-subscription-detail"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.zenMux))
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(usage.windows.map(\.usedFraction) == [0.0715, 0.0673])
        #expect(usage.windows.allSatisfy { $0.reportsLength })
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-03-24T08:35:09.000Z"))
        #expect(usage.plan == "Ultra")
        // The monthly allowance is sized but not used: left off.
        #expect(usage.windows.count == 2)
        #expect(usage.creditBalance == nil)
    }

    @Test("The PAYG balance is read in the currency ZenMux names")
    func balance() throws {
        let usage = ZenMuxUsageService.reading(
            from: try fixture("zenmux-subscription-detail"),
            balance: try fixture("zenmux-payg-balance"),
            context: context
        )
        #expect(usage.creditRemaining == .init(amount: 482.74, currency: "USD"))
        #expect(usage.creditBalance?.contains("482") == true)
    }

    @Test("An overdue balance stays negative; an unreadable one is left off")
    func balanceEdges() {
        let overdue = #"{"success":true,"data":{"currency":"usd","total_credits":-12.34}}"#
        #expect(ZenMuxUsageService.balance(from: Data(overdue.utf8)) == .init(amount: -12.34, currency: "USD"))
        for json in [#"{"success":false,"data":{"currency":"usd","total_credits":1}}"#,
                     #"{"success":true,"data":{"total_credits":1}}"#, "not json"] {
            #expect(ZenMuxUsageService.balance(from: Data(json.utf8)) == nil)
        }
    }

    @Test("A reply that isn't a successful one can't be read", arguments: [
        #"{"success":false,"data":{}}"#,
        #"{"data":{"quota_5_hour":{"usage_percentage":0.1}}}"#,
        #"{"success":true}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = ZenMuxUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A figure that isn't one is left off, and nothing left is no limits")
    func noFigures() {
        let json = #"{"success":true,"data":{"quota_5_hour":{"usage_percentage":-0.2},"quota_7_day":{"max_flows":10}}}"#
        let usage = ZenMuxUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("Past the quota reads as spent, not clamped")
    func overQuota() {
        let json = #"{"success":true,"data":{"quota_5_hour":{"usage_percentage":1.05}}}"#
        let usage = ZenMuxUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.first?.usedFraction == 1.05)
        #expect(usage.windows.first?.isExhausted == true)
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .zenMux, credential: "  ", serverAddress: nil)
        #expect(await ZenMuxUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
