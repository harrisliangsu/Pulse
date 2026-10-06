// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Which bundled brand mark goes beside a model's name on the recap cards.
///
/// A model's display name says who made it ("Claude Opus 5", "GPT-6 Astra",
/// "GLM-5"), and the marks are the ones the app already ships for providers
/// and agents. **No guess for a name that is none of these**: the card draws a
/// monogram of the first letter rather than borrow another company's mark.
enum RecapVendorMark {
    /// Lower-cased fragments of a model name, and the resource they name. The
    /// first row that matches wins, so a more specific fragment comes first.
    private static let table: [(needles: [String], resource: String)] = [
        (["claude", "opus", "sonnet", "haiku"], "claude"),
        (["gpt", "codex", "chatgpt", "davinci"], "openai"),
        (["gemini"], "gemini"),
        (["glm", "zhipu"], "zai"),
        (["kimi"], "kimi"),
        (["moonshot"], "moonshot"),
        (["deepseek"], "deepseek"),
        (["qwen", "qwq"], "qwen"),
        (["mistral", "codestral", "devstral", "magistral", "ministral"], "mistral"),
        (["minimax"], "minimax"),
        (["grok"], "grok"),
        (["doubao"], "volcengine"),
        (["step-"], "stepfun"),
        (["mimo"], "xiaomimimo"),
        (["longcat"], "longcat"),
        (["hunyuan"], "tencent"),
        (["sonar"], "perplexity"),
    ]

    /// The resource name (without `.svg`) for a model's display name or id;
    /// nil where the vendor is not one the app has a mark for.
    static func resource(forModel name: String) -> String? {
        let lower = name.lowercased()
        for row in table where row.needles.contains(where: { lower.contains($0) }) {
            return row.resource
        }
        // OpenAI's o-series: "o3", "o4-mini".
        if lower.range(of: #"^o\d"#, options: .regularExpression) != nil { return "openai" }
        return nil
    }

    /// The letter a monogram tile shows for a name.
    static func monogram(for name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "•"
    }

    /// Every resource name the table can return, for the test that each
    /// ships in the bundle.
    static var resources: Set<String> { Set(table.map(\.resource)) }
}
