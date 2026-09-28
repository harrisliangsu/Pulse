import Foundation
import Testing
@testable import Pulse

/// Venice's API balance.
///
/// **The fixture is second-hand**: written from CodexBar's Venice plugin and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Venice")
struct VeniceTests {
    private let context = ProfileContext(provider: .venice, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func read(_ json: String) -> ProviderUsage {
        VeniceUsageService.reading(from: Data(json.utf8), context: context)
    }

    @Test("A dollar balance is read as money, with no ring")
    func dollars() throws {
        let usage = VeniceUsageService.reading(from: try fixture("venice-balance"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.venice))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 25.75, currency: "USD"))
        #expect(usage.creditBalance == VeniceUsageService.money(25.75))
    }

    @Test("A DIEM account's balance is its DIEM, and no percentage is made of the allocation")
    func diem() {
        let usage = read(#"{"canConsume":true,"consumptionCurrency":"DIEM","balances":{"diem":"90.50","usd":"25.75"},"diemEpochAllocation":"100.0"}"#)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditBalance == VeniceUsageService.tokens(90.5))
        #expect(usage.creditRemaining == nil)
    }

    @Test("A health flag is not a percentage: a refusal to spend still shows only the balance")
    func cannotConsume() {
        let usage = read(#"{"canConsume":false,"consumptionCurrency":"USD","balances":{"diem":null,"usd":100.0}}"#)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining?.amount == 100)
    }

    @Test("With no currency named, dollars come before DIEM")
    func unnamed() {
        #expect(read(#"{"canConsume":true,"consumptionCurrency":"BUNDLED_CREDITS","balances":{"diem":50,"usd":10}}"#)
            .creditRemaining?.amount == 10)
        #expect(read(#"{"canConsume":true,"balances":{"diem":50,"usd":null}}"#)
            .creditBalance == VeniceUsageService.tokens(50))
    }

    @Test("No balance at all is nothing to show, not a zero")
    func none() {
        #expect(read(#"{"canConsume":true,"balances":{"diem":null,"usd":""}}"#).state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that can't be read", arguments: [
        "not json", "[]", "{}",
        #"{"canConsume":"yes","balances":{"usd":1}}"#,
        #"{"canConsume":true}"#,
        #"{"canConsume":true,"balances":[]}"#,
        #"{"canConsume":true,"balances":{"usd":"lots"}}"#,
        #"{"canConsume":true,"balances":{"usd":true}}"#,
        #"{"canConsume":true,"consumptionCurrency":7,"balances":{"usd":1}}"#,
    ])
    func unreadable(json: String) {
        #expect(read(json).state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .venice, credential: nil, serverAddress: nil)
        #expect(await VeniceUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }

    @Test("Statuses mean what they mean everywhere", arguments: [
        (401, ProviderUsage.Unavailability.apiKeyRefused), (403, .apiKeyRefused),
        (429, .rateLimited), (500, .serverError),
    ])
    func statuses(status: Int, reason: ProviderUsage.Unavailability) {
        #expect(ProfileHTTP.classify(.init(data: Data(), status: status)) == .failure(reason))
    }
}
