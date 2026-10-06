// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

// The pieces the redesigned opener, calendar, timetable and payback cards
// share: tiles, section heads, rings and the brand marks. Flat fills and
// strokes only, so `ImageRenderer` draws all of it.

extension View {
    /// One line that scales down to `floor` of its size where it is too wide,
    /// and is never squeezed vertically: a stack that is a little short gives
    /// the deficit to whatever can shrink, and a label with a scale floor can,
    /// all the way to the floor, for no visible reason.
    func recapFit(_ floor: CGFloat = 0.6) -> some View {
        lineLimit(1)
            .minimumScaleFactor(floor)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A thin rule across the card, in ink or in the paler grey.
struct RecapHairline: View {
    var strong = false

    var body: some View {
        Rectangle()
            .fill(strong ? RecapColor.ink : RecapColor.rule)
            .frame(height: strong ? 2 : 1)
    }
}

/// A section's title, and a small note at the right.
struct RecapSectionHead: View {
    let title: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.recap(22, .bold))
                .recapFit(0.7)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let note {
                Text(note)
                    .font(.recap(18))
                    .foregroundStyle(RecapColor.tertiary)
                    .recapFit(0.6)
            }
        }
    }
}

/// The ground of a tile.
enum RecapTileTone { case white, ink, lime }

/// A rounded tile: white with a hairline, ink, or lime.
struct RecapTile<Content: View>: View {
    var tone: RecapTileTone = .white
    var radius: CGFloat = 20
    var padding = EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            }
            .overlay {
                if tone == .white {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(RecapColor.hairline, lineWidth: 1)
                }
            }
    }

    private var fill: Color {
        switch tone {
        case .white: RecapColor.white
        case .ink: RecapColor.ink
        case .lime: RecapColor.lime
        }
    }
}

/// The colours a tile's text takes in each tone.
extension RecapTileTone {
    /// A small caption.
    var caption: Color {
        switch self {
        case .white: RecapColor.secondary
        case .ink: RecapColor.paper.opacity(0.6)
        case .lime: RecapColor.limeInk
        }
    }

    /// A line of detail under a figure.
    var detail: Color {
        switch self {
        case .white: RecapColor.tertiary
        case .ink: RecapColor.paper.opacity(0.6)
        case .lime: RecapColor.limeInk
        }
    }
}

// MARK: - Marks

/// A bundled brand mark in one flat colour (a template image, tinted).
struct RecapBrandMark: View {
    let resource: String
    let side: CGFloat
    let color: Color

    var body: some View {
        LobeIconView(resource: resource, size: side)
            .foregroundStyle(color)
    }
}

/// A brand mark, or — for a name with no mark in the app — the name's first
/// letter in the same square, in the same colour.
struct RecapGlyph: View {
    let resource: String?
    let name: String
    let side: CGFloat
    let color: Color

    var body: some View {
        Group {
            if let resource {
                RecapBrandMark(resource: resource, side: side, color: color)
            } else {
                Text(verbatim: RecapVendorMark.monogram(for: name))
                    .font(.recap(side * 0.8, .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .frame(width: side, height: side)
            }
        }
    }
}

/// The square a brand mark sits on: ink with a lime mark for the lead, white
/// with a hairline otherwise.
struct RecapMarkTile: View {
    let resource: String?
    let name: String
    let side: CGFloat
    var lead = false

    var body: some View {
        let radius = side / 4
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(lead ? RecapColor.ink : RecapColor.white)
            if !lead {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(RecapColor.hairline, lineWidth: 1)
            }
            RecapGlyph(resource: resource, name: name, side: side * 0.53, color: lead ? RecapColor.lime : RecapColor.ink)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Rings and chains

/// A ring of equal segments, the first `filled` of them in ink. Segments are
/// butt-ended arcs with a small gap, drawn from the top.
struct RecapSegmentRing: View {
    let filled: Int
    let segments: Int
    var lineWidth: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            guard segments > 0 else { return }
            let radius = min(size.width, size.height) / 2 - lineWidth / 2 - 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let step = 360.0 / Double(segments)
            for index in 0..<segments {
                var arc = Path()
                arc.addArc(center: center, radius: radius,
                           startAngle: .degrees(Double(index) * step - 90 + 2),
                           endAngle: .degrees(Double(index + 1) * step - 90 - 2), clockwise: false)
                context.stroke(arc, with: .color(index < filled ? RecapColor.ink : Color(recap: 0xE2E2DB)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
    }
}

/// A run of days drawn as a chain of small squares, the run's own in lime
/// with an ink edge.
struct RecapStreakChain: View {
    let chain: RecapInsights.Chain

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(chain.days.indices, id: \.self) { index in
                    let inRun = chain.run.contains(index)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(inRun ? RecapColor.lime : RecapColor.heatZero)
                        .overlay {
                            if inRun {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(RecapColor.ink, lineWidth: 2)
                            }
                        }
                        .frame(width: 22, height: 22)
                }
            }
            HStack(spacing: 8) {
                Text(verbatim: RecapFormat.shortDay(chain.first))
                Rectangle().fill(RecapColor.rule).frame(height: 1)
                Text(verbatim: RecapFormat.shortDay(chain.last))
            }
            .font(.recap(14, .regular, mono: true))
            .foregroundStyle(RecapColor.tertiary)
            .lineLimit(1)
        }
    }
}
