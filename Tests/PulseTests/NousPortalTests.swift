import Foundation
import Testing
@testable import Pulse

/// Nous Portal's account reply, and the Hermes login it is read with.
///
/// **The fixtures are second-hand**: written from CodexBar's Nous provider,
/// its plugin and its tests (MIT), not captured from a live account or a real
/// Hermes install. They pin the shape Pulse reads; they do not prove the shape
/// is right.
@Suite("Nous Portal")
struct NousPortalTests {
    private let context = ProfileContext(provider: .nousPortal, credential: nil, serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A home folder of its own, with Hermes's file written into it.
    private func home(auth: Data?, shared: Data? = nil) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "nous-\(UUID().uuidString)")
        let hermes = home.appending(path: ".hermes/shared")
        try FileManager.default.createDirectory(at: hermes, withIntermediateDirectories: true)
        if let auth { try auth.write(to: home.appending(path: ".hermes/auth.json")) }
        if let shared { try shared.write(to: hermes.appending(path: "nous_auth.json")) }
        return home
    }

    @Test("The month's grant is a ring, and what can be spent is the balance")
    func account() throws {
        let usage = NousPortalUsageService.reading(from: try fixture("nous-portal-account"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.nousPortal))
        #expect(usage.windows.count == 1)
        let month = try #require(usage.windows.first)
        #expect(month.kind == .monthly)
        // $55 of $220 left: $165 used.
        #expect(month.usedFraction == 0.75)
        #expect(month.resetsAt == ProfileHTTP.date("2026-10-12T04:29:00.000Z"))
        // A billing cycle is not a stated length.
        #expect(!month.reportsLength)
        #expect(usage.plan == "Ultra")
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 74.25, currency: "USD"))
        #expect(usage.creditBalance == NousPortalUsageService.money(74.25))
    }

    @Test("Amounts written as decimals in strings read the same")
    func stringAmounts() throws {
        let json = #"{"subscription":{"monthly_credits":"22","credits_remaining":"0"},"purchased_credits_remaining":"3.25"}"#
        let usage = NousPortalUsageService.reading(from: Data(json.utf8), context: context)
        let month = try #require(usage.windows.first)
        #expect(month.usedFraction == 1)
        #expect(month.isExhausted)
        // No total reported: the top-ups are the balance.
        #expect(usage.creditRemaining?.amount == 3.25)
    }

    @Test("A free account with no grant draws no ring, only the balance it reports")
    func freeTier() {
        let json = #"{"subscription":null,"purchased_credits_remaining":0}"#
        let usage = NousPortalUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining?.amount == 0)
    }

    @Test("A grant with nothing said about what's left is left off, not drawn at zero")
    func grantWithoutRemainder() {
        let json = #"{"subscription":{"plan":"Ultra","monthly_credits":220}}"#
        let usage = NousPortalUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that can't be read", arguments: [
        "not json", "[]", "{}", #"{"subscription":{}}"#,
        #"{"purchased_credits_remaining":true}"#,
        #"{"purchased_credits_remaining":"NaN"}"#,
        #"{"purchased_credits_remaining":""}"#,
        #"{"purchased_credits_remaining":[]}"#,
    ])
    func unreadable(json: String) {
        let usage = NousPortalUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("An error in the reply is the service's error")
    func errorBody() {
        let usage = NousPortalUsageService.reading(from: Data(#"{"error":"boom"}"#.utf8), context: context)
        #expect(usage.state == .unavailable(.serverError))
    }

    @Test("Hermes's login is read, with its portal only if it is Nous's own")
    func login() throws {
        let now = try #require(ProfileHTTP.date("2026-07-16T10:00:00Z"))
        let login = try NousPortalUsageService.storedLogin(
            home: home(auth: fixture("nous-portal-auth")), now: now
        ).get()
        #expect(login.token == "fixture-token")
        #expect(login.portal.absoluteString == "https://preview.nousresearch.com")

        #expect(NousPortalUsageService.trustedPortal("https://evil.example.com") == nil)
        #expect(NousPortalUsageService.trustedPortal("https://notnousresearch.com") == nil)
        #expect(NousPortalUsageService.trustedPortal("http://portal.nousresearch.com") == nil)
        #expect(NousPortalUsageService.trustedPortal("https://portal.nousresearch.com/steal") == nil)
    }

    @Test("A pooled login is the one that lasts longest; a bare state object is read too")
    func otherShapes() throws {
        let pool = #"""
        {"credential_pool":{"nous":[
          {"access_token":"old","expires_at":"2026-07-16T09:00:00Z"},
          {"access_token":"new","expires_at":"2026-07-16T12:00:00Z","portal_base_url":"https://evil.example.com"}]}}
        """#
        let pooled = try #require(NousPortalUsageService.login(from: Data(pool.utf8)))
        #expect(pooled.token == "new")
        #expect(pooled.portal == NousPortalUsageService.defaultPortal)

        let bare = try #require(NousPortalUsageService.login(from: Data(#"{"access_token":"bare"}"#.utf8)))
        #expect(bare.token == "bare")
        #expect(bare.expiresAt == nil)
    }

    @Test("A lapsed login is not sent; the shared copy is tried next")
    func expired() async throws {
        let now = try #require(ProfileHTTP.date("2026-07-16T10:59:30Z"))
        let lapsed = try fixture("nous-portal-auth")
        let usage = await NousPortalUsageService.fetch(context, home: try home(auth: lapsed), now: now)
        #expect(usage.state == .unavailable(.localLoginExpired))

        let fresh = Data(#"{"access_token":"shared","expires_at":"2026-07-16T12:00:00Z"}"#.utf8)
        let found = try NousPortalUsageService.storedLogin(home: home(auth: lapsed, shared: fresh), now: now).get()
        #expect(found.token == "shared")
    }

    @Test("No Hermes login is asked for, not guessed at")
    func missing() async throws {
        let usage = await NousPortalUsageService.fetch(context, home: try home(auth: nil))
        #expect(usage.state == .unavailable(.localLoginMissing))
    }

    @Test("A JWT's own expiry stands in for a missing one")
    func jwt() {
        // {"exp":1784196000} — 2026-07-16T10:00:00Z.
        let token = "e30.eyJleHAiOjE3ODQxOTYwMDB9.sig"
        #expect(NousPortalUsageService.jwtExpiry(token) == Date(timeIntervalSince1970: 1_784_196_000))
        #expect(NousPortalUsageService.jwtExpiry("opaque") == nil)
    }

    @Test("A refused token is the saved login having lapsed", arguments: [401, 403])
    func refused(status: Int) {
        let result = ProfileHTTP.classify(.init(data: Data(), status: status), refused: .localLoginExpired)
        #expect(result == .failure(.localLoginExpired))
    }
}
