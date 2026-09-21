import Darwin
import Foundation
import Testing
@testable import Pulse

/// Opt-in, repeatable memory probe. It writes only synthetic data into its own
/// temporary root; never points a performance run at a user's conversations.
/// PULSE_SPEND_BENCHMARK=1 swift test --filter SpendReadPerformanceTests
@Suite("Spend read performance")
struct SpendReadPerformanceTests {
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
        for _ in 0..<16_384 { try writer.write(contentsOf: line) }
        try writer.close()

        let start = ContinuousClock.now
        let records = TencentBuddyReader.records(client: "workbuddy", roots: [root])
        let elapsed = start.duration(to: .now)
        #expect(records.count == 1)
        #expect(records.first?.tally == TokenTally(input: 100, output: 20))
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("Spend synthetic JSONL: \(line.count * 16_384) bytes, \(elapsed), peak RSS \(usage.ru_maxrss) bytes")
    }
}
