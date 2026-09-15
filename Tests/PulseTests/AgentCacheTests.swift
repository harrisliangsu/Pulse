import Foundation
import SQLite3
import Testing
@testable import Pulse

/// Whether the disk cache that keeps an agent's finished ledger is valid:
/// settled by the store's real inputs and the price table, never by the store
/// root's own size and date.
@Suite("Agent cache")
struct AgentCacheTests {
    private static func temporary(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
    }

    private static func append(_ text: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    @Test("A log appended to inside a store moves the fingerprint, though the directory's stamp does not")
    func nestedAppendsAreSeen() throws {
        let root = Self.temporary("grok-store")
        let run = root.appending(path: "%2FUsers%2Fme%2FCode").appending(path: "01a0")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let log = run.appending(path: "updates.jsonl")
        try "{\"timestamp\":1}\n".write(to: log, atomically: true, encoding: .utf8)

        let before = AgentCache.sourceFingerprint(of: root)
        let rootBefore = try root.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        // A plain append: the file grows, the directory entry does not change.
        try Self.append("{\"timestamp\":2}\n", to: log)
        let after = AgentCache.sourceFingerprint(of: root)
        let rootAfter = try root.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        #expect(before != after)
        // The store root's own values, which the old stamp was built from,
        // need not have moved at all — which is exactly why it missed this.
        #expect(rootBefore.contentModificationDate == rootAfter.contentModificationDate)
    }

    @Test("Adding and removing a session file moves the fingerprint")
    func additionsAndRemovalsAreSeen() throws {
        let root = Self.temporary("kimi-store")
        let first = root.appending(path: "hash/one")
        let second = root.appending(path: "hash/two")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "{}".write(to: first.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        let one = AgentCache.sourceFingerprint(of: root)

        try "{}".write(to: second.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        let two = AgentCache.sourceFingerprint(of: root)
        #expect(one != two)

        try FileManager.default.removeItem(at: second)
        #expect(AgentCache.sourceFingerprint(of: root) == one)
    }

    @Test("A session's title file is part of the store")
    func titleFilesArePartOfTheStore() throws {
        let root = Self.temporary("kimi-title")
        let session = root.appending(path: "hash/session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "{}".write(to: session.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        let before = AgentCache.sourceFingerprint(of: root)

        // The title lives in `state.json` beside the wire log; a rename must
        // invalidate a ledger whose session row carries the old one.
        try #"{"custom_title":"A new name"}"#.write(
            to: session.appending(path: "state.json"), atomically: true, encoding: .utf8
        )
        #expect(before != AgentCache.sourceFingerprint(of: root))
    }

    @Test("Reading a store does not change its own fingerprint")
    func readingDoesNotInvalidateTheCache() throws {
        let root = Self.temporary("kimi-read")
        let session = root.appending(path: "hash/session")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let wire = session.appending(path: "wire.jsonl")
        try #"{"timestamp":1}"#.write(to: wire, atomically: true, encoding: .utf8)

        let before = AgentCache.sourceFingerprint(of: root)
        _ = try Data(contentsOf: wire)
        #expect(before == AgentCache.sourceFingerprint(of: root))
    }

    @Test("A database's write-ahead log counts; its shared-memory index does not")
    func databaseSidecars() throws {
        let directory = Self.temporary("db-store")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let db = directory.appending(path: "opencode.db")
        try Data([0x01]).write(to: db)
        let main = AgentCache.sourceFingerprint(of: db)

        // SQLite commits into the WAL first; the `.db` can sit unchanged
        // across a restart while the work is all in the log beside it.
        try Data([0x02, 0x03]).write(to: URL(fileURLWithPath: db.path + "-wal"))
        let withWAL = AgentCache.sourceFingerprint(of: db)
        #expect(main != withWAL)

        // `-shm` is shared memory the act of opening the store touches, so it
        // must not count — otherwise every read would invalidate the cache it
        // just filled.
        try Data([0x04]).write(to: URL(fileURLWithPath: db.path + "-shm"))
        #expect(AgentCache.sourceFingerprint(of: db) == withWAL)
    }

    @Test("A real WAL commit moves the fingerprint while the open database's own stamp sits still")
    func aRealWALCommitIsSeen() throws {
        let directory = Self.temporary("real-wal")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let db = directory.appending(path: "sessions.db")
        var writer: OpaquePointer?
        #expect(sqlite3_open(db.path, &writer) == SQLITE_OK)
        // Left open for the whole test: *closing* a WAL database is what
        // checkpoints it into the `.db`, which is exactly the event that
        // would hide the window this covers.
        defer { sqlite3_close(writer) }

        for sql in [
            "PRAGMA journal_mode=WAL;",
            "PRAGMA wal_autocheckpoint=0;",
            "CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT);",
            "INSERT INTO t (v) VALUES ('one');",
        ] {
            #expect(sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK)
        }

        // WAL mode is established and the first row is committed into the WAL,
        // so the `.db` has settled at its size for the statements that follow.
        let dbBefore = try URL(fileURLWithPath: db.path)
            .resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fingerprintBefore = AgentCache.sourceFingerprint(of: db)

        #expect(sqlite3_exec(writer, "INSERT INTO t (v) VALUES ('two');", nil, nil, nil) == SQLITE_OK)

        let dbAfter = try URL(fileURLWithPath: db.path)
            .resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fingerprintAfter = AgentCache.sourceFingerprint(of: db)

        // The writer is still open: the commit went to the WAL, not the `.db`.
        #expect(dbBefore.fileSize == dbAfter.fileSize)
        #expect(dbBefore.contentModificationDate == dbAfter.contentModificationDate)
        // Which is exactly why the fingerprint has to include the WAL.
        #expect(fingerprintBefore != fingerprintAfter)

        // The shared-memory index really is there, and is not part of the
        // digest: moving its date must not read as a data change.
        let shm = URL(fileURLWithPath: db.path + "-shm")
        #expect(FileManager.default.fileExists(atPath: shm.path))
        let settled = AgentCache.sourceFingerprint(of: db)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: shm.path
        )
        #expect(AgentCache.sourceFingerprint(of: db) == settled)
    }

    @Test("An empty price table is its own stamp, and one changed rate is a different one")
    func pricesArePartOfTheStamp() {
        #expect(AgentCache.priceFingerprint([:]) == "empty")

        let table = ["m": ModelPrice(input: 1, output: 2, cacheRead: nil, cacheWrite: nil, name: nil)]
        let digest = AgentCache.priceFingerprint(table)
        #expect(digest != "empty")
        // The same table is the same digest, so a daily refresh that fetched
        // nothing new does not throw every cached ledger away.
        #expect(AgentCache.priceFingerprint(table) == digest)
        // A changed rate is a different digest.
        let raised = ["m": ModelPrice(input: 9, output: 2, cacheRead: nil, cacheWrite: nil, name: nil)]
        #expect(AgentCache.priceFingerprint(raised) != digest)
    }

    @Test("A ledger cached offline at $0.00 is invalidated when prices arrive")
    func anEmptyPriceTableDoesNotStick() throws {
        let store = Self.temporary("offline-store")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store) }

        let offline = AgentCache.stamp(for: store, prices: [:])
        let online = AgentCache.stamp(
            for: store,
            prices: ["m": ModelPrice(input: 1, output: 2, cacheRead: nil, cacheWrite: nil, name: nil)]
        )
        // The store is untouched; only the price table changed. Without the
        // table in the stamp the first offline run would be cached at $0.00
        // for ever, because an unchanged store is never read again.
        #expect(offline.source == online.source)
        #expect(offline != online)
    }

    @Test("A cache written before sessions kept their buckets does not decode")
    func theOldShapeDoesNotDecode() throws {
        // The `agent-1` shape: a store-sized stamp, and a session with no
        // buckets. If this decoded, every project in it would total $0.00
        // rather than the store being read again.
        let old = """
        {"stamp":{"size":1,"modified":0},"ledger":{"days":[],"sessions":[\
        {"id":"s","name":"n","start":0,"end":0,"tokens":1,"cost":0.1}],\
        "unpricedModels":[],"modelNames":{},"slots":[]}}
        """
        var decoded = false
        do {
            _ = try JSONDecoder().decode(AgentCache.Saved.self, from: Data(old.utf8))
            decoded = true
        } catch {}
        #expect(!decoded)
    }

    @Test("A kept session's buckets survive the cache round-trip")
    func sessionSlotsRoundTrip() throws {
        let stored = AgentCache.StoredSession(
            id: "s", name: "n", title: "T", project: "Pulse",
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 200),
            tokens: 15, cost: 1.5,
            slots: [AgentCache.StoredSlot(start: Date(timeIntervalSince1970: 100), tokens: 15, cost: 1.5)]
        )
        let back = try JSONDecoder().decode(
            AgentCache.StoredSession.self, from: JSONEncoder().encode(stored)
        )
        #expect(back.slots.count == 1)
        #expect(back.slots.first?.tokens == 15)
        #expect(back.slots.first?.cost == 1.5)
        #expect(back.slots.first?.start == Date(timeIntervalSince1970: 100))
    }
}
