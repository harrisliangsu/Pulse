import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Not private: the menu bar scene reads the language from it so the menu
    /// rebuilds when the language changes.
    let settings = AppSettings.restored()
    /// Not private for the same reason: the menu bar scene shows a newer
    /// version when there is one.
    let update = AppUpdate()
    private let placement = PanelPlacement.restored()
    /// Not private: the settings pane shows what the system says about
    /// permission, which is not the same as what the switches say.
    private(set) lazy var alerts = UsageAlerts(settings: settings)
    /// Not private for the same reason: the settings pane is the only place
    /// that can report a combination the window server refused.
    let shortcuts = GlobalShortcutMonitor()
    private lazy var store = UsageStore(settings: settings, alerts: alerts)

    private var panelController: FloatingPanelController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // **Writing to a pipe whose far end has closed raises SIGPIPE, whose
        // default is to kill the process.** Pulse writes to one: the Codex
        // helper's standard input. So that helper exiting — crashing, being
        // killed with the terminal it was started from, the user quitting
        // Codex — took Pulse down with it, with nothing in the log but
        // "Terminated due to signal 13". Ignored here rather than in
        // `CodexAppServer` because it is a property of the whole process, and
        // because the failure it prevents is not local to the caller that
        // happened to trigger it. The write then returns an error, which
        // `CodexAppServer.write(_:to:)` reads as the helper being gone.
        signal(SIGPIPE, SIG_IGN)

        // Keep the registered status line path pointing at wherever this
        // build actually lives, since rebuilding can move it.
        StatusLineHook.repairPathIfNeeded()

        // Caches whose format changed are invalidated by renaming the file;
        // this takes the orphans away rather than leaving them on disk.
        PulseStorage.removeSupersededFiles()

        // A launch agent left over from a loose build has to be handed over
        // before anything reads the state, or both builds start at login.
        LoginItem.adoptBundleIfNeeded()

        // On by default, decided once — and repaired rather than re-added, so
        // switching it off stays off.
        LoginItem.applyDefaultOnFirstRun()
        LoginItem.repairPathIfNeeded()

        // Daily at most, and only from a bundle — see `AppUpdate`.
        update.checkIfDue()

        // Asks for the Claude desktop app's keychain item now rather than
        // leaving it behind a setting nobody would think to open. Fenced and
        // asked once — see `requestPermissionAtLaunch`. It runs off this
        // thread, since the dialog blocks whoever raised it.
        let claudeCode = AccountKey(.claudeCode)
        let claudeSource = settings.source(for: claudeCode)
        ClaudeDesktopSession.requestPermissionAtLaunch(
            willBeUsed: settings.isEnabled(claudeCode)
                && [.automatic, .desktopApp].contains(claudeSource)
        ) { [weak self] in
            // A grant is a new route, and the pass that just went out did not
            // have it.
            self?.store.refresh(claudeCode)
        }

        // Before the first pass, so nothing is decided about a reading before
        // the memory of what has already been said is in place. Deliberately
        // does not ask for permission — see `UsageAlerts.start`.
        alerts.start { [weak self] in self?.showSettings() }

        store.start()

        let controller = FloatingPanelController(
            store: store,
            settings: settings,
            placement: placement,
            openSettings: { [weak self] in self?.showSettings() }
        )
        panelController = controller

        settings.onChange = { [weak self] in
            controller.settingsChanged()
            self?.settingsWindow?.refreshTitle()
            // Changing where the figures come from — or how often they're
            // read — should show up now, not at the next tick.
            self?.store.settingsChanged()
        }

        // A secondary click on the rail is a way into settings that does not
        // go through the menu bar at all — which is the point, since a full
        // menu bar is where Pulse's icon stops being reachable. Issue #24.
        controller.contextMenu = { [weak self] in self?.panelMenu() ?? NSMenu() }

        // Same issue, from the other side: a combination that works with no
        // pointer involved. Both unset until somebody sets one.
        shortcuts.on(.openSettings) { [weak self] in self?.showSettings() }
        shortcuts.on(.togglePanel) { [weak self] in
            // Through the setting rather than `controller.toggle()`, so the
            // panel is in the state the switch in settings claims it is, and
            // stays that way across a launch.
            self?.settings.isPanelVisible.toggle()
        }
        shortcuts.apply(settings)

        if settings.isPanelVisible {
            controller.show()
        }

        // Once ever, and only for someone who has Claude Code. After the panel
        // is actually on screen: a modal put up any earlier blocks the launch
        // and asks for something while the app is still invisible.
        StatusLineHook.offerOnFirstRun()
    }

    func showSettings() {
        showSettings(link: nil)
    }

    /// The rail's own menu: the same three things the menu bar offers, because
    /// this exists for the Mac where that menu cannot be reached.
    ///
    /// Built on each click rather than kept, so an update found since the last
    /// one is on it — an `NSMenu` held as a property would still be showing
    /// whatever was true when it was made.
    private func panelMenu() -> NSMenu {
        let menu = NSMenu()

        if let newer = update.newer {
            let item = NSMenuItem(
                title: .localized("Pulse \(newer.version) is available"),
                action: #selector(checkForUpdate),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(
            title: .localized("Settings…"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: .localized("Quit Pulse"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func checkForUpdate() {
        update.check()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let link = PulseLink(url: url) { showSettings(link: link) }
        }
    }

    private func showSettings(link: PulseLink?) {
        let window = settingsWindow ?? SettingsWindowController(store: store, settings: settings, placement: placement, update: update, alerts: alerts, shortcuts: shortcuts)
        settingsWindow = window
        window.show(link: link)
    }
}
