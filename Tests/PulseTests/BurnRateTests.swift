import Foundation
import Testing
@testable import Pulse

/// The exhaustion line and the Codex windows that feed it.
@Suite("Burn rate")
struct BurnRateTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(
        kind: UsageWindow.Kind = .weekly,
        scope: String? = nil,
        used: Double,
        seconds: Int = 604_800,
        resetsAt: Date?,
        reportsLength: Bool = true
    ) -> UsageWindow {
        UsageWindow(
            id: "window",
            kind: kind,
            scope: scope,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength
        )
    }

    /// Half a week already gone, unless a test says otherwise.
    private static func weekly(used: Double, elapsed: Double = 0.5) -> UsageWindow {
        Self.window(
            used: used,
            resetsAt: Self.now.addingTimeInterval(604_800 * (1 - elapsed))
        )
    }

    private static func pace(remaining: TimeInterval, length: Double = 604_800, elapsed: Double = 0.5) -> Double {
        let elapsedSeconds = length * elapsed
        return elapsedSeconds / (remaining + elapsedSeconds)
    }

    @Test("A time is returned whenever the pace runs out before the reset")
    func readingKeepsTheTimePastSixHours() {
        let far = BurnRate.reading(for: Self.weekly(used: Self.pace(remaining: 37 * 3600)), now: Self.now)
        #expect(far?.exhaustsBeforeReset == true)
        let seconds = far?.timeToExhaustion ?? 0
        #expect(abs(seconds - 37 * 3600) < 60)

        let close = BurnRate.reading(for: Self.weekly(used: Self.pace(remaining: 4 * 3600)), now: Self.now)
        #expect(close?.exhaustsBeforeReset == true)
        #expect(abs((close?.timeToExhaustion ?? 0) - 4 * 3600) < 60)
    }

    @Test("A window that lasts, or that has barely opened, says nothing about a time")
    func readingRefusesWhatItCannotDivide() {
        let lasts = BurnRate.reading(for: Self.weekly(used: 0.2), now: Self.now)
        #expect(lasts?.exhaustsBeforeReset == false)
        #expect(lasts?.timeToExhaustion == nil)

        let fresh = Self.window(used: 0.9, resetsAt: Self.now.addingTimeInterval(604_800 * 0.99))
        #expect(BurnRate.reading(for: fresh, now: Self.now) == nil)

        let unstated = Self.window(used: 0.8, resetsAt: Self.now.addingTimeInterval(302_400), reportsLength: false)
        #expect(BurnRate.reading(for: unstated, now: Self.now) == nil)

        let noReset = Self.window(used: 0.8, resetsAt: nil)
        #expect(BurnRate.reading(for: noReset, now: Self.now) == nil)
    }

    @Test("The card states a time only inside the horizon, then the reset sentence, then the hint")
    func cardLineFollowsTheSwitches() {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        let week = Self.weekly(used: Self.pace(remaining: 37 * 3600))
        let reading = BurnRate.reading(for: week, now: Self.now)!
        let horizon = 6.0 * 3600

        let countdown = BurnRate.cardLine(
            for: week, reading: reading, horizon: 48 * 3600, softHint: true, beforeReset: true
        )
        #expect(countdown?.tone == .countdown)
        #expect(countdown?.text == "Weekly · may run out in 1d 13h")

        let tied = BurnRate.cardLine(
            for: week, reading: reading, horizon: horizon, softHint: true, beforeReset: true
        )
        #expect(tied?.tone == .beforeReset)
        #expect(tied?.text == "At the current pace, about 1d 13h before the next reset.")

        let hint = BurnRate.cardLine(
            for: week, reading: reading, horizon: horizon, softHint: true, beforeReset: false
        )
        #expect(hint?.tone == .hint)
        #expect(hint?.text == "Weekly · may run out before the reset")

        #expect(BurnRate.cardLine(
            for: week, reading: reading, horizon: horizon, softHint: false, beforeReset: false
        ) == nil)

        let close = Self.weekly(used: Self.pace(remaining: 4 * 3600))
        let closeReading = BurnRate.reading(for: close, now: Self.now)!
        let soon = BurnRate.cardLine(
            for: close, reading: closeReading, horizon: horizon, softHint: false, beforeReset: false
        )
        #expect(soon?.tone == .countdown)
        #expect(soon?.text == "Weekly · may run out in about 4 hours")

        let steady = Self.weekly(used: 0.2)
        let steadyReading = BurnRate.reading(for: steady, now: Self.now)!
        #expect(BurnRate.cardLine(
            for: steady, reading: steadyReading, horizon: horizon, softHint: true, beforeReset: true
        )?.tone == .lasts)

        let fiveHour = Self.window(
            kind: .fiveHour,
            scope: "GPT",
            used: 0.7,
            seconds: 18_000,
            resetsAt: Self.now.addingTimeInterval(4 * 3600)
        )
        let scoped = BurnRate.reading(for: fiveHour, now: Self.now)!
        let named = BurnRate.cardLine(
            for: fiveHour, reading: scoped, horizon: horizon, softHint: true, beforeReset: true
        )
        #expect(named?.text.hasPrefix("5-hour · GPT · ") == true)

        LocalizationSource.use(.chineseSimplified)
        #expect(BurnRate.approximate(37 * 3600) == "约 1天13小时")
        #expect(BurnRate.span(37 * 3600) == "1天13小时")
        let chinese = BurnRate.cardLine(
            for: week, reading: reading, horizon: 48 * 3600, softHint: true, beforeReset: true
        )
        #expect(chinese?.text == "每周 · 约 1天13小时后用尽")
    }

    @Test("Codex 5-hour and weekly windows forecast when the reply states a length and a reset")
    func codexWindowsForecast() {
        let http: [String: Any] = [
            "plan_type": "plus",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 70,
                    "limit_window_seconds": "18000",
                    "reset_at": (Self.now.timeIntervalSince1970 + 4 * 3600) * 1000,
                ],
                "secondary_window": [
                    "used_percent": 40,
                    "limit_window_seconds": 604_800,
                    "reset_after_seconds": 3 * 86_400,
                ],
            ] as [String: Any],
        ]
        let parsed = CodexUsageService.parseUsageResponse(http, for: AccountKey(.codex), now: Self.now)
        #expect(parsed.windows.count == 2)
        let fiveHour = parsed.windows.first { $0.kind == .fiveHour }
        let weekly = parsed.windows.first { $0.kind == .weekly }
        #expect(fiveHour?.reportsLength == true)
        #expect(fiveHour?.windowSeconds == 18_000)
        #expect(fiveHour?.resetsAt == Self.now.addingTimeInterval(4 * 3600))
        let fiveReading = fiveHour.flatMap { BurnRate.reading(for: $0, now: Self.now) }
        #expect(fiveReading?.exhaustsBeforeReset == true)
        #expect((fiveReading?.timeToExhaustion ?? 0) < 6 * 3600)

        #expect(weekly?.reportsLength == true)
        #expect(weekly?.resetsAt == Self.now.addingTimeInterval(3 * 86_400))
        #expect(BurnRate.reading(for: weekly!, now: Self.now) != nil)

        let missing: [String: Any] = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 70,
                    "reset_at": Self.now.timeIntervalSince1970 + 4 * 3600,
                ],
            ],
        ]
        let quiet = CodexUsageService.parseUsageResponse(missing, for: AccountKey(.codex), now: Self.now)
        #expect(quiet.windows.first?.reportsLength == false)
        #expect(quiet.windows.first.flatMap { BurnRate.reading(for: $0, now: Self.now) } == nil)

        let flagged: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": true, "limit_window_seconds": 18_000],
            ],
        ]
        #expect(CodexUsageService.parseUsageResponse(flagged, for: AccountKey(.codex), now: Self.now).windows.isEmpty)
    }

    @Test("The app-server reply uses the same length and reset rules")
    func codexAppServerForecast() {
        let server: [String: Any] = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 70,
                    "windowDurationMins": "300",
                    "resetAfterSeconds": 4 * 3600,
                ] as [String: Any],
            ],
        ]
        let parsed = CodexUsageService.parseAppServerResponse(server, now: Self.now)
        let window = parsed.windows.first
        #expect(window?.kind == .fiveHour)
        #expect(window?.reportsLength == true)
        #expect(window?.resetsAt == Self.now.addingTimeInterval(4 * 3600))
        #expect(window.flatMap { BurnRate.reading(for: $0, now: Self.now) }?.exhaustsBeforeReset == true)
    }
}
