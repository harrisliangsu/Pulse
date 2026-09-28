import Foundation
import Testing
@testable import Pulse

/// Qwen Cloud's individual Token Plan, read from its console with a browser
/// session.
///
/// **The fixtures are second-hand**: written from CodexBar's Qwen Cloud and
/// Alibaba Token Plan providers and their tests (MIT), not captured from a
/// live account. They pin the shape Pulse reads; they do not prove it right.
@Suite("Qwen Cloud")
struct QwenCloudTests {
    private let context = ProfileContext(provider: .qwenCloud, credential: "login_qwencloud_ticket=t", serverAddress: nil)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func reading(_ json: String) -> ProviderUsage {
        QwenCloudUsageService.reading(from: Data(json.utf8), context: context, now: now)
    }

    @Test("The windows are read as the shares the console reports, through its nested envelope")
    func windows() throws {
        let usage = QwenCloudUsageService.reading(from: try fixture("qwen-cloud-usage"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.qwenCloud))
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(usage.windows.map(\.usedFraction) == [0.03, 0.01])
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_700_003_600))
        #expect(usage.windows[1].resetsAt == Date(timeIntervalSince1970: 1_700_086_400))
    }

    @Test("A monthly window is read without claiming a length")
    func monthly() {
        let usage = reading(#"{"data":{"per1MonthPercentage":0.4,"per1MonthResetTime":1701000000000}}"#)
        #expect(usage.windows.map(\.kind) == [.monthly])
        #expect(usage.windows[0].reportsLength == false)
    }

    @Test("The subscription names the tier as the page spells it")
    func plan() throws {
        #expect(QwenCloudUsageService.planName(from: try fixture("qwen-cloud-subscription")) == "Standard")
        #expect(QwenCloudUsageService.planName(from: Data("{}".utf8)) == nil)
    }

    @Test("An account that counts no subscription has no plan")
    func noSubscription() throws {
        let usage = QwenCloudUsageService.reading(
            from: try fixture("qwen-cloud-no-subscription"), context: context, now: now)
        #expect(usage.state == .unavailable(.noPlan))
    }

    @Test("A console that wants a sign-in, or refuses the session, is an expired session", arguments: [
        #"{"code":"ConsoleNeedLogin","message":"You need to log in.","successResponse":false}"#,
        #"{"statusCode":403,"message":"Forbidden"}"#,
        #"{"code":"200","data":{"success":false,"errorCode":"PostonlyOrTokenError","errorMsg":"refresh page"},"successResponse":true}"#,
    ])
    func signedOut(json: String) {
        #expect(reading(json).state == .unavailable(.sessionExpired))
    }

    @Test("A workspace the account may not use is a failure, not a session to renew")
    func workspace() {
        let json = #"{"code":"200","data":{"success":false,"errorCode":"BailianGateway.Workspace.NotAuthorised"},"successResponse":true}"#
        #expect(reading(json).state == .unavailable(.serverError))
    }

    @Test("A reply that can't be read, and a sign-in page in its place")
    func unreadable() {
        #expect(reading("not-json").state == .unavailable(.unreadableReply))
        let page = "<html><a href=\"https://passport.alibabacloud.com/login\">Sign in</a></html>"
        #expect(reading(page).state == .unavailable(.sessionExpired))
    }

    @Test("A figure that isn't one is left off, and nothing left is no limits")
    func noFigures() {
        #expect(reading(#"{"data":{"per5HourPercentage":-0.2,"per1WeekPercentage":null}}"#).state
            == .unavailable(.noLimitsReported))
    }

    @Test("The page's security token is found in the forms the console writes it")
    func securityToken() {
        #expect(QwenCloudUsageService.securityToken(inPage: #"<script>sec_token = "abc+/=";</script>"#) == "abc+/=")
        #expect(QwenCloudUsageService.securityToken(inPage: #"{"secToken":"xyz"}"#) == "xyz")
        #expect(QwenCloudUsageService.securityToken(inPage: "<html></html>") == nil)
    }

    @Test("The form keeps reserved characters in the token and the JSON as themselves")
    func form() {
        let body = QwenCloudUsageService.form([("sec_token", "a+b&c=d/東"), ("params", #"{"Api":"x"}"#)])
        #expect(String(decoding: body, as: UTF8.self)
            == "sec_token=a%2Bb%26c%3Dd%2F%E6%9D%B1&params=%7B%22Api%22%3A%22x%22%7D")
    }

    @Test("The gateway request goes to Qwen Cloud's own host with the session and its CSRF token")
    func request() throws {
        let cookie = "login_qwencloud_ticket=t; login_aliyunid_csrf=c1; cna=anon"
        let request = QwenCloudUsageService.request(QwenCloudUsageService.usageAPI, data: [:], token: "tok", cookie: cookie)
        #expect(request.url?.host == "cs-data.qwencloud.com")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Cookie") == cookie)
        #expect(request.value(forHTTPHeaderField: "x-csrf-token") == "c1")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("sec_token=tok"))
        #expect(body.contains("product=sfm_bailian"))
        #expect(body.contains("X-Anonymous-Id%22%3A%22anon"))
    }

    @Test("Only the named cookies leave the browser, and not without a sign-in ticket")
    func cookies() {
        let header = "login_qwencloud_ticket=t; tracking=x; cna=anon"
        #expect(ProviderProfile.keep(header, cookies: QwenCloudUsageService.cookies) == "login_qwencloud_ticket=t; cna=anon")
        #expect(ProviderProfile.keep("cna=anon", cookies: QwenCloudUsageService.cookies) == nil)
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .qwenCloud, credential: nil, serverAddress: nil)
        #expect(await QwenCloudUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }
}
