import Foundation
import Testing
@testable import Pulse

/// Replicate's billing page and credit balance, read with a browser session.
///
/// **The fixtures are second-hand**: the balance reply and the billing-page
/// snippets below are written from CodexBar's Replicate plugin and its tests
/// (MIT), not captured from a live account. They pin the shape Pulse reads;
/// they do not prove the shape is right.
@Suite("Replicate")
struct ReplicateTests {
    private let context = ProfileContext(provider: .replicate, credential: "sessionid=s", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private static let userPage = #"""
    <html><head><title>Billing | Replicate</title></head><body>
    <script type="application/json" id="react-component-props-billing-page">
    {"page":{"account":{"kind":"user","username":"demo-user"}}}
    </script></body></html>
    """#

    @Test("The balance is read as reported, in dollars, with no ring")
    func balance() throws {
        let usage = ReplicateUsageService.reading(from: try fixture("replicate-unused-credit"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.replicate))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 80, currency: "USD"))
        #expect(usage.creditBalance == ReplicateUsageService.money(80))
    }

    @Test("The billing page names a user's account")
    func userAccount() {
        let account = ReplicateUsageService.account(inBillingPage: Self.userPage)
        #expect(account == .found(.init(isOrganization: false, username: "demo-user")))
        guard case .found(let found) = account else { return }
        #expect(found.creditURL.absoluteString == "https://replicate.com/api/users/demo-user/unused-credit")
    }

    @Test("An organization nested deeper in other props is found, and asked for as one")
    func organization() {
        let page = #"""
        <script id='react-component-props-layout' type='application/json'>
        {"layout":{"nested":[{"x":1},{"account":{"kind":"organization","username":"demo org"}}]}}
        </script>
        """#
        guard case .found(let found) = ReplicateUsageService.account(inBillingPage: page) else {
            Issue.record("The organization should be found")
            return
        }
        #expect(found.creditURL.absoluteString == "https://replicate.com/api/organizations/demo%20org/unused-credit")
    }

    @Test("Props in any other script are not trusted")
    func otherScripts() {
        let page = #"""
        <script type="application/json" id="analytics">{"account":{"kind":"user","username":"someone"}}</script>
        <script id="react-component-props-x">{"account":{"kind":"user","username":"no-type"}}</script>
        """#
        #expect(ReplicateUsageService.account(inBillingPage: page) == .unrecognized)
    }

    @Test("Replicate's sign-in page is a lapsed session, not a changed page")
    func signedOut() {
        let page = #"""
        <html><head><title>Sign in | Replicate</title></head>
        <body><a class="btn" href="/login/github/?next=/account/billing">Sign in with GitHub</a></body></html>
        """#
        #expect(ReplicateUsageService.account(inBillingPage: page) == .signedOut)
        #expect(ReplicateUsageService.account(inBillingPage: "<title>Sign in | Replicate</title>") == .unrecognized)
    }

    @Test("A balance that isn't one can't be read", arguments: [
        #"{"unused_credit":"NaN"}"#, #"{"unused_credit":"-1"}"#, #"{"unused_credit":""}"#,
        #"{"unused_credit":true}"#, #"{"unused_credit":-3}"#, "<html>unavailable</html>", "[]",
    ])
    func unreadable(json: String) {
        let usage = ReplicateUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("No balance reported is nothing to show, not a zero")
    func noBalance() {
        #expect(ReplicateUsageService.reading(from: Data("{}".utf8), context: context).state
            == .unavailable(.noLimitsReported))
        #expect(ReplicateUsageService.reading(from: Data(#"{"unused_credit":12.5}"#.utf8), context: context)
            .creditRemaining?.amount == 12.5)
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .replicate, credential: " ", serverAddress: nil)
        #expect(await ReplicateUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }

    @Test("Only the session cookies are kept from the browser")
    func keptCookies() {
        guard case .sessionCookie(let host, let cookies) = ProviderProfile.replicate.credential else {
            Issue.record("Replicate reads a browser session")
            return
        }
        #expect(host == "replicate.com")
        #expect(ProviderProfile.keep("_ga=1; sessionid=abc; csrftoken=t", cookies: cookies)
            == "sessionid=abc; csrftoken=t")
        #expect(ProviderProfile.keep("csrftoken=t", cookies: cookies) == nil)
    }

    @Test("A refused session has expired", arguments: [401, 403])
    func refused(status: Int) {
        let result = ProfileHTTP.classify(.init(data: Data(), status: status), refused: .sessionExpired)
        #expect(result == .failure(.sessionExpired))
    }
}
