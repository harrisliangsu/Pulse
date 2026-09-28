import Foundation
import Testing
@testable import Pulse

/// Amp's balance RPC, whose reply is the text `amp usage` prints.
///
/// **The fixtures are second-hand**: written from CodexBar's Amp provider and
/// its parser tests (MIT), not captured from a live account. They pin the
/// lines Pulse reads; they do not prove Amp still prints them.
@Suite("Amp")
struct AmpTests {
    private let context = ProfileContext(provider: .amp, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func reply(_ text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["ok": true, "result": ["displayText": text]])
    }

    @Test("A paid tier reads its agent dollars and Orb hours, beside Amp Free and the credits")
    func tier() throws {
        let usage = AmpUsageService.reading(from: try fixture("amp-balance-tier"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.amp))
        #expect(usage.plan == "Megawatt")

        let free = try #require(usage.windows.first)
        #expect(free.id == "amp.free")
        #expect(free.kind == .daily)
        #expect(free.scope == "Amp Free")
        #expect(free.usedFraction == 0.39)
        #expect(free.reportsLength)
        // Daily is stated; the hour it turns over is not.
        #expect(free.resetsAt == nil)

        let agent = try #require(usage.windows.first { $0.id == "amp.agent" })
        #expect(agent.kind == .monthly)
        #expect(agent.scope == nil)
        #expect(abs(agent.usedFraction - 1.43 / 20) < 1e-9)
        #expect(!agent.reportsLength)
        #expect(agent.resetsAt == ProfileHTTP.date("2026-10-13T00:00:00Z"))

        let orb = try #require(usage.windows.first { $0.id == "amp.orb" })
        #expect(orb.scope == "Orb")
        #expect(abs(orb.usedFraction - 17.2 / 750) < 1e-9)
        #expect(orb.resetsAt == agent.resetsAt)

        #expect(usage.creditRemaining == .init(amount: 1_020.5, currency: "USD"))
        #expect(usage.creditBalance == AmpUsageService.dollars(1_020.5))
    }

    @Test("The older wording reads too, dollars win over the rounded free percentage, workspaces are left off")
    func legacy() throws {
        let usage = AmpUsageService.reading(from: try fixture("amp-balance-legacy"), context: context)

        #expect(usage.state == .live)
        #expect(usage.plan == "Megawatt")
        let free = try #require(usage.windows.first { $0.id == "amp.free" })
        // Refilled by the hour: no reset and no length to claim.
        #expect(free.kind == .credits)
        #expect(free.usedFraction == 0.4)
        #expect(!free.reportsLength)
        #expect(free.resetsAt == nil)
        #expect(usage.windows.first { $0.id == "amp.agent" }?.usedFraction == 0.03)
        #expect(usage.windows.first { $0.id == "amp.orb" }?.usedFraction == 0)
        // The countdown alone is rounded and moves; it is not a reset.
        #expect(usage.windows.allSatisfy { $0.resetsAt == nil })
        #expect(usage.creditBalance == nil)
        #expect(usage.creditRemaining == nil)
    }

    @Test("A limit of nothing is left off; the credits beside it still show")
    func noLimit() throws {
        let text = "Amp Megawatt Tier: agent usage $0 of $0 remaining - resets upon renewal in 27 days\nIndividual credits: $12 remaining"
        let usage = AmpUsageService.reading(from: try reply(text), context: context)
        #expect(usage.state == .live)
        #expect(usage.windows.isEmpty)
        #expect(usage.creditRemaining == .init(amount: 12, currency: "USD"))
    }

    @Test("More left than the limit is nothing used, not a negative")
    func overfull() throws {
        let text = "Amp Example Tier: agent usage $1,100 of $1,000 remaining - resets upon renewal in 1 month"
        let usage = AmpUsageService.reading(from: try reply(text), context: context)
        #expect(usage.windows.map(\.usedFraction) == [0])
    }

    @Test("Only a1.small Orb hours are an allowance Pulse reads")
    func otherOrb() throws {
        let text = "Amp Example Tier: agent usage $3 of $20 remaining (15%), orb usage 12h of 50h a1.large orb hours remaining - resets upon renewal in 2 days"
        let usage = AmpUsageService.reading(from: try reply(text), context: context)
        #expect(usage.windows.map(\.id) == ["amp.agent"])
        #expect(usage.windows.first?.usedFraction == 0.85)
    }

    @Test("A dead token is refused, whether Amp says so in the envelope or in the text")
    func refused() throws {
        let envelope = Data(#"{"ok":false,"error":{"code":"auth-required","message":"Sign in"}}"#.utf8)
        #expect(AmpUsageService.reading(from: envelope, context: context).state == .unavailable(.apiKeyRefused))
        let text = AmpUsageService.reading(from: try reply("Please log in to use Amp."), context: context)
        #expect(text.state == .unavailable(.apiKeyRefused))
    }

    @Test("Any other failure in the envelope is the service's")
    func failed() {
        let envelope = Data(#"{"ok":false,"error":{"code":"internal","message":"oops"}}"#.utf8)
        #expect(AmpUsageService.reading(from: envelope, context: context).state == .unavailable(.serverError))
    }

    @Test("A reply that isn't one can't be read", arguments: [
        "not json",
        #"{"ok":true}"#,
        #"{"ok":true,"result":{"displayText":""}}"#,
        #"{"ok":true,"result":{"displayText":"Signed in as a@b.c\nSomething new"}}"#,
        #"{"result":{"displayText":"Amp Free: 61% remaining today"}}"#,
    ])
    func unreadable(json: String) {
        let usage = AmpUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("The request is the read-only RPC, with the token as a bearer, to Amp only")
    func request() throws {
        let request = AmpUsageService.request(token: "abc")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "ampcode.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["method"] as? String == "userDisplayBalanceInfo")
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .amp, credential: "  ", serverAddress: nil)
        #expect(await AmpUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
