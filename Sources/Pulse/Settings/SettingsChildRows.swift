// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Whether a settings row that belongs to another control is drawn.
///
/// This is layout. A `false` here omits the row; it does not write the
/// setting that row edits, clear it, or change when a notice fires. The
/// value stays where it was, and the row comes back with that value when
/// its parent is on again.
enum SettingsChildRows {
    static func showsLimitCameBack(_ threshold: AlertThreshold) -> Bool {
        threshold != .off
    }

    static func showsForecastDetails(onCard: Bool) -> Bool {
        onCard
    }

    static func showsExhaustionStages(alertsOn: Bool) -> Bool {
        alertsOn
    }

    static func showsExhaustionAccountList(allAccounts: Bool) -> Bool {
        !allAccounts
    }

    static func showsPredictedLead(_ on: Bool) -> Bool {
        on
    }

    static func showsRegularLead(_ on: Bool) -> Bool {
        on
    }

    static func showsHourlyCelebration(_ on: Bool) -> Bool {
        on
    }

    static func showsTransparency(usesGlass: Bool) -> Bool {
        usesGlass
    }

    static func showsFiguresBeside(percentagesAcross: Bool) -> Bool {
        percentagesAcross
    }

    /// The figure can sit above a ring only when some rail is drawing figures.
    static func showsFigureAboveRing(sidePercentages: Bool, acrossPercentages: Bool) -> Bool {
        sidePercentages || acrossPercentages
    }

    static func showsTimeRingDirection(clockOn: Bool) -> Bool {
        clockOn
    }

    static func showsWarningThreshold(_ scheme: RingColourScheme) -> Bool {
        scheme == .redAlert || scheme == .quiet
    }

    /// Hide, screenshots, snap and follow-the-display. Shown only while the
    /// rail itself is on; each one was already inoperable while it was off.
    static func showsPanelDetails(panelVisible: Bool) -> Bool {
        panelVisible
    }

    static func showsMenuBarFigureOptions(showsUsage: Bool, iconHidden: Bool) -> Bool {
        showsUsage && !iconHidden
    }

    static func showsManualProxy(_ mode: NetworkProxyMode) -> Bool {
        mode == .manual
    }

    static func showsExchangeRate(_ currency: DisplayCurrency) -> Bool {
        currency != .usd
    }

    static func showsTokenSpendDetails(reading: Bool) -> Bool {
        reading
    }
}

/// The percent written beside the glass slider. The stored setting stays
/// a fraction from 0 to 1; this string is not written back.
enum GlassTransparencyLabel {
    static func percent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
