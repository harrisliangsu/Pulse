import Foundation
import Testing
@testable import Pulse

/// When Claude Code's prompt cache lapses: the last request that touched it,
/// plus the tier the session last wrote — both read from the log.
struct PromptCacheLapseTests {
    private func reply(_ at: String, read: Int = 0, hour: Int = 0, fiveMinutes: Int = 0, sidechain: Bool = false) -> String {
        """
        {"type":"assistant","timestamp":"\(at)","isSidechain":\(sidechain),"message":{"usage":{"input_tokens":3,\
        "cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(hour + fiveMinutes),\
        "cache_creation":{"ephemeral_1h_input_tokens":\(hour),"ephemeral_5m_input_tokens":\(fiveMinutes)},"output_tokens":9}}}
        """
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func anHourTierLastsAnHourFromTheLastRequest() throws {
        let lapse = try #require(ClaudePromptCache.lapse(inTail: [
            reply("2026-09-30T10:00:00.000Z", hour: 500),
            reply("2026-09-30T10:20:00.000Z", read: 9_000, hour: 200),
        ].joined(separator: "\n")))
        #expect(lapse.lifetime == PromptCacheLapse.hour)
        #expect(lapse.expiresAt == date("2026-09-30T11:20:00Z"))
    }

    @Test func aHitRenewsTheTierAnEarlierReplyWrote() throws {
        // The last reply only read the cache; the tier comes from the one before.
        let lapse = try #require(ClaudePromptCache.lapse(inTail: [
            reply("2026-09-30T10:00:00.000Z", fiveMinutes: 800),
            reply("2026-09-30T10:03:00.000Z", read: 9_000),
        ].joined(separator: "\n")))
        #expect(lapse.lifetime == PromptCacheLapse.fiveMinutes)
        #expect(lapse.lastRequest == date("2026-09-30T10:03:00Z"))
    }

    @Test func subagentLinesAndOtherEntriesAreNotTheSession() throws {
        let lapse = try #require(ClaudePromptCache.lapse(inTail: [
            "half a line cut off by the tail\"usage\"",
            reply("2026-09-30T10:00:00.000Z", hour: 500),
            #"{"type":"user","timestamp":"2026-09-30T10:30:00.000Z","message":{"usage":{}}}"#,
            reply("2026-09-30T10:40:00.000Z", fiveMinutes: 300, sidechain: true),
        ].joined(separator: "\n")))
        #expect(lapse.lastRequest == date("2026-09-30T10:00:00Z"))
        #expect(lapse.lifetime == PromptCacheLapse.hour)
    }

    @Test func noTierInReachIsNoLapse() {
        // Replies that only read the cache never say how long it is kept.
        #expect(ClaudePromptCache.lapse(inTail: reply("2026-09-30T10:00:00.000Z", read: 9_000)) == nil)
        #expect(ClaudePromptCache.lapse(inTail: reply("2026-09-30T10:00:00.000Z")) == nil)
        #expect(ClaudePromptCache.lapse(inTail: "") == nil)
    }

    // MARK: Every conversation

    private let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!

    private func iso(_ minutesAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(-minutesAgo * 60))
    }

    /// A session file whose last reply is `minutesAgo` old, written then.
    private func write(_ home: URL, _ path: String, minutesAgo: Double, lines: [String]) throws {
        let file = home.appending(path: ".claude/projects/\(path)")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-minutesAgo * 60)],
                                              ofItemAtPath: file.path)
    }

    private func opening(_ text: String) -> String {
        #"{"type":"user","cwd":"/Users/me/Code/Pulse","message":{"role":"user","content":"\#(text)"}}"#
    }

    @Test func everyLiveConversationSoonestFirstSubagentsLeftOut() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "pulse-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        // Three conversations side by side, each on the hour tier.
        try write(home, "-Users-me-Code-Pulse/a.jsonl", minutesAgo: 50,
                  lines: [opening("Fix the card"), reply(iso(50), hour: 400)])
        try write(home, "-Users-me-Code-Pulse/b.jsonl", minutesAgo: 5,
                  lines: [opening("Write the docs"), reply(iso(5), hour: 400),
                          #"{"type":"custom-title","customTitle":"Docs pass"}"#])
        try write(home, "-Users-me-Code-Site/c.jsonl", minutesAgo: 20,
                  lines: [opening("Ship the site"), reply(iso(20), hour: 400)])
        // A subagent a folder deeper, just now, on the short tier: not a conversation.
        try write(home, "-Users-me-Code-Pulse/b/subagents/agent-1.jsonl", minutesAgo: 1,
                  lines: [reply(iso(1), fiveMinutes: 300)])
        // One from yesterday, long lapsed.
        try write(home, "-Users-me-Code-Pulse/old.jsonl", minutesAgo: 1440,
                  lines: [opening("Old"), reply(iso(1440), hour: 400)])

        let reading = ClaudePromptCache.read(home: home, now: now)
        #expect(reading.live.map(\.title) == ["Fix the card", "Ship the site", "Docs pass"])
        #expect(reading.live.map { $0.lapse.expiresAt } == [10, 40, 55].map { now.addingTimeInterval($0 * 60) })
        #expect(reading.live.first?.project == "Pulse")
        #expect(reading.lastLapsed == nil)
    }

    @Test func withNoneAliveTheNewestLapseIsKept() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "pulse-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try write(home, "p/a.jsonl", minutesAgo: 90, lines: [reply(iso(90), hour: 400)])
        try write(home, "p/b.jsonl", minutesAgo: 30, lines: [reply(iso(30), fiveMinutes: 400)])

        let reading = ClaudePromptCache.read(home: home, now: now)
        #expect(reading.live.isEmpty)
        #expect(reading.lastLapsed?.expiresAt == now.addingTimeInterval(-25 * 60))
    }

    // MARK: The request's time, not the reply's

    /// A reply block carrying an id and the entry it answers.
    private func block(_ at: String, uuid: String, parent: String?, hour: Int = 0, read: Int = 0) -> String {
        let parentField = parent.map { "\"\($0)\"" } ?? "null"
        return """
        {"uuid":"\(uuid)","parentUuid":\(parentField),"type":"assistant","timestamp":"\(at)","isSidechain":false,\
        "message":{"usage":{"cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(hour),\
        "cache_creation":{"ephemeral_1h_input_tokens":\(hour),"ephemeral_5m_input_tokens":0}}}}
        """
    }

    private func prompt(_ at: String, uuid: String, type: String = "user") -> String {
        #"{"uuid":"\#(uuid)","parentUuid":null,"type":"\#(type)","timestamp":"\#(at)","message":{"content":"x"}}"#
    }

    @Test func theCacheIsCountedFromTheRequestNotFromTheEndOfTheAnswer() throws {
        // Asked at 10:00:00; the answer streamed for ninety seconds, as two
        // logged blocks, and was written down at 10:01:30.
        let lapse = try #require(ClaudePromptCache.lapse(inTail: [
            prompt("2026-09-30T10:00:00.000Z", uuid: "ask"),
            block("2026-09-30T10:00:05.000Z", uuid: "b1", parent: "ask", hour: 300),
            block("2026-09-30T10:01:30.000Z", uuid: "b2", parent: "b1", hour: 300),
        ].joined(separator: "\n")))
        #expect(lapse.lastRequest == date("2026-09-30T10:00:00Z"))
        #expect(lapse.expiresAt == date("2026-09-30T11:00:00Z"))
    }

    @Test func aToolResultIsTheRequestToo() throws {
        let lapse = try #require(ClaudePromptCache.lapse(inTail: [
            prompt("2026-09-30T10:00:00.000Z", uuid: "ask"),
            block("2026-09-30T10:00:10.000Z", uuid: "b1", parent: "ask", hour: 300),
            prompt("2026-09-30T10:12:00.000Z", uuid: "tool", type: "user"),
            block("2026-09-30T10:12:20.000Z", uuid: "b2", parent: "tool", read: 9_000),
        ].joined(separator: "\n")))
        #expect(lapse.lastRequest == date("2026-09-30T10:12:00Z"))
        #expect(lapse.lifetime == PromptCacheLapse.hour)
    }

    @Test func theRepliesOwnTimeStandsWhenTheRequestIsNotInReachOrNotPlausible() throws {
        // The prompting entry is not in the tail.
        let cut = try #require(ClaudePromptCache.lapse(inTail: block("2026-09-30T10:01:30.000Z", uuid: "b", parent: "gone", hour: 300)))
        #expect(cut.lastRequest == date("2026-09-30T10:01:30Z"))

        // Forty minutes before the reply is not the message it answered.
        let far = try #require(ClaudePromptCache.lapse(inTail: [
            prompt("2026-09-30T09:00:00.000Z", uuid: "ask"),
            block("2026-09-30T09:40:00.000Z", uuid: "b", parent: "ask", hour: 300),
        ].joined(separator: "\n")))
        #expect(far.lastRequest == date("2026-09-30T09:40:00Z"))
    }

    // MARK: The conversation to name

    private func session(_ name: String?, project: String?, expiresInMinutes: Double) -> PromptCacheSession {
        PromptCacheSession(
            id: name ?? "-", title: name, project: project,
            lapse: PromptCacheLapse(lastRequest: now.addingTimeInterval((expiresInMinutes - 60) * 60), lifetime: PromptCacheLapse.hour)
        )
    }

    @Test func theCardNamesTheConversationAboutToLapse() {
        let reading = PromptCacheReading(live: [
            session("Docs pass", project: "Pulse", expiresInMinutes: 55),
            session("Fix the card", project: "Pulse", expiresInMinutes: 10),
            session(nil, project: "Site", expiresInMinutes: 40),
        ], lastLapsed: nil)

        let alive = reading.alive(at: now)
        #expect(alive.map(\.displayName) == ["Fix the card", "Site", "Docs pass"])
        // Ten minutes later the first has lapsed and the next is named.
        #expect(reading.alive(at: now.addingTimeInterval(11 * 60)).first?.displayName == "Site")
        #expect(reading.alive(at: now.addingTimeInterval(56 * 60)).isEmpty)
    }
}
