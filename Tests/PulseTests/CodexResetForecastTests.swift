import Foundation
import Testing
@testable import Pulse

@Suite("Codex Resets status")
struct CodexResetForecastTests {
    private let scheduledFor = "2026-09-24T18:30:00Z"
    private let expiresAt = "2026-09-23T12:00:00Z"

    @Test("An explicit scheduled_for is the reset time")
    func scheduledWins() throws {
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": {
              "id": "post-1",
              "status": "scheduled",
              "reset_type": "regular",
              "announced_at": "2026-09-23T08:00:00Z",
              "scheduled_for": "\(scheduledFor)",
              "text": "Resetting tomorrow.",
              "source": { "type": "x_post", "author": "thsottiaux", "url": "https://x.com/thsottiaux/status/1" }
            },
            "active_watch": {
              "level": "strong",
              "reset_chance_percent": 80,
              "forecast_window": "within 24h",
              "observed_at": "2026-09-23T08:00:00Z",
              "expires_at": "\(expiresAt)",
              "text": "watch",
              "source": { "type": "observed" }
            },
            "stats": { "total": 1, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))

        let when = try #require(CodexResetDates.parse(scheduledFor))
        #expect(status.card == .scheduled(when))
        #expect(status.explicitReset == when)
        #expect(status.explicitReset != CodexResetDates.parse(expiresAt))
    }

    @Test("A watch is a forecast, and expires_at is not the reset")
    func watchIsNotATime() throws {
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": {
              "id": "post-2",
              "status": "scheduled",
              "reset_type": "regular",
              "announced_at": "2026-09-23T08:00:00Z",
              "scheduled_for": null,
              "text": "Soon.",
              "source": { "type": "observed" }
            },
            "active_watch": {
              "level": "elevated",
              "reset_chance_percent": 42,
              "forecast_window": "later today",
              "observed_at": "2026-09-23T08:00:00Z",
              "expires_at": "\(expiresAt)",
              "text": "watch",
              "source": { "type": "observed" }
            },
            "stats": { "total": 0, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))

        #expect(status.explicitReset == nil)
        guard case .watch(let watch) = status.card else {
            Issue.record("expected a watch")
            return
        }
        #expect(watch.level == "elevated")
        #expect(watch.chancePercent == 42)
        #expect(watch.forecastWindow == "later today")
    }

    @Test("Neither a time nor a watch is an empty card")
    func empty() throws {
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 0, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        #expect(status.card == .empty)
        #expect(status.explicitReset == nil)
    }

    @Test("A body that is not a status document is a failure, not an empty card")
    func malformed() {
        #expect(CodexResetStatus.parse(Data("[]".utf8)) == nil)
        #expect(CodexResetStatus.parse(Data(#"{"data":[]}"#.utf8)) == nil)
    }

    @Test("304 keeps the caller on its cache; 429 names a wait; a bad 200 does not")
    func http() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let empty = CodexResetReply.interpret(statusCode: 304, headers: ["ETag": "abc"], body: Data(), now: now)
        #expect(empty.payload == .notModified)
        #expect(empty.etag == "abc")

        let limited = CodexResetReply.interpret(
            statusCode: 429,
            headers: ["Retry-After": "90"],
            body: Data(#"{"status":429}"#.utf8),
            now: now
        )
        #expect(limited.payload == .failed)
        #expect(limited.retryAfter == 90)

        let garbage = CodexResetReply.interpret(statusCode: 200, headers: [:], body: Data("nope".utf8), now: now)
        #expect(garbage.payload == .failed)

        #expect(CodexResetSchedule.delay(maxAge: 30, retryAfter: nil, failed: false) == CodexResetSchedule.floor)
        #expect(CodexResetSchedule.delay(maxAge: nil, retryAfter: 90, failed: true) == 90)
        #expect(CodexResetSchedule.delay(maxAge: nil, retryAfter: nil, failed: true) == CodexResetSchedule.default)
    }

    @Test("Missing reset credits are unknown, not zero")
    func credits() throws {
        #expect(CodexAccountUsageService.credits(from: [:]) == nil)
        let limits = try #require(JSONSerialization.jsonObject(with: Data("""
        {"rateLimitResetCredits":{"availableCount":2,"credits":[
          {"title":"Later","status":"available","expiresAt":1800000000},
          {"title":"Soon","status":"available","expiresAt":1700000000},
          {"title":"Used","status":"consumed","expiresAt":1600000000}
        ]}}
        """.utf8)) as? [String: Any])
        let summary = CodexAccountUsageService.credits(from: limits)
        #expect(summary?.available == 2)
        #expect(summary?.nextExpiresAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(summary?.showsOnCard == true)
        let empty: [String: Any] = ["rateLimitResetCredits": ["availableCount": 0, "credits": [Any]()] as [String: Any]]
        let none = CodexAccountUsageService.credits(from: empty)
        #expect(none?.available == 0)
        #expect(none?.showsOnCard == false)
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }
}

@Suite("Advance reset reminders")
struct AdvanceResetReminderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let lead12: TimeInterval = 12 * 3600
    private let lead48: TimeInterval = 48 * 3600

    @Test("Only an explicit scheduled_for schedules a predicted reminder")
    func predictedRequiresATime() throws {
        let when = now.addingTimeInterval(36 * 3600)
        let timed = CodexResetStatus(
            scheduled: .init(id: "post-9", scheduledFor: when),
            watch: .init(level: "strong", chancePercent: 90, forecastWindow: "soon")
        )
        let reminder = try #require(AdvanceReminderPlanner.predicted(status: timed, lead: lead12, now: now))
        #expect(reminder.identifier == "pulse.advance.predicted|post-9|\(Int(when.timeIntervalSince1970))")
        #expect(reminder.fireAt == when.addingTimeInterval(-lead12))

        let watchOnly = CodexResetStatus(
            scheduled: .init(id: "post-9", scheduledFor: nil),
            watch: .init(level: "elevated", chancePercent: 40, forecastWindow: "this week")
        )
        #expect(AdvanceReminderPlanner.predicted(status: watchOnly, lead: lead12, now: now) == nil)
        #expect(AdvanceReminderPlanner.predicted(
            status: CodexResetStatus(scheduled: nil, watch: nil),
            lead: lead12,
            now: now
        ) == nil)
        #expect(AdvanceReminderPlanner.predicted(
            status: CodexResetStatus(scheduled: .init(id: "old", scheduledFor: now.addingTimeInterval(-60)), watch: nil),
            lead: lead12,
            now: now
        ) == nil)
    }

    @Test("Inside the lead, the predicted reminder is due now and is not repeated")
    func predictedDedupes() {
        let when = now.addingTimeInterval(6 * 3600)
        let status = CodexResetStatus(scheduled: .init(id: "post-3", scheduledFor: when), watch: nil)
        let reminder = AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: now)
        #expect(reminder?.fireAt == nil)

        var book = AdvanceReminderBook()
        let first = book.reconcile(desired: reminder.map { [$0] } ?? [], enabled: true, now: now)
        #expect(first.schedule.count == 1)
        let second = book.reconcile(desired: reminder.map { [$0] } ?? [], enabled: true, now: now)
        #expect(second.schedule.isEmpty)
        #expect(second.cancel.isEmpty)
    }

    @Test("A window shorter than the lead is skipped; a longer one is kept")
    func leadSkipsShortWindows() {
        let soon = now.addingTimeInterval(3 * 3600)
        let week = now.addingTimeInterval(5 * 24 * 3600)
        let windows = [
            AdvanceReminderPlanner.Window(
                accountID: "codex", accountLabel: "Codex", windowID: "five",
                windowName: "5-hour limit", resetsAt: soon, length: 5 * 3600
            ),
            AdvanceReminderPlanner.Window(
                accountID: "codex", accountLabel: "Codex", windowID: "week",
                windowName: "Weekly limit", resetsAt: week, length: 7 * 24 * 3600
            ),
            AdvanceReminderPlanner.Window(
                accountID: "kimi", accountLabel: "Kimi", windowID: "rolling",
                windowName: "Weekly limit", resetsAt: week, length: nil
            )
        ]
        let due = AdvanceReminderPlanner.regular(windows: windows, lead: lead12, now: now)
        #expect(due.map(\.identifier) == [
            "pulse.advance.regular|codex|week|\(Int(week.timeIntervalSince1970))"
        ])
        #expect(due.first?.fireAt == week.addingTimeInterval(-lead12))

        let tooSoonForTwoDays = AdvanceReminderPlanner.regular(windows: windows, lead: lead48, now: now)
        #expect(tooSoonForTwoDays.map(\.identifier) == due.map(\.identifier))
    }

    @Test("Turning reminders off cancels a pending one without marking it delivered")
    func disablingCancels() throws {
        let when = now.addingTimeInterval(36 * 3600)
        let status = CodexResetStatus(scheduled: .init(id: "post-4", scheduledFor: when), watch: nil)
        let reminder = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: now))
        var book = AdvanceReminderBook()
        let scheduled = book.reconcile(desired: [reminder], enabled: true, now: now)
        #expect(scheduled.schedule.count == 1)
        #expect(book.memory.pending[reminder.identifier] != nil)

        let off = book.reconcile(desired: [], enabled: false, now: now)
        #expect(off.cancel == [reminder.identifier])
        #expect(book.memory.pending.isEmpty)
        #expect(!book.memory.delivered.contains(reminder.identifier))

        let again = book.reconcile(desired: [reminder], enabled: true, now: now)
        #expect(again.schedule.map(\.identifier) == [reminder.identifier])
    }

    @Test("A changed lead moves a pending reminder; once its fire time has passed it is not posted again")
    func replacesPendingOnly() throws {
        let when = now.addingTimeInterval(60 * 3600)
        let status = CodexResetStatus(scheduled: .init(id: "post-5", scheduledFor: when), watch: nil)
        let early = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead48, now: now))
        let later = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: now))
        #expect(early.identifier == later.identifier)
        #expect(early.fireAt == when.addingTimeInterval(-lead48))
        #expect(later.fireAt == when.addingTimeInterval(-lead12))

        var book = AdvanceReminderBook()
        _ = book.reconcile(desired: [early], enabled: true, now: now)
        let moved = book.reconcile(desired: [later], enabled: true, now: now)
        #expect(moved.cancel == [early.identifier])
        #expect(moved.schedule.map(\.identifier) == [later.identifier])
        #expect(book.memory.pending[later.identifier] == later.fireAt)

        let afterFire = try #require(later.fireAt).addingTimeInterval(60)
        let due = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: afterFire))
        #expect(due.fireAt == nil)
        let passed = book.reconcile(desired: [due], enabled: true, now: afterFire)
        #expect(passed.schedule.isEmpty)
        #expect(book.memory.delivered.contains(due.identifier))
    }
}
