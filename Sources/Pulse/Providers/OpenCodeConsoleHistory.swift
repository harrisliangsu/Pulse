// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One workspace's compact request log, shared by warm-up, Settings and the
/// card. Publish saved/arriving rows while the bounded pager fills the gaps.
/// A failed interval stays pending on disk; meeting one known id cannot prove
/// the other intervals were read. Only complete reads get the short freshness
/// window, including a genuinely empty account.
actor OpenCodeConsoleHistory {
    static let shared = OpenCodeConsoleHistory(file: PulseStorage.directory.appending(path: "opencode-console-log.json"))
    static let freshness: TimeInterval = 60
    /// How far behind the last read the next one starts (`rangesToRead`).
    static let tailOverlap: TimeInterval = 15 * 60

    typealias Progress = @MainActor @Sendable (UsageLedger) -> Void
    typealias Resolve = @Sendable (String) async -> OpenCodeConsole.Resolved
    typealias Fetch = @Sendable (String, String, OpenCodeConsolePager.Range, String?) async -> OpenCodeConsole.PageResult

    private var items: [String: OpenCodeConsole.Item] = [:]
    private var complete = false
    private var pending: [OpenCodeConsolePager.Range] = []
    private var checkedThrough: Date?
    private var org: String?
    private var visibleCookie: String?
    private var running: Running?
    private var observers: [UUID: Observer] = [:]
    private let file: URL?
    private let resolve: Resolve
    private let fetch: Fetch
    private let retryDelay: Duration

    /// Injected routes keep cache, progress and coalescing tests off real accounts.
    init(
        file: URL? = nil,
        retryDelay: Duration = .seconds(1),
        resolve: @escaping Resolve = { await OpenCodeConsoleWorkspace.shared.resolve(cookie: $0) },
        fetch: @escaping Fetch = { cookie, org, range, cursor in
            await OpenCodeConsole.fetchPage(cookie: cookie, org: org, since: range.since, until: range.until, cursor: cursor)
        }
    ) {
        self.file = file
        self.retryDelay = retryDelay
        self.resolve = resolve
        self.fetch = fetch
    }

    private struct Running {
        let id: UUID
        let cookie: String
        let task: Task<OpenCodeConsole.Read, Never>
    }

    private struct Observer {
        let cookie: String
        let receive: Progress
    }

    private struct Saved: Codable {
        let org: String
        let items: [OpenCodeConsole.Item]
        let complete: Bool
        // Optional only to preserve the original complete-cache format. An
        // old incomplete cache has no proven ranges and must walk the span.
        var pending: [OpenCodeConsolePager.Range]?
        var checkedThrough: Date?
    }

    func ledger(cookie: String, now: Date = Date(), progress: Progress? = nil) async -> OpenCodeConsole.Read {
        let observer = UUID()
        if let progress { observers[observer] = Observer(cookie: cookie, receive: progress) }
        defer { observers[observer] = nil }

        while let existing = running {
            if existing.cookie == cookie, visibleCookie == cookie, let progress, !items.isEmpty || complete {
                await progress(snapshot(now: now))
            }
            let result = await existing.task.value
            // A waiter may resume before the caller that started the task.
            // Whichever clears it first must not clear a replacement read.
            if running?.id == existing.id { running = nil }
            if existing.cookie == cookie { return result }
        }
        let id = UUID()
        let task = Task { await self.read(cookie: cookie, now: now) }
        running = Running(id: id, cookie: cookie, task: task)
        let result = await task.value
        if running?.id == id { running = nil }
        return result
    }

    private func read(cookie: String, now: Date) async -> OpenCodeConsole.Read {
        visibleCookie = nil
        let workspace: String
        switch await resolve(cookie) {
        case .workspace(let value): workspace = value.id
        case .signedOut: return .signedOut
        case .failed: return .failed
        }
        if workspace != org { restore(workspace: workspace) }
        visibleCookie = cookie
        if !items.isEmpty || complete { await publish(cookie: cookie, now: now) }

        if complete, let checkedThrough, now >= checkedThrough,
           now.timeIntervalSince(checkedThrough) < Self.freshness {
            return .answered(snapshot(now: now))
        }

        let ranges = rangesToRead(now: now)
        let wasComplete = complete
        complete = false
        let fetch = self.fetch
        let result = await OpenCodeConsolePager.read(ranges: ranges, retryDelay: retryDelay, fetch: { range, cursor in
            await fetch(cookie, workspace, range, cursor)
        }, receive: { page in
            await self.receive(page, cookie: cookie, now: now)
        })
        // Nothing was settled: what was whole stays whole, so the next read
        // takes the tail rather than walking the month again.
        guard !Task.isCancelled else { complete = wasComplete; return .failed }
        if case .signedOut = result.outcome { complete = wasComplete; return .signedOut }

        pending = result.pending
        complete = result.complete
        checkedThrough = now
        let horizon = now.addingTimeInterval(-OpenCodeConsole.span - 86_400)
        items = items.filter { $0.value.date >= horizon }
        save()
        if case .failed = result.outcome, items.isEmpty { return .failed }
        return .answered(snapshot(now: now))
    }

    private func rangesToRead(now: Date) -> [OpenCodeConsolePager.Range] {
        let horizon = now.addingTimeInterval(-OpenCodeConsole.span)
        if !complete, pending.isEmpty { return [.init(since: horizon, until: now)] }
        var ranges = pending.compactMap { range -> OpenCodeConsolePager.Range? in
            let start = max(horizon, range.since)
            let end = min(now, range.until)
            return start <= end ? .init(since: start, until: end) : nil
        }
        // Use the last attempted upper bound even on an empty account. The
        // pending intervals describe its holes independently of the new tail.
        let latest = checkedThrough ?? items.values.map(\.date).max() ?? horizon
        // The log is placed by when a request **started**, and its counts are
        // only known once it ends: a request still running at the last read
        // began before it. Fifteen minutes back covers the longest of them.
        ranges.insert(.init(since: max(horizon, min(latest, now).addingTimeInterval(-Self.tailOverlap)), until: now), at: 0)
        return ranges
    }

    private func receive(_ page: [OpenCodeConsole.Item], cookie: String, now: Date) async {
        var changed = false
        for item in page where items[item.id] != item {
            items[item.id] = item
            changed = true
        }
        if changed { await publish(cookie: cookie, now: now) }
    }

    private func snapshot(now: Date) -> UsageLedger {
        var ledger = OpenCodeConsole.ledger(from: Array(items.values), now: now)
        ledger.hasPartialCounts = !complete
        return ledger
    }

    private func publish(cookie: String, now: Date) async {
        let listeners = observers.values.filter { $0.cookie == cookie }
        guard !listeners.isEmpty else { return }
        let ledger = snapshot(now: now)
        for listener in listeners { await listener.receive(ledger) }
    }

    private func restore(workspace: String) {
        items = [:]
        complete = false
        pending = []
        checkedThrough = nil
        org = workspace
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.org == workspace else { return }
        items = Dictionary(saved.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        pending = saved.pending ?? []
        complete = saved.complete && pending.isEmpty
        checkedThrough = saved.checkedThrough
    }

    private func save() {
        guard let file, let org,
              let data = try? JSONEncoder().encode(Saved(
                org: org, items: Array(items.values), complete: complete, pending: pending, checkedThrough: checkedThrough
              )) else { return }
        _ = LocalSecrets.write(data, to: file)
    }
}
