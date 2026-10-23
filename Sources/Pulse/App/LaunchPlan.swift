// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// How this process was started, as far as the launch signals can say.
///
/// `.uncertain` is not a guess that the launch was at login. The window
/// decision treats it as a manual launch, so a person who opened Blinky
/// still gets the main window when the signal is missing.
enum LaunchKind: Equatable, Sendable {
    case login
    case manual
    case uncertain
}

/// What can be read about the launch without asking the window server to
/// decide anything. Built by `LaunchSignalReader`; classified here.
struct LaunchSignals: Equatable, Sendable {
    /// `keyAELaunchedAsLogInItem` (`'lgit'`) on the open-application event.
    enum LoginItemFlag: Equatable, Sendable {
        /// The event was readable and carried the flag.
        case present(Bool)
        /// The open-application event was readable and the flag was not set.
        /// Finder, Spotlight, Launchpad and `open -a` launch that way.
        case absent
        /// There was no open-application event to read.
        case unreadable
    }

    var loginItemFlag: LoginItemFlag
    /// Bundle identifier of the parent process, when that parent is an app.
    var parentBundleIdentifier: String?
    /// Last path component of the parent executable, without an extension,
    /// lowercased. `launchd` is a normal parent of a GUI app and is not
    /// treated as a login launcher.
    var parentExecutableName: String?

    static let unknown = LaunchSignals(
        loginItemFlag: .unreadable,
        parentBundleIdentifier: nil,
        parentExecutableName: nil
    )
}

/// Login-item detection for `SMAppService`.
///
/// There is no supported "why did I start?" API. Two signals are read, and
/// a login launch is reported only when one of them is positive:
///
/// 1. `keyAELaunchedAsLogInItem` on the `kAEOpenApplication` event. Present
///    and true is a login launch; present and false is a manual launch.
/// 2. When that flag is missing, the parent process. `loginwindow` and
///    BackgroundTaskManagement are the processes that start a modern login
///    item. `launchd` is not: on current macOS it is the parent of an
///    ordinary open as well.
///
/// Anything else is `.manual` when the open event was readable (the flag's
/// absence is how a person opens the app) and `.uncertain` when the event
/// could not be read and the parent is not a known launcher. Uncertain
/// follows the manual path.
enum LaunchClassification {
    /// Bundle identifiers that start a login item. `launchd` is deliberately
    /// absent.
    static let loginLauncherBundles: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.backgroundtaskmanagementagent"
    ]

    /// Executable names, lowercased, without a path or extension.
    static let loginLauncherExecutables: Set<String> = [
        "loginwindow",
        "backgroundtaskmanagementagent",
        "backgroundtaskmanagementd"
    ]

    static let manualLauncherBundles: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.Spotlight",
        "com.apple.Terminal"
    ]

    static let manualLauncherExecutables: Set<String> = [
        "finder",
        "dock",
        "spotlight",
        "terminal",
        "open"
    ]

    static func kind(_ signals: LaunchSignals) -> LaunchKind {
        switch signals.loginItemFlag {
        case .present(true):
            return .login
        case .present(false):
            return .manual
        case .absent:
            // A readable open event without the flag is a person's launch,
            // unless the parent is one of the login launchers — SMAppService
            // has been seen to omit the flag.
            return isLoginLauncher(signals) ? .login : .manual
        case .unreadable:
            if isLoginLauncher(signals) { return .login }
            if isManualLauncher(signals) { return .manual }
            return .uncertain
        }
    }

    static func isLoginLauncher(_ signals: LaunchSignals) -> Bool {
        if let id = signals.parentBundleIdentifier, loginLauncherBundles.contains(id) { return true }
        if let name = signals.parentExecutableName, loginLauncherExecutables.contains(name) { return true }
        return false
    }

    static func isManualLauncher(_ signals: LaunchSignals) -> Bool {
        if let id = signals.parentBundleIdentifier, manualLauncherBundles.contains(id) { return true }
        if let name = signals.parentExecutableName, manualLauncherExecutables.contains(name) { return true }
        return false
    }
}

/// What a launch or a reopen does with the main window and the first-run
/// prompts. The panel and the menu bar item are not in here: they follow
/// their own settings, on a login launch as on any other.
struct LaunchDecision: Equatable, Sendable {
    /// Open today's Settings window, titled Blinky, on the pane it already
    /// uses (Appearance, until the reader moves).
    var showMainWindow: Bool
    /// The provider chooser, initial or the one-time upgrade suggestion.
    var showProviderChooser: Bool
    /// Status-line offer, Claude desktop keychain prompt, and the chooser.
    var showFirstRunPrompts: Bool
    /// Those prompts wait for a later manual open or a reopen.
    var deferFirstRunPrompts: Bool
}

enum LaunchPlanner {
    /// A cold launch. `.uncertain` matches `.manual`: show the window.
    /// A login launch never shows the chooser or the other first-run prompts;
    /// the main window follows `showMainWindowAtLogin` only.
    static func onLaunch(
        kind: LaunchKind,
        showMainWindowAtLogin: Bool,
        needsProviderSelection: Bool,
        hasSuggestedProviders: Bool
    ) -> LaunchDecision {
        let promptsDue = needsProviderSelection || hasSuggestedProviders
        switch kind {
        case .login:
            return LaunchDecision(
                showMainWindow: showMainWindowAtLogin,
                showProviderChooser: false,
                showFirstRunPrompts: false,
                deferFirstRunPrompts: true
            )
        case .manual, .uncertain:
            return LaunchDecision(
                showMainWindow: true,
                showProviderChooser: promptsDue,
                showFirstRunPrompts: true,
                deferFirstRunPrompts: false
            )
        }
    }

    /// What is already on screen when the app is opened again. A recap does
    /// not stand in for the main window, and an open main window is brought
    /// forward rather than built a second time.
    enum ReopenSurface: Equatable, Sendable {
        case noWindow
        case mainWindowOpen
        case recapOnly
    }

    struct ReopenDecision: Equatable, Sendable {
        var showMainWindow: Bool
        /// The main window is already open; order it front instead of
        /// placing a new one.
        var orderFront: Bool
        var showProviderChooser: Bool
        var releaseDeferredPrompts: Bool
        /// A recap that is open stays open.
        var leaveRecapOpen: Bool
    }

    /// Dock, Finder, Spotlight, Launchpad, or `open -a` while Blinky is
    /// already running. The main window comes forward in every case.
    static func onReopen(
        needsProviderSelection: Bool,
        hasSuggestedProviders: Bool,
        surface: ReopenSurface
    ) -> ReopenDecision {
        let showChooser = needsProviderSelection || hasSuggestedProviders
        switch surface {
        case .noWindow:
            return ReopenDecision(
                showMainWindow: true,
                orderFront: false,
                showProviderChooser: showChooser,
                releaseDeferredPrompts: true,
                leaveRecapOpen: false
            )
        case .mainWindowOpen:
            return ReopenDecision(
                showMainWindow: true,
                orderFront: true,
                showProviderChooser: showChooser,
                releaseDeferredPrompts: true,
                leaveRecapOpen: false
            )
        case .recapOnly:
            return ReopenDecision(
                showMainWindow: true,
                orderFront: false,
                showProviderChooser: showChooser,
                releaseDeferredPrompts: true,
                leaveRecapOpen: true
            )
        }
    }
}

/// The upgrade chooser is offered once because restoration stamps every
/// built-in provider as offered. A login launch that does not show the
/// chooser has to put that stamp back, or quitting without a manual open
/// would spend the offer unseen.
enum UpgradeOfferStamp {
    static func shouldWithhold(deferFirstRunPrompts: Bool, hasSuggestedProviders: Bool) -> Bool {
        deferFirstRunPrompts && hasSuggestedProviders
    }
}

/// The menu bar icon is forced back on when hiding it would leave no way
/// into Blinky. The note in General is that event, not the bare fact that
/// the panel is hidden: an icon that was never hidden has nothing to explain.
enum MenuBarRestoreNote {
    static func record(
        currentlyRecorded: Bool,
        hidesMenuBarIcon: Bool,
        mustRemainVisible: Bool
    ) -> Bool {
        if hidesMenuBarIcon && mustRemainVisible { return true }
        if !mustRemainVisible { return false }
        return currentlyRecorded
    }
}

/// Closing the main window, the chooser, or a recap leaves Blinky running.
/// The Dock's Quit is a separate question (`DockQuit`) and is unchanged.
enum AppLifetime {
    static let terminatesWhenLastWindowCloses = false
}

/// The main window's title. The sidebar and the panes keep their own names.
enum MainWindowTitle {
    static let localizationKey = "Blinky"
}
