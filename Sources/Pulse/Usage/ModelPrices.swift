import Foundation

/// What one model charges, per million tokens.
///
/// Straight from models.dev, which publishes the providers' own list prices.
/// Missing rates stay `nil` rather than falling back to a plausible number:
/// a model Pulse has no price for is left out of the total and counted
/// separately, so a figure on screen is never part guesswork.
struct ModelPrice: Codable, Sendable, Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double?
    let cacheWrite: Double?
    /// How the provider writes the model's name — "GPT-5.6 Sol" rather than
    /// `gpt-5.6-sol`. Optional so an older cached file still decodes.
    let name: String?
}

/// The price list, fetched from models.dev and kept on disk.
///
/// models.dev covers every provider in one 4MB document; only the two Pulse
/// reads usage for are kept, which leaves a few kilobytes to cache. It is
/// re-fetched once a day — list prices change on the order of months, and the
/// cached copy is what makes the settings pane work on a plane.
///
/// Prices are the base rates. Some models charge more above a long-context
/// threshold, and that tier isn't applied here: the logs record how many
/// tokens a request used, not how full its context was, so honouring the tier
/// would mean guessing which side of the line each request fell on.
actor ModelPrices {
    static let shared = ModelPrices()

    private var table: [String: ModelPrice]?
    private var inFlight: Task<[String: ModelPrice], Never>?

    /// Providers whose models Pulse can see usage for, **in priority order**.
    ///
    /// It was these two alone, which was right while only Claude Code and
    /// Codex were read — and wrong the moment anything else was, because the
    /// agents run whatever their plan sells. Four of the seven agents on this
    /// machine came out at $0.00 for no better reason than that their vendor
    /// was not in this list, and so did every third-party model the two CLIs
    /// were pointed at.
    ///
    /// **Model ids are unique within a provider and not across all 213 of
    /// them**, which is why this is a list rather than the whole document.
    /// Across the fourteen here there are 22 collisions and 21 of them are
    /// `github-copilot` re-listing somebody else's model — it is a reseller,
    /// and Pulse reads no Copilot transcripts, so it is left out. The one real
    /// collision is `glm-5.2`, sold by both Zhipu and Alibaba; the order below
    /// settles it, and the rates are within a rounding error of each other
    /// anyway.
    private static let providers = [
        "anthropic", "openai", "xai", "moonshotai", "zhipuai", "minimax",
        "deepseek", "google", "xiaomi", "alibaba", "mistral", "meta",
    ]

    private static let source = URL(string: "https://models.dev/api.json")!
    private static let refreshAfter: TimeInterval = 24 * 3600

    func prices() async -> [String: ModelPrice] {
        if let table { return table }

        if let cached = Self.readCache(), cached.age < Self.refreshAfter {
            table = cached.prices
            return cached.prices
        }

        // One download even if several panes ask at once.
        if let inFlight { return await inFlight.value }

        let task = Task<[String: ModelPrice], Never> {
            if let fetched = await Self.download() {
                Self.writeCache(fetched)
                return fetched
            }
            // Offline: an old copy beats no prices at all, since list prices
            // barely move.
            return Self.readCache()?.prices ?? [:]
        }
        inFlight = task

        let result = await task.value
        inFlight = nil
        if !result.isEmpty { table = result }
        return result
    }

    // MARK: - Network

    private static func download() async -> [String: ModelPrice]? {
        var request = URLRequest(url: source)
        request.timeoutInterval = 30

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var prices: [String: ModelPrice] = [:]
        for provider in providers {
            let models = (root[provider] as? [String: Any])?["models"] as? [String: Any] ?? [:]
            for (id, model) in models {
                // First provider in the list wins a shared id.
                guard prices[id] == nil else { continue }
                guard
                    let cost = (model as? [String: Any])?["cost"] as? [String: Any],
                    let input = number(cost["input"]),
                    let output = number(cost["output"])
                else { continue }

                prices[id] = ModelPrice(
                    input: input,
                    output: output,
                    cacheRead: number(cost["cache_read"]),
                    cacheWrite: number(cost["cache_write"]),
                    name: (model as? [String: Any])?["name"] as? String
                )
            }
        }

        return prices.isEmpty ? nil : prices
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    // MARK: - Spelling

    /// The price for a model id, allowing for the fact that the agents do not
    /// all spell one the same way.
    ///
    /// **Aliases, not fuzzy matching.** Every rule here is one product's known
    /// habit, written out, because the failure mode of a loose match is a
    /// model priced at another model's rate — a wrong number that looks right.
    /// A lookup that still misses is left unpriced, which is what the footnote
    /// on the page counts.
    static func price(for model: String, in table: [String: ModelPrice]) -> ModelPrice? {
        if let exact = table[model] { return exact }

        // MiniMax writes `MiniMax-M3` and the agents that call it write
        // `minimax-m3`. Case is the only difference.
        let lowered = model.lowercased()
        if let match = table.first(where: { $0.key.lowercased() == lowered })?.value { return match }

        for candidate in aliases(for: model) {
            if let match = table[candidate] { return match }
            let folded = candidate.lowercased()
            if let match = table.first(where: { $0.key.lowercased() == folded })?.value { return match }
        }

        return nil
    }

    /// Spellings to try for one id, most specific first.
    static func aliases(for model: String) -> [String] {
        var candidates: [String] = []

        // Grok Build tags its own build of a model: `grok-4.6-build` is
        // xAI's `grok-4.6`, at xAI's rates.
        if model.hasSuffix("-build"), model != "grok-build-0.1" {
            candidates.append(String(model.dropLast("-build".count)))
        }

        // Devin's CLI writes the version with dashes and an effort on the end:
        // `gpt-5-6-sol-medium` is OpenAI's `gpt-5.6-sol`.
        for effort in ["-medium", "-high", "-low", "-minimal"] where model.hasSuffix(effort) {
            let base = String(model.dropLast(effort.count))
            candidates.append(base)
            candidates.append(Self.dotted(base))
        }
        candidates.append(Self.dotted(model))

        // A context window on the end is the same model with more room:
        // `k3-256k` is `kimi-k3`, and it is billed at `k3`'s rates.
        if let tag = model.range(of: "-[0-9]+[kKmM]$", options: .regularExpression) {
            let base = String(model[model.startIndex..<tag.lowerBound])
            candidates.append(base)
            candidates.append(contentsOf: Self.aliases(for: base))
        }

        // Kimi's CLI abbreviates: `k2p6` is `kimi-k2.6`, `k3` is `kimi-k3`.
        if model.first == "k", model.dropFirst().allSatisfy({ $0.isNumber || $0 == "p" }) {
            candidates.append("kimi-" + model.replacingOccurrences(of: "p", with: "."))
        }

        return candidates.filter { $0 != model }
    }

    /// `gpt-5-6-sol` → `gpt-5.6-sol`: a digit, a dash, a digit is a version
    /// number somebody spelled with the wrong separator. Two words joined by a
    /// dash are left alone.
    private static func dotted(_ model: String) -> String {
        var out = ""
        let characters = Array(model)
        for (index, character) in characters.enumerated() {
            if character == "-", index > 0, index + 1 < characters.count,
               characters[index - 1].isNumber, characters[index + 1].isNumber {
                out.append(".")
            } else {
                out.append(character)
            }
        }
        return out
    }

    // MARK: - Cache

    private struct Cache: Codable {
        let fetchedAt: Date
        let prices: [String: ModelPrice]

        var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
    }

    /// The `2` is the stored shape. Model names were added to it, and a file
    /// written before that decodes fine with every name missing — a cache
    /// that is quietly a little bit wrong is worse than one that misses.
    private static var cacheFile: URL {
        // **The number is the stored shape and the table's own reach.** It went
        // to `3` when the provider list grew from two vendors to twelve: a
        // cached `2` still decodes perfectly and holds only Anthropic's and
        // OpenAI's models, so every other vendor would stay unpriced for a day
        // — and then for another day, because the cache is rewritten on the
        // same schedule whatever is in it.
        PulseStorage.directory.appending(path: "model-prices-3.json")
    }

    private static func readCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func writeCache(_ prices: [String: ModelPrice]) {
        PulseStorage.prepare()
        guard let data = try? JSONEncoder().encode(Cache(fetchedAt: Date(), prices: prices)) else { return }
        try? data.write(to: cacheFile, options: .atomic)
    }
}

/// Where Pulse keeps the things too big for `UserDefaults`.
enum PulseStorage {
    static let directory: URL = URL.applicationSupportDirectory.appending(path: "Pulse")

    static func prepare() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Files left behind by earlier cache formats.
    ///
    /// Renaming the file is the right way to invalidate a cache whose shape
    /// changed — the alternative, reusing the name, leaves old entries parsing
    /// as nothing at all, silently. But it does mean the superseded file sits
    /// in the user's Application Support forever unless something takes it
    /// away, so this does. Add a name here whenever a cache is versioned up.
    private static let superseded = [
        "ledger-claudeCode.json",   // day buckets, before quarter-hours
        "ledger-codex.json",
        "model-prices.json"         // before model display names were kept
    ]

    static func removeSupersededFiles() {
        for name in superseded {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
