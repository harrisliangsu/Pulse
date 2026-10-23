import Foundation
import Testing
@testable import Pulse

/// Layout only: which child row is drawn, and that drawing it or hiding it
/// does not change the setting underneath. Defaults and stored keys are the
/// ones 1.5.5 shipped.
@Suite("Settings layout")
@MainActor
struct SettingsLayoutRulesTests {
    @Test("Child rows follow the parent and leave the stored value alone")
    func childRowsDoNotChangeSettings() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.alertThreshold == .off)
        #expect(!SettingsChildRows.showsLimitCameBack(settings.alertThreshold))
        settings.alertsOnReset = true
        settings.alertThreshold = .ninety
        #expect(SettingsChildRows.showsLimitCameBack(settings.alertThreshold))
        settings.alertThreshold = .off
        #expect(!SettingsChildRows.showsLimitCameBack(.off))
        #expect(settings.alertsOnReset)

        #expect(settings.showsForecast)
        #expect(SettingsChildRows.showsForecastDetails(onCard: true))
        settings.exhaustionCardHours = 8
        settings.exhaustionSoftHint = false
        settings.showsForecast = false
        #expect(!SettingsChildRows.showsForecastDetails(onCard: settings.showsForecast))
        #expect(settings.exhaustionCardHours == 8)
        #expect(settings.exhaustionSoftHint == false)

        #expect(settings.exhaustionAlerts)
        #expect(settings.exhaustionStages.map(\.hours) == [24])
        settings.exhaustionAlerts = false
        #expect(!SettingsChildRows.showsExhaustionStages(alertsOn: false))
        #expect(settings.exhaustionStages.map(\.hours) == [24])

        #expect(settings.exhaustionAllAccounts)
        #expect(!SettingsChildRows.showsExhaustionAccountList(allAccounts: true))
        settings.exhaustionAllAccounts = false
        #expect(SettingsChildRows.showsExhaustionAccountList(allAccounts: false))

        #expect(!settings.remindsBeforePredictedReset)
        #expect(!settings.remindsBeforeRegularReset)
        #expect(settings.predictedResetLead == .default)
        #expect(settings.regularResetLead == .default)
        #expect(!SettingsChildRows.showsPredictedLead(false))
        #expect(!SettingsChildRows.showsRegularLead(false))
        settings.remindsBeforePredictedReset = true
        settings.predictedResetLead = .twelve
        settings.remindsBeforeRegularReset = true
        settings.regularResetLead = .twoDays
        #expect(SettingsChildRows.showsPredictedLead(settings.remindsBeforePredictedReset))
        #expect(SettingsChildRows.showsRegularLead(settings.remindsBeforeRegularReset))
        settings.remindsBeforePredictedReset = false
        settings.remindsBeforeRegularReset = false
        #expect(settings.predictedResetLead == .twelve)
        #expect(settings.regularResetLead == .twoDays)
        #expect(defaults.object(forKey: "settings.predictedResetLead") as? Int == ResetLead.twelve.rawValue)
        #expect(defaults.object(forKey: "settings.regularResetLead") as? Int == ResetLead.twoDays.rawValue)

        #expect(!settings.celebratesReset)
        #expect(!SettingsChildRows.showsHourlyCelebration(false))
        settings.celebratesHourlyReset = true
        settings.celebratesReset = false
        #expect(!SettingsChildRows.showsHourlyCelebration(settings.celebratesReset))
        #expect(settings.celebratesHourlyReset)

        #expect(SettingsChildRows.showsWarningThreshold(.redAlert))
        #expect(SettingsChildRows.showsWarningThreshold(.quiet))
        #expect(!SettingsChildRows.showsWarningThreshold(.gradient))
        #expect(!SettingsChildRows.showsFiguresBeside(percentagesAcross: false))
        #expect(SettingsChildRows.showsFiguresBeside(percentagesAcross: true))
        #expect(!SettingsChildRows.showsFigureAboveRing(sidePercentages: false, acrossPercentages: false))
        #expect(SettingsChildRows.showsFigureAboveRing(sidePercentages: true, acrossPercentages: false))
        #expect(SettingsChildRows.showsFigureAboveRing(sidePercentages: false, acrossPercentages: true))
        #expect(!SettingsChildRows.showsTimeRingDirection(clockOn: false))
        #expect(SettingsChildRows.showsTimeRingDirection(clockOn: true))
        #expect(SettingsChildRows.showsPanelDetails(panelVisible: true))
        #expect(!SettingsChildRows.showsPanelDetails(panelVisible: false))
        #expect(!SettingsChildRows.showsMenuBarFigureOptions(showsUsage: true, iconHidden: true))
        #expect(SettingsChildRows.showsMenuBarFigureOptions(showsUsage: true, iconHidden: false))
        #expect(!SettingsChildRows.showsMenuBarFigureOptions(showsUsage: false, iconHidden: false))
        #expect(SettingsChildRows.showsMainWindowAtLogin(openAtLogin: true))
        #expect(!SettingsChildRows.showsMainWindowAtLogin(openAtLogin: false))
        #expect(SettingsChildRows.showsDockIconWhileWindowOpen(alwaysShowsDockIcon: false))
        #expect(!SettingsChildRows.showsDockIconWhileWindowOpen(alwaysShowsDockIcon: true))
        #expect(SettingsChildRows.showsManualProxy(.manual))
        #expect(!SettingsChildRows.showsManualProxy(.system))
        #expect(!SettingsChildRows.showsExchangeRate(.usd))
        #expect(SettingsChildRows.showsExchangeRate(.cny))
        #expect(!SettingsChildRows.showsTokenSpendDetails(reading: false))
        #expect(SettingsChildRows.showsTokenSpendDetails(reading: true))
        #expect(!SettingsChildRows.showsTransparency(usesGlass: false))
        #expect(SettingsChildRows.showsTransparency(usesGlass: true))
    }

    @Test("The countdown stepper shows its hours and writes the same setting")
    func countdownHoursStayVisibleAndClamped() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.exhaustionCardHours == 6)
        #expect(ExhaustionHoursControl.digits(settings.exhaustionCardHours) == "6")
        #expect(!ExhaustionHoursControl.digits(settings.exhaustionCardHours).isEmpty)

        settings.exhaustionCardHours = ExhaustionHoursControl.applied(settings.exhaustionCardHours + 1)
        #expect(settings.exhaustionCardHours == 7)
        #expect(ExhaustionHoursControl.digits(settings.exhaustionCardHours) == "7")
        #expect(defaults.object(forKey: "settings.exhaustionCardHours") as? Int == 7)

        settings.exhaustionCardHours = ExhaustionHoursControl.applied(0)
        #expect(settings.exhaustionCardHours == ExhaustionStage.minimumHours)
        #expect(ExhaustionHoursControl.digits(0) == "\(ExhaustionStage.minimumHours)")
        #expect(!ExhaustionHoursControl.digits(0).isEmpty)

        settings.exhaustionCardHours = ExhaustionHoursControl.applied(ExhaustionStage.maximumHours + 40)
        #expect(settings.exhaustionCardHours == ExhaustionStage.maximumHours)
        #expect(ExhaustionHoursControl.digits(10_000) == "\(ExhaustionStage.maximumHours)")

        let back = AppSettings.restoredSettings(
            from: defaults, detected: [], scan: ExtensionCatalog.Scan()
        )
        #expect(back.exhaustionCardHours == ExhaustionStage.maximumHours)
        #expect(ExhaustionHoursControl.digits(back.exhaustionCardHours) == "\(ExhaustionStage.maximumHours)")
    }

    @Test("Notify before the reset is off unless a stored true says otherwise")
    func notifyBeforeResetIsNotInverted() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.exhaustionNotifyBeforeReset == false)
        #expect(defaults.object(forKey: "settings.exhaustionNotifyBeforeReset") == nil)

        settings.exhaustionNotifyBeforeReset = true
        #expect(settings.exhaustionNotifyBeforeReset)
        #expect(defaults.object(forKey: "settings.exhaustionNotifyBeforeReset") as? Bool == true)

        let on = AppSettings.restoredSettings(
            from: defaults, detected: [], scan: ExtensionCatalog.Scan()
        )
        #expect(on.exhaustionNotifyBeforeReset)

        on.exhaustionNotifyBeforeReset = false
        #expect(on.exhaustionNotifyBeforeReset == false)
        #expect(defaults.object(forKey: "settings.exhaustionNotifyBeforeReset") as? Bool == false)

        let off = AppSettings.restoredSettings(
            from: defaults, detected: [], scan: ExtensionCatalog.Scan()
        )
        #expect(off.exhaustionNotifyBeforeReset == false)
    }

    @Test("Shipped exhaustion defaults are unchanged")
    func exhaustionDefaultsStay() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.showsForecast)
        #expect(settings.exhaustionAllAccounts)
        #expect(settings.exhaustionCardHours == 6)
        #expect(settings.exhaustionCardHorizon == TimeInterval(6 * 3600))
        #expect(settings.exhaustionSoftHint)
        #expect(settings.exhaustionBeforeReset)
        #expect(settings.exhaustionAlerts)
        #expect(settings.exhaustionStages == ExhaustionStage.defaultStages)
        #expect(settings.exhaustionStages == [ExhaustionStage(id: "24h", hours: 24)])
        #expect(settings.exhaustionNotifyBeforeReset == false)
        #expect(settings.alertThreshold == .off)
        #expect(settings.alertsOnReset == false)
        #expect(settings.celebratesReset == false)
        #expect(settings.celebratesHourlyReset == false)
        #expect(settings.remindsBeforePredictedReset == false)
        #expect(settings.remindsBeforeRegularReset == false)
        #expect(settings.readsTokenSpend == false)
    }

    @Test("The card still follows the stored horizon, hint and reset sentence")
    func cardFollowsStoredExhaustionSettings() {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let far = Self.weekly(used: Self.pace(remaining: 37 * 3600), now: now)
        let reading = BurnRate.reading(for: far, now: now)!

        let tied = BurnRate.cardLine(
            for: far,
            reading: reading,
            horizon: settings.exhaustionCardHorizon,
            softHint: settings.exhaustionSoftHint,
            beforeReset: settings.exhaustionBeforeReset
        )
        #expect(tied?.tone == .beforeReset)

        settings.exhaustionBeforeReset = false
        let hint = BurnRate.cardLine(
            for: far,
            reading: reading,
            horizon: settings.exhaustionCardHorizon,
            softHint: settings.exhaustionSoftHint,
            beforeReset: settings.exhaustionBeforeReset
        )
        #expect(hint?.tone == .hint)

        settings.exhaustionCardHours = 48
        let countdown = BurnRate.cardLine(
            for: far,
            reading: reading,
            horizon: settings.exhaustionCardHorizon,
            softHint: settings.exhaustionSoftHint,
            beforeReset: settings.exhaustionBeforeReset
        )
        #expect(countdown?.tone == .countdown)
        #expect(settings.exhaustionCardHorizon == TimeInterval(48 * 3600))

        settings.exhaustionCardHours = 6
        settings.exhaustionSoftHint = false
        #expect(BurnRate.cardLine(
            for: far,
            reading: reading,
            horizon: settings.exhaustionCardHorizon,
            softHint: settings.exhaustionSoftHint,
            beforeReset: settings.exhaustionBeforeReset
        ) == nil)
    }

    @Test("The glass slider's percent is a label, not a new setting")
    func glassPercentIsDisplayOnly() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        let stored = settings.glassTransparency

        #expect(GlassTransparencyLabel.percent(0) == "0%")
        #expect(GlassTransparencyLabel.percent(0.5) == "50%")
        #expect(GlassTransparencyLabel.percent(1) == "100%")
        #expect(GlassTransparencyLabel.percent(1.4) == "100%")
        #expect(!GlassTransparencyLabel.percent(stored).isEmpty)
        #expect(settings.glassTransparency == stored)
    }

    @Test("Exhaustion group titles and the countdown subtitle")
    func exhaustionCopy() {
        LocalizationSource.use(.chineseSimplified)
        defer { LocalizationSource.use(.system) }

        #expect(ExhaustionSettingsSections.titles == ["卡片上显示什么", "通知", "作用账号"])
        #expect(String.localized("The furthest time, in hours, at which the card writes a countdown.")
            == "卡片上写出具体倒计时的最远时间（小时）。")
        #expect(String.localized("Limits and outages") == "故障与额度")
        #expect(String.localized("Countdown up to") == "具体倒计时")

        LocalizationSource.use(.english)
        #expect(ExhaustionSettingsSections.titles == [
            "What the card shows", "Notices", "Which accounts",
        ])
        #expect(String.localized("The furthest time, in hours, at which the card writes a countdown.")
            == "The furthest time, in hours, at which the card writes a countdown.")
    }

    private static func pace(remaining: TimeInterval, length: Double = 604_800, elapsed: Double = 0.5) -> Double {
        let elapsedSeconds = length * elapsed
        return elapsedSeconds / (remaining + elapsedSeconds)
    }

    private static func weekly(used: Double, now: Date, elapsed: Double = 0.5) -> UsageWindow {
        UsageWindow(
            id: "window",
            kind: .weekly,
            scope: nil,
            usedFraction: used,
            windowSeconds: 604_800,
            resetsAt: now.addingTimeInterval(604_800 * (1 - elapsed)),
            reportsLength: true
        )
    }
}
