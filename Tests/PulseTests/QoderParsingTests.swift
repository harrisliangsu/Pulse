import Foundation
import Testing
@testable import Pulse

/// Qoder's credits are read from its account page's own request, with the
/// browser session that page uses. The fixtures are sanitized from the shapes
/// other monitors of this route recorded — camelCase today, snake_case in an
/// earlier build — not from a capture made here.
@Suite("Qoder")
struct QoderParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static let resetDate = Date(timeIntervalSince1970: 1_725_148_800)

    // MARK: - The credential

    /// Qoder's session cookie has no published name, so the filter drops what
    /// third-party analytics set and keeps the rest of what the host set.
    @Test("Analytics cookies are dropped, the host's own are kept")
    func normalizeDropsAnalytics() throws {
        let kept = try QoderCookie.normalize(
            "_ga=GA1.1.9; _gcl_au=1.1; qoder_session=abc; Hm_lvt_x=1; cna=dev1; locale=zh"
        )
        #expect(kept == "qoder_session=abc; cna=dev1; locale=zh")
    }

    @Test("A pasted header is taken as pasted")
    func normalizeAcceptsAPastedHeader() throws {
        #expect(try QoderCookie.normalize("Cookie: sid=abc; lang=en") == "sid=abc; lang=en")
    }

    /// A value carrying a newline would end the header and start whatever came
    /// after it as a fresh one.
    @Test("A control character is refused, not forwarded")
    func normalizeRefusesControlCharacters() {
        #expect(throws: QoderError.invalidCookie) {
            try QoderCookie.normalize("sid=abc\r\nX-Injected: 1")
        }
    }

    @Test("Nothing but analytics is no session")
    func normalizeNeedsSomethingOfTheHost() {
        #expect(throws: QoderError.invalidCookie) { try QoderCookie.normalize("_ga=1; _gid=2") }
        #expect(throws: QoderError.missingCookie) { try QoderCookie.normalize("Cookie: ") }
    }

    /// The browser hands back a host-only and a domain row for one name; the
    /// first wins rather than the whole session being thrown away.
    @Test("A repeated name keeps the first")
    func normalizeKeepsFirstOfRepeatedName() throws {
        #expect(try QoderCookie.normalize("sid=first; sid=second") == "sid=first")
    }

    /// A console token is not a cookie. `normalize` would drop it.
    @Test("A personal token is recognised and left alone")
    func personalTokenIsNotACookie() {
        #expect(QoderCookie.accessToken(in: "pt-abc") == "pt-abc")
        #expect(QoderCookie.accessToken(in: "  jt-xyz ") == "jt-xyz")
        #expect(QoderCookie.accessToken(in: "sid=abc") == nil)
    }

    // MARK: - The reply

    @Test("The account's credits, with Qoder's own reset")
    func parsesCamelCase() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits"))
        #expect(snapshot.personal == .init(used: 125, limit: 500, remaining: 375))
        #expect(snapshot.shared == nil)
        #expect(snapshot.resetsAt == Self.resetDate)

        let windows = QoderUsageService.windows(from: snapshot)
        #expect(windows.count == 1)
        #expect(windows[0].kind == .credits)
        #expect(windows[0].usedFraction == 0.25)
        #expect(windows[0].resetsAt == Self.resetDate)
        #expect(!windows[0].reportsLength)
        #expect(!windows[0].isExhausted)
    }

    /// The earlier build's field names, and a reset stated in milliseconds.
    /// `total_quota` already includes the plan and the packs, so those two are
    /// not added on top.
    @Test("The snake_case reply reads the same")
    func parsesSnakeCase() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-snake"))
        #expect(snapshot.personal == .init(used: 125, limit: 500, remaining: 375))
        #expect(snapshot.resetsAt == Self.resetDate)
    }

    /// A spent personal allowance beside a team pool with room in it. Summed,
    /// they read as 68% — "plenty left" about the pool that is actually
    /// stopping the reader. Two rings, and the personal one says spent.
    @Test("A team pool is a second ring, never a sum")
    func teamPoolIsItsOwnRing() throws {
        let windows = QoderUsageService.windows(from: try QoderClient.parse(Self.fixture("qoder-credits-team")))
        #expect(windows.map(\.kind) == [.credits, .sharedCredits])
        #expect(windows[0].usedFraction == 1)
        #expect(windows[0].isExhausted)
        #expect(windows[1].usedFraction == 0.2)
        #expect(!windows[1].isExhausted)
        // Qoder states the account's reset, not the team's.
        #expect(windows[1].resetsAt == nil)
    }

    /// A limit of zero is an account with nothing granted. Not a ring at 100%,
    /// which would say something was spent.
    @Test("No credits at all draws nothing")
    func zeroLimitDrawsNothing() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-none"))
        #expect(snapshot.shared == nil)
        #expect(QoderUsageService.windows(from: snapshot).isEmpty)
    }

    @Test("A reply without the account's summary is unreadable, not empty")
    func missingSummaryIsUnreadable() {
        #expect(throws: QoderError.unreadableReply) {
            try QoderClient.parse(Data(#"{"quotaKey":"big_model_credits"}"#.utf8))
        }
        #expect(throws: QoderError.unreadableReply) {
            try QoderClient.parse(Data("<html>sign in</html>".utf8))
        }
        #expect(throws: QoderError.unreadableReply) {
            try QoderClient.parse(Data(#"{"totalQuota":{"quotaSummary":{"usedValue":-1,"limitValue":5}}}"#.utf8))
        }
    }

    /// Without a remainder the arithmetic decides; with one, Qoder's word does.
    @Test("Spent follows Qoder's remainder when it gives one")
    func exhaustionFollowsTheRemainder() {
        let stated = QoderSnapshot(personal: .init(used: 10, limit: 10, remaining: 3), shared: nil, resetsAt: nil)
        #expect(QoderUsageService.windows(from: stated).first?.isExhausted == false)
        let silent = QoderSnapshot(personal: .init(used: 10, limit: 10, remaining: nil), shared: nil, resetsAt: nil)
        #expect(QoderUsageService.windows(from: silent).first?.isExhausted == true)
    }

    /// A pack bought on top raises the limit, and the fraction falls with
    /// nothing reset. Only Qoder's reset date moving forward says it turned
    /// over — otherwise a purchase would be announced as a reset.
    @Test("A pack bought on top is not a reset")
    func purchaseIsNotAReset() throws {
        let before = Date(timeIntervalSince1970: 1_725_148_800)
        let bought = QoderSnapshot(personal: .init(used: 450, limit: 2_500, remaining: 2_050),
                                   shared: nil, resetsAt: before)
        let window = try #require(QoderUsageService.windows(from: bought).first)
        #expect(!window.hasTurnedOver(since: 0.9, resetsAt: before))

        let team = QoderSnapshot(personal: .init(used: 0, limit: 10, remaining: 10),
                                 shared: .init(used: 10, limit: 5_000, remaining: 4_990), resetsAt: nil)
        let shared = try #require(QoderUsageService.windows(from: team).last)
        #expect(!shared.hasTurnedOver(since: 0.9, resetsAt: nil))

        let renewed = QoderSnapshot(personal: .init(used: 5, limit: 500, remaining: 495),
                                    shared: nil, resetsAt: before.addingTimeInterval(30 * 86_400))
        let next = try #require(QoderUsageService.windows(from: renewed).first)
        #expect(next.hasTurnedOver(since: 0.9, resetsAt: before))
    }

    // MARK: - Sites

    @Test("Each site asks its own host, and only its own")
    func sitesStayApart() {
        #expect(QoderSite.international.usageURL.absoluteString == "https://qoder.com/api/v2/me/usages/big_model_credits")
        #expect(QoderSite.china.usageURL.absoluteString == "https://qoder.com.cn/api/v2/me/usages/big_model_credits")
        #expect(QoderSite.china.accountPage.absoluteString == "https://qoder.com.cn/account/usage")
    }

    @Test("A missing session is said, not fetched")
    func missingSessionIsReported() async {
        let usage = await QoderUsageService(cookie: nil, site: .international).fetch()
        #expect(usage.state == .unavailable(.qoderSessionMissing))
        #expect(usage.sourceScope == nil)
    }
}
