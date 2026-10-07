// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The Token spend pane: how far back it counts, which view of the year chart is
// open, and whether Pulse reads local records at all. None of these is the
// usage loop's business, so none goes through `onChange` — that hook refreshes
// the quota providers. Each is stored through a `store…`/`stored…` pair that
// takes the defaults as an argument, so the round trip can be pinned against an
// isolated suite.

extension AppSettings.Key {
    static let spendSpan = "settings.spendSpan"
    static let spendActivityView = "settings.spendActivityView"
    static let readsTokenSpend = "settings.readsTokenSpend"
}

extension AppSettings.Default {
    static let readsTokenSpend = false
}

extension AppSettings {
    func spendSpanChanged(from old: SpendSpan) {
        guard spendSpan != old else { return }
        Self.storeSpendSpan(spendSpan, in: defaults)
    }

    func spendActivityViewChanged(from old: ActivityView) {
        guard spendActivityView != old else { return }
        Self.storeSpendActivityView(spendActivityView, in: defaults)
    }

    func readsTokenSpendChanged(from old: Bool) {
        guard readsTokenSpend != old else { return }
        Self.storeReadsTokenSpend(readsTokenSpend, in: defaults)
    }

    /// The span last chosen, or `.week` when nothing is stored or what is
    /// stored no longer names an offered range.
    ///
    /// Takes the store as an argument, rather than reaching for
    /// `UserDefaults.standard`, so the round trip can be pinned against an
    /// isolated suite. `restored()` and `spendSpan`'s observer both go through
    /// this and `storeSpendSpan`, so what a test exercises is the one
    /// production uses.
    static func storedSpendSpan(in defaults: UserDefaults) -> SpendSpan {
        defaults.string(forKey: Key.spendSpan)
            .flatMap(SpendSpan.init(rawValue:)) ?? .default
    }

    static func storeSpendSpan(_ span: SpendSpan, in defaults: UserDefaults) {
        defaults.set(span.rawValue, forKey: Key.spendSpan)
    }

    /// The key the chosen span lives under. Internal so a test can store a
    /// value the picker no longer offers and prove the fallback; nothing
    /// outside the module can see it either way.
    static var spendSpanDefaultsKey: String { Key.spendSpan }

    /// The chart view last chosen, or the daily grid when nothing is stored or
    /// what is stored is no longer offered. Takes the store as an argument so
    /// the round trip can be pinned against an isolated suite.
    static func storedSpendActivityView(in defaults: UserDefaults) -> ActivityView {
        defaults.string(forKey: Key.spendActivityView)
            .flatMap(ActivityView.init(rawValue:)) ?? .default
    }

    static func storeSpendActivityView(_ view: ActivityView, in defaults: UserDefaults) {
        defaults.set(view.rawValue, forKey: Key.spendActivityView)
    }

    static var spendActivityViewDefaultsKey: String { Key.spendActivityView }

    static func storedReadsTokenSpend(in defaults: UserDefaults) -> Bool {
        defaults.settingsFlag(Key.readsTokenSpend, default: Default.readsTokenSpend)
    }

    static func storeReadsTokenSpend(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: Key.readsTokenSpend)
    }
}
