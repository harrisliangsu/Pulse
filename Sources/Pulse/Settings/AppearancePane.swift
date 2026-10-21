// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// How the rail and card look: size, spacing, the ends, the surface.
struct AppearancePane: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if settings.needsProviderSelection {
                Text(localized: "Enable a service in its settings to start monitoring.")
                    .foregroundStyle(.secondary)
            }

            SettingsGroup {
                SettingsRow(
                    String.localized("Size"),
                    subtitle: String.localized("Size of the rail on screen.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.panelSize },
                        set: { settings.panelSize = $0 }
                    )) {
                        ForEach(PanelSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Spacing"),
                    subtitle: String.localized("How much air there is between the rings.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.railSpacing },
                        set: { settings.railSpacing = $0 }
                    )) {
                        ForEach(RailSpacing.allCases) { spacing in
                            Text(spacing.title).tag(spacing)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Round ends"),
                    subtitle: String.localized("The rail's ends and the card's tail follow the ring's own curve.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.usesRoundEnds },
                        set: { settings.usesRoundEnds = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                // Not greyed out with the panel hidden: the menu's bars
                // follow it too.
                SettingsRow(
                    String.localized("Progress bars"),
                    subtitle: String.localized("How limit bars are drawn on the card and in the menu.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.usageBarStyle },
                        set: { settings.usageBarStyle = $0 }
                    )) {
                        ForEach(UsageBarStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Appearance"),
                    subtitle: String.localized("Dark, light, match the Mac, or glass.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.panelAppearance },
                        set: { settings.panelAppearance = $0 }
                    )) {
                        ForEach(PanelAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                // Only while glass is on: it is how clear the glass is, and on
                // a solid panel there is no glass to be clear.
                if settings.usesGlass {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Transparency"),
                        subtitle: String.localized("Clearer to the right, and the text turns from white to black. Black text is hard to read over dark windows.")
                    ) {
                        Slider(
                            value: Binding(
                                get: { settings.glassTransparency },
                                set: { settings.glassTransparency = $0 }
                            ),
                            in: 0...1
                        )
                        .labelsHidden()
                        .frame(width: SettingsLayout.controlWidth)
                        .disabled(!settings.isPanelVisible)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Ring activity animation"),
                    subtitle: String.localized("The turning mark for a working CLI or a reading being fetched. Off leaves the ring still.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.animatesRingActivity },
                        set: { settings.animatesRingActivity = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }
        }
    }
}
