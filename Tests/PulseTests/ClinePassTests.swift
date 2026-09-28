import Foundation
import Testing
@testable import Pulse

/// ClinePass's usage limits.
///
/// **The fixture is second-hand**: written from CodexBar's ClinePass plugin
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("ClinePass")
struct ClinePassTests {
    private let context = ProfileContext(provider: .clinePass, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The three named limits are read as reported, shortest first")
    func limits() throws {
        let usage = ClinePassUsageService.reading(from: try fixture("clinepass-usage-limits"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.clinePass))
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        #expect(usage.windows.map(\.usedFraction) == [0.125, 0.34, 0.5675])
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-07-16T10:20:30Z"))
        // A billing month is not a stated length.
        #expect(!usage.windows[2].reportsLength)
        #expect(usage.windows[2].resetsAt == nil)
    }

    @Test("A limit type Cline hasn't named here is left off, not guessed at")
    func unknownType() throws {
        let usage = ClinePassUsageService.reading(from: try fixture("clinepass-usage-limits"), context: context)
        #expect(!usage.windows.contains { $0.id.contains("experimental") })
    }

    @Test("A reply that isn't a successful one can't be read", arguments: [
        #"{"success":false,"data":{"limits":[]}}"#,
        #"{"data":{"limits":[{"type":"weekly","percentUsed":40}]}}"#,
        #"{"success":true,"data":{}}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = ClinePassUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A figure that isn't one is left off, and nothing left is no limits")
    func noFigures() {
        let json = #"{"success":true,"data":{"limits":[{"type":"weekly","percentUsed":-3},{"type":"monthly"}]}}"#
        let usage = ClinePassUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .clinePass, credential: "  ", serverAddress: nil)
        #expect(await ClinePassUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }

    @Test("Statuses mean what they mean everywhere", arguments: [
        (401, ProviderUsage.Unavailability.apiKeyRefused), (403, .apiKeyRefused),
        (429, .rateLimited), (500, .serverError), (404, .serverError),
    ])
    func statuses(status: Int, reason: ProviderUsage.Unavailability) {
        let result = ProfileHTTP.classify(.init(data: Data(), status: status))
        #expect(result == .failure(reason))
    }
}

@Suite("Profiled session cookies")
struct ProfileCookieTests {
    @Test("Only the named cookies are kept, and the first has to be there")
    func exactNames() {
        #expect(ProviderProfile.keep("a=1; b=2; tracking=x", cookies: ["a", "b"]) == "a=1; b=2")
        #expect(ProviderProfile.keep("b=2; tracking=x", cookies: ["a", "b"]) == nil)
        #expect(ProviderProfile.keep("a=; b=2", cookies: ["a", "b"]) == nil)
    }

    @Test("A trailing star is a prefix that must be followed by something")
    func prefixes() {
        let header = "ory_session_abc123=s; csrftoken=c; ory_session_=empty; other=x"
        #expect(ProviderProfile.keep(header, cookies: ["ory_session_*", "csrftoken"]) == "ory_session_abc123=s; csrftoken=c")
        #expect(ProviderProfile.keep("csrftoken=c", cookies: ["ory_session_*", "csrftoken"]) == nil)
        #expect(ProviderProfile.keep("a=1; b=2", cookies: ["*"]) == nil)
    }

    @Test("Alternatives in the first entry: any one is enough, all are kept")
    func alternatives() {
        #expect(ProviderProfile.keep("b=2; x=9", cookies: ["a|b", "c"]) == "b=2")
        #expect(ProviderProfile.keep("a=1; b=2; c=3", cookies: ["a|b", "c"]) == "a=1; b=2; c=3")
        #expect(ProviderProfile.keep("c=3", cookies: ["a|b", "c"]) == nil)
    }
}
