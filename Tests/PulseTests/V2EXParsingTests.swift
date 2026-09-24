import Foundation
import Testing
@testable import Pulse

/// V2EX's five hours are the first window Pulse carries that **has not
/// started**: it begins when the next message arrives rather than on a clock,
/// so a perfectly good reading can report an allowance, a size, and no window
/// at all. Most of these are about not drawing a countdown for a clock that is
/// not running.
@Suite("V2EX parsing")
struct V2EXParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static func quota(_ name: String) throws -> V2EXUsageService.Reply.Quota {
        let reply = try JSONDecoder().decode(V2EXUsageService.Reply.self, from: try fixture(name))
        return try #require(reply.result)
    }

    @Test("A running window reports its reset and its length")
    func activeWindowHasAClock() throws {
        let windows = V2EXUsageService.windows(from: try Self.quota("v2ex-quota"))
        let window = try #require(windows.first)

        #expect(window.kind == .fiveHour)
        #expect(abs(window.usedFraction - 0.25) < 0.0001)
        #expect(window.windowSeconds == 5 * 3_600)
        #expect(window.reportsLength)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_758_546_000))
    }

    /// **The heart of this provider.** With no window running, `period_end` is
    /// zero — and 1 January 1970 drawn as a reset time is a countdown that ran
    /// out fifty-six years ago. The allowance is still reported, because it is
    /// still true.
    @Test("A window that has not started reports no reset and no length")
    func inactiveWindowHasNoClock() throws {
        let windows = V2EXUsageService.windows(from: try Self.quota("v2ex-inactive"))
        let window = try #require(windows.first)

        #expect(window.usedFraction == 0)
        #expect(window.resetsAt == nil)
        #expect(!window.reportsLength)
        #expect(window.elapsedFraction(at: Date()) == nil)
    }

    /// A reader whose five hours are spent but whose pack is full is not out
    /// of quota, and one ring reading 100% would tell them they were.
    @Test("An extra pack is its own allowance, after the window")
    func extraPackIsItsOwnWindow() throws {
        let windows = V2EXUsageService.windows(from: try Self.quota("v2ex-quota"))

        #expect(windows.map(\.id) == ["window", "extra"])
        let pack = windows[1]
        #expect(pack.kind == .topUp)
        #expect(abs(pack.usedFraction - 34_897.0 / 12_000_000.0) < 0.000001)
        // It never expires, so there is nothing to count down to.
        #expect(pack.resetsAt == nil)
        #expect(!pack.reportsLength)
    }

    @Test("No pack bought means no second ring")
    func noPackMeansNoWindow() throws {
        let windows = V2EXUsageService.windows(from: try Self.quota("v2ex-inactive"))
        #expect(windows.count == 1)
    }

    /// Buying a pack drops the fraction by more than forty points with nothing
    /// having turned over, which is exactly the shape the reset test fires on.
    @Test("A top-up pack never counts as a window that reset")
    func topUpNeverReadsAsAReset() throws {
        let pack = try #require(V2EXUsageService.windows(from: try Self.quota("v2ex-quota")).last)
        #expect(!pack.hasTurnedOver(since: 0.9, resetsAt: nil))
    }

    /// Zero is what this route reports when there is no window, not a moment
    /// in 1970.
    @Test("A period stamp of zero is not a date")
    func zeroIsNotADate() {
        #expect(V2EXUsageService.date(0) == nil)
        #expect(V2EXUsageService.date(nil) == nil)
        #expect(V2EXUsageService.date(-1) == nil)
        #expect(V2EXUsageService.date(1_758_546_000) != nil)
    }

    /// V2EX's own remainder, not the arithmetic. Reading a missing field as
    /// zero announces an allowance as spent on the strength of silence.
    @Test("Spent comes from the reported remainder, and absence is not zero")
    func spentComesFromTheProvider() {
        #expect(V2EXUsageService.isSpent(nil) == false)
        #expect(V2EXUsageService.isSpent(1) == false)
        #expect(V2EXUsageService.isSpent(0) == true)
    }

    @Test("A total of zero is not an allowance to divide by")
    func zeroTotalProducesNoFraction() {
        #expect(V2EXUsageService.fraction(used: 5, total: 0) == nil)
        #expect(V2EXUsageService.fraction(used: 5, total: nil) == nil)
        #expect(V2EXUsageService.fraction(used: nil, total: 100) == nil)
    }
}
