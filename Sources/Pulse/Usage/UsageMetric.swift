// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A reading that is not a limit: a figure with a name and a unit, and
/// optionally the series it came from. An extension's `metrics[]` — a relay's
/// time to first token, its output rate, its success rate (issue #80).
///
/// **Everything here is what the program stated.** The label and the unit are
/// its own words, never translated; the value is drawn as given, rounded for
/// display and nothing else; the history is its points, in time order, with no
/// point added between them. Pulse does not convert units, does not average,
/// and does not judge whether a figure is good — a slow first token and a fast
/// output rate are drawn in the same colour, because only the program knows
/// which way is better.
///
/// **Never a ring.** A metric has no ceiling, so it neither drives the ring nor
/// counts as a reading on its own: an extension still needs a limit or a
/// balance for the ring to have anything to draw.
struct UsageMetric: Identifiable, Equatable, Codable, Sendable {
    /// The program's own id when it gave one, else the metric's place in the
    /// list. Identity for SwiftUI and for `--json`.
    let id: String
    let label: String
    let value: Double
    /// "ms", "tok/s", "%". Absent when the figure is a plain count.
    let unit: String?
    /// The series, oldest first. Fewer than two points draw no chart.
    var history: [Point] = []

    struct Point: Equatable, Codable, Sendable {
        let at: Date
        let value: Double
    }

    /// Whether there is a line to draw: two points at least, and not all at
    /// one moment.
    var hasTrend: Bool {
        guard let first = history.first, let last = history.last else { return false }
        return history.count >= 2 && last.at > first.at
    }

    /// "320 ms", "87.4 tok/s", "99.2%".
    var valueText: String { text(for: value) }

    /// A figure in this metric's unit, formatted in the reader's language.
    func text(for figure: Double) -> String {
        let number = Self.number(figure)
        guard let unit else { return number }
        // A percent sign sits against its number in every language Pulse
        // ships; any other unit is a word, and gets a space.
        return unit == "%" ? number + unit : number + " " + unit
    }

    /// Rounded to two places, which is display and not a different figure —
    /// except that a figure too small for two places keeps two significant
    /// digits rather than reading as a zero the program never said.
    static func number(_ figure: Double, locale: Locale = LocalizationSource.locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if figure != 0, abs(figure) < 0.01 {
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 2
        } else {
            formatter.maximumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: figure)) ?? String(figure)
    }
}
