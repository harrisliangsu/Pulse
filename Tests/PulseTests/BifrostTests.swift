import Foundation
import Testing
@testable import Pulse

/// Bifrost's virtual-key budgets.
///
/// **The fixture is second-hand**: written from CodexBar's Bifrost plugin
/// (MIT), not captured from a live gateway. It pins the shape Pulse reads; it
/// does not prove the shape is right.
@Suite("Bifrost")
struct BifrostTests {
    private let context = ProfileContext(provider: .bifrost, credential: "vk", serverAddress: "https://gw.example.com")
    private let now = ProfileHTTP.date("2026-06-10T12:30:00Z")!

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Budgets are read as spent out of allowed, shortest period first")
    func budgets() throws {
        let usage = BifrostUsageService.reading(from: try fixture("bifrost-quota"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.windows.map(\.kind) == [.other(seconds: 3_600), .weekly, .monthly])
        // 1 of 5 + a 5 raise still in force; 10 of 20; 25 of 100.
        #expect(usage.windows.map(\.usedFraction) == [0.1, 0.5, 0.25])
        #expect(usage.windows.map(\.scope) == [nil, "gpt-4o", nil])
        // A month is a name and a sort key, not a length.
        #expect(!usage.windows[2].reportsLength)
    }

    @Test("A fixed period's next reset follows the last; a calendar one's is not guessed")
    func resets() throws {
        let usage = BifrostUsageService.reading(from: try fixture("bifrost-quota"), context: context, now: now)
        #expect(usage.windows[0].resetsAt == ProfileHTTP.date("2026-06-10T13:00:00Z"))
        #expect(usage.windows[1].resetsAt == nil)
        #expect(usage.windows[2].resetsAt == nil)
        // Already past: the gateway hasn't moved it on, and Pulse doesn't either.
        #expect(BifrostUsageService.nextReset(after: ProfileHTTP.date("2026-06-10T10:00:00Z"), period: 3_600, now: now) == nil)
    }

    @Test("A zero budget and the rate limits are left off")
    func leftOff() throws {
        let usage = BifrostUsageService.reading(from: try fixture("bifrost-quota"), context: context, now: now)
        #expect(!usage.windows.contains { $0.id.contains("b-empty") })
        #expect(usage.windows.count == 3)
    }

    @Test("Durations read as Bifrost writes them", arguments: [
        ("5h", UsageWindow.Kind.fiveHour, true), ("24h", .daily, true), ("1d", .daily, true),
        ("7d", .weekly, true), ("2w", .other(seconds: 14 * 86_400), true),
        ("30m", .spend, false), ("1Q", .spend, false), ("nonsense", .spend, false),
    ])
    func durations(raw: String, kind: UsageWindow.Kind, reportsLength: Bool) {
        let period = BifrostUsageService.Period.parse(raw)
        #expect(period.kind == kind)
        #expect(period.reportsLength == reportsLength)
    }

    @Test("An inactive key with nothing on it is refused")
    func inactive() {
        let usage = BifrostUsageService.reading(from: Data(#"{"is_active":false}"#.utf8), context: context, now: now)
        #expect(usage.state == .unavailable(.apiKeyRefused))
    }

    @Test("A reply that isn't an object can't be read", arguments: ["not json", "[]", #"{"budgets":{}}"#])
    func unreadable(json: String) {
        let usage = BifrostUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("Negative or missing figures are left off, and nothing left is no limits")
    func noFigures() {
        let json = #"{"budgets":[{"id":"a","max_limit":10,"current_usage":-1},{"id":"b","current_usage":1},{"max_limit":5,"current_usage":1}]}"#
        let usage = BifrostUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No key, no address, or an address that may not carry one: nothing is sent")
    func credentials() async {
        let noKey = ProfileContext(provider: .bifrost, credential: nil, serverAddress: "https://gw.example.com")
        #expect(await BifrostUsageService.fetch(noKey).state == .unavailable(.apiKeyMissing))
        let noAddress = ProfileContext(provider: .bifrost, credential: "vk", serverAddress: " ")
        #expect(await BifrostUsageService.fetch(noAddress).state == .unavailable(.serverAddressMissing))
        let plainHTTP = ProfileContext(provider: .bifrost, credential: "vk", serverAddress: "http://gw.example.com")
        #expect(await BifrostUsageService.fetch(plainHTTP).state == .unavailable(.serverAddressRefused))
    }
}
