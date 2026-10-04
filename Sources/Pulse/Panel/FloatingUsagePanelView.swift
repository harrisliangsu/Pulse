// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Builds the readings only when their observed inputs change. The child owns
/// pointer/card state and shares these entries across layout and hit testing.
struct FloatingUsagePanelView: View {
    let store: UsageStore
    let settings: AppSettings
    let placement: PanelPlacement

    /// The clock arc moves to the minute even when quota refresh backs off.
    @State private var minute = Date()
    /// Bumped each second while a mark's event is showing; see below.
    @State private var eventCheck = 0

    var body: some View {
        // Formatting reads the selected language through a plain function.
        let _ = settings.language
        let _ = eventCheck
        let entries = entries
        let hasEvent = entries.contains { $0.botEvent != nil }
        FloatingUsagePanelContent(store: store, settings: settings, entries: entries, placement: placement)
            .task(id: settings.showsWindowClock) {
                guard settings.showsWindowClock else { return }
                while !Task.isCancelled {
                    minute = Date()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            // `botEvent` comes from clocks — a reset in the last 20 s, a turn
            // finished in the last 6 — and nothing observed changes when they
            // run out. Built here, away from the pointer state that used to
            // re-run it by accident, it would stay set: a mark remounted later
            // replayed it, and the next real event, never preceded by nil, did
            // not play at all. So while one shows, look again each second;
            // once none does, this stops.
            .task(id: hasEvent) {
                guard hasEvent else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    eventCheck += 1
                }
            }
    }

    /// Only the providers switched on in settings, so the rail shrinks when
    /// one is turned off.
    private var entries: [RailEntry] {
        RailSlot.rail(
            for: settings.shownAccounts,
            isSplit: settings.isSplit,
            groups: { RailSlot.modelGroups(of: store.usage(for: $0)) }
        ).map { slot in
            let usage = store.usage(for: slot.account)
            return entry(
                for: slot,
                usage: slot.group.map { Self.usage(usage, keeping: $0) } ?? usage
            )
        }
    }

    /// The same reading with only one group's limits in it, so every figure
    /// downstream — the ring, the card, the second ring — is about that group.
    private static func usage(_ usage: ProviderUsage, keeping group: String) -> ProviderUsage {
        ProviderUsage(
            account: usage.account,
            windows: usage.windows.filter { $0.scope == group },
            observedAt: usage.observedAt,
            state: usage.state,
            plan: usage.plan,
            creditBalance: usage.creditBalance
        )
    }

    private func entry(for slot: RailSlot, usage: ProviderUsage) -> RailEntry {
        let account = slot.account
        let label = settings.label(for: account)
        let pinned = settings.pinnedWindow(for: account)
        let headline = usage.headlineWindow(preferring: pinned)

        // An unavailable reading must not draw remembered money as current.
        let figure: String? = if headline == nil, case .unavailable = usage.state {
            nil
        } else if headline == nil {
            usage.creditRemaining?.railText() ?? usage.creditBalance
        } else {
            nil
        }

        return RailEntry(
            usage: usage,
            headline: headline,
            // Activity is per provider: transcripts do not identify accounts.
            isRunning: store.isRunning(account.provider),
            isRefreshing: store.isRefreshing(account),
            tint: settings.ringTint(for: account),
            showsBotMark: settings.showsBotMark(for: account),
            botPersona: settings.botPersona(for: account),
            botBody: settings.botBody(for: account),
            // A witnessed reset outranks a finished turn.
            botEvent: store.justReset(account) ? .limitReset
                : store.justFinishedWorking(account.provider) ? .workFinished : nil,
            botColour: settings.botColour(for: account),
            slot: slot,
            title: slot.group.map { "\(label) · \($0)" } ?? label,
            windowClock: settings.showsWindowClock
                ? headline?.windowClockFraction(direction: settings.windowClockDirection, at: minute)
                : nil,
            figure: figure,
            second: settings.showsSecondRing ? usage.secondWindow(preferring: pinned) : nil,
            showsRemaining: settings.showsRemaining
        )
    }
}
