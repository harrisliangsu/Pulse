import Foundation
import Testing
@testable import Pulse

/// Provider status pages (`ServiceStatus`): status.openai.com's Codex group
/// and every component status.claude.com shows.
///
/// Captured live on 2026-10-04 and trimmed to what is read:
/// `openai-status-operational` (the page's summary), `openai-status-impacts`
/// (Codex's impacts over the page's own 91-day window, as the page requested
/// it from UTC+8, and **every** uptime entry — the groups' own come without a
/// `component_id`, and requiring one once lost the whole history in the app
/// while a fixture trimmed to Codex passed), `claude-status-summary` and
/// `claude-status-uptime`.
/// The OpenAI bars below were read off the page itself the same day, so the
/// history test is the page, bar for bar.
///
/// `openai-status-incident` is written by hand: its shape follows CodexBar's
/// incident.io fixtures (MIT), because no live incident has been captured.
@Suite("Service status")
struct ServiceStatusTests {
    private func fixture(_ name: String, _ ext: String = "json") throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// One character a day: 0 operational, 1 degraded, 2 partial, 3 full,
    /// m maintenance, ? unrecognised, - no record.
    private func bars(_ component: ServiceStatus.Component) -> String {
        String(component.days.map { day -> Character in
            switch day.state {
            case nil: "-"
            case .operational: "0"
            case .degraded: "1"
            case .partialOutage: "2"
            case .fullOutage: "3"
            case .maintenance: "m"
            case .unrecognised: "?"
            }
        })
    }

    // MARK: - status.openai.com

    @Test("The live page lists Codex's four components, all operational")
    func operational() throws {
        let components = try #require(ServiceStatus.incidentIOComponents(from: try fixture("openai-status-operational"), group: "Codex"))

        #expect(components.map(\.name) == ["Codex Web", "Codex API", "CLI", "VS Code extension"])
        #expect(components.allSatisfy { $0.state == .operational })
    }

    @Test("Affected components take their stated state; the rest are operational")
    func incident() throws {
        let components = try #require(ServiceStatus.incidentIOComponents(from: try fixture("openai-status-incident"), group: "Codex"))

        // Hidden rows are dropped; another group's outage is not Codex's.
        #expect(components.map(\.name) == ["Codex Web", "Codex API", "CLI", "VS Code extension"])
        #expect(components.map(\.state) == [.degraded, .operational, .fullOutage, .unrecognised])
    }

    @Test("Each day takes its worst impact — the page's own bars, every one")
    func openAIHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-04T12:00:00+08:00"))
        let days = ServiceStatus.calendarDays(endingAt: now, count: 91, calendar: calendar)
        #expect(days.first?.start == ISO8601DateFormatter().date(from: "2026-07-05T16:00:00Z"))

        let current = try #require(ServiceStatus.incidentIOComponents(from: try fixture("openai-status-operational"), group: "Codex"))
        let components = ServiceStatus.incidentIOHistory(
            from: try fixture("openai-status-impacts"), days: days, now: now, calendar: calendar, applyingTo: current
        )

        let page = [
            "Codex Web": "0000000000000010011100000000000000000000000000000000000000011000000000000000000000300010000",
            "Codex API": "0000000000000000011100000000000000000000000000100000000000011000000000000000000000300010000",
            "CLI": "0000000000001010011100000000000000000000000000000000000000011000000000000000000000300010000",
            "VS Code extension": "0000000000000010011100000000000000000000000000000000000000011000000000000000000000300010000",
        ]
        for component in components {
            #expect(bars(component) == page[component.name], "\(component.name)")
            #expect(component.uptime == 99.95)
            #expect(component.days.allSatisfy { $0.rgb == nil })
        }
        #expect(components.first?.days.first?.date == DateComponents(year: 2026, month: 7, day: 6))
        #expect(components.first?.days.last?.date == DateComponents(year: 2026, month: 10, day: 4))
    }

    @Test("Days that ended before the page had data have no record")
    func openAIBeforeData() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        // Codex API's data starts 2026-03-26T22:18Z; a window over that week.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-03-29T12:00:00+08:00"))
        let days = ServiceStatus.calendarDays(endingAt: now, count: 6, calendar: calendar)
        let current = [ServiceStatus.Component(id: "01KMP3KP5MGE23B80K1EK4S8PV", name: "Codex API", state: .operational)]

        let components = ServiceStatus.incidentIOHistory(
            from: try fixture("openai-status-impacts"), days: days, now: now, calendar: calendar, applyingTo: current
        )
        // 24th–26th local ended before 06:18 on the 27th local; the 27th holds it.
        #expect(bars(try #require(components.first)) == "---000")
    }

    @Test("A missing group, or a feed that isn't one, is no reading — not all clear")
    func missing() throws {
        #expect(ServiceStatus.incidentIOComponents(from: try fixture("openai-status-operational"), group: "Nonexistent") == nil)
        #expect(ServiceStatus.incidentIOComponents(from: Data("{}".utf8), group: "Codex") == nil)
        #expect(ServiceStatus.incidentIOComponents(from: Data("<html></html>".utf8), group: "Codex") == nil)
    }

    @Test("A history that can't be read leaves the current state standing")
    func unreadableHistory() throws {
        let current = try #require(ServiceStatus.incidentIOComponents(from: try fixture("openai-status-operational"), group: "Codex"))
        let components = ServiceStatus.incidentIOHistory(
            from: Data("<html></html>".utf8), days: [], now: .now, applyingTo: current
        )
        #expect(components == current)
    }

    // MARK: - status.claude.com

    @Test("Every component the page shows, in the page's order")
    func claudeComponents() throws {
        let components = try #require(ServiceStatus.statuspageComponents(from: try fixture("claude-status-summary")))
        #expect(components.map(\.name) == [
            "claude.ai", "Claude Console (platform.claude.com)", "Claude API (api.anthropic.com)",
            "Claude Code", "Claude Cowork", "Claude for Government",
        ])
        #expect(components.allSatisfy { $0.state == .operational })
        #expect(ServiceStatus.statuspageComponents(from: Data("{}".utf8)) == nil)
    }

    @Test("Groups' own rows are left out, and a show-when-degraded one while it isn't")
    func claudeHiddenComponents() throws {
        let summary = Data(#"""
        {"components": [
          {"id": "b", "name": "Second", "status": "operational", "position": 2},
          {"id": "g", "name": "A group", "status": "operational", "position": 0, "group": true},
          {"id": "a", "name": "First", "status": "operational", "position": 1, "group_id": "g"},
          {"id": "quiet", "name": "Quiet", "status": "operational", "position": 3, "only_show_if_degraded": true},
          {"id": "loud", "name": "Loud", "status": "partial_outage", "position": 4, "only_show_if_degraded": true}
        ]}
        """#.utf8)
        let components = try #require(ServiceStatus.statuspageComponents(from: summary))
        #expect(components.map(\.name) == ["First", "Second", "Loud"])
        #expect(components.last?.state == .partialOutage)
    }

    @Test("Claude's ninety days carry the page's colours and its uptime figures")
    func claudeHistory() throws {
        let current = try #require(ServiceStatus.statuspageComponents(from: try fixture("claude-status-summary")))
        let components = ServiceStatus.statuspageHistory(from: try fixture("claude-status-uptime"), applyingTo: current)

        // The figures the page printed that day, in its order.
        #expect(components.map(\.uptime) == [99.44, 99.95, 99.52, 99.44, 99.44, 100])
        #expect(components.allSatisfy { $0.days.count == 90 })

        let code = try #require(components.first { $0.name == "Claude Code" })
        #expect(code.days.first?.date == DateComponents(year: 2026, month: 7, day: 7))
        #expect(code.days.last?.date == DateComponents(year: 2026, month: 10, day: 4))
        #expect(code.days.first?.state == .partialOutage)
        #expect(code.days.first?.rgb == 0xE75F36)
        #expect(code.days.dropFirst().first?.rgb == 0x76AD2A)

        // The state read from the outage seconds agrees with the page's own
        // colour: green exactly on the days with no outage.
        for component in components {
            for day in component.days {
                #expect((day.rgb == 0x76AD2A) == (day.state == .operational), "\(component.name) \(day.date)")
            }
        }
    }

    @Test("Colours are used only when there is one for every day")
    func claudePartialColours() throws {
        let one = ##"<rect height="34" width="3" x="0" y="0" fill="#e75f36" role="tab" class="uptime-day component-x day-0" />"##
        #expect(ServiceStatus.barColours(in: one) == [0xE75F36])
        #expect(ServiceStatus.barColours(in: ##"<rect fill="#000000" class="legend" />"##).isEmpty)

        let showcase = Data(#"""
        {"timelines": {"x": {"component": {"startDate": "2026-10-02"}, "days": [
            {"date": "2026-10-01", "outages": {}},
            {"date": "2026-10-02", "outages": {"m": 60}},
            {"date": "2026-10-03", "outages": {"p": 60}}
        ]}},
         "values": [],
         "components": {"x": "\#(one.replacingOccurrences(of: "\"", with: "\\\""))"}}
        """#.utf8)
        let components = ServiceStatus.statuspageHistory(
            from: showcase, applyingTo: [ServiceStatus.Component(id: "x", name: "X", state: .operational)]
        )
        let x = try #require(components.first)
        #expect(bars(x) == "-32")
        #expect(x.days.allSatisfy { $0.rgb == nil })
        #expect(x.uptime == nil)
    }

    // MARK: - status.deepseek.com

    @Test("DeepSeek's page: every component in its order, a section opened into its own")
    func deepSeekComponents() throws {
        let components = try #require(ServiceStatus.flashcat(
            from: try fixture("deepseek-status-page", "html"), now: .now, days: nil
        ))
        #expect(components.map(\.name) == [
            "DeepSeek V4 Pro API服务(API Service)", "DeepSeek V4.1 Flash API服务(API Service)",
            "对话服务(Chatservice)", "上传文件服务(File Upload Service)", "搜索服务(Search Service)",
        ])
        #expect(components.allSatisfy { $0.state == .operational })
        #expect(components.allSatisfy { $0.days.isEmpty })
        // Notified about: the API rows, which is what Pulse's DeepSeek account is.
        #expect(components.filter(StatusPage.deepSeek.notifiesAbout).map(\.name) == [
            "DeepSeek V4 Pro API服务(API Service)", "DeepSeek V4.1 Flash API服务(API Service)",
        ])
    }

    @Test("DeepSeek's days are the page's own bars, every one, in local days")
    func deepSeekHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-04T16:00:00+08:00"))
        let days = ServiceStatus.calendarDays(endingAt: now, count: 90, calendar: calendar)
        let components = try #require(ServiceStatus.flashcat(
            from: try fixture("deepseek-status-page", "html"), now: now, days: days, calendar: calendar
        ))

        // Read off the page in a browser in UTC+8, the same day.
        let page = [
            "000000000000000001000101100120020000001000010000000000000300000000000010100000220000000100",
            "000000000000000001000100200020020010000000010120000000000000000000000020000100220000000100",
            "000000000000000200000000100000000000000000000000000000000000000000000020000100220000000100",
            "---------------000000000000000000000000000000000000000000000000000000000000000000000000000",
            "---------------000000020000000000000003000200000000000000000000000000000000000000000000000",
        ]
        #expect(components.map(bars) == page)
        #expect(components.map(\.uptime) == [99.92, 99.69, 99.68, 100, 99.91])
        #expect(components.allSatisfy { $0.days.allSatisfy { $0.rgb == nil } })
    }

    @Test("An open impact is the state now; a page without the data is no reading")
    func deepSeekOpenImpact() throws {
        let flight = #"""
        1:["$","$L2",null,{"initialData":{"page":{"components":[{"component_id":"a","name":"X API","section_id":null,"status":null,"order_id":1},{"component_id":"b","name":"Y API","section_id":null,"status":"maintenance","order_id":2}],"sections":[]}}}]
        2:["$","$L3",null,{"initialData":{"component_impacts":[{"component_id":"a","start_at_seconds":100,"status":"partial_outage"},{"component_id":"a","start_at_seconds":10,"end_at_seconds":20,"status":"full_outage"}],"component_uptimes":[]}}]

        """#
        let literal = String(decoding: try JSONEncoder().encode(flight), as: UTF8.self)
        let html = Data("<script>self.__next_f.push([1,\(literal)])</script>".utf8)

        let components = try #require(ServiceStatus.flashcat(from: html, now: Date(timeIntervalSince1970: 200), days: nil))
        #expect(components.map(\.state) == [.partialOutage, .maintenance])

        #expect(ServiceStatus.flashcat(from: Data("<html></html>".utf8), now: .now, days: nil) == nil)
    }

    @Test("Each feed value maps to its state")
    func states() {
        #expect(ServiceStatus.State(feedValue: "operational") == .operational)
        #expect(ServiceStatus.State(feedValue: "degraded_performance") == .degraded)
        #expect(ServiceStatus.State(feedValue: "partial_outage") == .partialOutage)
        #expect(ServiceStatus.State(feedValue: "full_outage") == .fullOutage)
        #expect(ServiceStatus.State(feedValue: "major_outage") == .fullOutage)
        #expect(ServiceStatus.State(feedValue: "under_maintenance") == .maintenance)
        #expect(ServiceStatus.State(feedValue: "degraded") == .degraded)
        #expect(ServiceStatus.State(feedValue: "maintenance") == .maintenance)
        #expect(ServiceStatus.State(feedValue: "") == .unrecognised)
    }
}
