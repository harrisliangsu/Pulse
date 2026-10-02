import Darwin
import Foundation
import Testing
@testable import Pulse

/// Opt-in, repeatable memory probe. It writes only synthetic data into its own
/// temporary root; never points a performance run at a user's conversations.
/// PULSE_SPEND_BENCHMARK=1 swift test --filter SpendReadPerformanceTests
@Suite("Spend read performance", .serialized)
struct SpendReadPerformanceTests {
    /// A GiB-scale read uses the same bounded fixture writer and assertions.
    private var rowCount: Int {
        ProcessInfo.processInfo.environment["PULSE_SPEND_BENCHMARK_LARGE"] == "1" ? 131_072 : 16_384
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_SPEND_BENCHMARK"] == "1"))
    func codexTranscript() async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseCodexBenchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data((
            #"{"payload":{"cwd":"/synthetic/project","model":"gpt-5","type":"message","role":"user","content":"Benchmark"}}"# + "\n"
        ).utf8))
        let noise = Data((
            #"{"type":"response_item","payload":{"type":"function_call_output","output":""#
                + String(repeating: "x", count: 8_192) + #""}}"# + "\n"
        ).utf8)
        for index in 1...rowCount {
            try writer.write(contentsOf: noise)
            if index.isMultiple(of: 16) {
                let count = """
                {"timestamp":"2026-01-02T09:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(index * 100),"cached_input_tokens":\(index * 20),"output_tokens":\(index * 10)}}}}

                """
                try writer.write(contentsOf: Data(count.utf8))
            }
        }
        try writer.close()
        let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0

        let start = ContinuousClock.now
        let scanned = await UsageLedgerReader().parse(file, provider: .codex)
        let elapsed = start.duration(to: .now)
        #expect(scanned.title == "Benchmark")
        #expect(scanned.cwd == "/synthetic/project")
        #expect(scanned.allDays.values.flatMap { $0.values }.reduce(TokenTally(), +)
            == TokenTally(input: rowCount * 80, cacheRead: rowCount * 20, output: rowCount * 10))
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("Spend synthetic Codex: \(bytes) bytes, \(elapsed), peak RSS \(usage.ru_maxrss) bytes")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_SPEND_BENCHMARK"] == "1"))
    func largeTranscript() throws {
        let root = URL.temporaryDirectory.appending(path: "PulseSpendBenchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "session.jsonl")
        let row: [String: Any] = [
            "id": "replayed-message", "type": "message", "role": "assistant", "status": "completed",
            "timestamp": 1_780_000_000_000, "sessionId": "synthetic",
            "message": ["model": "gpt-5", "usage": ["input_tokens": 100, "output_tokens": 20],
                        "content": String(repeating: "x", count: 8_192)]
        ]
        var line = try JSONSerialization.data(withJSONObject: row)
        line.append(0x0a)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file)
        for _ in 0..<rowCount { try writer.write(contentsOf: line) }
        try writer.close()

        let start = ContinuousClock.now
        let records = TencentBuddyReader.records(client: "workbuddy", roots: [root])
        let elapsed = start.duration(to: .now)
        #expect(records.count == 1)
        #expect(records.first?.tally == TokenTally(input: 100, output: 20))
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("Spend synthetic JSONL: \(line.count * rowCount) bytes, \(elapsed), peak RSS \(usage.ru_maxrss) bytes")
    }
}
