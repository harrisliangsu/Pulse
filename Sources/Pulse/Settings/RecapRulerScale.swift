// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The payback card's ruler: it ends just past the larger figure, in round
/// steps — labels at 1, 2, 2.5 or 5 times a power of ten, with a tick halfway
/// between each pair.
struct RecapRulerScale: Equatable, Sendable {
    let step: Double
    let subdivisions: Int
    let ticks: Int

    /// The value at the ruler's far end.
    var maximum: Double { Double(ticks) * step / Double(subdivisions) }

    init(for value: Double) {
        let target = max(value, 0.01) / 4
        let magnitude = pow(10, floor(log10(target)))
        step = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * magnitude }.first { $0 >= target } ?? 10 * magnitude
        subdivisions = 2
        ticks = max(Int((value * 1.04 / step).rounded(.up)), 1) * 2
    }
}
