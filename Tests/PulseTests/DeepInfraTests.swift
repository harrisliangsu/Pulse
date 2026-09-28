import Foundation
import Testing
@testable import Pulse

/// DeepInfra's billing checklist.
///
/// **The fixture is second-hand**: written from CodexBar's DeepInfra provider
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("DeepInfra")
struct DeepInfraTests {
    private let context = ProfileContext(provider: .deepInfra, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The inverted ledger reads as money left, and the account's own limit as a ring")
    func checklist() throws {
        let usage = DeepInfraUsageService.reading(from: try fixture("deepinfra-checklist"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.deepInfra))
        // -(−99.75 + 3.94)
        let remaining = try #require(usage.creditRemaining)
        #expect(remaining.currency == "USD")
        #expect(abs(remaining.amount - 95.81) < 0.000_001)
        #expect(usage.creditBalance?.contains("95") == true)

        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.kind == .spend)
        #expect(abs(window.usedFraction - 3.94 / 20) < 0.000_001)
        #expect(!window.reportsLength)
        #expect(window.resetsAt == nil)
    }

    @Test("Money owed is a negative balance, not nothing")
    func owed() {
        let json = #"{"stripe_balance":2.75,"recent":7,"limit":-1}"#
        let usage = DeepInfraUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.creditRemaining == .init(amount: -9.75, currency: "USD"))
        // A limit of -1 is no limit: no ring.
        #expect(usage.windows.isEmpty)
    }

    @Test("An empty account is zero, and negative recent spend is none")
    func empty() {
        let json = #"{"stripe_balance":0,"recent":-1}"#
        let usage = DeepInfraUsageService.reading(from: Data(json.utf8), context: context)
        let amount = usage.creditRemaining?.amount
        #expect(amount == 0)
        #expect(amount?.sign == .plus)
    }

    @Test("Suspension is not drawn as a full ring")
    func suspended() {
        let json = #"{"stripe_balance":-5,"recent":1,"suspended":true,"suspend_reason":"Payment review"}"#
        let usage = DeepInfraUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == .init(amount: 4, currency: "USD"))
    }

    @Test("A checklist without its figures can't be read", arguments: [
        #"{"stripe_balance":"5","recent":1}"#,
        #"{"recent":1}"#,
        #"{"stripe_balance":-5}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = DeepInfraUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .deepInfra, credential: "", serverAddress: nil)
        #expect(await DeepInfraUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
