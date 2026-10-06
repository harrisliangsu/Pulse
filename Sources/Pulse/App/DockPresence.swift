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
