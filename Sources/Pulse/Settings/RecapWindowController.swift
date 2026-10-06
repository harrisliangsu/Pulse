// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// Owns the recap window.
///
/// AppKit-owned for the reason the settings window is: Pulse is an `.accessory`
/// app that is rarely active, so a window has to activate it explicitly or it
/// opens behind whatever the person was looking at — and it shares the Dock
/// icon rule (`DockPresence`), so a covered recap can be found again.
///
/// **Nothing is read while it is closed.** The model's ledgers and every recap
/// built from them are dropped when the window closes (`RecapWindowModel`), and
/// a read still running is cancelled.
@MainActor
final class RecapWindowController {
    private let settings: AppSettings
    private let dock: DockPresence
    private let openTokenSpend: @MainActor () -> Void
    private let model: RecapWindowModel
    private var window: RecapWindow?
    private var titleGeneration = 0

    init(settings: AppSettings, dock: DockPresence, openTokenSpend: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.dock = dock
        self.openTokenSpend = openTokenSpend
        model = RecapWindowModel(settings: settings)
    }

    /// Opens the window, on a period if one is named and on the one it already
    /// shows if it is open and none is.
    func show(period: Recap.Period? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        model.begin(on: period)
        refreshTitle()
        trackTitle()

        let wasVisible = window.isVisible
        window.makeKeyAndOrderFront(nil)
        if !wasVisible { window.center() }
        dock.apply()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Re-reads the title, which has to follow the language and the kind of
    /// period while the window is open.
    func refreshTitle() {
        window?.title = model.isYear ? .localized("Yearly Recap") : .localized("Monthly Recap")
    }

    /// The title follows the Month / Year choice. Re-armed on every change,
    /// because `withObservationTracking` fires once.
    private func trackTitle() {
        titleGeneration += 1
        let generation = titleGeneration
        withObservationTracking {
            _ = model.isYear
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.titleGeneration == generation, self.window?.isVisible == true else { return }
                self.refreshTitle()
                self.trackTitle()
            }
        }
    }

    private func makeWindow() -> RecapWindow {
        let window = RecapWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.onClose = { [weak self, weak window] in
            self?.model.windowDidClose()
            // The files handed to the share sheet are not kept past the window.
            RecapExport.removeShareFolder()
            // `close()` runs this before the window is off screen.
            self?.dock.apply(closing: window)
        }
        // ← and → turn the page, while this window is the key one and no field
        // is being edited — the window's own handling, not a global monitor.
        window.onArrow = { [weak self] direction in
            guard let self, let deck = self.model.deck, !deck.cards.isEmpty else { return }
            self.model.step(direction, in: deck)
        }
        dock.track(window)
        window.contentView = NSHostingView(
            rootView: RecapWindowView(model: model, settings: settings, openTokenSpend: openTokenSpend)
        )
        return window
    }
}

/// The recap window: closing is reported before it happens, a click outside
/// the price field ends its editing (`NSWindow.endFieldEditing(ifOutside:)`),
/// and the arrow keys turn the page.
final class RecapWindow: NSWindow {
    var onClose: (() -> Void)?
    /// -1 for ←, 1 for →.
    var onArrow: ((Int) -> Void)?

    override func close() {
        // Ends the price field's editing first, which commits what was typed:
        // closing mid-entry keeps the price, as Return or a click away would.
        makeFirstResponder(nil)
        onClose?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        endFieldEditing(ifOutside: event)
        if event.type == .keyDown, isKeyWindow,
           let direction = Self.direction(of: event, editing: fieldBeingEdited() != nil),
           Self.takesArrows(firstResponder) {
            onArrow?(direction)
            return
        }
        super.sendEvent(event)
    }

    /// Whether the first responder leaves ← and → to the window. Not a control
    /// that uses them itself — the Month / Year segments, a popup, a slider, a
    /// stepper, a text view — and not any other control but a plain button
    /// (arrows mean nothing to one); the window itself, its content and the
    /// views drawn in it do.
    static func takesArrows(_ responder: NSResponder?) -> Bool {
        switch responder {
        case nil: return true
        case is NSText, is NSSegmentedControl, is NSPopUpButton, is NSSlider, is NSStepper, is NSTextField,
             is NSComboBox, is NSDatePicker, is NSTableView, is NSOutlineView:
            return false
        case let control as NSControl:
            return control is NSButton
        default:
            return true
        }
    }

    /// ← or → pressed alone and not inside a field, which keeps its caret keys.
    static func direction(of event: NSEvent, editing: Bool) -> Int? {
        guard !editing, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: return -1
        case 124: return 1
        default: return nil
        }
    }
}
