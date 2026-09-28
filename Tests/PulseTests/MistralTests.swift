import Foundation
import Testing
@testable import Pulse

/// Mistral's included allowances and available credit.
///
/// **The fixtures are second-hand**: written from CodexBar's Mistral provider
/// and its tests (MIT), not captured from a live account — and so is the
/// subscription page built below. They pin the shape Pulse reads; they do not
/// prove the shape is right.
@Suite("Mistral")
struct MistralTests {
    private let context = ProfileContext(provider: .mistral, credential: "ory_session_x=abc", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A Next.js page whose server-rendered data is `stream`, pushed in pieces
    /// the way the page pushes it.
    private func page(_ stream: String, pieces: Int = 2) throws -> String {
        let size = max(stream.count / pieces, 1)
        var scripts: [String] = []
        var rest = Substring(stream)
        while !rest.isEmpty {
            let piece = String(rest.prefix(size))
            rest = rest.dropFirst(size)
            let pushed = try JSONSerialization.data(withJSONObject: [1, piece])
            scripts.append("<script>self.__next_f.push(\(String(decoding: pushed, as: UTF8.self)))</script>")
        }
        return "<html><body><script>self.__next_f.push([0])</script>\(scripts.joined())</body></html>"
    }

    private let budgets = #"""
    5:["$","div",null,{"budget":{"api_budget":{"usage_percentage":42.5,"initial_budget":10,"currency":"EUR","reset_at":"$D2026-10-01T00:00:00.000Z"},"vibe_budget":{"usage_percentage":12,"initial_budget":20,"currency":"EUR","reset_at":"2026-10-01T00:00:00Z"}}}]

    """#

    @Test("Both allowances are read from the page, as the percentages Mistral reports")
    func allowances() throws {
        let found = MistralUsageService.allowances(fromPage: try page(budgets, pieces: 3))
        #expect(found.api == .init(percentUsed: 42.5, resetsAt: ProfileHTTP.date("2026-10-01T00:00:00Z")))
        #expect(found.vibe == .init(percentUsed: 12, resetsAt: ProfileHTTP.date("2026-10-01T00:00:00Z")))
    }

    @Test("A page with no allowance, or two that disagree, gives none")
    func noAllowance() throws {
        #expect(MistralUsageService.allowances(fromPage: try page(#"1:["$","p",null,{"children":"Free"}]"#)) == .init())
        #expect(MistralUsageService.allowances(fromPage: "<html>signed out</html>") == .init())

        let twice = #"1:{"api_budget":{"usage_percentage":10}}"# + "\n" + #"2:{"api_budget":{"usage_percentage":90}}"#
        #expect(MistralUsageService.allowances(fromPage: try page(twice)).api == nil)
        // The same one twice is still one.
        let same = #"1:{"api_budget":{"usage_percentage":10}}"# + "\n" + #"2:{"api_budget":{"usage_percentage":10}}"#
        #expect(MistralUsageService.allowances(fromPage: try page(same)).api?.percentUsed == 10)
        // A figure that isn't one is left off.
        #expect(MistralUsageService.allowances(fromPage: try page(#"1:{"vibe_budget":{"usage_percentage":-4}}"#)).vibe == nil)
    }

    @Test("The console's Vibe figure, when the page has none")
    func vibe() throws {
        let found = MistralUsageService.vibe(from: try fixture("mistral-vibe-usage"))
        #expect(found == .init(percentUsed: 37, resetsAt: ProfileHTTP.date("2026-07-01T00:00:00Z")))
        #expect(MistralUsageService.vibe(from: Data("[]".utf8)) == nil)
        #expect(MistralUsageService.vibe(from: Data("<html>".utf8)) == nil)
    }

    @Test("Available credit is the wallet and credit notes, less usage not yet settled")
    func credit() throws {
        let credit = MistralUsageService.credit(from: try fixture("mistral-credits"))
        #expect(credit == .init(amount: 13.25, currency: "USD"))

        // Below zero is a debt, not a balance; no currency is no money.
        #expect(MistralUsageService.credit(from: Data(#"{"wallet_amount":1,"ongoing_usage_balance":3,"currency":"EUR"}"#.utf8)) == nil)
        #expect(MistralUsageService.credit(from: Data(#"{"wallet_amount":5}"#.utf8)) == nil)
        #expect(MistralUsageService.credit(from: Data("<html>".utf8)) == nil)
    }

    @Test("The reading: two monthly allowances, scoped by product, and the balance")
    func reading() throws {
        let allowances = MistralUsageService.allowances(fromPage: try page(budgets))
        let credit = MistralUsageService.credit(from: try fixture("mistral-credits"))
        let usage = MistralUsageService.reading(allowances, credit: credit, context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.mistral))
        #expect(usage.windows.map(\.scope) == ["API", "Vibe"])
        #expect(usage.windows.map(\.usedFraction) == [0.425, 0.12])
        #expect(usage.windows.allSatisfy { $0.kind == .monthly && !$0.reportsLength })
        #expect(usage.creditRemaining == .init(amount: 13.25, currency: "USD"))
        #expect(usage.creditBalance?.contains("13.25") == true)
    }

    @Test("Nothing reported at all is no limits")
    func nothing() {
        let usage = MistralUsageService.reading(.init(), credit: nil, context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("Only the Ory session and the CSRF token are kept from a pasted header")
    func cookies() throws {
        let cookies = try #require(MistralUsageService.sessionCookies(
            from: "Cookie: _ga=GA1; ory_session_coolstack=abc; csrftoken=tok; ajs_user_id=me; ory_session_=empty"
        ))
        #expect(cookies.session == ["ory_session_coolstack=abc"])
        #expect(cookies.csrf == "tok")
        #expect(cookies.header == "ory_session_coolstack=abc; csrftoken=tok")

        #expect(MistralUsageService.sessionCookies(from: "csrftoken=tok; _ga=GA1") == nil)
        #expect(MistralUsageService.sessionCookies(from: "ory_session_x=") == nil)
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .mistral, credential: " ", serverAddress: nil)
        #expect(await MistralUsageService.fetch(empty).state == .unavailable(.sessionMissing))
        let noSession = ProfileContext(provider: .mistral, credential: "csrftoken=tok", serverAddress: nil)
        #expect(await MistralUsageService.fetch(noSession).state == .unavailable(.sessionMissing))
    }

    @Test("A redirect to sign in is an expired session; the rest mean what they mean everywhere", arguments: [
        (302, ProviderUsage.Unavailability.sessionExpired), (303, .sessionExpired), (401, .sessionExpired),
        (403, .sessionExpired), (429, .rateLimited), (500, .serverError),
    ])
    func statuses(status: Int, reason: ProviderUsage.Unavailability) {
        #expect(MistralUsageService.status(.init(data: Data(), status: status)) == .failure(reason))
    }
}
