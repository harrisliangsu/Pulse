// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// Flashcat: status.deepseek.com. Read out of the page, because Flashcat
// offers no feed without an account key.

extension ServiceStatus {
    /// Every component the page shows, in its order, with its state now and —
    /// given `days` — its days and uptime. Nil when the page's data can't be
    /// found, or it shows nothing.
    ///
    /// **Read out of the page**, because Flashcat's API needs an account key.
    /// The page is a Next.js app: its data travels in
    /// `self.__next_f.push([1,"…"])` chunks, which joined are lines of
    /// `id:JSON`. Two carry an `initialData` object — the layout (`page`), and
    /// the impacts and uptimes — and nothing else is read. A redesign that
    /// moves them is no reading, never "all clear".
    ///
    /// The model is incident.io's: impacts with a start and an end, a day
    /// taking its worst. The bars the page draws in a browser were checked
    /// against this, all five components, on 2026-10-04 in UTC+8; the page
    /// draws local days once it loads (its first, server-drawn pass is UTC).
    static func flashcat(
        from html: Data,
        now: Date,
        days: [DateInterval]?,
        calendar: Calendar = .current
    ) -> [Component]? {
        guard
            let data = flashcatInitialData(in: String(decoding: html, as: UTF8.self)),
            let feed = try? JSONDecoder().decode(FlashcatData.self, from: data)
        else { return nil }

        let impacts = feed.componentImpacts.map { record in
            Impact(
                componentID: record.componentID,
                start: Date(timeIntervalSince1970: record.startAtSeconds),
                end: record.endAtSeconds.map { Date(timeIntervalSince1970: $0) },
                state: State(feedValue: record.status)
            )
        }

        // Top level: components outside any section, and sections, by order;
        // a section opens into its own components, by order. The section's
        // own row is an aggregate and isn't drawn — as with OpenAI's groups.
        let visible = feed.page.components.filter { $0.hideAll != true }
        let order = { (value: Int?) in value ?? .max }
        let loose = visible
            .filter { ($0.sectionID ?? "").isEmpty }
            .map { (order: order($0.orderID), members: [$0]) }
        let sections = (feed.page.sections ?? [])
            .filter { $0.hideAll != true }
            .map { section in
                (order: order(section.orderID),
                 members: visible
                    .filter { $0.sectionID == section.sectionID }
                    .sorted { order($0.orderID) < order($1.orderID) })
            }

        let components = (loose + sections)
            .sorted { $0.order < $1.order }
            .flatMap(\.members)
            .map { component in
                // The page's own word when it gives one; otherwise whatever
                // impact is still open; otherwise operational.
                let open = impacts
                    .filter { $0.componentID == component.componentID && $0.start <= now && ($0.end ?? .distantFuture) > now }
                    .map(\.state)
                    .max { $0.severity < $1.severity }
                let stated = component.status.flatMap { $0.isEmpty ? nil : State(feedValue: $0) }
                return Component(
                    id: component.componentID, name: component.name, state: stated ?? open ?? .operational,
                    group: component.sectionID.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        guard !components.isEmpty else { return nil }
        guard let days else { return components }

        var since: [String: Date] = [:]
        var uptimes: [String: Double] = [:]
        for record in feed.componentUptimes {
            guard let id = record.componentID else { continue }
            since[id] = record.availableSinceSeconds.map { Date(timeIntervalSince1970: $0) }
            uptimes[id] = record.uptime
        }
        return applyingHistory(
            impacts: impacts, since: since, uptimes: uptimes,
            days: days, now: now, calendar: calendar, to: components
        )
    }

    /// The page's `initialData` objects, merged into one JSON object; nil
    /// without the layout.
    static func flashcatInitialData(in html: String) -> Data? {
        guard let push = try? Regex(#"self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)"#) else { return nil }
        let flight = html.matches(of: push).compactMap { match -> String? in
            guard let literal = match.output[1].substring else { return nil }
            return try? JSONDecoder().decode(String.self, from: Data(literal.utf8))
        }.joined()

        var merged: [String: Any] = [:]
        for line in flight.split(separator: "\n") where line.contains("\"initialData\"") {
            guard
                let colon = line.firstIndex(of: ":"),
                let record = try? JSONSerialization.jsonObject(with: Data(line[line.index(after: colon)...].utf8))
            else { continue }
            collectInitialData(record, into: &merged)
        }
        guard merged["page"] != nil else { return nil }
        return try? JSONSerialization.data(withJSONObject: merged)
    }

    private static func collectInitialData(_ node: Any, into merged: inout [String: Any]) {
        if let object = node as? [String: Any] {
            if let data = object["initialData"] as? [String: Any] {
                merged.merge(data) { first, _ in first }
            }
            for value in object.values { collectInitialData(value, into: &merged) }
        } else if let array = node as? [Any] {
            for value in array { collectInitialData(value, into: &merged) }
        }
    }

    private struct FlashcatData: Decodable {
        let page: Page
        let componentImpacts: [ImpactRecord]
        let componentUptimes: [Uptime]

        enum CodingKeys: String, CodingKey {
            case page
            case componentImpacts = "component_impacts"
            case componentUptimes = "component_uptimes"
        }

        /// Entry by entry, as with incident.io's lists.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            page = try container.decode(Page.self, forKey: .page)
            componentImpacts = try container.lenient(.componentImpacts)
            componentUptimes = try container.lenient(.componentUptimes)
        }

        struct Page: Decodable {
            let components: [Component]
            let sections: [Section]?

            enum CodingKeys: String, CodingKey { case components, sections }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                components = try container.lenient(.components)
                sections = try container.lenient(.sections)
            }
        }

        struct Component: Decodable {
            let componentID: String
            let name: String
            let sectionID: String?
            /// Null while operational, as far as has been seen.
            let status: String?
            let orderID: Int?
            let hideAll: Bool?

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case name, status
                case sectionID = "section_id"
                case orderID = "order_id"
                case hideAll = "hide_all"
            }
        }

        struct Section: Decodable {
            let sectionID: String
            let orderID: Int?
            let hideAll: Bool?

            enum CodingKeys: String, CodingKey {
                case sectionID = "section_id"
                case orderID = "order_id"
                case hideAll = "hide_all"
            }
        }

        struct ImpactRecord: Decodable {
            let componentID: String
            let status: String
            let startAtSeconds: Double
            let endAtSeconds: Double?

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case status
                case startAtSeconds = "start_at_seconds"
                case endAtSeconds = "end_at_seconds"
            }
        }

        struct Uptime: Decodable {
            let componentID: String?
            let uptime: Double?
            let availableSinceSeconds: Double?

            enum CodingKeys: String, CodingKey {
                case componentID = "component_id"
                case uptime
                case availableSinceSeconds = "available_since_seconds"
            }
        }
    }
}
