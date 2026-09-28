import Foundation
import Testing
@testable import Pulse

/// GitKraken AI's credit usage.
///
/// **The fixture is second-hand**: written from CodexBar's GitKraken plugin
/// and its docs (MIT), which follow GitLens's parser — not captured from a
/// live account. It pins the shape Pulse reads; it does not prove the shape
/// is right.
@Suite("GitKraken AI")
struct GitKrakenTests {
    private let context = ProfileContext(provider: .gitKraken, credential: "token", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Personal credits and the organization's pool, each used out of its limit")
    func credits() throws {
        let usage = GitKrakenUsageService.reading(from: try fixture("gitkraken-usage"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.gitKraken))
        #expect(usage.windows.map(\.kind) == [.credits, .sharedCredits])
        #expect(usage.windows.map(\.usedFraction) == [0.3, 0.3])
        // An offset, not UTC: midnight in +02:00 is 22:00 the day before.
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-07-05T22:00:00Z"))
        // The reply states no length.
        #expect(usage.windows.allSatisfy { !$0.reportsLength })
    }

    @Test("Unlimited (-1) and no allowance (0) draw nothing")
    func unlimited() {
        let json = #"{"data":{"used":50,"limit":-1,"resetsOn":"2026-07-06T00:00:00Z","organization":{"used":1,"limit":0}}}"#
        let usage = GitKrakenUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A malformed pool is left off while the personal figure stays")
    func malformedPool() {
        let json = #"{"data":{"used":10,"limit":100,"resetsOn":"2026-07-06T00:00:00Z","organization":{"used":-4,"limit":100}}}"#
        let usage = GitKrakenUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.kind) == [.credits])
    }

    @Test("A reply with no usage can't be read", arguments: ["not json", #"{"error":"nope"}"#, #"{"data":{}}"#])
    func unreadable(json: String) {
        let usage = GitKrakenUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A pasted header value is reduced to the token")
    func pastedHeader() {
        #expect(GitKrakenUsageService.token(from: "Bearer abc.def") == "abc.def")
        #expect(GitKrakenUsageService.token(from: "abc.def") == "abc.def")
        #expect(GitKrakenUsageService.token(from: "Bearer") == nil)
    }

    @Test("No token is asked for, not sent — a bare \"Bearer\" is no token")
    func missingToken() async {
        for credential in [nil, "  ", "Bearer "] as [String?] {
            let empty = ProfileContext(provider: .gitKraken, credential: credential, serverAddress: nil)
            #expect(await GitKrakenUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
        }
    }
}
