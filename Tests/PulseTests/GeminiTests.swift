import Foundation
import Testing
@testable import Pulse

/// Gemini CLI's quota, the account lookup before it, and the saved login.
///
/// **The fixtures are second-hand**: written from CodexBar's Gemini provider
/// and its tests (MIT), not captured from a live account. They pin the shape
/// Pulse reads; they do not prove the shape is right.
@Suite("Gemini")
struct GeminiTests {
    private let context = ProfileContext(provider: .gemini, credential: nil, serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A home folder of its own, with `.gemini` holding what the test puts there.
    private func home(_ files: [String: String]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gemini-\(UUID().uuidString)")
        let folder = home.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: folder.appendingPathComponent(name))
        }
        return home
    }

    @Test("Each model is its own row, at the least any of its buckets has left")
    func models() throws {
        let usage = GeminiUsageService.reading(
            from: try fixture("gemini-retrieve-user-quota"), context: context, plan: "Gemini Code Assist Standard"
        )

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.gemini))
        #expect(usage.plan == "Gemini Code Assist Standard")
        #expect(usage.windows.map(\.scope) == ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro"])
        #expect(usage.windows.map(\.usedFraction) == [0.125, 1, 0.5])
        #expect(usage.windows.map(\.isExhausted) == [false, true, false])
        // The pro row is its input-token bucket, which has less left — and
        // that bucket's reset, not the other one's.
        #expect(usage.windows[2].resetsAt == ProfileHTTP.date("2026-07-17T01:00:00Z"))
        #expect(usage.windows[1].resetsAt == ProfileHTTP.date("2026-07-17T00:00:00Z"))
    }

    @Test("Google states a reset and no length, so none is claimed")
    func lengthNotClaimed() throws {
        let usage = GeminiUsageService.reading(from: try fixture("gemini-retrieve-user-quota"), context: context)
        #expect(usage.windows.allSatisfy { $0.kind == .daily && !$0.reportsLength })
    }

    @Test("A bucket with no model, or a fraction that isn't one, is left off")
    func strayBuckets() throws {
        let usage = GeminiUsageService.reading(from: try fixture("gemini-retrieve-user-quota"), context: context)
        #expect(!usage.windows.contains { $0.scope == "gemini-2.0-flash" })
        #expect(usage.windows.count == 3)

        let none = Data(#"{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":1.4},{"remainingFraction":0.2}]}"#.utf8)
        #expect(GeminiUsageService.reading(from: none, context: context).state == .unavailable(.noLimitsReported))
        let empty = Data(#"{"buckets":[]}"#.utf8)
        #expect(GeminiUsageService.reading(from: empty, context: context).state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that isn't a quota can't be read", arguments: [#"{"error":"nope"}"#, "[]", "not json"])
    func unreadable(json: String) {
        let usage = GeminiUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("The account lookup gives the project and Google's own plan name")
    func codeAssist() throws {
        let account = GeminiUsageService.codeAssist(from: try fixture("gemini-load-code-assist"))
        #expect(account.project == "cloudaicompanion-123")
        #expect(account.plan == "Gemini Code Assist in Google One AI Pro")
        #expect(!account.unsupportedClient)

        let bare = GeminiUsageService.codeAssist(from: Data(#"{"currentTier":{"id":"free-tier","name":"Gemini Code Assist for individuals"},"cloudaicompanionProject":"  "}"#.utf8))
        #expect(bare.project == nil)
        #expect(bare.plan == "Gemini Code Assist for individuals")
    }

    @Test("An account Google moved off Gemini CLI has no plan here to read")
    func unsupportedClient() throws {
        let account = GeminiUsageService.codeAssist(from: try fixture("gemini-load-code-assist-unsupported"))
        #expect(account.unsupportedClient)
        #expect(account.plan == nil)

        let refused = ProfileHTTP.Reply(data: Data(#"{"error":{"status":"PERMISSION_DENIED"}}"#.utf8), status: 403)
        #expect(GeminiUsageService.quota(refused, unsupportedClient: true) == .failure(.noPlan))
        // Without that, a 403 is a login Google would not take.
        #expect(GeminiUsageService.quota(refused, unsupportedClient: false) == .failure(.localLoginExpired))
        // And Google can say it in the refusal itself.
        let said = ProfileHTTP.Reply(data: Data(#"{"error":{"message":"IneligibleTierError"}}"#.utf8), status: 403)
        #expect(GeminiUsageService.quota(said, unsupportedClient: false) == .failure(.noPlan))
    }

    @Test("Statuses on the quota call", arguments: [
        (401, ProviderUsage.Unavailability.localLoginExpired), (429, .rateLimited), (500, .serverError),
    ])
    func statuses(status: Int, reason: ProviderUsage.Unavailability) {
        let reply = ProfileHTTP.Reply(data: Data(), status: status)
        #expect(GeminiUsageService.quota(reply, unsupportedClient: false) == .failure(reason))
    }

    @Test("The saved login is used only while it is current")
    func savedLogin() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = Int(now.timeIntervalSince1970 * 1000) + 60_000
        let earlier = Int(now.timeIntervalSince1970 * 1000) - 60_000

        #expect(GeminiUsageService.accessToken(
            from: Data(#"{"access_token":"ya29.token","expiry_date":\#(later)}"#.utf8), now: now
        ) == .success("ya29.token"))
        #expect(GeminiUsageService.accessToken(
            from: Data(#"{"access_token":"ya29.token","expiry_date":\#(earlier)}"#.utf8), now: now
        ) == .failure(.localLoginExpired))
        #expect(GeminiUsageService.accessToken(
            from: Data(#"{"refresh_token":"1//r"}"#.utf8), now: now
        ) == .failure(.localLoginExpired))
        #expect(GeminiUsageService.accessToken(from: Data("not json".utf8), now: now) == .failure(.localLoginMissing))
    }

    @Test("A key or Vertex sign-in is not a Google login", arguments: [
        (#"{"security":{"auth":{"selectedType":"gemini-api-key"}}}"#, false),
        (#"{"security":{"auth":{"selectedType":"vertex-ai"}}}"#, false),
        (#"{"selectedAuthType":"gemini-api-key"}"#, false),
        (#"{"security":{"auth":{"selectedType":"oauth-personal"}}}"#, true),
        (#"{"theme":"dark"}"#, true),
    ])
    func authType(settings: String, google: Bool) {
        #expect(GeminiUsageService.usesGoogleLogin(Data(settings.utf8)) == google)
    }

    @Test("No login on this Mac, or one signed in with a key, is asked for, not sent")
    func missingLogin() async throws {
        let empty = try home([:])
        #expect(await GeminiUsageService.fetch(context, home: empty).state == .unavailable(.localLoginMissing))

        let keyed = try home([
            "settings.json": #"{"security":{"auth":{"selectedType":"gemini-api-key"}}}"#,
            "oauth_creds.json": #"{"access_token":"ya29.old","expiry_date":9999999999999}"#,
        ])
        #expect(await GeminiUsageService.fetch(context, home: keyed).state == .unavailable(.localLoginMissing))
    }

    @Test("An expired login is reported, never renewed and never sent")
    func expiredLogin() async throws {
        let stale = try home(["oauth_creds.json": #"{"access_token":"ya29.old","refresh_token":"1//r","expiry_date":1000}"#])
        #expect(await GeminiUsageService.fetch(context, home: stale).state == .unavailable(.localLoginExpired))
        // Left exactly as the CLI wrote it.
        let after = try String(contentsOf: stale.appendingPathComponent(".gemini/oauth_creds.json"), encoding: .utf8)
        #expect(after == #"{"access_token":"ya29.old","refresh_token":"1//r","expiry_date":1000}"#)
    }
}
