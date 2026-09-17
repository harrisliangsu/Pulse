import Foundation
import SQLite3
import Testing
@testable import Pulse

/// One session saved in two shapes must not become two agents' consumption.
/// Synthetic stores pass through AgentLedgers' real production dispatch.
@Suite("Devin spend reconciliation")
struct DevinSpendReconciliationTests {
    private static let at = Date(timeIntervalSince1970: 1_789_560_000)
    private static let prices = [
        "priced": ModelPrice(input: 1, output: 1, cacheRead: 1, cacheWrite: nil, name: "Priced")
    ]

    private func fixture(input: Int = 100, dated: Bool = true) throws -> URL {
        let home = URL.temporaryDirectory.appending(path: "PulseDevinSpend-\(UUID().uuidString)")
        let database = home.appending(path: ".local/share/devin/cli/sessions.db")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        try #require(sqlite3_open(database.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let message = """
        {"role":"assistant","metadata":{"generation_model":"priced","metrics":{"input_tokens":\(input),"output_tokens":0}}}
        """
        for sql in [
            "CREATE TABLE sessions (id TEXT, title TEXT, model TEXT, working_directory TEXT)",
            "CREATE TABLE message_nodes (session_id TEXT, chat_message TEXT, created_at INTEGER)",
            "INSERT INTO sessions VALUES ('shared','Shared task','priced','/work/review')",
            "INSERT INTO message_nodes VALUES ('shared','\(message)',\(dated ? Int(Self.at.timeIntervalSince1970) : 0))",
        ] {
            try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        return home
    }

    private func capture(home: URL, name: String, title: String, legacy: Bool = false) throws {
        let events = home.appending(path: "Library/Application Support/Devin/User/acp-events")
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
        var usage: [String: Any] = ["sessionUpdate": "usage_update", "created_at": Self.at.timeIntervalSince1970]
        if legacy {
            usage["metadata"] = ["generation_model": "priced", "metrics": ["input_tokens": 100]]
        } else {
            usage["_meta"] = ["cognition.ai/inputTokens": 100, "cognition.ai/model": "priced"]
        }
        let rows: [[String: Any]] = [
            ["notification": ["sessionUpdate": "session_info_update", "title": title]],
            ["notification": usage],
        ]
        let text = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        try text.joined(separator: "\n").write(to: events.appending(path: "\(name).ndjson"), atomically: true, encoding: .utf8)
    }

    private func read(_ agent: SpendAgent, home: URL) -> UsageLedger {
        AgentLedgers.read(agent, prices: Self.prices, home: home, environment: [:]).ledger
    }

    @Test("Native usage owns the same session's canonical and legacy captures")
    func mirroredSessionCountsOnce() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        try capture(home: home, name: "canonical", title: "Shared task")
        try capture(home: home, name: "legacy", title: "Shared task", legacy: true)
        let native = read(.devinCLI, home: home)
        let desktop = read(.devinDesktop, home: home)
        #expect(desktop.days.isEmpty)
        let ledgers: [SpendAgent: UsageLedger] = [.devinCLI: native, .devinDesktop: desktop]
        let summary = SpendSummary.of(ledgers, overLast: 1, now: Self.at)
        #expect(summary.tokens == 100)
        #expect(summary.sessions.count == 1)
        #expect(abs(summary.cost - 0.0001) < 1e-12)
        let model = ModelSpendSummary.of(ledgers, named: "Priced", overLast: 1, now: Self.at)
        #expect(model.tokens == 100)
        #expect(model.agents.map(\.agent) == [.devinCLI])

        // Reading a capture independently, or using a database only for
        // metadata, has no counted native source to take precedence over it.
        let roots = SpendAgent.devinDesktop.stores(home: home, environment: [:])
        #expect(DevinDesktopReader.records(roots: roots).count == 2)
    }

    @Test("An empty or undated native message cannot suppress its capture", arguments: [true, false])
    func noUsableNativeUsage(dated: Bool) throws {
        let home = try fixture(input: dated ? 0 : 100, dated: dated)
        defer { try? FileManager.default.removeItem(at: home) }
        try capture(home: home, name: "canonical", title: "Shared task")
        #expect(read(.devinCLI, home: home).days.isEmpty)
        #expect(read(.devinDesktop, home: home).allTime.tokens == 100)
    }

    @Test("A capture not matched to a counted session remains separate work")
    func anotherSessionSurvives() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        try capture(home: home, name: "mirror", title: "Shared task")
        try capture(home: home, name: "other", title: "Another task")
        let native = read(.devinCLI, home: home)
        let desktop = read(.devinDesktop, home: home)
        #expect(desktop.allTime.tokens == 100)
        #expect(desktop.sessions.count == 1)
        let summary = SpendSummary.of([.devinCLI: native, .devinDesktop: desktop], overLast: 1, now: Self.at)
        #expect(summary.tokens == 200)
    }
}
