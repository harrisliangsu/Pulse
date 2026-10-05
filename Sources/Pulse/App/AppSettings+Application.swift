// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The app's own shell: the menu bar item, the Dock icon the settings window
// brings, the two global shortcuts, and the interface language. None of it is
// a reading, so none of it asks the usage loop to do anything — except the
// language, whose strings are on screen in the panel as well.

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
    }
}
