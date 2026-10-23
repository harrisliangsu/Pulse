// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The summary window beside the floating panel.
///
/// A normal window, so Escape and a click outside can dismiss it. The usage
/// panel cannot become key, which is why this is not drawn inside that panel.
@MainActor
final class SpendGlanceController {
    private let settings: AppSettings
    private let model: SpendGlanceModel
    private var window: SpendGlancePanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    /// The entry button, in screen coordinates. A click there toggles; it is
    /// not a click outside.
    var entryRect = CGRect.null
    /// The rail's screen rect, the edge, and the visible frame. Supplied by
    /// the panel controller, which is created beside this one.
    var anchor: () -> SpendGlanceAnchor? = { nil }

    init(settings: AppSettings) {
        self.settings = settings
        model = SpendGlanceModel(settings: settings)
    }

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
            window.level = anchor.level
            let frame = SpendGlancePlacement.frame(
                rail: anchor.rail,
                edge: anchor.edge,
                screen: anchor.screen,
                cardClearance: anchor.cardClearance
            )
            window.setFrame(frame, display: false)
        }
        window.title = String.localized("Token spend")
        installMonitors()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        model.isOpen = false
        removeMonitors()
        window?.orderOut(nil)
    }

    private func share() {
        guard SpendGlanceExport.copy(model.picture) else { return }
        model.noteCopied()
    }

    private func makeWindow() -> SpendGlancePanel {
        let window = SpendGlancePanel(
            contentRect: NSRect(origin: .zero, size: SpendGlancePlacement.size),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.backgroundColor = .windowBackgroundColor
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.onDismiss = { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: SpendGlanceView(
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
        // key code and a window identity can. Same split as the shortcut recorder.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            let type = event.type
            let keyCode = event.keyCode
            let eventWindow = event.window.map { ObjectIdentifier($0) }
            let point = NSEvent.mouseLocation
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self, let window = self.window, window.isVisible else { return false }
                if type == .keyDown {
                    if keyCode == 53, eventWindow == ObjectIdentifier(window) {
                        self.close()
                        return true
                    }
                    return false
                }
                if window.frame.contains(point) || self.entryRect.contains(point) { return false }
                self.close()
                return false
            }
            return swallow ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

struct SpendGlanceAnchor {
    var rail: CGRect
    var edge: PanelEdge
    var screen: CGRect
    var cardClearance: CGFloat
    var level: NSWindow.Level
}

/// Escape and the close button both dismiss. Clicks outside are the controller's monitors.
final class SpendGlancePanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        onDismiss?()
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
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
                    if !picture.agents.isEmpty {
                        agents(picture)
                    }
                    if !picture.bars.isEmpty {
                        activity(picture)
                    }
                    footnotes(picture)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 16)
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
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: SpendGlance.spanTitle(settings.spendSpan, custom: settings.spendCustomDays))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(String.localized("Refresh")) { model.rescan += 1 }
                .disabled(model.isScanning)
            Button(shareLabel, action: onShare)
                .disabled(!model.figuresReady || model.isScanning)
        }
        .controlSize(.small)
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
                .font(.system(size: picture.cost == nil && picture.costNote == nil ? 15 : 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let cost = picture.cost {
                Text(verbatim: cost)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
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
            ForEach(Array(picture.agents.enumerated()), id: \.offset) { _, agent in
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
                            .fill(Color.primary.opacity(0.85))
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
            SpendGlanceBars(bars: picture.bars, quiet: Color.primary.opacity(0.2), ink: Color.primary.opacity(0.85))
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
    let quiet: Color
    let ink: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                barMark(bar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func barMark(_ bar: SpendGlancePicture.Bar) -> some View {
        if let tokens = bar.tokens {
            Capsule()
                .fill(tokens > 0 ? ink : quiet)
                .frame(height: tokens > 0 ? max(4, 56 * bar.share) : 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        } else {
            Color.clear
        }
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
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                if let cost = picture.cost {
                    Text(verbatim: cost)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
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
                    ForEach(Array(picture.agents.enumerated()), id: \.offset) { _, agent in
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
                                .fill(ink.opacity(0.92))
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
                    SpendGlanceBars(bars: picture.bars, quiet: ink.opacity(0.22), ink: ink.opacity(0.92))
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
