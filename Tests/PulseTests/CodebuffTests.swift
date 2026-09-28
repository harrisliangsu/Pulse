import Foundation
import Testing
@testable import Pulse

/// Codebuff's credits and weekly limit, and the login its CLI saves.
///
/// **The fixtures are second-hand**: written from CodexBar's Codebuff provider
/// and its tests (MIT), not captured from a live account. They pin the shape
/// Pulse reads; they do not prove the shape is right.
@Suite("Codebuff")
struct CodebuffTests {
    private let context = ProfileContext(provider: .codebuff, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func home(credentials: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "codebuff-\(UUID().uuidString)")
        let folder = home.appending(path: ".config/manicode")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let credentials { try Data(credentials.utf8).write(to: folder.appending(path: "credentials.json")) }
        return home
    }

    @Test("Credits alone, as an API key reads them")
    func credits() throws {
        let usage = CodebuffUsageService.reading(usage: try fixture("codebuff-usage"), subscription: nil, context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.codebuff))
        let credits = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(credits.kind == .credits)
        #expect(credits.usedFraction == 0.25)
        #expect(credits.resetsAt == ProfileHTTP.date("2026-05-01T00:00:00Z"))
        #expect(!credits.reportsLength)
        #expect(usage.creditBalance == (3750.0).formatted(.number.precision(.fractionLength(0...1)).locale(LocalizationSource.locale)))
        // Credits are not money.
        #expect(usage.creditRemaining == nil)
    }

    @Test("With the CLI's login, the weekly limit and the tier too, shortest first")
    func weekly() throws {
        let usage = CodebuffUsageService.reading(
            usage: try fixture("codebuff-usage"), subscription: try fixture("codebuff-subscription"), context: context
        )
        #expect(usage.windows.map(\.kind) == [.weekly, .credits])
        #expect(usage.windows[0].usedFraction == 0.3)
        #expect(usage.windows[0].reportsLength)
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-05-08T00:00:00Z"))
        #expect(usage.plan == "Pro")
    }

    @Test("Figures written as strings, and resets as seconds, read the same")
    func strings() throws {
        let json = #"{"usage":"12","quota":"100","remainingBalance":"88","next_quota_reset":1777680000}"#
        let usage = CodebuffUsageService.reading(usage: Data(json.utf8), subscription: nil, context: context)
        let credits = try #require(usage.windows.first)
        #expect(credits.usedFraction == 0.12)
        #expect(credits.resetsAt == Date(timeIntervalSince1970: 1_777_680_000))
    }

    @Test("A missing quota is left off, not drawn as spent; a weekly limit with no use reported too")
    func missingQuota() {
        let json = #"{"usage":25,"remainingBalance":75}"#
        let subscription = #"{"rateLimit":{"weeklyLimit":7000}}"#
        let usage = CodebuffUsageService.reading(
            usage: Data(json.utf8), subscription: Data(subscription.utf8), context: context
        )
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditBalance != nil)
    }

    @Test("Nothing reported at all is no limits; negative figures are none")
    func nothing() {
        for json in ["{}", #"{"usage":-1,"quota":-5,"remainingBalance":-2}"#] {
            let usage = CodebuffUsageService.reading(usage: Data(json.utf8), subscription: nil, context: context)
            #expect(usage.state == .unavailable(.noLimitsReported))
        }
    }

    @Test("A reply that can't be read", arguments: ["not json", "[]"])
    func unreadable(json: String) {
        let usage = CodebuffUsageService.reading(usage: Data(json.utf8), subscription: nil, context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("An unreadable subscription reply leaves the credits standing")
    func badSubscription() throws {
        let usage = CodebuffUsageService.reading(
            usage: try fixture("codebuff-usage"), subscription: Data("oops".utf8), context: context
        )
        #expect(usage.windows.map(\.kind) == [.credits])
    }

    @Test("The CLI's saved token is read from either place it keeps it")
    func savedToken() throws {
        #expect(CodebuffUsageService.savedToken(home: try home(credentials: #"{"default":{"authToken":" a "}}"#)) == "a")
        #expect(CodebuffUsageService.savedToken(home: try home(credentials: #"{"authToken":"b","fingerprintId":"fp"}"#)) == "b")
        #expect(CodebuffUsageService.savedToken(home: try home(credentials: #"{"default":{}}"#)) == nil)
        #expect(CodebuffUsageService.savedToken(home: try home(credentials: nil)) == nil)
    }

    @Test("No key pasted and no CLI login is asked for, not sent")
    func missing() async throws {
        let empty = ProfileContext(provider: .codebuff, credential: nil, serverAddress: nil)
        let usage = await CodebuffUsageService.fetch(empty, home: try home(credentials: nil))
        #expect(usage.state == .unavailable(.apiKeyMissing))
    }
}
