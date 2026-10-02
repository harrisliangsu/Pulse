// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Reads Token spend in the background while it is switched on, so the pane
/// opens on figures rather than on a spinner.
///
/// The pane used to read only once it was opened, and let the result go when
/// the window closed — so every visit began with a wait, and the wait was
/// longest exactly when something had changed. With the switch on this reads
/// once shortly after launch, again the moment the switch is turned on, and
/// every `interval` after that; the pane shows the kept scan at once
/// (`AgentLedgers.keptSnapshot`) and rereads quietly behind it when the scan
/// is older than `paneFreshness`.
///
/// **Background priority, one read at a time, nothing while it is off.** The
/// readers' own disk caches make a quiet pass cheap — about a tenth of a
/// second on a Mac with fifteen agents' stores, measured — so the cost is
/// the revalidation, not a full read. Switching off cancels a read in
/// progress and drops the kept scan.
@MainActor
final class SpendWarmer {
    static let interval: TimeInterval = 10 * 60
    /// A kept scan younger than this is shown and not reread when the pane
    /// opens.
    static let paneFreshness: TimeInterval = 2 * 60
    /// Out of the way of launch, which has the rings to fetch first.
    static let launchDelay: Duration = .seconds(20)

    private let settings: AppSettings
    private var loop: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        follow(firstDelay: Self.launchDelay)
    }

    /// Re-arms on every change of the switch, the way the menu bar reading
    /// follows its settings.
    private func follow(firstDelay: Duration) {
        withObservationTracking {
            _ = settings.readsTokenSpend
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow(firstDelay: .zero) }
        }
        loop?.cancel()
        guard settings.readsTokenSpend else {
            loop = nil
            Task { await AgentLedgers.shared.forget() }
            return
        }
        loop = Task(priority: .utility) {
            try? await Task.sleep(for: firstDelay)
            while !Task.isCancelled {
                _ = try? await AgentLedgers.shared.scan()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }
}
