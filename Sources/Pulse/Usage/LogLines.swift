// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Darwin
import Foundation

/// Replayable, synchronous line IO with a cancellation checkpoint per read and
/// per line. IO buffers hold a 64 KiB chunk plus any cross-chunk line, never
/// the file. A line within a chunk shares its storage until the caller releases it.
/// A fresh iterator owns its descriptor; breaking a loop closes it on release.
struct LogLines: Sequence {
    private let file: URL?
    private let data: Data?
    private let chunkSize: Int

    init(at file: URL, chunkSize: Int = 64 * 1024) {
        self.file = file
        self.data = nil
        self.chunkSize = Swift.max(1, chunkSize)
    }

    /// The fixture parsers share the exact same line semantics as disk reads.
    init(data: Data) {
        self.file = nil
        self.data = data
        self.chunkSize = 64 * 1024
    }

    func makeIterator() -> Iterator { Iterator(file: file, data: data, chunkSize: chunkSize) }

    func forEachLine(_ body: (Data) -> Void) {
        for line in self { autoreleasepool { body(line) } }
    }

    final class Iterator: IteratorProtocol {
        private var handle: FileHandle?
        private var chunk: Data
        private var offset: Int
        private let chunkSize: Int

        init(file: URL?, data: Data?, chunkSize: Int) {
            handle = Task.isCancelled ? nil : file.flatMap { try? FileHandle(forReadingFrom: $0) }
            chunk = data ?? Data()
            offset = chunk.startIndex
            self.chunkSize = chunkSize
        }

        deinit { try? handle?.close() }

        func next() -> Data? {
            var line = Data()
            while !Task.isCancelled {
                if offset < chunk.endIndex {
                    if let end = newline() {
                        let start = offset
                        offset = end + 1
                        if line.isEmpty {
                            if start == end { continue }
                            // Data's slice owns the storage; no borrowed pointer
                            // escapes and the next read cannot overwrite it.
                            return chunk[start..<end]
                        }
                        line.append(contentsOf: chunk[start..<end])
                        return line
                    }
                    line.append(contentsOf: chunk[offset...])
                    offset = chunk.endIndex
                }
                guard let handle else { return line.isEmpty ? nil : line }
                let bytes = autoreleasepool { try? handle.read(upToCount: chunkSize) }
                guard let bytes, !bytes.isEmpty else {
                    close()
                    return line.isEmpty ? nil : line
                }
                chunk = bytes
                offset = chunk.startIndex
            }
            close()
            return nil
        }

        /// Search contiguous bytes with libc's vectorized scanner instead of
        /// visiting every byte through Data's Collection conformance. Keep
        /// pointer offsets separate from Data indices (a slice may start > 0).
        private func newline() -> Int? {
            let start = chunk.startIndex
            let consumed = offset - start
            return chunk.withUnsafeBytes { bytes -> Int? in
                guard let base = bytes.baseAddress,
                      let found = memchr(base.advanced(by: consumed), 0x0a, bytes.count - consumed)
                else { return nil }
                return start + base.distance(to: UnsafeRawPointer(found))
            }
        }

        private func close() {
            try? handle?.close()
            handle = nil
            chunk = Data()
            offset = 0
        }
    }
}
