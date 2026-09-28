import Foundation
import Testing
@testable import Pulse

/// Warp's request-limit query.
///
/// **The fixture is second-hand**: written from CodexBar's Warp provider and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Warp")
struct WarpTests {
    private let context = ProfileContext(provider: .warp, credential: "wk-key", serverAddress: nil)
    /// Before every expiry in the fixture.
    private let now = ProfileHTTP.date("2026-09-25T00:00:00Z")!

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func read(_ json: String) -> ProviderUsage {
        WarpUsageService.reading(from: Data(json.utf8), context: context, now: now)
    }

    @Test("The plan's credits and the add-on credits, each as stated")
    func credits() throws {
        let usage = WarpUsageService.reading(from: try fixture("warp-request-limit"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.warp))
        #expect(usage.windows.map(\.kind) == [.credits, .topUp])

        let plan = usage.windows[0]
        #expect(plan.usedFraction == 0.25)
        #expect(plan.resetsAt == ProfileHTTP.date("2026-10-01T00:00:00Z"))
        // A refill date is stated; the period's length is not.
        #expect(!plan.reportsLength)

        // The user's grant and the workspace's, added up: 1,500 granted, 900 left.
        let addOn = usage.windows[1]
        #expect(addOn.usedFraction == 600.0 / 1_500.0)
        #expect(addOn.resetsAt == nil)
        #expect(addOn.nextExpiry == UsageWindow.Expiry(amount: 400, at: ProfileHTTP.date("2026-10-15T12:00:00Z")!))
    }

    @Test("An unlimited plan has no limit to draw")
    func unlimited() {
        let usage = read(#"{"data":{"user":{"__typename":"UserOutput","user":{"requestLimitInfo":{"isUnlimited":true,"requestLimit":0,"requestsUsedSinceLastRefresh":12}}}}}"#)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A limit with no figure is left off, and nothing left is no limits", arguments: [
        #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":false,"requestLimit":0,"requestsUsedSinceLastRefresh":0}}}}}"#,
        #"{"data":{"user":{"user":{"requestLimitInfo":{"requestLimit":100,"requestsUsedSinceLastRefresh":-1},"bonusGrants":[{"requestCreditsGranted":100,"requestCreditsRemaining":-5}]}}}}"#,
        #"{"data":{"user":{"user":{"requestLimitInfo":{"requestLimit":100}}}}}"#,
    ])
    func noFigures(json: String) {
        #expect(read(json).state == .unavailable(.noLimitsReported))
    }

    @Test("A reply without the limit can't be read", arguments: [
        "not json",
        "{}",
        #"{"data":{"user":{"__typename":"UserFacingError"}}}"#,
    ])
    func unreadable(json: String) {
        #expect(read(json).state == .unavailable(.unreadableReply))
    }

    @Test("GraphQL errors answered with a 200 are the service's error")
    func graphQLErrors() {
        let usage = read(#"{"errors":[{"message":"Something went wrong"}],"data":null}"#)
        #expect(usage.state == .unavailable(.serverError))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .warp, credential: nil, serverAddress: nil)
        #expect(await WarpUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }

    @Test("The query is a read, posted with the key and the client headers Warp's edge asks for")
    func request() throws {
        let request = WarpUsageService.request(key: "wk-key")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer wk-key")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Warp/1.0")
        #expect(request.value(forHTTPHeaderField: "x-warp-client-id") == "warp-app")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["operationName"] as? String == "GetRequestLimitInfo")
        #expect((object["query"] as? String)?.hasPrefix("query ") == true)
    }
}
