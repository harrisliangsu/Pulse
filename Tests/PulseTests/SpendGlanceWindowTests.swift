// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Testing
@testable import Pulse

/// Real event delivery through the Token spend window.
///
/// Earlier tests called `SpendGlanceDismissal` with rectangles and key codes.
/// The window on a Mac still dropped the click: a utility panel never became
/// key, `sendEvent` returned before the content view, and the content covered
/// the close button. These tests build that window and send the events.
@MainActor
@Suite("Token spend glance window", .serialized)
struct SpendGlanceWindowTests {
    @Test("The window sits above the rail and under a menu")
    func level() {
        let aboveRail = SpendGlanceWindowLevel.above(.statusBar)
        #expect(aboveRail.rawValue > NSWindow.Level.floating.rawValue)
        #expect(aboveRail.rawValue < NSWindow.Level.popUpMenu.rawValue)
        #expect(SpendGlanceWindowLevel.above(.popUpMenu).rawValue < NSWindow.Level.popUpMenu.rawValue)
        #expect(SpendGlanceWindowLevel.above(.floating).rawValue == NSWindow.Level.floating.rawValue + 1)

        #expect(SpendGlanceWindowLevel.isAuxiliary(level: .popUpMenu, className: "NSWindow"))
        #expect(SpendGlanceWindowLevel.isAuxiliary(level: .normal, className: "NSMenuWindow"))
        #expect(SpendGlanceWindowLevel.isAuxiliary(level: .normal, className: "DatePickerPanel"))
        #expect(!SpendGlanceWindowLevel.isAuxiliary(level: .floating, className: "SpendGlancePanel"))
        #expect(!SpendGlanceWindowLevel.dismisses(inside: true, auxiliary: false))
        #expect(!SpendGlanceWindowLevel.dismisses(inside: false, auxiliary: true))
        #expect(SpendGlanceWindowLevel.dismisses(inside: false, auxiliary: false))
    }

    @Test("Span, breakdown, Refresh, Share, the close button, and Escape all reach the window")
    func controlsReceiveEvents() throws {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        settings.readsTokenSpend = true
        settings.spendSpan = .month

        let controller = SpendGlanceController(settings: settings)
        controller.model.presentReadySummary()
        controller.anchor = {
            SpendGlanceAnchor(
                rail: CGRect(x: 800, y: 700, width: 280, height: 36),
                edge: .right,
                screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                cardClearance: 12,
                level: .statusBar
            )
        }
        controller.show()
        defer {
            settings.readsTokenSpend = false
            controller.close()
        }

        let window = try #require(NSApp.windows.first { $0 is SpendGlancePanel } as? SpendGlancePanel)
        #expect(!(window is NSPanel))
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(!window.styleMask.contains(.utilityWindow))
        #expect(window.level == SpendGlanceWindowLevel.above(.statusBar))
        #expect(window.contentView?.acceptsFirstMouse(for: nil) == true)
        #expect(window.title == "Token spend")

        window.makeKey()
        window.contentView?.layoutSubtreeIfNeeded()
        pump()
        window.contentView?.layoutSubtreeIfNeeded()
        let views = Self.flatten(window.contentView)
        let described = views.map {
            "\(type(of: $0)) id=\($0.accessibilityIdentifier() ?? "-") title=\(($0 as? NSButton)?.title ?? "-")"
        }.joined(separator: "\n")

        let refresh = try #require(
            Self.button(named: "Refresh", identifier: "spend-glance-refresh", in: views),
            "Refresh was not in the window.\n\(described)"
        )
        let share = try #require(
            Self.button(named: "Share this summary", identifier: "spend-glance-share", in: views),
            "Share was not in the window.\n\(described)"
        )
        let menus = views.compactMap { $0 as? NSPopUpButton }
        #expect(menus.count >= 2, "Expected the span and breakdown menus.\n\(described)")

        let content = try #require(window.contentView)
        let refreshHit = Self.hit(refresh, in: content)
        #expect(Self.contains(refreshHit, refresh))
        let shareHit = Self.hit(share, in: content)
        #expect(Self.contains(shareHit, share))
        for menu in menus {
            #expect(Self.contains(Self.hit(menu, in: content), menu))
        }

        // Share before Refresh. Refresh starts a read, and that read must not
        // be what this click is proving.
        #expect(share.isEnabled)
        try Self.click(share, in: window)
        pump()
        #expect(controller.model.didCopy || controller.model.copyFailed)
        let note = controller.model.didCopy
            ? String.localized("Copied to the clipboard.")
            : String.localized("Could not copy.")
        #expect(!note.isEmpty)
        let noted = Self.flatten(window.contentView).contains {
            $0.accessibilityIdentifier() == "spend-glance-copy-note"
        }
        #expect(noted)

        // A menu's click is outside this window's frame and must not dismiss it.
        let menu = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        menu.level = .popUpMenu
        menu.orderFront(nil)
        defer { menu.orderOut(nil) }
        let menuClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: menu.windowNumber,
            context: nil,
            eventNumber: 7,
            clickCount: 1,
            pressure: 1
        ))
        NSApp.sendEvent(menuClick)
        #expect(controller.isOpen)

        // A click in the content must reach the control. The old sendEvent
        // returned before super, so this click changed nothing.
        let rescanBefore = controller.model.rescan
        try Self.click(refresh, in: window)
        #expect(controller.model.rescan == rescanBefore + 1)
        #expect(controller.isOpen)

        let close = try #require(window.standardWindowButton(.closeButton))
        #expect(close.isEnabled)
        if let frame = window.contentView?.superview {
            let hit = Self.hit(close, in: frame)
            #expect(Self.contains(hit, close), "The close button was covered.\n\(described)")
        }
        close.performClick(nil)
        #expect(!controller.isOpen)
        #expect(!window.isVisible)

        controller.show()
        pump()
        let again = try #require(NSApp.windows.first { $0 is SpendGlancePanel })
        again.makeKey()
        pump()
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: again.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: SpendGlanceDismissal.escapeKeyCode
        ))
        if again.isKeyWindow {
            again.sendEvent(escape)
        } else {
            NSApp.sendEvent(escape)
        }
        #expect(!controller.isOpen)
    }

    private func pump() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private static func flatten(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { flatten($0) }
    }

    private static func button(named title: String, identifier: String, in views: [NSView]) -> NSButton? {
        views.compactMap { $0 as? NSButton }.first {
            $0.title == title || $0.accessibilityIdentifier() == identifier || $0.accessibilityLabel() == title
        }
    }

    private static func hit(_ control: NSView, in root: NSView) -> NSView? {
        let point = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: root)
        return root.hitTest(point)
    }

    private static func contains(_ hit: NSView?, _ control: NSView) -> Bool {
        var view = hit
        while let current = view {
            if current === control { return true }
            view = current.superview
        }
        return false
    }

    private static func click(_ control: NSView, in window: NSWindow) throws {
        let point = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))
        window.sendEvent(down)
        window.sendEvent(up)
    }
}
