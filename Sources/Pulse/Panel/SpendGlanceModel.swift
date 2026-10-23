// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

/// The glance window's reading.
///
/// Opening shows the scan `SpendWarmer` already kept and does not walk the
/// stores again. Refresh is the explicit rescan: it uses the same read id as
/// Settings, so a close or a switch-off drops a late result.
@MainActor
@Observable
final class SpendGlanceModel {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isOpen = false
    var summary = SpendSummary()
    var activity = SpendGlanceActivity()
    var isScanning = false
    var progress: AgentLedgers.Progress?
    var observedAt: Date?
    var hasReadLimitations = false
    var didCopy = false
    var copyFailed = false
    /// Window coordinates of Refresh and Share, written while they lay out.
    /// Not observed: storing a frame must not lay the window out again. SwiftUI
    /// draws these two without an `NSButton`, and an in-process accessibility
    /// query does not list them, so a test sends the click to this rectangle.
    /// Layout calls in on the main thread; the property is nonisolated so that
    /// call is not an actor hop.
    @ObservationIgnored nonisolated(unsafe) var controlFrames: [String: CGRect] = [:]
    /// Set once the span's figures match `summaryRequest`. Share stays off
    /// until then, so a click cannot copy the empty summary still on screen
    /// while the arithmetic is in flight.
    private(set) var displayedRequest: SpendSummaryCache.Request?
    private(set) var read = SpendGlanceRead()
    var rescan = 0
    private var cache = SpendSummaryCache()
    private var copyClear: Task<Void, Never>?

    var figuresReady: Bool {
        guard let request = summaryRequest else { return false }
        return displayedRequest == request
    }

    var loadKey: SpendGlanceRead.Request {
        SpendGlanceRead.Request(
            isEnabled: settings.readsTokenSpend,
            isOpen: isOpen,
            rescan: rescan
        )
    }

    /// What the figures depend on. A span change recomputes; it does not read.
    var summaryRequest: SpendSummaryCache.Request? {
        guard settings.readsTokenSpend, isOpen, let snapshot = read.snapshotID else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let bounds = settings.spendSpan.bounds(custom: settings.spendCustomDays, now: now, calendar: calendar)
        return SpendSummaryCache.Request(
            window: .init(
                snapshot: snapshot,
                from: bounds.from,
                until: bounds.until,
                today: calendar.startOfDay(for: now),
                calendar: calendar,
                language: settings.language.rawValue
            ),
            agent: nil,
            model: nil
        )
    }

    var picture: SpendGlancePicture {
        SpendGlancePicture.make(
            span: settings.spendSpan,
            custom: settings.spendCustomDays,
            summary: summary,
            activity: activity,
            observedAt: observedAt,
            hasReadLimitations: hasReadLimitations,
            dimension: settings.spendGlanceDimension
        )
    }

    func load() async {
        guard !Task.isCancelled else { return }
        progress = nil
        isScanning = false

        let id: UUID
        let refresh: Bool
        switch read.prepare(loadKey) {
        case .retain:
            return
        case .release:
            clearFigures()
            return
        case .scan(let nextID, let force):
            id = nextID
            refresh = force
        }

        // The kept scan is the one the background reader finished. Showing it
        // is a lookup, not a walk over the stores. Refresh does not take this path.
        if !refresh, let kept = await AgentLedgers.shared.keptSnapshot() {
            guard !Task.isCancelled, read.complete(kept.snapshot, for: id) else { return }
            adopt(kept.snapshot, at: kept.at)
            read.finish(id)
            return
        }

        clearFigures()
        isScanning = true
        defer {
            if read.finish(id) {
                isScanning = false
                progress = nil
            }
        }

        let result: AgentLedgers.Snapshot
        do {
            result = try await AgentLedgers.shared.scan(refresh: refresh) { [weak self] progress in
                guard let self, self.read.isCurrent(id), !Task.isCancelled else { return }
                self.progress = progress
            }
        } catch {
            return
        }
        guard !Task.isCancelled, settings.readsTokenSpend, isOpen, read.complete(result, for: id) else { return }
        adopt(result, at: Date())
    }

    func recompute() async {
        guard let request = summaryRequest else { return }
        guard let result = try? await cache.summaries(for: request, ledgers: read.snapshot?.ledgers ?? [:]),
              !Task.isCancelled, summaryRequest == request else { return }
        summary = result.overview
        activity = SpendGlanceActivity.covering(
            summary: result.overview,
            span: settings.spendSpan,
            custom: settings.spendCustomDays
        )
        displayedRequest = request
    }

    func noteCopied(hold: Duration = SpendGlanceCopy.hold) {
        copyFailed = false
        didCopy = true
        copyClear?.cancel()
        copyClear = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    nonisolated func noteControlFrame(id: String, frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        controlFrames[id] = frame
    }

    func noteCopyFailed() {
        copyClear?.cancel()
        didCopy = false
        copyFailed = true
    }

    /// Shows an empty summary as ready, so Share can be clicked without
    /// walking the stores. A later open reuses it (`SpendGlanceRead` retains
    /// a snapshot it already holds).
    func presentReadySummary() {
        isOpen = true
        read.install(AgentLedgers.Snapshot())
        displayedRequest = summaryRequest
    }

    private func adopt(_ snapshot: AgentLedgers.Snapshot, at date: Date) {
        observedAt = date
        hasReadLimitations = !snapshot.notes.isEmpty
    }

    private func clearFigures() {
        cache = SpendSummaryCache()
        displayedRequest = nil
        summary = SpendSummary()
        activity = SpendGlanceActivity()
        observedAt = nil
        hasReadLimitations = false
        progress = nil
    }
}
