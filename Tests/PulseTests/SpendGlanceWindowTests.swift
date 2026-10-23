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
        #expect(!window.isKind(of: NSPanel.self))
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
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        pump()
        window.contentView?.layoutSubtreeIfNeeded()
        let content = try #require(window.contentView)
        let views = Self.flatten(content)
        // SwiftUI's menu picker is a popup view, not an NSPopUpButton the
        // test can downcast. Refresh and Share are not NSButtons either:
        // they are accessibility elements in this same tree.
        let menus = views.filter {
            let name = String(describing: type(of: $0))
            return name.contains("PopupButton") || name.contains("PopUpButton")
        }
        #expect(menus.count >= 2)
        for menu in menus {
            #expect(Self.contains(Self.hit(menu, in: content), menu))
        }

        let nodes = Self.axNodes(from: content)
        let described = Self.describe(nodes)
        let refresh = try #require(
            Self.control("spend-glance-refresh", label: String.localized("Refresh"), in: nodes),
            "Refresh was not in the accessibility tree: \(described)"
        )
        let share = try #require(
            Self.control("spend-glance-share", label: String.localized("Share this summary"), in: nodes),
            "Share was not in the accessibility tree: \(described)"
        )
        #expect(Self.hit(refresh, in: content, window: window) != nil)
        #expect(Self.hit(share, in: content, window: window) != nil)

        // Share before Refresh. Refresh starts a read, and that read must not
        // be what this click is proving.
        try Self.click(share, in: window)
        pump()
        #expect(controller.model.didCopy || controller.model.copyFailed)
        let note = controller.model.didCopy
            ? String.localized("Copied to the clipboard.")
            : String.localized("Could not copy.")
        let noted = Self.axNodes(from: content).contains { node in
            Self.identifier(of: node) == "spend-glance-copy-note" || Self.label(of: node) == note
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
        menu.orderOut(nil)

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
            #expect(Self.contains(hit, close))
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

    /// The macOS 26 SDK does not put these getters on `NSObject`. They are
    /// still the AppKit methods, so the test reads them by name.
    private static func axNodes(from root: Any?) -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        var output: [NSObject] = []
        func walk(_ object: Any?, depth: Int) {
            guard depth < 12, output.count < 400, let object = object as? NSObject else { return }
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            output.append(object)
            for child in children(of: object) {
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return output
    }

    private static func children(of object: NSObject) -> [NSObject] {
        let names = [
            "accessibilityChildren",
            "accessibilityVisibleChildren",
            "accessibilityChildrenInNavigationOrder",
        ]
        var found: [NSObject] = []
        for name in names {
            guard object.responds(to: NSSelectorFromString(name)) else { continue }
            let value = object.value(forKey: name)
            if let list = value as? [NSObject] {
                found.append(contentsOf: list)
            } else if let list = value as? NSArray {
                found.append(contentsOf: list.compactMap { $0 as? NSObject })
            }
        }
        return found
    }

    private static func identifier(of object: NSObject) -> String? {
        text(object, "accessibilityIdentifier")
    }

    private static func label(of object: NSObject) -> String? {
        text(object, "accessibilityLabel")
    }

    private static func text(_ object: NSObject, _ name: String) -> String? {
        guard object.responds(to: NSSelectorFromString(name)) else { return nil }
        return object.value(forKey: name) as? String
    }

    private static func frame(of object: NSObject) -> NSRect {
        let name = "accessibilityFrame"
        guard object.responds(to: NSSelectorFromString(name)) else { return .zero }
        return (object.value(forKey: name) as? NSValue)?.rectValue ?? .zero
    }

    private static func control(_ identifier: String, label: String, in nodes: [NSObject]) -> NSObject? {
        nodes.first { Self.identifier(of: $0) == identifier }
            ?? nodes.first { Self.label(of: $0) == label }
    }

    private static func describe(_ nodes: [NSObject]) -> String {
        nodes.prefix(30).map { node in
            let id = identifier(of: node) ?? "-"
            let label = label(of: node) ?? "-"
            return "\(type(of: node)) id=\(id) label=\(label)"
        }.joined(separator: " | ")
    }

    private static func hit(_ control: NSView, in root: NSView) -> NSView? {
        let inWindow = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        guard let superview = root.superview else { return root.hitTest(inWindow) }
        return root.hitTest(superview.convert(inWindow, from: nil))
    }

    private static func hit(_ element: NSObject, in root: NSView, window: NSWindow) -> NSView? {
        let frame = frame(of: element)
        guard !frame.isEmpty else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        guard let superview = root.superview else { return root.hitTest(inWindow) }
        return root.hitTest(superview.convert(inWindow, from: nil))
    }

    private static func contains(_ hit: NSView?, _ control: NSView) -> Bool {
        var view = hit
        while let current = view {
            if current === control { return true }
            view = current.superview
        }
        return false
    }

    private static func click(_ element: NSObject, in window: NSWindow) throws {
        let frame = frame(of: element)
        try #require(!frame.isEmpty)
        let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
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
