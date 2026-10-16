// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// Status pages built on a hosted product or an uptime monitor rather than
// written by hand: Instatus (Zed, GitKraken, Atlas Cloud), Upptime (Command
// Code), Gatus (Cline) and UptimeRobot (Charm's, for Hyper). Each feed is the
// one the page itself is drawn from. Only UptimeRobot publishes its days; the
// others are the state now and no bars — never a row of green standing in for
// days nobody published.

extension ServiceStatus {
    // MARK: - Instatus

    /// `/v2/components.json`: every component with its state, in the page's
    /// order, a group's name as its members'. A group's own row is in the
    /// list too, and is left out like Statuspage's.
    static func instatus(from data: Data) -> [Component]? {
        guard let feed = try? JSONDecoder().decode(InstatusFeed.self, from: data) else { return nil }
        let headers = Set(feed.components.compactMap(\.group?.id))
        let components = feed.components
            .filter { !headers.contains($0.id) }
            .map { Component(id: $0.id, name: $0.name, state: State(feedValue: $0.status), group: $0.group?.name) }
        return components.isEmpty ? nil : components
    }

    private struct InstatusFeed: Decodable {
        let components: [Component]

        enum CodingKeys: String, CodingKey { case components }

        init(from decoder: any Decoder) throws {
            components = try decoder.container(keyedBy: CodingKeys.self).lenient(.components)
        }

        struct Component: Decodable {
            let id: String
            let name: String
            let status: String
            let group: Group?

            enum CodingKeys: String, CodingKey { case id, name, status, group }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)
                status = try container.decode(String.self, forKey: .status)
                group = try? container.decodeIfPresent(Group.self, forKey: .group)
            }
        }

        struct Group: Decodable {
            let id: String
            let name: String
        }
    }

    // MARK: - Upptime

    /// The repository's `history/summary.json`: each monitored site, `up`,
    /// `degraded` or `down` as of the last check.
    static func upptime(from data: Data) -> [Component]? {
        guard let sites = try? JSONDecoder().decode([Lenient<UpptimeSite>].self, from: data) else { return nil }
        let components = sites.compactMap(\.value).map { site in
            Component(id: site.slug, name: site.name, state: upptimeState(site.status))
        }
        return components.isEmpty ? nil : components
    }

    static func upptimeState(_ value: String) -> State {
        switch value {
        case "up": .operational
        case "degraded": .degraded
        case "down": .fullOutage
        default: .unrecognised
        }
    }

    private struct UpptimeSite: Decodable {
        let name: String
        let slug: String
        let status: String
    }

    // MARK: - Gatus

    /// `/api/v1/endpoints/statuses`: each endpoint with its last checks,
    /// newest last. The state is the newest check's: passed, operational; a
    /// failed check that still got a 2xx failed on a condition such as
    /// response time, degraded; any other failure, an outage — what Gatus
    /// draws red.
    static func gatus(from data: Data) -> [Component]? {
        guard let endpoints = try? JSONDecoder().decode([Lenient<GatusEndpoint>].self, from: data) else { return nil }
        let components = endpoints.compactMap(\.value).map { endpoint in
            let state: State = switch endpoint.results.last {
            case nil: .unrecognised
            case let result? where result.success: .operational
            case let result? where (200..<300).contains(result.status ?? 0): .degraded
            case _?: .fullOutage
            }
            return Component(id: endpoint.key, name: endpoint.name, state: state, group: endpoint.group)
        }
        return components.isEmpty ? nil : components
    }

    private struct GatusEndpoint: Decodable {
        let name: String
        let group: String?
        let key: String
        let results: [Result]

        enum CodingKeys: String, CodingKey { case name, group, key, results }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            group = try? container.decodeIfPresent(String.self, forKey: .group)
            key = try container.decode(String.self, forKey: .key)
            results = try container.lenient(.results)
        }

        struct Result: Decodable {
            let success: Bool
            let status: Int?
        }
    }

    // MARK: - UptimeRobot

    /// A public page's `getMonitorList`: each monitor's state, its ninety
    /// daily uptime ratios, and the page's ninety-day figure. A day the page
    /// greys out (before the monitor existed, or paused) has no record; a
    /// whole day up is operational, a whole day down a full outage, and
    /// anything between a partial one — as Statuspage grades its days.
    static func uptimeRobot(from data: Data) -> [Component]? {
        guard let page = try? JSONDecoder().decode(UptimeRobotPage.self, from: data) else { return nil }
        let components = page.data.map { monitor in
            Component(
                id: String(monitor.monitorId),
                name: htmlUnescaped(monitor.name),
                state: uptimeRobotState(monitor.statusClass),
                days: monitor.dailyRatios.compactMap { day in
                    guard let date = dayComponents(day.date) else { return nil }
                    guard day.color != "grey", day.color != "black", let ratio = Double(day.ratio) else {
                        return Day(date: date, state: nil)
                    }
                    let state: State = ratio >= 100 ? .operational : ratio <= 0 ? .fullOutage : .partialOutage
                    return Day(date: date, state: state)
                },
                uptime: monitor.ninety.flatMap { Double($0.ratio) }
            )
        }
        return components.isEmpty ? nil : components
    }

    /// `success` is up, `danger` down; a paused monitor (`black`) is not a
    /// reading.
    static func uptimeRobotState(_ value: String) -> State {
        switch value {
        case "success": .operational
        case "warning": .degraded
        case "danger": .fullOutage
        default: .unrecognised
        }
    }

    /// The page writes names with HTML entities: "Soft Serve &#40;git.charm.sh&#41;".
    static func htmlUnescaped(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in [("&amp;", "&"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&apos;", "'")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        guard let numeric = try? Regex(#"&#(\d+);"#) else { return result }
        return result.replacing(numeric) { match in
            match.output[1].substring
                .flatMap { UInt32($0) }
                .flatMap(Unicode.Scalar.init)
                .map { String(Character($0)) } ?? String(result[match.range])
        }
    }

    private struct UptimeRobotPage: Decodable {
        let data: [Monitor]

        enum CodingKeys: String, CodingKey { case data }

        init(from decoder: any Decoder) throws {
            data = try decoder.container(keyedBy: CodingKeys.self).lenient(.data)
        }

        struct Monitor: Decodable {
            let monitorId: Int
            let name: String
            let statusClass: String
            let dailyRatios: [Ratio]
            let ninety: Ratio?

            enum CodingKeys: String, CodingKey {
                case monitorId, name, statusClass, dailyRatios
                case ninety = "90dRatio"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                monitorId = try container.decode(Int.self, forKey: .monitorId)
                name = try container.decode(String.self, forKey: .name)
                statusClass = try container.decode(String.self, forKey: .statusClass)
                dailyRatios = try container.lenient(.dailyRatios)
                ninety = try? container.decodeIfPresent(Ratio.self, forKey: .ninety)
            }
        }

        struct Ratio: Decodable {
            let date: String
            let ratio: String
            let color: String?

            enum CodingKeys: String, CodingKey { case date, ratio, color }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                date = (try? container.decodeIfPresent(String.self, forKey: .date)) ?? ""
                ratio = try container.decode(String.self, forKey: .ratio)
                color = try? container.decodeIfPresent(String.self, forKey: .color)
            }
        }
    }
}
