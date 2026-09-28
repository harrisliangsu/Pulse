import Foundation
import Testing
@testable import Pulse

/// Answers as OpenAI would for each kind of key, told apart by the key itself.
private final class OpenAIPlatformStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let key = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
        let balance = request.url?.path == "/v1/dashboard/billing/credit_grants"
        let status: Int = switch (key, balance) {
        case ("user", true): 200
        case ("admin", true): 403
        case ("admin", false): 200
        case ("retired", true): 404
        case ("busy", _): 429
        default: 401
        }
        let body = balance && status == 200 ? OpenAIPlatformTests.grants : Data("{}".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The OpenAI API's credit balance.
///
/// **The fixture is second-hand**: written from CodexBar's OpenAI plugin
/// (MIT), which reads the same legacy billing route, not captured from a live
/// account. It pins the shape Pulse reads; it does not prove the shape is
/// right.
@Suite("OpenAI API")
struct OpenAIPlatformTests {
    static let grants: Data = {
        let url = Bundle.module.url(forResource: "openai-api-credit-grants", withExtension: "json", subdirectory: "Fixtures")!
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    private let context = ProfileContext(provider: .openAIPlatform, credential: "key", serverAddress: nil)

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIPlatformStub.self]
        return URLSession(configuration: configuration)
    }

    private func fetch(key: String) async -> ProviderUsage {
        let context = ProfileContext(provider: .openAIPlatform, credential: key, serverAddress: nil)
        return await OpenAIPlatformUsageService.fetch(context, session: session())
    }

    @Test("The balance left is shown in dollars, with no ring")
    func balance() {
        let usage = OpenAIPlatformUsageService.reading(from: Self.grants, context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.openAIPlatform))
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == ProviderUsage.CreditAmount(amount: 12.3, currency: "USD"))
        #expect(usage.creditBalance == OpenAIPlatformUsageService.money(12.3))
    }

    @Test("A reply that isn't a credit summary can't be read", arguments: ["not json", "{}", "[]"])
    func unreadable(json: String) {
        let usage = OpenAIPlatformUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A balance that isn't one is left off, and nothing left is no limits", arguments: [
        #"{"total_granted":5,"total_used":7,"total_available":-2}"#,
        #"{"total_granted":5,"total_used":1}"#,
    ])
    func noBalance(json: String) {
        let usage = OpenAIPlatformUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
        #expect(usage.creditBalance == nil)
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .openAIPlatform, credential: "", serverAddress: nil)
        #expect(await OpenAIPlatformUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }

    @Test("A key that reads the balance shows it")
    func userKey() async {
        let usage = await fetch(key: "user")
        #expect(usage.state == .live)
        #expect(usage.creditRemaining?.amount == 12.3)
    }

    @Test("An Admin key the balance route turns away works, and reports no limits")
    func adminKey() async {
        #expect(await fetch(key: "admin").state == .unavailable(.noLimitsReported))
    }

    @Test("A key both routes refuse is refused", arguments: ["bad", "retired"])
    func refused(key: String) async {
        #expect(await fetch(key: key).state == .unavailable(.apiKeyRefused))
    }

    @Test("Easing off is not taken for a refusal")
    func rateLimited() async {
        #expect(await fetch(key: "busy").state == .unavailable(.rateLimited))
    }
}
