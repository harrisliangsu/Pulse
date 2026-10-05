import Foundation
import Testing

/// Every bundled mark has to be drawable by CoreSVG, which `NSImage` uses.
///
/// SVG allows an arc's two flags to run into the next number — `a14 14 0 01-4.4-3`
/// is large-arc 0, sweep 1, then x -4.4. CoreSVG rejects that ("A/a command was
/// given the wrong number of floats") and draws the path only up to it: Gemini's
/// star came out as a sliver in the Token spend pane, and nine more marks lost
/// pieces. The Lobe Icons sources write arcs that way, so a mark added from them
/// has to have its arcs spelled out (`0 0 1 -4.4 -3`).
@Suite("Icon paths")
struct IconPathTests {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/Pulse/Resources")

    /// The arcs in a path whose flags are not each followed by a separator.
    static func packedArcFlags(in d: String) -> Int {
        let chars = Array(d)
        var packed = 0
        var i = 0
        var inArc = false
        var argument = 0
        func skipSeparators() { while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i].isNewline { i += 1 } }
        func number() {
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                i += 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
                while i < chars.count, chars[i].isNumber { i += 1 }
            }
        }
        while i < chars.count {
            skipSeparators()
            guard i < chars.count else { break }
            if chars[i].isLetter, chars[i] != "e", chars[i] != "E" {
                inArc = chars[i] == "a" || chars[i] == "A"
                argument = 0
                i += 1
                continue
            }
            if inArc, argument % 7 == 3 || argument % 7 == 4 {
                // A flag is one character, and something must separate it from
                // what follows unless a command letter does.
                i += 1
                if i < chars.count, !(chars[i] == " " || chars[i] == "," || chars[i].isLetter) { packed += 1 }
            } else {
                let start = i
                number()
                if i == start { i += 1 }
            }
            argument += 1
        }
        return packed
    }

    @Test("Arc flags are spelled out in every bundled mark")
    func arcFlagsAreSeparated() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "svg" }
        #expect(!files.isEmpty)
        let path = try NSRegularExpression(pattern: #"\sd="([^"]*)""#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in path.matches(in: text, range: range) {
                guard let d = Range(match.range(at: 1), in: text).map({ String(text[$0]) }) else { continue }
                #expect(Self.packedArcFlags(in: d) == 0, "\(file.lastPathComponent) has packed arc flags")
            }
        }
    }

    @Test("The check catches a packed flag and passes a spelled-out one")
    func detector() {
        // Both flags run on: "0" into "1", and "1" into "-4.4".
        #expect(Self.packedArcFlags(in: "M0 0a14.1 14.1 0 01-4.4-3z") == 2)
        #expect(Self.packedArcFlags(in: "M0 0a14.1 14.1 0 0 1 -4.4 -3z") == 0)
        #expect(Self.packedArcFlags(in: "M0 0 L10 10 C1 2 3 4 5 6") == 0)
    }
}
