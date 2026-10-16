// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// MiniMax Code's own session log: `~/.minimax/v2/sessions/<yyyy>/<MM>/<dd>/
/// <session>/messages.jsonl`, written by the desktop app as it runs (issue #86).
///
/// One message per line, with no `type` wrapper and no session header:
/// `message_id` at the top, and under `message` the `role`, the `model` that
/// actually answered (a request can be routed to another vendor's model —
/// `kimi-for-coding`), a millisecond `timestamp`, and a Pi-shaped `usage`
/// (`input`, `output`, `cacheRead`, `cacheWrite`, `totalTokens`; `input`
/// excludes cache reads), read through `PiTranscript.usage`.
///
/// - **`usage.cost` is not read.** It is zero on every line; the counts are
///   priced like any other agent's.
/// - **A message with no tokens at all is no message** — history migrated
///   from an earlier version is stored as all-zero lines.
/// - **A `message_id` is counted once across files**, so a resumed session that
///   copies its history does not count it twice.
/// - **Only `messages.jsonl`.** A subagent's readable transcript beside it
///   (`task-*.readable.v1.jsonl`) is not a usage record.
///
/// Evidence: *spec* — the shape is TokenTracker's reader and its fixture,
/// which mirrors a real record. The MiniMax Code on the Mac this was written
/// on was an older version with an older layout and no usage in it.
enum MiniMaxCodeSessionReader {
    /// The desktop app's session tree. No override: none is documented.
    static func root(home: URL) -> URL {
        home.appending(path: ".minimax/v2/sessions")
    }

    static func files(in roots: [URL]) -> [URL] {
        AgentLogIO.files(in: roots, extensions: ["jsonl"]).filter { $0.lastPathComponent == "messages.jsonl" }
    }

    static func records(roots: [URL]) -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []
        for file in files(in: roots) {
            guard !Task.isCancelled else { return [] }
            let session = file.deletingLastPathComponent().lastPathComponent
            for row in AgentLogIO.jsonLines(at: file) {
                guard let record = record(from: row, session: session) else { continue }
                records.append(record)
            }
        }
        return records
    }

    /// One line's usage, or nil for a line that is not an assistant message
    /// with tokens, a time and a model.
    static func record(from row: [String: Any], session: String?) -> AgentUsageRecord? {
        guard
            let message = AgentLogIO.object(row["message"]),
            AgentLogIO.text(message["role"]) == "assistant",
            let usage = AgentLogIO.object(message["usage"])
        else { return nil }

        let (tally, unclassified) = PiTranscript.usage(usage)
        guard tally.total > 0 || unclassified > 0,
              let model = AgentLogIO.text(message["model"]),
              let timestamp = AgentLogIO.timestamp(message["timestamp"], milliseconds: true)
                ?? AgentLogIO.timestamp(row["timestamp"], milliseconds: true)
        else { return nil }

        var record = AgentUsageRecord(timestamp: timestamp, model: model, tally: tally)
        record.sessionID = session
        record.deduplicationID = AgentLogIO.text(row["message_id"]).map { "mcode:message:\($0)" }
        record.unclassifiedTokens = unclassified
        return record
    }
}
