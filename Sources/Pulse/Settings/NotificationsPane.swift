// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

struct NotificationsPane: View {
    let store: UsageStore
    let settings: AppSettings
    let alerts: UsageAlerts

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Limits and outages")) {
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

                // Hidden while Warn at is Off. The switch keeps its stored
                // value; a reset is still announced only for a window that
                // was mentioned on the way up.
                if SettingsChildRows.showsLimitCameBack(settings.alertThreshold) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("When a limit comes back"),
                        subtitle: String.localized("Only for one you were warned about."),
                        nested: true
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
                        .disabled(!UsageAlerts.isSupported)
                    }
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

            exhaustionNoticeGroup

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

                if SettingsChildRows.showsPredictedLead(settings.remindsBeforePredictedReset) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("How early"),
                        subtitle: String.localized("Hours before the predicted time."),
                        nested: true
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
                        .disabled(!UsageAlerts.isSupported)
                    }
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

                if SettingsChildRows.showsRegularLead(settings.remindsBeforeRegularReset) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("How early"),
                        subtitle: String.localized("Hours before that reset."),
                        nested: true
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
                        .disabled(!UsageAlerts.isSupported)
                    }
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

                if SettingsChildRows.showsHourlyCelebration(settings.celebratesReset) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Also celebrate hourly quota resets"),
                        subtitle: String.localized("Five-hour windows, not only the week or month."),
                        nested: true
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.celebratesHourlyReset },
                            set: { settings.celebratesHourlyReset = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
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

    /// Remaining-time notices. Greyed out where there is no app bundle to post from.
    private var exhaustionNoticeGroup: some View {
        SettingsGroup(ExhaustionSettingsSections.notices) {
            SettingsRow(
                String.localized("Notify when a limit is running out"),
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

            if SettingsChildRows.showsExhaustionStages(alertsOn: settings.exhaustionAlerts) {
                SettingsRowDivider()

                    SettingsRow(
                        String.localized("Hours left to notify"),
                        subtitle: String.localized("Each stage notifies once, at its own hours left. A new install starts with 24 hours."),
                        nested: true
                    ) {
                    Button(String.localized("Add a stage")) {
                        settings.addExhaustionStage()
                        commitExhaustionAlerts()
                    }
                    .disabled(!UsageAlerts.isSupported)
                }

                ForEach(settings.exhaustionStages) { stage in
                    SettingsRowDivider()
                    SettingsRow(String.localized("\("\(liveStageHours(stage))") hours"), nested: true) {
                        HStack(spacing: 10) {
                            ExhaustionHoursStepper(
                                hours: liveStageHours(stage),
                                enabled: UsageAlerts.isSupported,
                                value: Binding(
                                    get: { liveStageHours(stage) },
                                    set: { hours in
                                        settings.setExhaustionStageHours(
                                            id: stage.id,
                                            hours: ExhaustionHoursControl.applied(hours)
                                        )
                                        commitExhaustionAlerts()
                                    }
                                )
                            )
                            Button(String.localized("Remove")) {
                                settings.removeExhaustionStage(id: stage.id)
                                commitExhaustionAlerts()
                            }
                            .disabled(!UsageAlerts.isSupported)
                        }
                    }
                }
            }

            SettingsRowDivider()

            SettingsRow(
                String.localized("Notify if it will not last until the reset"),
                subtitle: String.localized("Sends a separate notice when the current pace will not last until the reset.")
            ) {
                // The switch is `exhaustionNotifyBeforeReset` itself. On sends
                // the notice. The shipped default is off; a stored true stays on.
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
    }

    /// The hours still stored for this stage. Read while the row is built, so
    /// the stepper's label and the row title follow a click.
    private func liveStageHours(_ stage: ExhaustionStage) -> Int {
        settings.exhaustionStages.first { $0.id == stage.id }?.hours ?? stage.hours
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
        return .localized("Notifies once when the time left reaches a stage, for each account and limit.")
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

/// The three exhaustion groups. The card and the account list are on Usage
/// card; the notices are on Exhaustion and reminders. The titles stay in
/// that order so a test can name them without opening a window.
enum ExhaustionSettingsSections {
    static var card: String { String.localized("Exhaustion on the card") }
    static var notices: String { String.localized("Exhaustion notifications") }
    static var accounts: String { String.localized("Which accounts") }

    static var titles: [String] { [card, notices, accounts] }
}

/// Up and down, with the current hours written beside them.
///
/// The binding is built in the row, where it reads the setting again after
/// the click. A copy taken while the row was last built puts the old number
/// back, and the click looks dead. The label is that same number: hiding it
/// was how the row shipped with bare chevrons.
///
/// The binding stays a `Binding` rather than two closures passed in. Those
/// closures are not sendable, and the stepper's binding requires closures
/// that are.
struct ExhaustionHoursStepper: View {
    let hours: Int
    var enabled: Bool
    @Binding var value: Int

    var body: some View {
        let shown = ExhaustionHoursControl.digits(hours)
        Stepper(
            value: $value,
            in: ExhaustionStage.minimumHours...ExhaustionStage.maximumHours,
            step: 1
        ) {
            Text(verbatim: shown)
                .font(.system(size: 13).monospacedDigit())
                .frame(minWidth: 36, alignment: .trailing)
        }
        .fixedSize()
        .accessibilityValue(shown)
        .disabled(!enabled)
    }
}
