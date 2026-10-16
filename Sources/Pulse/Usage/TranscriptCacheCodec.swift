// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The transcript cache (`FileCache`) on disk, as bytes rather than JSON.
///
/// **Why.** The cache is read whole on every history read, and Claude Code's
/// had grown to 13 MB of JSON: 345 transcripts, 38k replies kept by id for the
/// cross-file dedupe. Measured on an M5, `JSONDecoder` took ~0.22 s of it —
/// 92% of a card's history read — and decoding left ~100 MB in the process,
/// because every reply's quarter-hour and model came back as strings of their
/// own. The keyed containers `Codable` decodes through are most of that cost,
/// and no JSON decoder avoids them.
///
/// **What changes is the encoding and nothing else.** It decodes to the very
/// `FileCache` the JSON did, field for field, nil kept apart from empty, so
/// `scan` counts exactly as it did. Every string is written once, in a table,
/// and referred to by number: a quarter-hour or a model that a thousand
/// replies share is one string in memory after reading, not a thousand.
///
/// Layout, little-endian: `PLDC`, a format byte, the string table (count, then
/// each as length and UTF-8), then the entries. Anything that does not read
/// cleanly is no cache at all, exactly as a JSON file that failed to decode
/// was — the transcripts are read again.
enum TranscriptCacheCodec {
    private static let magic: [UInt8] = Array("PLDC".utf8)
    private static let format: UInt8 = 1

    struct Malformed: Error {}

    // MARK: - Writing

    static func encode(_ cache: FileCache) -> Data {
        var strings = StringTable()
        var body = Writer()
        body.u32(cache.files.count)
        for (path, entry) in cache.files {
            body.u32(strings.index(of: path))
            write(entry, to: &body, strings: &strings)
        }

        var out = Writer()
        out.bytes.reserveCapacity(body.bytes.count + strings.byteCount + 64)
        out.bytes.append(contentsOf: magic)
        out.bytes.append(format)
        out.u32(strings.list.count)
        for string in strings.list {
            let utf8 = Array(string.utf8)
            out.u32(utf8.count)
            out.bytes.append(contentsOf: utf8)
        }
        out.bytes.append(contentsOf: body.bytes)
        return Data(out.bytes)
    }

    private static func write(_ entry: FileCache.Entry, to out: inout Writer, strings: inout StringTable) {
        out.i64(entry.stamp.size)
        out.f64(entry.stamp.modified)

        var flags: UInt8 = 0
        if entry.title != nil { flags |= 1 << 0 }
        if entry.cwd != nil { flags |= 1 << 1 }
        if let isReview = entry.isReview {
            flags |= 1 << 2
            if isReview { flags |= 1 << 3 }
        }
        if entry.timings != nil { flags |= 1 << 4 }
        if entry.replies != nil { flags |= 1 << 5 }
        if entry.runningTotals != nil { flags |= 1 << 6 }
        out.bytes.append(flags)

        if let title = entry.title { out.u32(strings.index(of: title)) }
        if let cwd = entry.cwd { out.u32(strings.index(of: cwd)) }

        out.u32(entry.days.count)
        for (slot, models) in entry.days {
            out.u32(strings.index(of: slot))
            out.u32(models.count)
            for (model, tally) in models {
                out.u32(strings.index(of: model))
                write(tally, to: &out)
            }
        }

        if let timings = entry.timings {
            out.u32(timings.count)
            for (slot, models) in timings {
                out.u32(strings.index(of: slot))
                out.u32(models.count)
                for (model, timing) in models {
                    out.u32(strings.index(of: model))
                    write(timing, to: &out)
                }
            }
        }

        if let replies = entry.replies {
            out.u32(replies.count)
            for (id, reply) in replies {
                out.u32(strings.index(of: id))
                out.u32(strings.index(of: reply.slot))
                out.u32(strings.index(of: reply.model))
                write(reply.tally, to: &out)
                var replyFlags: UInt8 = 0
                if reply.timing != nil { replyFlags |= 1 << 0 }
                if reply.runningTotal != nil { replyFlags |= 1 << 1 }
                if let fromFork = reply.fromFork {
                    replyFlags |= 1 << 2
                    if fromFork { replyFlags |= 1 << 3 }
                }
                out.bytes.append(replyFlags)
                if let timing = reply.timing { write(timing, to: &out) }
                if let total = reply.runningTotal { out.u32(strings.index(of: total)) }
            }
        }

        if let totals = entry.runningTotals {
            out.u32(totals.count)
            for total in totals { out.u32(strings.index(of: total)) }
        }
    }

    private static func write(_ tally: TokenTally, to out: inout Writer) {
        out.i64(tally.input)
        out.i64(tally.cacheWrite)
        out.i64(tally.cacheRead)
        out.i64(tally.output)
        out.i64(tally.cacheWrite1h)
        out.i64(tally.repliesWithoutCacheFields)
        out.u32(tally.contextBands.count)
        for (band, inner) in tally.contextBands {
            out.i64(band)
            write(inner, to: &out)
        }
    }

    private static func write(_ timing: ReplyTiming, to out: inout Writer) {
        out.i64(timing.outputTokens)
        out.f64(timing.seconds)
        out.i64(timing.replies)
        out.f64(timing.firstTokenSeconds)
        out.i64(timing.firstTokenTurns)
    }

    // MARK: - Reading

    static func decode(_ data: Data) throws -> FileCache {
        try data.withUnsafeBytes { raw in
            var reader = Reader(raw)
            guard try reader.take(magic.count).elementsEqual(magic), try reader.byte() == format else {
                throw Malformed()
            }

            let stringCount = try reader.count()
            var strings: [String] = []
            strings.reserveCapacity(stringCount)
            for _ in 0..<stringCount {
                let length = try reader.count()
                strings.append(String(decoding: try reader.take(length), as: UTF8.self))
            }
            func string(_ reader: inout Reader) throws -> String {
                let index = try reader.count()
                guard index < strings.count else { throw Malformed() }
                return strings[index]
            }

            var cache = FileCache()
            let entryCount = try reader.count()
            cache.files.reserveCapacity(entryCount)
            for _ in 0..<entryCount {
                let path = try string(&reader)
                cache.files[path] = try entry(&reader, string: string)
            }
            guard reader.isAtEnd else { throw Malformed() }
            return cache
        }
    }

    private static func entry(
        _ reader: inout Reader, string: (inout Reader) throws -> String
    ) throws -> FileCache.Entry {
        let stamp = FileCache.Stamp(size: try reader.i64(), modified: try reader.f64())
        let flags = try reader.byte()
        let title = flags & (1 << 0) != 0 ? try string(&reader) : nil
        let cwd = flags & (1 << 1) != 0 ? try string(&reader) : nil
        let isReview: Bool? = flags & (1 << 2) != 0 ? flags & (1 << 3) != 0 : nil

        var days: [String: [String: TokenTally]] = [:]
        let dayCount = try reader.count()
        days.reserveCapacity(dayCount)
        for _ in 0..<dayCount {
            let slot = try string(&reader)
            let modelCount = try reader.count()
            var models: [String: TokenTally] = [:]
            models.reserveCapacity(modelCount)
            for _ in 0..<modelCount {
                let model = try string(&reader)
                models[model] = try tally(&reader)
            }
            days[slot] = models
        }

        var timings: [String: [String: ReplyTiming]]?
        if flags & (1 << 4) != 0 {
            var read: [String: [String: ReplyTiming]] = [:]
            let slotCount = try reader.count()
            read.reserveCapacity(slotCount)
            for _ in 0..<slotCount {
                let slot = try string(&reader)
                let modelCount = try reader.count()
                var models: [String: ReplyTiming] = [:]
                models.reserveCapacity(modelCount)
                for _ in 0..<modelCount {
                    let model = try string(&reader)
                    models[model] = try timing(&reader)
                }
                read[slot] = models
            }
            timings = read
        }

        var replies: [String: UsageLedgerReader.ScannedReply]?
        if flags & (1 << 5) != 0 {
            var read: [String: UsageLedgerReader.ScannedReply] = [:]
            let replyCount = try reader.count()
            read.reserveCapacity(replyCount)
            for _ in 0..<replyCount {
                let id = try string(&reader)
                let slot = try string(&reader)
                let model = try string(&reader)
                let tally = try tally(&reader)
                let replyFlags = try reader.byte()
                var reply = UsageLedgerReader.ScannedReply(slot: slot, model: model, tally: tally)
                if replyFlags & (1 << 0) != 0 { reply.timing = try timing(&reader) }
                if replyFlags & (1 << 1) != 0 { reply.runningTotal = try string(&reader) }
                if replyFlags & (1 << 2) != 0 { reply.fromFork = replyFlags & (1 << 3) != 0 }
                read[id] = reply
            }
            replies = read
        }

        var runningTotals: [String]?
        if flags & (1 << 6) != 0 {
            let totalCount = try reader.count()
            var read: [String] = []
            read.reserveCapacity(totalCount)
            for _ in 0..<totalCount { read.append(try string(&reader)) }
            runningTotals = read
        }

        return FileCache.Entry(
            stamp: stamp, days: days, title: title, cwd: cwd, isReview: isReview,
            timings: timings, replies: replies, runningTotals: runningTotals
        )
    }

    private static func tally(_ reader: inout Reader) throws -> TokenTally {
        var tally = TokenTally()
        tally.input = try reader.i64()
        tally.cacheWrite = try reader.i64()
        tally.cacheRead = try reader.i64()
        tally.output = try reader.i64()
        tally.cacheWrite1h = try reader.i64()
        tally.repliesWithoutCacheFields = try reader.i64()
        let bandCount = try reader.count()
        if bandCount > 0 {
            var bands: [Int: TokenTally] = [:]
            bands.reserveCapacity(bandCount)
            for _ in 0..<bandCount {
                let band = try reader.i64()
                bands[band] = try self.tally(&reader)
            }
            tally.contextBands = bands
        }
        return tally
    }

    private static func timing(_ reader: inout Reader) throws -> ReplyTiming {
        var timing = ReplyTiming()
        timing.outputTokens = try reader.i64()
        timing.seconds = try reader.f64()
        timing.replies = try reader.i64()
        timing.firstTokenSeconds = try reader.f64()
        timing.firstTokenTurns = try reader.i64()
        return timing
    }

    // MARK: - Bytes

    /// Each string once, numbered in the order first seen.
    private struct StringTable {
        var list: [String] = []
        var numbers: [String: Int] = [:]
        var byteCount = 0

        mutating func index(of string: String) -> Int {
            if let number = numbers[string] { return number }
            let number = list.count
            numbers[string] = number
            list.append(string)
            byteCount += string.utf8.count + 4
            return number
        }
    }

    private struct Writer {
        var bytes: [UInt8] = []

        mutating func u32(_ value: Int) {
            withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) { bytes.append(contentsOf: $0) }
        }

        mutating func i64(_ value: Int) {
            withUnsafeBytes(of: Int64(value).littleEndian) { bytes.append(contentsOf: $0) }
        }

        mutating func f64(_ value: Double) {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }
    }

    /// Bounds-checked: a short or damaged file throws rather than reading
    /// past its end.
    private struct Reader {
        let raw: UnsafeRawBufferPointer
        var offset = 0

        init(_ raw: UnsafeRawBufferPointer) {
            self.raw = raw
        }

        var isAtEnd: Bool { offset == raw.count }

        mutating func take(_ count: Int) throws -> UnsafeRawBufferPointer {
            guard count >= 0, count <= raw.count - offset else { throw Malformed() }
            defer { offset += count }
            return UnsafeRawBufferPointer(rebasing: raw[offset..<offset + count])
        }

        mutating func byte() throws -> UInt8 {
            try take(1)[0]
        }

        /// A count or a string's number, which cannot be more than the bytes
        /// left could hold.
        mutating func count() throws -> Int {
            let value = Int(UInt32(littleEndian: try take(4).loadUnaligned(as: UInt32.self)))
            guard value <= raw.count else { throw Malformed() }
            return value
        }

        mutating func i64() throws -> Int {
            Int(Int64(littleEndian: try take(8).loadUnaligned(as: Int64.self)))
        }

        mutating func f64() throws -> Double {
            Double(bitPattern: UInt64(littleEndian: try take(8).loadUnaligned(as: UInt64.self)))
        }
    }
}
