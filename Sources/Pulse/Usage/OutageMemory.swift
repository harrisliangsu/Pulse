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
/// Its own file, `status-alerts.json`, rather than a field on `AlertMemory`:
/// that type decodes as a whole, and a key old files lack would have thrown
/// every limit already warned about away with it.
struct OutageMemory: Codable, Sendable, Equatable {
    /// By component id, the state last announced for a component still down.
    /// Absent means nothing said, or said and since recovered.
    var announced: [String: ServiceStatus.State] = [:]

    struct Change: Equatable, Sendable {
        /// Down, or worse than when last announced, with the state now.
        var worse: [ServiceStatus.Component] = []
        /// Announced as down, operational again.
        var recovered: [ServiceStatus.Component] = []

        var isEmpty: Bool { worse.isEmpty && recovered.isEmpty }
    }

    /// What one reading of a page is worth saying, and the record of having
    /// said it. Pure: no clock, no disk, no notification centre.
    mutating func changes(in components: [ServiceStatus.Component]) -> Change {
        var change = Change()
        for component in components {
            let said = announced[component.id]
            if component.state.isOutage {
                if said.map({ component.state.severity > $0.severity }) ?? true {
                    change.worse.append(component)
                }
                // Better but still down is recorded without a word, so getting
                // worse again is news again.
                announced[component.id] = component.state
            } else if component.state == .operational, said != nil {
                change.recovered.append(component)
                announced[component.id] = nil
            }
            // Maintenance or an unknown value: neither down nor proven back.
        }
        return change
    }
}
