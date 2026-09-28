import Foundation
import Testing
@testable import Pulse

/// Neuralwatt's quota: subscription kWh, key allowance and prepaid balance.
///
/// **The fixture is second-hand**: written from CodexBar's Neuralwatt provider
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("Neuralwatt")
struct NeuralwattTests {
    private let context = ProfileContext(provider: .neuralwatt, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Subscription kWh, the key's allowance and the prepaid balance are read apart")
    func quota() throws {
        let usage = NeuralwattUsageService.reading(from: try fixture("neuralwatt-quota"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.neuralwatt))
        #expect(usage.plan == "Pro")
        #expect(usage.creditRemaining == .init(amount: 51, currency: "USD"))
        #expect(usage.creditBalance?.contains("51") == true)

        #expect(usage.windows.map(\.kind) == [.monthly, .spend])
        let subscription = usage.windows[0]
        #expect(subscription.usedFraction == 0.25)
        // Both ends of the period are stated, so its length is.
        #expect(subscription.reportsLength)
        #expect(subscription.windowSeconds == 30 * 86_400)
        #expect(subscription.resetsAt == ProfileHTTP.date("2026-10-10T00:00:00Z"))

        let allowance = usage.windows[1]
        #expect(allowance.usedFraction == 0.25)
        #expect(!allowance.reportsLength)
    }

    @Test("No subscription leaves the balance standing alone")
    func prepaidOnly() {
        let json = #"{"balance":{"credits_remaining_usd":0,"total_credits_usd":0},"subscription":null}"#
        let usage = NeuralwattUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == .init(amount: 0, currency: "USD"))
    }

    @Test("The allowance is used plus left when its size isn't stated")
    func derivedAllowance() {
        let json = #"{"balance":{"credits_used_usd":2,"total_credits_usd":10},"subscription":{"kwh_used":1,"kwh_remaining":3}}"#
        let usage = NeuralwattUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.usedFraction) == [0.25])
        // No interval and no period: an allowance, not a month.
        #expect(usage.windows.first?.kind == .credits)
        #expect(usage.windows.first?.reportsLength == false)
        #expect(usage.creditRemaining == .init(amount: 8, currency: "USD"))
    }

    @Test("A blocked key is not a full ring, and figures that aren't are left off")
    func noFigures() {
        let json = #"""
        {"balance":{"accounting_method":"energy"},
         "subscription":{"kwh_included":0,"kwh_used":1},
         "key":{"allowance":{"blocked":true,"limit_usd":0}}}
        """#
        let usage = NeuralwattUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply without a balance can't be read", arguments: [
        #"{"subscription":{"kwh_included":10,"kwh_used":1}}"#,
        #"{"balance":{"credits_remaining_usd":"51"}}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = NeuralwattUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .neuralwatt, credential: nil, serverAddress: nil)
        #expect(await NeuralwattUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
