// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// Atlassian Statuspage: Claude's, Cursor's, GitHub's, Devin's and a dozen
// more. The summary says which components there are and their state; the
// uptime showcase — the feed the page draws its bars from — gives the days,
// the page's colours and its ninety-day figure, where the page draws bars at
// all. Zoom's draws none for any row, and Cloudflare's answers the showcase
// with a 404; both are read for the state alone.

extension ServiceStatus {
    /// The summary first, because it says which components there are; then
    /// the history of the ones the pane shows, in one request (the page asks
    /// up to 60 at a time) — never Zoom's 339.
    static func readStatuspage(root: URL, showing rule: ComponentRule) async -> [Component]? {
        guard
            let summary = await fetch(root.appending(path: "api/v2/summary.json")),
            var components = statuspageComponents(from: summary)?.filter(rule.matches),
            !components.isEmpty
        else { return nil }

        var history = URLComponents(url: root.appending(path: "uptime_showcase"), resolvingAgainstBaseURL: false)
        history?.queryItems = [
            URLQueryItem(name: "components", value: components.map(\.id).joined(separator: ",")),
        ]
        if let showcase = await fetch(history?.url) {
            components = statuspageHistory(from: showcase, applyingTo: components)
        }
        return components
    }

    /// Every component the page shows, in its order, each with its state now
    /// and its group's id: groups' own rows left out, and one marked to show
    /// only when degraded left out while it isn't. Nil when the page shows
    /// none.
    static func statuspageComponents(from data: Data) -> [Component]? {
        guard let summary = try? JSONDecoder().decode(StatuspageSummary.self, from: data) else { return nil }
        let components = summary.components
            .filter { $0.group != true && ($0.onlyShowIfDegraded != true || $0.status != "operational") }
            .sorted { ($0.position ?? .max) < ($1.position ?? .max) }
            .map { Component(id: $0.id, name: $0.name, state: State(feedValue: $0.status), group: $0.groupID) }
        return components.isEmpty ? nil : components
    }

    /// Each component's days, colours and uptime from the uptime showcase.
    static func statuspageHistory(from data: Data, applyingTo components: [Component]) -> [Component] {
        guard let showcase = try? JSONDecoder().decode(StatuspageShowcase.self, from: data) else { return components }

        return components.map { component in
            guard let timeline = showcase.timelines[component.id] else { return component }
            let started = timeline.component.startDate

            var days = timeline.days.compactMap { day -> Day? in
                guard let date = dayComponents(day.date) else { return nil }
                // Same-format dates compare as text.
                if let started, day.date < started { return Day(date: date, state: nil) }
                let state: State = (day.outages?.m ?? 0) > 0 ? .fullOutage
                    : (day.outages?.p ?? 0) > 0 ? .partialOutage
                    : .operational
                return Day(date: date, state: state)
            }
            // The page's own colours, only when there is one for every day —
            // a partial list can't be lined up with the days safely.
            let colours = showcase.components[component.id].map(barColours) ?? []
            if colours.count == days.count {
                for index in days.indices { days[index].rgb = colours[index] }
            }

            var component = component
            component.days = days
            component.uptime = showcase.values.first { $0.component == component.id }?.ninety
            return component
        }
    }

    /// The `fill` of each `uptime-day` bar in the page's SVG, in order.
    static func barColours(in html: String) -> [UInt32] {
        guard
            let tag = try? Regex(#"<rect\b[^>]*>"#),
            let fill = try? Regex(##"fill="#([0-9a-fA-F]{6})""##)
        else { return [] }
        return html.matches(of: tag).compactMap { match in
            let rect = html[match.range]
            guard
                rect.contains("uptime-day"),
                let colour = rect.firstMatch(of: fill)?.output[1].substring
            else { return nil }
            return UInt32(colour, radix: 16)
        }
    }

    private struct StatuspageSummary: Decodable {
        let components: [Component]

        enum CodingKeys: String, CodingKey { case components }

        init(from decoder: any Decoder) throws {
            components = try decoder.container(keyedBy: CodingKeys.self).lenient(.components)
        }

        struct Component: Decodable {
            let id: String
            let name: String
            let status: String
            let position: Int?
            let group: Bool?
            let groupID: String?
            let onlyShowIfDegraded: Bool?

            enum CodingKeys: String, CodingKey {
                case id, name, status, position, group
                case groupID = "group_id"
                case onlyShowIfDegraded = "only_show_if_degraded"
            }
        }
    }

    private struct StatuspageShowcase: Decodable {
        let timelines: [String: Timeline]
        let values: [Value]
        /// Each component's bars, as the SVG the page inserts.
        let components: [String: String]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timelines = try container.decode([String: Lenient<Timeline>].self, forKey: .timelines)
                .compactMapValues(\.value)
            values = try container.decodeIfPresent([Value].self, forKey: .values) ?? []
            components = try container.decodeIfPresent([String: String].self, forKey: .components) ?? [:]
        }

        enum CodingKeys: String, CodingKey {
            case timelines, values, components
        }

        struct Timeline: Decodable {
            let component: Info
            let days: [Day]
        }

        struct Info: Decodable {
            let startDate: String?
        }

        struct Day: Decodable {
            let date: String
            let outages: Outages?
        }

        /// Seconds of partial and of major outage that day.
        struct Outages: Decodable {
            let p: Int?
            let m: Int?
        }

        struct Value: Decodable {
            let component: String
            let ninety: Double?
        }
    }
}
