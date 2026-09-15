import Foundation
import Testing
@testable import Pulse

/// The saved plan is a **launch-time snapshot**, not a fetch: the row is
/// written when Devin's own app starts and not again while it runs. These pin
/// what happens to it as it ages — it becomes "as of", its reset windows are
/// dropped rather than drawn stale, an undated row is refused rather than
/// dated to now, and past the cache's day it is gone.
@Suite("Devin saved-plan age")
struct DevinSnapshotTests {
    /// Before both fixture resets (daily 1_789_372_800, weekly 1_789_891_200),
    /// so a test that is not about expiry keeps every window.
    private static let beforeResets = Date(timeIntervalSince1970: 1_789_000_000)
    private static let dailyReset = Date(timeIntervalSince1970: 1_789_372_800)

    private static let paidPlan = #"""
    {"planName":"Pro","dailyRemainingPercent":98,"weeklyRemainingPercent":99,
     "dailyResetAtUnix":1789372800,"weeklyResetAtUnix":1789891200,
     "overageBalanceMicros":10000000}
    """#

    private static func plan(_ json: String, accountID: String? = "user-current") throws -> DevinUsageService.Plan {
        try #require(DevinUsageService.Plan(json: Data(json.utf8), accountID: accountID))
    }

    private static func reading(
        _ json: String,
        launchedAt: Date?,
        now: Date,
        accountID: String? = "user-current"
    ) throws -> ProviderUsage {
        DevinUsageService.reading(
            for: try Self.plan(json, accountID: accountID), launchedAt: launchedAt, now: now
        )
    }

    @Test("A snapshot from just now is a live reading scoped to the app's own route")
    func freshSnapshotIsLive() throws {
        let reading = try Self.reading(
            Self.paidPlan, launchedAt: Self.beforeResets.addingTimeInterval(-60), now: Self.beforeResets
        )

        #expect(reading.state == .live)
        #expect(reading.windows.map(\.id) == ["devin-daily", "devin-weekly"])
        // The scope names the app-cache route and the row's user id — and **no
        // organization**, because the row carries none to name. That is what
        // keeps it from ever matching an organization-scoped endpoint reading.
        #expect(reading.sourceScope == UsageScope(
            route: .appCache, organization: nil, identity: "user-current"
        ))
        #expect(reading.requiresScopeMatch)
    }

    @Test("A snapshot older than the fresh window says \"as of\", not \"now\"")
    func olderSnapshotIsStale() throws {
        let launched = Self.beforeResets.addingTimeInterval(-3 * 3_600)
        let reading = try Self.reading(Self.paidPlan, launchedAt: launched, now: Self.beforeResets)

        #expect(reading.state == .stale)
        #expect(reading.observedAt == launched)
    }

    @Test("A window that has reset since the snapshot is dropped, not aged")
    func resetWindowIsDropped() throws {
        // An hour after the daily reset, with a weekly reset still ahead.
        let now = Self.dailyReset.addingTimeInterval(3_600)
        let reading = try Self.reading(Self.paidPlan, launchedAt: now.addingTimeInterval(-3_600), now: now)

        #expect(reading.windows.map(\.id) == ["devin-weekly"])
        #expect(reading.state == .stale)
    }

    @Test("A missing, future, or day-old stamp is not a reading at all")
    func unreliableStampsAreRefused() throws {
        // No stamp: the row is undated, and dating it with the fetch's clock
        // would invent a fresh reading out of nothing.
        #expect(try Self.reading(Self.paidPlan, launchedAt: nil, now: Self.beforeResets)
            .state == .unavailable(.devinPlanUnread))
        // A stamp after `now` is not a launch that happened.
        #expect(try Self.reading(
            Self.paidPlan, launchedAt: Self.beforeResets.addingTimeInterval(60), now: Self.beforeResets
        ).state == .unavailable(.devinPlanUnread))
        // Past the cache's day.
        #expect(try Self.reading(
            Self.paidPlan,
            launchedAt: Self.beforeResets.addingTimeInterval(-(UsageCache.maximumAge + 3_600)),
            now: Self.beforeResets
        ).state == .unavailable(.devinPlanUnread))
    }

    @Test("A balance-only plan keeps its money, has no window, and still ages")
    func balanceOnlyPlanAges() throws {
        let balanceOnly = #"{"planName":"Pro","overageBalanceMicros":10000000}"#
        let now = Self.beforeResets

        let fresh = try Self.reading(balanceOnly, launchedAt: now.addingTimeInterval(-60), now: now)
        #expect(fresh.windows.isEmpty)
        #expect(fresh.creditBalance != nil)
        #expect(fresh.state == .live)

        #expect(try Self.reading(balanceOnly, launchedAt: now.addingTimeInterval(-3_600), now: now)
            .state == .stale)

        // With no reliable stamp, or past the day, the money does not save it.
        #expect(try Self.reading(balanceOnly, launchedAt: nil, now: now)
            .state == .unavailable(.devinPlanUnread))
        #expect(try Self.reading(
            balanceOnly,
            launchedAt: now.addingTimeInterval(-(UsageCache.maximumAge + 3_600)),
            now: now
        ).state == .unavailable(.devinPlanUnread))
    }

    @Test("A plan whose only window has reset and with no balance reports nothing")
    func everythingResetIsNoLimits() throws {
        let now = Self.dailyReset.addingTimeInterval(7_200)
        let reading = try Self.reading(
            #"{"planName":"Free","dailyRemainingPercent":50,"dailyResetAtUnix":1789372800}"#,
            launchedAt: now.addingTimeInterval(-3_600),
            now: now
        )

        #expect(reading.state == .unavailable(.noLimitsReported))
    }

    // MARK: - The file path

    @Test("The store's launch stamp ages the reading the tooling route reads")
    func toolingRouteReadsTheLaunchStamp() throws {
        let launch = Self.beforeResets.addingTimeInterval(-3 * 3_600)
        let support = try Self.scratchSupport(launch: Self.launchName(launch))
        defer { try? FileManager.default.removeItem(at: support) }

        let reading = DevinUsageService.appCache(store: support, now: Self.beforeResets)

        // Three hours after launch, the newest row's plan is a snapshot, not a
        // live reading — which is what puts "as of" on the card.
        #expect(reading.state == .stale)
        #expect(reading.plan == "Pro")
        #expect(reading.sourceScope?.identity == "user-current")
    }

    @Test("A store with no readable plan is unread, not empty")
    func scratchStoreMissingPlan() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pulse-devin-empty-\(UUID().uuidString)")
        let database = root.appending(path: "User/globalStorage")
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a database".utf8).write(to: database.appending(path: "state.vscdb"))

        #expect(DevinUsageService.appCache(store: root, now: Date())
            .state == .unavailable(.devinPlanUnread))
    }

    @Test("A store with no launch log is undated, and undated is refused")
    func storeWithoutALaunchIsRefused() throws {
        // The database is there and holds a plan, but `logs/` is not — there is
        // no stamp, and the database's own date is deliberately not used.
        let support = try Self.scratchSupport(launch: nil)
        defer { try? FileManager.default.removeItem(at: support) }

        #expect(DevinUsageService.appCache(store: support, now: Self.beforeResets)
            .state == .unavailable(.devinPlanUnread))
    }

    // MARK: - The cache ages a direct snapshot too

    @Test("An unrelated log entry cannot manufacture a launch from its modification date")
    func unrecognizedLogEntriesAreNotLaunches() throws {
        let support = try Self.scratchSupport(launch: "window1")
        defer { try? FileManager.default.removeItem(at: support) }
        let now = Date().addingTimeInterval(1)
        #expect(DevinUsageService.appCache(store: support, now: now)
            .state == .unavailable(.devinPlanUnread))

        // Even a timestamp-shaped regular file is not the per-launch directory.
        let file = support.appending(path: "logs/\(Self.launchName(now.addingTimeInterval(-60)))")
        try Data().write(to: file)
        #expect(DevinUsageService.appCache(store: support, now: now)
            .state == .unavailable(.devinPlanUnread))
        #expect(DevinUsageService.launchStamp("20260914T092003.log") == nil)
    }

    @Test("A day-old snapshot is refused on the fetch path, not only on read-back")
    func cacheAgesADirectSnapshot() async {
        let cache = Self.cache()
        let now = Date()
        var old = ProviderUsage(
            account: AccountKey(.devin),
            windows: [UsageWindow(
                id: "devin-daily", kind: .daily, scope: nil,
                usedFraction: 0.5, windowSeconds: 86_400,
                resetsAt: now.addingTimeInterval(-3_600)
            )],
            observedAt: now.addingTimeInterval(-(UsageCache.maximumAge + 3_600)),
            state: .live,
            plan: "Pro",
            creditBalance: nil
        )
        old.origin = .appCache
        old.sourceScope = UsageScope(route: .appCache, organization: nil, identity: "user-current")

        let shown = await cache.reconciled(old)

        // The live branch used to hand this straight back. It is not drawn a
        // day later as a current ring...
        #expect(shown.state == .unavailable(.noLimitsReported))
        // ...and it is not banked for a later fallback either.
        #expect(await cache.lastReading(for: AccountKey(.devin)) == nil)
    }

    @Test("A reset window is dropped from a fetched snapshot, not aged")
    func cacheDropsTheResetWindowOnAFetch() async {
        let cache = Self.cache()
        let now = Date()
        var snapshot = ProviderUsage(
            account: AccountKey(.devin),
            windows: [
                UsageWindow(id: "devin-daily", kind: .daily, scope: nil, usedFraction: 0.5,
                            windowSeconds: 86_400, resetsAt: now.addingTimeInterval(-3_600)),
                UsageWindow(id: "devin-weekly", kind: .weekly, scope: nil, usedFraction: 0.2,
                            windowSeconds: 604_800, resetsAt: now.addingTimeInterval(3 * 86_400)),
            ],
            observedAt: now.addingTimeInterval(-3_600),
            state: .live,
            plan: "Pro",
            creditBalance: nil
        )
        snapshot.origin = .appCache
        snapshot.sourceScope = UsageScope(route: .appCache, organization: nil, identity: "user-current")

        let shown = await cache.reconciled(snapshot)

        #expect(shown.windows.map(\.id) == ["devin-weekly"])
    }

    // MARK: - Notifications

    @Test("An old saved plan is not an outage, but an endpoint failure still is")
    func appCacheStalenessIsNotAFailure() {
        let account = AccountKey(.devin)
        var savedPlan = ProviderUsage.unavailable(.devin, reason: .noLimitsReported)
        savedPlan.origin = .appCache

        // The app simply has not been relaunched; every check got through.
        #expect(!UsageAlerts.staleMeansFailure(route: .tooling, raw: savedPlan, for: account))
        #expect(!UsageAlerts.staleMeansFailure(route: .automatic, raw: savedPlan, for: account))

        // An endpoint that failed is still a failure, whichever route is set.
        var endpointFailure = ProviderUsage.unavailable(.devin, reason: .unreachable)
        endpointFailure.origin = .endpoint
        #expect(UsageAlerts.staleMeansFailure(route: .automatic, raw: endpointFailure, for: account))
    }

    private static func cache() -> UsageCache {
        UsageCache(
            file: FileManager.default.temporaryDirectory
                .appending(path: "pulse-devin-age-\(UUID().uuidString).json")
        )
    }

    private static func launchName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    /// A support directory with the fixture store in place and, when a launch
    /// is given, a `logs/` entry whose **name** is the launch time, exactly as
    /// the app leaves it. No launch means an undated store.
    private static func scratchSupport(launch: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pulse-devin-\(UUID().uuidString)")
        let database = root.appending(path: "User/globalStorage")
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)

        let source = try #require(Bundle.module.url(
            forResource: "devin-state", withExtension: "vscdb", subdirectory: "Fixtures"
        ))
        try FileManager.default.copyItem(at: source, to: database.appending(path: "state.vscdb"))

        if let launch {
            try FileManager.default.createDirectory(
                at: root.appending(path: "logs/\(launch)"), withIntermediateDirectories: true
            )
        }
        return root
    }
}
