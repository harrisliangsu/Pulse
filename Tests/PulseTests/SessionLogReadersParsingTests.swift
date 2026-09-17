import Foundation
import SQLite3
import Testing
@testable import Pulse

/// The per-client parsers for the formats that are not Pi-shaped: Gemini's
/// three shapes, Qwen's chat lines, Amp's ledger/message reconciliation,
/// Droid's aggregate settings and OpenClaw's two stores.
///
/// Every store is hand-built under a private temporary root. The SQLite stores
/// are created with `SQLite3` directly and removed by the test that made them.
@Suite("Session log reader parsing")
struct SessionLogReadersParsingTests {
    private static let prices: [String: ModelPrice] = [
        "gpt-5": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "GPT-5"),
        "qwen3-coder": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "Qwen3 Coder")
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Store helpers

    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "PulseSessionReadersParse-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private static func makeDatabase(at url: URL, statements: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        for sql in statements {
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }
        sqlite3_close(handle)
    }

    private static func tokens(_ records: [AgentUsageRecord], namespace: String) -> Int {
        AgentUsageLedger.build(records, prices: prices, namespace: namespace, calendar: calendar)
            .days.reduce(0) { $0 + $1.tokens }
    }

    // MARK: - Gemini

    @Test("Gemini session JSON folds tool into input and strips cache only when the total proves it")
    func geminiSessionShape() throws {
        let home = try Self.temporary("gemini-session")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "gemini", home: home)
        let base = try #require(roots.first)

        try Self.write(
            """
            {"sessionId":"g-1","projectHash":"abc","startTime":"2026-01-02T03:00:00Z","lastUpdated":"2026-01-02T03:10:00Z","messages":[
              {"id":"g1","timestamp":"2026-01-02T03:04:05Z","type":"gemini","model":"gemini-2.5-pro","tokens":{"input":100,"output":20,"thoughts":5,"cached":30,"tool":10,"total":135}},
              {"id":"g2","timestamp":"2026-01-02T03:05:05Z","type":"gemini","model":"gemini-2.5-pro","tokens":{"input":100,"output":20,"thoughts":5,"cached":30,"tool":10}},
              {"id":"g3","timestamp":"2026-01-02T03:06:05Z","type":"user","tokens":{"input":999}}
            ]}
            """,
            to: base.appending(path: "abc/chats/chat.json")
        )

        let records = SessionLogReaders.records(client: "gemini", roots: roots)
        #expect(records.count == 2)
        let withTotal = try #require(records.first { $0.deduplicationID == "gemini:session:g-1:g1" })
        #expect(withTotal.tally == TokenTally(input: 80, cacheWrite: 0, cacheRead: 30, output: 25))
        let withoutTotal = try #require(records.first { $0.deduplicationID == "gemini:session:g-1:g2" })
        #expect(withoutTotal.tally == TokenTally(input: 110, cacheWrite: 0, cacheRead: 30, output: 25))
    }

    @Test("A Gemini bare total is unclassified, and legacy session files are accepted")
    func geminiLegacyAndBareTotal() throws {
        let home = try Self.temporary("gemini-legacy")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "gemini", home: home)
        let base = try #require(roots.first)

        try Self.write(
            """
            {"sessionId":"legacy","messages":[
              {"id":"l1","created_at":"2026-01-02T03:04:05Z","type":"gemini","model":"gemini-2.0-flash","tokens":{"totalTokenCount":500}}
            ]}
            """,
            to: base.appending(path: "session-old.json")
        )

        let record = try #require(SessionLogReaders.records(client: "gemini", roots: roots).first)
        #expect(record.tally == TokenTally())
        #expect(record.unclassifiedTokens == 500)
        #expect(record.sessionID == "legacy")
    }

    @Test("Gemini headless stats emit one record per model and replace a re-exported line id")
    func geminiHeadless() throws {
        let home = try Self.temporary("gemini-headless")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "gemini", home: home)
        let base = try #require(roots.first)

        try Self.write(
            """
            {"type":"init","model":"gemini-2.5-flash","session_id":"sess-h"}
            {"type":"gemini","id":"call-1","timestamp":"2026-01-02T03:04:05Z","tokens":{"input":10,"output":2}}
            {"type":"gemini","id":"call-1","timestamp":"2026-01-02T03:04:05Z","tokens":{"input":99,"output":2}}
            {"timestamp":"2026-01-02T03:05:05Z","result":{"stats":{"models":{"gemini-2.5-flash":{"prompt_tokens":100,"candidates_tokens":20,"thoughts_tokens":5,"cached_tokens":30},"gemini-2.5-pro":{"promptTokenCount":40,"candidatesTokenCount":8}}}}}
            """,
            to: base.appending(path: "headless.jsonl")
        )

        let records = SessionLogReaders.records(client: "gemini", roots: roots)
        #expect(records.count == 3)
        #expect(records.filter { $0.model == "gemini-2.5-flash" }.count == 2)
        let call = try #require(records.first { $0.deduplicationID == "gemini:line:call-1" })
        #expect(call.tally.input == 99)
        #expect(records.contains { $0.model == "gemini-2.5-pro" && $0.tally.input == 40 && $0.tally.output == 8 })
    }

    @Test("A Gemini prompt-style key is cache-inclusive even without a total; a net input is not")
    func geminiPromptStyleIsCacheInclusive() throws {
        let home = try Self.temporary("gemini-prompt")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "gemini", home: home)
        let base = try #require(roots.first)

        try Self.write(
            """
            {"sessionId":"gp","messages":[
              {"id":"p1","timestamp":"2026-01-02T03:04:05Z","type":"gemini","model":"gemini-2.5-pro","tokens":{"prompt":100,"output":10,"cached":40}},
              {"id":"p2","timestamp":"2026-01-02T03:05:05Z","type":"gemini","model":"gemini-2.5-pro","tokens":{"input":100,"output":10,"cached":40}}
            ]}
            """,
            to: base.appending(path: "session-prompt.json")
        )

        let records = SessionLogReaders.records(client: "gemini", roots: roots)
        let promptStyle = try #require(records.first { $0.deduplicationID == "gemini:session:gp:p1" })
        #expect(promptStyle.tally == TokenTally(input: 60, cacheWrite: 0, cacheRead: 40, output: 10))
        let net = try #require(records.first { $0.deduplicationID == "gemini:session:gp:p2" })
        #expect(net.tally == TokenTally(input: 100, cacheWrite: 0, cacheRead: 40, output: 10))
    }

    // MARK: - Qwen

    @Test("Qwen takes promptTokenCount as cache-inclusive and folds thoughts into output")
    func qwenMetadata() throws {
        let home = try Self.temporary("qwen")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "qwen", home: home)
        let root = try #require(roots.first)

        try Self.write(
            """
            {"type":"user","timestamp":"2026-01-02T03:00:00Z","sessionId":"q-1","usageMetadata":{"promptTokenCount":1}}
            {"type":"assistant","timestamp":"2026-01-02T03:04:05Z","sessionId":"q-1","model":"qwen3-coder","usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":20,"thoughtsTokenCount":5,"cachedContentTokenCount":30}}
            {"type":"assistant","model":"qwen3-coder","usageMetadata":{"promptTokenCount":7}}
            """,
            to: root.appending(path: "myproject/chats/session.jsonl")
        )

        let records = SessionLogReaders.records(client: "qwen", roots: roots)
        #expect(records.count == 1)
        let record = try #require(records.first)
        // prompt includes the cache read: 100 - 30 fresh, 30 read, 20 + 5 output.
        #expect(record.tally == TokenTally(input: 70, cacheWrite: 0, cacheRead: 30, output: 25))
        #expect(record.project == "myproject")
        #expect(record.sessionID == "q-1")
        #expect(record.deduplicationID?.hasPrefix("qwen:q-1:") == true)
    }

    @Test("A Qwen total that equals prompt+output proves the cache is inside the prompt")
    func qwenTotalProvesInclusion() throws {
        let home = try Self.temporary("qwen-included")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "qwen", home: home)
        let root = try #require(roots.first)

        // The double-count fixture: input 100 + cache 40 + output 10 would be
        // 150, but the reported total says 110, so the cache is inside input.
        try Self.write(
            #"{"type":"assistant","id":"m-1","timestamp":"2026-01-02T03:04:05Z","sessionId":"q-inc","model":"qwen3-coder","usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":10,"cachedContentTokenCount":40,"totalTokenCount":110}}"#,
            to: root.appending(path: "p/chats/a.jsonl")
        )

        let record = try #require(SessionLogReaders.records(client: "qwen", roots: roots).first)
        #expect(record.tally == TokenTally(input: 60, cacheWrite: 0, cacheRead: 40, output: 10))
        #expect(record.tally.total == 110)
    }

    @Test("A Qwen total that equals the disjoint sum proves the cache is beside the prompt")
    func qwenTotalProvesDisjoint() throws {
        let home = try Self.temporary("qwen-disjoint")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "qwen", home: home)
        let root = try #require(roots.first)

        try Self.write(
            #"{"type":"assistant","id":"m-2","timestamp":"2026-01-02T03:04:05Z","sessionId":"q-dis","model":"qwen3-coder","usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":10,"cachedContentTokenCount":40,"totalTokenCount":150}}"#,
            to: root.appending(path: "p/chats/b.jsonl")
        )

        let record = try #require(SessionLogReaders.records(client: "qwen", roots: roots).first)
        #expect(record.tally == TokenTally(input: 100, cacheWrite: 0, cacheRead: 40, output: 10))
    }

    @Test("A Qwen total that settles nothing becomes unclassified, never a guessed kind")
    func qwenTotalUnclear() throws {
        let home = try Self.temporary("qwen-unclear")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "qwen", home: home)
        let root = try #require(roots.first)

        try Self.write(
            #"{"type":"assistant","id":"m-3","timestamp":"2026-01-02T03:04:05Z","sessionId":"q-unk","model":"qwen3-coder","usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":10,"cachedContentTokenCount":40,"totalTokenCount":200}}"#,
            to: root.appending(path: "p/chats/c.jsonl")
        )

        let record = try #require(SessionLogReaders.records(client: "qwen", roots: roots).first)
        #expect(record.tally == TokenTally())
        #expect(record.unclassifiedTokens == 200)
    }

    @Test("Two Qwen fragments of one session keep their own records")
    func qwenFragmentsAreNotLost() throws {
        let home = try Self.temporary("qwen-fragments")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "qwen", home: home)
        let root = try #require(roots.first)

        // Same session, two files, each with a distinct message id.
        try Self.write(
            #"{"type":"assistant","id":"frag-a","timestamp":"2026-01-02T03:04:05Z","sessionId":"q-split","model":"qwen3-coder","usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":10}}"#,
            to: root.appending(path: "p/chats/a.jsonl")
        )
        try Self.write(
            #"{"type":"assistant","id":"frag-b","timestamp":"2026-01-02T03:05:05Z","sessionId":"q-split","model":"qwen3-coder","usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":5}}"#,
            to: root.appending(path: "p/chats/b.jsonl")
        )
        let withIDs = SessionLogReaders.records(client: "qwen", roots: roots)
        #expect(withIDs.count == 2)
        #expect(Set(withIDs.compactMap { $0.deduplicationID }).count == 2)
        #expect(Self.tokens(withIDs, namespace: "qwen") == 165)

        // No ids at all: two fragments must still not collide on index 0.
        let bareRoot = root.appending(path: "bare")
        try Self.write(
            #"{"type":"assistant","timestamp":"2026-01-02T03:04:05Z","sessionId":"q-bare","model":"qwen3-coder","usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":1}}"#,
            to: bareRoot.appending(path: "p/chats/c.jsonl")
        )
        try Self.write(
            #"{"type":"assistant","timestamp":"2026-01-02T03:05:05Z","sessionId":"q-bare","model":"qwen3-coder","usageMetadata":{"promptTokenCount":9,"candidatesTokenCount":2}}"#,
            to: bareRoot.appending(path: "p/chats/d.jsonl")
        )
        let withoutIDs = SessionLogReaders.records(client: "qwen", roots: [bareRoot])
        #expect(withoutIDs.count == 2)
        #expect(Self.tokens(withoutIDs, namespace: "qwen") == 19)
    }

    @Test("A byte-identical Qwen fragment mirror folds to one")
    func qwenMirrorFolds() throws {
        let home = try Self.temporary("qwen-mirror")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "qwen", home: home)
        let root = try #require(roots.first)

        let line = #"{"type":"assistant","timestamp":"2026-01-02T03:04:05Z","sessionId":"q-mirror","model":"qwen3-coder","usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":10}}"#
        try Self.write(line, to: root.appending(path: "one/p/chats/a.jsonl"))
        try Self.write(line, to: root.appending(path: "two/p/chats/a.jsonl"))

        let records = SessionLogReaders.records(client: "qwen", roots: roots)
        #expect(records.count == 2)
        #expect(records.first?.deduplicationID == records.last?.deduplicationID)
        #expect(Self.tokens(records, namespace: "qwen") == 110)
    }

    // MARK: - Amp

    @Test("Amp merges a matched message into its ledger event and dates the rest at the thread's report")
    func ampReconciliation() throws {
        let home = try Self.temporary("amp")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "amp", home: home)
        let root = try #require(roots.first)

        try Self.write(
            """
            {"id":"thread-9","created":1700000000000,"messages":[
              {"role":"assistant","messageId":7,"usage":{"model":"gpt-5","inputTokens":100,"outputTokens":10,"cacheReadInputTokens":0,"cacheCreationInputTokens":0,"credits":1.5}},
              {"role":"assistant","messageId":8,"usage":{"model":"gpt-5","inputTokens":50,"outputTokens":5,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}}
            ],"usageLedger":{"events":[
              {"timestamp":"2026-01-02T03:04:05Z","model":"gpt-5","credits":1.5,"tokens":{"input":100,"output":10,"cacheReadInputTokens":0,"cacheCreationInputTokens":0},"operationType":"chat","fromMessageId":6,"toMessageId":7}
            ]}}
            """,
            to: root.appending(path: "T-9.json")
        )

        let records = SessionLogReaders.records(client: "amp", roots: roots)
        #expect(records.count == 2)
        #expect(records.contains { $0.tally == TokenTally(input: 100, cacheWrite: 0, cacheRead: 0, output: 10) })
        let appended = try #require(records.first { $0.deduplicationID == "amp:thread-9:message:8" })
        #expect(appended.tally == TokenTally(input: 50, cacheWrite: 0, cacheRead: 0, output: 5))
        // The thread's own report time, marked aggregate — not created + id.
        #expect(abs(appended.timestamp.timeIntervalSince1970 - 1_700_000_000) < 0.001)
        #expect(appended.isAggregate)
    }

    @Test("Amp never derives seconds from a message id and drops calls with no real time")
    func ampMissingTimestampIsNotInvented() throws {
        let home = try Self.temporary("amp-missing")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "amp", home: home)
        let root = try #require(roots.first)

        // A thread with only its own report time: the message lands on it as an
        // aggregate, never at created + messageId.
        try Self.write(
            #"{"id":"t-created","created":1700000000000,"messages":[{"role":"assistant","messageId":42,"usage":{"model":"gpt-5","inputTokens":10,"outputTokens":1}}],"usageLedger":{"events":[]}}"#,
            to: root.appending(path: "T-created.json")
        )
        // A thread with neither a report time nor an event stamp has nothing.
        try Self.write(
            #"{"id":"t-none","messages":[{"role":"assistant","messageId":5,"usage":{"model":"gpt-5","inputTokens":10,"outputTokens":1}}],"usageLedger":{"events":[]}}"#,
            to: root.appending(path: "T-none.json")
        )

        let records = SessionLogReaders.records(client: "amp", roots: roots)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(abs(record.timestamp.timeIntervalSince1970 - 1_700_000_000) < 0.001)
        #expect(record.isAggregate)
        // The undatable thread's usage is not silently dropped: the readable
        // sibling is flagged as a partial batch.
        #expect(record.isPartial)
        #expect(record.deduplicationID == "amp:t-created:message:42")
    }

    // MARK: - Droid

    @Test("Droid keeps only the reported output when a cache has no total, and says it is partial")
    func droidCacheWithoutTotalIsPartial() throws {
        let home = try Self.temporary("droid-partial")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "droid", home: home)
        let root = try #require(roots.first)

        // Both an Anthropic lock and an OpenAI lock: neither proves how the
        // stored camelCase inputTokens relates to the cache columns.
        try Self.write(
            #"{"model":"custom:claude-opus-4.5[1m]","providerLock":"anthropic","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheCreationTokens":5,"cacheReadTokens":7,"thinkingTokens":3}}"#,
            to: root.appending(path: "anthropic.settings.json")
        )
        try Self.write(
            #"{"model":"gpt-5.1","providerLock":"openai","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheCreationTokens":0,"cacheReadTokens":40,"thinkingTokens":0}}"#,
            to: root.appending(path: "openai.settings.json")
        )

        let records = SessionLogReaders.records(client: "droid", roots: roots)
        #expect(records.count == 2)
        for record in records {
            // No cache or input was priced as a kind, and no cost for them.
            #expect(record.tally.cacheRead == 0)
            #expect(record.tally.cacheWrite == 0)
            #expect(record.tally.input == 0)
            // The reported input is kept as a known quantity of unknown kind.
            #expect(record.unclassifiedTokens == 100)
            #expect(record.isPartial)
            #expect(record.isAggregate)
        }
        let anthropic = try #require(records.first { $0.sessionID == "anthropic" })
        #expect(anthropic.model == "claude-opus-4.5")
        #expect(anthropic.tally == TokenTally(output: 20))
    }

    @Test("Droid marks a record partial when its thinking could be independent of output")
    func droidThinkingWithoutCacheIsPartial() throws {
        let home = try Self.temporary("droid-thinking")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "droid", home: home)
        let root = try #require(roots.first)

        try Self.write(
            #"{"model":"m","providerLock":"anthropic","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheCreationTokens":0,"cacheReadTokens":0,"thinkingTokens":3}}"#,
            to: root.appending(path: "thinking.settings.json")
        )
        try Self.write(
            #"{"model":"m","providerLock":"anthropic","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheCreationTokens":0,"cacheReadTokens":0,"thinkingTokens":0}}"#,
            to: root.appending(path: "plain.settings.json")
        )

        let records = SessionLogReaders.records(client: "droid", roots: roots)
        let thinking = try #require(records.first { $0.sessionID == "thinking" })
        #expect(thinking.tally == TokenTally(input: 100, output: 20))
        #expect(thinking.isPartial)
        let plain = try #require(records.first { $0.sessionID == "plain" })
        #expect(plain.tally == TokenTally(input: 100, output: 20))
        #expect(!plain.isPartial)
    }

    @Test("A Droid total settles inclusion, disjointness, and the unresolvable case")
    func droidTotalReconciliation() throws {
        let home = try Self.temporary("droid-total")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "droid", home: home)
        let root = try #require(roots.first)

        // Total == input + output: the cache is inside input.
        try Self.write(
            #"{"model":"m","providerLock":"openai","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":40,"totalTokens":120}}"#,
            to: root.appending(path: "included.settings.json")
        )
        // Total == input + cache + output: disjoint.
        try Self.write(
            #"{"model":"m","providerLock":"openai","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":40,"totalTokens":160}}"#,
            to: root.appending(path: "disjoint.settings.json")
        )
        // No identity holds: the total is complete, only its kinds are unknown.
        try Self.write(
            #"{"model":"m","providerLock":"openai","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":40,"totalTokens":999}}"#,
            to: root.appending(path: "unclear.settings.json")
        )

        let records = SessionLogReaders.records(client: "droid", roots: roots)
        let included = try #require(records.first { $0.sessionID == "included" })
        #expect(included.tally == TokenTally(input: 60, cacheWrite: 0, cacheRead: 40, output: 20))
        #expect(!included.isPartial)
        let disjoint = try #require(records.first { $0.sessionID == "disjoint" })
        #expect(disjoint.tally == TokenTally(input: 100, cacheWrite: 0, cacheRead: 40, output: 20))
        #expect(!disjoint.isPartial)
        let unclear = try #require(records.first { $0.sessionID == "unclear" })
        #expect(unclear.tally == TokenTally())
        #expect(unclear.unclassifiedTokens == 999)
        #expect(!unclear.isPartial)
    }

    @Test("Droid marks the readable siblings partial when a session's usage has no time")
    func droidUnreadableSessionMarksSiblingsPartial() throws {
        let home = try Self.temporary("droid-sibling")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "droid", home: home)
        let root = try #require(roots.first)

        try Self.write(
            #"{"model":"m","providerLock":"anthropic","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":10,"outputTokens":1,"cacheCreationTokens":0,"cacheReadTokens":0,"thinkingTokens":0}}"#,
            to: root.appending(path: "readable.settings.json")
        )
        // Real usage, but no locatable time: recognized, not countable.
        try Self.write(
            #"{"model":"m","providerLock":"anthropic","tokenUsage":{"inputTokens":99,"outputTokens":9,"cacheCreationTokens":0,"cacheReadTokens":0,"thinkingTokens":0}}"#,
            to: root.appending(path: "undated.settings.json")
        )

        let records = SessionLogReaders.records(client: "droid", roots: roots)
        #expect(records.count == 1)
        let readable = try #require(records.first)
        #expect(readable.sessionID == "readable")
        #expect(readable.isPartial)
    }

    @Test("Droid falls back to the transcript's model and then a valueless provider placeholder")
    func droidModelFallbacks() throws {
        let home = try Self.temporary("droid-fallback")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "droid", home: home)
        let root = try #require(roots.first)

        try Self.write(
            #"{"model":"","providerLock":"openai","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":10,"outputTokens":1,"cacheCreationTokens":0,"cacheReadTokens":0,"thinkingTokens":0}}"#,
            to: root.appending(path: "with-transcript.settings.json")
        )
        try Self.write(
            #"{"type":"message","message":{"role":"assistant"},"timestamp":"2026-01-02T03:04:00Z","content":"<system-reminder>Model: gpt-5.1-codex</system-reminder>"}"#,
            to: root.appending(path: "with-transcript.jsonl")
        )
        try Self.write(
            #"{"providerLock":"anthropic","providerLockTimestamp":"2026-01-02T03:04:05Z","tokenUsage":{"inputTokens":10,"outputTokens":1,"cacheCreationTokens":0,"cacheReadTokens":0,"thinkingTokens":0}}"#,
            to: root.appending(path: "defaulted.settings.json")
        )

        let records = SessionLogReaders.records(client: "droid", roots: roots)
        #expect(records.contains { $0.sessionID == "with-transcript" && $0.model == "gpt-5.1-codex" })
        #expect(records.contains { $0.sessionID == "defaulted" && $0.model == "claude-unknown" })
        #expect(records.allSatisfy { !$0.isPartial })
    }

    // MARK: - OpenClaw

    @Test("OpenClaw reads the SQLite store, its session metadata and carried model changes")
    func openClawSQLite() throws {
        let home = try Self.temporary("openclaw-sqlite")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "openclaw", home: home)
        let database = home.appending(path: ".openclaw/agents/ag1/agent/openclaw-agent.sqlite")

        try Self.makeDatabase(at: database, statements: [
            "CREATE TABLE session_windows (session_id TEXT PRIMARY KEY, session_key TEXT, previous_session_id TEXT, created_at INTEGER, updated_at INTEGER, model_provider TEXT, model TEXT, agent_harness_id TEXT)",
            "CREATE TABLE transcript_events (session_id TEXT, seq INTEGER, event_json TEXT, created_at INTEGER, PRIMARY KEY (session_id, seq))",
            "INSERT INTO session_windows VALUES ('s1','k1',NULL,1700000000000,1700000000000,'openai','gpt-5','h1')",
            #"INSERT INTO transcript_events VALUES ('s1',1,'{"type":"message","id":"e1","message":{"role":"assistant","timestamp":1700000000000,"usage":{"input":100,"output":50,"cacheRead":0,"cacheWrite":0,"totalTokens":150,"reasoningTokens":20}}}',1700000000000)"#,
            #"INSERT INTO transcript_events VALUES ('s1',2,'{"type":"message","api":"openclaw-transcript","id":"e2","message":{"role":"assistant","timestamp":1700000001000,"usage":{"input":9999,"output":9999}}}',1700000001000)"#,
            #"INSERT INTO transcript_events VALUES ('s1',3,'{"type":"model_change","id":"e3","modelId":"helper","provider":"openai"}',1700000002000)"#,
            #"INSERT INTO transcript_events VALUES ('s1',4,'{"type":"message","id":"e4","message":{"role":"assistant","timestamp":1700000003000,"usage":{"input":10,"output":1}}}',1700000003000)"#
        ])

        let records = SessionLogReaders.records(client: "openclaw", roots: roots)
        #expect(records.count == 2)
        let first = try #require(records.first { $0.deduplicationID?.hasPrefix("openclaw:e1:") == true })
        #expect(first.model == "gpt-5")
        // reasoning is a subset of output, not an extra bucket.
        #expect(first.tally == TokenTally(input: 100, cacheWrite: 0, cacheRead: 0, output: 50))
        let carried = try #require(records.first { $0.deduplicationID?.hasPrefix("openclaw:e4:") == true })
        #expect(carried.model == "helper")
        #expect(carried.sessionID == "s1")
    }

    @Test("The same OpenClaw event in SQLite and a legacy JSONL folds to one")
    func openClawCrossStoreDedup() throws {
        let home = try Self.temporary("openclaw-fold")
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = SessionLogReaders.inputs(client: "openclaw", home: home)
        let database = home.appending(path: ".openclaw/agents/ag1/agent/openclaw-agent.sqlite")

        try Self.makeDatabase(at: database, statements: [
            "CREATE TABLE transcript_events (session_id TEXT, seq INTEGER, event_json TEXT, created_at INTEGER, PRIMARY KEY (session_id, seq))",
            #"INSERT INTO transcript_events VALUES ('s1',1,'{"type":"message","id":"evt-1","message":{"role":"assistant","model":"gpt-5","timestamp":1700000000000,"usage":{"input":10,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":11}}}',1700000000000)"#
        ])
        try Self.write(
            #"{"type":"message","id":"evt-1","message":{"role":"assistant","model":"gpt-5","timestamp":1700000000000,"usage":{"input":10,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":11}}}"#,
            to: home.appending(path: ".openclaw/agents/ag1/sessions/legacy.jsonl")
        )

        let records = SessionLogReaders.records(client: "openclaw", roots: roots)
        #expect(records.count == 2)
        #expect(records.first?.deduplicationID == records.last?.deduplicationID)
        #expect(Self.tokens(records, namespace: "openclaw") == 11)
    }
}
