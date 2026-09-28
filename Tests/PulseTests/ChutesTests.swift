import Foundation
import Testing
@testable import Pulse

/// Chutes' subscription usage.
///
/// **The fixture is second-hand**: written from CodexBar's Chutes plugin and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Chutes")
struct ChutesTests {
    private let context = ProfileContext(provider: .chutes, credential: "cpk_key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The rolling window and the month are read as used out of the limit")
    func windows() throws {
        let usage = ChutesUsageService.reading(from: try fixture("chutes-subscription-usage"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.chutes))
        #expect(usage.plan == "Pro")
        #expect(usage.windows.map(\.kind) == [.other(seconds: 4 * 3_600), .monthly])
        #expect(usage.windows.map(\.usedFraction) == [0.4, 0.25])
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-06-13T18:00:00Z"))
        #expect(usage.windows[0].reportsLength)
        #expect(usage.windows[1].resetsAt == ProfileHTTP.date("2026-07-01T00:00:00Z"))
        #expect(!usage.windows[1].reportsLength)
    }

    @Test("A rolling window with no stated length is left off, not given four hours")
    func unstatedLength() {
        let json = #"{"rolling_window":{"requests":40,"limit":100},"four_hour":{"used":10,"limit":100}}"#
        let usage = ChutesUsageService.reading(from: Data(json.utf8), context: context)
        // Only the one whose name states its length.
        #expect(usage.windows.map(\.usedFraction) == [0.1])
        #expect(usage.windows.map(\.kind) == [.other(seconds: 4 * 3_600)])
    }

    @Test("A remainder with a limit is a figure; a percentage under 1 is not read as a fraction")
    func remainderAndPercent() {
        let json = #"{"data":{"monthly":{"remaining":600,"limit":1000},"fourHour":{"percent_used":0.5}}}"#
        let usage = ChutesUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.windows.map(\.usedFraction) == [0.005, 0.4])
    }

    @Test("No subscription is an answer, not an outage")
    func noPlan() {
        let json = #"{"subscription":{"active":false,"status":"free"}}"#
        let usage = ChutesUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noPlan))
    }

    @Test("A reply that isn't an object can't be read", arguments: ["not json", "[1]"])
    func unreadable(json: String) {
        let usage = ChutesUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("Zero limits and negative counts are left off, and nothing left is no limits")
    func noFigures() {
        let json = #"{"monthly":{"used":5,"limit":0},"rolling_4h":{"used":-2,"limit":100}}"#
        let usage = ChutesUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .chutes, credential: nil, serverAddress: nil)
        #expect(await ChutesUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
