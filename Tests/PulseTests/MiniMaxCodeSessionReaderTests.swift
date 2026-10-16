import Foundation
import Testing
@testable import Pulse

/// MiniMax Code's own session log (`MiniMaxCodeSessionReader`), read through
/// the `mcode` client (issue #86). Lines mirror TokenTracker's fixture, which
/// mirrors a real record: no `type` wrapper, `message_id` at the top, a
/// Pi-shaped `usage` under `message`, and a millisecond timestamp.
@Suite("MiniMax Code session log")
struct MiniMaxCodeSessionReaderTests {
    private static func home() throws -> URL {
        let home = URL.temporaryDirectory.appending(path: "PulseMiniMaxCode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private static func assistant(
        _ id: String, model: String = "MiniMax-M2.7", input: Int, output: Int,
        cacheRead: Int = 0, cacheWrite: Int = 0, total: Int? = nil, at milliseconds: Int
    ) -> String {
        let total = total ?? input + output + cacheRead + cacheWrite
        return #"{"message_id":"\#(id)","turn_id":"turn-\#(id)","message":{"role":"assistant","model":"\#(model)","provider":"minimax","timestamp":\#(milliseconds),"usage":{"input":\#(input),"output":\#(output),"cacheRead":\#(cacheRead),"cacheWrite":\#(cacheWrite),"totalTokens":\#(total),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}}}}"#
    }

    private static func user(_ id: String, at milliseconds: Int) -> String {
        #"{"message_id":"\#(id)","turn_id":"turn-\#(id)","message":{"role":"user","timestamp":\#(milliseconds)}}"#
    }

    @discardableResult
    private static func session(_ home: URL, day: String, name: String, lines: [String]) throws -> URL {
        let folder = MiniMaxCodeSessionReader.root(home: home).appending(path: "\(day)/\(name)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "messages.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func ledger(home: URL) -> (UsageLedger, [AgentUsageRecord]) {
        let roots = CapturedUsageReaders.inputs(client: "mcode", home: home, environment: [:])
        let read = AgentRecordReaders.read(client: "mcode", roots: roots)
        let ledger = AgentUsageLedger.build(read.records, prices: [:], namespace: "mcode")
        return (ledger, read.records)
    }

    private static let t1 = 1_789_999_500_000  // 2026-09-21, a millisecond time

    @Test("Assistant lines are counted with their own model; user, zero-usage and unreadable lines are not")
    func counts() throws {
        let home = try Self.home()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = try Self.session(home, day: "2026/09/20", name: "14-05-00-000-session_ABC", lines: [
            Self.user("u-1", at: Self.t1 - 1000),
            Self.assistant("m-1", input: 132_719, output: 16692, cacheRead: 439_298, total: 588_709, at: Self.t1),
            Self.assistant("m-2", input: 100, output: 20, cacheRead: 300, cacheWrite: 7, at: Self.t1 + 60000),
            Self.assistant("m-3", model: "kimi-for-coding", input: 10, output: 5, at: Self.t1 + 1_800_000),
            // Migrated history: all zero, no message.
            Self.assistant("legacy-1", model: "historical-transcript", input: 0, output: 0, at: Self.t1),
            "not json",
        ])
        // A subagent's readable transcript beside it is not a usage record.
        try Self.assistant("x", input: 999, output: 999, at: Self.t1)
            .write(to: file.deletingLastPathComponent().appending(path: "task-1.readable.v1.jsonl"),
                   atomically: true, encoding: .utf8)

        let (ledger, records) = Self.ledger(home: home)
        #expect(records.count == 3)
        #expect(Set(records.map(\.model)) == ["MiniMax-M2.7", "kimi-for-coding"])
        let m1 = try #require(records.first { $0.deduplicationID == "mcode:message:m-1" })
        #expect(m1.tally == TokenTally(input: 132_719, cacheRead: 439_298, output: 16692))
        #expect(m1.timestamp == Date(timeIntervalSince1970: Double(Self.t1) / 1000))
        #expect(m1.sessionID == "14-05-00-000-session_ABC")
        #expect(ledger.allTime.tokens == 588_709 + 427 + 15)
    }

    @Test("A message copied into a second session is counted once")
    func dedupes() throws {
        let home = try Self.home()
        defer { try? FileManager.default.removeItem(at: home) }
        let line = Self.assistant("dup-1", input: 50, output: 5, cacheRead: 45, at: Self.t1)
        try Self.session(home, day: "2026/09/21", name: "09-10-00-000-session_ONE", lines: [line])
        try Self.session(home, day: "2026/09/21", name: "09-20-00-000-session_TWO", lines: [line])
        #expect(Self.ledger(home: home).0.allTime.tokens == 100)
    }

    @Test("With its own log present, captures are not read; without it, they are, and the origin says which")
    func ownLogFirst() throws {
        let home = try Self.home()
        defer { try? FileManager.default.removeItem(at: home) }
        let roots = CapturedUsageReaders.inputs(client: "mcode", home: home, environment: [:])
        #expect(!CapturedUsageReaders.readsOwnLog(client: "mcode", roots: roots))

        try Self.session(home, day: "2026/09/22", name: "03-00-00-000-session_APP", lines: [
            Self.assistant("a-1", input: 1000, output: 100, at: Self.t1),
        ])
        #expect(CapturedUsageReaders.readsOwnLog(client: "mcode", roots: roots))
        #expect(!CapturedUsageReaders.readsOwnLog(client: "cursor", roots: roots))
        #expect(Self.ledger(home: home).0.allTime.tokens == 1100)
    }

    @Test("A log with files but no records reads the captures, and the read says so")
    func emptyLogIsNotOwnLog() throws {
        let home = try Self.home()
        defer { try? FileManager.default.removeItem(at: home) }
        // Only a zeroed migration line: files, no records.
        try Self.session(home, day: "2026/09/22", name: "03-00-00-000-session_OLD", lines: [
            Self.assistant("legacy-1", model: "historical-transcript", input: 0, output: 0, at: Self.t1),
        ])
        let capture = home.appending(path: ".config/tokscale/headless/mcode/capture.jsonl")
        try FileManager.default.createDirectory(at: capture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try [
            #"{"type":"message","message":{"id":"m-1","turnId":"turn-1","role":"assistant","timestamp":1717200000,"usage":{"inputTokens":100,"outputTokens":20}}}"#,
            #"{"type":"exec.result","sessionId":"sess-1","turnId":"turn-1","status":"ok","model":{"providerId":"minimax","modelId":"MiniMax-M2.7"}}"#,
        ].joined(separator: "\n").write(to: capture, atomically: true, encoding: .utf8)

        let roots = CapturedUsageReaders.inputs(client: "mcode", home: home, environment: [:])
        let read = AgentRecordReaders.read(client: "mcode", roots: roots)
        #expect(!read.records.isEmpty)
        // The captures were read, so this is not the Mac's own log.
        #expect(!read.readsOwnLog)
        #expect(!CapturedUsageReaders.readsOwnLog(client: "mcode", roots: roots))
    }

    @Test("MiniMax's card and pane take their history from MiniMax Code")
    func history() {
        #expect(SpendAgent.mcode.iconProvider == .minimax)
        #expect(Provider.minimax.cardHistory(openCodeSession: false, deepSeekSession: false) == .agents([.mcode]))
    }
}
