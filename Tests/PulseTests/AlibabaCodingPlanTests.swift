import Foundation
import Testing
@testable import Pulse

/// Alibaba Coding Plan's quota, read with an API key from the Model Studio
/// console.
///
/// **The fixture is second-hand**: written from CodexBar's Alibaba provider
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("Alibaba Coding Plan")
struct AlibabaCodingPlanTests {
    private let context = ProfileContext(provider: .alibabaCodingPlan, credential: "key", serverAddress: nil)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func answer(_ json: String) -> AlibabaCodingPlanUsageService.Answer {
        AlibabaCodingPlanUsageService.answer(from: Data(json.utf8), context: context, now: now)
    }

    @Test("The active plan's three allowances are read as used over total, shortest first")
    func allowances() throws {
        let usage = AlibabaCodingPlanUsageService.reading(
            from: try fixture("alibaba-coding-plan-instances"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.alibabaCodingPlan))
        #expect(usage.plan == "Alibaba Coding Plan Pro")
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        let expected: [Double] = [52.0 / 1_000, 800.0 / 5_000, 1_200.0 / 20_000]
        #expect(usage.windows.map(\.usedFraction) == expected)
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_700_000_300))
        #expect(usage.windows[1].resetsAt == Date(timeIntervalSince1970: 1_700_100_000))
        // A billing month is not a stated length.
        #expect(usage.windows.map(\.reportsLength) == [true, true, false])
    }

    @Test("A reply carried as a JSON string inside the envelope is read the same")
    func wrapped() throws {
        let inner = #"{"data":{"codingPlanInstanceInfos":[{"planName":"Coding Plan Lite","status":"VALID","codingPlanQuotaInfo":{"per5HourUsedQuota":0,"per5HourTotalQuota":1000,"per5HourQuotaNextRefreshTime":1700000300000}}]},"statusCode":200}"#
        let wrapped = try JSONSerialization.data(withJSONObject: ["successResponse": ["body": inner]])
        let usage = AlibabaCodingPlanUsageService.reading(from: wrapped, context: context, now: now)
        #expect(usage.plan == "Coding Plan Lite")
        #expect(usage.windows.map(\.usedFraction) == [0])
    }

    @Test("A reset already past is dropped, not moved forward five hours")
    func staleReset() {
        let result = answer(#"{"codingPlanQuotaInfo":{"per5HourUsedQuota":10,"per5HourTotalQuota":100,"per5HourQuotaNextRefreshTime":1699999000000}}"#)
        guard case .usage(let usage) = result else { Issue.record("expected a reading"); return }
        #expect(usage.windows.count == 1)
        #expect(usage.windows[0].resetsAt == nil)
    }

    @Test("A figure that isn't one is left off, and nothing left is worth asking the other site about")
    func missingFigures() {
        let json = #"{"codingPlanQuotaInfo":{"per5HourUsedQuota":10,"perWeekUsedQuota":-4,"perWeekTotalQuota":100,"perBillMonthUsedQuota":3,"perBillMonthTotalQuota":0}}"#
        #expect(answer(json) == .askOtherSite(.noLimitsReported))
    }

    @Test("A plan list that is empty or only lapsed says there is no plan", arguments: [
        #"{"data":{"codingPlanInstanceInfos":[]},"status_code":0}"#,
        #"{"data":{"codingPlanInstanceInfos":[{"planName":"Old","status":"EXPIRED"}]},"status_code":0}"#,
    ])
    func noPlan(json: String) {
        #expect(answer(json) == .askOtherSite(.noPlan))
    }

    @Test("A plan with no figures is not a plan with no limits said as zero")
    func planWithoutFigures() {
        let json = #"{"data":{"codingPlanInstanceInfos":[{"planName":"Pro","planUsage":"18%"}]},"status_code":0}"#
        #expect(answer(json) == .askOtherSite(.noLimitsReported))
    }

    @Test("A reply that can't be read", arguments: ["not json", "[]", "\"text\""])
    func unreadable(json: String) {
        #expect(answer(json) == .final(.unreadableReply))
    }

    @Test("A key the route won't take for this account is said as refused, and not retried")
    func consoleOnly() {
        #expect(answer(#"{"code":"ConsoleNeedLogin","message":"You need to log in.","successResponse":false}"#)
            == .final(.apiKeyRefused))
    }

    @Test("Refusals in the body are asked of the other site; other failures are not", arguments: [
        (#"{"status_code":401,"message":"Unauthorized"}"#, AlibabaCodingPlanUsageService.Answer.askOtherSite(.apiKeyRefused)),
        (#"{"statusCode":400,"message":"Invalid API key"}"#, .askOtherSite(.apiKeyRefused)),
        (#"{"status_code":500,"message":"Internal"}"#, .final(.serverError)),
    ])
    func bodyStatus(json: String, expected: AlibabaCodingPlanUsageService.Answer) {
        #expect(answer(json) == expected)
    }

    @Test("The request carries the key to the console it names, with that console's plan code")
    func request() throws {
        for site in [AlibabaCodingPlanUsageService.Site.international, .chinaMainland] {
            let request = AlibabaCodingPlanUsageService.request(site, key: "sk-test")
            #expect(request.url?.host == URL(string: site.origin)?.host)
            #expect(request.url?.path == "/data/api.json")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            #expect(request.value(forHTTPHeaderField: "X-DashScope-API-Key") == "sk-test")
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: [String: String]])
            #expect(json["queryCodingPlanInstanceInfoRequest"]?["commodityCode"] == site.commodityCode)
        }
        #expect(AlibabaCodingPlanUsageService.Site.international.endpoint.host == "modelstudio.console.alibabacloud.com")
        #expect(AlibabaCodingPlanUsageService.Site.chinaMainland.endpoint.host == "bailian.console.aliyun.com")
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .alibabaCodingPlan, credential: " ", serverAddress: nil)
        #expect(await AlibabaCodingPlanUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
