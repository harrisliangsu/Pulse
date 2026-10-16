// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// Reports where the pointer is inside the panel, by sampling its position
/// rather than by listening for enter/exit events.
///
/// The location is given in the tracked view's own coordinates, with the
/// origin at its top-left corner to match SwiftUI, or `nil` when the pointer
/// is outside the panel altogether. Callers decide what counts as "still on
/// the panel" — the window's frame is not a useful answer to that, because
/// most of this panel is transparent space the content does not occupy.
///
/// Enter/exit events proved unusable for this. Views appearing, disappearing
/// and animating under a stationary pointer fire spurious exits; acting on
/// one closes the card, which puts the pointer back on a ring, which opens it
/// again — an endless open/close loop. Sampling the pointer's actual position
/// cannot be knocked out of sync by animation, by a view sliding underneath,
/// or by an event that never arrives.
///
/// Attach as a background of a view that fills the panel.
struct PanelPointerWatcher: NSViewRepresentable {
    let onChange: (CGPoint?) -> Void
    /// Answers where the pointer is now, in the same space, between samples.
    var probe: PointerProbe?

    func makeNSView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.onChange = onChange
        probe?.view = view
        return view
    }

    func updateNSView(_ view: WatcherView, context: Context) {
        view.onChange = onChange
        probe?.view = view
    }

    static func dismantleNSView(_ view: WatcherView, coordinator: ()) {
        view.stop()
    }

    final class WatcherView: NSView {
        var onChange: ((CGPoint?) -> Void)?

        /// Matches SwiftUI's top-left origin, so the reported point can be
        /// compared against SwiftUI frames without flipping it first.
        override var isFlipped: Bool { true }

        /// Fast enough to feel immediate when the pointer leaves, slow enough
        /// to be free.
        private static let interval: TimeInterval = 0.15

        private var timer: Timer?
        private var lastReported: CGPoint??

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? stop() : start()
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            lastReported = nil
        }

        private func start() {
            guard timer == nil else { return }

            let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            // Keep sampling while menus or other modal run loops are up.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        /// Makes the next sample report wherever the pointer is, even where
        /// it was last reported. See `PointerProbe.reportAgain`.
        func reportAgain() {
            lastReported = nil
        }

        /// The pointer now, or nil off the panel. Not throttled or deduplicated.
        func currentPoint() -> CGPoint? {
            guard let window else { return nil }
            let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            return bounds.contains(local) ? local : nil
        }

        private func sample() {
            guard window != nil else { return }
            let point = currentPoint()

            // Only speak up when something actually changed, so a resting
            // pointer doesn't churn SwiftUI state six times a second.
            if let lastReported, Self.isSame(lastReported, point) { return }

            lastReported = point
            onChange?(point)
        }

        private static func isSame(_ a: CGPoint?, _ b: CGPoint?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?): abs(a.x - b.x) < 1 && abs(a.y - b.y) < 1
            default: false
            }
        }
    }
}

/// Where the pointer is at this moment, for a decision that cannot wait for
/// the next sample: the last one reported can be 150ms old, which is most of
/// `PanelIntent.notchDwell`, so a pointer that had already left would still
/// read as inside.
@MainActor
final class PointerProbe {
    fileprivate weak var view: PanelPointerWatcher.WatcherView?

    func current() -> CGPoint? { view?.currentPoint() }

    /// Has the next sample report the pointer even if it has not moved.
    ///
    /// **Samples are deduplicated, so something that opens the panel by
    /// another path has to ask for one.** A card or the rail opened by a
    /// tracking area's enter that arrives late — behind a busy main thread,
    /// or from a ring crossed between two samples — lands after the sampler
    /// has already reported the pointer gone. Every later sample is that
    /// same "gone", so nothing reported it again and the card stayed open
    /// until the pointer came back and left once more.
    func reportAgain() { view?.reportAgain() }
}
