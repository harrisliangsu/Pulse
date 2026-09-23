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

    @Test("A banked latest announcement is history, not a prediction")
    func bankedLatest() throws {
        let announced = "2026-09-22T18:23:37.000Z"
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "2102463847714247142",
              "reset_type": "banked",
              "announced_at": "\(announced)",
              "scheduled_for": "2026-09-25T00:00:00Z",
              "text": "We are loading a banked reset.",
              "source": { "type": "x_post", "author": "thsottiaux", "url": "https://x.com/thsottiaux/status/1" }
            },
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 54, "last_reset_at": "\(announced)", "days_since_last": 0.8, "avg_interval_days": 7 }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T12:42:24.788Z" }
        }
        """)))

        let when = try #require(CodexResetDates.parse(announced))
        let latest = try #require(status.latest)
        #expect(latest.id == "2102463847714247142")
        #expect(latest.resetType == "banked")
        #expect(latest.announcedAt == when)
        #expect(latest.text == "We are loading a banked reset.")
        #expect(status.card == .empty)
        #expect(status.explicitReset == nil)
        #expect(status.explicitReset != when)
    }

    @Test("A regular latest announcement keeps its type, and a bad instant is dropped")
    func regularLatestAndABrokenOne() throws {
        let announced = "2026-09-20T01:00:00Z"
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": " post-regular ",
              "reset_type": " regular ",
              "announced_at": "\(announced)",
              "text": "Reset.",
              "source": { "type": "x_post" }
            },
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 1, "last_reset_at": "\(announced)", "days_since_last": 1, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        #expect(status.latest?.id == "post-regular")
        #expect(status.latest?.resetType == "regular")
        #expect(status.latest?.text == "Reset.")
        #expect(status.card == .empty)

        let broken = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": { "id": "nope", "reset_type": "banked", "announced_at": "not-a-date" },
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 0, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        #expect(broken.latest == nil)
        #expect(broken.card == .empty)
        #expect(broken.explicitReset == nil)
    }

    @Test("An unknown type is kept, and an empty prediction still yields when a time is scheduled")
    func unknownTypeAndScheduledStillWins() throws {
        let announced = "2026-09-22T18:23:37.000Z"
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "later-kind",
              "reset_type": "surprise",
              "announced_at": "\(announced)"
            },
            "scheduled_reset": {
              "id": "post-1",
              "status": "scheduled",
              "reset_type": "regular",
              "announced_at": "2026-09-23T08:00:00Z",
              "scheduled_for": "\(scheduledFor)",
              "text": "Resetting tomorrow.",
              "source": { "type": "x_post" }
            },
            "active_watch": null,
            "stats": { "total": 1, "last_reset_at": "\(announced)", "days_since_last": 1, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        let when = try #require(CodexResetDates.parse(scheduledFor))
        #expect(status.latest?.resetType == "surprise")
        #expect(status.latest?.text == nil)
        #expect(status.card == .scheduled(when))
        #expect(status.explicitReset == when)
        #expect(status.explicitReset != status.latest?.announcedAt)
    }

    @Test("The latest row is a local clock and a relative interval")
    func presentation() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let local = CodexResetPresentation.absolute(
            announcedAt: announced,
            locale: Locale(identifier: "zh_CN"),
            calendar: shanghai
        )
        #expect(local.contains("2:23"))
        #expect(local.contains("月"))
        #expect(!local.contains("22"))
        #expect(!local.contains("18"))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let utcText = CodexResetPresentation.absolute(
            announcedAt: announced,
            locale: Locale(identifier: "zh_CN"),
            calendar: utc
        )
        #expect(utcText.contains("22"))
        #expect(utcText.contains("18") || utcText.contains("6:23"))

        let relative = CodexResetPresentation.relative(
            announcedAt: announced,
            now: announced.addingTimeInterval(18 * 3600),
            locale: Locale(identifier: "en_US")
        )
        #expect(relative == "18 hours ago")

        #expect(CodexResetPresentation.detail(resetType: "", absolute: "STAMP") == "STAMP")
        #expect(CodexResetPresentation.detail(resetType: "surprise", absolute: "STAMP").contains("surprise"))
        #expect(CodexResetPresentation.detail(resetType: "surprise", absolute: "STAMP").contains("STAMP"))
        #expect(CodexResetPresentation.typeLabel(resetType: "banked") != CodexResetPresentation.typeLabel(resetType: "regular"))
        #expect(CodexResetPresentation.help(resetType: "banked", announcement: nil)?.isEmpty == false)
        #expect(CodexResetPresentation.help(resetType: "regular", announcement: nil) == nil)
        #expect(CodexResetPresentation.help(resetType: "surprise", announcement: nil) == nil)
    }

    @Test("The type tooltip follows the reset type and does not invent copy")
    func typeTooltip() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        func row(type: String, text: String?) -> CodexResetCardLines.Latest? {
            CodexResetCardLines.make(CodexResetStatus(
                scheduled: nil,
                watch: nil,
                latest: .init(id: "id", resetType: type, announcedAt: announced, text: text)
            )).latest
        }

        let bankedHelp = try #require(CodexResetPresentation.help(resetType: "banked", announcement: nil))
        let banked = try #require(row(type: "banked", text: "We are loading a banked reset."))
        #expect(banked.help == bankedHelp)
        #expect(banked.help != "We are loading a banked reset.")
        #expect(banked.typeLabel == CodexResetPresentation.typeLabel(resetType: "banked"))
        #expect(banked.detail.contains(banked.typeLabel))
        #expect(banked.detail.contains(banked.absolute))

        #expect(row(type: "regular", text: "  Reset.  ")?.help == "Reset.")
        #expect(row(type: "regular", text: nil)?.help == nil)
        #expect(row(type: "regular", text: " \n ")?.help == nil)
        #expect(row(type: "regular", text: "Reset.")?.typeLabel == CodexResetPresentation.typeLabel(resetType: "regular"))

        let other = try #require(row(type: "surprise", text: "Something new."))
        #expect(other.help == "Something new.")
        #expect(other.typeLabel == "surprise")
        #expect(row(type: "surprise", text: nil)?.help == nil)

        let blank = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "blank",
              "reset_type": "regular",
              "announced_at": "2026-09-22T18:23:37.000Z",
              "text": "  "
            },
            "scheduled_reset": null,
            "active_watch": null
          }
        }
        """)))
        #expect(blank.latest?.text == nil)
        #expect(CodexResetCardLines.make(blank).latest?.help == nil)

        let withBody = CodexResetStatus(
            scheduled: nil, watch: nil,
            latest: .init(id: "id", resetType: "regular", announcedAt: announced, text: "Reset.")
        )
        let withoutBody = CodexResetStatus(
            scheduled: nil, watch: nil,
            latest: .init(id: "id", resetType: "regular", announcedAt: announced, text: nil)
        )
        #expect(CodexResetCardLines.identity(withBody) != CodexResetCardLines.identity(withoutBody))
    }

    @Test("A cached status from before latest_reset still decodes")
    func decodesWithoutLatest() throws {
        let data = Data(#"{"scheduled":null,"watch":null}"#.utf8)
        let status = try JSONDecoder().decode(CodexResetStatus.self, from: data)
        #expect(status.latest == nil)
        #expect(status.card == .empty)

        let bareLatest = Data(#"{"id":"post","resetType":"regular","announcedAt":700000000}"#.utf8)
        let bareAnnouncement = try JSONDecoder().decode(CodexResetStatus.Latest.self, from: bareLatest)
        #expect(bareAnnouncement.text == nil)
        #expect(bareAnnouncement.resetType == "regular")

        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        let round = CodexResetStatus(
            scheduled: nil,
            watch: .init(level: "elevated", chancePercent: nil, forecastWindow: "soon"),
            latest: .init(id: "post", resetType: "banked", announcedAt: announced)
        )
        let encoded = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(CodexResetStatus.self, from: encoded)
        #expect(decoded == round)
        #expect(decoded.card == .watch(.init(level: "elevated", chancePercent: nil, forecastWindow: "soon")))
    }

    @Test("Last reset is an extra row beside an empty prediction")
    func lastResetBesideEmptyPrediction() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        let status = CodexResetStatus(
            scheduled: nil,
            watch: nil,
            latest: .init(id: "2102463847714247142", resetType: "banked", announcedAt: announced)
        )
        #expect(status.card == .empty)
        #expect(status.explicitReset == nil)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let lines = CodexResetCardLines.make(
            status,
            now: announced.addingTimeInterval(18 * 3600),
            locale: Locale(identifier: "en_US"),
            calendar: utc
        )
        let latest = try #require(lines.latest)
        #expect(latest.relative == "18 hours ago")
        #expect(latest.help?.isEmpty == false)
        #expect(latest.detail.isEmpty == false)
        #expect(latest.spoken.contains(latest.relative))
        #expect(CodexResetCardLines.identity(status) != CodexResetCardLines.identity(nil))
        #expect(CodexResetCardLines.identity(status).contains("2102463847714247142"))

        #expect(CodexResetCardLines.make(nil).latest == nil)
        let empty = CodexResetStatus(scheduled: nil, watch: nil)
        #expect(empty.card == .empty)
        #expect(CodexResetCardLines.make(empty).latest == nil)
        #expect(CodexResetCardLines.identity(empty).isEmpty)
    }

    @Test("The on-disk cache delivers latest to the card, including a file from before the field existed")
    @MainActor
    func cacheDeliversLatest() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        let status = CodexResetStatus(
            scheduled: nil,
            watch: nil,
            latest: .init(id: "2102463847714247142", resetType: "banked", announcedAt: announced)
        )
        let record = CodexResetDisk(status: status, etag: "abc", fetchedAt: Date(), maxAge: 600)
        let data = try #require(CodexResetDisk.encode(record))
        let decoded = try #require(CodexResetDisk.decode(data))
        #expect(decoded.status == status)
        #expect(decoded.status.card == .empty)
        #expect(decoded.status.latest?.resetType == "banked")

        let url = FileManager.default.temporaryDirectory
            .appending(path: "pulse-codex-resets-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        var delivered: CodexResetStatus?
        let monitor = CodexResetMonitor(settings: AppSettings(), file: url) { delivered = $0 }
        let loaded = monitor.restoreCache()
        #expect(loaded?.latest == status.latest)
        #expect(loaded?.card == .empty)
        #expect(loaded?.explicitReset == nil)
        #expect(delivered == loaded)

        let stale = Data(#"{"status":{"scheduled":null,"watch":null},"etag":"old","fetchedAt":700000000,"maxAge":600}"#.utf8)
        let legacy = try #require(CodexResetDisk.decode(stale))
        #expect(legacy.status.latest == nil)
        #expect(legacy.status.card == .empty)
        #expect(legacy.etag == "old")
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

        let ahead = now.addingTimeInterval(6 * 3600)
        let onlyLatest = CodexResetStatus(
            scheduled: nil,
            watch: nil,
            latest: .init(id: "banked-1", resetType: "banked", announcedAt: ahead)
        )
        #expect(onlyLatest.explicitReset == nil)
        #expect(AdvanceReminderPlanner.predicted(status: onlyLatest, lead: lead12, now: now) == nil)

        let whenLatest = now.addingTimeInterval(36 * 3600)
        let both = CodexResetStatus(
            scheduled: .init(id: "post-future", scheduledFor: whenLatest),
            watch: nil,
            latest: .init(id: "banked-1", resetType: "banked", announcedAt: now.addingTimeInterval(-3600))
        )
        let alongside = try #require(AdvanceReminderPlanner.predicted(status: both, lead: lead12, now: now))
        #expect(alongside.fireAt == whenLatest.addingTimeInterval(-lead12))
        #expect(alongside.identifier.contains("post-future"))
        #expect(!alongside.identifier.contains("banked-1"))
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
