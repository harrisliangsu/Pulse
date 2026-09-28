import Foundation
import Testing
@testable import Pulse

/// Abacus AI's compute credits.
///
/// **The fixtures are second-hand**: written from CodexBar's Abacus provider,
/// its docs and its tests (MIT), not captured from a live account. They pin
/// the shape Pulse reads; they do not prove the shape is right.
@Suite("Abacus AI")
struct AbacusTests {
    private let context = ProfileContext(provider: .abacus, credential: "sessionid=abc", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func points(_ result: String) -> Data {
        Data(#"{"success":true,"result":{\#(result)}}"#.utf8)
    }

    @Test("Credits used over the total, with the next billing date as the reset")
    func credits() throws {
        let usage = AbacusUsageService.reading(
            points: try fixture("abacus-compute-points"), billing: try fixture("abacus-billing-info"), context: context
        )

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.abacus))
        #expect(usage.plan == "Pro")
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.kind == .credits)
        #expect(window.usedFraction == 0.25)
        #expect(window.resetsAt == ProfileHTTP.date("2026-10-01T00:00:00Z"))
        // A billing date says when this cycle ends, not how long it is.
        #expect(!window.reportsLength)
        #expect(!window.isExhausted)
    }

    @Test("Without billing info the credits still show, with no reset and no plan", arguments: [
        nil, #"{"success":false,"error":"Something broke"}"#, "not json",
    ])
    func noBilling(billing: String?) throws {
        let usage = AbacusUsageService.reading(
            points: try fixture("abacus-compute-points"), billing: billing.map { Data($0.utf8) }, context: context
        )
        #expect(usage.state == .live)
        #expect(usage.plan == nil)
        #expect(usage.windows.first?.resetsAt == nil)
        #expect(!(usage.windows.first?.reportsLength ?? true))
    }

    @Test("A refusal Abacus sends as a 200 is the session expiring; any other is the service's", arguments: [
        ("Session expired, please login again", ProviderUsage.Unavailability.sessionExpired),
        ("Unauthorized", .sessionExpired),
        ("Internal error", .serverError),
    ])
    func refusals(error: String, reason: ProviderUsage.Unavailability) {
        let data = Data(#"{"success":false,"error":"\#(error)"}"#.utf8)
        #expect(AbacusUsageService.reading(points: data, billing: nil, context: context).state == .unavailable(reason))
    }

    @Test("A reply that isn't one can't be read", arguments: ["not json", #"{"success":true}"#, #"{"result":{}}"#])
    func unreadable(json: String) {
        let usage = AbacusUsageService.reading(points: Data(json.utf8), billing: nil, context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A total of nothing, or a half missing, draws nothing", arguments: [
        #""totalComputePoints":0,"computePointsLeft":0"#,
        #""totalComputePoints":1000"#,
        #""computePointsLeft":750"#,
    ])
    func noFigures(result: String) {
        let usage = AbacusUsageService.reading(points: points(result), billing: nil, context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("Nothing left is the end of the allowance")
    func exhausted() {
        let usage = AbacusUsageService.reading(
            points: points(#""totalComputePoints":500,"computePointsLeft":0"#), billing: nil, context: context
        )
        #expect(usage.windows.first?.usedFraction == 1)
        #expect(usage.windows.first?.isExhausted == true)
    }

    @Test("No session, or one without the session cookie, is asked for, not sent",
          arguments: [nil, "", "_ga=1; csrftoken=2"])
    func missingSession(credential: String?) async {
        let empty = ProfileContext(provider: .abacus, credential: credential, serverAddress: nil)
        #expect(await AbacusUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }
}
