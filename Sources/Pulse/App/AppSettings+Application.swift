// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The app's own shell: the menu bar item, the Dock icon the settings window
// brings, the two global shortcuts, the interface language and the currency
// estimates are shown in. None of it is a reading, so none of it asks the
// usage loop to do anything — except the language, whose strings are on
// screen in the panel as well. The currency redraws the panel through
// `moneyIdentity` and fetches nothing but the day's rates.

extension AppSettings.Key {
    static let hidesMenuBarIcon = "settings.hidesMenuBarIcon"
    static let showsDockIconInSettings = "settings.showsDockIconInSettings"
    static let showsUsageInMenuBar = "settings.showsUsageInMenuBar"
    static let showsMenuDashboard = "settings.showsMenuDashboard"
    static let menuBarAccount = "settings.menuBarAccount"
    static let menuBarStyle = "settings.menuBarStyle"
    static let openSettingsShortcut = "settings.openSettingsShortcut"
    static let togglePanelShortcut = "settings.togglePanelShortcut"
    static let language = "settings.language"
    static let displayCurrency = "settings.displayCurrency"
    static let manualExchangeRates = "settings.manualExchangeRates"
}

extension AppSettings.Default {
    static let hidesMenuBarIcon = false
    static let showsDockIconInSettings = true
}

extension AppSettings {
    func hidesMenuBarIconChanged(from old: Bool) {
        guard hidesMenuBarIcon != old else { return }
        defaults.set(hidesMenuBarIcon, forKey: Key.hidesMenuBarIcon)
        onMenuBarIconChange?()
    }

    func showsDockIconInSettingsChanged(from old: Bool) {
        guard showsDockIconInSettings != old else { return }
        defaults.set(showsDockIconInSettings, forKey: Key.showsDockIconInSettings)
        onDockIconChange?()
    }

    func showsUsageInMenuBarChanged(from old: Bool) {
        guard showsUsageInMenuBar != old else { return }
        defaults.set(showsUsageInMenuBar, forKey: Key.showsUsageInMenuBar)
        onMenuBarIconChange?()
    }

    func showsMenuDashboardChanged(from old: Bool) {
        guard showsMenuDashboard != old else { return }
        defaults.set(showsMenuDashboard, forKey: Key.showsMenuDashboard)
    }

    func menuBarAccountChanged(from old: String?) {
        guard menuBarAccount != old else { return }
        defaults.set(menuBarAccount, forKey: Key.menuBarAccount)
        onMenuBarIconChange?()
    }

    func menuBarStyleChanged(from old: MenuBarStyle) {
        guard menuBarStyle != old else { return }
        defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle)
        onMenuBarIconChange?()
    }

    func openSettingsShortcutChanged(from old: GlobalShortcut?) {
        guard openSettingsShortcut != old else { return }
        defaults.set(openSettingsShortcut?.storage, forKey: Key.openSettingsShortcut)
    }

    func togglePanelShortcutChanged(from old: GlobalShortcut?) {
        guard togglePanelShortcut != old else { return }
        defaults.set(togglePanelShortcut?.storage, forKey: Key.togglePanelShortcut)
    }

    func languageChanged(from old: AppLanguage) {
        guard language != old else { return }
        LocalizationSource.use(language)
        defaults.set(language.rawValue, forKey: Key.language)
        onChange?()
    }

    func displayCurrencyChanged(from old: DisplayCurrency) {
        guard displayCurrency != old else { return }
        defaults.set(displayCurrency.rawValue, forKey: Key.displayCurrency)
        if drivesPanelMetrics { applyMoney() }
    }

    func manualExchangeRatesChanged(from old: [String: Double]) {
        guard manualExchangeRates != old else { return }
        defaults.set(manualExchangeRates, forKey: Key.manualExchangeRates)
        if drivesPanelMetrics { applyMoney() }
    }

    func exchangeRatesChanged(from old: ExchangeRates.Stored?) {
        guard exchangeRates != old else { return }
        if drivesPanelMetrics { applyMoney() }
    }

    /// The rate typed for `currency`: a positive number keeps it, nil or
    /// anything else goes back to the fetched rate.
    func setManualExchangeRate(_ rate: Double?, for currency: DisplayCurrency) {
        // A dollar is a dollar: there is no rate to type for it.
        guard currency != .usd else { return }
        if let rate, rate.isFinite, rate > 0 {
            manualExchangeRates[currency.code] = rate
        } else {
            manualExchangeRates[currency.code] = nil
        }
    }

    /// Puts the currency and the rates into effect for every formatter. Like
    /// `applyLanguage`, never done in `init`.
    func applyMoney() {
        Money.use(displayCurrency, manualRates: manualExchangeRates)
        Money.useRates(exchangeRates?.rates ?? [:])
    }

    /// What the money on screen depends on, for a view's `.id`: money is
    /// formatted by plain functions, which SwiftUI cannot observe.
    var moneyIdentity: String {
        let code = displayCurrency.code
        return "\(code)-\(manualExchangeRates[code] ?? 0)-\(exchangeRates?.rates[code] ?? 0)"
    }

    /// Puts the stored language into effect. Deliberately not done in `init`:
    /// that would let any throwaway instance — a SwiftUI preview, say — reset
    /// the language the app is actually running in.
    func applyLanguage() {
        LocalizationSource.use(language)
    }

    /// The settings `init` has no parameter for.
    func restoreApplication(from defaults: UserDefaults) {
        showsUsageInMenuBar = defaults.bool(forKey: Key.showsUsageInMenuBar)
        showsMenuDashboard = defaults.bool(forKey: Key.showsMenuDashboard)
        menuBarAccount = defaults.string(forKey: Key.menuBarAccount)
        menuBarStyle = defaults.settingsChoice(Key.menuBarStyle) ?? .figure
        displayCurrency = defaults.settingsChoice(Key.displayCurrency) ?? .default
        manualExchangeRates = (defaults.dictionary(forKey: Key.manualExchangeRates) as? [String: Double] ?? [:])
            .filter { $0.value.isFinite && $0.value > 0 }
    }
}
