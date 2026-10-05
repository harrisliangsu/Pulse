// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What each ring and the card say, and when they turn red.
struct RingsPane: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Figures")) {
                SettingsRow(
                    String.localized("Percentages at the side"),
                    subtitle: String.localized("The figure under each ring, docked left or right.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.sideRailShowsPercentages },
                        set: { settings.sideRailShowsPercentages = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Percentages across"),
                    subtitle: String.localized("When the panel lies across: docked to the top or bottom, or free.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.topRailShowsPercentages },
                        set: { settings.topRailShowsPercentages = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Figures beside the rings"),
                    subtitle: String.localized("Only when the panel lies free across. A thinner, longer panel.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.freeAcrossFiguresBeside },
                        set: { settings.freeAcrossFiguresBeside = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible || !settings.topRailShowsPercentages)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Figure above the ring"),
                    subtitle: String.localized("Swaps the two, wherever the panel is.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.labelAboveRing },
                        set: { settings.labelAboveRing = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(
                        !settings.isPanelVisible
                            // Nothing to swap when neither rail shows a figure.
                            || (!settings.sideRailShowsPercentages && !settings.topRailShowsPercentages)
                    )
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Show what's left"),
                    subtitle: String.localized("Counts down instead of up, figure and ring together.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsRemaining },
                        set: { settings.showsRemaining = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Forecast"),
                    subtitle: String.localized("Whether each limit lasts its window, on the card.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsForecast },
                        set: { settings.showsForecast = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }

            SettingsGroup(String.localized("Rings")) {
                SettingsRow(
                    String.localized("Second limit inside the ring"),
                    subtitle: String.localized("A thinner ring for the next-fullest limit, where a provider has one.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsSecondRing },
                        set: { settings.showsSecondRing = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Time until reset"),
                    subtitle: String.localized("A second arc outside each ring, showing progress through the current window.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsWindowClock },
                        set: { settings.showsWindowClock = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Time ring direction"),
                    subtitle: String.localized("Choose whether the outer arc fills with elapsed time or empties with time remaining.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.windowClockDirection },
                        set: { settings.windowClockDirection = $0 }
                    )) {
                        ForEach(WindowClockDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible || !settings.showsWindowClock)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Turn red at"),
                    subtitle: String.localized("Where a ring stops being amber. A spent limit is red whatever this says.")
                ) {
                    Picker(String.localized("Turn red at"), selection: Binding(
                        get: { settings.warningThreshold },
                        set: { settings.warningThreshold = $0 }
                    )) {
                        ForEach(WarningThreshold.allCases) { threshold in
                            Text(threshold.title).tag(threshold)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Alert colour when docked"),
                    subtitle: String.localized("Off keeps the collapsed rail neutral even when a limit needs attention.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.dockShowsAlertColor },
                        set: { settings.dockShowsAlertColor = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }
        }
    }
}
