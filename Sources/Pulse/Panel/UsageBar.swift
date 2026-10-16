// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// A limit's bar, continuous or segmented (`UsageBarStyle`), on the card and
/// in the menu.
///
/// Segmented is a row of thin ticks across the same width, lit up to the
/// fraction: every tick the same, the gaps the same, as many as fit. A
/// fraction above zero always lights at least one, so a limit just touched
/// does not read as untouched; a fraction short of whole never lights the
/// last, so a limit nearly spent does not read as spent.
struct UsageBar: View {
    let fraction: Double
    let accent: Color
    let track: Color
    let style: UsageBarStyle
    var scale: CGFloat = 1

    /// The heights the two styles are drawn at, before `PanelMetrics.scale`.
    nonisolated static let continuousHeight: CGFloat = 6
    nonisolated static let segmentedHeight: CGFloat = 12

    nonisolated static let tickWidth: CGFloat = 2.5
    nonisolated static let tickGap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            switch style {
            case .continuous:
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(accent).frame(width: proxy.size.width * clamped)
                }
            case .segmented:
                let ticks = Self.ticks(width: proxy.size.width, fraction: clamped, scale: scale)
                HStack(spacing: Self.tickGap * scale) {
                    ForEach(0..<ticks.count, id: \.self) { index in
                        Capsule()
                            .fill(index < ticks.lit ? accent : track)
                            .frame(width: Self.tickWidth * scale)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    /// How many ticks fit in `width`, and how many of them `fraction` lights.
    nonisolated static func ticks(width: CGFloat, fraction: Double, scale: CGFloat = 1) -> (count: Int, lit: Int) {
        let step = (tickWidth + tickGap) * scale
        let count = max(Int(((width + tickGap * scale) / step).rounded(.down)), 1)
        let clamped = min(max(fraction, 0), 1)
        var lit = Int((clamped * Double(count)).rounded())
        if clamped > 0 { lit = max(lit, 1) }
        if clamped < 1 { lit = min(lit, count - 1) }
        return (count, clamped >= 1 ? count : lit)
    }
}
