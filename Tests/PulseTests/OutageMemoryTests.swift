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
        let first = memory.changes(in: [component("cli", .partialOutage), component("web", .operational)])
        #expect(first.worse.map(\.id) == ["cli"])
        #expect(first.recovered.isEmpty)

        #expect(memory.changes(in: [component("cli", .partialOutage)]).isEmpty)
    }

    @Test("Worse is news again; better but still down is not")
    func worseAndBetter() {
        var memory = OutageMemory()
        _ = memory.changes(in: [component("cli", .degraded)])

        #expect(memory.changes(in: [component("cli", .fullOutage)]).worse.map(\.state) == [.fullOutage])
        #expect(memory.changes(in: [component("cli", .degraded)]).isEmpty)
        // Recorded at degraded, so a second slide to full is said again.
        #expect(memory.changes(in: [component("cli", .fullOutage)]).worse.map(\.id) == ["cli"])
    }

    @Test("Back to normal only for an outage that was announced")
    func recovery() {
        var memory = OutageMemory()
        #expect(memory.changes(in: [component("cli", .operational)]).isEmpty)

        _ = memory.changes(in: [component("cli", .partialOutage)])
        #expect(memory.changes(in: [component("cli", .operational)]).recovered.map(\.id) == ["cli"])
        #expect(memory.announced.isEmpty)
        #expect(memory.changes(in: [component("cli", .operational)]).isEmpty)
    }

    @Test("Maintenance, an unknown value, or a missing component neither raise nor clear")
    func neither() {
        var memory = OutageMemory()
        #expect(memory.changes(in: [component("cli", .maintenance), component("web", .unrecognised)]).isEmpty)
        #expect(memory.announced.isEmpty)

        _ = memory.changes(in: [component("cli", .fullOutage)])
        #expect(memory.changes(in: [component("cli", .maintenance)]).isEmpty)
        #expect(memory.changes(in: [component("cli", .unrecognised)]).isEmpty)
        #expect(memory.changes(in: []).isEmpty)
        #expect(memory.announced["cli"] == .fullOutage)
    }

    @Test("The memory survives a round trip to disk")
    func persisted() throws {
        var memory = OutageMemory()
        _ = memory.changes(in: [component("cli", .degraded)])
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
}
