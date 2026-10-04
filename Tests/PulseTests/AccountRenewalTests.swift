import Foundation
import Testing
@testable import Pulse

/// When a renewal that comes back late may be written over what is stored —
/// the rule alone, never the user's own `accounts.dat`.
@Suite("Account renewal")
struct AccountRenewalTests {
    private func login(_ minutes: Double, id: String? = "acct") -> AccountCredentials {
        AccountCredentials(accessToken: "a\(minutes)", refreshToken: "r\(minutes)",
                           expiresAt: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60), accountID: id)
    }

    @Test("A login removed while its renewal was out is not brought back")
    func removedStaysRemoved() {
        #expect(!AccountCredentialStore.acceptsRenewal(login(60), over: nil))
    }

    @Test("A newer renewal replaces the login it renews; an older one does not")
    func newerWins() {
        #expect(AccountCredentialStore.acceptsRenewal(login(60), over: login(0)))
        #expect(!AccountCredentialStore.acceptsRenewal(login(30), over: login(60)))
    }

    @Test("Another account signed in to the slot meanwhile is not overwritten")
    func otherAccountKept() {
        #expect(!AccountCredentialStore.acceptsRenewal(login(60, id: "first"), over: login(0, id: "second")))
    }
}
