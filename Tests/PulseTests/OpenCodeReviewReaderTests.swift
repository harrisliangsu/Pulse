import Foundation
import Testing
@testable import Pulse

/// OpenCodeReview's usage is settled by the store's own total, never by
/// assuming `prompt_tokens` and the cache buckets are disjoint. A line's own
/// `uuid` is its business identity, so two equal requests in one second are
/// both counted while a replayed `uuid` folds once.
@Suite("OpenCodeReview reader")
struct OpenCodeReviewReaderTests {
    private static func line(
        _ usage: [String: Any],
        at hour: Int,
        session: String = "sess-a",
        duration: Int? = nil,
        uuid: String? = nil
    ) -> [String: Any] {
        var row: [String: Any] = [
            "type": "llm_response",
            "sessionId": session,
            "timestamp": EditorTestSupport.millis(EditorTestSupport.at(hour: hour)),
            "usage": usage,
        ]
        if let duration { row["duration_ms"] = duration }
        if let uuid { row["uuid"] = uuid }
        return row
    }

    private static func start(_ session: String = "sess-a") -> [String: Any] {
        [
            "type": "session_start", "sessionId": session,
            "timestamp": EditorTestSupport.millis(EditorTestSupport.at(hour: 8)),
            "cwd": "/work/pulse", "model": "claude-sonnet",
        ]
    }

    @Test("The reported total settles the cache relation, and an unprovable total is unclassified")
    func totalSettlesTheCacheRelation() throws {
        let home = try EditorTestSupport.temporary("opencodereview-total")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".opencodereview/sessions/repo-1/session-a.jsonl")

        try EditorTestSupport.jsonLines([
            Self.start(),
            // total == prompt + completion, and less than the disjoint sum:
            // prompt contains the cache, so fresh input is 100 - 40 = 60.
            Self.line(
                ["prompt_tokens": 100, "cache_read_tokens": 40, "completion_tokens": 10,
                 "total_tokens": 110],
                at: 9
            ),
            // total counts every kind: the four are disjoint.
            Self.line(
                ["prompt_tokens": 100, "cache_read_tokens": 40, "cache_write_tokens": 5,
                 "completion_tokens": 10, "total_tokens": 155],
                at: 10
            ),
            // total fits neither shape: keep it whole rather than guess.
            Self.line(
                ["prompt_tokens": 100, "cache_read_tokens": 40, "completion_tokens": 10,
                 "total_tokens": 130],
                at: 11
            ),
            // No total and no cache: nothing can overlap.
            Self.line(["prompt_tokens": 7, "completion_tokens": 3], at: 12),
            // No total and a positive cache: the relation is unproven, so there
            // is no complete-looking number to give.
            Self.line(["prompt_tokens": 100, "cache_read_tokens": 40, "completion_tokens": 10], at: 13),
        ], to: file)

        let records = EditorLogReaders.records(
            client: "opencodereview",
            roots: EditorLogReaders.inputs(client: "opencodereview", home: home)
        )
        #expect(records.count == 4)
        // One unprovable cache line was dropped, so what remains is a subset.
        #expect(records.allSatisfy { $0.isPartial })

        // The I100/C40/O10/T110 case must not become 150.
        let inclusive = try #require(records.first { $0.tally.cacheRead == 40 && $0.tally.input == 60 })
        #expect(inclusive.tally == TokenTally(input: 60, cacheRead: 40, output: 10))
        #expect(inclusive.tally.total == 110)
        #expect(inclusive.tally.total != 150)

        let disjoint = try #require(records.first { $0.tally.cacheWrite == 5 })
        #expect(disjoint.tally == TokenTally(input: 100, cacheWrite: 5, cacheRead: 40, output: 10))

        let unprovable = try #require(records.first { $0.unclassifiedTokens == 130 })
        #expect(unprovable.tally == TokenTally())
        #expect(unprovable.model == "claude-sonnet")

        let noCache = try #require(records.first { $0.tally.input == 7 })
        #expect(noCache.tally == TokenTally(input: 7, output: 3))
    }

    @Test("Equal same-second requests count twice; a real uuid replay folds once")
    func identityIsNotValueEquality() throws {
        let home = try EditorTestSupport.temporary("opencodereview-identity")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".opencodereview/sessions")

        let usage: [String: Any] = [
            "prompt_tokens": 100, "cache_read_tokens": 40, "completion_tokens": 10, "total_tokens": 110,
        ]
        // Two distinct requests in the same second, each with its own uuid.
        let first = Self.line(usage, at: 9, uuid: "u1")
        let second = Self.line(usage, at: 9, uuid: "u2")
        // Two more with no id at all: value equality is not identity.
        let anonymousA = Self.line(usage, at: 9)
        let anonymousB = Self.line(usage, at: 9)

        let session = [Self.start(), first, second, anonymousA, anonymousB]
        try EditorTestSupport.jsonLines(session, to: sessions.appending(path: "repo-a/s1.jsonl"))
        // The whole session re-exported: every uuid/count is the same and every
        // line position is the same, so nothing is added a second time.
        try EditorTestSupport.jsonLines(session, to: sessions.appending(path: "repo-b/s1.jsonl"))

        let records = EditorLogReaders.records(
            client: "opencodereview",
            roots: EditorLogReaders.inputs(client: "opencodereview", home: home)
        )
        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.tally == TokenTally(input: 60, cacheRead: 40, output: 10) })
        #expect(records.contains { $0.deduplicationID?.contains("uuid:u1") == true })
        #expect(records.contains { $0.deduplicationID?.contains("uuid:u2") == true })
    }

    @Test("A whole-file mirror folds, but two same-session fragments stay apart")
    func fragmentIdentity() throws {
        let home = try EditorTestSupport.temporary("opencodereview-fragments")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".opencodereview/sessions")

        // Same session id, no uuid, both restart at line 1 — but different
        // fragments, so neither may be folded away.
        try EditorTestSupport.jsonLines([
            Self.start(),
            Self.line(["prompt_tokens": 5, "completion_tokens": 1], at: 9),
        ], to: sessions.appending(path: "repo-a/s1.jsonl"))
        try EditorTestSupport.jsonLines([
            Self.start(),
            Self.line(["prompt_tokens": 7, "completion_tokens": 2], at: 10),
        ], to: sessions.appending(path: "repo-b/s1.jsonl"))

        // A byte-identical mirror of the first fragment: a whole-file replay.
        try EditorTestSupport.jsonLines([
            Self.start(),
            Self.line(["prompt_tokens": 5, "completion_tokens": 1], at: 9),
        ], to: sessions.appending(path: "repo-c/s1.jsonl"))

        let records = EditorLogReaders.records(
            client: "opencodereview",
            roots: EditorLogReaders.inputs(client: "opencodereview", home: home)
        )
        #expect(records.count == 2)
        #expect(records.contains { $0.tally == TokenTally(input: 5, output: 1) })
        #expect(records.contains { $0.tally == TokenTally(input: 7, output: 2) })
    }

    @Test("Two equal no-id lines in one file are two requests")
    func sameFileEqualNoIDLinesCountTwice() throws {
        let home = try EditorTestSupport.temporary("opencodereview-same-file")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".opencodereview/sessions/repo-1/s1.jsonl")
        let duplicate = Self.line(["prompt_tokens": 5, "completion_tokens": 1], at: 9)

        try EditorTestSupport.jsonLines([Self.start(), duplicate, duplicate], to: file)

        let records = EditorLogReaders.records(
            client: "opencodereview",
            roots: EditorLogReaders.inputs(client: "opencodereview", home: home)
        )
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.tally == TokenTally(input: 5, output: 1) })
        #expect(records.allSatisfy { !$0.isPartial })
    }

    @Test("A request's start is anchored at its end minus the duration")
    func durationAnchoring() throws {
        let home = try EditorTestSupport.temporary("opencodereview-duration")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".opencodereview/sessions/repo-1/session-a.jsonl")
        let end = EditorTestSupport.at(hour: 9)

        try EditorTestSupport.jsonLines([
            Self.start(),
            Self.line(["prompt_tokens": 5, "completion_tokens": 1], at: 9, duration: 2000),
        ], to: file)

        let records = EditorLogReaders.records(
            client: "opencodereview",
            roots: EditorLogReaders.inputs(client: "opencodereview", home: home)
        )
        try #require(records.count == 1)
        #expect(records[0].timestamp == end.addingTimeInterval(-2))
        #expect(records[0].tally == TokenTally(input: 5, output: 1))
    }
}
