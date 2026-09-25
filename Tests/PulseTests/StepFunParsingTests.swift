import Foundation
import Testing
@testable import Pulse

/// StepFun's Step Plan is read from its console's own request, with the
/// browser session that console uses. `stepfun-token-plan.json` is a real reply
/// from a Token Plan (Plus), captured 2026-09-24; the top-up and Coding Plan
/// fixtures are written to the shape other monitors of this route recorded.
@Suite("StepFun")
struct StepFunParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    /// 2026-09-24T12:00Z, between the fixtures' activation and their expiry.
    private static let now = Date(timeIntervalSince1970: 1_790_236_800)

    // MARK: - The credential

    /// The session has published names, so nothing else the host set leaves.
    @Test("Only the console's own cookies are kept")
    func normalizeKeepsTheSession() throws {
        let kept = try StepFunCookie.normalize(
            "Cookie: _ga=GA1.1; Oasis-Token=abc...def; Hm_lvt=1; Oasis-Webid=w1; INGRESSCOOKIE=i1; lang=zh"
        )
        #expect(kept == "Oasis-Token=abc...def; Oasis-Webid=w1; INGRESSCOOKIE=i1")
    }

    @Test("No token is no session; a control character is refused")
    func normalizeRefusesWhatIsNotASession() {
        #expect(throws: StepFunError.invalidCookie) { try StepFunCookie.normalize("Oasis-Webid=w1; lang=zh") }
        #expect(throws: StepFunError.missingCookie) { try StepFunCookie.normalize("Cookie: ") }
        #expect(throws: StepFunError.invalidCookie) {
            try StepFunCookie.normalize("Oasis-Token=abc\r\nX-Injected: 1")
        }
    }

    /// A token sent from a device id other than its own is refused as stolen,
    /// so the id is the cookie's when there is one, and the token's claim when
    /// there is not.
    @Test("The device id comes from the cookie, else from the token")
    func webIDFollowsTheToken() {
        #expect(StepFunCookie.webID(in: "Oasis-Token=a.b.c; Oasis-Webid=w1") == "w1")

        let claims = Data(#"{"device_id":"dev-42"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        #expect(StepFunCookie.webID(in: "Oasis-Token=x.e30.y...h.\(claims).s") == "dev-42")
        #expect(StepFunCookie.webID(in: "Oasis-Token=opaque") == nil)
    }

    // MARK: - The Token Plan

    /// The real reply: a month's pool of 1.6 billion Credits, almost untouched,
    /// that ends with the subscription on 5 October and states no refill. One
    /// ring, no reset claimed, and the end date said as an expiry.
    @Test("A Token Plan's pool is one ring that says when it lapses")
    func tokenPlan() throws {
        let snapshot = try StepFunClient.parse(Self.fixture("stepfun-token-plan"))
        let windows = StepFunUsageService.windows(from: snapshot, at: Self.now)
        let window = try #require(windows.first)
        #expect(windows.count == 1)
        #expect(window.kind == .credits)
        #expect(abs(window.usedFraction - 86_166.0 / 1_600_000_000) < 1e-12)
        #expect(window.resetsAt == nil)
        #expect(!window.reportsLength)
        #expect(!window.isExhausted)
        #expect(window.nextExpiry == .init(amount: 1_599_913_834,
                                           at: Date(timeIntervalSince1970: 1_791_187_256)))
    }

    /// A pool and a pack are spent from one balance, so the ring is their sum;
    /// the pool's refill is a reset, and what lapses first is the pool's
    /// remainder.
    @Test("A top-up pack adds to the same ring")
    func tokenPlanWithTopUp() throws {
        let windows = StepFunUsageService.windows(
            from: try StepFunClient.parse(Self.fixture("stepfun-token-plan-topup")), at: Self.now)
        let window = try #require(windows.first)
        #expect(windows.count == 1)
        #expect(window.usedFraction == 0.45)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_790_582_456))
        #expect(window.nextExpiry == .init(amount: 40_000_000,
                                           at: Date(timeIntervalSince1970: 1_791_187_256)))
    }

    /// Everything zeroed: no window and no credit. The account has no plan,
    /// which is an answer, not a ring at 0% or 100%.
    @Test("A reply with nothing in it is no plan")
    func zeroedReplyIsNoPlan() {
        let empty = #"{"status":1,"five_hour_usage_left_rate":0,"five_hour_usage_reset_time":"0","weekly_usage_left_rate":0,"weekly_usage_reset_time":"0","plan_credit_rate_limit":{"subscription_credit_left_rate":0,"topup_credit_left_rate":0,"credit_buckets":[]}}"#
        #expect(throws: StepFunError.noPlan) { try StepFunClient.parse(Data(empty.utf8)) }
    }

    // MARK: - The Coding Plan

    /// A window counts only when it states a reset: that is how a Coding Plan
    /// is told from a Token Plan, whose windows come back as zero with "0".
    @Test("A Coding Plan's two windows, from the fraction left")
    func codingPlan() throws {
        let windows = StepFunUsageService.windows(
            from: try StepFunClient.parse(Self.fixture("stepfun-coding-plan")), at: Self.now)
        #expect(windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(windows[0].usedFraction == 0.25)
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1_790_250_000))
        #expect(windows[0].reportsLength)
        #expect(windows[1].usedFraction == 0)
        #expect(windows[1].resetsAt == Date(timeIntervalSince1970: 1_790_640_000))
    }

    // MARK: - Refusals and the plan's name

    @Test("A refusal inside a 200 is an expired session only when it says auth")
    func refusalInsideSuccess() {
        #expect(throws: StepFunError.sessionExpired) {
            try StepFunClient.parse(Data(#"{"status":0,"desc":"auth failed: token is invalid"}"#.utf8))
        }
        #expect(throws: StepFunError.unreadableReply) {
            try StepFunClient.parse(Data(#"{"status":0,"desc":"busy"}"#.utf8))
        }
        #expect(throws: StepFunError.unreadableReply) { try StepFunClient.parse(Data("<html>".utf8)) }
    }

    @Test("The plan's name comes from the status reply")
    func planName() throws {
        #expect(StepFunClient.planName(try Self.fixture("stepfun-plan-status")) == "Plus")
        #expect(StepFunClient.planName(Data(#"{"status":0}"#.utf8)) == nil)
    }

    @Test("Each site asks its own host")
    func sitesStayApart() {
        #expect(StepFunSite.china.endpoint("QueryStepPlanRateLimit").absoluteString
                == "https://platform.stepfun.com/api/step.openapi.devcenter.Dashboard/QueryStepPlanRateLimit")
        #expect(StepFunSite.international.host == "platform.stepfun.ai")
    }

    @Test("A missing session is said, not fetched")
    func missingSessionIsReported() async {
        let usage = await StepFunUsageService(cookie: nil, site: .china).fetch()
        #expect(usage.state == .unavailable(.stepFunSessionMissing))
        #expect(usage.sourceScope == nil)
    }
}
