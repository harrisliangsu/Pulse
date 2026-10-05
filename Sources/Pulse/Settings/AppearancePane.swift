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
                    .pickerStyle(.segmented)
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
                    .pickerStyle(.segmented)
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

                SettingsRow(
                    String.localized("Liquid Glass"),
                    subtitle: glassSubtitle
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.usesGlass },
                        set: { settings.usesGlass = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                // Only while glass is on: it is how clear the glass is, and on
                // the black panel there is no glass to be clear.
                if settings.usesGlass {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Transparency"),
                        subtitle: String.localized("Clearer to the right. Darker reads better over bright pages.")
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

    private var glassSubtitle: String {
        .localized("Clear glass that shows what is behind the panel, instead of solid black.")
    }
}
