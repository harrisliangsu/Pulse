import Foundation
import Testing
@testable import Pulse

/// Which span the Token spend pane counts over, and that the reader's choice is
/// kept. The store is taken as an argument by `AppSettings.storedSpendSpan` /
/// `storeSpendSpan` — the same pair `restored()` and the `spendSpan` property
/// use — so the round trip is pinned against a suite of this test's own rather
/// than the app's real defaults.
@Suite("Spend span preference")
struct SpendSpanPreferenceTests {
    /// A `UserDefaults` domain owned by one test, emptied on the way out.
    ///
    /// Never `.standard`: writing there would leave a span behind for the app,
    /// and two tests could not run beside each other. Unique per call so
    /// parallel tests cannot see one another's value.
    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "PulseTests.spendSpan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test("A store nobody has chosen from counts a week")
    func unchosenCountsAWeek() {
        withIsolatedDefaults { defaults in
            #expect(SpendSpan.default == .week)
            #expect(AppSettings.storedSpendSpan(in: defaults) == .week)
            // An instance built without a stored value opens on the same week.
            #expect(AppSettings().spendSpan == .week)
        }
    }

    @Test("Every span the picker offers survives a round trip")
    func everyOfferedSpanIsKept() {
        withIsolatedDefaults { defaults in
            for span in SpendSpan.allCases {
                AppSettings.storeSpendSpan(span, in: defaults)
                #expect(AppSettings.storedSpendSpan(in: defaults) == span)
            }
        }
    }

    @Test("Today, once chosen, is what a later instance is built with")
    func aChosenSpanSurvives() {
        withIsolatedDefaults { defaults in
            AppSettings.storeSpendSpan(.today, in: defaults)

            // Reading again is what a launch does; the instance built from that
            // reading is what the pane then opens on.
            let restored = AppSettings(spendSpan: AppSettings.storedSpendSpan(in: defaults))
            #expect(restored.spendSpan == .today)
            // The read does not consume the choice.
            #expect(AppSettings.storedSpendSpan(in: defaults) == .today)
        }
    }

    @Test("A stored value the picker no longer offers falls back to the week")
    func anUnreadableStoredValueFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set("fortnight", forKey: AppSettings.spendSpanDefaultsKey)
            #expect(AppSettings.storedSpendSpan(in: defaults) == .week)
        }
    }
}
