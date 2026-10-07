import Foundation
import Testing
@testable import Pulse

/// How `UsageStore` schedules its passes, driven through the `UsageServiceFactory`
/// seam with fake services: no network, no provider, a scratch cache file and a
/// clock the test moves. What each pass *says* about a provider is the
/// providers' tests; this is who is asked, when, and what is allowed to write.
@Suite("Usage store scheduling", .serialized)
@MainActor
struct UsageStoreSchedulingTests {
    // MARK: - Fakes

    /// Time the store reads, moved by the test. A lock rather than an actor
    /// because the store takes a plain closure.
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date()
        var now: Date { lock.withLock { current } }
        func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    }

    /// Who was actually asked, in order, counted per account.
    final class Asks: @unchecked Sendable {
        private let lock = NSLock()
        private var log: [AccountKey] = []
        var all: [AccountKey] { lock.withLock { log } }
        var accounts: Set<AccountKey> { Set(all) }
        /// Records one ask and returns how many times this account has now
        /// been asked.
        func record(_ account: AccountKey) -> Int {
            lock.withLock {
                log.append(account)
                return log.filter { $0 == account }.count
            }
        }
    }

    /// Holds a fetch until the test lets it go.
    actor Gate {
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiting.append($0) }
        }
        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting.removeAll()
        }
    }

    /// Answers from memory. `answer` gets the account and how many times it
    /// has been asked, and may wait on a `Gate` to hold a pass in flight.
    final class FakeServices: UsageServiceFactory {
        let asks = Asks()
        private let answer: @Sendable (AccountKey, Int) async -> ProviderUsage

        init(answer: @escaping @Sendable (AccountKey, Int) async -> ProviderUsage = { account, _ in
            UsageStoreSchedulingTests.reading(account, used: 0.2)
        }) {
            self.answer = answer
        }

        func storedKey(for provider: Provider) -> String? { nil }

        func fetch(for account: AccountKey, key: String?) -> UsageFetch {
            let asks = asks, answer = answer
            return {
                let count = asks.record(account)
                return await answer(account, count)
            }
        }
    }

    nonisolated static func reading(_ account: AccountKey, used: Double) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: [UsageWindow(
                id: "five-hour", kind: .fiveHour, scope: nil,
                usedFraction: used, windowSeconds: 18_000, resetsAt: nil
            )],
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    static let kiro = AccountKey(.kiro)
    static let cursor = AccountKey(.cursor)
    static let antigravity = AccountKey(.antigravity)

    /// A store over fake services, a scratch cache and a movable clock, with
    /// Kiro and Cursor on the rail and Antigravity off it.
    private func makeStore(
        _ services: FakeServices,
        clock: TestClock = TestClock(),
        extra: ExtraAccount? = nil
    ) -> UsageStore {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "pulse-scheduling-\(UUID().uuidString).json")
        var enabled: Set<String> = [Provider.kiro.rawValue, Provider.cursor.rawValue]
        if let extra { enabled.insert(extra.id) }
        let settings = AppSettings(
            enabledAccounts: enabled,
            extraAccounts: extra.map { [$0] } ?? [],
            readsTokenSpend: false
        )
        return UsageStore(
            settings: settings,
            services: services,
            cache: UsageCache(file: scratch),
            clock: { clock.now }
        )
    }

    /// Polls for something that happens on another task. Fails the test rather
    /// than hanging it.
    private func until(_ what: String = "", _ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(what)")
    }

    /// Lets anything still on its way happen, so "nothing more was asked" is
    /// a statement about something rather than about not having waited.
    private func settle() async { try? await Task.sleep(for: .milliseconds(150)) }

    // MARK: - Who is asked

    @Test("A pass asks the accounts on the rail and no others")
    func disabledProvidersAreNotFetched() async {
        let services = FakeServices()
        let store = makeStore(services)
        defer { store.stop() }

        store.refresh()
        await until("the pass") { !store.isRefreshing }

        #expect(services.asks.all.count == 2)
        #expect(services.asks.accounts == [Self.kiro, Self.cursor])
        #expect(Set(store.diagnostics.keys) == [Self.kiro.id, Self.cursor.id])
        // The one switched off keeps what it was seeded with.
        #expect(store.diagnostics[Self.antigravity.id] == nil)
        #expect(store.usage(for: Self.antigravity).state == .unavailable(.loading))
        #expect(store.usage(for: Self.kiro).state == .live)
    }

    @Test("Refreshing a switched-off account from its pane asks nothing")
    func disabledAccountIsNotFetchedOnItsOwn() async {
        let services = FakeServices()
        let store = makeStore(services)
        defer { store.stop() }

        store.refresh(Self.antigravity)
        #expect(!store.isRefreshing)
        await settle()

        #expect(services.asks.all.isEmpty)
        #expect(store.diagnostics.isEmpty)
    }

    @Test("A single-account refresh asks that account alone and starts no full pass")
    func singleRefreshIsNotAPass() async {
        let services = FakeServices()
        let store = makeStore(services)
        defer { store.stop() }

        store.refresh(Self.kiro)
        // The ring says so for the account clicked and for no other.
        #expect(store.isRefreshing(Self.kiro))
        #expect(!store.isRefreshing(Self.cursor))
        await until("the refresh") { !store.isRefreshing }
        await settle()

        #expect(services.asks.all == [Self.kiro])
        #expect(Set(store.diagnostics.keys) == [Self.kiro.id])
        #expect(store.usage(for: Self.cursor).state == .unavailable(.loading))
    }

    @Test("A pass asks added accounts only after the primary ones have answered")
    func addedAccountsFollowThePrimaries() async {
        let gate = Gate()
        let extra = ExtraAccount(provider: .claudeCode, slot: "second", label: "Second")
        let services = FakeServices { account, _ in
            if account.isPrimary { await gate.wait() }
            return Self.reading(account, used: 0.3)
        }
        let store = makeStore(services, extra: extra)
        defer { store.stop() }

        store.refresh()
        await until("the primaries") { services.asks.accounts == [Self.kiro, Self.cursor] }
        await settle()
        #expect(!services.asks.accounts.contains(extra.key))

        await gate.open()
        await until("the added account") { services.asks.accounts.contains(extra.key) }
        await until("the pass") { !store.isRefreshing }
        #expect(store.usage(for: extra.key).state == .live)
    }

    // MARK: - A pass in flight

    @Test("A pass asked for while one is in flight is not run alongside it, and runs once after")
    func passInFlightIsNotDoubled() async {
        let gate = Gate()
        let services = FakeServices { account, count in
            if count == 1 { await gate.wait() }
            return Self.reading(account, used: 0.2)
        }
        let store = makeStore(services)
        defer { store.stop() }

        store.refresh()
        await until("the first pass") { services.asks.all.count == 2 }
        // Three more asks while it is held: none of them starts a request.
        store.refresh()
        store.refresh()
        store.refresh(dueOnly: true)
        await settle()
        #expect(services.asks.all.count == 2)

        await gate.open()
        await until("the queued pass") { services.asks.all.count == 4 && !store.isRefreshing }
        await settle()
        // They collapse into one pass, not three.
        #expect(services.asks.all.count == 4)
    }

    @Test("An account refresh asked for mid-pass waits its turn")
    func accountRefreshWaitsForThePass() async {
        let gate = Gate()
        let services = FakeServices { account, count in
            if count == 1 { await gate.wait() }
            return Self.reading(account, used: 0.2)
        }
        let store = makeStore(services)
        defer { store.stop() }

        store.refresh()
        await until("the first pass") { services.asks.all.count == 2 }
        store.refresh(Self.kiro)
        await settle()
        #expect(services.asks.all.count == 2)

        await gate.open()
        await until("the queued refresh") { services.asks.all.count == 3 && !store.isRefreshing }
        await settle()
        #expect(services.asks.all.count == 3)
        #expect(services.asks.all.last == Self.kiro)
    }

    @Test("A whole pass queued behind one in flight covers the account refreshes queued with it")
    func queuedPassSupersedesQueuedAccounts() async {
        let gate = Gate()
        let services = FakeServices { account, count in
            if count == 1 { await gate.wait() }
            return Self.reading(account, used: 0.2)
        }
        let store = makeStore(services)
        defer { store.stop() }

        store.refresh()
        await until("the first pass") { services.asks.all.count == 2 }
        store.refresh(Self.kiro)
        store.refresh()

        await gate.open()
        await until("the queued pass") { services.asks.all.count == 4 && !store.isRefreshing }
        await settle()
        // Four: the two passes. Not five: the account refresh is not run again.
        #expect(services.asks.all.count == 4)
    }

    // MARK: - The watchdog

    @Test("Within the ceiling a pass is still in flight, and a new one waits")
    func insideTheCeiling() async {
        let clock = TestClock()
        let gate = Gate()
        let services = FakeServices { account, count in
            if count == 1 { await gate.wait() }
            return Self.reading(account, used: 0.2)
        }
        let store = makeStore(services, clock: clock)
        defer { store.stop() }

        store.refresh()
        await until("the first pass") { services.asks.all.count == 2 }
        clock.advance(UsageStore.passCeiling - 1)
        store.refresh()
        await settle()
        #expect(services.asks.all.count == 2)
        await gate.open()
        await until("the first pass to finish") { !store.isRefreshing }
    }

    @Test("A pass past the ceiling is given up on, the next runs, and the ghost's late answer is not written")
    func pastTheCeiling() async {
        let clock = TestClock()
        let gate = Gate()
        // The first request for each account hangs, and answers 90% when it is
        // finally let go. Every later one answers 10% at once.
        let services = FakeServices { account, count in
            if count == 1 {
                await gate.wait()
                return Self.reading(account, used: 0.9)
            }
            return Self.reading(account, used: 0.1)
        }
        let store = makeStore(services, clock: clock)
        defer { store.stop() }

        store.refresh()
        await until("the first pass") { services.asks.all.count == 2 }

        clock.advance(UsageStore.passCeiling + 1)
        store.refresh()
        await until("the second pass") { services.asks.all.count == 4 && !store.isRefreshing }
        #expect(store.usage(for: Self.kiro).windows.first?.usedFraction == 0.1)

        // The abandoned pass finally hears back. It must not undo the answer
        // that has been on screen since.
        await gate.open()
        await settle()
        #expect(store.usage(for: Self.kiro).windows.first?.usedFraction == 0.1)
        #expect(store.usage(for: Self.cursor).windows.first?.usedFraction == 0.1)
        #expect(!store.isRefreshing)
        #expect(services.asks.all.count == 4)
    }

    @Test("A single-account refresh past the ceiling gives up on a pass that never came back")
    func accountRefreshPastTheCeiling() async {
        let clock = TestClock()
        let gate = Gate()
        let services = FakeServices { account, count in
            if count == 1 {
                await gate.wait()
                return Self.reading(account, used: 0.9)
            }
            return Self.reading(account, used: 0.2)
        }
        let store = makeStore(services, clock: clock)
        defer { store.stop() }

        store.refresh()
        await until("the first pass") { services.asks.all.count == 2 }
        clock.advance(UsageStore.passCeiling + 1)
        store.refresh(Self.kiro)
        await until("the account refresh") { services.asks.all.count == 3 && !store.isRefreshing }
        #expect(store.usage(for: Self.kiro).windows.first?.usedFraction == 0.2)

        // The pass that was given up on answers late and writes nothing: not
        // over the refresh, and not into the account that refresh never asked.
        await gate.open()
        await settle()
        #expect(store.usage(for: Self.kiro).windows.first?.usedFraction == 0.2)
        #expect(store.usage(for: Self.cursor).state == .unavailable(.loading))
        #expect(!store.isRefreshing)
    }

    // MARK: - Pacing

    @Test("Only the timer honours each account's cadence; anything else asks everyone")
    func dueOnlyIsTheTimers() async {
        let clock = TestClock()
        let services = FakeServices()
        let store = makeStore(services, clock: clock)
        defer { store.stop() }

        store.refresh()
        await until("the first pass") { !store.isRefreshing }
        #expect(services.asks.all.count == 2)

        // The timer, a moment later: nobody is due.
        store.refresh(dueOnly: true)
        await until("the timer's pass") { !store.isRefreshing }
        #expect(services.asks.all.count == 2)

        // Something happened — a setting, a wake: look now, whatever the cadence says.
        store.refresh()
        await until("the second pass") { !store.isRefreshing }
        #expect(services.asks.all.count == 4)

        // The timer again, once the slowest cadence has come round.
        clock.advance(AdaptiveRefresh.ceiling + 60)
        store.refresh(dueOnly: true)
        await until("the late timer pass") { !store.isRefreshing }
        #expect(services.asks.all.count == 6)
    }

    @Test("The loop is a one-shot timer between two and thirty minutes")
    func adaptiveTimerIsAOneShot() async throws {
        #expect(AdaptiveRefresh.floor == 120)
        #expect(AdaptiveRefresh.ceiling == 1_800)

        let services = FakeServices()
        let store = makeStore(services)
        defer { store.stop() }
        #expect(store.timer == nil)

        store.refresh()
        await until("the pass") { !store.isRefreshing }

        let timer = try #require(store.timer)
        #expect(timer.isValid)
        // Zero is what a timer that does not repeat reports.
        #expect(timer.timeInterval == 0)
        let wait = timer.fireDate.timeIntervalSinceNow
        #expect(wait > AdaptiveRefresh.floor - 5)
        #expect(wait <= AdaptiveRefresh.ceiling)
        #expect((AdaptiveRefresh.floor...AdaptiveRefresh.ceiling).contains(store.currentInterval))

        // Rescheduled after every pass: a new timer, and the old one is gone.
        store.refresh()
        await until("the second pass") { !store.isRefreshing }
        #expect(store.timer !== timer)
        #expect(!timer.isValid)
    }
}
