// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Bounded, adaptive walks of the console's newest-first request log. A page
/// tells us both which interval is already covered and the density near its
/// older edge. Split off roughly one more page of time there, leaving the
/// older remainder to another worker. Quiet weeks cost one request, while a
/// busy day can use several workers instead of one long cursor chain.
enum OpenCodeConsolePager {
    struct Range: Codable, Equatable, Sendable {
        let since: Date
        let until: Date
    }

    struct Result: Sendable {
        var pending: [Range] = []
        var outcome: OpenCodeConsole.PageResult?
        var complete: Bool { pending.isEmpty && outcome == nil }
    }

    private struct Job: Sendable {
        let range: Range
        var cursor: String?
        var seen: Set<String> = []
    }

    /// Internal injection points exercise the actual scheduler against a
    /// synthetic paginated server, including failures and coincident times.
    static func read(
        ranges: [Range],
        pageLimit: Int = OpenCodeConsole.pageLimit,
        retryDelay: Duration = .seconds(1),
        fetch: @escaping @Sendable (Range, String?) async -> OpenCodeConsole.PageResult,
        receive: @escaping @Sendable ([OpenCodeConsole.Item]) async -> Void
    ) async -> Result {
        await withTaskGroup(of: (Int, OpenCodeConsole.PageResult).self) { group in
            var queue = ranges.map { Job(range: $0) }
            var next = 0
            var issued = 0
            var active: [Int: Job] = [:]
            var result = Result()
            var sawItems = false
            var failed = false

            while !Task.isCancelled {
                while next < queue.count, active.count < OpenCodeConsole.concurrentPages, issued < pageLimit {
                    let job = queue[next]
                    next += 1
                    let id = issued
                    issued += 1
                    active[id] = job
                    group.addTask {
                        let page = await OpenCodeConsole.retryPage(retryDelay: retryDelay) {
                            await fetch(job.range, job.cursor)
                        }
                        return (id, page)
                    }
                }
                guard let (id, reply) = await group.next(), var job = active.removeValue(forKey: id) else { break }
                switch reply {
                case .signedOut:
                    group.cancelAll()
                    return Result(pending: ranges, outcome: .signedOut)
                case .failed:
                    result.pending.append(job.range)
                    failed = true
                case .page(let page):
                    if !page.items.isEmpty {
                        sawItems = true
                        await receive(page.items)
                    }
                    guard let cursor = page.nextCursor, !cursor.isEmpty, !page.items.isEmpty else { continue }
                    guard job.seen.insert(cursor).inserted else {
                        result.pending.append(job.range)
                        continue
                    }
                    if let split = split(job.range, after: page) {
                        queue.append(contentsOf: split.map { Job(range: $0) })
                    } else {
                        // Same-millisecond bursts cannot be split by time.
                        // Keep the server's opaque cursor, never fabricate one.
                        job.cursor = cursor
                        queue.append(job)
                    }
                }
            }
            if Task.isCancelled {
                group.cancelAll()
                return Result(pending: ranges, outcome: .failed)
            }
            result.pending.append(contentsOf: queue.dropFirst(next).map(\.range))
            if failed, !sawItems { result.outcome = .failed }
            return result
        }
    }

    private static func split(_ range: Range, after page: OpenCodeConsole.Page) -> [Range]? {
        let dates = page.items.map(\.date)
        guard dates.allSatisfy({ $0 >= range.since && $0 <= range.until }),
              let oldest = dates.min(), let newest = dates.max(),
              oldest > range.since, oldest < range.until else { return nil }
        let width = newest.timeIntervalSince(oldest)
        // Millisecond-aligned, inclusive bounds. Keep the oldest timestamp in
        // the next ranges so a page ending halfway through a timestamp loses
        // nothing. The history merges boundary duplicates by request id.
        let pivot = Date(timeIntervalSince1970:
            ((oldest.timeIntervalSince1970 - width) * 1000).rounded(.down) / 1000)
        guard width >= 1, pivot > range.since, pivot < oldest else { return nil }
        return [Range(since: pivot, until: oldest), Range(since: range.since, until: pivot)]
    }
}
