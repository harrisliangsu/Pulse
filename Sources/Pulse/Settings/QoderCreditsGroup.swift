// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Qoder's usage history in its settings pane (issue #88): today, 7 days and
/// 31 days in credits — what was used and what was deducted — and the month
/// day by day. The account's own records, the same read the detailed card
/// makes (`QoderClient.fetchCreditDays`), asked when the pane opens and on
/// Refresh, never on a timer.
struct QoderCreditsGroup: View {
    let settings: AppSettings

    private enum Read: Equatable {
        case reading
        case read(QoderCreditDays)
        /// Not answered, or answered with less than the whole month.
        case failed
        case noSession
    }

    @State private var read: Read = .reading

    var body: some View {
        SettingsGroup(String.localized("Usage history")) {
            switch read {
            case .reading:
                SettingsRow(String.localized("Reading the account's records…")) {
                    ProgressView().controlSize(.small)
                }
            case .noSession:
                SettingsRow(
                    String.localized("No session"),
                    subtitle: String.localized("Read the session from your browser above to see the account's usage history.")
                ) { EmptyView() }
            case .failed:
                SettingsRow(String.localized("Couldn't read the history.")) {
                    Button(String.localized("Retry")) { Task { await load() } }
                }
            case .read(let credits):
                figures(credits)
                SettingsRowDivider()
                CreditBarChart(days: credits.days)
                    .frame(height: 96)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                SettingsRowDivider()
                SettingsRow(
                    String.localized("From Qoder's usage records, in credits."),
                    subtitle: String.localized("The whole account, editor and CLI alike. Used is before discounts and free allowances; charged is what was deducted.")
                ) {
                    Button(String.localized("Refresh")) { Task { await load() } }
                }
            }
        }
        // Read again when the site or the session changes, as well as on
        // opening: another site's records are another account's.
        .task(id: "\(settings.qoderSite.rawValue)|\(APIKeyStore.key(for: .qoder)?.hashValue ?? 0)") {
            await load()
        }
    }

    private func load() async {
        guard let cookie = APIKeyStore.key(for: .qoder), !cookie.isEmpty else {
            read = .noSession
            return
        }
        read = .reading
        let credits = await QoderClient().fetchCreditDays(cookie: cookie, site: settings.qoderSite)
        read = credits.map(Read.read) ?? .failed
    }

    private func figures(_ credits: QoderCreditDays) -> some View {
        HStack(alignment: .top, spacing: 20) {
            figure(String.localized("Today"), credits.total(overLast: 1))
            figure(String.localized("Last \("7") days"), credits.total(overLast: 7))
            figure(String.localized("Last \("31") days"), credits.total(overLast: QoderCreditDays.span))
        }
        .padding(16)
    }

    private func figure(_ label: String, _ total: (used: Double, charged: Double)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(verbatim: UsageDetailCard.creditAmount(total.used))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
            Text(String.localized("Charged \(UsageDetailCard.creditAmount(total.charged))"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String.localized("\(UsageDetailCard.creditAmount(total.used)) credits used, \(UsageDetailCard.creditAmount(total.charged)) charged"))
    }
}

/// Credits used per day, one bar a day, with the day's two figures on hover.
/// Not `SpendBarChart`, whose hover and VoiceOver speak in tokens.
private struct CreditBarChart: View {
    let days: [QoderCreditDays.Day]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let peak = max(days.map(\.used).max() ?? 1, 0.01)
                let slot = proxy.size.width / CGFloat(max(days.count, 1))
                let width = max(min(slot * 0.72, 22), 1)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(days, id: \.date) { day in
                        RoundedRectangle(cornerRadius: min(width, 5) / 2, style: .continuous)
                            .fill(day.used > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: width,
                                   height: day.used > 0 ? max((proxy.size.height - 1) * CGFloat(day.used / peak), 3) : 2)
                            .frame(width: slot, alignment: .center)
                            .contentShape(Rectangle())
                            .help(Self.describe(day))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(SpendFormat.chartDate(day.date))
                            .accessibilityValue(Self.describe(day))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.quaternary).frame(height: 1)
                }
            }
            if let first = days.first, let last = days.last, days.count > 1 {
                HStack {
                    Text(verbatim: SpendFormat.chartDate(first.date))
                    Spacer(minLength: 0)
                    Text(verbatim: SpendFormat.chartDate(last.date))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("Credits used per day"))
    }

    private static func describe(_ day: QoderCreditDays.Day) -> String {
        SpendFormat.chartDate(day.date) + " · " + String.localized(
            "\(UsageDetailCard.creditAmount(day.used)) credits used, \(UsageDetailCard.creditAmount(day.charged)) charged")
    }
}
