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
                    subtitle: String.localized("Codex, Claude Code and DeepSeek, from their own status pages — only the ones you have switched on.")
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
            return .localized("Turned off for Pulse in System Settings › Notifications.")
        }
        return .localized("Notify when a limit passes this, and again when it is spent.")
    }
}
