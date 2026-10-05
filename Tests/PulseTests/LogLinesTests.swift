import Foundation
import Testing
@testable import Pulse

@Suite("Streaming log bytes")
struct LogLinesTests {
    @Test("Disk chunks preserve exact bytes, and returned lines outlive their iterator",
          arguments: [1, 2, 7, 64, 65_536])
    func bytes(chunkSize: Int) throws {
        let root = URL.temporaryDirectory.appending(path: "PulseLogLines-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "bytes.log")
        let expected = [
            Data("first\r".utf8), Data([0x0d]), Data([0, 0xff, 0x80]),
            Data(String(repeating: "数🙂", count: 20_000).utf8), Data("last".utf8)
        ]
        var input = Data([0x0a, 0x0a])
        for (index, line) in expected.enumerated() {
            input.append(line)
            if index < expected.count - 1 { input.append(contentsOf: [0x0a, 0x0a]) }
        }
        try input.write(to: file)
        let lines = Array(LogLines(at: file, chunkSize: chunkSize))
        try FileManager.default.removeItem(at: file)
        #expect(lines == expected)
    }

    @Test("In-memory slices need not start at zero; EOF and blank lines match disk semantics")
    func slicedData() {
        for suffix in ["", "\n", "\n\n"] {
            let input = Data(("prefix\nalpha\n\nbeta" + suffix).utf8).dropFirst(6)
            #expect(input.startIndex != 0)
            let iterator = LogLines(data: input).makeIterator()
            let first = iterator.next()
            #expect(iterator.next() == Data("beta".utf8))
            #expect(iterator.next() == nil)
            #expect(iterator.next() == nil)
            #expect(first == Data("alpha".utf8))
        }
        for input in [Data(), Data([0x0a]), Data([0x0a, 0x0a])] {
            #expect(Array(LogLines(data: input)).isEmpty)
        }
    }

    @Test("Iterators have independent positions and retained slices survive later reads")
    func independentIterators() {
        let lines = LogLines(data: Data("one\ntwo\nthree".utf8))
        let first = lines.makeIterator()
        let second = lines.makeIterator()
        let retained = first.next()
        #expect(first.next() == Data("two".utf8))
        #expect(second.next() == retained)
        #expect(first.next() == Data("three".utf8))
        #expect(first.next() == nil)
        #expect(second.next() == Data("two".utf8))
        #expect(retained == Data("one".utf8))
    }
}
