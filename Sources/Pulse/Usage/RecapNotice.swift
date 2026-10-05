// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import UserNotifications

/// Says "Your September recap is ready" in the first days of October — if the
/// reader switched that on, and only if the month had records Pulse has seen.
///
/// The rules are `RecapNoticeRule` (pure, tested); this is the clock, the scan
/// it reads and the notification. **It reads nothing of its own**: only the
/// scan `SpendWarmer` already keeps while Token spend reading is on
/// (`AgentLedgers.keptSnapshot`). No kept scan, no sentence — and nothing is
/// remembered, so a later tick asks again. See
/// [notifications.md](../../Docs/notifications.md#the-monthly-recap).
@MainActor
final class RecapNotice {
    /// Out of the way of launch, and after `SpendWarmer`'s first read has had
    /// its head start.
    static let launchDelay: Duration = .seconds(90)
    /// Half an hour is a fine grain for "the first three days of a month", and
    /// a check outside them returns before it reads anything.
    static let checkInterval: Duration = .seconds(30 * 60)

    private let settings: AppSettings
    private let alerts: UsageAlerts
    private var loop: Task<Void, Never>?

    init(settings: AppSettings, alerts: UsageAlerts) {
        self.settings = settings
        self.alerts = alerts
    }

    func start() {
        // Switching it on in the first days of a month says so at once.
        settings.onRecapAlertChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                _ = await self.alerts.requestAuthorizationIfNeeded()
                self.check()
            }
        }
        loop = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// Decides now, and posts at most one notification.
    func check(now: Date = Date()) {
        guard settings.alertsOnRecap, settings.readsTokenSpend, UsageAlerts.isSupported,
              // The grant is not known yet: nothing is consumed while it is
              // being asked for, as with the limit alerts.
              alerts.authorization != .notDetermined,
              RecapNoticeRule.candidate(now: now) != nil else { return }

        Task { @MainActor in
            guard let kept = await AgentLedgers.shared.keptSnapshot() else { return }
            let announced = settings.recapAnnouncedMonth.flatMap(Recap.Period.init(key:))
            // The month's summary is arithmetic over every day of every
            // ledger: off the main actor, then back for the decision.
            let ledgers = kept.snapshot.ledgers
            let due = await Task.detached(priority: .utility) {
                Self.dueMonth(now: now, announced: announced, ledgers: ledgers)
            }.value
            // Read again after the awaits: a second check (the switch going on
            // while the timer fires) may have announced this month meanwhile.
            guard let month = due, settings.alertsOnRecap, settings.recapAnnouncedMonth != month.key else { return }

            // Remembered before it is posted, and whether or not the system
            // will show it: a month is announced once.
            settings.recapAnnouncedMonth = month.key
            post(month)
        }
    }

    /// `RecapNoticeRule.due` over the ledgers, in the recap's calendar. Pure
    /// and `nonisolated`, so it can run off the main actor.
    nonisolated static func dueMonth(
        now: Date, announced: Recap.Period?, ledgers: [SpendAgent: UsageLedger], calendar: Calendar = Recap.calendar
    ) -> Recap.Period? {
        RecapNoticeRule.due(
            now: now,
            announced: announced,
            tokens: { period in
                guard let bounds = period.bounds(calendar: calendar) else { return nil }
                return SpendSummary.of(ledgers, from: bounds.start, until: bounds.end, now: now, calendar: calendar).tokens
            },
            calendar: calendar
        )
    }

    private func post(_ month: Recap.Period) {
        guard case .month(_, let number) = month else { return }
        let content = UNMutableNotificationContent()
        content.title = .localized("Monthly Recap")
        content.body = .localized("Your \(RecapFormat.monthName(number)) recap is ready")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: RecapNoticeRule.identifier(for: month),
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}
