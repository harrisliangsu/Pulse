// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Whose status page, and what on it belongs to the provider.
enum StatusPage: Sendable, Hashable, CaseIterable {
    /// status.openai.com, its Codex group.
    case openAI
    /// status.claude.com, every component it shows.
    case claude
    /// status.deepseek.com, every component it shows.
    case deepSeek

    var address: URL {
        switch self {
        case .openAI: URL(string: "https://status.openai.com")!
        case .claude: URL(string: "https://status.claude.com")!
        case .deepSeek: URL(string: "https://status.deepseek.com")!
        }
    }

    var host: String { address.host() ?? "" }

    /// Who is speaking on the page, for the footnote.
    var company: String {
        switch self {
        case .openAI: "OpenAI"
        case .claude: "Anthropic"
        case .deepSeek: "DeepSeek"
        }
    }

    /// The provider whose pane shows it, and whose name a notification bears.
    var provider: Provider {
        switch self {
        case .openAI: .codex
        case .claude: .claudeCode
        case .deepSeek: .deepSeek
        }
    }

    /// Whether an outage of this component is worth a notification to
    /// someone using the provider. The pane shows every component on the
    /// page; a notification is only for what the provider's account runs on.
    /// Claude's by Statuspage id — Claude Code, and the API it runs on —
    /// because names change and ids don't. DeepSeek's by name: Pulse reads
    /// its API account, its API rows are named after the model ("DeepSeek V4
    /// Pro API服务"), and a new model is a new row; the chat site is not the
    /// API. Codex's page is read as its group already.
    func notifiesAbout(_ component: ServiceStatus.Component) -> Bool {
        switch self {
        case .openAI: true
        case .claude: ["yyzkbfz2thpt", "k8w3r06qmzrp"].contains(component.id)
        case .deepSeek: component.name.contains("API")
        }
    }

    /// How many days the page draws, ending today.
    var dayCount: Int {
        switch self {
        case .openAI: 91
        case .claude, .deepSeek: 90
        }
    }
}

extension Provider {
    /// The provider's own status page, where Pulse shows and watches it.
    var statusPage: StatusPage? {
        switch self {
        case .codex: .openAI
        case .claudeCode: .claude
        case .deepSeek: .deepSeek
        default: nil
        }
    }
}

/// What a provider's own status page says about its service: each
/// component's state now, the page's own uptime figure, and its last ninety
/// or so days, one bar a day as the page draws them.
///
/// **Three hosts, three feeds.** status.openai.com is incident.io's,
/// status.claude.com Atlassian Statuspage's, status.deepseek.com Flashcat's.
/// Each is read from what the page itself is drawn from, because no public
/// summary carries the history — OpenAI's Statuspage-compatible summary
/// leaves the Codex group out entirely, and Flashcat offers none without an
/// account key, so DeepSeek's is read out of the page.
///
/// **Nothing here is Pulse's figure.** The uptime percentage is the page's,
/// passed through and never computed; a missing one is not shown. Claude's
/// bars are the colours the page drew. OpenAI's are the worst impact the feed
/// lists on each local day — checked bar for bar against the page, all four
/// Codex rows, 2026-10-04. A component not listed as affected is operational,
/// because that is how both feeds say it; a page that can't be read is no
/// reading, never "all clear". Docs/providers/codex.md, "Service status".
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

        init(feedValue: String) {
            switch feedValue {
            case "operational": self = .operational
            // Flashcat (DeepSeek) says `degraded` and `maintenance`.
            case "degraded_performance", "degraded": self = .degraded
            case "partial_outage": self = .partialOutage
            // incident.io says `full_outage`, Statuspage `major_outage`.
            case "full_outage", "major_outage": self = .fullOutage
            case "under_maintenance", "maintenance": self = .maintenance
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
        /// The calendar day as the page counts it: this Mac's for OpenAI,
        /// the page's own for Claude.
        let date: DateComponents
        /// The worst the page recorded that day; nil before it kept any record
        /// of the component.
        let state: State?
        /// The colour the page drew, where it says: status.claude.com grades a
        /// day by how long it was out, which a state alone can't. 0xRRGGBB.
        var rgb: UInt32?
    }

    struct Component: Equatable, Sendable, Identifiable {
        let id: String
        /// The page's own name — "CLI", "Claude API (api.anthropic.com)" —
        /// shown as written, like a model name.
        let name: String
        let state: State
        /// Oldest first. Empty when the history couldn't be read; the current
        /// state still stands.
        var days: [Day] = []
        /// The page's figure for the period, in percent.
        var uptime: Double?
    }

    let page: StatusPage
    let components: [Component]

    // MARK: - Reading

    /// How often a status page is asked: by the outage check while its switch
    /// is on, and by a pane while it is open. Status pages are written by
    /// people, minutes into an incident; asking more often learns nothing
    /// sooner and only loads someone else's server.
    static let checkInterval: Duration = .seconds(300)

    /// The page's components, or nil when its current state couldn't be read.
    static func read(_ page: StatusPage, now: Date = .now) async -> ServiceStatus? {
        switch page {
        case .openAI: await readOpenAI(now: now)
        case .claude: await readClaude()
        case .deepSeek:
            await fetch(deepSeekPage, accept: "text/html").flatMap {
                flashcat(from: $0, now: now, days: calendarDays(endingAt: now, count: StatusPage.deepSeek.dayCount))
            }
            .map { ServiceStatus(page: .deepSeek, components: $0) }
        }
    }

    /// The state now and nothing else — one request, for the outage check
    /// (`UsageAlerts.checkServices`, every `checkInterval`). Nil when it
    /// couldn't be read.
    static func current(_ page: StatusPage) async -> [Component]? {
        switch page {
        case .openAI:
            guard let summary = await fetch(openAIFeed) else { return nil }
            return incidentIOComponents(from: summary, group: openAIGroup)
        case .claude:
            guard let summary = await fetch(claudeSummary) else { return nil }
            return statuspageComponents(from: summary)
        case .deepSeek:
            guard let page = await fetch(deepSeekPage, accept: "text/html") else { return nil }
            return flashcat(from: page, now: .now, days: nil)
        }
    }

    private static let openAIFeed = URL(string: "https://status.openai.com/proxy/status.openai.com")!
    private static let openAIGroup = "Codex"
    private static let claudeSummary = URL(string: "https://status.claude.com/api/v2/summary.json")!
    /// The page itself: Flashcat publishes no feed without an account key, and
    /// renders its data into the page.
    private static let deepSeekPage = URL(string: "https://status.deepseek.com/")!

    private static func readOpenAI(now: Date) async -> ServiceStatus? {
        let days = calendarDays(endingAt: now, count: StatusPage.openAI.dayCount)
        guard let first = days.first, let last = days.last else { return nil }

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var history = URLComponents(
            url: openAIFeed.appending(path: "component_impacts"),
            resolvingAgainstBaseURL: false
        )
        history?.queryItems = [
            URLQueryItem(name: "start_at", value: stamp.string(from: first.start)),
            URLQueryItem(name: "end_at", value: stamp.string(from: last.end)),
        ]

        async let summary = fetch(openAIFeed)
        async let impacts = fetch(history?.url)
        guard
            let summary = await summary,
            var components = incidentIOComponents(from: summary, group: openAIGroup)
        else { return nil }
        if let impacts = await impacts {
            components = incidentIOHistory(from: impacts, days: days, now: now, applyingTo: components)
        }
        return ServiceStatus(page: .openAI, components: components)
    }

    /// The summary first, because it says which components there are; then
    /// their history in one request (the page asks up to 60 at a time).
    private static func readClaude() async -> ServiceStatus? {
        guard
            let summary = await fetch(claudeSummary),
            var components = statuspageComponents(from: summary)
        else { return nil }

        var history = URLComponents(string: "https://status.claude.com/uptime_showcase")
        history?.queryItems = [
            URLQueryItem(name: "components", value: components.map(\.id).joined(separator: ",")),
        ]
        if let showcase = await fetch(history?.url) {
            components = statuspageHistory(from: showcase, applyingTo: components)
        }
        return ServiceStatus(page: .claude, components: components)
    }

    private static func fetch(_ url: URL?, accept: String = "application/json") async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(accept, forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await NetworkSession.shared.data(for: request),
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

    // MARK: - incident.io (status.openai.com)

    /// The named group's visible components, each with its state now. Nil when
    /// the feed doesn't parse or has no such group, or the group shows nothing.
    static func incidentIOComponents(from data: Data, group name: String) -> [Component]? {
        guard
            let feed = try? JSONDecoder().decode(IncidentIOFeed.self, from: data),
            let group = feed.summary.structure.items.lazy.compactMap(\.group).first(where: { $0.name == name })
        else { return nil }

        let affected = Dictionary(
            feed.summary.affectedComponents.map { ($0.componentID, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
        let components = group.components
            .filter { $0.hidden != true }
            .map { component in
                Component(
                    id: component.componentID,
                    name: component.name,
                    state: affected[component.componentID].map(State.init(feedValue:)) ?? .operational
                )
            }
        return components.isEmpty ? nil : components
    }

    /// Each component's days and uptime from the impacts feed: a day takes the
    /// worst impact that overlaps it, and a day that ended before the page had
    /// data for the component has none.
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

    /// One stretch of a component not being operational; no end while it
    /// lasts. The model incident.io and Flashcat share.
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

    private static func timestamp(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    // MARK: - Flashcat (status.deepseek.com)

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
                return Component(id: component.componentID, name: component.name, state: stated ?? open ?? .operational)
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

    // MARK: - Statuspage (status.claude.com)

    /// Every component the page shows, in its order, each with its state now:
    /// groups' own rows left out, and one marked to show only when degraded
    /// left out while it isn't. Nil when the page shows none.
    static func statuspageComponents(from data: Data) -> [Component]? {
        guard let summary = try? JSONDecoder().decode(StatuspageSummary.self, from: data) else { return nil }
        let components = summary.components
            .filter { $0.group != true && ($0.onlyShowIfDegraded != true || $0.status != "operational") }
            .sorted { ($0.position ?? .max) < ($1.position ?? .max) }
            .map { Component(id: $0.id, name: $0.name, state: State(feedValue: $0.status)) }
        return components.isEmpty ? nil : components
    }

    /// Each component's days, colours and uptime from the uptime showcase —
    /// the feed status.claude.com draws its bars from.
    static func statuspageHistory(from data: Data, applyingTo components: [Component]) -> [Component] {
        guard let showcase = try? JSONDecoder().decode(StatuspageShowcase.self, from: data) else { return components }

        return components.map { component in
            guard let timeline = showcase.timelines[component.id] else { return component }
            let started = timeline.component.startDate

            var days = timeline.days.compactMap { day -> Day? in
                let parts = day.date.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                let date = DateComponents(year: parts[0], month: parts[1], day: parts[2])
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

    // MARK: - Feeds

    private struct IncidentIOFeed: Decodable {
        let summary: Summary

        struct Summary: Decodable {
            let affectedComponents: [Affected]
            let structure: Structure

            enum CodingKeys: String, CodingKey {
                case affectedComponents = "affected_components"
                case structure
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                affectedComponents = try container.decodeIfPresent([Affected].self, forKey: .affectedComponents) ?? []
                structure = try container.decode(Structure.self, forKey: .structure)
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

        /// Either a group or a component on its own; only groups are read.
        struct Item: Decodable {
            let group: Group?
        }

        struct Group: Decodable {
            let name: String
            let components: [GroupComponent]

            enum CodingKeys: String, CodingKey { case name, components }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                components = try container.lenient(.components)
            }
        }

        struct GroupComponent: Decodable {
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
            componentImpacts = (try container.decodeIfPresent([Lenient<Impact>].self, forKey: .componentImpacts) ?? [])
                .compactMap(\.value)
            componentUptimes = (try container.decodeIfPresent([Lenient<Uptime>].self, forKey: .componentUptimes) ?? [])
                .compactMap(\.value)
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
            componentImpacts = (try container.decodeIfPresent([Lenient<ImpactRecord>].self, forKey: .componentImpacts) ?? [])
                .compactMap(\.value)
            componentUptimes = (try container.decodeIfPresent([Lenient<Uptime>].self, forKey: .componentUptimes) ?? [])
                .compactMap(\.value)
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

    /// One list entry, or nil when it doesn't decode.
    fileprivate struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
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
            let onlyShowIfDegraded: Bool?

            enum CodingKeys: String, CodingKey {
                case id, name, status, position, group
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

private extension KeyedDecodingContainer {
    /// A list read entry by entry: one the page shapes differently — a null
    /// name on some unrelated component — is skipped rather than taking every
    /// other component, and so the whole pane and every alert, with it. A
    /// missing list is empty.
    func lenient<Element: Decodable>(_ key: Key) throws -> [Element] {
        (try decodeIfPresent([ServiceStatus.Lenient<Element>].self, forKey: key) ?? []).compactMap(\.value)
    }
}
