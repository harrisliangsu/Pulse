// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

/// The Token spend pane's reading, held for as long as the Settings window
/// lives rather than as long as the pane does.
///
/// The shell owns it and runs `load()` and `recompute()` from two tasks keyed
/// on `loadKey` and `summaryRequest`. They have to be the shell's: leaving the
/// pane, switching reading off or closing the window changes `loadKey`, and
/// the release path only runs if a task is still there to see it.
@MainActor
@Observable
final class SpendPaneModel {
    private let settings: AppSettings
    private let navigation: SettingsNavigation

    init(settings: AppSettings, navigation: SettingsNavigation) {
        self.settings = settings
        self.navigation = navigation
    }

    /// Every agent's spending, for the pane that is not about one provider.
    /// Its own state rather than something derived from `ledgers`, which is
    /// filled one account at a time as their panes are opened.
    var spend = SpendSummary()
    var isScanningSpend = false
    var spendRead = SpendReadState()
    var spendProgress: AgentLedgers.Progress?
    var spendRescan = 0
    /// The agent the spend pane is looking at on its own, and that agent's own
    /// figures. Kept beside the combined ones rather than derived on the fly:
    /// both come out of the same ledgers and the same span, so they cannot
    /// disagree about what a month is.
    var spendFocus: SpendAgent?
    var focusedSpend = SpendSummary()
    /// The year-long activity chart's series, for the agent on screen or all.
    var spendActivity = TokenActivity()
    var spendLedgers: [SpendAgent: UsageLedger] { spendRead.snapshot?.ledgers ?? [:] }
    /// Present sources — installed, or captured/exported somewhere Pulse reads
    /// — that produced no records at all. Named together at the foot of the
    /// pane so a silent source is not mistaken for a zero reading. Not
    /// span-dependent: "nothing was read" is the same answer over any span.
    var spendNoRecords: [SpendAgent] {
        SpendAgent.allCases.filter { spendLedgers[$0]?.allTime.tokens == 0 }
    }
    /// Whether any present source held history a reader could not decode —
    /// a compressed transcript, say. The pane shows a short generic status
    /// rather than dropping those records silently; the readers' own English
    /// diagnostics never reach the view.
    var spendHasReadLimitations: Bool { spendRead.snapshot?.notes.isEmpty == false }
    /// The model the spend pane has drilled into, and that model's own figures
    /// over the same span — crossed with `spendFocus` when an agent is open, so
    /// a model opened from an agent's list counts only that agent's work in it.
    ///
    /// **Not a setting.** Drilling in is a way of reading the page in front of
    /// you, not a preference about the app, so it lives here and is dropped
    /// when the agent changes rather than being written to `AppSettings`.
    var selectedModel: String?
    var modelSpend = ModelSpendSummary()
    var spendSummaryCache = SpendSummaryCache()
    var displayedSpendRequest: SpendSummaryCache.Request?

    /// One task owns opening, enabling and manual rescans. Leaving, disabling
    /// or closing the settings window cancels that same task, even mid-rescan.
    var loadKey: SpendReadState.Request {
        // Keep these separate even away from the pane: closing the window
        // there must still run the release path rather than keep the same "-".
        SpendReadState.Request(
            isEnabled: settings.readsTokenSpend,
            isWindowVisible: navigation.isWindowVisible,
            isPaneSelected: navigation.pane == .spend,
            rescan: spendRescan
        )
    }

    /// What the *figures* depend on, which is read back out of what was loaded.
    var summaryRequest: SpendSummaryCache.Request? {
        guard case .spend = navigation.pane, settings.readsTokenSpend, navigation.isWindowVisible,
              let snapshot = spendRead.snapshotID else { return nil }
        let calendar = Calendar.current
        return SpendSummaryCache.Request(
            window: .init(snapshot: snapshot, days: settings.spendSpan.days,
                          today: calendar.startOfDay(for: Date()), calendar: calendar,
                          language: settings.language.rawValue),
            agent: spendFocus, model: selectedModel
        )
    }

    var summaryIsPending: Bool {
        guard let request = summaryRequest else { return false }
        return displayedSpendRequest.map { !request.canKeepShowing($0) } ?? true
    }

    /// Every agent's ledger, added up.
    ///
    /// Sidebar visits reuse the last completed snapshot. Turning reading off
    /// or closing the window releases it; a later visit revalidates disk caches.
    func load() async {
        guard !Task.isCancelled else { return }
        spendProgress = nil
        isScanningSpend = false

        let id: UUID
        let refresh: Bool
        switch spendRead.prepare(loadKey) {
        case .retain:
            return
        case .release:
            clearSpendSummaries()
            return
        case .scan(let nextID, let force):
            id = nextID
            refresh = force
        }

        // **The background read's scan first.** With Token spend on,
        // `SpendWarmer` keeps one; the pane opens on it, and reads again
        // behind the figures only when it is a few minutes old — no spinner,
        // no progress row, nothing cleared. Rescan still reads from scratch.
        var quiet = false
        // Reading while the kept scan is asked for: the actor may be busy with
        // the background read, and an empty pane meanwhile says "nothing yet".
        isScanningSpend = true
        if !refresh, let kept = await AgentLedgers.shared.keptSnapshot() {
            guard !Task.isCancelled, spendRead.complete(kept.snapshot, for: id) else { return }
            guard Date().timeIntervalSince(kept.at) >= SpendWarmer.paneFreshness else {
                spendRead.finish(id)
                isScanningSpend = false
                return
            }
            quiet = true
        } else {
            clearSpendSummaries()
        }

        isScanningSpend = true
        defer {
            if spendRead.finish(id) {
                isScanningSpend = false
                spendProgress = nil
            }
        }

        let result: AgentLedgers.Snapshot
        do {
            result = try await AgentLedgers.shared.scan(refresh: refresh) { progress in
                guard !quiet, spendRead.isCurrent(id), !Task.isCancelled else { return }
                spendProgress = progress
            }
        } catch {
            return
        }
        guard !Task.isCancelled, settings.readsTokenSpend, navigation.isWindowVisible,
              navigation.pane == .spend, spendRead.complete(result, for: id) else { return }
    }

    private func clearSpendSummaries() {
        spendSummaryCache = SpendSummaryCache()
        displayedSpendRequest = nil
        spend = SpendSummary()
        focusedSpend = SpendSummary()
        modelSpend = ModelSpendSummary()
        spendActivity = TokenActivity()
    }

    /// The same function over the same ledgers, twice: once for everything and
    /// once for the agent being looked at. Deriving the second from the first
    /// would mean a second way of counting a span, and two ways of counting
    /// one thing eventually disagree.
    ///
    /// A model is counted from the same ledgers too, **narrowed to the agent on
    /// screen first where there is one** — so a model opened from an agent's
    /// list reports that agent's work in it and never the other agents' same
    /// model. Nothing here reads a store: it is arithmetic over what was
    /// already loaded, performed on the summary cache's actor.
    ///
    /// **One `now` and one calendar for all three.** Asked separately, a recompute
    /// that happens to straddle midnight can put the combined total on one day
    /// and the model on the next, so the drill-down no longer adds up to the row
    /// it was opened from.
    func recompute() async {
        guard let request = summaryRequest else { return }
        // The view task owns cancellation. A result from an earlier model,
        // span or snapshot may finish, but cannot replace the current figures.
        guard let result = try? await spendSummaryCache.summaries(for: request, ledgers: spendLedgers),
              !Task.isCancelled, summaryRequest == request else { return }
        spend = result.overview
        focusedSpend = result.agent
        modelSpend = result.model
        spendActivity = result.activity
        displayedSpendRequest = request
    }
}
