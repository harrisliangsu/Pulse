import Foundation
import Testing
@testable import Pulse

/// The transcript cache's bytes (`TranscriptCacheCodec`) must give back the
/// very `FileCache` they were written from — every field, nil kept apart from
/// empty — or `scan` would count differently from one read to the next.
@Suite("Transcript cache codec")
struct TranscriptCacheCodecTests {
    private static func tally(_ base: Int, banded: Bool = false) -> TokenTally {
        var tally = TokenTally(input: base, cacheWrite: base + 1, cacheRead: base + 2, output: base + 3)
        tally.cacheWrite1h = base / 2
        tally.repliesWithoutCacheFields = base % 3
        if banded { tally.contextBands = [200_000: TokenTally(input: base, output: 1), 128_000: TokenTally(cacheRead: 7)] }
        return tally
    }

    /// Every optional both ways, shared and unshared strings, bands, negative
    /// and huge numbers, and non-ASCII text.
    static let sample: FileCache = {
        var cache = FileCache()
        let timing = ReplyTiming(outputTokens: 400, seconds: 12.5, replies: 2, firstTokenSeconds: 0.75, firstTokenTurns: 1)
        var forked = UsageLedgerReader.ScannedReply(slot: "2026-10-14 16:15", model: "gpt-5.6", tally: tally(5))
        forked.runningTotal = "1200|300|80"
        forked.fromFork = true
        var plain = UsageLedgerReader.ScannedReply(slot: "2026-10-14 16:15", model: "claude-opus-4-5", tally: tally(9, banded: true))
        plain.timing = timing
        plain.fromFork = false
        cache.files["/Users/me/.codex/sessions/2026/10/14/rollout-a.jsonl"] = FileCache.Entry(
            stamp: FileCache.Stamp(size: 123_456_789, modified: 1_760_400_000.123456),
            days: ["2026-10-14 16:15": ["gpt-5.6": tally(5), "claude-opus-4-5": tally(9, banded: true)],
                   "2026-10-14 16:30": ["gpt-5.6": tally(-3)]],
            title: "修复 #85 · «quoted» 🚀", cwd: "/Users/me/项目", isReview: true,
            timings: ["2026-10-14 16:15": ["gpt-5.6": timing]],
            replies: ["msg_01": forked, "msg_02": plain],
            runningTotals: ["1200|300|80", ""]
        )
        cache.files["/Users/me/.claude/projects/p/s.jsonl"] = FileCache.Entry(
            stamp: FileCache.Stamp(size: 0, modified: 0),
            days: [:], title: nil, cwd: nil, isReview: false,
            timings: [:], replies: [:], runningTotals: []
        )
        cache.files["/Users/me/.claude/projects/p/old.jsonl"] = FileCache.Entry(
            stamp: FileCache.Stamp(size: Int.max, modified: -1.5),
            days: ["2025-01-01 00:00": ["m": TokenTally(input: Int.max)]],
            title: "", cwd: nil, isReview: nil, timings: nil, replies: nil, runningTotals: nil
        )
        return cache
    }()

    @Test("Bytes read back as exactly the cache they were written from")
    func roundTrip() throws {
        let data = TranscriptCacheCodec.encode(Self.sample)
        #expect(try TranscriptCacheCodec.decode(data) == Self.sample)
        #expect(try TranscriptCacheCodec.decode(TranscriptCacheCodec.encode(FileCache())) == FileCache())
    }

    @Test("Bytes and the JSON they replace hold the same cache")
    func sameAsJSON() throws {
        let json = try JSONEncoder().encode(Self.sample)
        let fromJSON = try JSONDecoder().decode(FileCache.self, from: json)
        #expect(try TranscriptCacheCodec.decode(TranscriptCacheCodec.encode(fromJSON)) == fromJSON)
    }

    @Test("A damaged file is no cache, never a partial one")
    func damaged() {
        let data = TranscriptCacheCodec.encode(Self.sample)
        for cut in [0, 3, 4, 5, 9, data.count / 2, data.count - 1] {
            #expect(throws: (any Error).self) { try TranscriptCacheCodec.decode(data.prefix(cut)) }
        }
        var wrongMagic = data
        wrongMagic[0] = 0x58
        #expect(throws: (any Error).self) { try TranscriptCacheCodec.decode(wrongMagic) }
        #expect(throws: (any Error).self) { try TranscriptCacheCodec.decode(data + Data([0])) }
    }

    @Test("The JSON cache is read once, written out as bytes, and removed")
    func migratesFromJSON() throws {
        let directory = URL.temporaryDirectory.appending(path: "PulseCodec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = directory.appending(path: "ledger-\(UsageLedgerReader.cacheVersion)-codex.json")
        let bin = directory.appending(path: "ledger-\(UsageLedgerReader.cacheVersion)-codex.bin")
        try JSONEncoder().encode(Self.sample).write(to: json)

        let migrated = FileCache.load(for: .codex, directory: directory)
        #expect(migrated.isFromJSON)
        #expect(migrated.files == Self.sample.files)

        migrated.save(for: .codex, directory: directory)
        #expect(FileManager.default.fileExists(atPath: bin.path))
        #expect(!FileManager.default.fileExists(atPath: json.path))
        let reread = FileCache.load(for: .codex, directory: directory)
        #expect(!reread.isFromJSON)
        #expect(reread.files == Self.sample.files)
    }

    @Test("A scan with nothing changed still moves a JSON cache to bytes, and counts the same")
    func scanMigrates() async throws {
        let home = URL.temporaryDirectory.appending(path: "PulseCodecScan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let logs = home.appending(path: ".claude/projects/fixture")
        let cache = home.appending(path: "cache")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let row = #"{"type":"assistant","timestamp":"2026-09-20T10:00:00Z","message":{"id":"one","model":"m","usage":{"input_tokens":100,"output_tokens":10}}}"#
        try (row + "\n").write(to: logs.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)

        let first = await UsageLedgerReader(home: home, cacheDirectory: cache).ledger(for: .claudeCode, prices: [:])
        // Put the cache back the way an earlier build left it: JSON, no bytes.
        let bin = cache.appending(path: "ledger-\(UsageLedgerReader.cacheVersion)-claudeCode.bin")
        let json = bin.deletingPathExtension().appendingPathExtension("json")
        let written = FileCache.load(for: .claudeCode, directory: cache)
        try JSONEncoder().encode(written).write(to: json)
        try FileManager.default.removeItem(at: bin)

        let again = await UsageLedgerReader(home: home, cacheDirectory: cache).ledger(for: .claudeCode, prices: [:])
        #expect(again.allTime.tokens == first.allTime.tokens)
        #expect(FileManager.default.fileExists(atPath: bin.path))
        #expect(!FileManager.default.fileExists(atPath: json.path))
        #expect(FileCache.load(for: .claudeCode, directory: cache).files == written.files)
    }
}
