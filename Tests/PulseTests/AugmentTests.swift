import Foundation
import Testing
@testable import Pulse

/// Augment Code's credits for the billing cycle.
///
/// **The fixtures are second-hand**: written from CodexBar's Augment provider,
/// its tests and its notes on the `auggie` CLI's output (MIT), not captured
/// from a live account. They pin the shape Pulse reads; they do not prove the
/// shape is right.
@Suite("Augment Code")
struct AugmentTests {
    private let context = ProfileContext(provider: .augment, credential: "_session=abc", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func reading(_ credits: String, subscription: Data? = nil) -> ProviderUsage {
        AugmentUsageService.reading(credits: Data(credits.utf8), subscription: subscription, context: context)
    }

    @Test("Credits used against credits available, with the cycle's end as the reset")
    func credits() throws {
        let usage = AugmentUsageService.reading(
            credits: try fixture("augment-credits"),
            subscription: try fixture("augment-subscription"),
            context: context
        )

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.augment))
        #expect(usage.plan == "Max")
        #expect(usage.windows.count == 1)
        let window = try #require(usage.windows.first)
        #expect(window.kind == .credits)
        #expect(window.usedFraction == 130_946.0 / 450_000.0)
        #expect(window.resetsAt == ProfileHTTP.date("2026-06-09T00:00:00Z"))
        // A billing cycle is not a length Augment states.
        #expect(!window.reportsLength)
        #expect(!window.isExhausted)
    }

    @Test("Without the subscription reply the figures still stand, with no plan and no reset")
    func noSubscription() throws {
        let usage = AugmentUsageService.reading(credits: try fixture("augment-credits"), subscription: nil,
                                                context: context)
        #expect(usage.state == .live)
        #expect(usage.plan == nil)
        #expect(usage.windows.first?.resetsAt == nil)

        let garbled = reading(#"{"usageUnitsConsumedThisBillingCycle":1,"usageUnitsAvailable":4}"#,
                              subscription: Data("<html>".utf8))
        #expect(garbled.windows.first?.usedFraction == 0.25)
        #expect(garbled.plan == nil)
    }

    @Test("No stated allowance draws nothing — remaining plus consumed is not a limit Augment gave", arguments: [
        #"{"usageUnitsRemaining":15,"usageUnitsConsumedThisBillingCycle":10}"#,
        #"{"usageUnitsRemaining":15,"usageUnitsConsumedThisBillingCycle":10,"usageUnitsAvailable":0}"#,
        #"{"usageUnitsRemaining":15,"usageUnitsConsumedThisBillingCycle":-10,"usageUnitsAvailable":100}"#,
        #"{"usageUnitsRemaining":15,"usageUnitsAvailable":100}"#,
    ])
    func noAllowance(json: String) {
        #expect(reading(json).state == .unavailable(.noLimitsReported))
    }

    @Test("A spent allowance says so")
    func exhausted() {
        let usage = reading(#"{"usageUnitsConsumedThisBillingCycle":120,"usageUnitsAvailable":100}"#)
        #expect(usage.windows.first?.isExhausted == true)
        #expect(usage.windows.first?.usedFraction == 1.2)
    }

    @Test("A reply that can't be read", arguments: ["not json", "<html><body>Sign in</body></html>", "[]"])
    func unreadable(body: String) {
        #expect(reading(body).state == .unavailable(.unreadableReply))
    }

    @Test("Only the session cookies are kept from the browser, and _session must be one")
    func cookies() throws {
        guard case .sessionCookie(let host, let names) = ProviderProfile.augment.credential else {
            Issue.record("Augment reads a browser session")
            return
        }
        #expect(host == "app.augmentcode.com")
        let kept = ProviderProfile.keep("_ga=1; _session=abc; web_rpc_proxy_session=def; other=2", cookies: names)
        #expect(kept == "_session=abc; web_rpc_proxy_session=def")
        #expect(ProviderProfile.keep("web_rpc_proxy_session=def", cookies: names) == nil)
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .augment, credential: nil, serverAddress: nil)
        #expect(await AugmentUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }

    @Test("A refused session is an expired one", arguments: [401, 403])
    func refused(status: Int) {
        let result = ProfileHTTP.classify(.init(data: Data(), status: status), refused: .sessionExpired)
        #expect(result == .failure(.sessionExpired))
    }

    @Test("Other statuses mean what they mean everywhere", arguments: [
        (429, ProviderUsage.Unavailability.rateLimited), (500, .serverError), (404, .serverError),
    ])
    func statuses(status: Int, reason: ProviderUsage.Unavailability) {
        #expect(ProfileHTTP.classify(.init(data: Data(), status: status), refused: .sessionExpired) == .failure(reason))
    }
}
