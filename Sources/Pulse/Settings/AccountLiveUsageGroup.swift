// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// An account's Current usage card: when it was last read, and each limit's
/// figure and reset.
struct AccountLiveUsageGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings

    var body: some View {
        let usage = store.usage(for: account)

        return SettingsGroup(String.localized("Current usage")) {
            if !settings.isEnabled(account) {
                SettingsRow(
                    String.localized("Not shown"),
                    subtitle: String.localized("Enable a service in its settings to start monitoring.")
                ) {
                    EmptyView()
                }
            } else {
                // Says how current these figures are, and offers to make them
                // current. The rail has the same on a ring click, but nobody
                // reading a settings pane should have to go and find it there.
                SettingsRow(String.localized("Last read")) {
                    HStack(spacing: 10) {
                        // `Text`'s relative style keeps counting on its own. A
                        // string worked out once said "just now" for the whole
                        // half hour until something else redrew the view.
                        if let observed = usage.observedAt {
                            Text(observed, style: .relative)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                // Every other date in the app is pinned to the
                                // language chosen in Settings; this one formats
                                // with the environment's locale, which follows the
                                // system. Without this, an English Pulse on a
                                // Chinese Mac prints "4分钟" beside "Refresh".
                                .environment(\.locale, LocalizationSource.locale)
                        } else {
                            Text(localized: "Not yet")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Button(String.localized("Refresh")) { store.refresh(account) }
                            // Any pass, not just this account.provider's: during a
                            // background one the press would only queue, with
                            // nothing on screen to say so.
                            .disabled(store.isRefreshing)
                    }
                }

                SettingsRowDivider()

                if usage.windows.isEmpty {
                    SettingsRow(
                        String.localized("No reading"),
                        subtitle: {
                            if case .unavailable(let reason) = usage.state { return reason.message }
                            return nil
                        }()
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(usage.windows.enumerated()), id: \.element.id) { index, window in
                        if index > 0 { SettingsRowDivider() }

                        SettingsRow(window.name, subtitle: resetText(window)) {
                            Text(window.percentText(remaining: settings.showsRemaining))
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }

                if let plan = usage.plan {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Plan")) {
                        Text(plan)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if let credit = usage.creditBalance {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Credit balance")) {
                        Text(credit)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func resetText(_ window: UsageWindow) -> String? {
        // **The same rule as `UsageDetailCard.resetText`, and it has to be
        // stated in both places.** `windowSeconds` is sometimes a sort key
        // rather than a measurement, and printing one here put a figure nobody
        // reported under a heading that reads like a reported one — with the
        // panel's own card, an inch away, deliberately saying nothing.
        guard let resets = window.resetsAt else {
            return window.reportsLength ? window.lengthText : nil
        }
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(resets) ? "jmm" : "MMMdjmm"
        )
        return String.localized("Resets \(formatter.string(from: resets))")
    }
}
