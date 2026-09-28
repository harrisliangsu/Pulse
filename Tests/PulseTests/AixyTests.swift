import Foundation
import Testing
@testable import Pulse

/// Aixy's key-scoped budgets.
///
/// **The fixture is second-hand**: written from the usage contract CodexBar's
/// Aixy provider (MIT) validates — CodexBar ships no Aixy reply of its own —
/// not captured from a live account. It pins the shape Pulse reads; it does not
/// prove the shape is right.
@Suite("Aixy")
struct AixyTests {
    private let context = ProfileContext(provider: .aixy, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("One binding budget per period, shortest first")
    func budgets() throws {
        let usage = AixyUsageService.reading(from: try fixture("aixy-usage"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.aixy))
        #expect(usage.windows.map(\.kind) == [.daily, .monthly, .spend])
        // Daily: the enforced key budget, spent plus reserved, beats the
        // monitored team budget that is further along.
        #expect(usage.windows[0].id == "aixy.b_key_daily")
        #expect(usage.windows[0].usedFraction == 0.3)
        #expect(usage.windows[0].reportsLength)
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-09-21T00:00:00Z"))
        // Monthly: a calendar month, reset as stated, length not claimed.
        #expect(usage.windows[1].usedFraction == 0.25)
        #expect(!usage.windows[1].reportsLength)
        #expect(usage.windows[1].resetsAt == ProfileHTTP.date("2026-10-01T00:00:00Z"))
        // Lifetime: never resets.
        #expect(usage.windows[2].usedFraction == 0.125)
        #expect(usage.windows[2].resetsAt == nil)
    }

    @Test("An unknown balance, and another key's budget, are left off")
    func leftOff() throws {
        let usage = AixyUsageService.reading(from: try fixture("aixy-usage"), context: context)
        #expect(!usage.windows.contains { $0.id == "aixy.b_org_weekly" })
        #expect(!usage.windows.contains { $0.id == "aixy.b_other_key" })
        #expect(!usage.windows.contains { $0.kind == .weekly })
    }

    @Test("Of two budgets alike in kind, the one nearest its limit binds")
    func nearest() {
        let json = #"""
        {"object":"key.usage","currency":"USD","key":{"id":"k","project_id":"p"},"budgets":[
         {"id":"a","interval":"weekly","enforcement":"hard","limit_usd":10,"applies_to":[{"api_key_id":"k","project_id":"p"}],
          "availability":{"status":"available","spent_usd":1,"reserved_usd":0}},
         {"id":"b","interval":"weekly","enforcement":"hard","limit_usd":10,"applies_to":[{"api_key_id":"k","project_id":"p"}],
          "availability":{"status":"available","spent_usd":6,"reserved_usd":"1.5"}}]}
        """#
        let usage = AixyUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.id) == ["aixy.b"])
        #expect(usage.windows.first?.usedFraction == 0.75)
    }

    @Test("No budget with a known balance is no limits, not zero")
    func noBudgets() {
        let json = #"{"object":"key.usage","currency":"USD","key":{"id":"k"},"budgets":[]}"#
        let usage = AixyUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply outside the contract can't be read", arguments: [
        #"{"object":"key.usage","currency":"EUR","key":{"id":"k"},"budgets":[]}"#,
        #"{"object":"usage","currency":"USD","key":{"id":"k"},"budgets":[]}"#,
        #"{"object":"key.usage","currency":"USD","budgets":[]}"#,
        #"{"object":"key.usage","currency":"USD","key":{"id":"k"}}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = AixyUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .aixy, credential: nil, serverAddress: nil)
        #expect(await AixyUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
