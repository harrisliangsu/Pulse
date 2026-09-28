import Foundation
import Testing
@testable import Pulse

/// Manus's available credits.
///
/// **The fixture is second-hand**: written from CodexBar's Manus provider and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Manus")
struct ManusTests {
    private let context = ProfileContext(provider: .manus, credential: "session_id=abc", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The daily refresh and the monthly credits are size less what's left")
    func credits() throws {
        let usage = ManusUsageService.reading(from: try fixture("manus-credits"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.manus))
        #expect(usage.windows.map(\.kind) == [.daily, .monthly])
        #expect(usage.windows.map(\.usedFraction) == [0.75, 0.7])
        #expect(usage.windows[0].reportsLength)
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-04-13T00:00:00Z"))
        #expect(!usage.windows[1].reportsLength)
        #expect(usage.windows[1].resetsAt == nil)
        // Credits are not money: a count, and nothing to warn against.
        #expect(usage.creditRemaining == nil)
        #expect(usage.creditBalance?.contains("200") == true)
    }

    @Test("An envelope is looked inside")
    func envelope() {
        let json = #"{"data":{"proMonthlyCredits":100,"periodicCredits":40}}"#
        let usage = ManusUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.usedFraction) == [0.6])
        #expect(usage.creditBalance == nil)
    }

    @Test("Missing figures are left off, never read as zero")
    func sparse() {
        let json = #"""
        {"totalCredits":"1200","periodicCredits":"300","proMonthlyCredits":1000,
         "refreshCredits":"bad","maxRefreshCredits":100,"nextRefreshTime":0,"refreshInterval":"DAILY REFRESH"}
        """#
        let usage = ManusUsageService.reading(from: Data(json.utf8), context: context)
        // The refresh has no remainder, so it has no share; the numeric reset
        // is not read either.
        #expect(usage.windows.map(\.kind) == [.monthly])
        #expect(usage.windows.first?.usedFraction == 0.7)
    }

    @Test("A refresh interval not named daily claims no length")
    func otherInterval() {
        let json = #"{"refreshCredits":1,"maxRefreshCredits":4,"refreshInterval":"weekly"}"#
        let usage = ManusUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.first?.kind == .credits)
        #expect(usage.windows.first?.reportsLength == false)
    }

    @Test("Only a total is a balance with no ring")
    func totalOnly() {
        let usage = ManusUsageService.reading(from: Data(#"{"totalCredits":5}"#.utf8), context: context)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditBalance == "5")
    }

    @Test("A reply with no credit figure at all can't be read", arguments: [
        #"{"nextRefreshTime":"2026-04-13T00:00:00Z","refreshInterval":"daily"}"#,
        #"{"code":"unauthenticated","message":"expired"}"#,
        "[]",
        "not json",
    ])
    func unreadable(json: String) {
        let usage = ManusUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("Only the session_id value goes as the token", arguments: [
        ("session_id=abc; other=x", "abc"),
        ("other=x; session_id=a=b", "a=b"),
    ])
    func token(header: String, token: String) {
        #expect(ManusUsageService.sessionToken(from: header) == token)
    }

    @Test("A header without the session is no session")
    func missingSession() async {
        #expect(ManusUsageService.sessionToken(from: "other=x") == nil)
        let empty = ProfileContext(provider: .manus, credential: "other=x", serverAddress: nil)
        #expect(await ManusUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }

    @Test("A refused session is an expired one")
    func refused() {
        let result = ProfileHTTP.classify(.init(data: Data(), status: 401), refused: .sessionExpired)
        #expect(result == .failure(.sessionExpired))
    }
}
