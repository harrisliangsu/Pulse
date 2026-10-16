// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// incident.io: OpenAI's page, JetBrains', Amp's, Notion's and more. Read from
// the page's own `/proxy/<host>` feed — OpenAI's Statuspage-compatible
// summary leaves its Codex group out entirely — and its `component_impacts`.
// The bars are the worst impact the feed lists on each local day, checked bar
// for bar against status.openai.com, all four Codex rows, 2026-10-04.

extension ServiceStatus {
    static func readIncidentIO(
        _ url: URL, showing rule: ComponentRule, days: [DateInterval], now: Date
    ) async -> [Component]? {
        guard let first = days.first, let last = days.last else { return nil }

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var history = URLComponents(url: url.appending(path: "component_impacts"), resolvingAgainstBaseURL: false)
        history?.queryItems = [
            URLQueryItem(name: "start_at", value: stamp.string(from: first.start)),
            URLQueryItem(name: "end_at", value: stamp.string(from: last.end)),
        ]

        async let summary = fetch(url)
        async let impacts = fetch(history?.url)
        guard let feed = await summary.flatMap(incidentIOSummary) else { return nil }
        var components = feed.components.filter(rule.matches)
        if let impacts = await impacts {
            components = incidentIOHistory(from: impacts, days: days, now: now, applyingTo: components)
        }
        // A page set to draw bars without a percentage has one in its feed
        // all the same; it is not shown where the page doesn't show it.
        if !feed.showsUptime {
            components = components.map { var component = $0; component.uptime = nil; return component }
        }
        return components
    }

    /// Every visible component in the page's order — rows of their own and
    /// each group's members, the group's name as theirs — with its state now;
    /// and whether the page shows an uptime figure. Nil when the feed doesn't
    /// parse or shows nothing.
    static func incidentIOSummary(from data: Data) -> (components: [Component], showsUptime: Bool)? {
        guard let feed = try? JSONDecoder().decode(IncidentIOFeed.self, from: data) else { return nil }

        let affected = Dictionary(
            feed.summary.affectedComponents.map { ($0.componentID, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
        func component(_ item: IncidentIOFeed.Member, group: String?) -> Component? {
            guard item.hidden != true else { return nil }
            return Component(
                id: item.componentID,
                name: item.name,
                state: affected[item.componentID].map(State.init(feedValue:)) ?? .operational,
                group: group
            )
        }
        let components = feed.summary.structure.items.flatMap { item -> [Component] in
            if let group = item.group {
                guard group.hidden != true else { return [] }
                return group.components.compactMap { component($0, group: group.name) }
            }
            return item.component.flatMap { component($0, group: nil) }.map { [$0] } ?? []
        }
        guard !components.isEmpty else { return nil }
        return (components, feed.summary.displayUptimeMode != "chart_only")
    }

    /// Each component's days and uptime from the impacts feed.
    static func incidentIOHistory(
        from data: Data,
        days: [DateInterval],
        now: Date,
        calendar: Calendar = .current,
        applyingTo components: [Component]
    ) -> [Component] {
        guard let feed = try? JSONDecoder().decode(IncidentIOImpacts.self, from: data) else { return components }

        let impacts = feed.componentImpacts.compactMap { impact -> Impact? in
            guard let start = timestamp(impact.startAt) else { return nil }
            return Impact(
                componentID: impact.componentID,
                start: start,
                end: impact.endAt.flatMap(timestamp),
                state: State(feedValue: impact.status)
            )
        }
        var since: [String: Date] = [:]
        var uptimes: [String: Double] = [:]
        for record in feed.componentUptimes {
            guard let id = record.componentID else { continue }
            since[id] = record.dataAvailableSince.flatMap(timestamp)
            uptimes[id] = Double(record.uptime)
        }
        return applyingHistory(
            impacts: impacts, since: since, uptimes: uptimes,
            days: days, now: now, calendar: calendar, to: components
        )
    }

    private struct IncidentIOFeed: Decodable {
        let summary: Summary

        struct Summary: Decodable {
            let affectedComponents: [Affected]
            let structure: Structure
            let displayUptimeMode: String?

            enum CodingKeys: String, CodingKey {
                case affectedComponents = "affected_components"
                case structure
                case displayUptimeMode = "display_uptime_mode"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                affectedComponents = try container.decodeIfPresent([Affected].self, forKey: .affectedComponents) ?? []
                structure = try container.decode(Structure.self, forKey: .structure)
                displayUptimeMode = try? container.decodeIfPresent(String.self, forKey: .displayUptimeMode)
            }
        }

        struct Affected: Decodable {
            let componentID: String
            let status: String

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case status
            }
        }

        struct Structure: Decodable {
            let items: [Item]

            enum CodingKeys: String, CodingKey { case items }

            init(from decoder: any Decoder) throws {
                items = try decoder.container(keyedBy: CodingKeys.self).lenient(.items)
            }
        }

        /// A group, or a component on its own.
        struct Item: Decodable {
            let group: Group?
            let component: Member?
        }

        struct Group: Decodable {
            let name: String
            let hidden: Bool?
            let components: [Member]

            enum CodingKeys: String, CodingKey { case name, hidden, components }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                hidden = try? container.decodeIfPresent(Bool.self, forKey: .hidden)
                components = try container.lenient(.components)
            }
        }

        struct Member: Decodable {
            let componentID: String
            let name: String
            let hidden: Bool?

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case name, hidden
            }
        }
    }

    private struct IncidentIOImpacts: Decodable {
        let componentImpacts: [Impact]
        let componentUptimes: [Uptime]

        enum CodingKeys: String, CodingKey {
            case componentImpacts = "component_impacts"
            case componentUptimes = "component_uptimes"
        }

        /// Entry by entry: one the feed shapes differently is skipped, not
        /// allowed to take the whole history with it.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            componentImpacts = try container.lenient(.componentImpacts)
            componentUptimes = try container.lenient(.componentUptimes)
        }

        struct Impact: Decodable {
            let componentID: String
            let status: String
            let startAt: String
            let endAt: String?

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case status
                case startAt = "start_at"
                case endAt = "end_at"
            }
        }

        /// A group's own figure comes in this list too, with a
        /// `status_page_component_group_id` and no `component_id`.
        struct Uptime: Decodable {
            let componentID: String?
            let uptime: String
            let dataAvailableSince: String?

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case uptime
                case dataAvailableSince = "data_available_since"
            }
        }
    }
}
