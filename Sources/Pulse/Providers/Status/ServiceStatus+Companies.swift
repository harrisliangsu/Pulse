// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// Pages a company built itself, each read from the JSON its page is drawn
// from: OpenCode's, DeepInfra's, IBM Bob's, and Google Cloud's dashboard for
// Gemini Code Assist. The first three are the state now: OpenCode keeps two
// and a half days in three-hour bars, DeepInfra draws its services' days only
// in the page, and IBM lists incidents but no days. Google's incidents are
// drawn as days the way incident.io's impacts are.

extension ServiceStatus {
    // MARK: - OpenCode

    /// `/api/status`: one row per service, named as the page names them,
    /// with the bars the page draws — the last seven days in three-hour
    /// slots, 56 of them, aligned to UTC and ending with the slot now under
    /// way. The feed's `history` fills the slots it covers (about two and a
    /// half days); a slot it doesn't, or one it calls `unknown`, has no
    /// record, as the page draws it. Checked against status.opencode.ai on
    /// 2026-10-15: 56 bars, "Thu, Oct 8, 09:00–12:00 UTC" to "Today,
    /// 06:00–09:00 UTC".
    static func openCode(from data: Data, now: Date = Date(), calendar: Calendar = .current) -> [Component]? {
        guard let feed = try? JSONDecoder().decode(OpenCodeFeed.self, from: data) else { return nil }
        let slot = Double(openCodeBarHours * 3600)
        let current = (now.timeIntervalSince1970 / slot).rounded(.down) * slot
        let starts = (0..<openCodeBarCount).reversed().map { current - Double($0) * slot }
        let buckets = Dictionary(feed.history.map { ($0.start / 1000, $0.services) }, uniquingKeysWith: { first, _ in first })
        let components = feed.components.map { service in
            Component(
                id: service.service,
                name: openCodeName(service.service),
                state: State(feedValue: service.status),
                days: starts.map { start in
                    let word = buckets[start]?[service.service]
                    return Day(
                        date: calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: start)
                        ),
                        state: word.flatMap { $0 == "unknown" ? nil : State(feedValue: $0) },
                        hours: openCodeBarHours
                    )
                }
            )
        }
        return components.isEmpty ? nil : components
    }

    /// The page's bars: three hours each, seven days of them.
    static let openCodeBarHours = 3
    static let openCodeBarCount = 56

    /// The page's own names for the services the feed lists by id; one this
    /// build doesn't know is shown by its id.
    static func openCodeName(_ id: String) -> String {
        switch id {
        case "console": "Console API"
        case "logs": "Request logs"
        case "inference": "Inference API"
        case "go": "Go"
        case "payg": "Pay-as-you-go"
        case "free": "Free inference"
        default: id
        }
    }

    private struct OpenCodeFeed: Decodable {
        let components: [Service]
        let history: [Bucket]

        enum CodingKeys: String, CodingKey { case components, history }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            components = try container.lenient(.components)
            history = try container.lenient(.history)
        }

        struct Service: Decodable {
            let service: String
            let status: String
        }

        /// Milliseconds since 1970, and each service's word for the bar.
        struct Bucket: Decodable {
            let start: Double
            let services: [String: String]
        }
    }

    // MARK: - DeepInfra

    /// `/api/v1/status`: the services (the API, the website), not the
    /// hundreds of models listed beside them.
    static func deepInfra(from data: Data) -> [Component]? {
        guard let feed = try? JSONDecoder().decode(DeepInfraFeed.self, from: data) else { return nil }
        let components = feed.services.map {
            Component(id: $0.publicId, name: $0.displayName, state: State(feedValue: $0.status))
        }
        return components.isEmpty ? nil : components
    }

    private struct DeepInfraFeed: Decodable {
        let services: [Service]

        enum CodingKeys: String, CodingKey { case services }

        init(from decoder: any Decoder) throws {
            services = try decoder.container(keyedBy: CodingKeys.self).lenient(.services)
        }

        struct Service: Decodable {
            let publicId: String
            let displayName: String
            let status: String
        }
    }

    // MARK: - IBM Bob

    /// `/api/v1/status`: services by region, one per synthetic check — so a
    /// name comes several times, once per check. One row per name, the worst
    /// of its checks, in the order the page first lists it.
    static func ibmBob(from data: Data) -> [Component]? {
        guard let feed = try? JSONDecoder().decode(IBMBobFeed.self, from: data) else { return nil }
        var order: [String] = []
        var worst: [String: State] = [:]
        for service in feed.regions.flatMap(\.services) {
            let state = State(feedValue: service.status)
            if let before = worst[service.name] {
                if state.severity > before.severity { worst[service.name] = state }
            } else {
                order.append(service.name)
                worst[service.name] = state
            }
        }
        let components = order.map { Component(id: $0, name: $0, state: worst[$0] ?? .unrecognised) }
        return components.isEmpty ? nil : components
    }

    private struct IBMBobFeed: Decodable {
        let regions: [Region]

        enum CodingKeys: String, CodingKey { case regions }

        init(from decoder: any Decoder) throws {
            regions = try decoder.container(keyedBy: CodingKeys.self).lenient(.regions)
        }

        struct Region: Decodable {
            let services: [Service]

            enum CodingKeys: String, CodingKey { case services }

            init(from decoder: any Decoder) throws {
                services = try decoder.container(keyedBy: CodingKeys.self).lenient(.services)
            }
        }

        struct Service: Decodable {
            let name: String
            let status: String
        }
    }

    // MARK: - Google Cloud

    /// `incidents.json`: the dashboard's incidents, each with when it began
    /// and ended, how bad (`status_impact`) and the products it touched. One
    /// row, the product's: down while an incident touching it is open, and —
    /// given `days` — a day taking the worst incident that overlapped it.
    /// Nil when the feed can't be read; a product with no incident is
    /// operational, which is how the dashboard says it.
    static func googleCloud(
        from data: Data, product: String, name: String, now: Date, days: [DateInterval]?, calendar: Calendar = .current
    ) -> [Component]? {
        guard let incidents = try? JSONDecoder().decode([Lenient<GoogleIncident>].self, from: data) else { return nil }
        let impacts = incidents.compactMap(\.value)
            .filter { $0.affectedProducts.contains { $0.id == product } }
            .compactMap { incident -> Impact? in
                guard let start = timestamp(incident.begin) else { return nil }
                return Impact(
                    componentID: product,
                    start: start,
                    end: incident.end.flatMap(timestamp),
                    state: googleCloudState(incident.statusImpact)
                )
            }
        let open = impacts
            .filter { $0.start <= now && ($0.end ?? .distantFuture) > now }
            .map(\.state)
            .max { $0.severity < $1.severity }
        let component = Component(id: product, name: name, state: open ?? .operational)
        guard let days else { return [component] }
        return applyingHistory(
            impacts: impacts, since: [:], uptimes: [:], days: days, now: now, calendar: calendar, to: [component]
        )
    }

    /// The dashboard's three kinds: an outage, a disruption, and "service
    /// information" — an incident it lists for a lesser problem, which is
    /// still the service not working as it should.
    static func googleCloudState(_ value: String?) -> State {
        switch value {
        case "SERVICE_OUTAGE": .fullOutage
        case "SERVICE_DISRUPTION": .partialOutage
        case "SERVICE_INFORMATION": .degraded
        default: .unrecognised
        }
    }

    private struct GoogleIncident: Decodable {
        let begin: String
        let end: String?
        let statusImpact: String?
        let affectedProducts: [Product]

        enum CodingKeys: String, CodingKey {
            case begin, end
            case statusImpact = "status_impact"
            case affectedProducts = "affected_products"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            begin = try container.decode(String.self, forKey: .begin)
            end = try? container.decodeIfPresent(String.self, forKey: .end)
            statusImpact = try? container.decodeIfPresent(String.self, forKey: .statusImpact)
            affectedProducts = try container.lenient(.affectedProducts)
        }

        struct Product: Decodable {
            let id: String
        }
    }
}
