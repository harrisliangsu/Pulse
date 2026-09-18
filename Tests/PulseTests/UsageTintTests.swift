import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// The colour language each scheme speaks, and that 1.2.1's spent-only
/// picker migrates onto it.
///
/// Red alert is green and red only — no amber step. Gradient and Quiet must
/// never emit alarm red, including when a limit is spent, which is the
/// failure 1.2.1 Quiet had: it only overrode the spent hue and left 98% used
/// on the old green→amber→red ladder.
@Suite("Usage tint")
struct UsageTintTests {
    private static func colour(
        _ used: Double,
        warningAt: WarningThreshold = .seventyFive,
        spent: Bool = false,
        scheme: RingColourScheme = .redAlert
    ) -> Color {
        UsageTint.color(
            for: used,
            isExhausted: spent,
            warningAt: warningAt.fraction,
            scheme: scheme
        )
    }

    private static let usages: [Double] = [
        0, 0.2, 0.49, 0.5, 0.61, 0.74, 0.75, 0.8, 0.86, 0.98, 1
    ]

    // MARK: Red alert

    @Test("Red alert is green below the threshold and red at or above it")
    func redAlertGreenThenRed() {
        #expect(Self.colour(0.74, warningAt: .seventyFive) == .pulseGood)
        #expect(Self.colour(0.75, warningAt: .seventyFive) == .pulseWarning)
        #expect(Self.colour(0.76, warningAt: .eighty) == .pulseGood)
        #expect(Self.colour(0.61, warningAt: .sixty) == .pulseWarning)
        #expect(Self.colour(0.98) == .pulseWarning)
    }

    @Test("Red alert has no amber step")
    func redAlertHasNoAmber() {
        for threshold in WarningThreshold.allCases {
            #expect(Self.colour(0.49, warningAt: threshold) == .pulseGood)
            #expect(Self.colour(0.5, warningAt: threshold) == .pulseGood)
            #expect(Self.colour(threshold.fraction.nextDown, warningAt: threshold) == .pulseGood)
            #expect(Self.colour(threshold.fraction.nextDown, warningAt: threshold) != .pulseCaution)
            #expect(Self.colour(threshold.fraction, warningAt: threshold) == .pulseWarning)
        }
    }

    @Test("Red alert colours a spent limit deep red, wherever the threshold sits")
    func redAlertSpentIsDeepRed() {
        #expect(Self.colour(0.1, warningAt: .ninety, spent: true) == .pulseExhausted)
        #expect(Self.colour(1, warningAt: .ninety) == .pulseExhausted)
    }

    // MARK: Gradient

    @Test("Gradient climbs green to amber to orange, never red")
    func gradientNeverRed() {
        #expect(Self.colour(0.2, scheme: .gradient) == .pulseGood)
        #expect(Self.colour(0.5, scheme: .gradient) == .pulseCaution)
        #expect(Self.colour(0.74, warningAt: .seventyFive, scheme: .gradient) == .pulseCaution)
        #expect(Self.colour(0.75, warningAt: .seventyFive, scheme: .gradient) == .pulseGradientPeak)
        #expect(Self.colour(0.98, scheme: .gradient) == .pulseGradientPeak)
        #expect(Self.colour(1, scheme: .gradient) == .pulseGradientPeak)
        #expect(Self.colour(0.1, spent: true, scheme: .gradient) == .pulseGradientPeak)

        for used in Self.usages {
            #expect(!Self.colour(used, scheme: .gradient).isPulseAlarmRed)
            #expect(!Self.colour(used, spent: true, scheme: .gradient).isPulseAlarmRed)
        }
        for threshold in WarningThreshold.allCases {
            #expect(!Self.colour(1, warningAt: threshold, scheme: .gradient).isPulseAlarmRed)
        }
    }

    // MARK: Quiet

    @Test("Quiet is a grey scale and never red or amber")
    func quietNeverRedOrAmber() {
        #expect(Self.colour(0.2, scheme: .quiet) == .pulseQuietLight)
        #expect(Self.colour(0.5, scheme: .quiet) == .pulseQuiet)
        #expect(Self.colour(0.98, scheme: .quiet) == .pulseQuiet)
        #expect(Self.colour(1, scheme: .quiet) == .pulseQuietDeep)
        #expect(Self.colour(0.1, warningAt: .ninety, spent: true, scheme: .quiet) == .pulseQuietDeep)

        for used in Self.usages {
            let colour = Self.colour(used, scheme: .quiet)
            #expect(!colour.isPulseAlarmRed)
            #expect(colour != .pulseCaution)
            #expect(!Self.colour(used, spent: true, scheme: .quiet).isPulseAlarmRed)
        }
    }

    @Test("Quiet ignores the red threshold")
    func quietIgnoresTheThreshold() {
        #expect(
            Self.colour(0.8, warningAt: .sixty, scheme: .quiet)
                == Self.colour(0.8, warningAt: .ninety, scheme: .quiet)
        )
    }

    // MARK: Shared

    @Test("every offered figure sits above the caution step")
    func optionsClearCaution() {
        for threshold in WarningThreshold.allCases {
            #expect(threshold.fraction > UsageTint.cautionThreshold)
        }
    }

    @Test("the shipped defaults are Red alert at 75%")
    func defaultsAreRedAlert() {
        #expect(UsageTint.warningThreshold == 0.75)
        #expect(WarningThreshold.default == .seventyFive)
        #expect(RingColourScheme.default == .redAlert)
        #expect(AppSettings().ringColourScheme == .redAlert)
    }

    @Test("a chosen tint yields to Red alert spent red, and not to Gradient or Quiet")
    func chosenTintAndScheme() {
        let blue = Color(red: 0.25, green: 0.60, blue: 1.00)

        #expect(
            UsageTint.resolved(
                usedFraction: 0.1,
                isExhausted: true,
                warningAt: 0.75,
                scheme: .redAlert,
                chosenTint: blue
            ) == .pulseExhausted
        )
        #expect(
            UsageTint.resolved(
                usedFraction: 0.98,
                isExhausted: false,
                warningAt: 0.75,
                scheme: .redAlert,
                chosenTint: blue
            ) == blue
        )
        #expect(
            UsageTint.resolved(
                usedFraction: 1,
                isExhausted: true,
                warningAt: 0.75,
                scheme: .gradient,
                chosenTint: blue
            ) == blue
        )
        #expect(
            UsageTint.resolved(
                usedFraction: 1,
                isExhausted: true,
                warningAt: 0.75,
                scheme: .quiet,
                chosenTint: blue
            ) == blue
        )
        #expect(
            !UsageTint.resolved(
                usedFraction: 1,
                isExhausted: true,
                warningAt: 0.75,
                scheme: .gradient,
                chosenTint: nil
            ).isPulseAlarmRed
        )
    }

    // MARK: Migration

    @Test("1.2.1 spent-colour values land on the matching scheme")
    func spentColourMigrates() {
        #expect(RingColourScheme.migrating(fromSpentRingColour: nil) == .redAlert)
        #expect(RingColourScheme.migrating(fromSpentRingColour: "emphasize") == .redAlert)
        #expect(RingColourScheme.migrating(fromSpentRingColour: "followUsage") == .gradient)
        #expect(RingColourScheme.migrating(fromSpentRingColour: "quiet") == .quiet)
        #expect(RingColourScheme.migrating(fromSpentRingColour: "unknown") == .redAlert)
    }

    @Test("a stored 1.2.1 Quiet value restores as Quiet and writes the new key")
    func storedQuietMigrates() {
        withIsolatedDefaults { defaults in
            defaults.set("quiet", forKey: AppSettings.spentRingColourDefaultsKey)
            #expect(AppSettings.storedRingColourScheme(in: defaults) == .quiet)
            #expect(defaults.string(forKey: AppSettings.ringColourSchemeDefaultsKey) == "quiet")
        }
    }

    @Test("a stored 1.2.1 Follow usage value restores as Gradient")
    func storedFollowUsageMigrates() {
        withIsolatedDefaults { defaults in
            defaults.set("followUsage", forKey: AppSettings.spentRingColourDefaultsKey)
            #expect(AppSettings.storedRingColourScheme(in: defaults) == .gradient)
        }
    }

    @Test("a stored 1.2.1 Emphasize value restores as Red alert and keeps the threshold")
    func storedEmphasizeMigrates() {
        withIsolatedDefaults { defaults in
            defaults.set("emphasize", forKey: AppSettings.spentRingColourDefaultsKey)
            defaults.set(WarningThreshold.sixty.rawValue, forKey: "settings.warningThreshold")
            #expect(AppSettings.storedRingColourScheme(in: defaults) == .redAlert)
            #expect(
                (defaults.object(forKey: "settings.warningThreshold") as? Int)
                    .flatMap(WarningThreshold.init(rawValue:)) == .sixty
            )
        }
    }

    @Test("the new key wins over a leftover 1.2.1 value")
    func newKeyWins() {
        withIsolatedDefaults { defaults in
            defaults.set("quiet", forKey: AppSettings.spentRingColourDefaultsKey)
            AppSettings.storeRingColourScheme(.gradient, in: defaults)
            #expect(AppSettings.storedRingColourScheme(in: defaults) == .gradient)
        }
    }

    @Test("nothing stored is Red alert and does not write a default")
    func absentStaysDefault() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings.storedRingColourScheme(in: defaults) == .redAlert)
            #expect(defaults.object(forKey: AppSettings.ringColourSchemeDefaultsKey) == nil)
        }
    }

    /// A `UserDefaults` domain owned by one test, emptied on the way out.
    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "PulseTests.ringColourScheme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
