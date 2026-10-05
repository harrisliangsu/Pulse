// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Which drawing of the year the "Token activity" section shows. Kept by
/// `AppSettings.spendActivityView`, like the span.
enum ActivityView: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case cumulative

    static let `default` = ActivityView.daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: .localized("Daily")
        case .weekly: .localized("Weekly")
        case .cumulative: .localized("Cumulative")
        }
    }
}

/// The last twelve months of tokens: a grid with a square per day, a bar per
/// week, or the running total.
///
/// **One horizontal scale for all three.** Every view is `activity.columnCount`
/// week columns wide, so the month labels under the plot are the same for each
/// and switching views moves nothing sideways. The columns always fill the
/// row: cells shrink with the pane (down to the 720pt settings window) and
/// grow with it, so a wide window leaves no empty strip on the right.
///
/// **Nothing is invented.** A day before the first record is a placeholder
/// square fainter than a quiet one and a day after today has no cell; a quiet
/// day is a real zero and drawn as one. The pointer reads out
/// the date (or week) and its count the way every other chart in the pane does.
struct TokenActivitySection: View {
    let activity: TokenActivity
    @Binding var view: ActivityView
    var calendar: Calendar = .current

    private static let labelHeight: CGFloat = 13
    /// How far a month label may run past the plot's right edge: inside the
    /// group's 16pt horizontal padding.
    private static let labelOverhang: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized: "Token activity")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 4)
                Spacer(minLength: 12)
                Picker("", selection: $view) {
                    ForEach(ActivityView.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(String.localized("Token activity"))
                .frame(width: 230)
            }

            SettingsGroup {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String.localized("\(TokenCount.short(activity.total)) tokens in the last 12 months"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer(minLength: 8)
                        if view == .daily { legend }
                    }

                    plot
                    monthLabels

                    if activity.hasPartialCounts {
                        Text(localized: "Counts may be incomplete.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String.localized("Token activity"))
                .accessibilityValue(summary)
            }
        }
    }

    // MARK: - Pieces

    private var columns: CGFloat { CGFloat(max(activity.columnCount, 1)) }

    /// What VoiceOver reads for the whole chart: the figures behind the
    /// picture, which a pointer-only read-out cannot give it.
    private var summary: String {
        String.localized(
            "\(SpendFormat.tokens(activity.total)) over the last 12 months, \("\(activity.activeDays)") active days"
        )
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text(localized: "Less")
            ForEach(0..<5, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.fill(step: step))
                    .frame(width: 9, height: 9)
            }
            Text(localized: "More")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    /// A column as wide as the pane allows, and as tall as seven of them: the
    /// grid's own proportions, which the bars and the line borrow.
    private var plot: some View {
        ColumnsLayout(columns: columns, height: nil) {
            GeometryReader { proxy in
                let pitch = proxy.size.width / columns
                switch view {
                case .daily: DailyGrid(activity: activity, pitch: pitch)
                case .weekly: WeeklyBars(activity: activity, pitch: pitch, calendar: calendar)
                case .cumulative: CumulativeLine(activity: activity, pitch: pitch)
                }
            }
        }
    }

    private var monthLabels: some View {
        ColumnsLayout(columns: columns, height: Self.labelHeight) {
            GeometryReader { proxy in
                ForEach(Self.placedMonths(activity.monthMarks(calendar: calendar), width: proxy.size.width, columns: columns), id: \.mark.column) { placed in
                    Text(Self.month(placed.mark.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: placed.x + placed.width / 2, y: Self.labelHeight / 2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Each label left-aligned on its month's first day. The last may run up to
    /// `labelOverhang` into the card's own padding before it is pulled back, so
    /// the running month, which starts in the last columns, does not push into
    /// the month before it. Where a label would still touch the next, the
    /// earlier one goes, so the running month is always named.
    private static func placedMonths(
        _ marks: [TokenActivity.Mark], width: CGFloat, columns: CGFloat
    ) -> [(mark: TokenActivity.Mark, x: CGFloat, width: CGFloat)] {
        let pitch = width / columns
        var placed: [(mark: TokenActivity.Mark, x: CGFloat, width: CGFloat)] = []
        for mark in marks.reversed() {
            let labelWidth = monthWidth(mark.date)
            let x = max(min(CGFloat(mark.position) * pitch, width + labelOverhang - labelWidth), 0)
            if let next = placed.last, x + labelWidth + 4 > next.x { continue }
            placed.append((mark, x, labelWidth))
        }
        return placed.reversed()
    }

    /// The month as the reader's calendar abbreviates it: "11月", "Nov".
    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(LocalizationSource.locale))
    }

    /// Enough width to left-align a label on its column with `position`, which
    /// centres: an over-estimate only shifts the label by a pixel or two.
    private static func monthWidth(_ date: Date) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10)
        return (month(date) as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: - Colour

    /// Quiet is a light neutral; the four steps are the pane's accent at rising
    /// strength, so the chart reads in light and dark mode from the same blue
    /// the other charts use.
    static func fill(step: Int) -> Color {
        switch step {
        case 0: Color.primary.opacity(0.08)
        case 1: Color.accentColor.opacity(0.30)
        case 2: Color.accentColor.opacity(0.52)
        case 3: Color.accentColor.opacity(0.76)
        default: Color.accentColor
        }
    }

    /// A day before the first record: half a quiet day's strength, so the row
    /// is full and the difference still reads.
    static let unrecordedFill = Color.primary.opacity(0.04)

    /// "Oct 6 – 12, 2025", or the one day where a clipped week holds only one.
    static func weekTitle(_ range: ClosedRange<Date>) -> String {
        guard range.lowerBound < range.upperBound else { return SpendFormat.chartDate(range.lowerBound) }
        return (range.lowerBound..<range.upperBound).formatted(
            Date.IntervalFormatStyle().year().month(.abbreviated).day().locale(LocalizationSource.locale)
        )
    }
}

/// A box as wide as the pane offers and as tall as seven columns (or
/// `height`): the grid's own proportions, which the bars and the line borrow.
/// A layout rather than an aspect ratio, which sizes a flexible child from its
/// own ideal and not from the width it was offered. With no finite width on
/// offer it falls back to 13pt a column, the grid's natural size.
private struct ColumnsLayout: Layout {
    let columns: CGFloat
    let height: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = max(offered ?? columns * 13, 0)
        return CGSize(width: width, height: height ?? width * 7 / columns)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

// MARK: - Daily

/// A rounded square for each drawn day, a column for each week.
private struct DailyGrid: View {
    let activity: TokenActivity
    let pitch: CGFloat
    @State private var hovered: Cell?

    struct Cell: Equatable {
        let column: Int
        let row: Int
    }

    private var gap: CGFloat { min(max(pitch * 0.2, 1), 3) }

    private func frame(of cell: Cell) -> CGRect {
        CGRect(x: CGFloat(cell.column) * pitch, y: CGFloat(cell.row) * pitch, width: pitch - gap, height: pitch - gap)
    }

    var body: some View {
        Canvas { context, _ in
            let radius = max((pitch - gap) * 0.24, 1)
            for (column, week) in activity.weeks.enumerated() {
                for (row, day) in week.days.enumerated() {
                    let rect = frame(of: Cell(column: column, row: row))
                    guard let day else {
                        // Before the first record: a fainter square than a
                        // quiet day holds the place and says nothing about it.
                        if week.unrecorded[row] {
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                                with: .color(TokenActivitySection.unrecordedFill)
                            )
                        }
                        continue
                    }
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                        with: .color(TokenActivitySection.fill(step: activity.step(for: day.tokens)))
                    )
                }
            }
            if let hovered {
                context.stroke(
                    Path(roundedRect: frame(of: hovered).insetBy(dx: -0.5, dy: -0.5), cornerRadius: radius, style: .continuous),
                    with: .color(.primary.opacity(0.7)),
                    lineWidth: 1
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onContinuousHover { phase in
            let next: Cell?
            switch phase {
            case .active(let location): next = cell(at: location)
            case .ended: next = nil
            }
            if hovered != next { hovered = next }
        }
        .overlay(alignment: .topLeading) {
            if let hovered, let day = day(at: hovered) {
                GeometryReader { proxy in
                    SideTooltip(anchor: frame(of: hovered), bounds: proxy.size) {
                        ChartTooltipCard(title: SpendFormat.chartDate(day.date), tokens: day.tokens)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: activity) { _, _ in hovered = nil }
        .onDisappear { hovered = nil }
    }

    private func day(at cell: Cell) -> TokenActivity.Day? {
        guard activity.weeks.indices.contains(cell.column) else { return nil }
        return activity.weeks[cell.column].days[cell.row]
    }

    /// The cell under the pointer, or nil in a gap, off the grid or on a day
    /// that is not drawn.
    private func cell(at point: CGPoint) -> Cell? {
        guard pitch > 0, point.x >= 0, point.y >= 0 else { return nil }
        let candidate = Cell(column: Int(point.x / pitch), row: Int(point.y / pitch))
        guard candidate.row < 7, day(at: candidate) != nil else { return nil }
        return candidate
    }
}

/// Places a card beside a rectangle, flipping at the right edge and clamping
/// inside the plot, like `ChartHoverOverlay`'s own tooltip.
private struct SideTooltip<Content: View>: View {
    let anchor: CGRect
    let bounds: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        Placement(anchor: anchor) { content }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
    }

    private struct Placement: Layout {
        let anchor: CGRect

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard let card = subviews.first else { return }
            let size = card.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let gap: CGFloat = 8
            let preferredX = anchor.maxX + gap + size.width <= bounds.width
                ? anchor.maxX + gap
                : anchor.minX - gap - size.width
            let x = min(max(preferredX, 0), max(bounds.width - size.width, 0))
            let y = min(max(anchor.midY - size.height / 2, 0), max(bounds.height - size.height, 0))
            card.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

// MARK: - Weekly

/// One bar per week, over the same columns as the grid.
private struct WeeklyBars: View {
    let activity: TokenActivity
    let pitch: CGFloat
    let calendar: Calendar

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let peak = CGFloat(max(activity.weeks.map(\.tokens).max() ?? 1, 1))
            let width = max(pitch * 0.72, 1)

            Canvas { context, _ in
                for (column, week) in activity.weeks.enumerated() where week.hasData {
                    let tokens = week.tokens
                    // A week with any work keeps a visible stub; a quiet week is
                    // a hairline, so quiet reads as quiet and not as missing.
                    let barHeight = tokens > 0 ? max((height - 1) * CGFloat(tokens) / peak, 3) : 2
                    let rect = CGRect(
                        x: (CGFloat(column) + 0.5) * pitch - width / 2, y: height - barHeight,
                        width: width, height: barHeight
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: min(width, 5) / 2, style: .continuous),
                        with: .color(tokens > 0 ? .accentColor : .primary.opacity(0.08))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .overlay {
                ChartHoverOverlay(samples: activity.weeks.enumerated().compactMap { column, week in
                    guard let range = week.range else { return nil }
                    return .init(
                        x: (CGFloat(column) + 0.5) * pitch,
                        title: TokenActivitySection.weekTitle(range),
                        tokens: week.tokens
                    )
                })
            }
        }
    }
}

// MARK: - Cumulative

/// The running total from the first record to today, as a line over a wash.
private struct CumulativeLine: View {
    let activity: TokenActivity
    let pitch: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let points = activity.points
            let total = CGFloat(max(points.last?.running ?? 1, 1))

            Canvas { context, _ in
                guard let first = points.first, let last = points.last else { return }
                func y(_ running: Int) -> CGFloat { height - 1 - (height - 3) * CGFloat(running) / total }

                var line = Path()
                line.move(to: CGPoint(x: first.position * pitch, y: height - 1))
                for point in points { line.addLine(to: CGPoint(x: point.position * pitch, y: y(point.running))) }

                var area = line
                area.addLine(to: CGPoint(x: last.position * pitch, y: height - 1))
                area.closeSubpath()
                context.fill(area, with: .color(Color.accentColor.opacity(0.16)))

                // The first step from zero is drawn as a rise, so the stroke
                // starts on the baseline rather than at the first day's total.
                context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .overlay {
                ChartHoverOverlay(samples: points.map { point in
                    .init(
                        x: point.position * pitch,
                        title: String.localized("Total through \(SpendFormat.chartDate(point.date))"),
                        tokens: point.running
                    )
                })
            }
        }
    }
}
