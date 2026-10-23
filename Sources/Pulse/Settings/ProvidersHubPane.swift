// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Every built-in account, which the sidebar no longer lists one by one.
///
/// Extensions stay in the sidebar's Other section: they are programs somebody
/// added, not services Blinky ships. An account here opens the same pane the
/// sidebar row used to open.
struct ProvidersHubPane: View {
    let settings: AppSettings
    let navigation: SettingsNavigation

    var body: some View {
        let accounts = settings.orderedAccounts.filter { $0.provider != .pulseExtension }
        let groups = ProviderAccountGroups.make(accounts: accounts, isEnabled: settings.isEnabled)
        VStack(alignment: .leading, spacing: 22) {
            ForEach(groups) { group in
                SettingsGroup(group.title) {
                    ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 { SettingsRowDivider() }
                        accountRow(account)
                    }
                }
            }
        }
    }

    private func accountRow(_ account: AccountKey) -> some View {
        Button {
            navigation.open(.account(account))
        } label: {
            HStack(spacing: 10) {
                LobeIconView(provider: account.provider, size: 16)
                Text(settings.label(for: account))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Providers") {
    ProvidersHubPane(settings: AppSettings(), navigation: SettingsNavigation())
        .padding()
        .frame(width: 560)
}
