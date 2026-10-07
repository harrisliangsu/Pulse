// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The pane whose subject is every agent's spending added up: the switch that
/// turns reading on, the recap buttons, and `TokenSpendView` over what
/// `SpendPaneModel` has read.
struct TokenSpendPane: View {
    let settings: AppSettings
    @Bindable var model: SpendPaneModel
    /// Opens the recap window on a period.
    let openRecap: @MainActor (Recap.Period) -> Void
    let scroll: ScrollViewProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Token spend")) {
                SettingsRow(
                    String.localized("Read local usage records"),
                    subtitle: String.localized("When enabled, scans local records and exports.")
                ) {
                    Toggle(String.localized("Read local usage records"), isOn: Binding(
                        get: { settings.readsTokenSpend },
                        set: { settings.readsTokenSpend = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if settings.readsTokenSpend, model.isScanningSpend, let progress = model.spendProgress {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Reading \(progress.agent.displayName)…")) {
                        Text(verbatim: "\(progress.index + 1)/\(progress.total)")
                            .monospacedDigit()
                    }
                }
                if settings.readsTokenSpend {
                    SettingsRowDivider()
                    SettingsRow(
                        String.localized("Monthly and Yearly Recap"),
                        subtitle: String.localized("Shareable cards for a month or a year, from this Mac's records.")
                    ) {
                        // Both are visible here, so the yearly recap is
                        // not something found only inside the window.
                        HStack(spacing: 8) {
                            Button(recapButtonTitle) { openRecap(recapPeriod) }
                            Button(recapYearButtonTitle) { openRecap(recapYearPeriod) }
                        }
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
            }
            if settings.readsTokenSpend {
                TokenSpendView(
                    summary: model.spend,
                    focus: $model.spendFocus,
                    focused: model.focusedSpend,
                    modelFocus: $model.selectedModel,
                    modelSummary: model.modelSpend,
                    noRecords: model.spendNoRecords,
                    hasReadLimitations: model.spendHasReadLimitations,
                    span: Binding(
                        get: { settings.spendSpan },
                        set: { settings.spendSpan = $0 }
                    ),
                    activity: model.spendActivity,
                    activityView: Binding(
                        get: { settings.spendActivityView },
                        set: { settings.spendActivityView = $0 }
                    ),
                    isLoading: model.isScanningSpend,
                    isSummarizing: model.summaryIsPending,
                    refresh: { model.spendRescan += 1 }
                )
            }
        }
        // A model opened under one agent means nothing under another,
        // so changing the agent drops back out of the model.
        .onChange(of: model.spendFocus) { _, _ in model.selectedModel = nil }
        .onChange(of: model.selectedModel) { old, new in
            // Entering the detail drops the reader to the top, or they
            // land in the middle of it when the model row was well down
            // the page. Returning puts them back at the model list.
            if new != nil {
                scroll.scrollTo("heading", anchor: .top)
            } else if old != nil {
                scroll.scrollTo("models", anchor: .top)
            }
        }
    }

    /// The month the recap button opens, which is the one the window would
    /// open on by itself (`RecapPeriods.defaultMonth`).
    private var recapPeriod: Recap.Period {
        RecapPeriods.defaultMonth(earliest: RecapPeriods.earliest(in: model.spendLedgers))
    }

    /// The year the second button opens, by the same rule: January 1–7 opens
    /// on the year that just ended, any other day on this one, in progress
    /// (`RecapPeriods.defaultYear`).
    private var recapYearPeriod: Recap.Period {
        RecapPeriods.defaultYear(earliest: RecapPeriods.earliest(in: model.spendLedgers))
    }

    /// "View September recap".
    private var recapButtonTitle: String {
        guard case .month(_, let number) = recapPeriod else { return String.localized("Monthly Recap") }
        return String.localized("View \(RecapFormat.monthName(number)) recap")
    }

    /// "View 2026 recap": the year as a plain string, never grouped ("2,026").
    private var recapYearButtonTitle: String {
        guard case .year(let year) = recapYearPeriod else { return String.localized("Yearly Recap") }
        return String.localized("View \("\(year)") yearly recap")
    }
}
