// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// How the provider says its service is doing, drawn the way its status page
/// draws it: per component, the state now, one bar a day for about ninety
/// days, and the page's uptime figure between "90 days ago" and "Today".
///
/// **The provider's word, and said to be.** Pulse does not test the service;
/// the footnote names who reports it, the uptime is the page's own figure,
/// and each page keeps its own colours. Read when the pane opens and every
/// five minutes while it stays open, never once it is closed — nobody is
/// looking at it then. A page that
/// can't be read says so, rather than leaving rows to read as healthy.
struct ServiceStatusGroup: View {
    let page: StatusPage

    @State private var status: ServiceStatus?
    @State private var isReading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(String.localized("Service status")) {
                if let status {
                    ForEach(Array(status.components.enumerated()), id: \.element.id) { index, component in
                        if index > 0 { SettingsRowDivider() }
                        ServiceStatusRow(component: component, palette: StatusPalette(page))
                    }
                } else if isReading {
                    SettingsRow(String.localized("Checking…")) {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    SettingsRow(String.localized("Couldn't read the status page.")) { EmptyView() }
                }

                SettingsRowDivider()

                SettingsRow(String.localized("Status page"), subtitle: page.host) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(page.address)
                    }
                }
            }

            Text(localized: "As \(page.company) reports it on its status page, read when this page opens and every five minutes while it stays open.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        // Read on opening and again every `checkInterval` while open; leaving
        // the pane cancels it. A later read that fails replaces the rows with
        // "couldn't read" rather than leaving old ones to pass for current.
        .task(id: page) {
            isReading = true
            status = nil
            while !Task.isCancelled {
                let read = await ServiceStatus.read(page)
                guard !Task.isCancelled else { return }
                status = read
                isReading = false
                try? await Task.sleep(for: ServiceStatus.checkInterval)
            }
        }
    }
}

/// One component: its name and state, its days, and the uptime line.
private struct ServiceStatusRow: View {
    let component: ServiceStatus.Component
    let palette: StatusPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(component.name)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                Text(component.state.title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.colour(for: component.state))
            }

            if !component.days.isEmpty {
                DayBars(days: component.days, palette: palette)
                    .frame(height: 24)

                HStack(spacing: 8) {
                    Text(localized: "90 days ago")
                    rule
                    if let uptime = component.uptime {
                        Text(localized: "\(Self.percent(uptime)) uptime")
                        rule
                    }
                    Text(localized: "Today")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var rule: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    /// The page's figure as it gives it: up to two decimals, none for 100.
    private static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...2)).locale(LocalizationSource.locale))
    }
}

/// A bar a day, oldest on the left, at the page's own proportions: bars three
/// units wide with two between, stretched across the row.
private struct DayBars: View {
    let days: [ServiceStatus.Day]
    let palette: StatusPalette

    var body: some View {
        // One formatter for all ninety tooltips, made per pass so a language
        // switch still takes effect at once.
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")

        return GeometryReader { geometry in
            let unit = geometry.size.width / CGFloat(max(days.count * 5 - 2, 1))
            HStack(spacing: unit * 2) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    RoundedRectangle(cornerRadius: palette.barCornerRadius, style: .continuous)
                        .fill(palette.colour(for: day))
                        .frame(width: unit * 3)
                        .help(Self.tooltip(day, formatter))
                }
            }
        }
    }

    private static func tooltip(_ day: ServiceStatus.Day, _ formatter: DateFormatter) -> String {
        let state = day.state?.title ?? String.localized("No data")
        guard let date = Calendar.current.date(from: day.date) else { return state }
        return "\(formatter.string(from: date)) · \(state)"
    }
}

/// Each page's own colours, taken off the page (2026-10-04): incident.io's
/// for OpenAI, Claude's Statuspage theme for Claude, Flashcat's for DeepSeek.
private struct StatusPalette {
    let page: StatusPage

    init(_ page: StatusPage) { self.page = page }

    /// incident.io and Flashcat round their bars; Statuspage's are square.
    var barCornerRadius: CGFloat { page == .claude ? 0 : 1.5 }

    func colour(for state: ServiceStatus.State) -> Color {
        switch (page, state) {
        case (.openAI, .operational): Self.rgb(0x24C19A)
        case (.openAI, .degraded): Self.rgb(0xFBBF24)
        case (.openAI, .partialOutage): Self.rgb(0xF5785C)
        case (.openAI, .fullOutage): Self.rgb(0xF87171)
        // Not seen on the page; incident.io's blue.
        case (.openAI, .maintenance): Self.rgb(0x60A5FA)
        case (.claude, .operational): Self.rgb(0x76AD2A)
        case (.claude, .degraded): Self.rgb(0xFAA72A)
        case (.claude, .partialOutage): Self.rgb(0xE86235)
        case (.claude, .fullOutage): Self.rgb(0xE04343)
        case (.claude, .maintenance): Self.rgb(0x2C84DB)
        case (.deepSeek, .operational): Self.rgb(0x22C55E)
        case (.deepSeek, .degraded): Self.rgb(0xEAB308)
        case (.deepSeek, .partialOutage): Self.rgb(0xF97316)
        case (.deepSeek, .fullOutage): Self.rgb(0xEF4444)
        // Not seen on the page; the same Tailwind set's blue.
        case (.deepSeek, .maintenance): Self.rgb(0x3B82F6)
        case (_, .unrecognised): .secondary
        }
    }

    /// The page's own colour when it gave one; otherwise the state's. A day
    /// with no record is drawn faint in both light and dark.
    func colour(for day: ServiceStatus.Day) -> Color {
        if let rgb = day.rgb { return Self.rgb(rgb) }
        guard let state = day.state else { return Color.secondary.opacity(0.2) }
        return colour(for: state)
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview("Claude") {
    ServiceStatusGroup(page: .claude)
        .padding(24)
        .frame(width: 560)
}
