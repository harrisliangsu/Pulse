// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What has been said about a provider's service going down, and the rules for
/// what to say next (`AppSettings.alertsOnOutage`).
///
/// **The provider's word only.** A component is down when its own status page
/// says degraded, partial or full outage; maintenance is planned, and a value
/// Pulse can't read is not a witnessed outage. A page that can't be read
/// changes nothing here — it is neither an outage nor a recovery.
///
/// **Once per outage**, like every other alert: a component is announced when
/// it first goes down, again only if it gets worse, and once more when the page
/// calls it operational — and that last only for one that was announced, so a
/// recovery is never news about an outage nobody heard of. An outage already
/// under way when the setting goes on is said at once: silence then a wall is
/// the feature failing.
///
/// **Only what Pulse is still watching is remembered.** A component the page
/// no longer lists — a Statuspage row shown only while degraded, a renamed
/// one — is forgotten without a word, because its recovery was not seen; and
/// a page nobody is watching (the switch off, the provider off) is forgotten
/// whole. Otherwise an entry outlived its outage: a later outage at the same
/// severity was silent, and switching back on days later said "back to normal"
/// about something that ended unwatched.
///
/// Its own file, `status-alerts.json`, rather than a field on `AlertMemory`:
/// that type decodes as a whole, and a key old files lack would have thrown
/// every limit already warned about away with it.
struct OutageMemory: Codable, Sendable, Equatable {
    /// By page (its provider's raw value), then by component id: the state
    /// last announced for a component still down.
    var announced: [String: [String: ServiceStatus.State]] = [:]

    struct Change: Equatable, Sendable {
        /// Down, or worse than when last announced, with the state now.
        var worse: [ServiceStatus.Component] = []
        /// Announced as down, operational again.
        var recovered: [ServiceStatus.Component] = []

        var isEmpty: Bool { worse.isEmpty && recovered.isEmpty }
    }

    /// What one reading of a page is worth saying, and the record of having
    /// said it. `components` is everything on the page Pulse watches. Pure: no
    /// clock, no disk, no notification centre.
    mutating func changes(in components: [ServiceStatus.Component], on page: StatusPage) -> Change {
        let key = page.provider.rawValue
        let said = announced[key] ?? [:]
        var now: [String: ServiceStatus.State] = [:]
        var change = Change()

        for component in components {
            let before = said[component.id]
            if component.state.isOutage {
                if before.map({ component.state.severity > $0.severity }) ?? true {
                    change.worse.append(component)
                }
                // Better but still down is recorded without a word, so getting
                // worse again is news again.
                now[component.id] = component.state
            } else if component.state == .operational {
                if before != nil { change.recovered.append(component) }
            } else if let before {
                // Maintenance or an unknown value: neither down nor proven
                // back, so what was said stands.
                now[component.id] = before
            }
        }
        // Anything not on the page any more is dropped here, unannounced.
        announced[key] = now.isEmpty ? nil : now
        return change
    }

    /// Forgets the pages Pulse is no longer watching.
    mutating func keepOnly(_ pages: Set<StatusPage>) {
        let watched = Set(pages.map(\.provider.rawValue))
        announced = announced.filter { watched.contains($0.key) }
    }
}
