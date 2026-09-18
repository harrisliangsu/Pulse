import AppKit
import SwiftUI

extension UsageWindow {
    /// Colour for how much of a limit is gone.
    ///
    /// Rings and bars used to be drawn in each provider's brand colour, which
    /// read as a status even though it never was one: Claude Code's orange-red
    /// looked like a warning at 3% used. Colour here means one thing only —
    /// how close this limit is to running out.
    /// **No default for `warningAt` or `spentAs`.** Where red begins, and
    /// what a spent limit is coloured, are settings now, and a default here
    /// is how one ring on the panel comes to disagree with the one beside it
    /// — silently, and only for whoever moved the figure.
    func tint(warningAt: Double, spentAs: SpentRingColour) -> Color {
        UsageTint.color(for: usedFraction, isExhausted: isExhausted, warningAt: warningAt, spentAs: spentAs)
    }
}

/// Where the ring turns red.
///
/// A short list rather than a slider: this is the one step in the colour
/// language that means "pay attention", and a figure somebody nudged to 73 is
/// not a clearer signal than one they picked. Every option sits above
/// `UsageTint.cautionThreshold`, so moving this one never has to push the
/// yellow step out of its way.
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

/// What a spent limit’s ring is coloured.
///
/// The provider still says whether the limit is spent — this only picks the
/// hue. Emphasize is the colour language the rail has always used: a deep red
/// of its own, darker than the warning step, so being blocked does not read
/// as merely “nearly out”. Follow usage and Quiet leave that state alone
/// (the account stays on the rail, the arc still fills, notifications still
/// fire) and only change how loudly the ring says it.
enum SpentRingColour: String, CaseIterable, Identifiable, Sendable {
    case emphasize
    case followUsage
    case quiet

    static let `default` = SpentRingColour.emphasize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emphasize: .localized("Emphasize")
        case .followUsage: .localized("Follow usage")
        case .quiet: .localized("Quiet")
        }
    }
}

enum UsageTint {
    /// Comfortable below this.
    static let cautionThreshold = 0.5
    /// Getting tight above this, unless somebody has moved it. The shipped
    /// default, and the fallback anywhere the setting has not reached.
    static let warningThreshold = WarningThreshold.default.fraction

    /// Spent is its own state, not just "more red". Being blocked and being
    /// nearly out call for different reactions, and at ring size a fourth hue
    /// would just read as the third — so Emphasize is darker *and* the figure
    /// beside the ring changes colour too. Follow usage and Quiet are the
    /// two ways to opt out of that shout; they do not change whether the
    /// limit is spent.
    ///
    /// **No default for `spentAs`.** Same reason `warningAt` has none: a
    /// default here is how one ring comes to disagree with the one beside it.
    static func color(
        for usedFraction: Double,
        isExhausted: Bool = false,
        warningAt: Double,
        spentAs: SpentRingColour
    ) -> Color {
        if isExhausted || usedFraction >= 1 {
            switch spentAs {
            case .emphasize:
                return .pulseExhausted
            case .followUsage:
                // Colour as if the reading were 100% on the same ladder —
                // never the spent hue. Every offered warning step sits below
                // 1, so this lands on warning red.
                return ladder(for: 1, warningAt: warningAt)
            case .quiet:
                return .pulseQuiet
            }
        }
        return ladder(for: usedFraction, warningAt: warningAt)
    }

    /// The green / amber / red steps, with no spent override.
    private static func ladder(for usedFraction: Double, warningAt: Double) -> Color {
        switch usedFraction {
        case ..<cautionThreshold: return .pulseGood
        case ..<warningAt: return .pulseCaution
        default: return .pulseWarning
        }
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
/// A spent limit still shows the spent colour under Emphasize, whatever
/// is chosen — being blocked is not a matter of taste. Follow usage and
/// Quiet apply those modes instead of the deep red.
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
    /// Quiet's spent hue: enough ink to keep the full arc visible, not enough
    /// to read as an alarm. Neutral on both the black rail and the light one.
    static let pulseQuiet = Color(red: 0.58, green: 0.60, blue: 0.64)
}

/// How full a limit has to be before the panel draws it in the warning colour,
/// and how a spent limit is coloured.
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

private struct SpentRingColourKey: EnvironmentKey {
    static let defaultValue = SpentRingColour.default
}

extension EnvironmentValues {
    var usageWarningThreshold: Double {
        get { self[UsageWarningThresholdKey.self] }
        set { self[UsageWarningThresholdKey.self] = newValue }
    }

    /// How a spent limit is coloured, for every ring, bar and figure below.
    var spentRingColour: SpentRingColour {
        get { self[SpentRingColourKey.self] }
        set { self[SpentRingColourKey.self] = newValue }
    }
}
