import Foundation
import Testing
@testable import Pulse

/// LongCat's token allowance and fuel packs, read from its platform with a
/// browser session.
///
/// **The fixtures are second-hand**: written from CodexBar's LongCat provider
/// and its tests (MIT), not captured from a live account. They pin the shape
/// Pulse reads; they do not prove it right.
@Suite("LongCat")
struct LongCatTests {
    private let context = ProfileContext(provider: .longCat, credential: "passport_token=t", serverAddress: nil)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func payload(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try LongCatUsageService.payload(of: Data(contentsOf: url)).get()
    }

    private func payload(json: String) throws -> [String: Any] {
        try LongCatUsageService.payload(of: Data(json.utf8)).get()
    }

    @Test("An active token pack and the fuel packs are read as used over their stated totals")
    func packs() throws {
        let usage = LongCatUsageService.reading(
            packs: try payload("longcat-token-packs"), tokenUsage: nil,
            fuel: try payload("longcat-fuel-packages"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.longCat))
        #expect(usage.windows.map(\.kind) == [.credits, .topUp])
        #expect(usage.windows[0].usedFraction == 1_212_576.0 / 50_000_000)
        // 1,000 in all, 600 + 150 left.
        #expect(usage.windows[1].usedFraction == 0.25)
        #expect(usage.windows.allSatisfy { $0.resetsAt == nil && !$0.reportsLength })
        let expiry = try #require(usage.windows[1].nextExpiry)
        #expect(expiry.amount == 600)
        #expect(expiry.at == Date(timeIntervalSince1970: 1_750_000_000))
    }

    @Test("Without an active pack, the older route's allowance is read")
    func legacy() throws {
        let usage = LongCatUsageService.reading(
            packs: try payload(json: #"{"code":0,"data":{"currentLot":{"totalToken":50000000,"status":"EXPIRED"}}}"#),
            tokenUsage: try payload("longcat-token-usage"), fuel: nil, context: context, now: now)
        #expect(usage.windows.map(\.kind) == [.credits])
        #expect(usage.windows[0].usedFraction == 0.24)
    }

    @Test("Tokens left stand in for tokens used when both come with the total")
    func remainder() throws {
        let usage = LongCatUsageService.reading(
            packs: nil, tokenUsage: try payload(json: #"{"code":0,"data":{"usage":{"totalToken":500000,"availableToken":380000}}}"#),
            fuel: nil, context: context, now: now)
        #expect(usage.windows.map(\.usedFraction) == [0.24])
    }

    @Test("A figure that isn't reported is left off, never filled with zero or the whole pack")
    func missingFigures() throws {
        let usage = LongCatUsageService.reading(
            packs: try payload(json: #"{"code":0,"data":{"currentLot":{"totalToken":1000,"status":"ACTIVE"}}}"#),
            tokenUsage: nil,
            fuel: try payload(json: #"{"code":0,"data":{"totalQuota":1000,"list":[{"expireTime":1750000000000}]}}"#),
            context: context, now: now)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("The older route without a total isn't a reply this reads")
    func legacyWithoutTotal() throws {
        let usage = LongCatUsageService.reading(
            packs: nil, tokenUsage: try payload(json: #"{"code":0,"data":{"usage":{"usedToken":120000}}}"#),
            fuel: nil, context: context, now: now)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("The envelope's code decides", arguments: [
        (#"{"code":401,"message":"unauthorized"}"#, ProviderUsage.Unavailability.sessionExpired),
        (#"{"code":403}"#, .sessionExpired),
        (#"{"code":500,"message":"busy"}"#, .serverError),
        (#"{"code":"x1"}"#, .unreadableReply),
        (#"{"code":0,"data":[]}"#, .unreadableReply),
        ("<html>", .unreadableReply),
    ])
    func envelope(json: String, reason: ProviderUsage.Unavailability) {
        guard case .failure(let found) = LongCatUsageService.payload(of: Data(json.utf8)) else {
            Issue.record("expected a failure")
            return
        }
        #expect(found == reason)
    }

    @Test("A success code hands over its data")
    func success() throws {
        #expect(try payload(json: #"{"code":0,"data":{"name":"Leo"}}"#)["name"] as? String == "Leo")
    }

    @Test("Fuel expiry reads epoch seconds, milliseconds, ISO 8601 and the console's own format")
    func dates() {
        #expect(LongCatUsageService.date(1_760_000_000) == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(LongCatUsageService.date(1_760_000_000_000) == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(LongCatUsageService.date("2025-10-09T12:00:00.500Z") != nil)
        #expect(LongCatUsageService.date("2025-10-09 12:00:00") != nil)
        #expect(LongCatUsageService.date("soon") == nil)
    }

    @Test("Only the named cookies leave the browser, and not without the passport token")
    func cookies() {
        #expect(ProviderProfile.keep("passport_token=t; uid=42; _ga=x", cookies: LongCatUsageService.cookies)
            == "passport_token=t; uid=42")
        #expect(ProviderProfile.keep("uid=42", cookies: LongCatUsageService.cookies) == nil)
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .longCat, credential: "", serverAddress: nil)
        #expect(await LongCatUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }
}
