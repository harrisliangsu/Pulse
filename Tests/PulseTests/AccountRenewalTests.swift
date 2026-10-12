import Foundation
import Testing
@testable import Pulse

/// When a renewal that comes back late may be written over what is stored —
/// the rule alone, never the user's own `accounts.dat`.
@Suite("Account renewal")
struct AccountRenewalTests {
    /// One sign-in unless told otherwise, as every renewal of a login is.
    private func login(_ minutes: Double, id: String? = "acct", signIn: String? = "first sign-in") -> AccountCredentials {
        var credentials = AccountCredentials(accessToken: "a\(minutes)", refreshToken: "r\(minutes)",
                                             expiresAt: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60), accountID: id)
        credentials.signIn = signIn
        return credentials
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

    @Test("A renewal still out when the slot was signed in to again is not written over the new login")
    func newSignInKept() {
        // Claude Code and Grok name no account, so only the sign-in tells
        // the old login's renewal from the new login.
        let old = login(0, id: nil)
        let signedInAgain = login(30, id: nil, signIn: "second sign-in")
        let lateRenewal = old.renewalOf(login(90, id: nil))
        #expect(!AccountCredentialStore.acceptsRenewal(lateRenewal, over: signedInAgain))
        // Its own login it still renews.
        #expect(AccountCredentialStore.acceptsRenewal(lateRenewal, over: old))
    }

    @Test("A login saved before sign-ins were recorded is still renewed, and both passes of it agree")
    func legacyLogin() throws {
        let legacy = login(0, id: nil, signIn: nil)
        let first = legacy.renewalOf(login(60, id: nil))
        let second = legacy.renewalOf(login(90, id: nil))
        #expect(first.signIn == second.signIn)
        #expect(AccountCredentialStore.acceptsRenewal(first, over: legacy))
        // The abandoned pass that answers later still wins, as before.
        #expect(AccountCredentialStore.acceptsRenewal(second, over: first))
        // An old file without the field decodes to nil, not to a fresh id.
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(login(0))) as? [String: Any])
        object["signIn"] = nil
        let decoded = try JSONDecoder().decode(AccountCredentials.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.signIn == nil)
    }
}
