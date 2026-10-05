// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.

/// One immutable price table, indexed once for a read. Memoizes misses too:
/// an unpublished model can occur in thousands of records. No process-global
/// cache can carry a missing or outdated rate into the next price snapshot.
struct ModelPriceLookup {
    private struct Key: Hashable {
        let model: String
        let vendor: String?
    }

    private let table: [String: ModelPrice]
    private var folded: [String: ModelPrice]?
    private var resolved: [Key: ModelPrice?] = [:]

    init(_ table: [String: ModelPrice]) {
        self.table = table
    }

    mutating func price(for model: String, vendor: String? = nil) -> ModelPrice? {
        // Exact first-party ids already have a constant-time index. A read
        // containing only those ids needs neither folding nor memo entries.
        if let price = table[model] { return price }
        let key = Key(model: model, vendor: vendor)
        if let answer = resolved[key] { return answer }
        if folded == nil {
            var index: [String: ModelPrice] = [:]
            for (id, price) in table {
                let lower = id.lowercased()
                if index[lower] == nil { index[lower] = price }
            }
            folded = index
        }
        let answer = ModelPrices.resolve(
            for: model, vendor: vendor, exact: { table[$0] }, folded: { folded?[$0] }
        )
        // updateValue stores an explicit nil; subscript assignment would remove it.
        resolved.updateValue(answer, forKey: key)
        return answer
    }
}
