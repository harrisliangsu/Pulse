import Foundation
import Testing
@testable import Pulse

/// A one-hour cache write is billed at twice the input rate, a five-minute one
/// at the list's cache-write rate.
@Suite("Cache write pricing")
struct CacheWritePricingTests {
    private let price = ModelPrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25, name: nil)

    @Test("The hour's share is priced at twice input, the rest at the five-minute rate")
    func hourAndFiveMinutes() {
        let tally = TokenTally(cacheWrite: 1_000_000, cacheWrite1h: 800_000)
        // 200k at $6.25/M and 800k at $10/M.
        #expect(abs(tally.costBreakdown(at: price).cacheWrite - (1.25 + 8)) < 0.000_001)
        #expect(tally.total == 1_000_000)
    }

    @Test("An hour share larger than the writes is held to them")
    func clamped() {
        let tally = TokenTally(cacheWrite: 100, cacheWrite1h: 500)
        #expect(abs(tally.costBreakdown(at: price).cacheWrite - 100 * 10 / 1_000_000) < 0.000_001)
    }

    @Test("Claude Code's one-hour share is read from cache_creation")
    func parsed() async {
        let line = #"{"type":"assistant","timestamp":"2026-09-20T10:00:00Z","message":{"id":"a","model":"claude-test","usage":{"input_tokens":3,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":5,"cache_creation":{"ephemeral_5m_input_tokens":200,"ephemeral_1h_input_tokens":800}}}}"#
        let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory).parseClaudeCode(Data(line.utf8))
        let tally = scanned.allDays.values.flatMap(\.values).reduce(TokenTally(), +)
        #expect(tally == TokenTally(input: 3, cacheWrite: 1_000, output: 5, cacheWrite1h: 800))
    }

    @Test("A reply with no cache field at all is told apart from one with zero")
    func cacheFieldsAbsent() async {
        let silent = #"{"type":"assistant","timestamp":"2026-09-20T10:00:00Z","message":{"id":"a","model":"glm","usage":{"input_tokens":30,"output_tokens":5}}}"#
        let zero = #"{"type":"assistant","timestamp":"2026-09-20T10:01:00Z","message":{"id":"b","model":"claude-test","usage":{"input_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":5}}}"#
        let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory)
            .parseClaudeCode(Data((silent + "\n" + zero).utf8))
        let byModel = scanned.allDays.values.reduce(into: [String: TokenTally]()) { result, models in
            for (model, tally) in models { result[model] = (result[model] ?? TokenTally()) + tally }
        }
        #expect(byModel["glm"]?.reportsNoCache == true)
        #expect(byModel["claude-test"]?.reportsNoCache == false)
    }

    @Test("A tally saved before the hour share existed still decodes")
    func oldShape() throws {
        let data = Data(#"{"input":1,"cacheWrite":2,"cacheRead":3,"output":4}"#.utf8)
        #expect(try JSONDecoder().decode(TokenTally.self, from: data)
            == TokenTally(input: 1, cacheWrite: 2, cacheRead: 3, output: 4))
    }
}

/// OpenCode's reasoning, beside output in current rows and inside it in old
/// ones, is counted once either way.
@Suite("OpenCode reasoning")
struct OpenCodeReasoningTests {
    private func int(_ value: Any?) -> Int { (value as? Int) ?? 0 }

    @Test("Current rows: reasoning beside output, inside total — added")
    func beside() {
        let counts: [String: Any] = ["input": 10, "output": 5, "reasoning": 20, "total": 135,
                                     "cache": ["read": 100, "write": 0]]
        #expect(OpenCodeStore.output(counts, int: int) == 25)
    }

    @Test("Old rows: reasoning already in output, outside total — not added again")
    func folded() {
        let counts: [String: Any] = ["input": 10, "output": 25, "reasoning": 20, "total": 135,
                                     "cache": ["read": 100, "write": 0]]
        #expect(OpenCodeStore.output(counts, int: int) == 25)
    }

    @Test("No total: OpenCode 2 adds it; OpenCode 1's old rows already hold it")
    func untold() {
        #expect(OpenCodeStore.output(["output": 25, "reasoning": 20], int: int) == 45)
        #expect(OpenCodeStore.output(["output": 25, "reasoning": 20], int: int, totallessFolded: true) == 25)
    }

    @Test("Reasoning larger than output cannot be inside it")
    func largerThanOutput() {
        // A total that leaves reasoning out, on a row whose output is smaller
        // than its reasoning: beside, whatever the total says.
        let counts: [String: Any] = ["input": 10, "output": 5, "reasoning": 20, "total": 115,
                                     "cache": ["read": 100, "write": 0]]
        #expect(OpenCodeStore.output(counts, int: int) == 25)
        #expect(OpenCodeStore.output(["output": 5, "reasoning": 20], int: int, totallessFolded: true) == 25)
    }
}
