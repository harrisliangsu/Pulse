import Foundation
import Testing
@testable import Pulse

/// LiteLLM's user and team budgets.
///
/// **The fixtures are second-hand**: written from CodexBar's LiteLLM provider
/// and its tests (MIT), not captured from a live proxy. They pin the shape
/// Pulse reads; they do not prove the shape is right.
@Suite("LiteLLM")
struct LiteLLMTests {
    private let context = ProfileContext(provider: .liteLLM, credential: "sk-key", serverAddress: "https://litellm.example.com/v1")
    private let both = LiteLLMUsageService.Identity(user: "user-123", team: "team-456")

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("/key/info names the key's user and team")
    func identity() throws {
        #expect(LiteLLMUsageService.identity(from: try fixture("litellm-key-info")) == both)
        let blank = #"{"info":{"user_id":"  ","team_id":"team-1"}}"#
        #expect(LiteLLMUsageService.identity(from: Data(blank.utf8)) == .init(user: nil, team: "team-1"))
        #expect(LiteLLMUsageService.identity(from: Data("not json".utf8)) == nil)
    }

    @Test("The key's team budget first, then the user's; another team's is ignored")
    func userAndTeam() throws {
        let usage = LiteLLMUsageService.reading(userInfo: try fixture("litellm-user-info"), identity: both, context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.liteLLM))
        #expect(usage.windows.map(\.id) == ["litellm.team", "litellm.user"])

        let team = usage.windows[0]
        #expect(team.kind == .sharedCredits)
        #expect(abs(team.usedFraction - 215.3245658499998 / 1_000) < 0.000_001)
        // `budget_duration: 7d` is a stated length.
        #expect(team.windowSeconds == 7 * 86_400)
        #expect(team.reportsLength)
        #expect(team.resetsAt == ProfileHTTP.date("2026-06-15T00:00:00Z"))

        let user = usage.windows[1]
        #expect(user.kind == .spend)
        #expect(abs(user.usedFraction - 212.3537162499998 / 300) < 0.000_001)
        // No duration: never turns over, no length claimed.
        #expect(!user.reportsLength)
        #expect(user.resetsAt == nil)
    }

    @Test("A team-only key reads the team's own budget")
    func teamOnly() throws {
        let identity = LiteLLMUsageService.Identity(user: nil, team: "team-456")
        let usage = LiteLLMUsageService.reading(teamInfo: try fixture("litellm-team-info"), identity: identity, context: context)
        #expect(usage.windows.map(\.kind) == [.sharedCredits])
        #expect(usage.windows.first?.usedFraction == 0.25)
        #expect(usage.windows.first?.windowSeconds == 30 * 86_400)
        #expect(usage.windows.first?.reportsLength == true)
    }

    @Test("Spend with no budget is no limits, not a ring at zero")
    func spendOnly() {
        let json = #"{"user_id":"user-123","user_info":{"user_id":"user-123","max_budget":null,"spend":12.5}}"#
        let usage = LiteLLMUsageService.reading(userInfo: Data(json.utf8), identity: .init(user: "user-123", team: nil), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("An answer about someone else can't be read", arguments: [
        #"{"user_info":{"user_id":"other","max_budget":10,"spend":1}}"#,
        #"{"user_id":"other","user_info":{"max_budget":10,"spend":1}}"#,
        #"{"user_info":{"spend":"4"}}"#,
        #"{"teams":[]}"#,
    ])
    func unreadable(json: String) {
        let usage = LiteLLMUsageService.reading(userInfo: Data(json.utf8), identity: .init(user: "user-123", team: nil), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("Another team's answer can't be read")
    func wrongTeam() {
        let json = #"{"team_info":{"team_id":"other","spend":25,"max_budget":100}}"#
        let usage = LiteLLMUsageService.reading(teamInfo: Data(json.utf8), identity: .init(user: nil, team: "team-456"), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("budget_duration becomes a stated length, a month only a sort key", arguments: [
        ("5h", UsageWindow.Kind.fiveHour, 5 * 3_600, true),
        ("1d", .daily, 86_400, true),
        ("24h", .daily, 86_400, true),
        ("7d", .weekly, 7 * 86_400, true),
        ("2w", .other(seconds: 14 * 86_400), 14 * 86_400, true),
        ("30d", .other(seconds: 30 * 86_400), 30 * 86_400, true),
        ("1mo", .monthly, 30 * 86_400, false),
        ("soon", .spend, 30 * 86_400, false),
    ])
    func durations(text: String, kind: UsageWindow.Kind, seconds: Int, stated: Bool) {
        let period = LiteLLMUsageService.period(text)
        #expect(period.kind == kind)
        #expect(period.seconds == seconds)
        #expect(period.stated == stated)
    }

    @Test("Key first, then the address; nothing is sent without both")
    func missingPieces() async {
        let noKey = ProfileContext(provider: .liteLLM, credential: nil, serverAddress: "https://litellm.example.com")
        #expect(await LiteLLMUsageService.fetch(noKey).state == .unavailable(.apiKeyMissing))
        let noAddress = ProfileContext(provider: .liteLLM, credential: "sk-key", serverAddress: " ")
        #expect(await LiteLLMUsageService.fetch(noAddress).state == .unavailable(.serverAddressMissing))
        let plainHTTP = ProfileContext(provider: .liteLLM, credential: "sk-key", serverAddress: "http://litellm.example.com")
        #expect(await LiteLLMUsageService.fetch(plainHTTP).state == .unavailable(.serverAddressRefused))
    }

    @Test("A reading is stamped with the proxy and key it came from")
    func scope() async {
        let noAddress = ProfileContext(provider: .liteLLM, credential: "sk-key", serverAddress: "")
        #expect(await LiteLLMUsageService.fetch(noAddress).sourceScope == nil)
        let refused = ProfileContext(provider: .liteLLM, credential: "sk-key", serverAddress: "http://litellm.example.com")
        #expect(await LiteLLMUsageService.fetch(refused).sourceScope == nil)
        #expect(GatewayAddress.scope(of: context.serverAddress, key: "sk-key") != nil)
    }
}
