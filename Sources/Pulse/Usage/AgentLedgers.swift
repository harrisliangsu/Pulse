import CryptoKit
import Foundation
import SQLite3

/// One ledger per agent, however that agent keeps its records.
///
/// `UsageLedgerReader` reads the two CLIs that write JSONL transcripts and is
/// keyed by `Provider`, because what it was built for is the per-provider
/// history card. This is the other axis: every agent that has spent tokens on
/// this Mac, whether or not Pulse draws a ring for it.
///
/// **The two it already reads are delegated, not re-read.** Claude Code and
/// Codex go through the same reader and the same cache as before; only the
/// agents it has never heard of are parsed here.
actor AgentLedgers {
    static let shared = AgentLedgers()

    private var cached: [SpendAgent: UsageLedger] = [:]

    /// What each agent's store really looked like when it was last read, so a
    /// relaunch does not repeat the work.
    ///
    /// **The in-memory cache is not enough.** It answers for the life of the
    /// process; the page is opened once a day for a minute, and a cold read of
    /// a ten-thousand-row database is the whole of that minute. The stamp is
    /// computed from the store's own inputs — see `AgentCache.Stamp` for why
    /// the store's size and date are not one of them.
    private var stamps: [SpendAgent: AgentCache.Stamp] = [:]

    func ledgers(refresh: Bool = false) async -> [SpendAgent: UsageLedger] {
        var all: [SpendAgent: UsageLedger] = [:]

        for agent in SpendAgent.present {
            if !refresh, let known = cached[agent] {
                all[agent] = known
                continue
            }

            let ledger: UsageLedger
            if let provider = agent.provider {
                // Its own cache, its own file, unchanged.
                ledger = await UsageLedgerReader.shared.ledger(for: provider, refresh: refresh)
            } else {
                let prices = await ModelPrices.shared.prices()
                let before = agent.store.map { AgentCache.stamp(for: $0, prices: prices) }

                if !refresh, let before, let saved = AgentCache.load(agent), saved.stamp == before {
                    ledger = saved.ledger
                } else {
                    ledger = Self.read(agent, prices: prices)

                    // **Confirm the read left the store where it found it.**
                    // A store appended to while Pulse was reading it produces
                    // a ledger the *before* stamp no longer describes. Only a
                    // stable read is worth persisting. When the two differ the ledger
                    // is kept for this process only and no disk cache is
                    // claimed for it — no retry loop, just an honest miss next
                    // time.
                    let after = agent.store.map { AgentCache.stamp(for: $0, prices: prices) }
                    if let before, let after, after == before {
                        AgentCache.save(ledger, stamp: before, for: agent)
                    }
                }
                stamps[agent] = before
            }

            cached[agent] = ledger
            all[agent] = ledger
        }

        return all
    }

    private static func read(_ agent: SpendAgent, prices: [String: ModelPrice]) -> UsageLedger {
        guard let store = agent.store else { return .empty }

        return switch agent {
        case .openCode, .kiloCLI: OpenCodeStore.ledger(at: store, prices: prices)
        case .grok: GrokStore.ledger(at: store, prices: prices)
        case .kimiCLI: KimiCLIStore.ledger(at: store, prices: prices)
        case .devinCLI: DevinCLIStore.ledger(at: store, prices: prices)
        // Read by `UsageLedgerReader`, and never routed here.
        case .claudeCode, .codex: .empty
        }
    }
}

/// OpenCode's store, and Kilo CLI's — the same schema, because Kilo is a fork
/// of it down to the migrations.
///
/// ```sql
/// session(id, project_id, slug, directory, title, …)
/// message(id, session_id, time_created, time_updated, data)
/// ```
///
/// `data` is the message as JSON, and an assistant's carries everything a
/// ledger needs:
///
/// ```json
/// { "role": "assistant", "modelID": "mimo-v2.5", "providerID": "…",
///   "cost": 0, "time": { "created": 1777654926954 },
///   "tokens": { "total": 10812, "input": 9705, "output": 11,
///               "reasoning": 72, "cache": { "write": 0, "read": 1024 } } }
/// ```
///
/// **Its own `cost` is ignored.** It is whatever OpenCode's own table said at
/// the time, is zero for a plan it has no rate for, and would put two
/// differently-sourced figures in one total. Everything here is priced from
/// `ModelPrices` like the rest of the page.
///
/// **Reasoning tokens are counted as output**, which is where every price list
/// bills them and where the two CLIs' own counts already put them.
enum OpenCodeStore {
    static func ledger(at file: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return .empty
        }
        defer { sqlite3_close(handle) }

        let sessions = Self.sessions(handle)

        var buckets: [String: [String: TokenTally]] = [:]
        var perSession: [String: (tally: TokenTally, cost: Double, start: Date, end: Date)] = [:]
        // A session resumed across days is several quarter-hours, and the
        // project totals need to be able to count only the ones inside the
        // span on screen.
        var sessionSlots: [String: [String: (tokens: Int, cost: Double)]] = [:]
        let calendar = Calendar.current

        Self.each(handle, "SELECT session_id, data FROM message") { statement in
            guard
                let sessionText = sqlite3_column_text(statement, 0),
                let dataText = sqlite3_column_text(statement, 1)
            else { return }

            let session = String(cString: sessionText)
            let json = Data(String(cString: dataText).utf8)
            guard
                let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                root["role"] as? String == "assistant",
                let model = root["modelID"] as? String,
                let counts = root["tokens"] as? [String: Any],
                let at = Self.date(in: root)
            else { return }

            let cache = counts["cache"] as? [String: Any] ?? [:]
            let tally = TokenTally(
                input: Self.int(counts["input"]),
                cacheWrite: Self.int(cache["write"]),
                cacheRead: Self.int(cache["read"]),
                output: Self.int(counts["output"]) + Self.int(counts["reasoning"])
            )
            guard tally.total > 0 else { return }

            let cost = ModelPrices.price(for: model, in: prices).map { tally.cost(at: $0) } ?? 0
            let key = UsageLedgerReader.slotKey(for: at)
            buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally

            var slot = sessionSlots[session, default: [:]][key] ?? (tokens: 0, cost: 0)
            slot.tokens += tally.total
            slot.cost += cost
            sessionSlots[session, default: [:]][key] = slot

            if var running = perSession[session] {
                running.tally = running.tally + tally
                running.cost += cost
                running.start = min(running.start, at)
                running.end = max(running.end, at)
                perSession[session] = running
            } else {
                perSession[session] = (tally, cost, at, at)
            }
        }

        guard !buckets.isEmpty else { return .empty }

        var ledger = UsageLedgerReader.price(buckets, with: prices, calendar: calendar)
        ledger.sessions = perSession
            .compactMap { id, totals in
                let session = sessions[id]
                return UsageLedger.Session(
                    id: "\(file.path)#\(id)",
                    name: session?.slug ?? id,
                    title: session?.title,
                    project: session?.directory.map { URL(fileURLWithPath: $0).lastPathComponent },
                    start: totals.start,
                    end: totals.end,
                    tokens: totals.tally.total,
                    cost: totals.cost,
                    slots: UsageLedgerReader.sessionSlots(sessionSlots[id] ?? [:])
                )
            }
            .sorted { $0.end > $1.end }

        return ledger
    }

    // MARK: - The tables

    private struct Session {
        var slug: String?
        var title: String?
        var directory: String?
    }

    private static func sessions(_ handle: OpaquePointer?) -> [String: Session] {
        var rows: [String: Session] = [:]
        each(handle, "SELECT id, slug, title, directory FROM session") { statement in
            guard let id = sqlite3_column_text(statement, 0) else { return }
            rows[String(cString: id)] = Session(
                slug: sqlite3_column_text(statement, 1).map { String(cString: $0) },
                title: sqlite3_column_text(statement, 2).map { String(cString: $0) },
                directory: sqlite3_column_text(statement, 3).map { String(cString: $0) }
            )
        }
        return rows
    }

    /// Read-only and in place, the same way Pulse reads every other
    /// application's store: the agent may be running and its journal belongs
    /// to that process.
    private static func each(
        _ handle: OpaquePointer?,
        _ sql: String,
        _ row: (OpaquePointer?) -> Void
    ) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    /// `time.created` in milliseconds, with the row's own column as the
    /// fallback for a message that carries no time of its own.
    private static func date(in root: [String: Any]) -> Date? {
        guard let time = root["time"] as? [String: Any] else { return nil }
        let created = int(time["created"])
        guard created > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(created) / 1000)
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}


/// One agent's ledger, kept between launches.
///
/// **The whole ledger rather than its inputs.** `UsageLedgerReader` caches
/// per-file token counts and prices them afresh each time, because a price
/// change should not mean rescanning hundreds of megabytes. These stores are
/// read from several places rather than file-by-file, so the cache keeps the
/// finished ledger — and its validity is settled by the store's real inputs
/// and the price table, not by the store root's own size and date.
enum AgentCache {
    /// Whether the store's real inputs, and the money behind its cost, are
    /// the same as when the ledger was kept.
    ///
    /// **Not the store's own size and date.** Half these stores are
    /// directories — Grok's sessions and Kimi's — and appending a line to a
    /// log inside one leaves the directory's own stamp untouched, so a
    /// machine could go a week without noticing. The databases have the
    /// mirror-image problem: SQLite writes the WAL, and the `.db` file only
    /// moves when a checkpoint happens, so a restart read a stale disk cache
    /// too.
    struct Stamp: Codable, Equatable {
        /// A digest of every file the ledger was read out of. For a directory
        /// store that is a recursive walk of its logs and their title files,
        /// by path, size and modification date; for a database it is the
        /// `.db` plus the `-wal` and `-journal` beside it.
        let source: String
        /// A digest of the price table. Money is part of what is kept, so a
        /// table that changed has to invalidate it — including the empty
        /// table an offline first run would otherwise freeze at $0.00 for
        /// ever, since an unchanged store would never be read again.
        let prices: String
    }

    /// The stamp a store and the price table produce *now*.
    ///
    /// Internal rather than private so a test can hold it. The fingerprint is
    /// deliberately taken from the inputs and never from the contents the
    /// readers derive: reading a store must not change its own stamp, or
    /// every read would invalidate the cache it just filled.
    static func stamp(for store: URL, prices: [String: ModelPrice]) -> Stamp {
        Stamp(source: sourceFingerprint(of: store), prices: priceFingerprint(prices))
    }

    /// A digest of the files a store is read out of.
    ///
    /// For a directory, every regular file beneath it, recursively, so
    /// **adding, removing or changing a log — or the `state.json` a title
    /// sits in — moves the digest**. For a file, that file and SQLite's
    /// sidecars. `-shm` is left out on purpose: it is shared memory rather
    /// than data, and merely opening the store can touch it, which would make
    /// a read invalidate the cache it was about to validate.
    static func sourceFingerprint(of store: URL) -> String {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: store.path, isDirectory: &isDirectory) else {
            return digest("missing")
        }

        var lines: [String] = []

        if isDirectory.boolValue {
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            if let walker = manager.enumerator(
                at: store,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let file as URL in walker {
                    guard
                        let values = try? file.resourceValues(forKeys: Set(keys)),
                        values.isRegularFile == true
                    else { continue }
                    lines.append(Self.line(file.path, values.fileSize ?? 0, values.contentModificationDate))
                }
            }
        } else {
            // `""` is the database itself; the sidecars are where SQLite keeps
            // what it has not folded in yet. A missing one is simply absent.
            for suffix in ["", "-wal", "-journal"] {
                let url = URL(fileURLWithPath: store.path + suffix)
                guard
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                    let size = values.fileSize
                else { continue }
                lines.append(Self.line(url.lastPathComponent, size, values.contentModificationDate))
            }
        }

        // Sorted so the enumerator's order cannot make one unchanged store
        // look like two different ones.
        lines.sort()
        return digest(lines.joined(separator: "\n"))
    }

    /// A digest of the price table's rates and names.
    ///
    /// Content, not the file's date: a daily refresh that fetched the same
    /// table must not throw away every agent's cached ledger, and a table
    /// with even one changed rate — or a renamed model — must.
    static func priceFingerprint(_ prices: [String: ModelPrice]) -> String {
        guard !prices.isEmpty else { return "empty" }

        let canonical = prices.keys.sorted().map { id -> String in
            let price = prices[id]!
            let cacheRead = price.cacheRead.map { String($0) } ?? "-"
            let cacheWrite = price.cacheWrite.map { String($0) } ?? "-"
            let name = price.name ?? "-"
            return "\(id)\t\(price.input)\t\(price.output)\t\(cacheRead)\t\(cacheWrite)\t\(name)"
        }
        return digest(canonical.joined(separator: "\n"))
    }

    private static func line(_ path: String, _ size: Int, _ modified: Date?) -> String {
        "\(path)\t\(size)\t\(modified?.timeIntervalSince1970 ?? 0)"
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", Int($0)) }
            .joined()
    }

    struct Saved: Codable {
        let stamp: Stamp
        let ledger: StoredLedger
    }

    /// `UsageLedger` is not `Codable` and should not become so for this: it
    /// carries display concerns the cache has no business freezing. This is
    /// the part worth keeping.
    struct StoredLedger: Codable {
        var days: [StoredDay] = []
        var sessions: [StoredSession] = []
        var unpricedModels: [String] = []
        var modelNames: [String: String] = [:]
        var slots: [StoredSlot] = []
    }

    struct StoredDay: Codable {
        let date: Date
        let tokens: Int
        let cost: Double
        let unpricedTokens: Int
        let models: [String: Int]
        let tally: TokenTally
    }

    struct StoredSlot: Codable {
        let start: Date
        let tokens: Int
        let cost: Double
    }

    struct StoredSession: Codable {
        let id: String
        let name: String
        let title: String?
        let project: String?
        let start: Date
        let end: Date
        let tokens: Int
        let cost: Double
        /// **Required, not defaulted.** A cache written before sessions
        /// carried their buckets would otherwise decode with none, leaving
        /// project totals unable to respect the selected span. Missing it has to
        /// fail the decode so the store is read again.
        let slots: [StoredSlot]
    }

    static func load(_ agent: SpendAgent) -> (stamp: Stamp, ledger: UsageLedger)? {
        guard
            let data = try? Data(contentsOf: file(for: agent)),
            let saved = try? JSONDecoder().decode(Saved.self, from: data)
        else { return nil }

        var ledger = UsageLedger(
            days: saved.ledger.days.map {
                LedgerDay(
                    date: $0.date, tokens: $0.tokens, cost: $0.cost,
                    unpricedTokens: $0.unpricedTokens, models: $0.models, tally: $0.tally
                )
            },
            earliest: saved.ledger.days.first?.date,
            unpricedModels: saved.ledger.unpricedModels,
            modelNames: saved.ledger.modelNames,
            slots: saved.ledger.slots.map { .init(start: $0.start, tokens: $0.tokens, cost: $0.cost) }
        )
        ledger.sessions = saved.ledger.sessions.map {
            .init(
                id: $0.id, name: $0.name, title: $0.title, project: $0.project,
                start: $0.start, end: $0.end, tokens: $0.tokens, cost: $0.cost,
                slots: $0.slots.map { .init(start: $0.start, tokens: $0.tokens, cost: $0.cost) }
            )
        }
        return (saved.stamp, ledger)
    }

    static func save(_ ledger: UsageLedger, stamp: Stamp, for agent: SpendAgent) {
        let stored = StoredLedger(
            days: ledger.days.map {
                StoredDay(
                    date: $0.date, tokens: $0.tokens, cost: $0.cost,
                    unpricedTokens: $0.unpricedTokens, models: $0.models, tally: $0.tally
                )
            },
            sessions: ledger.sessions.map {
                StoredSession(
                    id: $0.id, name: $0.name, title: $0.title, project: $0.project,
                    start: $0.start, end: $0.end, tokens: $0.tokens, cost: $0.cost,
                    slots: $0.slots.map { StoredSlot(start: $0.start, tokens: $0.tokens, cost: $0.cost) }
                )
            },
            unpricedModels: ledger.unpricedModels,
            modelNames: ledger.modelNames,
            slots: ledger.slots.map { StoredSlot(start: $0.start, tokens: $0.tokens, cost: $0.cost) }
        )

        guard let data = try? JSONEncoder().encode(Saved(stamp: stamp, ledger: stored)) else { return }
        try? data.write(to: file(for: agent), options: .atomic)
    }

    private static func file(for agent: SpendAgent) -> URL {
        // **The number is the stored shape.** A `1` has a store-shaped stamp
        // and sessions without buckets; both decode differently now, and a
        // session missing its buckets cannot be counted within a span.
        // Renaming forces the one rescan that fills them in.
        PulseStorage.directory.appending(path: "agent-2-\(agent.rawValue).json")
    }
}

/// Grok Build's transcripts.
///
/// `~/.grok/sessions/<directory>/<session id>/updates.jsonl`, where the
/// directory is the working directory **percent-encoded** — `%2FUsers%2Fme%2FCode`
/// — which is the one agent here that gives its project away in the path
/// without losing anything.
///
/// One line per event, and the one that counts is the end of a turn:
///
/// ```json
/// { "timestamp": 1786775595,
///   "params": { "update": { "sessionUpdate": "turn_completed",
///     "usage": { "inputTokens": 33379, "outputTokens": 91,
///                "cachedReadTokens": 22272, "cacheCreationTokens": 0,
///                "reasoningTokens": 42,
///                "modelUsage": { "grok-4.6-build": { … } } } } } }
/// ```
///
/// **`modelUsage` is what names the model**, and a turn can touch more than
/// one — so the per-model counts are read from it and the flat totals beside
/// it are used only when it is absent.
enum GrokStore {
    static func ledger(at root: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var buckets: [String: [String: TokenTally]] = [:]
        var sessions: [UsageLedger.Session] = []

        let manager = FileManager.default
        let directories = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []

        for directory in directories {
            // The folder is the working directory, percent-encoded.
            let project = directory.lastPathComponent.removingPercentEncoding.map {
                URL(fileURLWithPath: $0).lastPathComponent
            }

            let runs = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for run in runs {
                let file = run.appending(path: "updates.jsonl")
                guard manager.fileExists(atPath: file.path),
                      let data = try? Data(contentsOf: file, options: .mappedIfSafe)
                else { continue }

                var tokens = 0
                var cost = 0.0
                var first: Date?
                var last: Date?
                var title: String?
                var runSlots: [String: (tokens: Int, cost: Double)] = [:]

                for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                    guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let params = root["params"] as? [String: Any],
                          let update = params["update"] as? [String: Any]
                    else { continue }

                    // The opening prompt, for a row that would otherwise be a
                    // uuid.
                    if title == nil, update["sessionUpdate"] as? String == "user_message_chunk",
                       let text = UsageLedgerReader.text(in: update["content"]),
                       let opening = UsageLedgerReader.title(from: text) {
                        title = opening
                    }

                    guard update["sessionUpdate"] as? String == "turn_completed",
                          let usage = update["usage"] as? [String: Any],
                          let seconds = root["timestamp"] as? Double ?? (root["timestamp"] as? Int).map(Double.init)
                    else { continue }

                    let at = Date(timeIntervalSince1970: seconds)
                    first = min(first ?? at, at)
                    last = max(last ?? at, at)
                    let key = UsageLedgerReader.slotKey(for: at)

                    let perModel = usage["modelUsage"] as? [String: [String: Any]]
                        ?? ["grok": usage]

                    for (model, counts) in perModel {
                        let tally = TokenTally(
                            input: int(counts["inputTokens"]),
                            cacheWrite: int(counts["cacheCreationTokens"]),
                            cacheRead: int(counts["cachedReadTokens"]),
                            output: int(counts["outputTokens"]) + int(counts["reasoningTokens"])
                        )
                        guard tally.total > 0 else { continue }

                        let money = ModelPrices.price(for: model, in: prices).map { tally.cost(at: $0) } ?? 0
                        buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally
                        tokens += tally.total
                        cost += money

                        var slot = runSlots[key] ?? (tokens: 0, cost: 0)
                        slot.tokens += tally.total
                        slot.cost += money
                        runSlots[key] = slot
                    }
                }

                guard tokens > 0, let first, let last else { continue }
                sessions.append(
                    UsageLedger.Session(
                        id: file.path, name: run.lastPathComponent, title: title,
                        project: project, start: first, end: last, tokens: tokens, cost: cost,
                        slots: UsageLedgerReader.sessionSlots(runSlots)
                    )
                )
            }
        }

        guard !buckets.isEmpty else { return .empty }
        var ledger = UsageLedgerReader.price(buckets, with: prices)
        ledger.sessions = sessions.sorted { $0.end > $1.end }
        return ledger
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}

/// Kimi's CLI, which writes the raw exchange to `wire.jsonl`.
///
/// ```json
/// { "timestamp": …,
///   "message": { "payload": { "token_usage": {
///     "input_other": 4340, "output": 38,
///     "input_cache_read": 9216, "input_cache_creation": 0 } } } }
/// ```
///
/// **`input_other` is fresh input**, as the name says: the cache figures are
/// counted beside it rather than inside it, which is the same arrangement
/// Claude Code uses and the opposite of Codex's.
///
/// **It names no model, anywhere.** Neither the wire log nor the session state
/// carries one, so its tokens are counted and never costed — the same answer
/// Pulse gives for any model with no published price, arrived at one step
/// earlier. The id below is a placeholder so the buckets have a key, and is
/// deliberately one no price list can match.
enum KimiCLIStore {
    static func ledger(at root: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var buckets: [String: [String: TokenTally]] = [:]
        var sessions: [UsageLedger.Session] = []

        let manager = FileManager.default
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: nil) else { return .empty }

        for case let file as URL in walker where file.lastPathComponent == "wire.jsonl" {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }

            var tokens = 0
            var cost = 0.0
            var first: Date?
            var last: Date?
            var sessionSlots: [String: (tokens: Int, cost: Double)] = [:]
            let model = "kimi (unnamed)"

            for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = root["message"] as? [String: Any],
                      let payload = message["payload"] as? [String: Any]
                else { continue }

                guard let usage = payload["token_usage"] as? [String: Any] else { continue }

                let tally = TokenTally(
                    input: int(usage["input_other"]),
                    cacheWrite: int(usage["input_cache_creation"]),
                    cacheRead: int(usage["input_cache_read"]),
                    output: int(usage["output"])
                )
                guard tally.total > 0 else { continue }

                let seconds = (root["timestamp"] as? Double)
                    ?? (root["timestamp"] as? Int).map(Double.init)
                    ?? 0
                guard seconds > 0 else { continue }

                let at = Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
                first = min(first ?? at, at)
                last = max(last ?? at, at)

                let key = UsageLedgerReader.slotKey(for: at)
                let money = ModelPrices.price(for: model, in: prices).map { tally.cost(at: $0) } ?? 0
                buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally
                tokens += tally.total
                cost += money

                var slot = sessionSlots[key] ?? (tokens: 0, cost: 0)
                slot.tokens += tally.total
                slot.cost += money
                sessionSlots[key] = slot
            }

            guard tokens > 0, let first, let last else { continue }
            sessions.append(
                UsageLedger.Session(
                    id: file.path,
                    name: file.deletingLastPathComponent().lastPathComponent,
                    // The session's own state file keeps the title beside the
                    // wire log. Neither carries a working directory.
                    title: Self.title(besideWire: file),
                    project: nil,
                    start: first, end: last, tokens: tokens, cost: cost,
                    slots: UsageLedgerReader.sessionSlots(sessionSlots)
                )
            )
        }

        guard !buckets.isEmpty else { return .empty }
        var ledger = UsageLedgerReader.price(buckets, with: prices)
        ledger.sessions = sessions.sorted { $0.end > $1.end }
        return ledger
    }

    private static func title(besideWire file: URL) -> String? {
        let state = file.deletingLastPathComponent().appending(path: "state.json")
        guard
            let data = try? Data(contentsOf: state),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let custom = root["custom_title"] as? String
        else { return nil }
        return UsageLedgerReader.title(from: custom)
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}

/// Devin's CLI, which keeps its conversations in SQLite.
///
/// `message_nodes.chat_message` is the message as JSON, and an assistant's
/// carries its own metrics:
///
/// ```json
/// { "role": "assistant", "metadata": {
///     "generation_model": "…", "created_at": …,
///     "metrics": { "input_tokens": 11486, "output_tokens": 254,
///                  "cache_read_tokens": 6450, "cache_creation_tokens": null } } }
/// ```
///
/// **Not the same store as the quota route.** `DevinUsageService` reads the
/// desktop app's saved plan for the ring; this is the CLI's own transcript
/// database, and the two know nothing about each other.
enum DevinCLIStore {
    static func ledger(at file: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return .empty
        }
        defer { sqlite3_close(handle) }

        var directories: [String: (directory: String?, title: String?)] = [:]
        Self.each(handle, "SELECT id, working_directory, title FROM sessions") { statement in
            guard let id = sqlite3_column_text(statement, 0) else { return }
            directories[String(cString: id)] = (
                sqlite3_column_text(statement, 1).map { String(cString: $0) },
                sqlite3_column_text(statement, 2).map { String(cString: $0) }
            )
        }

        var buckets: [String: [String: TokenTally]] = [:]
        var perSession: [String: (tokens: Int, cost: Double, start: Date, end: Date)] = [:]
        var sessionSlots: [String: [String: (tokens: Int, cost: Double)]] = [:]

        Self.each(handle, "SELECT session_id, chat_message, created_at FROM message_nodes") { statement in
            guard
                let sessionText = sqlite3_column_text(statement, 0),
                let messageText = sqlite3_column_text(statement, 1)
            else { return }

            let session = String(cString: sessionText)
            let json = Data(String(cString: messageText).utf8)
            guard
                let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                let metadata = root["metadata"] as? [String: Any],
                let metrics = metadata["metrics"] as? [String: Any]
            else { return }

            let tally = TokenTally(
                input: int(metrics["input_tokens"]),
                cacheWrite: int(metrics["cache_creation_tokens"]),
                cacheRead: int(metrics["cache_read_tokens"]),
                output: int(metrics["output_tokens"])
            )
            guard tally.total > 0 else { return }

            // The row's own column is the reliable one; the message's
            // `created_at` is there for the rows that have it.
            let seconds = Double(sqlite3_column_int64(statement, 2))
            let at = Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
            guard at.timeIntervalSince1970 > 0 else { return }

            let model = metadata["generation_model"] as? String ?? "devin"
            let key = UsageLedgerReader.slotKey(for: at)
            buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally

            let cost = ModelPrices.price(for: model, in: prices).map { tally.cost(at: $0) } ?? 0

            var slot = sessionSlots[session, default: [:]][key] ?? (tokens: 0, cost: 0)
            slot.tokens += tally.total
            slot.cost += cost
            sessionSlots[session, default: [:]][key] = slot

            if var running = perSession[session] {
                running.tokens += tally.total
                running.cost += cost
                running.start = min(running.start, at)
                running.end = max(running.end, at)
                perSession[session] = running
            } else {
                perSession[session] = (tally.total, cost, at, at)
            }
        }

        guard !buckets.isEmpty else { return .empty }

        var ledger = UsageLedgerReader.price(buckets, with: prices)
        ledger.sessions = perSession.map { id, totals in
            let session = directories[id]
            return UsageLedger.Session(
                id: "\(file.path)#\(id)",
                name: id,
                title: session?.title,
                project: session?.directory.map { URL(fileURLWithPath: $0).lastPathComponent },
                start: totals.start,
                end: totals.end,
                tokens: totals.tokens,
                cost: totals.cost,
                slots: UsageLedgerReader.sessionSlots(sessionSlots[id] ?? [:])
            )
        }
        .sorted { $0.end > $1.end }

        return ledger
    }

    private static func each(
        _ handle: OpaquePointer?,
        _ sql: String,
        _ row: (OpaquePointer?) -> Void
    ) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
