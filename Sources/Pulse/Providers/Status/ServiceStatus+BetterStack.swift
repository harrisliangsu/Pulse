// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// Better Stack: Hugging Face's page, Chutes', Synthetic's, Raycast's and
// more. One request, `/index.json`, carries every monitor's state now, its
// days as the page draws them (ninety, or thirty on Synthetic's) and the
// page's availability figure. JSON:API: the monitors and their sections are
// in `included`, told apart by `type`.

extension ServiceStatus {
    /// Every monitor the page lists, its sections in order and each one's
    /// monitors in order, the section's name as its group. Nil when the page
    /// can't be read or lists none.
    static func betterStack(from data: Data) -> [Component]? {
        guard let page = try? JSONDecoder().decode(BetterStackPage.self, from: data) else { return nil }

        let sections = Dictionary(
            page.included.filter { $0.type == "status_page_section" }.map { ($0.id, $0.attributes) },
            uniquingKeysWith: { first, _ in first }
        )
        let resources = page.included
            .filter { $0.type == "status_page_resource" && $0.attributes.publicName != nil }
            .sorted { lhs, rhs in
                let left = lhs.attributes.sectionID.flatMap { sections[$0]?.position } ?? -1
                let right = rhs.attributes.sectionID.flatMap { sections[$0]?.position } ?? -1
                return left != right ? left < right : (lhs.attributes.position ?? .max) < (rhs.attributes.position ?? .max)
            }

        let components = resources.map { resource in
            let attributes = resource.attributes
            return Component(
                id: resource.id,
                name: attributes.publicName ?? "",
                state: attributes.status.map(betterStackState) ?? .unrecognised,
                days: (attributes.statusHistory ?? []).compactMap { day in
                    guard let date = dayComponents(day.day) else { return nil }
                    // Not monitored that day: no record, not a clear day.
                    let state = day.status == "not_monitored" ? nil : betterStackState(day.status)
                    return Day(date: date, state: state)
                },
                // A fraction, "0.999898".
                uptime: attributes.availability.map { $0 * 100 },
                group: attributes.sectionID.flatMap { sections[$0]?.name }
            )
        }
        return components.isEmpty ? nil : components
    }

    /// Better Stack's words. `downtime` is its red — the monitor failing,
    /// which is what an outage is — and `not_monitored` (Chutes' API now) is
    /// not a reading of the service at all.
    static func betterStackState(_ value: String) -> State {
        switch value {
        case "operational": .operational
        case "degraded", "recovered_degraded": .degraded
        case "downtime": .fullOutage
        case "maintenance": .maintenance
        default: .unrecognised
        }
    }

    private struct BetterStackPage: Decodable {
        let included: [Included]

        enum CodingKeys: String, CodingKey { case included }

        init(from decoder: any Decoder) throws {
            included = try decoder.container(keyedBy: CodingKeys.self).lenient(.included)
        }

        struct Included: Decodable {
            let id: String
            let type: String
            let attributes: Attributes
        }

        /// A section's and a monitor's fields together; each has only its own.
        struct Attributes: Decodable {
            let name: String?
            let position: Int?
            let publicName: String?
            let sectionID: String?
            let status: String?
            let availability: Double?
            let statusHistory: [HistoryDay]?

            enum CodingKeys: String, CodingKey {
                case name, position, status, availability
                case publicName = "public_name"
                case sectionID = "status_page_section_id"
                case statusHistory = "status_history"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try? container.decodeIfPresent(String.self, forKey: .name)
                position = try? container.decodeIfPresent(Int.self, forKey: .position)
                publicName = try? container.decodeIfPresent(String.self, forKey: .publicName)
                // A number in the feed; the section's own id is a string.
                sectionID = (try? container.decodeIfPresent(Int.self, forKey: .sectionID)).flatMap { $0.map(String.init) }
                    ?? (try? container.decodeIfPresent(String.self, forKey: .sectionID)) ?? nil
                status = try? container.decodeIfPresent(String.self, forKey: .status)
                availability = (try? container.decodeIfPresent(Double.self, forKey: .availability))
                    ?? (try? container.decodeIfPresent(String.self, forKey: .availability)).flatMap { $0.flatMap(Double.init) }
                statusHistory = try? container.lenient(.statusHistory)
            }
        }

        struct HistoryDay: Decodable {
            let day: String
            let status: String
        }
    }
}
