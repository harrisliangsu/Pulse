import Foundation
import Testing
@testable import Pulse

/// When a status page's outage is worth a notification (`OutageMemory`), and
/// which components a notification is about at all (`StatusPage.notifiesAbout`).
@Suite("Outage alerts")
struct OutageMemoryTests {
    private func component(_ id: String, _ state: ServiceStatus.State) -> ServiceStatus.Component {
        ServiceStatus.Component(id: id, name: id, state: state)
    }

    @Test("An outage already under way is said at once — and once")
    func firstSighting() {
        var memory = OutageMemory()
        let first = memory.changes(in: [component("cli", .partialOutage), component("web", .operational)], on: .openAI)
        #expect(first.worse.map(\.id) == ["cli"])
        #expect(first.recovered.isEmpty)

        #expect(memory.changes(in: [component("cli", .partialOutage)], on: .openAI).isEmpty)
    }

    @Test("Worse is news again; better but still down is not")
    func worseAndBetter() {
        var memory = OutageMemory()
        _ = memory.changes(in: [component("cli", .degraded)], on: .openAI)

        #expect(memory.changes(in: [component("cli", .fullOutage)], on: .openAI).worse.map(\.state) == [.fullOutage])
        #expect(memory.changes(in: [component("cli", .degraded)], on: .openAI).isEmpty)
        // Recorded at degraded, so a second slide to full is said again.
        #expect(memory.changes(in: [component("cli", .fullOutage)], on: .openAI).worse.map(\.id) == ["cli"])
    }

    @Test("Back to normal only for an outage that was announced")
    func recovery() {
        var memory = OutageMemory()
        #expect(memory.changes(in: [component("cli", .operational)], on: .openAI).isEmpty)

        _ = memory.changes(in: [component("cli", .partialOutage)], on: .openAI)
        #expect(memory.changes(in: [component("cli", .operational)], on: .openAI).recovered.map(\.id) == ["cli"])
        #expect(memory.announced.isEmpty)
        #expect(memory.changes(in: [component("cli", .operational)], on: .openAI).isEmpty)
    }

    @Test("Maintenance or an unknown value neither raises nor clears")
    func neither() {
        var memory = OutageMemory()
        #expect(memory.changes(in: [component("cli", .maintenance), component("web", .unrecognised)], on: .openAI).isEmpty)
        #expect(memory.announced.isEmpty)

        _ = memory.changes(in: [component("cli", .fullOutage)], on: .openAI)
        #expect(memory.changes(in: [component("cli", .maintenance)], on: .openAI).isEmpty)
        #expect(memory.changes(in: [component("cli", .unrecognised)], on: .openAI).isEmpty)
        #expect(memory.announced["codex"]?["cli"] == .fullOutage)
    }

    @Test("A component gone from the page is forgotten without a word, so its next outage is news")
    func vanished() {
        var memory = OutageMemory()
        _ = memory.changes(in: [component("quiet", .degraded)], on: .claude)

        // A show-only-when-degraded row recovers by disappearing.
        #expect(memory.changes(in: [], on: .claude).isEmpty)
        #expect(memory.announced.isEmpty)
        #expect(memory.changes(in: [component("quiet", .degraded)], on: .claude).worse.map(\.id) == ["quiet"])
    }

    @Test("Each page is its own; one page's reading leaves another's alone")
    func pagesApart() {
        var memory = OutageMemory()
        _ = memory.changes(in: [component("cli", .degraded)], on: .openAI)
        _ = memory.changes(in: [component("api", .operational)], on: .claude)
        #expect(memory.announced["codex"]?["cli"] == .degraded)
    }

    @Test("A page nobody watches any more is forgotten, so switching back on says nothing stale")
    func unwatched() {
        var memory = OutageMemory()
        _ = memory.changes(in: [component("cli", .degraded)], on: .openAI)
        _ = memory.changes(in: [component("api", .degraded)], on: .deepSeek)

        memory.keepOnly([.deepSeek])
        #expect(memory.announced.keys.sorted() == ["deepSeek"])

        memory.keepOnly([])
        // Back on after the outage ended unwatched: no "back to normal".
        #expect(memory.changes(in: [component("cli", .operational)], on: .openAI).isEmpty)
    }

    @Test("The memory survives a round trip to disk")
    func persisted() throws {
        var memory = OutageMemory()
        _ = memory.changes(in: [component("cli", .degraded)], on: .openAI)
        let decoded = try JSONDecoder().decode(OutageMemory.self, from: JSONEncoder().encode(memory))
        #expect(decoded == memory)
    }

    @Test("Claude Code hears about Claude Code and the API, not the rest of the page")
    func notifiesAbout() {
        let claude = ["rwppv331jlwc", "0qbwn08sd68x", "k8w3r06qmzrp", "yyzkbfz2thpt", "bpp5gb3hpjcl", "0scnb50nvy53"]
            .filter { StatusPage.claude.notifiesAbout(component($0, .fullOutage)) }
        #expect(claude == ["k8w3r06qmzrp", "yyzkbfz2thpt"])
        #expect(StatusPage.openAI.notifiesAbout(component("anything in the Codex group", .fullOutage)))
    }

    @Test("The outage switch asks for permission but leaves the usage rules asleep")
    @MainActor
    func switchesApart() {
        let settings = AppSettings()
        settings.alertsOnOutage = true
        // The test runner's own defaults, not Pulse's; left as found.
        defer { settings.alertsOnOutage = false }
        #expect(settings.wantsAlerts)
        #expect(!settings.wantsUsageAlerts)
    }
}
