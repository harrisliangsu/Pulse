import SwiftUI
import Testing
@testable import Pulse

/// Where the three usage colours change over.
///
/// The warning step is a setting now, so the thing worth pinning is that
/// moving it moves *only* that step: green and spent do not follow it around,
/// and every offered figure stays above the caution step it bounds.
@Suite("Usage tint")
struct UsageTintTests {
    private static func colour(_ used: Double, warningAt: WarningThreshold, spent: Bool = false) -> Color {
        UsageTint.color(for: used, isExhausted: spent, warningAt: warningAt.fraction)
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

    @Test("spent is not a matter of where red begins")
    func spentIgnoresTheSetting() {
        #expect(Self.colour(0.1, warningAt: .ninety, spent: true) == .pulseExhausted)
        #expect(Self.colour(1, warningAt: .ninety) == .pulseExhausted)
    }

    @Test("the shipped default is the figure it always was")
    func defaultIsUnchanged() {
        #expect(UsageTint.warningThreshold == 0.75)
        #expect(WarningThreshold.default == .seventyFive)
    }
}
