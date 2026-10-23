// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The summary window beside the floating panel.
///
/// A normal window, so Escape, the close button, and a click outside can
/// dismiss it. The usage panel cannot become key, which is why this is not
/// drawn inside that panel.
@MainActor
final class SpendGlanceController {
    private let settings: AppSettings
    let model: SpendGlanceModel
    private let dock: DockPresence?
    private var window: SpendGlancePanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    /// The entry button, in screen coordinates. A click there toggles; it is
    /// not a click outside.
    var entryRect = CGRect.null
    /// The rail's screen rect, the edge, and the visible frame. Supplied by
    /// the panel controller, which is created beside this one.
    var anchor: () -> SpendGlanceAnchor? = { nil }

    init(settings: AppSettings, dock: DockPresence? = nil) {
        self.settings = settings
        self.dock = dock
        model = SpendGlanceModel(settings: settings)
    }

    /// Whether the summary is open. False while reading is off: `show` and
    /// `toggle` both leave it closed, and neither makes a window.
    var isOpen: Bool { model.isOpen }

    func toggle() {
        guard settings.readsTokenSpend else {
            close()
            return
        }
        if window?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard settings.readsTokenSpend else { return }
        let window = window ?? makeWindow()
        self.window = window
        model.isOpen = true
        if let anchor = anchor(), !window.isVisible {
            window.level = SpendGlanceWindowLevel.above(anchor.level)
            let frame = SpendGlancePlacement.frame(
                rail: anchor.rail,
                edge: anchor.edge,
                screen: anchor.screen,
                cardClearance: anchor.cardClearance
            )
            window.setFrame(frame, display: false)
        }
        window.title = String.localized("Token spend")
        window.standardWindowButton(.closeButton)?.isEnabled = true
        installMonitors()
        dock?.track(window)
        // Same activation as the main window. A utility panel at the rail's
        // level never became key, so menus and the close button received nothing.
        window.makeKeyAndOrderFront(nil)
        if let dock {
            dock.apply(showingWindow: window)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
        }
    }

    func close() {
        model.isOpen = false
        let closing = window
        window?.orderOut(nil)
        if let closing { dock?.apply(closing: closing) }
        // `NSEvent.removeMonitor` must not run inside the monitor's own
        // handler. Escape and a click outside both come through that handler,
        // so the removal waits until this call has returned.
        let local = localMonitor
        let global = globalMonitor
        guard local != nil || global != nil else { return }
        localMonitor = nil
        globalMonitor = nil
        DispatchQueue.main.async {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
        }
    }

    private func share() {
        if SpendGlanceExport.copy(model.picture) {
            model.noteCopied()
        } else {
            model.noteCopyFailed()
        }
    }

    private func makeWindow() -> SpendGlancePanel {
        // A normal window, not a utility panel. A utility panel at the rail's
        // level does not become key, and SwiftUI menus and buttons in it
        // never see the click. The title bar is the system's, so the close
        // button is not covered by the content view.
        let window = SpendGlancePanel(
            contentRect: NSRect(origin: .zero, size: SpendGlancePlacement.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.onDismiss = { [weak self] in self?.close() }
        window.contentView = SpendGlanceHostingView(rootView: SpendGlanceView(
            model: model,
            settings: settings,
            onShare: { [weak self] in self?.share() },
            onDismiss: { [weak self] in self?.close() }
        ))
        return window
    }

    private func installMonitors() {
        guard localMonitor == nil else { return }
        // Monitors run on the main thread. The handler is not annotated with
        // the main actor, and an `NSEvent` cannot cross into that body — a
        // key code, whether a modifier is held, and a window identity can.
        // Same split as the shortcut recorder.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            let eventType = event.type
            let keyCode = event.keyCode
            let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            let eventWindow = event.window.map { ObjectIdentifier($0) }
            // The click's own window and point. The cursor is a fallback for an
            // event that names no window; a real click and a synthesized one
            // then name the same place. The window number crosses into the
            // actor; the window does not.
            let windowNumber = event.windowNumber
            let locationInWindow = event.locationInWindow
            let swallowEscape = MainActor.assumeIsolated { () -> Bool in
                guard let self, let window = self.window, window.isVisible else { return false }
                if eventType == .keyDown {
                    // A menu or a date popover owns Escape. Closing the summary
                    // here used to throw the picker away as it opened.
                    let menuOpen = NSApp.windows.contains {
                        $0 !== window && $0.isVisible && SpendGlanceWindowLevel.isAuxiliary($0)
                    }
                    guard !menuOpen else { return false }
                    guard SpendGlanceDismissal.shouldCloseOnEscape(
                        keyCode: keyCode,
                        hasModifiers: hasModifiers,
                        eventWindow: eventWindow,
                        glanceWindow: ObjectIdentifier(window)
                    ) else { return false }
                    window.close()
                    return true
                }
                let source = NSApp.window(withWindowNumber: windowNumber)
                let auxiliary = source.map { window in
                    SpendGlanceWindowLevel.isAuxiliary(
                        level: window.level,
                        className: String(describing: Swift.type(of: window))
                    )
                } ?? false
                let point = source?.convertPoint(toScreen: locationInWindow) ?? NSEvent.mouseLocation
                let inside = window.frame.contains(point) || self.entryRect.contains(point)
                if SpendGlanceWindowLevel.dismisses(inside: inside, auxiliary: auxiliary) {
                    self.close()
                }
                return false
            }
            return swallowEscape ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

struct SpendGlanceAnchor {
    var rail: CGRect
    var edge: PanelEdge
    var screen: CGRect
    var cardClearance: CGFloat
    var level: NSWindow.Level
}

/// Where the summary sits relative to the rail and to menus.
///
/// The rail can be at `.statusBar`. A window at that same level, or a utility
/// panel, does not keep a menu in front of it, so a picker looks dead. Stay
/// one level above the rail and strictly under `.popUpMenu`.
enum SpendGlanceWindowLevel {
    static func above(_ rail: NSWindow.Level) -> NSWindow.Level {
        let menu = NSWindow.Level.popUpMenu.rawValue
        let next = max(rail.rawValue, NSWindow.Level.floating.rawValue) + 1
        if next >= menu { return NSWindow.Level(rawValue: menu - 1) }
        return NSWindow.Level(rawValue: next)
    }

    static func isAuxiliary(_ window: NSWindow) -> Bool {
        // The monitor that calls this runs on the main thread, and a window's
        // level is isolated to that actor. The call is not in a main-actor
        // function: the event itself cannot cross into one.
        let level = MainActor.assumeIsolated { window.level }
        return isAuxiliary(level: level, className: String(describing: type(of: window)))
    }

    /// A menu, a popover, or a date picker. A click there is part of a control
    /// in this window, not a click outside it.
    static func isAuxiliary(level: NSWindow.Level, className: String) -> Bool {
        if level.rawValue >= NSWindow.Level.popUpMenu.rawValue { return true }
        return className.contains("Menu")
            || className.contains("Popover")
            || className.contains("Picker")
            || className.contains("Date")
    }

    static func dismisses(inside: Bool, auxiliary: Bool) -> Bool {
        !inside && !auxiliary
    }
}

/// What closes the glance window, without a window server: plain Escape, and
/// a click that lands inside the close button. A modified Escape is a
/// different shortcut. An empty button is one that has not been laid out.
enum SpendGlanceDismissal {
    static let escapeKeyCode: UInt16 = 53

    static func shouldCloseOnEscape(keyCode: UInt16, hasModifiers: Bool) -> Bool {
        keyCode == escapeKeyCode && !hasModifiers
    }

    /// Escape dismisses this window unless the event is already aimed at a
    /// different one. A key event that has not been given a window yet still
    /// belongs here.
    static func shouldCloseOnEscape(
        keyCode: UInt16,
        hasModifiers: Bool,
        eventWindow: ObjectIdentifier?,
        glanceWindow: ObjectIdentifier
    ) -> Bool {
        guard shouldCloseOnEscape(keyCode: keyCode, hasModifiers: hasModifiers) else { return false }
        if let eventWindow, eventWindow != glanceWindow { return false }
        return true
    }

    static func claimsCloseClick(buttonBounds: CGRect, pointInButton: CGPoint) -> Bool {
        !buttonBounds.isEmpty && buttonBounds.contains(pointInButton)
    }
}

/// Escape and the close button both dismiss. Clicks outside are the controller's monitors.
///
/// This is an `NSWindow`, not a panel. A utility panel never became key while
/// Blinky was an accessory app, and every SwiftUI control in it — the time
/// range, the dimension, Share — then ignored the click. The title bar is
/// the system's, so the close button is not under the content view.
/// `performClose` still closes directly: ⌘W and the button share one path.
/// Escape is taken here while this window is key. A menu that is key keeps it.
final class SpendGlancePanel: NSWindow {
    var onDismiss: (() -> Void)?
    private var closing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        // `onDismiss` orders the window out, which can re-enter `close` while
        // a click or Escape is still being delivered.
        guard !closing else { return }
        closing = true
        defer { closing = false }
        onDismiss?()
        super.close()
    }

    /// The button's action, and ⌘W.
    override func performClose(_ sender: Any?) {
        close()
    }

    override func sendEvent(_ event: NSEvent) {
        // Mouse events are not taken here. The previous override closed on a
        // geometry test and returned before the content view, which is how a
        // picker and Share could be clicked and still do nothing.
        if event.type == .keyDown, isKeyWindow,
           SpendGlanceDismissal.shouldCloseOnEscape(
               keyCode: event.keyCode,
               hasModifiers: !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
           ) {
            close()
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if SpendGlanceDismissal.shouldCloseOnEscape(
            keyCode: event.keyCode,
            hasModifiers: !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        ) {
            close()
            return
        }
        super.keyDown(with: event)
    }
}

/// The hosted summary. The first click has to reach the control even when
/// the window was not yet key: an accessory app's window otherwise eats it
/// as an activation click and the picker looks dead.
final class SpendGlanceHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Records a control's window rectangle without taking the click.
///
/// Refresh and Share are SwiftUI buttons. macOS 26 does not put an `NSButton`
/// under them, and asking the hosting view for its accessibility children
/// returns the view itself. The test needs the rectangle the button laid out
/// so it can send the click there. `hitTest` returns nil, so the press falls
/// through to the button.
struct ControlFrameProbe: NSViewRepresentable {
    var id: String
    var onFrame: (String, CGRect) -> Void

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onFrame = { [onFrame, id] frame in onFrame(id, frame) }
        nsView.report()
    }

    final class ProbeView: NSView {
        var onFrame: ((CGRect) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        func report() {
            guard window != nil, bounds.width > 1, bounds.height > 1 else { return }
            onFrame?(convert(bounds, to: nil))
        }
    }
}

/// Copies the branded summary. The image is the picture's text and bars;
/// nothing is written to disk.
@MainActor
enum SpendGlanceExport {
    static let pointSize = CGSize(width: 680, height: 920)

    static func copy(_ picture: SpendGlancePicture) -> Bool {
        let renderer = ImageRenderer(content: SpendGlancePoster(picture: picture).frame(width: pointSize.width, height: pointSize.height))
        renderer.proposedSize = ProposedViewSize(pointSize)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = pointSize
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }
}

/// The window's contents. The share image is `SpendGlancePoster`, drawn again
/// from the same picture, not a screenshot of this view.
struct SpendGlanceView: View {
    let model: SpendGlanceModel
    let settings: AppSettings
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let _ = settings.language
        let picture = model.picture
        let ready = model.figuresReady
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !ready {
                    reading
                } else {
                    overview(picture)
                    dimensionPicker
                    if !picture.agents.isEmpty {
                        agents(picture)
                    }
                    if !picture.bars.isEmpty {
                        activity(picture)
                    }
                    footnotes(picture)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, minHeight: 280)
        .task(id: model.loadKey) { await model.load() }
        .task(id: model.summaryRequest) { await model.recompute() }
        .onChange(of: settings.readsTokenSpend) { _, enabled in
            if !enabled { onDismiss() }
        }
    }

    private var header: some View {
        let shareLabel = model.didCopy
            ? String.localized("Copied")
            : String.localized("Share this summary")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Picker("", selection: Binding(
                    get: { settings.spendSpan },
                    set: { settings.spendSpan = $0 }
                )) {
                    ForEach(SpendSpan.allCases) { span in
                        Text(span.title).tag(span)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 180, alignment: .leading)
                .accessibilityIdentifier("spend-glance-span")
                Spacer(minLength: 8)
                Button(String.localized("Refresh")) { model.rescan += 1 }
                    .disabled(model.isScanning)
                    .accessibilityIdentifier("spend-glance-refresh")
                    .background(ControlFrameProbe(id: "spend-glance-refresh", onFrame: model.noteControlFrame))
                Button(shareLabel, action: onShare)
                    .disabled(!model.figuresReady || model.isScanning)
                    .accessibilityIdentifier("spend-glance-share")
                    .background(ControlFrameProbe(id: "spend-glance-share", onFrame: model.noteControlFrame))
            }
            if model.didCopy {
                Text(localized: "Copied to the clipboard.")
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityIdentifier("spend-glance-copy-note")
            } else if model.copyFailed {
                Text(localized: "Could not copy.")
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityIdentifier("spend-glance-copy-note")
            }
            if settings.spendSpan == .custom {
                customDatePickers
            }
        }
        .controlSize(.small)
    }

    /// The same two days as Settings, neither after today, the first never after the last.
    private var customDatePickers: some View {
        let today = Calendar.current.startOfDay(for: Date())
        return HStack(spacing: 6) {
            DatePicker("", selection: Binding(
                get: { settings.spendCustomDays.lowerBound },
                set: {
                    let first = Calendar.current.startOfDay(for: $0)
                    settings.spendCustomDays = first...max(settings.spendCustomDays.upperBound, first)
                }
            ), in: ...today, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .accessibilityLabel(String.localized("First day"))

            Text(verbatim: "–")
                .foregroundStyle(.secondary)

            DatePicker("", selection: Binding(
                get: { settings.spendCustomDays.upperBound },
                set: {
                    let last = Calendar.current.startOfDay(for: $0)
                    settings.spendCustomDays = min(settings.spendCustomDays.lowerBound, last)...last
                }
            ), in: ...today, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .accessibilityLabel(String.localized("Last day"))
        }
    }

    private var dimensionPicker: some View {
        Picker("", selection: Binding(
            get: { settings.spendGlanceDimension },
            set: { settings.spendGlanceDimension = $0 }
        )) {
            ForEach(SpendGlanceDimension.allCases) { dimension in
                Text(dimension.title).tag(dimension)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 180, alignment: .leading)
        .accessibilityIdentifier("spend-glance-dimension")
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView()
                .controlSize(.small)
            if let progress = model.progress {
                Text(String.localized("Reading \(progress.agent.displayName)…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(localized: "Reading…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func overview(_ picture: SpendGlancePicture) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: picture.tokens)
                .font(.system(size: SpendGlanceHeadline.tokenPointSize, weight: .semibold))
                .monospacedDigit()
            if let cost = picture.cost {
                Text(verbatim: cost)
                    .font(.system(size: SpendGlanceHeadline.moneyPointSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let note = picture.costNote {
                Text(verbatim: note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func agents(_ picture: SpendGlancePicture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: picture.agentsTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(Array(picture.agents.enumerated()), id: \.offset) { index, agent in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: agent.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: agent.tokens)
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let cost = agent.cost {
                            Text(verbatim: cost)
                                .font(.system(size: 12))
                                .monospacedDigit()
                        }
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(SpendGlancePalette.color(at: index))
                            .frame(width: max(proxy.size.width * agent.share, agent.share > 0 ? 2 : 0), height: 4)
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    private func activity(_ picture: SpendGlancePicture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: picture.activityTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            SpendGlanceBars(bars: picture.bars)
                .frame(height: 56)
        }
    }

    private func footnotes(_ picture: SpendGlancePicture) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(picture.footnotes.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Fourteen days as bars. A missing day is a gap; a quiet day is a hairline.
struct SpendGlanceBars: View {
    let bars: [SpendGlancePicture.Bar]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                barMark(bar, index: index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func barMark(_ bar: SpendGlancePicture.Bar, index: Int) -> some View {
        if let tokens = bar.tokens {
            Capsule()
                .fill(SpendGlancePalette.color(at: index).opacity(tokens > 0 ? 1 : 0.28))
                .frame(height: tokens > 0 ? max(4, 56 * bar.share) : 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        } else {
            Color.clear
        }
    }
}

extension SpendGlancePalette {
    static func color(at index: Int) -> Color {
        let swatch = swatch(at: index)
        return Color(red: swatch.red, green: swatch.green, blue: swatch.blue)
    }
}

/// The image Share puts on the clipboard. Flat colours only: `ImageRenderer`
/// does not draw materials or AppKit controls.
struct SpendGlancePoster: View {
    let picture: SpendGlancePicture

    private let ink = Color.white
    private let secondary = Color.white.opacity(0.62)
    private let ground = Color(red: 0.09, green: 0.09, blue: 0.11)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: picture.brand)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text(localized: "Token spend")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: picture.span)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(secondary)
                Text(verbatim: picture.tokens)
                    .font(.system(size: SpendGlanceHeadline.posterTokenPointSize, weight: .semibold, design: .rounded))
                if let cost = picture.cost {
                    Text(verbatim: cost)
                        .font(.system(size: SpendGlanceHeadline.posterMoneyPointSize, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                }
                if let note = picture.costNote {
                    Text(verbatim: note)
                        .font(.system(size: 14))
                        .foregroundStyle(secondary)
                }
            }
            if !picture.agents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: picture.agentsTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondary)
                    ForEach(Array(picture.agents.enumerated()), id: \.offset) { index, agent in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: agent.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 12)
                                Text(verbatim: agent.tokens)
                                    .font(.system(size: 15))
                                    .monospacedDigit()
                                    .foregroundStyle(secondary)
                                if let cost = agent.cost {
                                    Text(verbatim: cost)
                                        .font(.system(size: 15))
                                        .monospacedDigit()
                                }
                            }
                            Capsule()
                                .fill(SpendGlancePalette.color(at: index))
                                .frame(width: 560 * agent.share, height: 6)
                        }
                    }
                }
            }
            if !picture.bars.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: picture.activityTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondary)
                    SpendGlanceBars(bars: picture.bars)
                        .frame(height: 88)
                }
            }
            Spacer(minLength: 12)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(picture.footnotes.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.system(size: 12))
                            .foregroundStyle(secondary)
                    }
                }
                Spacer()
                Text(verbatim: picture.brand)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.38))
            }
        }
        .padding(36)
        .foregroundStyle(ink)
        .background(ground)
        .environment(\.colorScheme, .dark)
    }
}

#if DEBUG
#Preview("Token spend summary") {
    SpendGlancePoster(picture: SpendGlancePicture(
        span: "Last 7 days",
        tokens: "12.4M tokens",
        cost: "$4.20",
        costNote: "Partial estimate",
        agentsTitle: "By agent",
        agents: [
            .init(name: "Claude Code", tokens: "8.1M", cost: "$3.10", share: 1),
            .init(name: "Codex", tokens: "4.3M", cost: "$1.10*", share: 0.53)
        ],
        activityTitle: "Last 14 days",
        bars: (0..<14).map { index in
            .init(tokens: index < 3 ? nil : index * 10, share: index < 3 ? 0 : Double(index) / 13)
        },
        footnotes: ["Updated just now", "Counts may be incomplete."]
    ))
    .frame(width: 680, height: 920)
}
#endif
