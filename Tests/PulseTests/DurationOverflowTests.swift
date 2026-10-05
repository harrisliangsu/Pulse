import Foundation
import Testing
@testable import Pulse

/// A stated duration that overflows its unit drops the window rather than
/// trapping the process. Each case goes through the reader's own parsing.
@Suite("Duration overflow")
struct DurationOverflowTests {
    private static let huge = Int.max

    @Test("The shared length is checked for overflow and for any plausible window")
    func length() {
        #expect(UsageWindow.length(5, unitSeconds: 3_600) == 18_000)
        #expect(UsageWindow.length(Self.huge, unitSeconds: 86_400) == nil)
        #expect(UsageWindow.length(11 * 366, unitSeconds: 86_400) == nil)
        #expect(UsageWindow.length(0, unitSeconds: 60) == nil)
    }

    @Test("Kimi: a window whose duration overflows is dropped")
    func kimi() throws {
        let json = """
        {"limits":[
          {"window":{"duration":\(Self.huge),"timeUnit":"TIME_UNIT_DAY"},
           "detail":{"limit":"10","used":"1","resetTime":"2026-10-01T00:00:00.000Z"}},
          {"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},
           "detail":{"limit":"10","used":"1","resetTime":"2026-10-01T00:00:00.000Z"}}
        ]}
        """
        let reply = try JSONDecoder().decode(KimiCodeUsageService.Reply.self, from: Data(json.utf8))
        let windows = KimiCodeUsageService.windows(from: reply)
        #expect(windows.map(\.windowSeconds) == [18_000])
    }

    @Test("Z.ai: a limit whose number overflows its unit is dropped")
    func zai() throws {
        let json = """
        {"code":200,"data":{"limits":[
          {"type":"TOKENS_LIMIT","unit":1,"number":\(Self.huge),"percentage":10},
          {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":10}
        ]},"success":true}
        """
        let reply = try JSONDecoder().decode(ZaiUsageService.Reply.self, from: Data(json.utf8))
        let windows = ZaiUsageService.windows(from: try #require(reply.data?.limits), provider: .glmCoding)
        #expect(windows.map(\.windowSeconds) == [5 * 3_600])
    }

    @Test("LiteLLM: an overflowing budget duration is an unstated period")
    func liteLLM() {
        let period = LiteLLMUsageService.period("\(Self.huge)d")
        #expect(period.stated == false)
        #expect(LiteLLMUsageService.period("\(Self.huge)mo").stated == false)
        #expect(LiteLLMUsageService.period("7d").seconds == 7 * 86_400)
    }

    @Test("JetBrains: an overflowing ISO duration is not a length")
    func jetBrains() {
        #expect(JetBrainsAIUsageService.seconds(fromISODuration: "P\(Self.huge)D") == nil)
        #expect(JetBrainsAIUsageService.seconds(fromISODuration: "P99999999999999999999D") == nil)
        #expect(JetBrainsAIUsageService.seconds(fromISODuration: "P1DT12H") == 36 * 3_600)
    }
}
