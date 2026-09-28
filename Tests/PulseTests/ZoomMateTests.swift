import Foundation
import Testing
@testable import Pulse

/// ZoomMate's credit allowance, and the session-to-token exchange before it.
///
/// **The fixtures are second-hand**: written from CodexBar's ZoomMate provider
/// and its tests (MIT), whose payloads are themselves synthetic — not captured
/// from a live account. They pin the shape Pulse reads; they do not prove the
/// shape is right.
@Suite("ZoomMate")
struct ZoomMateTests {
    private let context = ProfileContext(provider: .zoomMate, credential: "_zm_ssid=abc", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func status(_ fields: String) -> Data {
        Data(#"{"data":{"credit_status":{\#(fields)}}}"#.utf8)
    }

    @Test("Credits used over the budget cap, for the cycle ZoomMate states")
    func credits() throws {
        let usage = ZoomMateUsageService.reading(from: try fixture("zoommate-credits-status"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.zoomMate))
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.kind == .credits)
        #expect(window.usedFraction == 678.0 / 12_345.0)
        // Both ends of the cycle are stated, so its length is too.
        #expect(window.windowSeconds == 2_678_399)
        #expect(window.reportsLength)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_896_134_399))
        #expect(!window.isExhausted)
    }

    @Test("Without the cycle's start, its length isn't claimed")
    func noStart() throws {
        let usage = ZoomMateUsageService.reading(
            from: status(#""budget_cap":100,"used_credit":10,"cycle_end_date":1896134399000"#), context: context
        )
        let window = try #require(usage.windows.first)
        #expect(!window.reportsLength)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_896_134_399))
    }

    @Test("Used is taken from what is left of the cap when only that is reported")
    func fromRemaining() {
        let usage = ZoomMateUsageService.reading(from: status(#""budget_cap":200,"remaining_credit":150"#), context: context)
        #expect(usage.windows.map(\.usedFraction) == [0.25])
    }

    @Test("Past the cap is the end only when overage isn't allowed", arguments: [(false, true), (true, false)])
    func overage(allowed: Bool, exhausted: Bool) {
        let usage = ZoomMateUsageService.reading(
            from: status(#""budget_cap":100,"used_credit":120,"allow_overage":\#(allowed)"#), context: context
        )
        #expect(usage.windows.first?.usedFraction == 1.2)
        #expect(usage.windows.first?.isExhausted == exhausted)
    }

    @Test("Unlimited, a cap of nothing, or a figure that isn't one draws nothing", arguments: [
        #""budget_cap":100,"used_credit":10,"is_unlimited":true"#,
        #""budget_cap":0,"used_credit":10"#,
        #""used_credit":10"#,
        #""budget_cap":100"#,
        #""budget_cap":100,"used_credit":-5"#,
    ])
    func noFigures(fields: String) {
        let usage = ZoomMateUsageService.reading(from: status(fields), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply without a credit status can't be read", arguments: ["not json", "{}", #"{"data":{}}"#])
    func unreadable(json: String) {
        let usage = ZoomMateUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("The session is exchanged for the token in data.nak")
    func token() throws {
        #expect(ZoomMateUsageService.token(from: try fixture("zoommate-login")) == .success("fake-minted-jwt"))
    }

    @Test("An exchange that says it failed is the session turned away; anything else can't be read", arguments: [
        (#"{"success":false}"#, ProviderUsage.Unavailability.sessionExpired),
        (#"{"success":true,"data":{"nak":""}}"#, .unreadableReply),
        ("<html>", .unreadableReply),
    ])
    func tokenFailure(json: String, reason: ProviderUsage.Unavailability) {
        #expect(ZoomMateUsageService.token(from: Data(json.utf8)) == .failure(reason))
    }

    @Test("Only Zoom's own two API hosts are ever asked")
    func hosts() {
        #expect(ZoomMateUsageService.hosts == ["ai.zoom.us", "zoommate.zoom.us"])
    }

    @Test("No session, or one without Zoom's session cookie, is asked for, not sent",
          arguments: [nil, "", "cf_clearance=1"])
    func missingSession(credential: String?) async {
        let empty = ProfileContext(provider: .zoomMate, credential: credential, serverAddress: nil)
        #expect(await ZoomMateUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }
}
