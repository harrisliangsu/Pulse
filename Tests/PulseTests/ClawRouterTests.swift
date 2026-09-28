import Foundation
import Testing
@testable import Pulse

/// ClawRouter's policy budget.
///
/// **The fixtures are second-hand**: written from CodexBar's ClawRouter
/// provider and its tests (MIT), not captured from a live account. They pin
/// the shape Pulse reads; they do not prove the shape is right.
@Suite("ClawRouter")
struct ClawRouterTests {
    private let context = ProfileContext(provider: .clawRouter, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The monthly budget is spent micros over limit micros, with no reset inferred")
    func budget() throws {
        let usage = ClawRouterUsageService.reading(from: try fixture("clawrouter-usage"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.clawRouter))
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.kind == .monthly)
        #expect(window.usedFraction == 6_000.0 / 25_000_000.0)
        #expect(!window.reportsLength)
        #expect(window.resetsAt == nil)
    }

    @Test("An unmetered policy has spend and no limit: no limits reported")
    func unmetered() throws {
        let usage = ClawRouterUsageService.reading(from: try fixture("clawrouter-usage-unmetered"), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A budget of zero, or spend that isn't one, is not drawn", arguments: [
        #"{"budget":{"configured":true,"limitMicros":0,"spentMicros":5}}"#,
        #"{"budget":{"configured":true,"limitMicros":100,"spentMicros":-5}}"#,
        #"{"budget":{"configured":true,"limitMicros":100}}"#,
    ])
    func noFigures(json: String) {
        let usage = ClawRouterUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply without a budget can't be read", arguments: [
        #"{"budget":{}}"#,
        #"{"usage":{}}"#,
        #"{"budget":{"configured":true,"limitMicros":1.5}}"#,
        "not json",
    ])
    func unreadable(json: String) {
        let usage = ClawRouterUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .clawRouter, credential: nil, serverAddress: nil)
        #expect(await ClawRouterUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
