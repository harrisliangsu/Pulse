import Foundation
import Testing
@testable import Pulse

/// T3 Chat's customer data, streamed as tRPC JSON lines.
///
/// **The fixture is second-hand**: written from CodexBar's T3 Chat plugin and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("T3 Chat")
struct T3ChatTests {
    private let context = ProfileContext(provider: .t3Chat, credential: "wos-session=abc", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The four-hour window and the month are read as reported")
    func windows() throws {
        let usage = T3ChatUsageService.reading(from: try fixture("t3-chat-customer-data"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.t3Chat))
        #expect(usage.plan == "Pro")
        #expect(usage.windows.map(\.kind) == [.other(seconds: 4 * 3_600), .monthly])
        #expect(usage.windows.map(\.usedFraction) == [0.125, 0.3425])
        // Milliseconds, both of them.
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_779_366_216.92))
        #expect(usage.windows[1].resetsAt == Date(timeIntervalSince1970: 1_780_763_009))
        #expect(!usage.windows[1].reportsLength)
    }

    @Test("The billing reset is not the month's, and seconds read as seconds")
    func dates() {
        let json = #"{"json":[{"usageMonthPercentage":20,"billingNextResetAt":1779366216920,"usageFourHourPercentage":1,"usageWindowNextResetAt":1779366216}]}"#
        let usage = T3ChatUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows[1].resetsAt == nil)
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_779_366_216))
    }

    @Test("A percentage T3 Chat leaves out is left off, not drawn as zero")
    func missingPercent() {
        let json = #"{"json":[{"subTier":"free","usageFourHourPercentage":5,"usagePeriodPercentage":65}]}"#
        let usage = T3ChatUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.kind) == [.other(seconds: 4 * 3_600)])
        #expect(usage.plan == "Free")
    }

    @Test("A reply with no customer record can't be read", arguments: ["not json", #"{"json":[1,2,3]}"#, ""])
    func unreadable(json: String) {
        let usage = T3ChatUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("Negative figures are left off, and nothing left is no limits")
    func noFigures() {
        let json = #"{"json":{"subscription":{},"usageBand":"max","usageFourHourPercentage":-4}}"#
        let usage = T3ChatUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .t3Chat, credential: nil, serverAddress: nil)
        #expect(await T3ChatUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }

    @Test("A refused session means the session expired")
    func refused() {
        #expect(ProfileHTTP.classify(.init(data: Data(), status: 401), refused: .sessionExpired) == .failure(.sessionExpired))
    }

    @Test("Only the named cookies are kept")
    func cookies() {
        guard case .sessionCookie(let host, let names) = ProviderProfile.t3Chat.credential else {
            Issue.record("T3 Chat should read a browser session")
            return
        }
        #expect(host == "t3.chat")
        #expect(ProviderProfile.keep("a=1; wos-session=xyz; b=2", cookies: names) == "wos-session=xyz")
    }
}
