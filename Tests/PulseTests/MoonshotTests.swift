import Foundation
import Testing
@testable import Pulse

/// Answers as Moonshot's two platforms would: each accepts only its own keys.
/// `intl-*` keys belong to api.moonshot.ai, `cn-*` keys to api.moonshot.cn,
/// anything else to neither. Every host asked is written down.
private final class MoonshotFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var asked: [String: [String]] = [:]
    private static let lock = NSLock()

    static func hosts(for key: String) -> [String] {
        lock.withLock { asked[key] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
        let host = request.url?.host ?? ""
        Self.lock.withLock { Self.asked[key, default: []].append(host) }

        let accepted = (host == "api.moonshot.ai" && key.hasPrefix("intl-"))
            || (host == "api.moonshot.cn" && key.hasPrefix("cn-"))
        let body = #"{"code":0,"data":{"available_balance":12.5,"voucher_balance":0,"cash_balance":12.5},"scode":"0x0","status":true}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: accepted ? 200 : 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((accepted ? body : "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Moonshot's (Kimi Open Platform's) API balance, on either platform.
///
/// **The fixture is second-hand**: written from CodexBar's Moonshot plugin and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right. The two-platform exchange is
/// simulated by a stub, not observed.
@Suite("Moonshot")
struct MoonshotTests {
    private let context = ProfileContext(provider: .moonshot, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private var stubbed: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MoonshotFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("The available balance is read in the platform's currency, with no ring")
    func balance() throws {
        let data = try fixture("moonshot-balance")
        let international = MoonshotUsageService.reading(from: data, region: .international, context: context)
        #expect(international.state == .live)
        #expect(international.account == AccountKey(.moonshot))
        #expect(international.windows.isEmpty)
        #expect(international.creditRemaining == ProviderUsage.CreditAmount(amount: 49.58, currency: "USD"))
        #expect(international.creditBalance == MoonshotUsageService.money(49.58, currency: "USD"))

        let china = MoonshotUsageService.reading(from: data, region: .china, context: context)
        #expect(china.creditRemaining == ProviderUsage.CreditAmount(amount: 49.58, currency: "CNY"))
    }

    @Test("A balance below zero is kept as reported")
    func deficit() {
        let json = #"{"code":0,"data":{"available_balance":-0.42,"voucher_balance":0,"cash_balance":-0.42},"scode":"0x0","status":true}"#
        let usage = MoonshotUsageService.reading(from: Data(json.utf8), region: .china, context: context)
        #expect(usage.creditRemaining?.amount == -0.42)
    }

    @Test("A reply that can't be read", arguments: [
        "not json", "{}", #"{"code":0,"status":true}"#,
        #"{"code":0,"status":true,"data":{"available_balance":"12"}}"#,
        #"{"code":"0","status":true,"data":{"available_balance":1}}"#,
    ])
    func unreadable(json: String) {
        let usage = MoonshotUsageService.reading(from: Data(json.utf8), region: .international, context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A reply that says it failed is the service's error")
    func failedReply() {
        let json = #"{"code":1,"data":{"available_balance":0},"scode":"0x1","status":false}"#
        let usage = MoonshotUsageService.reading(from: Data(json.utf8), region: .international, context: context)
        #expect(usage.state == .unavailable(.serverError))
    }

    @Test("An international key is read from the international platform only")
    func international() async {
        let key = "intl-\(UUID().uuidString)"
        let usage = await MoonshotUsageService.fetch(
            ProfileContext(provider: .moonshot, credential: key, serverAddress: nil), session: stubbed
        )
        #expect(usage.creditRemaining?.currency == "USD")
        #expect(MoonshotFixtureProtocol.hosts(for: key) == ["api.moonshot.ai"])
    }

    @Test("A China key refused internationally is read from the China platform, and remembered")
    func china() async {
        let key = "cn-\(UUID().uuidString)"
        let context = ProfileContext(provider: .moonshot, credential: key, serverAddress: nil)
        let first = await MoonshotUsageService.fetch(context, session: stubbed)
        #expect(first.creditRemaining == ProviderUsage.CreditAmount(amount: 12.5, currency: "CNY"))
        _ = await MoonshotUsageService.fetch(context, session: stubbed)
        #expect(MoonshotFixtureProtocol.hosts(for: key) == ["api.moonshot.ai", "api.moonshot.cn", "api.moonshot.cn"])
    }

    @Test("A key both platforms refuse is a refused key")
    func refusedEverywhere() async {
        let key = "bad-\(UUID().uuidString)"
        let usage = await MoonshotUsageService.fetch(
            ProfileContext(provider: .moonshot, credential: key, serverAddress: nil), session: stubbed
        )
        #expect(usage.state == .unavailable(.apiKeyRefused))
        #expect(MoonshotFixtureProtocol.hosts(for: key) == ["api.moonshot.ai", "api.moonshot.cn"])
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .moonshot, credential: "", serverAddress: nil)
        #expect(await MoonshotUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
