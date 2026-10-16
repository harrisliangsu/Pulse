// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit

/// The Dock icon that follows Pulse's windows.
///
/// Pulse runs as an `.accessory` app, which has no Dock icon and no ⌘-Tab
/// entry, so a window another app has covered cannot be found again. The icon
/// is there while **any** tracked window (Settings, the recap) is on screen and
/// `AppSettings.showsDockIconInSettings` allows it, and Pulse is a menu bar app
/// again the moment neither is true.
///
/// One owner rather than one per window: with each controller setting the
/// policy itself, closing the Settings window under an open recap — or the
/// other way round — took the Dock icon away from the window still showing.
///
/// `.regular` is also what puts Pulse in ⌘-Tab, which is the point.
@MainActor
final class DockPresence {
    private let settings: AppSettings
    private let windows = NSHashTable<NSWindow>.weakObjects()

    init(settings: AppSettings) {
        self.settings = settings
        settings.onDockIconChange = { [weak self] in self?.apply() }
    }

    func track(_ window: NSWindow) {
        windows.add(window)
    }

    /// Closes every window the Dock icon stands for — the answer to the
    /// Dock's Quit (`DockQuit`) — and the icon goes with the last of them.
    func closeWindows() {
        for window in windows.allObjects where window.isVisible || window.isMiniaturized {
            window.close()
        }
        apply()
    }

    /// Re-reads which windows are open. `closing` is a window `close()` is in
    /// the middle of: it still reports visible, so it is left out of the count.
    func apply(closing: NSWindow? = nil) {
        let open = windows.allObjects.contains { $0 !== closing && ($0.isVisible || $0.isMiniaturized) }
        let policy: NSApplication.ActivationPolicy = open && settings.showsDockIconInSettings ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Changing the policy can drop activation, and a window is what the
        // person is looking at.
        if policy == .regular { NSApp.activate(ignoringOtherApps: true) }
    }
}

/// The Dock's Quit, told apart from every other.
///
/// **Pulse's Dock icon stands for its windows, not for Pulse.** It is there
/// only while Settings or a recap is open (`DockPresence`), so its menu's
/// Quit reads as "close this" — and quitting the whole app from it took the
/// panel and every reading away from someone who meant to close Settings.
/// So the Dock's Quit closes the windows, and Pulse stays in the menu bar.
/// Pulse's own Quit — ⌘Q, the app menu, the menu bar icon's — still quits.
///
/// **Told apart by the Apple event that asked**: the Dock asks with a quit
/// event sent from the Dock's own process. Logging out, restarting and shutting
/// down send one too, from loginwindow and with a reason attached; those
/// always quit — holding up a logout is worse than any closed window.
enum DockQuit {
    static func isFromDock(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event else { return false }
        let sender = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))
            .flatMap { pid_t(exactly: $0.int32Value) }
            .flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        return closesWindowsOnly(
            eventClass: event.eventClass,
            eventID: event.eventID,
            sender: sender,
            hasQuitReason: event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
                || event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
        )
    }

    static func closesWindowsOnly(eventClass: AEEventClass, eventID: AEEventID, sender: String?, hasQuitReason: Bool) -> Bool {
        eventClass == AEEventClass(kCoreEventClass)
            && eventID == AEEventID(kAEQuitApplication)
            && sender == "com.apple.dock"
            && !hasQuitReason
    }
}
