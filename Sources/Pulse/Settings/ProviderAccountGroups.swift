// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Built-in accounts, grouped the way the sidebar used to list them: what is
/// switched on, then each way of paying, and an enabled account only once.
///
/// The Providers page always draws this. A sidebar search draws the same
/// groups for the accounts the search matched, so the two lists agree.
struct ProviderAccountGroups {
    enum Kind: Hashable {
        case enabled
        case billing(Provider.Billing)
    }

    struct Group: Identifiable {
        let kind: Kind
        let title: String
        let accounts: [AccountKey]
        var id: Kind { kind }
    }

    /// `accounts` is already in rail order. That order is kept inside each group.
    static func make(accounts: [AccountKey], isEnabled: (AccountKey) -> Bool) -> [Group] {
        var groups: [Group] = []
        let enabled = accounts.filter(isEnabled)
        if !enabled.isEmpty {
            groups.append(Group(kind: .enabled, title: String.localized("Enabled"), accounts: enabled))
        }
        for billing in Provider.Billing.allCases {
            let rows = accounts.filter { $0.provider.billing == billing && !isEnabled($0) }
            if !rows.isEmpty {
                groups.append(Group(kind: .billing(billing), title: billing.sectionTitle, accounts: rows))
            }
        }
        return groups
    }
}

/// Which provider accounts the sidebar draws.
///
/// A search draws the matches. With the field empty it draws none: the full
/// list is the Providers page, and opening an account does not add a row.
/// An extension is drawn with the other bottom rows, not here.
enum SettingsProviderListing {
    static func accounts(searching: Bool, matches: [AccountKey]) -> [AccountKey] {
        searching ? matches : []
    }
}
