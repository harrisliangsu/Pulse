import Foundation
import Testing
@testable import Pulse

/// Devin can be reached two ways, and they need not answer for the same account
/// **or the same organization**: the endpoint is organization-scoped, while the
/// plan row the app saved is keyed only by a user id. A quota or a plan name
/// borrowed across those is the same invention as a made-up percentage. These
/// drive the **real** service routes with an injected credential, store and
/// endpoint — no browser, no network, nothing read off this Mac — and then the
/// cache, which is where a fallback actually happens.
@Suite("Devin account and organization scope")
struct DevinAccountMixingTests {
    /// The endpoint call, failing the way a dropped connection does.
    private static let failing: @Sendable (DevinUsageService.Credential) async -> ProviderUsage = { _ in
        .unavailable(.devin, reason: .unreachable)
    }

    /// The endpoint call succeeding, with the reply's own plan name. `Date()`
    /// at the moment it is called, so the banked reading is never aged out
    /// against the test's own clock.
    private static let succeeding: @Sendable (DevinUsageService.Credential) async -> ProviderUsage = { _ in
        ProviderUsage(
            account: AccountKey(.devin),
            windows: [UsageWindow(
                id: "devin-weekly", kind: .weekly, scope: nil,
                usedFraction: 0.2, windowSeconds: 604_800, resetsAt: nil
            )],
            observedAt: Date(),
            state: .live,
            plan: "Endpoint",
            creditBalance: nil
        )
    }

    private static func browserCredential(
        userID: String,
        org: String,
        token: String = "auth1_abcdefghijklmnopqrstuvwxyz"
    ) throws -> DevinUsageService.Credential {
        try #require(DevinUsageService.Credential(storage: [
            "auth1_session": #"{"token":"\#(token)","userId":"\#(userID)"}"#,
            "last-internal-org-for-external-org-v1-null": org,
        ]))
    }

    private static func service(
        credential: DevinUsageService.Credential? = nil,
        store: URL? = nil,
        endpoint: @escaping @Sendable (DevinUsageService.Credential) async -> ProviderUsage,
        now: Date
    ) -> DevinUsageService {
        DevinUsageService(
            credential: credential,
            store: store,
            endpoint: endpoint,
            clock: { now },
            searchesBrowser: false
        )
    }

    private static func cache() -> UsageCache {
        UsageCache(
            file: FileManager.default.temporaryDirectory
                .appending(path: "pulse-devin-scope-\(UUID().uuidString).json")
        )
    }

    // MARK: - Scope is not a user id

    @Test("The endpoint scope carries the organization, not only the user")
    func endpointScopeCarriesOrganization() throws {
        let credential = try Self.browserCredential(userID: "user-current", org: "org-aaa")
        #expect(credential.endpointScope == UsageScope(
            route: .endpoint, organization: "organizations/org-aaa", identity: "user-current"
        ))
    }

    @Test("A scope match needs route, organization and identity together")
    func scopeMatchNeedsAllThree() {
        let base = UsageScope(route: .endpoint, organization: "organizations/org-aaa", identity: "user")
        #expect(UsageScope.match(base, base))

        // The same user id under another organization is another allowance.
        #expect(!UsageScope.match(
            base, UsageScope(route: .endpoint, organization: "organizations/org-bbb", identity: "user")
        ))
        // A different user is a different account.
        #expect(!UsageScope.match(
            base, UsageScope(route: .endpoint, organization: "organizations/org-aaa", identity: "other")
        ))
        // Another route is not comparable at all.
        #expect(!UsageScope.match(
            base, UsageScope(route: .appCache, organization: "organizations/org-aaa", identity: "user")
        ))
        // No identity is the absence of evidence, not a wildcard.
        #expect(!UsageScope.match(
            base, UsageScope(route: .endpoint, organization: "organizations/org-aaa", identity: nil)
        ))
        #expect(!UsageScope.match(nil, base))
        let unnamed = UsageScope(route: .endpoint, organization: "organizations/org-aaa", identity: "")
        #expect(!UsageScope.match(unnamed, unnamed))
        let noOrganization = UsageScope(route: .endpoint, organization: nil, identity: "user")
        #expect(!UsageScope.match(noOrganization, noOrganization))
    }

    // MARK: - Routing

    @Test("An endpoint failure never falls across to the app's saved plan")
    func endpointFailureDoesNotFuseTheAppCache() async throws {
        let now = Date()
        let support = try Self.scratchSupport(now: now)
        defer { try? FileManager.default.removeItem(at: support) }
        let credential = try Self.browserCredential(userID: "user-current", org: "org-aaa")

        let withCredential = Self.service(credential: credential, store: support, endpoint: Self.failing, now: now)
        let out = await withCredential.fetch(source: .automatic)

        // The endpoint was tried and refused; the saved plan is not evidence
        // that it failed for the same organization, so it is not shown.
        #expect(out.state == .unavailable(.unreachable))
        #expect(out.plan == nil)

        // The saved plan still answers its own route...
        let tooling = await Self.service(store: support, endpoint: Self.failing, now: now)
            .fetch(source: .tooling)
        #expect(tooling.plan == "Pro")
        #expect(tooling.sourceScope == UsageScope(route: .appCache, organization: nil, identity: "user-current"))

        // ...and automatic with no credential at all still uses it.
        let noCredential = await Self.service(store: support, endpoint: Self.failing, now: now)
            .fetch(source: .automatic)
        #expect(noCredential.plan == "Pro")
    }

    @Test("The endpoint's own plan name is kept, since the endpoint is describing itself")
    func endpointPlanNameIsKept() async throws {
        let credential = try Self.browserCredential(userID: "user-current", org: "org-aaa")
        let out = await Self.service(credential: credential, endpoint: Self.succeeding, now: Date())
            .fetch(source: .automatic)
        #expect(out.plan == "Endpoint")
        #expect(out.sourceScope?.organization == "organizations/org-aaa")
    }

    // MARK: - Cache fallback stays inside one scope

    @Test("An endpoint failure falls back only within the same account and organization")
    func endpointFallbackMatchesScope() async throws {
        let cache = Self.cache()
        let orgAUserCurrent = try Self.browserCredential(userID: "user-current", org: "org-aaa")
        let orgBUserCurrent = try Self.browserCredential(userID: "user-current", org: "org-bbb")
        let orgAUserOther = try Self.browserCredential(userID: "user-other", org: "org-aaa")

        // A successful endpoint reading under org A / user-current is banked.
        let good = await Self.service(credential: orgAUserCurrent, endpoint: Self.succeeding, now: Date())
            .fetch(source: .automatic)
        _ = await cache.reconciled(good)
        #expect(good.state == .live)

        // Same route, organization and identity: the banked figures stand in.
        let same = await Self.service(credential: orgAUserCurrent, endpoint: Self.failing, now: Date())
            .fetch(source: .automatic)
        let shownSame = await cache.reconciled(same)
        #expect(shownSame.state == .stale)
        #expect(shownSame.plan == "Endpoint")

        // Same user, different organization: not this allowance.
        let otherOrg = await Self.service(credential: orgBUserCurrent, endpoint: Self.failing, now: Date())
            .fetch(source: .automatic)
        #expect(await cache.reconciled(otherOrg).state == .unavailable(.unreachable))

        // Different user: not this account.
        let otherUser = await Self.service(credential: orgAUserOther, endpoint: Self.failing, now: Date())
            .fetch(source: .automatic)
        #expect(await cache.reconciled(otherUser).state == .unavailable(.unreachable))
    }

    @Test("A pasted credential is named by a hash, so its own readings match and another's do not")
    func pastedCredentialScope() async throws {
        let cache = Self.cache()
        let pasted = try #require(DevinUsageService.Credential(
            pasted: "auth1_abcdefghijklmnopqrstuvwxyz org_aaa"
        ))
        let sameToken = try #require(DevinUsageService.Credential(
            pasted: "auth1_abcdefghijklmnopqrstuvwxyz org_aaa"
        ))
        let otherToken = try #require(DevinUsageService.Credential(
            pasted: "auth1_zzzzzzzzzzzzzzzzzzzzzzzzzzzz org_aaa"
        ))
        // A pasted token names no user, so the scope's identity is a hash.
        #expect(pasted.accountID == nil)
        #expect(pasted.endpointScope.identity?.hasPrefix("auth1_") == false)

        let good = await Self.service(credential: pasted, endpoint: Self.succeeding, now: Date())
            .fetch(source: .automatic)
        _ = await cache.reconciled(good)

        let same = await Self.service(credential: sameToken, endpoint: Self.failing, now: Date())
            .fetch(source: .automatic)
        #expect(await cache.reconciled(same).state == .stale)

        let other = await Self.service(credential: otherToken, endpoint: Self.failing, now: Date())
            .fetch(source: .automatic)
        #expect(await cache.reconciled(other).state == .unavailable(.unreachable))
    }

    @Test("Expired endpoint content cannot bypass the organization check")
    func expiredContentStillChecksScope() async throws {
        let cache = Self.cache()
        let now = Date()
        let orgA = try Self.browserCredential(userID: "user-current", org: "org-aaa")
        let orgB = try Self.browserCredential(userID: "user-current", org: "org-bbb")
        let good = await Self.service(credential: orgA, endpoint: Self.succeeding, now: now)
            .fetch(source: .automatic)
        _ = await cache.reconciled(good)
        let expired: @Sendable (DevinUsageService.Credential) async -> ProviderUsage = { _ in
            ProviderUsage(
                account: AccountKey(.devin), windows: good.windows,
                observedAt: now.addingTimeInterval(-48 * 3600), state: .live,
                plan: "Expired", creditBalance: nil
            )
        }
        let other = await Self.service(credential: orgB, endpoint: expired, now: now)
            .fetch(source: .automatic)
        #expect(await cache.reconciled(other).state == .unavailable(.noLimitsReported))
        let same = await Self.service(credential: orgA, endpoint: expired, now: now)
            .fetch(source: .automatic)
        #expect(await cache.reconciled(same).plan == "Endpoint")
    }

    @Test("A legacy flat session names nobody and never borrows the saved plan's scope")
    func legacyCredentialDoesNotMatchAppCache() async throws {
        let now = Date()
        let support = try Self.scratchSupport(now: now)
        defer { try? FileManager.default.removeItem(at: support) }
        let cache = Self.cache()

        // Bank the saved plan; its scope is the app-cache route and user-current.
        let appPlan = await Self.service(store: support, endpoint: Self.failing, now: now)
            .fetch(source: .tooling)
        _ = await cache.reconciled(appPlan)

        // The older storefront's flat token carries no user beside it.
        let legacy = try #require(DevinUsageService.Credential(storage: [
            "devin_auth1_token": #""auth1_abcdefghijklmnopqrstuvwxyz""#,
            "devin_primary_org_id": "org_aaa",
        ]))
        #expect(legacy.accountID == nil)

        let failure = await Self.service(credential: legacy, endpoint: Self.failing, now: now)
            .fetch(source: .automatic)
        #expect(await cache.reconciled(failure).state == .unavailable(.unreachable))
    }

    @Test("Scope survives a restart, so the same one still falls back and another does not")
    func scopeSurvivesRestart() async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "pulse-devin-restart-\(UUID().uuidString).json")
        let orgA = try Self.browserCredential(userID: "user-current", org: "org-aaa")
        let orgB = try Self.browserCredential(userID: "user-current", org: "org-bbb")

        let first = UsageCache(file: file)
        let good = await Self.service(credential: orgA, endpoint: Self.succeeding, now: Date())
            .fetch(source: .automatic)
        _ = await first.reconciled(good)

        // A new cache reads the scope back off disk.
        let restarted = UsageCache(file: file)
        let same = await Self.service(credential: orgA, endpoint: Self.failing, now: Date())
            .fetch(source: .automatic)
        #expect(await restarted.reconciled(same).state == .stale)

        let otherOrg = await Self.service(credential: orgB, endpoint: Self.failing, now: Date())
            .fetch(source: .automatic)
        #expect(await restarted.reconciled(otherOrg).state == .unavailable(.unreachable))
    }

    @Test("An older saved plan never overwrites a newer banked reading of the same scope")
    func olderAppCacheDoesNotOverwrite() async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "pulse-devin-backwards-\(UUID().uuidString).json")
        let cache = UsageCache(file: file)

        let newer = Self.appCacheReading(used: 0.5, observedAt: Date())
        _ = await cache.reconciled(newer)

        let older = Self.appCacheReading(used: 0.1, observedAt: Date().addingTimeInterval(-3_600))
        let shown = await cache.reconciled(older)
        // The older snapshot is not drawn, and not stored.
        #expect(shown.windows.first?.usedFraction == 0.5)

        // And the newer one is what a restart reads back.
        let restarted = UsageCache(file: file)
        #expect(await restarted.lastReading(for: AccountKey(.devin))?.windows.first?.usedFraction == 0.5)
    }

    private static func appCacheReading(used: Double, observedAt: Date) -> ProviderUsage {
        var reading = ProviderUsage(
            account: AccountKey(.devin),
            windows: [UsageWindow(
                id: "devin-daily", kind: .daily, scope: nil,
                usedFraction: used, windowSeconds: 86_400, resetsAt: nil
            )],
            observedAt: observedAt,
            state: .stale,
            plan: "Pro",
            creditBalance: nil
        )
        reading.origin = .appCache
        reading.sourceScope = UsageScope(route: .appCache, organization: nil, identity: "user-current")
        return reading
    }

    private static func launchName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private static func scratchSupport(now: Date) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pulse-devin-mixing-\(UUID().uuidString)")
        let database = root.appending(path: "User/globalStorage")
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)

        let source = try #require(Bundle.module.url(
            forResource: "devin-state", withExtension: "vscdb", subdirectory: "Fixtures"
        ))
        try FileManager.default.copyItem(at: source, to: database.appending(path: "state.vscdb"))

        let launch = Self.launchName(now.addingTimeInterval(-60))
        try FileManager.default.createDirectory(
            at: root.appending(path: "logs/\(launch)"), withIntermediateDirectories: true
        )
        return root
    }
}
