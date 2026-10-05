import Foundation
import Testing
@testable import Pulse

/// DeepSeek's console, read with its sign-in: the token out of the console's
/// storage wrapper, the envelope's verdicts, and day buckets into a ledger.
/// Shapes are the console bundle's own; nothing here is anybody's account.
@Suite("DeepSeek console")
struct DeepSeekConsoleTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }()

    /// 2026-10-03 15:00 at +08:00.
    private static let now = Date(timeIntervalSince1970: 1_791_010_800)
    private static var today: Date { calendar.startOfDay(for: now) }
    private static func day(_ offset: Int) -> Double {
        calendar.date(byAdding: .day, value: offset, to: today)!.timeIntervalSince1970
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("The token is the storage wrapper's value; signed out or empty is none")
    func token() {
        #expect(DeepSeekConsole.token(fromStorage: ["userToken": #"{"value":"abc123","__version":"0"}"#]) == "abc123")
        #expect(DeepSeekConsole.token(fromStorage: ["userToken": #"{"value":null,"__version":"0"}"#]) == nil)
        #expect(DeepSeekConsole.token(fromStorage: ["userToken": #"{"value":"  ","__version":"0"}"#]) == nil)
        #expect(DeepSeekConsole.token(fromStorage: ["userToken": "abc123"]) == nil)
        #expect(DeepSeekConsole.token(fromStorage: [:]) == nil)
    }

    @Test("A refused token answers HTTP 200 with a 400xx code, and that is signed out")
    func envelope() throws {
        typealias E = DeepSeekConsole.Envelope<DeepSeekConsole.Summary>
        let missing = try Self.decode(E.self, #"{"code":40002,"msg":"Missing Token","data":null}"#)
        #expect(DeepSeekConsole.outcome(of: missing).failure == .signedOut)
        let invalid = try Self.decode(E.self, #"{"code":40003,"msg":"Authorization Failed (invalid token)","data":null}"#)
        #expect(DeepSeekConsole.outcome(of: invalid).failure == .signedOut)
        let broken = try Self.decode(E.self, #"{"code":50000,"msg":"x","data":null}"#)
        #expect(DeepSeekConsole.outcome(of: broken).failure == .failed)
        let refusedBiz = try Self.decode(E.self, #"{"code":0,"data":{"biz_code":1,"biz_data":null}}"#)
        #expect(DeepSeekConsole.outcome(of: refusedBiz).failure == .failed)
        let fine = try Self.decode(E.self, #"{"code":0,"data":{"biz_code":0,"biz_data":{"normal_wallets":[],"bonus_wallets":[]}}}"#)
        #expect(DeepSeekConsole.outcome(of: fine).failure == nil)
    }

    @Test("The range is the console's last 30 days, whole local days, tz in whole hours")
    func range() throws {
        let items = try #require(DeepSeekConsole.range(endingAt: Self.now, calendar: Self.calendar))
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values["start"] == String(Int(Self.day(-29))))
        #expect(values["end"] == String(Int(Self.day(1))))
        #expect(values["tz"] == "28800")

        // India: the hour below, the half hour moved into the range.
        var india = Calendar(identifier: .gregorian)
        india.timeZone = TimeZone(secondsFromGMT: 5 * 3600 + 1800)!
        let off = try #require(DeepSeekConsole.range(endingAt: Self.now, calendar: india))
        let start = Int(india.date(byAdding: .day, value: -29, to: india.startOfDay(for: Self.now))!.timeIntervalSince1970)
        #expect(off.first { $0.name == "tz" }?.value == "18000")
        #expect(off.first { $0.name == "start" }?.value == String(start + 1800))
    }

    @Test("Day buckets become thirty ledger days with kinds, models and the charged money")
    func ledger() throws {
        let amount = try Self.decode(DeepSeekConsole.Envelope<DeepSeekConsole.Amount>.self, """
        {"code":0,"data":{"biz_code":0,"biz_data":{"start":\(Int(Self.day(-29))),"end":\(Int(Self.day(1))),"bucket":86400,
          "models":["deepseek-chat","deepseek-reasoner"],
          "series":[
            {"api_key":{"tracking_id":"k1","name":"a","sensitive_id":"sk-1***","valid":true},"model":"deepseek-chat",
             "buckets":[{"time":\(Int(Self.day(0))),"usage":{"PROMPT_CACHE_HIT_TOKEN":800,"PROMPT_CACHE_MISS_TOKEN":150,"RESPONSE_TOKEN":50,"REQUEST":3}},
                        {"time":\(Int(Self.day(-2))),"usage":{"PROMPT_CACHE_HIT_TOKEN":0,"PROMPT_CACHE_MISS_TOKEN":0,"RESPONSE_TOKEN":0,"REQUEST":0}}]},
            {"api_key":{"tracking_id":"k2","name":"b","sensitive_id":"sk-2***","valid":true},"model":"deepseek-chat",
             "buckets":[{"time":\(Int(Self.day(0))),"usage":{"PROMPT_CACHE_HIT_TOKEN":"100","PROMPT_CACHE_MISS_TOKEN":"0","RESPONSE_TOKEN":"0","REQUEST":"1"}}]},
            {"api_key":{"tracking_id":"k1","name":"a","sensitive_id":"sk-1***","valid":true},"model":"deepseek-reasoner",
             "buckets":[{"time":\(Int(Self.day(-1))),"usage":{"PROMPT_CACHE_HIT_TOKEN":0,"PROMPT_CACHE_MISS_TOKEN":400,"RESPONSE_TOKEN":600,"REQUEST":2}}]}
          ]}}}
        """)
        let cost = try Self.decode(DeepSeekConsole.Envelope<DeepSeekConsole.Cost>.self, """
        {"code":0,"data":{"biz_code":0,"biz_data":{"start":0,"end":0,"bucket":86400,"models":[],
          "data":[
            {"currency":"USD","series":[]},
            {"currency":"CNY","series":[
              {"api_key":{"tracking_id":"k1"},"model":"deepseek-chat","buckets":[{"time":\(Int(Self.day(0))),"cost":"0.0125"}]},
              {"api_key":{"tracking_id":"k1"},"model":"deepseek-reasoner","buckets":[{"time":\(Int(Self.day(-1))),"cost":"1.5"}]}
            ]}
          ]}}}
        """)
        let ledger = DeepSeekConsole.ledger(
            amount: try #require(amount.data?.bizData), cost: try #require(cost.data?.bizData),
            preferring: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(ledger.origin == .providerLogs)
        #expect(ledger.currency == "CNY")
        #expect(ledger.slots.isEmpty)
        #expect(ledger.hasAggregateTiming)
        #expect(ledger.days.count == 30)
        #expect(ledger.days.first?.date == Self.calendar.date(byAdding: .day, value: -29, to: Self.today))

        let today = try #require(ledger.days.last)
        #expect(today.date == Self.today)
        // Two keys on one model, added; a string count read as a number.
        #expect(today.tally == TokenTally(input: 150, cacheWrite: 0, cacheRead: 900, output: 50))
        #expect(today.models == ["deepseek-chat": 1_100])
        #expect(abs(today.cost - 0.0125) < 1e-9)

        let yesterday = ledger.days[28]
        #expect(yesterday.tally == TokenTally(input: 400, cacheWrite: 0, cacheRead: 0, output: 600))
        #expect(abs(yesterday.cost - 1.5) < 1e-9)
        #expect(ledger.days[27].tokens == 0)
        #expect(ledger.earliest == yesterday.date)
    }

    @Test("The money follows the reader's currency, else the first with money in it")
    func currency() throws {
        let cost = try Self.decode(DeepSeekConsole.Cost.self, """
        {"data":[{"currency":"USD","series":[{"model":"m","buckets":[{"time":0,"cost":"0"}]}]},
                 {"currency":"CNY","series":[{"model":"m","buckets":[{"time":0,"cost":"2"}]}]}]}
        """)
        #expect(DeepSeekConsole.currency(of: cost, preferring: nil)?.currency == "CNY")
        // Nothing was charged in dollars: zeroes there would call the work free.
        #expect(DeepSeekConsole.currency(of: cost, preferring: "USD")?.currency == "CNY")
        #expect(DeepSeekConsole.currency(of: cost, preferring: "EUR")?.currency == "CNY")
        #expect(DeepSeekConsole.currency(of: .init(data: []), preferring: nil) == nil)

        let both = try Self.decode(DeepSeekConsole.Cost.self, """
        {"data":[{"currency":"CNY","series":[{"model":"m","buckets":[{"time":0,"cost":"2"}]}]},
                 {"currency":"USD","series":[{"model":"m","buckets":[{"time":0,"cost":"1"}]}]}]}
        """)
        #expect(DeepSeekConsole.currency(of: both, preferring: "USD")?.currency == "USD")
    }

    @Test("No money in the reply is tokens only, never a zero bill; bad numbers are absent, not a crash")
    func noMoney() throws {
        let amount = try Self.decode(DeepSeekConsole.Amount.self, """
        {"bucket":86400,"series":[{"model":"m","buckets":[
          {"time":\(Int(Self.day(0))),"usage":{"PROMPT_CACHE_HIT_TOKEN":"nan","PROMPT_CACHE_MISS_TOKEN":"1e30","RESPONSE_TOKEN":"inf"}},
          {"time":\(Int(Self.day(-1))),"usage":{"PROMPT_CACHE_HIT_TOKEN":0,"PROMPT_CACHE_MISS_TOKEN":10,"RESPONSE_TOKEN":5}}]}]}
        """)
        let ledger = DeepSeekConsole.ledger(
            amount: amount, cost: .init(data: []), preferring: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(ledger.origin == .providerStatistics)
        #expect(ledger.currency == nil)
        #expect(ledger.days.last?.tokens == 0)
        #expect(ledger.days[28].tokens == 15)
    }

    @Test("The wallets become the key route's reply: topped up plus granted, per currency")
    func wallets() throws {
        let summary = try Self.decode(DeepSeekConsole.Summary.self, """
        {"current_token":0,"monthly_usage":0,"total_usage":0,
         "normal_wallets":[{"balance":"8.15","currency":"CNY","token_estimation":"1"}],
         "bonus_wallets":[{"balance":"5.97","currency":"CNY","token_estimation":"1"},{"balance":"1","currency":"USD"}],
         "total_costs":[{"currency":"CNY","amount":"132.97"}]}
        """)
        let reply = DeepSeekConsole.reply(from: summary)
        #expect(reply.isAvailable == nil)
        let cny = try #require(DeepSeekUsageService.purse(from: reply, preferring: "CNY"))
        #expect(abs(cny.total - 14.12) < 1e-9)
        #expect(cny.toppedUp == 8.15)
        #expect(cny.granted == 5.97)
        let usd = try #require(DeepSeekUsageService.purse(from: reply, preferring: "USD"))
        #expect(usd.total == 1)
        #expect(usd.toppedUp == nil)

        // A wallet with no readable balance is left out, not read as zero.
        let blank = DeepSeekConsole.reply(from: try Self.decode(DeepSeekConsole.Summary.self,
            #"{"normal_wallets":[{"balance":null,"currency":"CNY"}],"bonus_wallets":[]}"#))
        #expect(DeepSeekUsageService.purse(from: blank, preferring: nil) == nil)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
