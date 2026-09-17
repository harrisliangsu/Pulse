import Foundation
import Testing
@testable import Pulse

/// Cherry appends one call several times while it streams; identity folds the
/// copies by field-wise maximum, and the V2 tree wins a session present in both.
@Suite("Cherry Studio reader")
struct CherryStudioReaderTests {
    private static func assistant(
        _ requestID: String?, uuid: String?, input: Int, output: Int,
        cacheRead: Int, cacheWrite: Int, at: Date
    ) -> [String: Any] {
        var line: [String: Any] = [
            "type": "assistant",
            "sessionId": "session-a",
            "timestamp": EditorTestSupport.iso(at),
            "message": [
                "model": "claude-sonnet",
                "usage": [
                    "input_tokens": input, "output_tokens": output,
                    "cache_read_input_tokens": cacheRead, "cache_creation_input_tokens": cacheWrite,
                ],
            ],
        ]
        if let requestID { line["requestId"] = requestID }
        if let uuid { line["uuid"] = uuid }
        return line
    }

    @Test("Streaming snapshots fold to one call per identity, merged by maximum")
    func streamingSnapshotsMerge() throws {
        let home = try EditorTestSupport.temporary("cherry")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appending(
            path: "Library/Application Support/CherryStudio/Data/Agents/.claude/projects"
        )
        let file = root.appending(path: "pulse/session-a.jsonl")

        try EditorTestSupport.jsonLines([
            Self.assistant("req-1", uuid: "u1", input: 10, output: 1,
                           cacheRead: 0, cacheWrite: 0, at: EditorTestSupport.at(hour: 9)),
            Self.assistant("req-1", uuid: "u2", input: 100, output: 5,
                           cacheRead: 30, cacheWrite: 20, at: EditorTestSupport.at(hour: 9)),
            Self.assistant("req-1", uuid: "u3", input: 100, output: 40,
                           cacheRead: 30, cacheWrite: 20, at: EditorTestSupport.at(hour: 9)),
            // A distinct call that happens to share the final counts.
            Self.assistant("req-2", uuid: "u4", input: 100, output: 40,
                           cacheRead: 30, cacheWrite: 20, at: EditorTestSupport.at(hour: 10)),
            // No identity at all: kept on its own.
            Self.assistant(nil, uuid: nil, input: 5, output: 6,
                           cacheRead: 0, cacheWrite: 0, at: EditorTestSupport.at(hour: 11)),
            // Not an assistant message.
            ["type": "user", "message": ["usage": ["input_tokens": 999]]],
        ], to: file)

        let roots = EditorLogReaders.inputs(client: "cherrystudio", home: home)
        let records = EditorLogReaders.records(client: "cherrystudio", roots: roots)
        #expect(records.count == 3)

        let first = try #require(records.first { $0.deduplicationID?.contains("req-1") == true })
        #expect(first.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(first.timestamp == EditorTestSupport.at(hour: 9))
        #expect(first.sessionID == "session-a")
        #expect(first.project == "pulse")

        let second = try #require(records.first { $0.deduplicationID?.contains("req-2") == true })
        #expect(second.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40))

        let anonymous = try #require(records.first { $0.deduplicationID == nil })
        #expect(anonymous.tally == TokenTally(input: 5, output: 6))
    }

    @Test("A session present in both V1 and V2 is read from V2")
    func v2WinsSameRelativePath() throws {
        let home = try EditorTestSupport.temporary("cherry-precedence")
        defer { try? FileManager.default.removeItem(at: home) }
        let v2 = home.appending(
            path: "Library/Application Support/CherryStudio/Data/Agents/.claude/projects"
        )
        let v1 = home.appending(path: "Library/Application Support/CherryStudio/.claude/projects")

        try EditorTestSupport.jsonLines(
            [Self.assistant("req-v1", uuid: "a", input: 1, output: 1, cacheRead: 0, cacheWrite: 0,
                            at: EditorTestSupport.at(hour: 9))],
            to: v1.appending(path: "pulse/session-a.jsonl")
        )
        try EditorTestSupport.jsonLines(
            [Self.assistant("req-v2", uuid: "b", input: 200, output: 100, cacheRead: 0, cacheWrite: 0,
                            at: EditorTestSupport.at(hour: 9))],
            to: v2.appending(path: "pulse/session-a.jsonl")
        )

        let roots = EditorLogReaders.inputs(client: "cherrystudio", home: home)
        let records = EditorLogReaders.records(client: "cherrystudio", roots: roots)
        try #require(records.count == 1)
        #expect(records[0].tally == TokenTally(input: 200, output: 100))
        #expect(records[0].deduplicationID?.contains("req-v2") == true)
    }
}
