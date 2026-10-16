// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What a provider's own status page says about its service: each
/// component's state now, the page's own uptime figure, and its last ninety
/// or so days, one bar a day as the page draws them.
///
/// **Each feed is read from what its page is drawn from** (`StatusFeed`):
/// Statuspage's and incident.io's own feeds, Flashcat's page payload, Better
/// Stack's `index.json`, and so on — because no common summary carries the
/// history, and some carry nothing at all of what the page shows. One file a
/// platform: `ServiceStatus+Statuspage`, `+IncidentIO`, `+Flashcat`,
/// `+BetterStack`, `+Instatus`, `+Monitors`, `+Companies`.
///
/// **Nothing here is Pulse's figure.** The uptime percentage is the page's,
/// passed through and never computed; a missing one is not shown. A page
/// that publishes no days gets no bars, never a row of green. A component
/// not listed as affected is operational where that is how the feed says it;
/// a page that can't be read is no reading, never "all clear".
/// Docs/providers/README.md, "Service status".
struct ServiceStatus: Equatable, Sendable {
    /// Raw values are what `OutageMemory` writes to disk; don't rename them.
    enum State: String, Codable, Equatable, Sendable {
        case operational
        case degraded
        case partialOutage
        case fullOutage
        case maintenance
        /// A value this build doesn't know. Shown as unrecognised, never as
        /// operational.
        case unrecognised

        /// What a notification is about: the service is failing. Maintenance
        /// is planned, and a value Pulse can't read is not a witnessed outage.
        var isOutage: Bool {
            switch self {
            case .degraded, .partialOutage, .fullOutage: true
            case .operational, .maintenance, .unrecognised: false
            }
        }

        /// The feeds' words, whatever their case and separators:
        /// Statuspage's `degraded_performance` and `major_outage`, incident.io's
        /// `full_outage`, Instatus's `DEGRADEDPERFORMANCE`, Flashcat's and
        /// OpenCode's `degraded`, DeepInfra's `OUTAGE`. Anything else —
        /// OpenCode's `unknown` — is unrecognised.
        init(feedValue: String) {
            let word = feedValue.lowercased().filter { $0.isLetter }
            switch word {
            case "operational": self = .operational
            case "degradedperformance", "degraded": self = .degraded
            case "partialoutage": self = .partialOutage
            case "fulloutage", "majoroutage", "outage": self = .fullOutage
            case "undermaintenance", "maintenance": self = .maintenance
            default: self = .unrecognised
            }
        }

        /// What the pane and a notification call it.
        var title: String {
            switch self {
            case .operational: String.localized("Operational")
            case .degraded: String.localized("Degraded performance")
            case .partialOutage: String.localized("Partial outage")
            case .fullOutage: String.localized("Full outage")
            case .maintenance: String.localized("Under maintenance")
            case .unrecognised: String.localized("Unrecognised status")
            }
        }

        /// For picking a day's worst, and telling worse from better.
        var severity: Int {
            switch self {
            case .operational: 0
            case .maintenance: 1
            case .unrecognised: 2
            case .degraded: 3
            case .partialOutage: 4
            case .fullOutage: 5
            }
        }
    }

    /// One day of a component's history.
    struct Day: Equatable, Sendable {
        /// The calendar day as the page counts it: this Mac's where Pulse
        /// lays the days out, the page's own where it lists them.
        let date: DateComponents
        /// The worst the page recorded that day; nil before it kept any record
        /// of the component.
        let state: State?
        /// The colour the page drew, where it says: status.claude.com grades a
        /// day by how long it was out, which a state alone can't. 0xRRGGBB.
        var rgb: UInt32?
        /// Hours, for a page whose bars are shorter than a day — OpenCode's
        /// are three — with `date` carrying the hour the bar starts; nil for
        /// a day.
        var hours: Int?
    }

    struct Component: Equatable, Sendable, Identifiable {
        let id: String
        /// The page's own name — "CLI", "Claude API (api.anthropic.com)" —
        /// shown as written, like a model name.
        let name: String
        let state: State
        /// Oldest first. Empty when the page publishes no days or they
        /// couldn't be read; the current state still stands.
        var days: [Day] = []
        /// The page's figure for the period, in percent.
        var uptime: Double?
        /// The group the page draws it under, as `ComponentRule.groups`
        /// matches it; nil for a row of its own.
        var group: String?
    }

    let page: StatusPage
    let components: [Component]

    // MARK: - Reading

    /// How often a status page is asked: by the outage check while its switch
    /// is on, and by a pane while it is open. Status pages are written by
    /// people, minutes into an incident; asking more often learns nothing
    /// sooner and only loads someone else's server.
    static let checkInterval: Duration = .seconds(300)

    /// The rows the provider's pane shows, with their days. Nil when the
    /// page's current state couldn't be read, or none of it is the
    /// provider's any more — a row renamed or removed is said, not hidden.
    static func read(_ page: StatusPage, now: Date = .now) async -> ServiceStatus? {
        let days = calendarDays(endingAt: now, count: page.dayCount)
        guard
            let components = await read(page.feed, showing: page.shows, days: days, now: now),
            !components.isEmpty
        else { return nil }
        return ServiceStatus(page: page, components: components)
    }

    /// Every component on the feed with its state now, and nothing else —
    /// one request, for the outage check (`UsageAlerts.checkServices`, every
    /// `checkInterval`), which reads a shared feed once for every provider on
    /// it. Nil when it couldn't be read.
    static func current(_ feed: StatusFeed, now: Date = .now) async -> [Component]? {
        switch feed {
        case .statuspage(let root):
            return await fetch(root.appending(path: "api/v2/summary.json")).flatMap(statuspageComponents)
        case .incidentIO(let url):
            return await fetch(url).flatMap(incidentIOSummary)?.components
        case .flashcat(let url):
            return await fetch(url, accept: "text/html").flatMap { flashcat(from: $0, now: now, days: nil) }
        case .betterStack(let url):
            return await fetch(url).flatMap { betterStack(from: $0) }
        case .instatus(let url):
            return await fetch(url).flatMap(instatus)
        case .upptime(let url):
            return await fetch(url).flatMap(upptime)
        case .gatus(let url):
            return await fetch(url).flatMap(gatus)
        case .uptimeRobot(let url):
            return await fetch(url).flatMap(uptimeRobot)
        case .openCode(let url):
            return await fetch(url).flatMap { openCode(from: $0) }
        case .deepInfra(let url):
            return await fetch(url).flatMap(deepInfra)
        case .ibmBob(let url):
            return await fetch(url).flatMap(ibmBob)
        case .googleCloud(let url, let product, let name):
            return await fetch(url).flatMap { googleCloud(from: $0, product: product, name: name, now: now, days: nil) }
        }
    }

    /// The components `rule` keeps, with whatever days the feed has.
    private static func read(
        _ feed: StatusFeed, showing rule: ComponentRule, days: [DateInterval], now: Date
    ) async -> [Component]? {
        switch feed {
        case .statuspage(let root):
            return await readStatuspage(root: root, showing: rule)
        case .incidentIO(let url):
            return await readIncidentIO(url, showing: rule, days: days, now: now)
        case .flashcat(let url):
            return await fetch(url, accept: "text/html")
                .flatMap { flashcat(from: $0, now: now, days: days) }?
                .filter(rule.matches)
        case .googleCloud(let url, let product, let name):
            return await fetch(url)
                .flatMap { googleCloud(from: $0, product: product, name: name, now: now, days: days) }?
                .filter(rule.matches)
        case .betterStack, .instatus, .upptime, .gatus, .uptimeRobot, .openCode, .deepInfra, .ibmBob:
            // One request carries whatever the feed has.
            return await current(feed, now: now)?.filter(rule.matches)
        }
    }

    static func fetch(_ url: URL?, accept: String = "application/json") async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(accept, forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await NetworkSession.shared.recordedData(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// The last `count` calendar days, oldest first, today last.
    static func calendarDays(endingAt now: Date, count: Int, calendar: Calendar = .current) -> [DateInterval] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            guard
                let start = calendar.date(byAdding: .day, value: -back, to: today),
                let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// "2026-10-04" as the page wrote it, a calendar day without a zone.
    static func dayComponents(_ text: String) -> DateComponents? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    // MARK: - Impacts, the model incident.io, Flashcat and Google Cloud share

    /// One stretch of a component not being operational; no end while it
    /// lasts.
    struct Impact: Sendable {
        let componentID: String
        let start: Date
        let end: Date?
        let state: State
    }

    /// Each component's days and uptime from its impacts: a day takes the
    /// worst impact that overlaps it, and a day that ended before the page had
    /// data for the component has none.
    static func applyingHistory(
        impacts: [Impact],
        since: [String: Date],
        uptimes: [String: Double],
        days: [DateInterval],
        now: Date,
        calendar: Calendar,
        to components: [Component]
    ) -> [Component] {
        components.map { component in
            let spans = impacts
                .filter { $0.componentID == component.id }
                .compactMap { impact -> (DateInterval, State)? in
                    let end = impact.end ?? now
                    guard end > impact.start else { return nil }
                    return (DateInterval(start: impact.start, end: end), impact.state)
                }
            let started = since[component.id]

            var component = component
            component.days = days.map { day in
                let date = calendar.dateComponents([.year, .month, .day], from: day.start)
                if let started, day.end <= started { return Day(date: date, state: nil) }
                let worst = spans
                    .filter { $0.0.start < day.end && $0.0.end > day.start }
                    .map(\.1)
                    .max { $0.severity < $1.severity }
                return Day(date: date, state: worst ?? .operational)
            }
            component.uptime = uptimes[component.id]
            return component
        }
    }

    static func timestamp(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// One list entry, or nil when it doesn't decode.
    struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}

extension KeyedDecodingContainer {
    /// A list read entry by entry: one the page shapes differently — a null
    /// name on some unrelated component — is skipped rather than taking every
    /// other component, and so the whole pane and every alert, with it. A
    /// missing list is empty.
    func lenient<Element: Decodable>(_ key: Key) throws -> [Element] {
        (try decodeIfPresent([ServiceStatus.Lenient<Element>].self, forKey: key) ?? []).compactMap(\.value)
    }
}
