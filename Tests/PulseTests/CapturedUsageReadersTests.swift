import Foundation
import Testing
@testable import Pulse

/// The Group E readers, driven from private temporary roots.
///
/// Every fixture here is written by the test and every root is deleted after
/// it. Nothing touches a real agent store, a network, or a login, and no
/// process is ever run — these readers only ever open files a user already
/// exported.
@Suite("Captured usage readers")
struct CapturedUsageReadersTests {
    // MARK: - Harness

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory
            .appending(path: "PulseCaptured-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    /// Rates chosen so a million tokens of each kind costs its rate in dollars,
    /// distinct per kind so a misread bucket is visible.
    private static let prices: [String: ModelPrice] = [
        "gpt-5.4": ModelPrice(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, name: "GPT-5.4"),
        "claude-sonnet-4-5": ModelPrice(input: 5, output: 6, cacheRead: 7, cacheWrite: 8, name: "Claude Sonnet 4.5"),
    ]

    /// The router marks a client's records `.importedRecords` at the build
    /// step; the reader itself only supplies records. The tests mirror that.
    private static func importedLedger(
        _ records: [AgentUsageRecord],
        namespace: String
    ) -> UsageLedger {
        AgentUsageLedger.build(
            records, prices: Self.prices, namespace: namespace,
            calendar: Self.calendar, origin: .importedRecords
        )
    }

    // MARK: - Catalog and inputs

    @Test("The family exposes exactly the six local-export clients and their roots")
    func catalog() throws {
        #expect(
            CapturedUsageReaders.supportedClients
                == Set(["cursor", "antigravity", "trae", "warp", "hindsight", "mcode"])
        )

        let home = URL(fileURLWithPath: "/home/tester")
        let environment = ["TOKSCALE_CONFIG_DIR": "/opt/tokscale", "HINDSIGHT_HOME": "/opt/hindsight"]

        func paths(_ client: String) -> Set<String> {
            Set(CapturedUsageReaders.inputs(client: client, home: home, environment: environment).map(\.path))
        }

        #expect(paths("cursor") == [
            "/opt/tokscale/cursor-cache",
            "/home/tester/Library/Application Support/Pulse/UsageImports/cursor",
        ])
        #expect(paths("antigravity") == [
            "/opt/tokscale/antigravity-cache/sessions",
            "/home/tester/Library/Application Support/Pulse/UsageImports/antigravity",
        ])
        #expect(paths("trae") == [
            "/opt/tokscale/trae-cache/sessions",
            "/home/tester/Library/Application Support/Pulse/UsageImports/trae",
        ])
        #expect(paths("warp") == [
            "/opt/tokscale/warp-cache",
            "/home/tester/Library/Application Support/Pulse/UsageImports/warp",
        ])
        #expect(paths("hindsight") == [
            "/opt/hindsight/usage",
            "/home/tester/Library/Application Support/Pulse/UsageImports/hindsight",
        ])
        #expect(paths("mcode") == [
            "/opt/tokscale/headless/mcode",
            "/home/tester/Library/Application Support/Pulse/UsageImports/mcode",
        ])

        // Defaults when no override is set.
        let defaults = Set(
            CapturedUsageReaders
                .inputs(client: "cursor", home: home, environment: [:])
                .map(\.path)
        )
        #expect(defaults.contains("/home/tester/.config/tokscale/cursor-cache"))

        #expect(CapturedUsageReaders.inputs(client: "nope", home: home, environment: [:]).isEmpty)
        #expect(CapturedUsageReaders.records(client: "nope", roots: []).isEmpty)
    }

    // MARK: - Cursor

    @Test("Cursor JSON keeps equal rows, names only real sessions, and folds a copied file")
    func cursorJSON() throws {
        let root = try Self.temporary("cursor-json")
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = #"""
        {"usageEventsDisplay":[
          {"conversationId":"conv-1","timestamp":1717200000000,"model":"gpt-5.4",
           "tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":30,"cacheWriteTokens":40}},
          {"conversationId":"conv-1","timestamp":1717200000000,"model":"gpt-5.4",
           "tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":30,"cacheWriteTokens":40}},
          {"conversationId":"conv-2","timestamp":"2024-06-01T00:10:00Z","model":"  ",
           "tokenUsage":{"inputTokens":5}},
          {"conversationId":"conv-3","timestamp":"2024-06-01T00:20:00Z","model":"mystery",
           "tokenUsage":{"inputTokens":50}},
          {"timestamp":"2024-06-01T00:25:00Z","model":"gpt-5.4",
           "tokenUsage":{"inputTokens":1}},
          {"conversationId":"conv-5","timestamp":"2024-06-01T00:30:00Z","model":"gpt-5.4",
           "chargedCents":999}
        ]}
        """#
        // The same export in two roots: byte-identical, so it is one export.
        try Self.write(fixture, to: root.appending(path: "cache/usage.json"))
        try Self.write(fixture, to: root.appending(path: "imports/usage.json"))

        let records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        // conv-1 twice (two real requests), conv-3, and the sessionless event;
        // the blank model, the bad time and the price-only row are skipped.
        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.deduplicationID == nil })
        #expect(records.allSatisfy { !$0.isPartial })

        let conversation = records.filter { $0.sessionID == "cursor:active:conv-1" }
        #expect(conversation.count == 2)
        #expect(conversation.allSatisfy {
            $0.tally == TokenTally(input: 100, cacheWrite: 40, cacheRead: 30, output: 20)
        })

        let unpriced = try #require(records.first { $0.model == "mystery" })
        #expect(unpriced.tally == TokenTally(input: 50))
        #expect(unpriced.sessionID == "cursor:active:conv-3")

        // No conversation id: tokens count, but no session is invented.
        let sessionless = try #require(records.first { $0.tally == TokenTally(input: 1) })
        #expect(sessionless.sessionID == nil)
    }

    @Test("Cursor CSV reads the schema by column name, keeps an embedded comma, and names a cloud session")
    func cursorCSV() throws {
        let root = try Self.temporary("cursor-csv")
        defer { try? FileManager.default.removeItem(at: root) }

        let csv = "Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,"
            + "Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost\r\n"
            + "2024-06-02T12:00:00Z,cloud-9,,chat,\"GPT-5.4, mini\",false,\"1,000\",250,300,50,1600,\"$0.10\"\r\n"
            + "2024-06-02T13:00:00Z,,,chat,broken,false,1\r\n"
            + "2024-06-03T00:00:00Z,,,,mystery,false,0,0,0,0,0,0\r\n"
        try Self.write(csv, to: root.appending(path: "usage.csv"))

        let records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        #expect(records.count == 1)

        let record = try #require(records.first)
        // A quoted model keeps its embedded comma; a quoted count keeps its
        // thousands separator as one number rather than two columns.
        #expect(record.model == "GPT-5.4, mini")
        #expect(record.tally == TokenTally(input: 250, cacheWrite: 1_000, cacheRead: 300, output: 50))
        // A report row's timing is aggregate, and only a stated cloud id is a
        // session — the plain column header gives no row a session.
        #expect(record.isAggregate)
        #expect(record.sessionID == "cursor:active:cloud:cloud-9")
        #expect(record.deduplicationID == nil)
    }

    @Test("A cross-day cloud CSV session stays inside Today, including after a cache reload")
    func cursorSessionCalendarDays() throws {
        let root = try Self.temporary("cursor-calendar-days")
        defer { try? FileManager.default.removeItem(at: root) }
        let csv = """
        Date,Model,Input (w/o Cache Write),Input (w/ Cache Write),Cache Read,Output Tokens,Cloud Agent ID
        2026-09-15T12:00:00Z,gpt-5.4,1000000,0,0,0,cloud-1
        2026-09-16T12:00:00Z,gpt-5.4,100000,0,0,0,cloud-1
        """
        try Self.write(csv, to: root.appending(path: "usage.csv"))
        let records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        let original = Self.importedLedger(records, namespace: "cursor")
        let cache = root.appending(path: "ledger.json")
        AgentCache.save(original, stamp: .init(source: "fixture", prices: "fixture"), for: .cursor, at: cache)
        let reloaded = try #require(AgentCache.load(.cursor, at: cache)).ledger
        #expect(reloaded == original)
        let now = try #require(records.map(\.timestamp).max())
        for ledger in [original, reloaded] {
            #expect(ledger.slots.isEmpty)
            #expect(ledger.sessions.first?.slots.isEmpty == true)
            #expect(ledger.sessions.first?.days.count == 2)
            let today = SpendSummary.of([.cursor: ledger], overLast: 1, now: now, calendar: Self.calendar)
            #expect(today.tokens == 100_000)
            #expect(today.sessions.first?.session.tokens == 100_000)
            #expect(abs((today.sessions.first?.session.cost ?? -1) - 0.1) < 1e-12)
            #expect(today.hours.isEmpty)
            let week = SpendSummary.of([.cursor: ledger], overLast: 7, now: now, calendar: Self.calendar)
            #expect(week.sessions.first?.session.tokens == 1_100_000)
        }
    }

    @Test("Cursor accepts a schema-valid import under any name and ignores an unrelated file")
    func cursorImportNames() throws {
        let root = try Self.temporary("cursor-import")
        defer { try? FileManager.default.removeItem(at: root) }

        let json = #"{"usageEventsDisplay":[{"conversationId":"x","timestamp":1717200000000,"model":"gpt-5.4","tokenUsage":{"inputTokens":7}}]}"#
        try Self.write(json, to: root.appending(path: "my-export-2024.json"))
        // Not a Cursor shape: no `usageEventsDisplay` root.
        try Self.write(#"{"notes":"something else"}"#, to: root.appending(path: "notes.json"))

        let csv = "Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost\n"
            + "2024-06-05T00:00:00Z,chat,gpt-5.4,false,0,42,0,0,42,0\n"
        try Self.write(csv, to: root.appending(path: "another-account.csv"))

        let records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        // One JSON event and one CSV row, from two differently named files.
        // They share one import scope — a file name is not an account — so the
        // scope is marked unknown.
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.isPartial })
        #expect(records.contains { $0.tally == TokenTally(input: 7) })
        #expect(records.contains { $0.tally == TokenTally(input: 42) })
    }

    @Test("An empty or corrupt JSON must not suppress a valid CSV, and unprovable overlap is partial")
    func cursorCrossFormat() throws {
        let root = try Self.temporary("cursor-cross")
        defer { try? FileManager.default.removeItem(at: root) }

        let csv = "Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost\n"
            + "2024-06-02T12:00:00Z,chat,gpt-5.4,false,0,100,0,0,100,0\n"
        try Self.write(csv, to: root.appending(path: "usage.csv"))
        let jsonURL = root.appending(path: "usage.json")

        // A corrupt JSON is not a usable lane.
        try Self.write("{not json", to: jsonURL)
        var records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        #expect(records.count == 1)
        #expect(records.first?.tally == TokenTally(input: 100))
        #expect(records.first?.isPartial == false)

        // A schema-valid but empty JSON is no lane either.
        try Self.write(#"{"usageEventsDisplay":[]}"#, to: jsonURL)
        records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        #expect(records.count == 1)
        #expect(records.first?.isPartial == false)

        // A JSON event outside the CSV's date is a clean union.
        try Self.write(
            #"{"usageEventsDisplay":[{"conversationId":"n","timestamp":"2024-06-10T00:00:00Z","model":"gpt-5.4","tokenUsage":{"inputTokens":7}}]}"#,
            to: jsonURL
        )
        records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        #expect(records.count == 2)
        #expect(records.allSatisfy { !$0.isPartial })

        // A JSON event inside the CSV's date is unverifiable overlap: the CSV
        // row is dropped and the account is marked incomplete, not silently
        // reconciled.
        try Self.write(
            #"{"usageEventsDisplay":[{"conversationId":"n","timestamp":"2024-06-02T12:00:00Z","model":"gpt-5.4","tokenUsage":{"inputTokens":7}}]}"#,
            to: jsonURL
        )
        records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        #expect(records.count == 1)
        #expect(records.first?.tally == TokenTally(input: 7))
        #expect(records.first?.isPartial == true)

        let ledger = Self.importedLedger(records, namespace: "cursor")
        #expect(ledger.hasPartialCounts)
    }

    @Test("Two same-account exports sharing a row are reconciled, not concatenated")
    func cursorOverlappingJSON() throws {
        let root = try Self.temporary("cursor-overlap")
        defer { try? FileManager.default.removeItem(at: root) }

        let shared = #"{"conversationId":"a","timestamp":"2024-06-01T00:00:00Z","model":"gpt-5.4","tokenUsage":{"inputTokens":10}}"#
        let extra = #"{"conversationId":"b","timestamp":"2024-06-01T06:00:00Z","model":"gpt-5.4","tokenUsage":{"inputTokens":20}}"#
        // Same native name in two roots: one account, two overlapping exports
        // {A} and {A, B}.
        try Self.write(#"{"usageEventsDisplay":[\#(shared)]}"#, to: root.appending(path: "cache/usage.json"))
        try Self.write(#"{"usageEventsDisplay":[\#(shared),\#(extra)]}"#, to: root.appending(path: "imports/usage.json"))

        let records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        // A once, then B: never 2A + B. The unconfirmed overlap is flagged.
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.isPartial })
        #expect(records.filter { $0.sessionID == "cursor:active:a" }.count == 1)
        #expect(records.reduce(0) { $0 + $1.tally.total } == 30)
    }

    @Test("Two declared accounts with an equal row are not mixed together")
    func cursorAccountsStaySeparate() throws {
        let root = try Self.temporary("cursor-accounts")
        defer { try? FileManager.default.removeItem(at: root) }

        let row = #"{"conversationId":"x","timestamp":"2024-06-01T00:00:00Z","model":"gpt-5.4","tokenUsage":{"inputTokens":10}}"#
        try Self.write(#"{"usageEventsDisplay":[\#(row)]}"#, to: root.appending(path: "usage.a.json"))
        try Self.write(#"{"usageEventsDisplay":[\#(row)]}"#, to: root.appending(path: "usage.b.json"))

        let records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        // Same content, two real accounts: two rows, and no overlap to flag.
        #expect(records.count == 2)
        #expect(records.allSatisfy { !$0.isPartial })
        #expect(records.contains { $0.sessionID == "cursor:a:x" })
        #expect(records.contains { $0.sessionID == "cursor:b:x" })
    }

    // MARK: - Antigravity

    @Test("Antigravity falls back to session_meta and marks reasoning partial rather than adding it to output")
    func antigravity() throws {
        let root = try Self.temporary("antigravity")
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = [
            #"{"type":"session_meta","sessionId":"s1","modelId":"gpt-5.4"}"#,
            #"{"type":"usage","sessionId":"s1","timestamp":1717200000000,"input":100,"output":10,"cacheRead":5,"cacheWrite":2,"reasoning":3,"responseId":"r1"}"#,
            // No model of its own: the session meta supplies one.
            #"{"type":"usage","sessionId":"s1","timestamp":1717200060000,"input":2,"output":2,"cacheRead":-9,"responseId":"r2"}"#,
            // No response id: it is its own record, not folded with anything.
            #"{"type":"usage","sessionId":"s1","timestamp":1717200120000,"input":3,"output":3}"#,
            // A placeholder names no resolvable model.
            #"{"type":"usage","sessionId":"s1","timestamp":1717200180000,"modelId":"MODEL_PLACEHOLDER_9","input":9,"output":9}"#,
            // All-zero rows assert nothing.
            #"{"type":"usage","sessionId":"s1","timestamp":1717200240000,"input":0,"output":0}"#,
            // A missing timestamp cannot be placed.
            #"{"type":"usage","sessionId":"s1","modelId":"gpt-5.4","input":4,"output":4}"#,
        ].joined(separator: "\n")
        try Self.write(lines, to: root.appending(path: "sessions/a.jsonl"))

        let records = CapturedUsageReaders.records(client: "antigravity", roots: [root])
        #expect(records.count == 3)

        let withReasoning = try #require(records.first)
        // Output stays exactly as reported; reasoning is neither added nor
        // placed in another bucket, and the record says it may be incomplete.
        #expect(withReasoning.tally == TokenTally(input: 100, cacheWrite: 2, cacheRead: 5, output: 10))
        #expect(withReasoning.unclassifiedTokens == 0)
        #expect(withReasoning.isPartial)
        #expect(withReasoning.deduplicationID == "antigravity:r1")
        #expect(withReasoning.sessionID == "s1")

        let clamped = try #require(records.first { $0.deduplicationID == "antigravity:r2" })
        #expect(clamped.tally == TokenTally(input: 2, output: 2))
        #expect(clamped.unclassifiedTokens == 0)
        #expect(!clamped.isPartial)

        let anonymous = try #require(records.first { $0.tally == TokenTally(input: 3, output: 3) })
        #expect(anonymous.deduplicationID == nil)
    }

    // MARK: - Trae

    @Test("Trae reads the four counters and keeps two equal rows in one session and second")
    func trae() throws {
        let root = try Self.temporary("trae")
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = #"""
        [
          {"session_id":"t1","model_name":"GPT-5.4","usage_time":1717200000,"dollar_float":0.5,
           "extra_info":{"input_token":100,"output_token":20,"cache_read_token":30,"cache_write_token":40,"prelude_token":999}},
          {"session_id":"t1","model_name":"GPT-5.4","usage_time":1717200000,
           "extra_info":{"input_token":100,"output_token":20,"cache_read_token":30,"cache_write_token":40}},
          {"session_id":"t2","model_name":"","mode":"auto","usage_time":1717203600,
           "extra_info":{"input_token":10,"output_token":5}},
          {"session_id":"","model_name":"GPT-5.4","usage_time":1717203600,
           "extra_info":{"input_token":1}},
          {"session_id":"t4","model_name":"Mystery X","usage_time":0,
           "extra_info":{"input_token":9}},
          {"session_id":"t5","model_name":"Claude Sonnet 4.5","usage_time":1717207200,
           "extra_info":{"input_token":7,"output_token":3,"cache_read_token":0,"cache_write_token":0}}
        ]
        """#
        // The same dump twice: byte-identical, so it is one page.
        try Self.write(fixture, to: root.appending(path: "sessions/page.json"))
        try Self.write(fixture, to: root.appending(path: "sessions/page-copy.json"))

        let records = CapturedUsageReaders.records(client: "trae", roots: [root])
        // t1 twice (two rows, no row id), t2 auto, t5; empty session and
        // non-positive time dropped. A byte-identical copy is one page, and
        // one page has no cross-page overlap to flag.
        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.deduplicationID == nil })
        #expect(records.allSatisfy { !$0.isPartial })

        let sameSecond = records.filter { $0.sessionID == "t1" }
        #expect(sameSecond.count == 2)
        #expect(sameSecond.allSatisfy {
            $0.tally == TokenTally(input: 100, cacheWrite: 40, cacheRead: 30, output: 20)
        })

        let auto = try #require(records.first { $0.model == "trae-auto" })
        #expect(auto.tally == TokenTally(input: 10, output: 5))

        let claude = try #require(records.first { $0.model == "claude-sonnet-4-5" })
        #expect(claude.tally == TokenTally(input: 7, output: 3))
    }

    @Test("Two overlapping Trae pages are both kept, and the account is marked incomplete")
    func traeOverlap() throws {
        let root = try Self.temporary("trae-overlap")
        defer { try? FileManager.default.removeItem(at: root) }

        let row = #"{"session_id":"t1","model_name":"GPT-5.4","usage_time":1717200000,"extra_info":{"input_token":100,"output_token":20,"cache_read_token":30,"cache_write_token":40}}"#
        try Self.write("[\(row)]", to: root.appending(path: "sessions/a.json"))
        try Self.write("[\(row),{\"session_id\":\"t2\",\"model_name\":\"GPT-5.4\",\"usage_time\":1717209000,\"extra_info\":{\"input_token\":5,\"output_token\":5}}]",
                       to: root.appending(path: "sessions/b.json"))

        let records = CapturedUsageReaders.records(client: "trae", roots: [root])
        // The shared row is counted once, not once per page; the second page's
        // extra row is added. The unknown increment in the overlap is flagged.
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.isPartial })
        #expect(records.filter { $0.sessionID == "t1" }.count == 1)
        #expect(records.contains { $0.sessionID == "t2" && $0.tally == TokenTally(input: 5, output: 5) })
    }

    // MARK: - Warp

    @Test("Warp reports requests and cost but no tokens, so it yields no records")
    func warpHasNoTokens() throws {
        let root = try Self.temporary("warp")
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = #"""
        {"syncedAt":"2024-06-01T00:00:00Z",
         "usage":{"requestsUsed":42,"spendCents":1234},
         "workspaces":[{"id":"ws 1","name":"Work","requestsUsed":10,"spendCents":99}]}
        """#
        try Self.write(fixture, to: root.appending(path: "warp-cache/usage.json"))

        #expect(CapturedUsageReaders.records(client: "warp", roots: [root]).isEmpty)

        // The root is still named, so a UI can say the snapshot exists and has
        // no token data rather than showing a zero.
        let roots = CapturedUsageReaders.inputs(
            client: "warp", home: URL(fileURLWithPath: "/home/tester"), environment: [:]
        )
        #expect(roots.contains { $0.path.hasSuffix("/warp-cache") })
    }

    // MARK: - Hindsight

    @Test("Hindsight keeps a valid ledger row and skips malformed, idle and untimed ones")
    func hindsight() throws {
        let root = try Self.temporary("hindsight")
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = [
            #"{"id":"h1","trace_id":"tr1","provider":"ollama","model":"llama-3.3-70b","operation":"chat","scope":"bank-a","started_at":"2024-06-01T00:00:00Z","input_tokens":100,"output_tokens":20,"cached_tokens":5,"total_tokens":120,"bank":"bank-a"}"#,
            #"{"id":"h2","model":"mistral","started_at":"2024-06-01T01:00:00Z","input_tokens":0,"output_tokens":0,"total_tokens":0}"#,
            #"{"id":"h3","model":"mistral","started_at":"not-a-time","input_tokens":5,"output_tokens":5,"total_tokens":10}"#,
            #"{"id":"","model":"mistral","started_at":"2024-06-01T02:00:00Z","input_tokens":5,"output_tokens":5,"total_tokens":10}"#,
            "this is not json",
        ].joined(separator: "\n")
        try Self.write(lines, to: root.appending(path: "usage/2024-06.jsonl"))

        let records = CapturedUsageReaders.records(client: "hindsight", roots: [root])
        #expect(records.count == 1)

        let record = try #require(records.first)
        #expect(record.model == "llama-3.3-70b")
        #expect(record.tally == TokenTally(input: 100, cacheRead: 5, output: 20))
        #expect(record.sessionID == "tr1")
        #expect(record.deduplicationID == "hindsight:h1")
        #expect(record.project == "bank-a")
        #expect(record.title == "chat / bank-a")
    }

    // MARK: - Mcode

    @Test("Mcode keeps independent messages, merges only the same message id, and never invents a split")
    func mcode() throws {
        let root = try Self.temporary("mcode")
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = [
            // A BOM on the first line must not lose the whole capture.
            "\u{FEFF}" + #"{"type":"message","message":{"id":"msg-a","turnId":"turn-1","role":"assistant","timestamp":1717200000,"usage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":30,"cacheWriteTokens":40,"totalTokens":190}}}"#,
            // The same id restated: one message, not two.
            #"{"type":"message","message":{"id":"msg-a","turnId":"turn-1","role":"assistant","timestamp":1717200000,"usage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":30,"cacheWriteTokens":40,"totalTokens":190}}}"#,
            // No id: two independent messages with equal values are both kept.
            #"{"type":"message","message":{"turnId":"turn-6","role":"assistant","timestamp":1717200300,"usage":{"inputTokens":10,"outputTokens":1}}}"#,
            #"{"type":"message","message":{"turnId":"turn-6","role":"assistant","timestamp":1717200300,"usage":{"inputTokens":10,"outputTokens":1}}}"#,
            // No id, second larger: still two independent messages.
            #"{"type":"message","message":{"turnId":"turn-7","role":"assistant","timestamp":1717200600,"usage":{"inputTokens":10,"outputTokens":1}}}"#,
            #"{"type":"message","message":{"turnId":"turn-7","role":"assistant","timestamp":1717200600,"usage":{"inputTokens":30,"outputTokens":2}}}"#,
            // The same id accumulated: the later restatement replaces it.
            #"{"type":"message","message":{"id":"msg-b","turnId":"turn-8","role":"assistant","timestamp":1717200900,"usage":{"inputTokens":10,"outputTokens":1}}}"#,
            #"{"type":"message","message":{"id":"msg-b","turnId":"turn-8","role":"assistant","timestamp":1717200900,"usage":{"inputTokens":30,"outputTokens":2}}}"#,
            // A stated total with no split stays unclassified.
            #"{"type":"message","message":{"turnId":"turn-2","role":"assistant","timestamp":"1717200060000","usage":{"totalTokens":55}}}"#,
            // No model-bearing result: unusable and dropped.
            #"{"type":"message","message":{"turnId":"turn-5","role":"assistant","timestamp":1717200240,"usage":{"inputTokens":9,"outputTokens":9}}}"#,
            #"{"type":"exec.result","sessionId":"sess-1","turnId":"turn-1","status":"ok","model":{"providerId":"minimax","modelId":"claude-sonnet-4-5","variant":"default"}}"#,
            #"{"type":"exec.result","sessionId":"sess-1","turnId":"turn-6","status":"ok","model":{"providerId":"minimax","modelId":"gpt-5.4"}}"#,
            #"{"type":"exec.result","sessionId":"sess-1","turnId":"turn-7","status":"ok","model":{"providerId":"minimax","modelId":"gpt-5.4"}}"#,
            #"{"type":"exec.result","sessionId":"sess-1","turnId":"turn-8","status":"ok","model":{"providerId":"minimax","modelId":"claude-sonnet-4-5"}}"#,
            #"{"type":"exec.result","sessionId":"sess-1","turnId":"turn-2","status":"ok","model":{"providerId":"minimax","modelId":"mystery"}}"#,
            #"{"type":"exec.result","sessionId":"sess-1","turnId":"turn-3","status":"ok","model":{"providerId":"","modelId":"gpt-5.4"}}"#,
        ].joined(separator: "\n")
        try Self.write(lines, to: root.appending(path: "headless/mcode/capture.jsonl"))

        let records = CapturedUsageReaders.records(client: "mcode", roots: [root])
        // turn-1 (1, one id), turn-6 (2), turn-7 (2), turn-8 (1), turn-2 (1).
        #expect(records.count == 7)

        func turn(_ id: String) -> [AgentUsageRecord] {
            records.filter { $0.deduplicationID?.hasPrefix("mcode:sess-1:\(id):") == true }
        }

        let one = try #require(turn("turn-1").first)
        #expect(one.model == "claude-sonnet-4-5")
        #expect(one.tally == TokenTally(input: 100, cacheWrite: 40, cacheRead: 30, output: 20))
        #expect(one.sessionID == "sess-1")

        // Two independent no-id messages with identical counts are both kept.
        #expect(turn("turn-6").count == 2)
        #expect(turn("turn-6").allSatisfy { $0.tally == TokenTally(input: 10, output: 1) })

        // Two independent no-id messages, the second larger, are both kept.
        #expect(turn("turn-7").count == 2)
        #expect(turn("turn-7").contains { $0.tally == TokenTally(input: 10, output: 1) })
        #expect(turn("turn-7").contains { $0.tally == TokenTally(input: 30, output: 2) })

        // The same id accumulated is one message, not two.
        let accumulated = turn("turn-8")
        #expect(accumulated.count == 1)
        #expect(accumulated.first?.tally == TokenTally(input: 30, output: 2))

        // A stated total without a split is counted as unclassified, never as
        // fresh input.
        let totalOnly = try #require(records.first { $0.model == "mystery" })
        #expect(totalOnly.tally == TokenTally())
        #expect(totalOnly.unclassifiedTokens == 55)
    }

    // MARK: - Through the production chain

    @Test("Imported records price through SpendSummary and ModelSpendSummary, nil where unpriced")
    func productionChain() throws {
        let cursorRoot = try Self.temporary("chain-cursor")
        let antigravityRoot = try Self.temporary("chain-antigravity")
        defer {
            try? FileManager.default.removeItem(at: cursorRoot)
            try? FileManager.default.removeItem(at: antigravityRoot)
        }

        let cursorJSON = #"""
        {"usageEventsDisplay":[
          {"conversationId":"c1","timestamp":1717200000000,"model":"gpt-5.4",
           "tokenUsage":{"inputTokens":1000,"outputTokens":100,"cacheReadTokens":200,"cacheWriteTokens":300}},
          {"conversationId":"c2","timestamp":1717200000000,"model":"mystery",
           "tokenUsage":{"inputTokens":500}}
        ]}
        """#
        try Self.write(cursorJSON, to: cursorRoot.appending(path: "usage.json"))

        let antigravityLines = [
            #"{"type":"session_meta","sessionId":"a1","modelId":"claude-sonnet-4-5"}"#,
            #"{"type":"usage","sessionId":"a1","timestamp":1717200000000,"input":200,"output":50,"responseId":"r1"}"#,
        ].joined(separator: "\n")
        try Self.write(antigravityLines, to: antigravityRoot.appending(path: "sessions/a.jsonl"))

        let cursor = Self.importedLedger(
            CapturedUsageReaders.records(client: "cursor", roots: [cursorRoot]), namespace: "cursor"
        )
        let antigravity = Self.importedLedger(
            CapturedUsageReaders.records(client: "antigravity", roots: [antigravityRoot]),
            namespace: "antigravity"
        )

        // The two keys only group the ledgers; the origin is what admits them.
        let ledgers: [SpendAgent: UsageLedger] = [.openCode: cursor, .grok: antigravity]

        let summary = SpendSummary.of(ledgers, overLast: nil, now: Date(), calendar: Self.calendar)
        // cursor: 1000+100+200+300 + 500 = 2100; antigravity: 250.
        #expect(summary.tokens == 2_350)
        #expect(summary.cost > 0)
        // The mystery model is counted but never priced.
        #expect(summary.unpricedTokens == 500)
        #expect(!summary.hasPartialCounts)

        let gpt = ModelSpendSummary.of(
            ledgers, named: "GPT-5.4", overLast: nil, now: Date(), calendar: Self.calendar
        )
        #expect(gpt.tokens == 1_600)
        // 1000*1 + 300*4 + 200*3 + 100*2, per million.
        #expect(abs((gpt.cost ?? -1) - (1000 + 1200 + 600 + 200) / 1_000_000) < 1e-12)
        #expect(gpt.unpricedTokens == 0)

        let mystery = ModelSpendSummary.of(
            ledgers, named: "mystery", overLast: nil, now: Date(), calendar: Self.calendar
        )
        #expect(mystery.tokens == 500)
        #expect(mystery.cost == nil)
        #expect(mystery.unpricedTokens == 500)

        let claude = ModelSpendSummary.of(
            ledgers, named: "Claude Sonnet 4.5", overLast: nil, now: Date(), calendar: Self.calendar
        )
        #expect(claude.tokens == 250)
        #expect(abs((claude.cost ?? -1) - (200 * 5 + 50 * 6) / 1_000_000) < 1e-12)
    }

    @Test("An aggregate CSV export is placed on its reported day and withholds an hour profile")
    func aggregateTiming() throws {
        let root = try Self.temporary("aggregate")
        defer { try? FileManager.default.removeItem(at: root) }

        let csv = "Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost\n"
            + "2024-06-02,chat,gpt-5.4,false,0,1000,0,0,1000,0\n"
        try Self.write(csv, to: root.appending(path: "usage.csv"))

        let records = CapturedUsageReaders.records(client: "cursor", roots: [root])
        #expect(records.count == 1)
        let csvRecord = try #require(records.first)
        #expect(csvRecord.isAggregate)
        // A report row names no session, so none is invented.
        #expect(csvRecord.sessionID == nil)

        let ledger = Self.importedLedger(records, namespace: "cursor")
        #expect(ledger.origin == .importedRecords)
        #expect(!ledger.hasPartialCounts)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "GPT-5.4", overLast: nil, now: Date(), calendar: Self.calendar
        )
        #expect(model.tokens == 1_000)
        // The report states a day, not a quarter-hour, so no hour series is
        // drawn from it.
        #expect(model.hours == nil)
    }
}
