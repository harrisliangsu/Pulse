// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Testing
@testable import Pulse

/// Launch, reopen, Dock policy, and the new settings. The decisions are pure;
/// the window server is not involved.
@Suite("Main window on launch")
struct MainWindowLaunchTests {
    private static let kinds: [LaunchKind] = [.login, .manual, .uncertain]

    @Test("A manual or uncertain launch opens the main window; a login launch follows the setting")
    func launchWindow() {
        for kind in Self.kinds {
            for showAtLogin in [false, true] {
                for needsSelection in [false, true] {
                    let decision = LaunchPlanner.onLaunch(
                        kind: kind,
                        showMainWindowAtLogin: showAtLogin,
                        needsProviderSelection: needsSelection,
                        hasSuggestedProviders: false
                    )
                    switch kind {
                    case .login:
                        #expect(decision.showMainWindow == showAtLogin)
                        #expect(!decision.showProviderChooser)
                        #expect(!decision.showFirstRunPrompts)
                        #expect(decision.deferFirstRunPrompts)
                    case .manual, .uncertain:
                        #expect(decision.showMainWindow)
                        #expect(decision.showProviderChooser == needsSelection)
                        #expect(decision.showFirstRunPrompts)
                        #expect(!decision.deferFirstRunPrompts)
                    }
                }
            }
        }
    }

    @Test("An uncertain launch decides the same window as a manual one")
    func uncertainMatchesManual() {
        for showAtLogin in [false, true] {
            for needsSelection in [false, true] {
                for suggestions in [false, true] {
                    let manual = LaunchPlanner.onLaunch(
                        kind: .manual,
                        showMainWindowAtLogin: showAtLogin,
                        needsProviderSelection: needsSelection,
                        hasSuggestedProviders: suggestions
                    )
                    let uncertain = LaunchPlanner.onLaunch(
                        kind: .uncertain,
                        showMainWindowAtLogin: showAtLogin,
                        needsProviderSelection: needsSelection,
                        hasSuggestedProviders: suggestions
                    )
                    #expect(manual == uncertain)
                }
            }
        }
    }

    @Test("A login launch defers the chooser even when the main window is shown, and a manual launch shows a suggestion")
    func promptsAndSuggestions() {
        let quiet = LaunchPlanner.onLaunch(
            kind: .login, showMainWindowAtLogin: false,
            needsProviderSelection: true, hasSuggestedProviders: false
        )
        #expect(quiet == LaunchDecision(
            showMainWindow: false, showProviderChooser: false,
            showFirstRunPrompts: false, deferFirstRunPrompts: true
        ))

        let loginWithWindow = LaunchPlanner.onLaunch(
            kind: .login, showMainWindowAtLogin: true,
            needsProviderSelection: false, hasSuggestedProviders: true
        )
        #expect(loginWithWindow.showMainWindow)
        #expect(!loginWithWindow.showProviderChooser)
        #expect(loginWithWindow.deferFirstRunPrompts)

        let manualSuggestion = LaunchPlanner.onLaunch(
            kind: .manual, showMainWindowAtLogin: false,
            needsProviderSelection: false, hasSuggestedProviders: true
        )
        #expect(manualSuggestion.showMainWindow)
        #expect(manualSuggestion.showProviderChooser)
        #expect(manualSuggestion.showFirstRunPrompts)
        #expect(!manualSuggestion.deferFirstRunPrompts)

        // The show-at-login switch does not change a manual launch.
        let manualIgnoringSwitch = LaunchPlanner.onLaunch(
            kind: .manual, showMainWindowAtLogin: true,
            needsProviderSelection: false, hasSuggestedProviders: false
        )
        #expect(manualIgnoringSwitch.showMainWindow)
        #expect(!manualIgnoringSwitch.showProviderChooser)
    }

    @Test("Reopening brings the main window forward, including over a recap, and releases a deferred chooser")
    func reopen() {
        let surfaces: [LaunchPlanner.ReopenSurface] = [.noWindow, .mainWindowOpen, .recapOnly]
        for surface in surfaces {
            for needsSelection in [false, true] {
                for suggestions in [false, true] {
                    let decision = LaunchPlanner.onReopen(
                        needsProviderSelection: needsSelection,
                        hasSuggestedProviders: suggestions,
                        surface: surface
                    )
                    #expect(decision.showMainWindow)
                    #expect(decision.releaseDeferredPrompts)
                    #expect(decision.showProviderChooser == (needsSelection || suggestions))
                    switch surface {
                    case .noWindow:
                        #expect(!decision.orderFront)
                        #expect(!decision.leaveRecapOpen)
                    case .mainWindowOpen:
                        #expect(decision.orderFront)
                        #expect(!decision.leaveRecapOpen)
                    case .recapOnly:
                        #expect(!decision.orderFront)
                        #expect(decision.leaveRecapOpen)
                    }
                }
            }
        }
    }

    @Test("The main window still opens on Appearance")
    @MainActor
    func opensOnAppearance() {
        #expect(SettingsNavigation().pane == .appearance)
        #expect(MainWindowTitle.localizationKey == "Blinky")
    }

    @Test("Closing the last window does not quit")
    func staysRunning() {
        #expect(!AppLifetime.terminatesWhenLastWindowCloses)
    }

    @Test("The upgrade offer stamp is put back only when a login launch deferred a suggestion")
    func offerStamp() {
        #expect(UpgradeOfferStamp.shouldWithhold(deferFirstRunPrompts: true, hasSuggestedProviders: true))
        #expect(!UpgradeOfferStamp.shouldWithhold(deferFirstRunPrompts: true, hasSuggestedProviders: false))
        #expect(!UpgradeOfferStamp.shouldWithhold(deferFirstRunPrompts: false, hasSuggestedProviders: true))
        #expect(!UpgradeOfferStamp.shouldWithhold(deferFirstRunPrompts: false, hasSuggestedProviders: false))
    }

    @Test("Withholding the stamp restores the offered list, and showing the chooser stamps it again")
    func offerStampRoundTrip() {
        let (defaults, cleanup) = TestDefaults.make("offerStamp")
        defer { cleanup() }
        defaults.set(["codex"], forKey: ProviderSelection.enabledKey)
        defaults.set(["codex"], forKey: ProviderSelection.offeredKey)

        let settings = AppSettings.restoredSettings(
            from: defaults, detected: [.cursor], scan: ExtensionCatalog.Scan()
        )
        #expect(settings.suggestedProviders.contains(.cursor))
        let stamped = defaults.stringArray(forKey: ProviderSelection.offeredKey) ?? []
        #expect(stamped.contains(Provider.cursor.rawValue))

        settings.withholdUpgradeOfferStamp()
        #expect(defaults.stringArray(forKey: ProviderSelection.offeredKey) == ["codex"])

        settings.stampOfferedProviders()
        let again = defaults.stringArray(forKey: ProviderSelection.offeredKey) ?? []
        #expect(again.contains(Provider.cursor.rawValue))
        #expect(again.contains(Provider.codex.rawValue))
    }

    @Test("The menu bar note is recorded only when the icon had to be turned back on")
    func menuBarRestoreNote() {
        let cases: [(Bool, Bool, Bool, Bool)] = [
            // currently, hides, must remain, expected
            (false, false, false, false),
            (false, false, true, false),
            (false, true, false, false),
            (false, true, true, true),
            (true, false, false, false),
            (true, false, true, true),
            (true, true, false, false),
            (true, true, true, true),
        ]
        for (recorded, hides, must, expected) in cases {
            #expect(
                MenuBarRestoreNote.record(
                    currentlyRecorded: recorded,
                    hidesMenuBarIcon: hides,
                    mustRemainVisible: must
                ) == expected
            )
        }
        // An icon that was never hidden does not grow the note just because
        // the panel is off and no shortcut is registered.
        #expect(!MenuBarRestoreNote.record(
            currentlyRecorded: false, hidesMenuBarIcon: false, mustRemainVisible: true
        ))
    }

    @Test("Dock policy: always-show, a tracked window, the while-open switch, and an update offer")
    func activationPolicy() {
        for always in [false, true] {
            for tracked in [false, true] {
                for whileOpen in [false, true] {
                    for offer in [false, true] {
                        let policy = DockPresence.activationPolicy(
                            alwaysShowsDockIcon: always,
                            trackedWindowOpen: tracked,
                            showsDockIconInSettings: whileOpen,
                            updateOfferVisible: offer
                        )
                        if always {
                            #expect(policy == .regular)
                        } else {
                            let wants = (tracked && whileOpen) || offer
                            #expect(policy == (wants ? .regular : .accessory))
                        }
                    }
                }
            }
        }
    }

    @Test("The service chooser is a tracked window, so it takes the Dock icon on the same rule")
    func chooserIsTracked() {
        #expect(
            DockPresence.activationPolicy(
                alwaysShowsDockIcon: false,
                trackedWindowOpen: true,
                showsDockIconInSettings: true,
                updateOfferVisible: false
            ) == .regular
        )
        #expect(
            DockPresence.activationPolicy(
                alwaysShowsDockIcon: false,
                trackedWindowOpen: true,
                showsDockIconInSettings: false,
                updateOfferVisible: false
            ) == .accessory
        )
        // Always-show does not need the chooser, or any window, to be open.
        #expect(
            DockPresence.activationPolicy(
                alwaysShowsDockIcon: true,
                trackedWindowOpen: false,
                showsDockIconInSettings: false,
                updateOfferVisible: false
            ) == .regular
        )
    }

    @Test("Launch sets .regular only when the Dock icon is always shown")
    func launchPolicy() {
        #expect(DockPresence.launchPolicy(alwaysShowsDockIcon: false) == .accessory)
        #expect(DockPresence.launchPolicy(alwaysShowsDockIcon: true) == .regular)
    }

    @Test("New keys default off and the existing Dock and panel keys are unchanged")
    func defaultsAndKeys() {
        #expect(AppSettings.Key.showMainWindowAtLogin == "settings.showMainWindowAtLogin")
        #expect(AppSettings.Key.alwaysShowsDockIcon == "settings.alwaysShowsDockIcon")
        #expect(AppSettings.Key.menuBarIconRestoreNote == "settings.menuBarIconRestoreNote")
        #expect(AppSettings.Default.showMainWindowAtLogin == false)
        #expect(AppSettings.Default.alwaysShowsDockIcon == false)
        #expect(AppSettings.Default.menuBarIconRestoreNote == false)

        #expect(AppSettings.Key.showsDockIconInSettings == "settings.showsDockIconInSettings")
        #expect(AppSettings.Default.showsDockIconInSettings == true)
        #expect(AppSettings.Key.hidesMenuBarIcon == "settings.hidesMenuBarIcon")
        #expect(AppSettings.Default.hidesMenuBarIcon == false)
        #expect(AppSettings.Key.panelVisible == "settings.panelVisible")
        #expect(AppSettings.Default.isPanelVisible == true)
    }

    @Test("The new flags persist, and Always show Dock icon uses the Dock callback")
    @MainActor
    func persistenceAndCallback() {
        let (defaults, cleanup) = TestDefaults.make("mainWindowSettings")
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.showMainWindowAtLogin)
        #expect(!settings.alwaysShowsDockIcon)
        #expect(!settings.menuBarIconRestoreNote)
        #expect(settings.showsDockIconInSettings)
        #expect(settings.isPanelVisible)

        var dockChanges = 0
        var panelChanges = 0
        settings.onDockIconChange = { dockChanges += 1 }
        settings.onChange = { panelChanges += 1 }

        settings.showMainWindowAtLogin = true
        #expect(defaults.object(forKey: "settings.showMainWindowAtLogin") as? Bool == true)
        #expect(dockChanges == 0)
        #expect(panelChanges == 0)

        settings.alwaysShowsDockIcon = true
        #expect(defaults.object(forKey: "settings.alwaysShowsDockIcon") as? Bool == true)
        #expect(dockChanges == 1)
        #expect(panelChanges == 0)

        settings.menuBarIconRestoreNote = true
        #expect(defaults.object(forKey: "settings.menuBarIconRestoreNote") as? Bool == true)
        #expect(dockChanges == 1)
        #expect(panelChanges == 0)

        let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())
        #expect(back.showMainWindowAtLogin)
        #expect(back.alwaysShowsDockIcon)
        #expect(back.menuBarIconRestoreNote)
        #expect(back.showsDockIconInSettings)
        #expect(back.isPanelVisible)
    }

    @Test("The login flag is read from the open-application event, and a missing event stays unreadable")
    func loginItemFlag() {
        let open = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        #expect(LaunchSignalReader.flag(in: open) == .absent)

        open.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: LaunchSignalReader.loginItemKeyword
        )
        #expect(LaunchSignalReader.flag(in: open) == .present(true))

        open.setParam(
            NSAppleEventDescriptor(boolean: false),
            forKeyword: LaunchSignalReader.loginItemKeyword
        )
        #expect(LaunchSignalReader.flag(in: open) == .present(false))

        let quit = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEQuitApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        #expect(LaunchSignalReader.flag(in: quit) == .unreadable)
        #expect(LaunchSignalReader.flag(in: nil) == .unreadable)

        let kept = LaunchSignalReader.merge(
            existing: LaunchSignals(
                loginItemFlag: .present(true),
                parentBundleIdentifier: "com.apple.loginwindow",
                parentExecutableName: "loginwindow"
            ),
            event: nil
        )
        #expect(kept.loginItemFlag == .present(true))
        #expect(kept.parentBundleIdentifier == "com.apple.loginwindow")

        let replaced = LaunchSignalReader.merge(existing: kept, event: open)
        #expect(replaced.loginItemFlag == .present(false))
        #expect(replaced.parentExecutableName == "loginwindow")
    }

    @Test("Login is reported only from a positive signal; anything uncertain is not called a login")
    func classification() {
        #expect(LaunchClassification.kind(signals(.present(true))) == .login)
        #expect(LaunchClassification.kind(signals(.present(false))) == .manual)
        #expect(LaunchClassification.kind(signals(.absent)) == .manual)
        #expect(LaunchClassification.kind(signals(.unreadable)) == .uncertain)

        // An explicit false wins over a login launcher as the parent.
        #expect(LaunchClassification.kind(signals(
            .present(false),
            bundle: "com.apple.loginwindow",
            executable: "loginwindow"
        )) == .manual)

        // SMAppService omitting the flag, with a login launcher as parent.
        #expect(LaunchClassification.kind(signals(
            .absent, bundle: "com.apple.backgroundtaskmanagementagent", executable: nil
        )) == .login)
        #expect(LaunchClassification.kind(signals(
            .unreadable, bundle: nil, executable: "backgroundtaskmanagementd"
        )) == .login)
        #expect(LaunchClassification.kind(signals(
            .unreadable, bundle: "com.apple.loginwindow", executable: nil
        )) == .login)

        // launchd is the parent of an ordinary open. It is not a login launch.
        #expect(LaunchClassification.kind(signals(
            .unreadable, bundle: nil, executable: "launchd"
        )) == .uncertain)
        #expect(LaunchClassification.kind(signals(
            .absent, bundle: nil, executable: "launchd"
        )) == .manual)

        #expect(LaunchClassification.kind(signals(
            .unreadable, bundle: "com.apple.finder", executable: nil
        )) == .manual)
        #expect(LaunchClassification.kind(signals(
            .unreadable, bundle: "com.apple.dock", executable: "dock"
        )) == .manual)
        #expect(LaunchClassification.kind(signals(
            .unreadable, bundle: nil, executable: "spotlight"
        )) == .manual)
        #expect(LaunchClassification.kind(signals(
            .unreadable, bundle: nil, executable: "open"
        )) == .manual)
        #expect(LaunchClassification.kind(signals(
            .absent, bundle: "com.apple.finder", executable: "finder"
        )) == .manual)
    }

    @Test("The new rows have copy in every language, and the simplified Chinese names are the ones on screen")
    func localizedCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let keys = [
            "Startup and windows",
            "Show main window when opened at login",
            "The main window opens when Blinky starts at login.",
            "Always show Dock icon",
            "Blinky stays in the Dock and in ⌘-Tab, including while every window is closed.",
            "Show Dock icon while a window is open",
            "The icon is there while the main window, a recap, or the service chooser is open, and it goes when they close.",
            "Blinky turned the menu bar icon back on, because the panel is hidden and no shortcut is registered.",
            "Blinky",
        ]
        let productName = "Blinky"
        for language in ["en", "zh-Hans", "zh-Hant", "ja", "ko", "ru"] {
            let file = root.appendingPathComponent("Sources/Pulse/Resources/\(language).lproj/Localizable.strings")
            let pairs = try Self.pairs(in: file)
            for key in keys {
                let value = try #require(pairs[key], "\(language) is missing \(key)")
                #expect(!value.isEmpty)
                if language != "en", key != productName {
                    #expect(value != key, "\(language) left \(key) in English")
                }
            }
            #expect(pairs[productName] == productName)
            #expect(pairs["Show Dock icon while Settings or a recap is open"] == nil)
        }
        let chinese = try Self.pairs(
            in: root.appendingPathComponent("Sources/Pulse/Resources/zh-Hans.lproj/Localizable.strings")
        )
        #expect(chinese["Startup and windows"] == "启动与窗口")
        #expect(chinese["Show main window when opened at login"] == "开机自启时显示主窗口")
        #expect(chinese["Open at login"] == "开机启动")
        #expect(chinese["Show floating panel"] == "显示悬浮面板")
    }

    private static func pairs(in file: URL) throws -> [String: String] {
        let text = try String(contentsOf: file, encoding: .utf8)
        var pairs: [String: String] = [:]
        let pattern = #/^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"/#
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let match = line.firstMatch(of: pattern) else { continue }
            pairs[String(match.1)] = String(match.2)
        }
        return pairs
    }

    private func signals(
        _ flag: LaunchSignals.LoginItemFlag,
        bundle: String? = nil,
        executable: String? = nil
    ) -> LaunchSignals {
        LaunchSignals(
            loginItemFlag: flag,
            parentBundleIdentifier: bundle,
            parentExecutableName: executable
        )
    }
}
