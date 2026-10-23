// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

struct NotificationsPane: View {
    let store: UsageStore
    let settings: AppSettings
    let alerts: UsageAlerts

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    String.localized("Warn at"),
                    subtitle: alertsSubtitle
                ) {
                    Picker("", selection: Binding(
                        get: { settings.alertThreshold },
                        set: {
                            settings.alertThreshold = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    )) {
                        ForEach(AlertThreshold.allCases) { threshold in
                            Text(threshold.title).tag(threshold)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a limit comes back"),
                    subtitle: String.localized("Only for one you were warned about.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnReset },
                        set: {
                            settings.alertsOnReset = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // Nothing to fire about: a reset is only announced for a
                    // window that was mentioned on the way up.
                    .disabled(!UsageAlerts.isSupported || settings.alertThreshold == .off)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a reading stops arriving"),
                    subtitle: String.localized("After several failed checks in a row, once per outage.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnFailure },
                        set: {
                            settings.alertsOnFailure = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a service is down"),
                    subtitle: String.localized("From each provider's own status page, for the providers you have switched on and only about what their accounts run on.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnOutage },
                        set: {
                            settings.alertsOnOutage = $0
                            // The status pages, not the readings: an outage
                            // already under way is said now, and switching off
                            // forgets what was said. `reconsiderAlerts` would
                            // refetch every provider for nothing.
                            Task {
                                _ = await alerts.requestAuthorizationIfNeeded()
                                alerts.checkServices()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a recap is ready"),
                    subtitle: String.localized("Last month's recap, at the start of the month. Needs Token spend reading.")
                ) {
                    // The request and the first check follow from the setting
                    // itself (`AppSettings.onRecapAlertChange`).
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnRecap },
                        set: { settings.alertsOnRecap = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // The month is only known from records Pulse has read — but
                    // a switch that is on can always be turned off, whatever
                    // Token spend reading says.
                    .disabled(!UsageAlerts.isSupported || (!settings.readsTokenSpend && !settings.alertsOnRecap))
                }
            }

            exhaustionGroup

            SettingsGroup(String.localized("Reset reminders")) {
                SettingsRow(
                    String.localized("Predicted reset"),
                    subtitle: predictedReminderSubtitle
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.remindsBeforePredictedReset },
                        set: { enabled in
                            settings.remindsBeforePredictedReset = enabled
                            commitAdvanceReminders()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("How early"),
                    subtitle: String.localized("Hours before the predicted time.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.predictedResetLead },
                        set: { lead in
                            settings.predictedResetLead = lead
                            commitAdvanceReminders()
                        }
                    )) {
                        ForEach(ResetLead.allCases) { lead in
                            Text(lead.title).tag(lead)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!UsageAlerts.isSupported || !settings.remindsBeforePredictedReset)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Regular resets"),
                    subtitle: String.localized("Before each window's own reset, skipping any window shorter than the lead.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.remindsBeforeRegularReset },
                        set: { enabled in
                            settings.remindsBeforeRegularReset = enabled
                            commitAdvanceReminders()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("How early"),
                    subtitle: String.localized("Hours before that reset.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.regularResetLead },
                        set: { lead in
                            settings.regularResetLead = lead
                            commitAdvanceReminders()
                        }
                    )) {
                        ForEach(ResetLead.allCases) { lead in
                            Text(lead.title).tag(lead)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!UsageAlerts.isSupported || !settings.remindsBeforeRegularReset)
                }
            }

            SettingsGroup(String.localized("Celebrations")) {
                SettingsRow(
                    String.localized("Celebrate a reset"),
                    subtitle: String.localized("After a limit turns over: ribbons and a sound, named for the provider.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.celebratesReset },
                        set: { settings.celebratesReset = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Also celebrate hourly quota resets"),
                    subtitle: String.localized("Five-hour windows, not only the week or month.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.celebratesHourlyReset },
                        set: { settings.celebratesHourlyReset = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.celebratesReset)
                }
            }
        }
        .task {
            // The time-to-empty notice starts on, so the grant has to be asked
            // when this pane opens. A switch that is already on never goes
            // from off to on, and a prompt at launch is refused for good.
            // An answer already given is not asked again.
            guard UsageAlerts.isSupported,
                  settings.wantsExhaustionAlerts,
                  alerts.authorization == .notDetermined
            else { return }
            if await alerts.requestAuthorizationIfNeeded() {
                store.reconsiderAlerts()
            }
        }
    }

    /// The card line and the remaining-time notices, in one group. Percent
    /// thresholds stay in the group above; this is the other question.
    @ViewBuilder
    private var exhaustionGroup: some View {
        SettingsGroup(String.localized("Exhaustion forecast")) {
            exhaustionAccountRows
            exhaustionCardRows
            exhaustionNoticeRows
        }
    }

    /// Whose windows are forecast, on the card and in the notices together.
    @ViewBuilder
    private var exhaustionAccountRows: some View {
        SettingsRow(
            String.localized("Accounts"),
            subtitle: String.localized("Every account on the panel, or only the ones you pick.")
        ) {
                Picker("", selection: Binding(
                    get: { settings.exhaustionAllAccounts },
                    set: { settings.setExhaustionAllAccounts($0) }
                )) {
                    Text(localized: "All shown accounts").tag(true)
                    Text(localized: "Selected accounts").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
            }

            if !settings.exhaustionAllAccounts {
                ForEach(settings.shownAccounts, id: \.id) { account in
                    SettingsRowDivider()
                    SettingsRow(settings.label(for: account)) {
                        Toggle("", isOn: Binding(
                            get: { settings.forecastsExhaustion(for: account) },
                            set: { settings.setForecastsExhaustion($0, for: account) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
            }
    }

    /// The line on the card. These stay usable without a notification grant.
    @ViewBuilder
    private var exhaustionCardRows: some View {
        SettingsRowDivider()

        SettingsRow(
            String.localized("On the card"),
            subtitle: String.localized("A line under each limit that has a length and a reset.")
        ) {
                Toggle("", isOn: Binding(
                    get: { settings.showsForecast },
                    set: { settings.showsForecast = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!settings.isPanelVisible)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Countdown within"),
                subtitle: String.localized("Hours. Show the time only this close to running out.")
            ) {
                Stepper(
                    value: Binding(
                        get: { settings.exhaustionCardHours },
                        set: { settings.exhaustionCardHours = $0 }
                    ),
                    in: ExhaustionStage.minimumHours...ExhaustionStage.maximumHours
                ) {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(!settings.isPanelVisible || !settings.showsForecast)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("May run out before reset"),
                subtitle: String.localized("A quieter line when it is further out than the countdown.")
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.exhaustionSoftHint },
                    set: { settings.exhaustionSoftHint = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!settings.isPanelVisible || !settings.showsForecast)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Tie it to the reset"),
                subtitle: String.localized("When it will not last until the reset, say roughly when.")
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.exhaustionBeforeReset },
                    set: { settings.exhaustionBeforeReset = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!settings.isPanelVisible || !settings.showsForecast)
            }
    }

    /// Remaining-time notices. Greyed out where there is no app bundle to post from.
    @ViewBuilder
    private var exhaustionNoticeRows: some View {
        SettingsRowDivider()

        SettingsRow(
            String.localized("Time remaining"),
            subtitle: exhaustionAlertsSubtitle
        ) {
                Toggle("", isOn: Binding(
                    get: { settings.exhaustionAlerts },
                    set: { enabled in
                        settings.exhaustionAlerts = enabled
                        commitExhaustionAlerts()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!UsageAlerts.isSupported)
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Stages"),
                subtitle: String.localized("Each one warns once, at its own remaining time.")
            ) {
                Button(String.localized("Add a stage")) {
                    settings.addExhaustionStage()
                    commitExhaustionAlerts()
                }
                .disabled(!UsageAlerts.isSupported || !settings.exhaustionAlerts)
            }

            ForEach(settings.exhaustionStages) { stage in
                SettingsRowDivider()
                SettingsRow(String.localized("\("\(stage.hours)") hours")) {
                    HStack(spacing: 10) {
                        Stepper(
                            value: Binding(
                                get: { stage.hours },
                                set: { hours in
                                    settings.setExhaustionStageHours(id: stage.id, hours: hours)
                                    commitExhaustionAlerts()
                                }
                            ),
                            in: ExhaustionStage.minimumHours...ExhaustionStage.maximumHours
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                        Button(String.localized("Remove")) {
                            settings.removeExhaustionStage(id: stage.id)
                            commitExhaustionAlerts()
                        }
                    }
                    .disabled(!UsageAlerts.isSupported || !settings.exhaustionAlerts)
                }
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Notify before the reset"),
                subtitle: String.localized("When the pace will not last until the reset.")
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.exhaustionNotifyBeforeReset },
                    set: { enabled in
                        settings.exhaustionNotifyBeforeReset = enabled
                        commitExhaustionAlerts()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!UsageAlerts.isSupported)
            }
    }

    /// Advance reminders are notifications, so they share the grant the other
    /// switches ask for. The sentence stays about *before*, which is what
    /// separates them from "when a limit comes back" and from the ribbons.
    private var predictedReminderSubtitle: String {
        guard UsageAlerts.isSupported else {
            return .localized("Notifications need the bundled app.")
        }
        if settings.wantsAdvanceReminders, alerts.authorization == .denied {
            return .localized("Turned off for Blinky in System Settings › Notifications.")
        }
        return .localized("Before an explicit time from Codex Resets; a forecast with no time stays quiet.")
    }

    /// The same grant as the other notices. A stage already passed is said
    /// once, on the readings Pulse already holds.
    private func commitExhaustionAlerts() {
        Task {
            if await alerts.requestAuthorizationIfNeeded() {
                store.reconsiderAlerts()
            }
        }
    }

    private var exhaustionAlertsSubtitle: String {
        guard UsageAlerts.isSupported else {
            return .localized("Notifications need the bundled app.")
        }
        if settings.wantsExhaustionAlerts, alerts.authorization == .denied {
            return .localized("Turned off for Blinky in System Settings › Notifications.")
        }
        return .localized("One notice per account, limit and stage.")
    }

    private func commitAdvanceReminders() {
        Task {
            if settings.wantsNotificationPermission {
                _ = await alerts.requestAuthorizationIfNeeded()
            }
            store.syncAdvanceReminders()
            store.refreshCodexResetForecast()
        }
    }

    /// Says what the *system* thinks, which is the half the switches cannot
    /// know. A switch left on while macOS is dropping everything Pulse posts is
    /// a setting that lies, and permission can be withdrawn in System Settings
    /// long after it was given.
    private var alertsSubtitle: String {
        guard UsageAlerts.isSupported else {
            // The `swift run` case: a bare executable has no bundle, and the
            // notification centre raises rather than refusing politely.
            return .localized("Notifications need the bundled app.")
        }

        if settings.wantsAlerts, alerts.authorization == .denied {
            return .localized("Turned off for Blinky in System Settings › Notifications.")
        }
        return .localized("Notify when a limit passes this, and again when it is spent.")
    }
}
