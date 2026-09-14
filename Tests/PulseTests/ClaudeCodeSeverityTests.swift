import Foundation
import Testing
@testable import Pulse

/// What Claude Code's `severity` is allowed to mean.
///
/// Spent is the state the ring fills for and the figure turns red for, so the
/// line between "getting tight" and "blocked" is the app's loudest claim. A
/// `warning` severity landed on the wrong side of it and drew a full
/// exhausted-red ring at 76% used.
@Suite("Claude Code severity")
struct ClaudeCodeSeverityTests {
    private static func window(severity: String? = nil, lockedReason: Any? = nil) throws -> UsageWindow {
        var limit: [String: Any] = ["kind": "weekly_scoped", "percent": 76]
        if let severity { limit["severity"] = severity }
        if let lockedReason { limit["locked_reason"] = lockedReason }

        let usage = ClaudeCodeUsageService.parse(["limits": [limit]], for: AccountKey(.claudeCode))
        return try #require(usage.windows.first)
    }

    @Test("a warning still has room left")
    func warningIsNotSpent() throws {
        #expect(try Self.window(severity: "warning").isExhausted == false)
        #expect(try Self.window(severity: "warn").isExhausted == false)
    }

    @Test("plainly fine severities are not spent")
    func normalIsNotSpent() throws {
        #expect(try Self.window(severity: "normal").isExhausted == false)
        #expect(try Self.window().isExhausted == false)
    }

    @Test("anything unrecognised still errs towards blocked")
    func unknownIsSpent() throws {
        #expect(try Self.window(severity: "exceeded").isExhausted)
        #expect(try Self.window(severity: "something_new").isExhausted)
    }

    @Test("a locked reason is unambiguous")
    func lockedIsSpent() throws {
        #expect(try Self.window(severity: "normal", lockedReason: "weekly_limit").isExhausted)
        #expect(try Self.window(severity: "normal", lockedReason: NSNull()).isExhausted == false)
    }
}
