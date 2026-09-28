import Foundation
import Testing
@testable import Pulse

/// Zed's billing usage, read with a zed.dev browser session.
///
/// **The fixture is second-hand**: written from CodexBar's Zed plugin and its
/// tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Zed")
struct ZedTests {
    private let context = ProfileContext(provider: .zed, credential: "zed.session=s", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Edit predictions and token spend are read as reported")
    func usage() throws {
        let usage = ZedUsageService.reading(from: try fixture("zed-billing-usage"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.zed))
        #expect(usage.windows.map(\.kind) == [.monthly, .spend])
        #expect(usage.windows.map(\.usedFraction) == [0.12, 0.25])
        #expect(usage.windows[0].scope == "Edit Predictions")
        // No period is stated, and nothing says when either turns over.
        #expect(usage.windows.allSatisfy { !$0.reportsLength && $0.resetsAt == nil })
        #expect(usage.plan == "Zed Pro")
        #expect(usage.creditBalance == nil)
    }

    @Test("A limit written as an object reads the same")
    func limitedObject() throws {
        let json = #"{"plan":"zed_pro_trial","current_usage":{"edit_predictions":{"used":10,"limit":{"limited":20}}}}"#
        let usage = ZedUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.usedFraction) == [0.5])
        #expect(usage.plan == "Zed Pro Trial")
    }

    @Test("Overspend is kept, and marked spent")
    func overspend() throws {
        let json = #"{"plan":"zed_pro","current_usage":{"token_spend":{"spend_in_cents":1500,"limit_in_cents":1000}}}"#
        let spend = try #require(ZedUsageService.reading(from: Data(json.utf8), context: context).windows.first)
        #expect(spend.usedFraction == 1.5)
        #expect(spend.isExhausted)
    }

    @Test("Unlimited predictions and no spending limit draw nothing, not a zero", arguments: [
        #"{"plan":"zed_pro","current_usage":{"token_spend":{"spend_in_cents":250,"limit_in_cents":null},"edit_predictions":{"used":12,"limit":"unlimited"}}}"#,
        #"{"plan":"zed_pro","current_usage":{"token_spend":{"spend_in_cents":250},"edit_predictions":{"used":12,"limit":null}}}"#,
    ])
    func unlimited(json: String) {
        let usage = ZedUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A figure that isn't one is left off", arguments: [
        #"{"current_usage":{"token_spend":{"spend_in_cents":-1,"limit_in_cents":1000},"edit_predictions":{"used":true,"limit":100}}}"#,
        #"{"current_usage":{"token_spend":{"spend_in_cents":250,"limit_in_cents":-1},"edit_predictions":{"used":12,"limit":0}}}"#,
    ])
    func badFigures(json: String) {
        let usage = ZedUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that can't be read", arguments: ["{}", "[]", "<html>login</html>", #"{"current_usage":[]}"#])
    func unreadable(json: String) {
        let usage = ZedUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .zed, credential: nil, serverAddress: nil)
        #expect(await ZedUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }

    @Test("Only the session cookie is kept from the browser")
    func keptCookies() {
        guard case .sessionCookie(let host, let cookies) = ProviderProfile.zed.credential else {
            Issue.record("Zed reads a browser session")
            return
        }
        #expect(host == "zed.dev")
        #expect(ProviderProfile.keep("_ga=1; zed.session=abc; other=2", cookies: cookies) == "zed.session=abc")
    }

    @Test("A refused session has expired", arguments: [401, 403])
    func refused(status: Int) {
        let result = ProfileHTTP.classify(.init(data: Data(), status: status), refused: .sessionExpired)
        #expect(result == .failure(.sessionExpired))
    }
}
