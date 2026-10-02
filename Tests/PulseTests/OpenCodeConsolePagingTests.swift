import Foundation
import Testing
@testable import Pulse

/// An original synthetic server: inclusive time bounds, opaque cursors and
/// descending timestamps, with the same 100-row page size as the console.
actor ConsoleTestServer {
    struct Request: Sendable {
        let range: OpenCodeConsolePager.Range
        let cursor: String?
    }
    let rows: [OpenCodeConsole.Item]
    private(set) var requests: [Request] = []
    private(set) var peak = 0
    private var active = 0
    private var failUntil: Date?
    private let gate: ConsoleTestGate?
    private let holdAfter: Int
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(rows: [OpenCodeConsole.Item], gate: ConsoleTestGate? = nil, holdAfter: Int = .max) {
        self.rows = rows.sorted { $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt > $1.startedAt }
        self.gate = gate
        self.holdAfter = holdAfter
    }

    func fail(until date: Date?) { failUntil = date }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func fetch(_ range: OpenCodeConsolePager.Range, _ cursor: String?) async -> OpenCodeConsole.PageResult {
        requests.append(Request(range: range, cursor: cursor))
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        let ready = waiters.filter { $0.0 <= requests.count }
        waiters.removeAll { $0.0 <= requests.count }
        for waiter in ready { waiter.1.resume() }
        if requests.count > holdAfter, let gate { await gate.wait() }
        // Yield so independent requests can overlap; tests assert the bound,
        // never a machine-dependent elapsed time.
        try? await Task.sleep(for: .milliseconds(1))
        if let failUntil, range.until <= failUntil { return .failed }
        // Exercise the production URL's millisecond boundary conversion too,
        // rather than matching Swift Dates on both sides and hiding round-off.
        let since = Double(OpenCodeConsole.milliseconds(range.since))
        let until = Double(OpenCodeConsole.milliseconds(range.until))
        let matched = rows.filter { $0.startedAt >= since && $0.startedAt <= until }
        let offset = cursor.flatMap(Int.init) ?? 0
        let page = Array(matched.dropFirst(offset).prefix(OpenCodeConsole.pageSize))
        let next = offset + page.count
        return .page(.init(items: page, nextCursor: next < matched.count ? String(next) : nil))
    }
}

actor ConsoleTestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

enum ConsoleTestData {
    static let now = Date(timeIntervalSince1970: 1_790_856_000)
    static let range = OpenCodeConsolePager.Range(since: now.addingTimeInterval(-OpenCodeConsole.span), until: now)
    static func rows(_ count: Int, spacing: TimeInterval = 60, newest: Date = now) -> [OpenCodeConsole.Item] {
        (0..<count).map { index in
            .init(id: "request-\(index)", startedAt: newest.addingTimeInterval(-Double(index) * spacing).timeIntervalSince1970 * 1000,
                  product: "go", model: "test", inputTokens: 100, outputTokens: 20,
                  cacheReadTokens: 900, cacheWriteTokens: 0, cost: 0.002)
        }
    }
    static func ledger(_ result: OpenCodeConsole.Read) throws -> UsageLedger {
        let ledger: UsageLedger? = if case .answered(let value) = result { value } else { nil }
        return try #require(ledger)
    }
}

@Suite("Adaptive console pagination")
struct OpenCodeConsolePagingTests {
    private actor Received {
        var items: [String: OpenCodeConsole.Item] = [:]
        var pages = 0
        func append(_ page: [OpenCodeConsole.Item]) {
            pages += 1
            for item in page { items[item.id] = item }
        }
    }

    @Test("Quiet histories cost one request instead of 31 daily requests", arguments: [0, 3, 99])
    func sparse(count: Int) async {
        let server = ConsoleTestServer(rows: ConsoleTestData.rows(count))
        let received = Received()
        let result = await OpenCodeConsolePager.read(ranges: [ConsoleTestData.range], retryDelay: .zero,
            fetch: { await server.fetch($0, $1) }, receive: { await received.append($0) })
        #expect(result.complete)
        #expect(await server.requests.count == 1)
        #expect(await received.items.count == count)
    }

    @Test("A busy day shares workers, with exact totals across inclusive boundaries")
    func busyDay() async {
        let rows = ConsoleTestData.rows(2_400, spacing: 5, newest: ConsoleTestData.now.addingTimeInterval(-10 * 86_400))
        let server = ConsoleTestServer(rows: rows)
        let received = Received()
        let result = await OpenCodeConsolePager.read(ranges: [ConsoleTestData.range], retryDelay: .zero,
            fetch: { await server.fetch($0, $1) }, receive: { await received.append($0) })
        #expect(result.complete)
        #expect(await received.items == Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }))
        #expect(await server.peak > 1)
        #expect(await server.peak <= OpenCodeConsole.concurrentPages)
        // The former daily walk needs 31 initial pages plus 23 continuations.
        #expect(await server.requests.count < 54)
        let ledger = await OpenCodeConsole.ledger(from: Array(received.items.values), now: ConsoleTestData.now)
        #expect(ledger.allTime.tokens == rows.count * 1_020)
        #expect(abs(ledger.allTime.cost - Double(rows.count) * 0.002) < 1e-9)
    }

    @Test("More than a page at the same timestamp follows cursors without dropping requests")
    func coincidentTimes() async {
        let server = ConsoleTestServer(rows: ConsoleTestData.rows(350, spacing: 0))
        let received = Received()
        let result = await OpenCodeConsolePager.read(ranges: [ConsoleTestData.range], retryDelay: .zero,
            fetch: { await server.fetch($0, $1) }, receive: { await received.append($0) })
        #expect(result.complete)
        #expect(await received.items.count == 350)
        #expect(await server.requests.count == 4)
        #expect(await server.requests.compactMap(\.cursor) == ["100", "200", "300"])
    }

    @Test("A global page budget leaves resumable intervals, never a falsely complete scan")
    func budget() async {
        let rows = ConsoleTestData.rows(1_000)
        let server = ConsoleTestServer(rows: rows)
        let received = Received()
        let first = await OpenCodeConsolePager.read(ranges: [ConsoleTestData.range], pageLimit: 3, retryDelay: .zero,
            fetch: { await server.fetch($0, $1) }, receive: { await received.append($0) })
        #expect(!first.complete)
        #expect(await server.requests.count == 3)
        let second = await OpenCodeConsolePager.read(ranges: first.pending, retryDelay: .zero,
            fetch: { await server.fetch($0, $1) }, receive: { await received.append($0) })
        #expect(second.complete)
        #expect(await received.items.count == rows.count)
    }

    @Test("Splitting through a shared millisecond cannot round its remaining requests out of the query")
    func millisecondBoundary() async {
        // At this magnitude Date -> milliseconds rounds just below the integer
        // on truncation. The first page ends inside 150 requests at that time.
        let boundary = Date(timeIntervalSince1970: 2_147_483_648.002)
        let older = (0..<150).map { index -> OpenCodeConsole.Item in
            .init(id: "edge-\(index)", startedAt: 2_147_483_648_002,
                  product: "go", model: "test", inputTokens: 100, outputTokens: 20,
                  cacheReadTokens: 900, cacheWriteTokens: 0, cost: 0.002)
        }
        let rows = ConsoleTestData.rows(99, spacing: 0.1, newest: boundary.addingTimeInterval(100)) + older
        let server = ConsoleTestServer(rows: rows)
        let received = Received()
        let range = OpenCodeConsolePager.Range(since: boundary.addingTimeInterval(-86_400), until: boundary.addingTimeInterval(200))
        let result = await OpenCodeConsolePager.read(ranges: [range], retryDelay: .zero,
            fetch: { await server.fetch($0, $1) }, receive: { await received.append($0) })
        #expect(result.complete)
        #expect(await received.items.count == rows.count)
    }

    @Test("Cancellation stops retrying a failed request")
    func cancellation() async {
        let calls = Received()
        let task = Task {
            await OpenCodeConsole.retryPage(retryDelay: .zero) {
                await calls.append(ConsoleTestData.rows(1))
                withUnsafeCurrentTask { $0?.cancel() }
                return .failed
            }
        }
        _ = await task.value
        #expect(await calls.pages == 1)
    }

    @Test("Authentication rejection after an answered page is still a rejection")
    func rejection() async {
        let result = await OpenCodeConsole.collect(retryDelay: .zero) { cursor in
            cursor == nil ? .page(.init(items: ConsoleTestData.rows(1), nextCursor: "next")) : .signedOut
        }
        if case .signedOut = result.outcome {} else { Issue.record("Lost authentication failure") }
        #expect(!result.complete)
    }

    @Test("Adaptive cursor fallback preserves authentication failure and rejects cursor loops")
    func fallbackFailures() async {
        let received = Received()
        let rejected = await OpenCodeConsolePager.read(ranges: [ConsoleTestData.range], retryDelay: .zero,
            fetch: { _, cursor in
                cursor == nil ? .page(.init(items: ConsoleTestData.rows(1), nextCursor: "next")) : .signedOut
            }, receive: { await received.append($0) })
        if case .signedOut = rejected.outcome {} else { Issue.record("Lost authentication failure") }
        #expect(!rejected.complete)
        #expect(await received.pages == 1)

        let looping = Received()
        let loop = await OpenCodeConsolePager.read(ranges: [ConsoleTestData.range], retryDelay: .zero,
            fetch: { _, _ in .page(.init(items: ConsoleTestData.rows(1), nextCursor: "same")) },
            receive: { await looping.append($0) })
        #expect(!loop.complete)
        #expect(loop.pending == [ConsoleTestData.range])
        #expect(await looping.pages == 2)
    }
}
