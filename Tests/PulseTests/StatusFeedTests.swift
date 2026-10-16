import Foundation
import Testing
@testable import Pulse

/// The status feeds beyond the first four pages: made-up replies in each
/// platform's real shape (taken from the pages on 2026-10-15), and the
/// catalogue's rules for what on a shared page belongs to whom.
@Suite("Status feeds")
struct StatusFeedTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - The catalogue

    @Test("Every page is the provider's own, on https, and pages sharing a feed are told apart by their rows")
    func catalogue() {
        let pages = StatusPage.catalogue
        #expect(pages.count >= 44)
        for page in pages {
            #expect(page.address.scheme == "https", "\(page.provider)")
            #expect(!page.company.isEmpty, "\(page.provider)")
        }
        // Two providers on one page never show the same rows.
        #expect(StatusPage.of(.cursor)!.feed == StatusPage.of(.grokBot)!.feed)
        let grokBot = ServiceStatus.Component(id: "sm5wkcnqkvr9", name: "Grok Bot", state: .fullOutage)
        #expect(StatusPage.of(.grokBot)!.notifiesAbout(grokBot))
        #expect(!StatusPage.of(.cursor)!.shows.matches(grokBot))
        #expect(StatusPage.of(.kimiCode)!.feed == StatusPage.of(.moonshot)!.feed)
    }

    @Test("MiniMax's page follows the account's site")
    func miniMaxSite() {
        #expect(StatusPage.of(.minimax, minimaxSite: .international)?.host == "status.minimax.io")
        #expect(StatusPage.of(.minimax, minimaxSite: .china)?.host == "status.minimaxi.com")
    }

    @Test("A provider with no page Pulse can read has none, not a stand-in")
    func noStandIns() {
        for provider in [Provider.antigravity, .xaiAPI, .grok, .mistral, .zai, .ollamaCloud] {
            #expect(StatusPage.of(provider) == nil, "\(provider)")
        }
    }

    @Test("Feed words are read whatever their case and separators")
    func feedWords() {
        #expect(ServiceStatus.State(feedValue: "OPERATIONAL") == .operational)
        #expect(ServiceStatus.State(feedValue: "DEGRADEDPERFORMANCE") == .degraded)
        #expect(ServiceStatus.State(feedValue: "degraded_performance") == .degraded)
        #expect(ServiceStatus.State(feedValue: "PARTIALOUTAGE") == .partialOutage)
        #expect(ServiceStatus.State(feedValue: "MAJOROUTAGE") == .fullOutage)
        #expect(ServiceStatus.State(feedValue: "OUTAGE") == .fullOutage)
        #expect(ServiceStatus.State(feedValue: "UNDERMAINTENANCE") == .maintenance)
        #expect(ServiceStatus.State(feedValue: "unknown") == .unrecognised)
    }

    // MARK: - Statuspage

    @Test("Statuspage rows carry their group's id, so a page's mirrored suppliers can be left out")
    func statuspageGroups() throws {
        let summary = data("""
        {"components":[
          {"id":"kfqc4mfdkrqx","name":"api.factory.ai","status":"operational","position":1,"group":false,"group_id":null},
          {"id":"8j6062wq4cl6","name":"Anthropic","status":"major_outage","position":2,"group":false,"group_id":"c9sjq8nsz2kq"},
          {"id":"c9sjq8nsz2kq","name":"Models","status":"major_outage","position":3,"group":true,"group_id":null}
        ]}
        """)
        let components = try #require(ServiceStatus.statuspageComponents(from: summary))
        #expect(components.map(\.id) == ["kfqc4mfdkrqx", "8j6062wq4cl6"])
        #expect(components[1].group == "c9sjq8nsz2kq")
        let factory = StatusPage.of(.factory)!
        #expect(components.filter(factory.shows.matches).map(\.name) == ["api.factory.ai"])
    }

    // MARK: - incident.io

    @Test("incident.io rows of their own are read beside groups, and a chart-only page shows no percentage")
    func incidentIOLooseRows() throws {
        let summary = data("""
        {"summary":{"display_uptime_mode":"chart_only","affected_components":[{"component_id":"b","status":"degraded_performance"}],
          "structure":{"items":[
            {"component":{"component_id":"a","name":"JetBrains AI","hidden":false}},
            {"group":{"id":"g","name":"AI Providers","hidden":false,"components":[{"component_id":"b","name":"Anthropic","hidden":false}]}},
            {"component":{"component_id":"c","name":"Hidden","hidden":true}}
          ]}}}
        """)
        let feed = try #require(ServiceStatus.incidentIOSummary(from: summary))
        #expect(feed.components.map(\.name) == ["JetBrains AI", "Anthropic"])
        #expect(feed.components.map(\.group) == [nil, "AI Providers"])
        #expect(feed.components[1].state == .degraded)
        #expect(!feed.showsUptime)
        let jetBrains = StatusPage.of(.jetBrainsAI)!
        #expect(feed.components.filter(jetBrains.shows.matches).map(\.name) == ["JetBrains AI"])
    }

    // MARK: - Better Stack

    private let betterStackPage = """
    {"data":{"id":"1","type":"status_page","attributes":{}},
     "included":[
      {"id":"20","type":"status_page_section","attributes":{"name":"API","position":1}},
      {"id":"10","type":"status_page_section","attributes":{"name":"Website","position":0}},
      {"id":"8599285","type":"status_page_resource","attributes":{"status_page_section_id":20,"public_name":"API Heartbeat","position":0,
        "availability":0.9991,"status":"downtime",
        "status_history":[{"day":"2026-10-13","status":"not_monitored"},{"day":"2026-10-14","status":"downtime"},{"day":"2026-10-15","status":"operational"}]}},
      {"id":"77","type":"status_page_resource","attributes":{"status_page_section_id":10,"public_name":"chutes.ai","position":0,
        "availability":1.0,"status":"not_monitored","status_history":[]}},
      {"id":"5","type":"status_report","attributes":{"title":"Maintenance"}}
     ]}
    """

    @Test("Better Stack: sections in order, the page's days and figure, and not-monitored is no reading")
    func betterStack() throws {
        let components = try #require(ServiceStatus.betterStack(from: data(betterStackPage)))
        #expect(components.map(\.name) == ["chutes.ai", "API Heartbeat"])
        #expect(components.map(\.group) == ["Website", "API"])
        let api = components[1]
        #expect(api.state == .fullOutage)
        #expect(api.days.map(\.state) == [nil, .fullOutage, .operational])
        #expect(api.days.first?.date == DateComponents(year: 2026, month: 10, day: 13))
        #expect(abs((api.uptime ?? 0) - 99.91) < 0.0001)
        // Monitoring switched off is not a clear service.
        #expect(components[0].state == .unrecognised)
        #expect(ServiceStatus.betterStack(from: data("{}")) == nil)
    }

    // MARK: - Instatus

    @Test("Instatus: a group's own row is left out and its name is its members' group")
    func instatus() throws {
        let feed = data("""
        {"components":[
          {"id":"agent","name":"Agent","status":"OPERATIONAL","group":null},
          {"id":"zed","name":"Zed","status":"OPERATIONAL","group":null},
          {"id":"edit","name":"Edit Prediction","status":"PARTIALOUTAGE","group":{"id":"zed","name":"Zed"}},
          {"id":"delta","name":"Delta","status":"OPERATIONAL","group":null},
          {"id":"cloud","name":"Delta Cloud Services","status":"MAJOROUTAGE","group":{"id":"delta","name":"Delta"}}
        ]}
        """)
        let components = try #require(ServiceStatus.instatus(from: feed))
        #expect(components.map(\.name) == ["Agent", "Edit Prediction", "Delta Cloud Services"])
        #expect(components[1].state == .partialOutage)
        #expect(components.allSatisfy { $0.days.isEmpty })
        let zed = StatusPage.of(.zed)!
        #expect(components.filter(zed.shows.matches).map(\.name) == ["Agent", "Edit Prediction"])
    }

    // MARK: - Monitors

    @Test("Upptime: up, degraded and down, and no bars")
    func upptime() throws {
        let feed = data(#"[{"name":"Command Code","slug":"command-code","status":"down","dailyMinutesDown":{"2026-10-14":12}}]"#)
        let components = try #require(ServiceStatus.upptime(from: feed))
        #expect(components.map(\.state) == [.fullOutage])
        #expect(components[0].days.isEmpty)
        #expect(ServiceStatus.upptimeState("up") == .operational)
    }

    @Test("Gatus: the newest check decides; a 2xx that failed a condition is degraded")
    func gatus() throws {
        let feed = data("""
        [{"name":"API Health Check","group":"Availability","key":"api","results":[
            {"status":500,"success":false},{"status":200,"success":true}]},
         {"name":"Slow","group":null,"key":"slow","results":[{"status":200,"success":false}]},
         {"name":"Down","key":"down","results":[{"status":0,"success":false}]},
         {"name":"New","key":"new","results":[]}]
        """)
        let components = try #require(ServiceStatus.gatus(from: feed))
        #expect(components.map(\.state) == [.operational, .degraded, .fullOutage, .unrecognised])
        #expect(components[0].group == "Availability")
    }

    @Test("UptimeRobot: grey days are no record, and the names lose their entities")
    func uptimeRobot() throws {
        let feed = data("""
        {"status":"ok","data":[{"monitorId":803945156,"name":"Soft Serve &#40;git.charm.sh&#41;","statusClass":"danger",
          "dailyRatios":[{"date":"2026-10-13","ratio":"0.000","label":"black","color":"grey"},
                         {"date":"2026-10-14","ratio":"99.500","label":"good","color":"blue"},
                         {"date":"2026-10-15","ratio":"100.000","label":"excellent","color":"green"}],
          "90dRatio":{"ratio":"99.950","label":"excellent","color":"green"}}]}
        """)
        let monitor = try #require(ServiceStatus.uptimeRobot(from: feed)?.first)
        #expect(monitor.id == "803945156")
        #expect(monitor.name == "Soft Serve (git.charm.sh)")
        #expect(monitor.state == .fullOutage)
        #expect(monitor.days.map(\.state) == [nil, .partialOutage, .operational])
        #expect(monitor.uptime == 99.95)
    }

    // MARK: - Companies' own

    @Test("OpenCode: the page's names, and its 56 three-hour slots ending with the one under way")
    func openCode() throws {
        let feed = data("""
        {"status":"operational","components":[{"service":"go","status":"degraded"},{"service":"payg","status":"unknown"},{"service":"new","status":"operational"}],
         "history":[{"start":1792033200000,"services":{"go":"degraded","payg":"operational"}},
                    {"start":1792022400000,"services":{"go":"unknown","payg":"operational"}}]}
        """)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 1792033200 is a slot's start; an hour into it is still that slot.
        let now = Date(timeIntervalSince1970: 1_792_033_200 + 3600)
        let components = try #require(ServiceStatus.openCode(from: feed, now: now, calendar: calendar))
        #expect(components.map(\.name) == ["Go", "Pay-as-you-go", "new"])
        #expect(components.map(\.state) == [.degraded, .unrecognised, .operational])
        let go = components[0]
        #expect(go.days.count == 56)
        #expect(go.days.allSatisfy { $0.hours == 3 })
        // The last slot is the one under way, the one before it three hours back.
        #expect(go.days.last?.state == .degraded)
        #expect(go.days[54].state == nil)  // "unknown" is no record
        #expect(go.days[53].state == nil)  // outside the history
        #expect(components[1].days[54].state == .operational)
        #expect(go.days.last?.date.hour == calendar.component(.hour, from: Date(timeIntervalSince1970: 1_792_033_200)))
    }

    @Test("DeepInfra: its services, not its models")
    func deepInfra() throws {
        let feed = data("""
        {"overallStatus":"OPERATIONAL","services":[{"publicId":"api","displayName":"API","status":"OUTAGE"}],
         "models":[{"publicId":"m","displayName":"Model","status":"OPERATIONAL"}]}
        """)
        let components = try #require(ServiceStatus.deepInfra(from: feed))
        #expect(components.map(\.id) == ["api"])
        #expect(components[0].state == .fullOutage)
    }

    @Test("IBM Bob: one row per service name, the worst of its checks")
    func ibmBob() throws {
        let feed = data("""
        {"regions":[{"id":"us-east","name":"us-east","services":[
          {"id":"1","name":"Chat/Code Completion","status":"operational"},
          {"id":"2","name":"Admin","status":"operational"},
          {"id":"3","name":"Chat/Code Completion","status":"partial_outage"}]}]}
        """)
        let components = try #require(ServiceStatus.ibmBob(from: feed))
        #expect(components.map(\.name) == ["Chat/Code Completion", "Admin"])
        #expect(components[0].state == .partialOutage)
        #expect(StatusPage.of(.ibmBob)!.notifiesAbout(components[0]))
        #expect(!StatusPage.of(.ibmBob)!.notifiesAbout(components[1]))
    }

    @Test("Google Cloud: an open incident on the product is its state, and its incidents are its days")
    func googleCloud() throws {
        let feed = data("""
        [{"begin":"2026-10-14T10:00:00+00:00","end":null,"status_impact":"SERVICE_DISRUPTION",
          "affected_products":[{"title":"Gemini Code Assist","id":"gca"}]},
         {"begin":"2026-10-12T10:00:00+00:00","end":"2026-10-12T11:00:00+00:00","status_impact":"SERVICE_OUTAGE",
          "affected_products":[{"title":"Gemini Code Assist","id":"gca"}]},
         {"begin":"2026-10-15T01:00:00+00:00","end":null,"status_impact":"SERVICE_OUTAGE",
          "affected_products":[{"title":"Cloud Storage","id":"gcs"}]}]
        """)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
        let days = ServiceStatus.calendarDays(endingAt: now, count: 4, calendar: calendar)
        let product = try #require(ServiceStatus.googleCloud(
            from: feed, product: "gca", name: "Gemini Code Assist", now: now, days: days, calendar: calendar
        )?.first)
        #expect(product.name == "Gemini Code Assist")
        #expect(product.state == .partialOutage)
        #expect(product.days.map(\.state) == [.fullOutage, .operational, .partialOutage, .partialOutage])

        let quiet = try #require(ServiceStatus.googleCloud(from: data("[]"), product: "gca", name: "Gemini Code Assist", now: now, days: nil))
        #expect(quiet.map(\.state) == [.operational])
        #expect(ServiceStatus.googleCloud(from: data("{}"), product: "gca", name: "x", now: now, days: nil) == nil)
    }
}
