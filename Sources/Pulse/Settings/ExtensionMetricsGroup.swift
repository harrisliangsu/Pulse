// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// An extension's metrics, every one of them, each series drawn with a hover
/// readout (issue #80).
///
/// **The place a series is read closely.** The panel's card draws at most a
/// few series and cannot be hovered — it never becomes key — so this is where
/// each point's time and value can be read, the way the Token spend pane is
/// for the card's days chart.
struct ExtensionMetricsGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings

    var body: some View {
        let metrics = store.usage(for: account).metrics
        if settings.isEnabled(account), !metrics.isEmpty {
            SettingsGroup(String.localized("Metrics")) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(metric.label) {
                        Text(verbatim: metric.valueText)
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    if metric.hasTrend {
                        MetricSeriesChart(metric: metric)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 11)
                    }
                }
            }
        }
    }
}

/// One series, its line and its first and last times, hovered point by point.
private struct MetricSeriesChart: View {
    let metric: UsageMetric

    private static let height: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let line = MetricTrendLine(points: metric.history, lineWidth: 1.5, colour: .accentColor)
                line
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.quaternary).frame(height: 1)
                    }
                    .overlay {
                        ChartHoverOverlay(samples: metric.history.indices.compactMap { index in
                            guard let location = MetricTrendLine.location(
                                of: index, in: metric.history, size: proxy.size, inset: line.inset
                            ) else { return nil }
                            let point = metric.history[index]
                            return .init(x: location.x, title: Self.time(point.at), value: metric.text(for: point.value))
                        })
                    }
            }
            .frame(height: Self.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metric.label)
            .accessibilityValue(MetricTrendLine.summary(of: metric))

            if let first = metric.history.first, let last = metric.history.last {
                HStack {
                    Text(verbatim: Self.time(first.at))
                    Spacer(minLength: 8)
                    Text(verbatim: Self.time(last.at))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The time to the minute, with the date unless it is today's.
    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(date) ? "jmm" : "MMMdjmm")
        return formatter.string(from: date)
    }
}
