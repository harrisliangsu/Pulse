import Foundation
import Testing
@testable import Pulse

/// How long the refresh loop's timer waits.
@Suite("Refresh timer")
struct RefreshTimerTests {
    @Test("With only added accounts on the rail, the chosen interval still holds")
    func addedAccountsOnly() {
        #expect(UsageStore.timerWait(primaryWaits: [], fixed: 60, adaptive: 1_800) == 60)
    }

    @Test("Automatic, with nothing primary, falls to the adaptive interval")
    func automatic() {
        #expect(UsageStore.timerWait(primaryWaits: [], fixed: nil, adaptive: 600) == 600)
    }

    @Test("The soonest primary account sets the alarm, never under fifteen seconds")
    func soonestPrimary() {
        #expect(UsageStore.timerWait(primaryWaits: [40, 200], fixed: 60, adaptive: 1_800) == 40)
        #expect(UsageStore.timerWait(primaryWaits: [0], fixed: 60, adaptive: 1_800) == 15)
    }
}
