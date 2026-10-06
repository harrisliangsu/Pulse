import Foundation
import Testing
@testable import Pulse

/// Which bundled mark a model's name gets on the payback card, and that none is
/// guessed for a name the app has no mark for.
@Suite("Recap vendor marks")
struct RecapVendorMarkTests {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/Pulse/Resources")

    @Test("A model's name finds its maker's mark")
    func knownVendors() {
        let expected: [(String, String)] = [
            ("Claude Opus 5", "claude"), ("Claude Sonnet 4.6", "claude"), ("claude-haiku-4-5", "claude"),
            ("GPT-6 Astra", "openai"), ("gpt-5.6-codex", "openai"), ("o3-mini", "openai"), ("o4", "openai"),
            ("Gemini 3 Pro", "gemini"), ("GLM-5", "zai"), ("Kimi K3", "kimi"), ("DeepSeek V4", "deepseek"),
            ("Qwen3-Coder", "qwen"), ("Mistral Large", "mistral"), ("Codestral", "mistral"),
            ("MiniMax M3", "minimax"), ("Grok 5", "grok"), ("Moonshot v1", "moonshot"),
        ]
        for (name, resource) in expected {
            #expect(RecapVendorMark.resource(forModel: name) == resource, "\(name)")
        }
    }

    @Test("A name with no mark in the app gets none, and the monogram is its first letter")
    func unknownVendors() {
        #expect(RecapVendorMark.resource(forModel: "Llama 4") == nil)
        #expect(RecapVendorMark.resource(forModel: "Opaque 1") == nil)
        #expect(RecapVendorMark.resource(forModel: "") == nil)
        #expect(RecapVendorMark.monogram(for: "llama 4") == "L")
        #expect(RecapVendorMark.monogram(for: "  -7B") == "7")
        #expect(RecapVendorMark.monogram(for: "") == "•")
    }

    @Test("Every mark the table names ships in the bundle")
    func marksExist() {
        for resource in RecapVendorMark.resources {
            let file = Self.resources.appending(path: "\(resource).svg")
            #expect(FileManager.default.fileExists(atPath: file.path), "\(resource).svg")
        }
    }
}
