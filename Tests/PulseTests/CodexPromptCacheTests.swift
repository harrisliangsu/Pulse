import Foundation
import Testing
@testable import Pulse

/// Codex's prompt cache: OpenAI's documented thirty-minute floor on GPT-5.6
/// and later, counted from the request the log shows last touching the cache.
struct CodexPromptCacheTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!

    private func iso(_ minutesAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func header(cwd: String = "/Users/me/Code/Pulse") -> String {
        #"{"timestamp":"2026-09-30T09:00:00.000Z","type":"session_meta","payload":{"cwd":"\#(cwd)"}}"#
    }

    private func context(_ model: String, _ minutesAgo: Double) -> String {
        #"{"timestamp":"\#(iso(minutesAgo))","type":"turn_context","payload":{"model":"\#(model)"}}"#
    }

    private func ask(_ text: String, _ minutesAgo: Double) -> String {
        #"{"timestamp":"\#(iso(minutesAgo))","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"\#(text)"}]}}"#
    }

    private func toolOutput(_ minutesAgo: Double) -> String {
        #"{"timestamp":"\#(iso(minutesAgo))","type":"response_item","payload":{"type":"custom_tool_call_output","output":"ok"}}"#
    }

    private func usage(_ minutesAgo: Double, cached: Int = 9_000, written: Int = 0) -> String {
        #"{"timestamp":"\#(iso(minutesAgo))","type":"token_usage_record","payload":{"usage":{"input_tokens":10000,"cached_input_tokens":\#(cached),"cache_write_input_tokens":\#(written),"output_tokens":20}}}"#
    }

    @Test func onlyModelsOpenAIStatesALifetimeForAreTimed() {
        for model in ["gpt-5.6", "gpt-5.6-sol", "gpt-6-sol", "gpt-6.1-sol", "gpt-7"] {
            #expect(CodexPromptCache.statesLifetime(forModel: model), "\(model)")
        }
        for model in ["gpt-5.5", "gpt-5", "gpt-5-codex", "codex-auto-review", "o3", "gpt-"] {
            #expect(!CodexPromptCache.statesLifetime(forModel: model), "\(model)")
        }
    }

    @Test func thirtyMinutesFromTheRequestAsAFloor() throws {
        // Asked 10 minutes ago; a tool ran and its output went back 4 minutes
        // ago; that answer's usage was logged 3 minutes ago.
        let lapse = try #require(CodexPromptCache.lapse(inTail: [
            header(), context("gpt-6-sol", 10), ask("Fix the build", 10),
            usage(9.5), toolOutput(4), usage(3),
        ].joined(separator: "\n")))
        #expect(lapse.isMinimum)
        #expect(lapse.lifetime == 30 * 60)
        #expect(lapse.lastRequest == now.addingTimeInterval(-4 * 60))
    }

    @Test func earlierModelsAndUntouchedCachesAreNotTimed() {
        #expect(CodexPromptCache.lapse(inTail: [context("gpt-5.5", 10), ask("x", 10), usage(9)].joined(separator: "\n")) == nil)
        #expect(CodexPromptCache.lapse(inTail: [context("gpt-6-sol", 10), ask("x", 10), usage(9, cached: 0)].joined(separator: "\n")) == nil)
        // No model in reach of the tail: nothing to look the lifetime up by.
        #expect(CodexPromptCache.lapse(inTail: [ask("x", 10), usage(9)].joined(separator: "\n")) == nil)
    }

    @Test func theLatestTurnsModelDecides() {
        // Switched from a timed model to an untimed one: the last request is not timed.
        #expect(CodexPromptCache.lapse(inTail: [
            context("gpt-6-sol", 20), ask("a", 20), usage(19),
            context("gpt-5.5", 5), ask("b", 5), usage(4),
        ].joined(separator: "\n")) == nil)
    }

    private func write(_ home: URL, _ name: String, minutesAgo: Double, lines: [String]) throws {
        let file = home.appending(path: ".codex/sessions/2026/09/29/\(name).jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-minutesAgo * 60)], ofItemAtPath: file.path)
    }

    @Test func everyConversationInsideItsFloorSoonestFirst() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "pulse-codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        // Filed under the day it started, still written to now.
        try write(home, "rollout-a", minutesAgo: 25, lines: [header(), context("gpt-6-sol", 26), ask("Ship the docs", 26), usage(25)])
        try write(home, "rollout-b", minutesAgo: 5, lines: [header(cwd: "/Users/me/Code/Site"), context("gpt-5.6-sol", 6),
                                                          ask("<environment_context>…</environment_context>", 6),
                                                          ask("Tidy the site", 6), usage(5)])
        // An earlier model: not timed, even though it is recent.
        try write(home, "rollout-c", minutesAgo: 2, lines: [header(), context("gpt-5.5", 3), ask("Old model", 3), usage(2)])

        let reading = CodexPromptCache.read(home: home, now: now)
        #expect(reading.live.map(\.title) == ["Ship the docs", "Tidy the site"])
        #expect(reading.live.map(\.project) == ["Pulse", "Site"])
        #expect(reading.live.first?.lapse.expiresAt == now.addingTimeInterval(4 * 60))
    }

    @Test func pastTheFloorTheNewestEndIsKept() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "pulse-codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try write(home, "rollout-a", minutesAgo: 50, lines: [context("gpt-6-sol", 50), ask("x", 50), usage(50)])
        let reading = CodexPromptCache.read(home: home, now: now)
        #expect(reading.live.isEmpty)
        #expect(reading.lastLapsed?.expiresAt == now.addingTimeInterval(-20 * 60))
        #expect(reading.lastLapsed?.isMinimum == true)
    }
}
