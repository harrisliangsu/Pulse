// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

/// What the recap window is showing, and the work of getting there.
///
/// **Reading is the person's decision, never this model's.** With Token spend
/// reading off nothing is read and nothing is switched on: the phase is
/// `needsReading` and the window says where to turn it on. With it on, the
/// ledgers come from `RecapSource` — the scan `SpendWarmer` already keeps when
/// that is fresh, a read with progress when it is not — and are held only while
/// the window is open.
///
/// **One read, many periods.** The ledgers cover every period, so switching
/// month or year only rebuilds a `Recap` (off the main actor, cached for the
/// life of the window). The read is the long part — about forty seconds on a
/// large history, first time — and it is cancelled when the window closes.
@MainActor
@Observable
final class RecapWindowModel {
    enum Phase: Equatable {
        /// Token spend reading is off.
        case needsReading
        /// Reading the ledgers.
        case loading
        case ready
        /// The read ended with something other than being cancelled.
        case failed
    }

    /// Which store the read is on, as the pane's "Reading Claude Code… 3/12".
    struct ReadProgress: Equatable {
        let agent: String
        let index: Int
        let total: Int
    }

    private(set) var phase: Phase
    private(set) var readProgress: ReadProgress?
    private(set) var period: Recap.Period
    /// Nil while it is being worked out, and nil for a period that cannot exist.
    private(set) var recap: Recap?
    private(set) var isBuilding = false
    /// The earliest record on this Mac; nil until the read has finished.
    private(set) var earliest: Date?
    /// The card on screen. Held by identity, not by position: typing a price
    /// adds a card before the scorecard, and the one being looked at stays.
    var card: RecapCard = .poster

    let settings: AppSettings
    private let now: () -> Date
    private var loaded: RecapSource.Loaded?
    private var cache: [Recap.Period: Recap] = [:]
    /// When `loaded` was read. A window left open reads again when it is shown
    /// or a period is chosen half an hour on, or on another day: a running
    /// month's "to date" would otherwise stop where the first read did.
    private var loadedAt: Date?
    private static let freshFor: TimeInterval = 30 * 60

    private var isStale: Bool {
        guard let loadedAt else { return false }
        let current = now()
        return current.timeIntervalSince(loadedAt) > Self.freshFor
            || !Recap.calendar.isDate(loadedAt, inSameDayAs: current)
    }
    /// Whether the window is on screen. Nothing is read, and a change of the
    /// Token spend switch starts nothing, while it is not.
    private var isOpen = false
    private var loadTask: Task<Void, Never>?
    /// Which read `loadTask` is. A cancelled read finishes (or throws) after a
    /// newer one has started — close and reopen, or off and on — and must not
    /// clear the newer one's reference or hand over its result.
    private var loadGeneration = 0
    private let load: Loader
    private var buildTask: Task<Void, Never>?
    /// Whether the person (or an entry point) named a period, so the read
    /// finishing does not move them off it onto the default.
    private var periodChosen = false

    /// How the ledgers are read; `RecapSource.load` unless a test says otherwise.
    typealias Loader = @MainActor (@escaping @MainActor @Sendable (AgentLedgers.Progress) -> Void) async throws -> RecapSource.Loaded

    init(
        settings: AppSettings,
        now: @escaping () -> Date = Date.init,
        load: @escaping Loader = { progress in try await RecapSource.load(progress: progress) }
    ) {
        self.settings = settings
        self.now = now
        self.load = load
        phase = settings.readsTokenSpend ? .loading : .needsReading
        period = RecapPeriods.defaultMonth(earliest: nil, now: now())
    }

    // MARK: - Periods

    var offeredMonths: [Recap.Period] { RecapPeriods.months(earliest: earliest, now: now()) }
    var offeredYears: [Recap.Period] { RecapPeriods.years(earliest: earliest, now: now()) }

    var isYear: Bool { period.isYear }

    /// The periods of the kind on screen, plus the selected one where it is
    /// not among them (a period asked for before the read said where records begin).
    var offered: [Recap.Period] {
        let list = isYear ? offeredYears : offeredMonths
        return list.contains(period) ? list : [period] + list
    }

    func select(_ next: Recap.Period) {
        guard next != period else { return }
        periodChosen = true
        period = next
        card = .poster
        if isStale {
            start()
            return
        }
        rebuild()
    }

    func selectKind(year: Bool) {
        guard year != isYear else { return }
        select(RecapPeriods.switched(period, earliest: earliest, now: now()))
    }

    // MARK: - Window lifecycle

    /// The window is on screen, optionally on a named period. Starts the read
    /// if there is none.
    func begin(on requested: Recap.Period?) {
        isOpen = true
        if let requested {
            periodChosen = true
            if requested != period {
                period = requested
                card = .poster
            }
        }
        start()
    }

    /// The window closed: nothing is read for it any more, and nothing is kept.
    func windowDidClose() {
        isOpen = false
        loadGeneration += 1
        loadTask?.cancel()
        buildTask?.cancel()
        loadTask = nil
        buildTask = nil
        loaded = nil
        loadedAt = nil
        cache = [:]
        recap = nil
        earliest = nil
        isBuilding = false
        readProgress = nil
        periodChosen = false
        card = .poster
        period = RecapPeriods.defaultMonth(earliest: nil, now: now())
        phase = settings.readsTokenSpend ? .loading : .needsReading
    }

    /// Reading, as `settings.readsTokenSpend` stands now: called on opening
    /// and whenever the switch moves while the window is up.
    func start() {
        guard isOpen else { return }
        guard settings.readsTokenSpend else {
            // Switched off under an open window: what was read goes too.
            loadGeneration += 1
            loadTask?.cancel()
            buildTask?.cancel()
            loadTask = nil
            loaded = nil
            loadedAt = nil
            cache = [:]
            recap = nil
            earliest = nil
            isBuilding = false
            readProgress = nil
            phase = .needsReading
            return
        }
        if loaded != nil {
            if !isStale {
                phase = .ready
                rebuild()
                return
            }
            // Read too long ago: read again rather than draw an old "to date".
            buildTask?.cancel()
            buildTask = nil
            loaded = nil
            loadedAt = nil
            cache = [:]
            recap = nil
            isBuilding = false
        }
        guard loadTask == nil else { return }
        phase = .loading
        readProgress = nil
        loadGeneration += 1
        let generation = loadGeneration
        let load = self.load
        loadTask = Task { [weak self] in
            do {
                let result = try await load { progress in
                    guard self?.loadGeneration == generation else { return }
                    self?.readProgress = ReadProgress(
                        agent: progress.agent.displayName, index: progress.index, total: progress.total
                    )
                }
                self?.finishedReading(result, generation: generation)
            } catch is CancellationError {
                // Only this read's own reference: a newer read may be running.
                if self?.loadGeneration == generation { self?.loadTask = nil }
            } catch {
                self?.failedReading(generation: generation)
            }
        }
    }

    private func finishedReading(_ result: RecapSource.Loaded, generation: Int) {
        guard generation == loadGeneration else { return }
        loadTask = nil
        guard isOpen, settings.readsTokenSpend else { return }
        loaded = result
        loadedAt = now()
        earliest = result.earliest
        if !periodChosen { period = RecapPeriods.defaultMonth(earliest: result.earliest, now: now()) }
        readProgress = nil
        phase = .ready
        rebuild()
    }

    private func failedReading(generation: Int) {
        guard generation == loadGeneration else { return }
        loadTask = nil
        readProgress = nil
        phase = .failed
    }

    private func rebuild() {
        buildTask?.cancel()
        buildTask = nil
        guard let loaded else { return }
        if let kept = cache[period] {
            recap = kept
            isBuilding = false
            return
        }
        recap = nil
        isBuilding = true
        let target = period
        let date = now()
        buildTask = Task { [weak self] in
            let built = await RecapSource.build(target, from: loaded, now: date)
            guard let self, !Task.isCancelled, self.period == target else { return }
            if let built { self.cache[target] = built }
            self.recap = built
            self.isBuilding = false
            self.buildTask = nil
        }
    }

    // MARK: - What is drawn

    /// The cards for the recap on screen, with the price and the privacy
    /// switch as they stand. Nil while there is no recap.
    var deck: RecapDeck? {
        recap.map {
            RecapDeck(recap: $0, monthlyPrice: settings.recapMonthlyPrice, hidesProjects: settings.recapHidesProjects)
        }
    }

    /// The card on screen: the chosen one if the deck still has it, else the first.
    func currentCard(in deck: RecapDeck) -> RecapCard {
        deck.cards.contains(card) ? card : (deck.cards.first ?? .poster)
    }

    /// Steps through the deck: -1 for the one before, 1 for the one after.
    func step(_ direction: Int, in deck: RecapDeck) {
        guard let index = deck.cards.firstIndex(of: currentCard(in: deck)) else { return }
        let target = index + direction
        guard deck.cards.indices.contains(target) else { return }
        card = deck.cards[target]
    }

    #if DEBUG
    /// A model in a given state without a read, for previews and the review render.
    static func preview(
        settings: AppSettings,
        phase: Phase,
        period: Recap.Period,
        recap: Recap? = nil,
        earliest: Date? = nil,
        progress: ReadProgress? = nil,
        isBuilding: Bool = false,
        card: RecapCard = .poster,
        now: @escaping () -> Date = Date.init
    ) -> RecapWindowModel {
        let model = RecapWindowModel(settings: settings, now: now)
        model.phase = phase
        model.period = period
        model.recap = recap
        model.earliest = earliest
        model.readProgress = progress
        model.isBuilding = isBuilding
        model.card = card
        return model
    }
    #endif
}

extension Recap.Period {
    /// "September 2026", "2026年9月", or the year: what the pickers, the empty
    /// state and the window title call the period, in the language's own order.
    var title: String {
        switch self {
        case .month:
            bounds(calendar: Recap.calendar).map { RecapFormat.monthYear($0.start) } ?? key
        case .year(let year):
            RecapFormat.yearName(year)
        }
    }
}
