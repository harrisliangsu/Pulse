import AppKit
import SwiftUI

extension UsageWindow {
    /// Colour for how much of a limit is gone.
    ///
    /// Rings and bars used to be drawn in each provider's brand colour, which
    /// read as a status even though it never was one: Claude Code's orange-red
    /// looked like a warning at 3% used. Colour here means one thing only —
    /// how close this limit is to running out.
    /// **No default for `warningAt` or `scheme`.** The scheme owns the whole
    /// colour language, and a default here is how one ring on the panel comes
    /// to disagree with the one beside it — silently, and only for whoever
    /// moved the figure.
    func tint(warningAt: Double, scheme: RingColourScheme) -> Color {
        UsageTint.color(for: usedFraction, isExhausted: isExhausted, warningAt: warningAt, scheme: scheme)
    }
}

/// Where Red alert turns from green to red.
///
/// A short list rather than a slider: this is the one step in that scheme
/// that means "pay attention", and a figure somebody nudged to 73 is not a
/// clearer signal than one they picked. Gradient reuses the same figure as
/// its yellow→orange step so a value stored under Red alert is not discarded
/// if the scheme changes; Quiet reuses it as the green→grey step. Every
/// option sits above `UsageTint.cautionThreshold`, which is Gradient's
/// green→yellow step.
enum WarningThreshold: Int, CaseIterable, Identifiable, Sendable {
    case sixty = 60
    case seventy = 70
    case seventyFive = 75
    case eighty = 80
    case eightyFive = 85
    case ninety = 90

    static let `default` = WarningThreshold.seventyFive

    var id: Int { rawValue }
    var fraction: Double { Double(rawValue) / 100 }

    /// Not run through `localized` — see `AlertThreshold.title` for why a bare
    /// percentage is not a sentence.
    var title: String { "\(rawValue)%" }
}

/// The colour language every ring, bar and figure uses.
///
/// One setting, not a global red threshold plus a spent-only tweak. 1.2.1's
/// `SpentRingColour` (Emphasize / Follow usage / Quiet) only overrode the
/// spent hue, so Quiet still went red at 98% used through the green→amber→red
/// ladder. The scheme owns the palette; red exists only in Red alert.
enum RingColourScheme: String, CaseIterable, Identifiable, Sendable {
    case redAlert
    case gradient
    case quiet

    static let `default` = RingColourScheme.redAlert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .redAlert: .localized("Red alert")
        case .gradient: .localized("Gradient")
        case .quiet: .localized("Quiet")
        }
    }

    /// Maps the 1.2.1 spent-only picker so Quiet users keep Quiet.
    static func migrating(fromSpentRingColour stored: String?) -> RingColourScheme {
        switch stored {
        case "followUsage": .gradient
        case "quiet": .quiet
        default: .redAlert
        }
    }
}

enum UsageTint {
    /// Comfortable below this. Gradient's green→yellow step; Red alert
    /// and Quiet ignore it (green runs up to the warning figure).
    static let cautionThreshold = 0.5
    /// Getting tight above this, unless somebody has moved it. The shipped
    /// default, and the fallback anywhere the setting has not reached.
    static let warningThreshold = WarningThreshold.default.fraction

    /// The scheme's colour for this reading. Red is produced only by
    /// Red alert — Gradient never climbs to it, and Quiet replaces the
    /// alarm band with grey, so a spent, locked, or 98%-used limit
    /// cannot go red.
    ///
    /// **No default for `scheme`.** Same reason `warningAt` has none: a
    /// default here is how one ring comes to disagree with the one beside it.
    static func color(
        for usedFraction: Double,
        isExhausted: Bool = false,
        warningAt: Double,
        scheme: RingColourScheme
    ) -> Color {
        switch scheme {
        case .redAlert:
            return redAlert(for: usedFraction, isExhausted: isExhausted, warningAt: warningAt)
        case .gradient:
            return gradient(for: usedFraction, isExhausted: isExhausted, warningAt: warningAt)
        case .quiet:
            return quiet(for: usedFraction, isExhausted: isExhausted, warningAt: warningAt)
        }
    }

    /// Apply a chosen tint, then let Red alert's spent red win as it always
    /// has. Gradient and Quiet keep the chosen tint — including when spent —
    /// so a custom colour is never forced to alarm red by the scheme.
    static func resolved(
        usedFraction: Double,
        isExhausted: Bool,
        warningAt: Double,
        scheme: RingColourScheme,
        chosenTint: Color?
    ) -> Color {
        let automatic = color(
            for: usedFraction,
            isExhausted: isExhausted,
            warningAt: warningAt,
            scheme: scheme
        )
        guard let chosenTint else { return automatic }
        if scheme == .redAlert && (isExhausted || usedFraction >= 1) {
            return automatic
        }
        return chosenTint
    }

    /// Green below the threshold, red at or above it, spent deep red.
    /// No amber step — that was the 1.2.1 ladder Quiet could not opt out of.
    private static func redAlert(for usedFraction: Double, isExhausted: Bool, warningAt: Double) -> Color {
        if isExhausted || usedFraction >= 1 { return .pulseExhausted }
        return usedFraction < warningAt ? .pulseGood : .pulseWarning
    }

    /// Green → yellow/amber → deeper amber/orange. The warning figure is the
    /// yellow→orange step, never a red one. Spent uses the top of the same
    /// climb.
    private static func gradient(for usedFraction: Double, isExhausted: Bool, warningAt: Double) -> Color {
        if isExhausted || usedFraction >= 1 { return .pulseGradientPeak }
        switch usedFraction {
        case ..<cautionThreshold: return .pulseGood
        case ..<warningAt: return .pulseCaution
        default: return .pulseGradientPeak
        }
    }

    /// The same green band Red alert uses, with muted grey in place of
    /// alarm red. Healthy stays green — Quiet is not a grey wash of the
    /// whole rail. At or above the warning figure, or when spent, the
    /// ring goes grey. Never red, never amber.
    private static func quiet(for usedFraction: Double, isExhausted: Bool, warningAt: Double) -> Color {
        if isExhausted || usedFraction >= 1 { return .pulseQuietDeep }
        return usedFraction < warningAt ? .pulseGood : .pulseQuiet
    }

    static func isSpent(_ window: UsageWindow?) -> Bool {
        guard let window else { return false }
        return window.isExhausted || window.usedFraction >= 1
    }
}

/// A colour someone has chosen for one account's ring, stored as hex.
///
/// **The default is no colour at all**, and should stay that way. Colour on
/// these rings means how much of a limit is gone; giving a ring a fixed hue
/// takes that reading away, which is what the app is for. It was how the rings
/// worked once — each provider in its own brand colour — and it read as a
/// status it never was: Claude Code's orange-red looked like a warning at 3%
/// used. So this is an option, off unless asked for.
///
/// Under Red alert, a spent limit still shows the spent colour whatever is
/// chosen — being blocked is not a matter of taste. Gradient and Quiet keep
/// the chosen tint; the scheme is what stops alarm red, not a forced grey.
///
/// Free rather than a fixed palette, because eight swatches is not a choice —
/// and the eight had to be legible on both the panel's black and on Liquid
/// Glass, which is a constraint on *us*, not on the person picking. Anything
/// can be chosen; `RingTint.suggestions` is only a starting point.
enum RingTint {
    /// A few that read at ring size on both surfaces, offered as a start.
    /// Not a limit — the colour well takes anything.
    static let suggestions: [Color] = [
        Color(red: 0.25, green: 0.60, blue: 1.00),
        Color(red: 0.70, green: 0.50, blue: 1.00),
        Color(red: 1.00, green: 0.44, blue: 0.72),
        Color(red: 1.00, green: 0.56, blue: 0.20),
        Color(red: 0.20, green: 0.82, blue: 0.82),
    ]

    /// The colour a stored value means, or nil for "colour it by usage".
    ///
    /// Accepts the eight names the first version of this stored, so a choice
    /// made before it became a colour well is not silently dropped.
    static func color(from stored: String?) -> Color? {
        guard let stored, !stored.isEmpty else { return nil }
        if let named = legacy[stored] { return named }
        return Color(hex: stored)
    }

    private static let legacy: [String: Color] = [
        "blue": Color(red: 0.25, green: 0.60, blue: 1.00),
        "purple": Color(red: 0.70, green: 0.50, blue: 1.00),
        "pink": Color(red: 1.00, green: 0.44, blue: 0.72),
        "red": .pulseWarning,
        "orange": Color(red: 1.00, green: 0.56, blue: 0.20),
        "yellow": .pulseCaution,
        "green": .pulseGood,
        "teal": Color(red: 0.20, green: 0.82, blue: 0.82),
    ]
}

extension Color {
    /// "#RRGGBB", which is what a chosen colour is stored as.
    ///
    /// Converted through sRGB explicitly: a colour picked in another space
    /// answers its components in that space, and the numbers would not survive
    /// a round trip.
    var hexString: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }

        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The two reds Red alert may emit. Gradient and Quiet must never
    /// return either, at any usage or when spent.
    var isPulseAlarmRed: Bool {
        self == .pulseWarning || self == .pulseExhausted
    }
}

extension Color {
    /// Picked to sit on the panel's black: bright enough to read at ring size,
    /// without the neon cast that fully saturated values take on there.
    static let pulseGood = Color(red: 0.00, green: 0.90, blue: 0.55)
    static let pulseCaution = Color(red: 1.00, green: 0.76, blue: 0.15)
    static let pulseWarning = Color(red: 1.00, green: 0.31, blue: 0.26)
    /// Deeper and flatter than the warning red, so a spent limit doesn't just
    /// look like a slightly redder nearly-spent one.
    static let pulseExhausted = Color(red: 0.85, green: 0.09, blue: 0.13)
    /// Gradient's top: deeper amber/orange than the caution step, and not red.
    static let pulseGradientPeak = Color(red: 0.95, green: 0.48, blue: 0.12)
    /// Quiet's alarm-band grey — the muted stand-in for Red alert's warning
    /// red. Healthy usage stays `pulseGood`; this is only for the line at
    /// or above the threshold.
    static let pulseQuiet = Color(red: 0.58, green: 0.60, blue: 0.64)
    /// Quiet's spent grey: darker than the alarm step, still above the
    /// empty track so a full arc does not vanish into the rail.
    static let pulseQuietDeep = Color(red: 0.46, green: 0.48, blue: 0.52)
}

/// How full a limit has to be before Red alert draws it red, and which
/// colour language the panel is speaking.
///
/// Through the environment rather than down the initializers. They are two
/// facts that every ring, bar and figure on the panel has to agree on, and the
/// alternative is a field in `RailEntry`, another in the dock's item, and more
/// arguments to a `UsageRingView` initializer that already had to be lifted
/// out of `body` to fit the compiler's type-checking budget. Neither is a
/// layout input, so they have no business in `PanelMetrics` beside the scale.
private struct UsageWarningThresholdKey: EnvironmentKey {
    static let defaultValue = UsageTint.warningThreshold
}

private struct RingColourSchemeKey: EnvironmentKey {
    static let defaultValue = RingColourScheme.default
}

extension EnvironmentValues {
    var usageWarningThreshold: Double {
        get { self[UsageWarningThresholdKey.self] }
        set { self[UsageWarningThresholdKey.self] = newValue }
    }

    /// The colour language for every ring, bar and figure below.
    var ringColourScheme: RingColourScheme {
        get { self[RingColourSchemeKey.self] }
        set { self[RingColourSchemeKey.self] = newValue }
    }
}
