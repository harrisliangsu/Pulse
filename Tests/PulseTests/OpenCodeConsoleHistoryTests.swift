import Foundation
import Testing
@testable import Pulse

@Suite("Console history reuse and progress")
struct OpenCodeConsoleHistoryTests {
    private func temporary() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseConsoleHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func history(_ server: ConsoleTestServer, file: URL? = nil) -> OpenCodeConsoleHistory {
        OpenCodeConsoleHistory(file: file, retryDelay: .zero,
            resolve: { .workspace(.init(id: $0, name: nil)) },
            fetch: { _, _, range, cursor in await server.fetch(range, cursor) })
    }

    @Test("Complete caches, including empty accounts, skip repeated reads and survive restart", arguments: [0, 5])
    func freshCache(count: Int) async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "history.json")
        let server = ConsoleTestServer(rows: ConsoleTestData.rows(count))
        let reader = history(server, file: file)
        let now = ConsoleTestData.now
        _ = await reader.ledger(cookie: "org", now: now)
        #expect(await server.requests.count == 1)
        let second = try ConsoleTestData.ledger(await reader.ledger(cookie: "org", now: now.addingTimeInterval(10)))
        #expect(second.allTime.tokens == count * 1_020)
        #expect(!second.hasPartialCounts)
        #expect(await server.requests.count == 1)
        _ = await history(server, file: file).ledger(cookie: "org", now: now.addingTimeInterval(20))
        #expect(await server.requests.count == 1)
        _ = await reader.ledger(cookie: "org", now: now.addingTimeInterval(120))
        let requests = await server.requests
        #expect(requests.count == 2)
        #expect(requests.last?.range.since == now.addingTimeInterval(-OpenCodeConsoleHistory.tailOverlap))
    }

    @Test("A saved partial scan retries its holes; overlap with known ids cannot hide missing history")
    func resumeHoles() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "history.json")
        let now = ConsoleTestData.now
        let rows = ConsoleTestData.rows(250, spacing: 3600)
        let server = ConsoleTestServer(rows: rows)
        let boundary = now.addingTimeInterval(-198 * 3600)
        await server.fail(until: boundary)
        let first = try ConsoleTestData.ledger(await history(server, file: file).ledger(cookie: "org", now: now))
        #expect(first.hasPartialCounts)
        #expect(first.allTime.tokens > 0)
        #expect(first.allTime.tokens < rows.count * 1_020)
        let before = await server.requests.count
        let reader = history(server, file: file)
        let second = try ConsoleTestData.ledger(await reader.ledger(cookie: "org", now: now.addingTimeInterval(120)))
        #expect(second.hasPartialCounts)
        let retries = await server.requests.dropFirst(before)
        #expect(retries.allSatisfy { $0.range.until <= boundary || $0.range.since >= now.addingTimeInterval(-OpenCodeConsoleHistory.tailOverlap) })
        await server.fail(until: nil)
        let final = try ConsoleTestData.ledger(await reader.ledger(cookie: "org", now: now.addingTimeInterval(240)))
        #expect(!final.hasPartialCounts)
        #expect(final.allTime.tokens == rows.count * 1_020)
    }

    @MainActor private final class Progress {
        var values: [UsageLedger] = []
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func append(_ ledger: UsageLedger) {
            values.append(ledger)
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
        func first() async {
            if !values.isEmpty { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    @Test("The original complete disk-cache shape upgrades with only an incremental request")
    func legacyCache() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "history.json")
        struct Legacy: Encodable {
            let org = "org"
            let complete = true
            let items: [OpenCodeConsole.Item]
        }
        let rows = ConsoleTestData.rows(5, newest: ConsoleTestData.now.addingTimeInterval(-600))
        try JSONEncoder().encode(Legacy(items: rows)).write(to: file)
        let server = ConsoleTestServer(rows: rows)
        let result = try ConsoleTestData.ledger(await history(server, file: file).ledger(cookie: "org", now: ConsoleTestData.now))
        #expect(!result.hasPartialCounts)
        #expect(result.allTime.tokens == rows.count * 1_020)
        #expect(await server.requests.count == 1)
        #expect(await server.requests.first?.range.since == rows[0].date.addingTimeInterval(-OpenCodeConsoleHistory.tailOverlap))
    }

    @Test("A cache from a different workspace never appears in progress or totals")
    @MainActor func differentWorkspaceCache() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "history.json")
        _ = await history(ConsoleTestServer(rows: ConsoleTestData.rows(5)), file: file)
            .ledger(cookie: "first", now: ConsoleTestData.now)
        let progress = Progress()
        let server = ConsoleTestServer(rows: [])
        let read = await history(server, file: file).ledger(cookie: "other", now: ConsoleTestData.now) { progress.append($0) }
        #expect(try ConsoleTestData.ledger(read).allTime.tokens == 0)
        #expect(progress.values.isEmpty)
        #expect(await server.requests.first?.range == ConsoleTestData.range)
    }

    @Test("Settings joining a warm-up gets its current partial snapshot before the remaining pages")
    @MainActor func joinsWarmup() async throws {
        let gate = ConsoleTestGate()
        let server = ConsoleTestServer(rows: ConsoleTestData.rows(300), gate: gate, holdAfter: 1)
        let reader = history(server)
        let warmup = Task { await reader.ledger(cookie: "org", now: ConsoleTestData.now) }
        await server.waitForRequests(2)
        let progress = Progress()
        let pane = Task {
            await reader.ledger(cookie: "org", now: ConsoleTestData.now) { progress.append($0) }
        }
        await progress.first()
        #expect(progress.values.first?.hasPartialCounts == true)
        #expect(progress.values.first?.allTime.tokens == 100 * 1_020)
        await gate.open()
        let a = try ConsoleTestData.ledger(await warmup.value)
        let b = try ConsoleTestData.ledger(await pane.value)
        #expect(a == b)
        #expect(!b.hasPartialCounts)
        #expect(b.allTime.tokens == 300 * 1_020)
    }

    @Test("Saved figures arrive before a slow incremental request finishes")
    @MainActor func savedProgress() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "history.json")
        let rows = ConsoleTestData.rows(5)
        _ = await history(ConsoleTestServer(rows: rows), file: file).ledger(cookie: "org", now: ConsoleTestData.now)
        let gate = ConsoleTestGate()
        let server = ConsoleTestServer(rows: rows, gate: gate, holdAfter: 0)
        let reader = history(server, file: file)
        let progress = Progress()
        let read = Task {
            await reader.ledger(cookie: "org", now: ConsoleTestData.now.addingTimeInterval(120)) { progress.append($0) }
        }
        await progress.first()
        #expect(progress.values.first?.allTime.tokens == 5 * 1_020)
        await gate.open()
        _ = await read.value
    }

    @Test("A different session cannot join another workspace's in-flight result")
    func separateSessions() async throws {
        let gate = ConsoleTestGate()
        let server = ConsoleTestServer(rows: ConsoleTestData.rows(1), gate: gate, holdAfter: 0)
        let reader = OpenCodeConsoleHistory(retryDelay: .zero,
            resolve: { .workspace(.init(id: $0, name: nil)) },
            fetch: { _, org, range, cursor in
                if org == "other" { return .page(.init(items: [], nextCursor: nil)) }
                return await server.fetch(range, cursor)
            })
        let first = Task { await reader.ledger(cookie: "first", now: ConsoleTestData.now) }
        await server.waitForRequests(1)
        let other = Task { await reader.ledger(cookie: "other", now: ConsoleTestData.now) }
        await gate.open()
        #expect(try ConsoleTestData.ledger(await first.value).allTime.tokens == 1_020)
        #expect(try ConsoleTestData.ledger(await other.value).allTime.tokens == 0)
    }
}
