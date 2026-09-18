import SwiftUI
import Testing
@testable import Pulse

/// Where the three usage colours change over, and how a spent limit is coloured.
///
/// The warning step is a setting now, so the thing worth pinning is that
/// moving it moves *only* that step: green does not follow it around, and
/// every offered figure stays above the caution step it bounds. Spent colour
/// is a setting of its own — Emphasize keeps the deep red, Follow usage
/// walks the same ladder at 100%, Quiet is a muted grey — and none of them
/// may move the amber→red step.
@Suite("Usage tint")
struct UsageTintTests {
    private static func colour(
        _ used: Double,
        warningAt: WarningThreshold,
        spent: Bool = false,
        spentAs: SpentRingColour = .emphasize
    ) -> Color {
        UsageTint.color(
            for: used,
            isExhausted: spent,
            warningAt: warningAt.fraction,
            spentAs: spentAs
        )
    }

    @Test("the warning step is where the setting puts it")
    func warningFollowsTheSetting() {
        #expect(Self.colour(0.76, warningAt: .seventyFive) == .pulseWarning)
        #expect(Self.colour(0.76, warningAt: .eighty) == .pulseCaution)
        #expect(Self.colour(0.86, warningAt: .eightyFive) == .pulseWarning)
        #expect(Self.colour(0.61, warningAt: .sixty) == .pulseWarning)
    }

    @Test("red starts at the selected threshold, not one step after it")
    func warningBoundary() {
        for threshold in WarningThreshold.allCases {
            #expect(Self.colour(threshold.fraction.nextDown, warningAt: threshold) == .pulseCaution)
            #expect(Self.colour(threshold.fraction, warningAt: threshold) == .pulseWarning)
        }
    }

    @Test("the caution step does not move with it")
    func cautionStaysPut() {
        for threshold in WarningThreshold.allCases {
            #expect(Self.colour(0.49, warningAt: threshold) == .pulseGood)
            #expect(Self.colour(0.5, warningAt: threshold) == .pulseCaution)
        }
    }

    @Test("every offered figure sits above the caution step")
    func optionsClearCaution() {
        for threshold in WarningThreshold.allCases {
            #expect(threshold.fraction > UsageTint.cautionThreshold)
        }
    }

    @Test("Emphasize is not a matter of where red begins")
    func emphasizeIgnoresTheSetting() {
        #expect(Self.colour(0.1, warningAt: .ninety, spent: true) == .pulseExhausted)
        #expect(Self.colour(1, warningAt: .ninety) == .pulseExhausted)
    }

    @Test("Follow usage colours a spent limit like any other 100%")
    func followUsageUsesTheLadderAtFull() {
        for threshold in WarningThreshold.allCases {
            #expect(Self.colour(0.1, warningAt: threshold, spent: true, spentAs: .followUsage) == .pulseWarning)
            #expect(Self.colour(1, warningAt: threshold, spentAs: .followUsage) == .pulseWarning)
        }
    }

    @Test("Quiet colours a spent limit in the muted grey")
    func quietUsesTheMutedGrey() {
        #expect(Self.colour(0.1, warningAt: .ninety, spent: true, spentAs: .quiet) == .pulseQuiet)
        #expect(Self.colour(1, warningAt: .sixty, spentAs: .quiet) == .pulseQuiet)
    }

    @Test("Follow usage and Quiet leave an unspent reading on the ladder")
    func unspentStillFollowsTheLadder() {
        #expect(Self.colour(0.2, warningAt: .seventyFive, spentAs: .followUsage) == .pulseGood)
        #expect(Self.colour(0.2, warningAt: .seventyFive, spentAs: .quiet) == .pulseGood)
        #expect(Self.colour(0.76, warningAt: .seventyFive, spentAs: .followUsage) == .pulseWarning)
        #expect(Self.colour(0.76, warningAt: .eighty, spentAs: .quiet) == .pulseCaution)
    }

    @Test("the shipped defaults are the figures they always were")
    func defaultsAreUnchanged() {
        #expect(UsageTint.warningThreshold == 0.75)
        #expect(WarningThreshold.default == .seventyFive)
        #expect(SpentRingColour.default == .emphasize)
        #expect(AppSettings().spentRingColour == .emphasize)
    }
}
