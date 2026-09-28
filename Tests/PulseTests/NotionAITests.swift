import Foundation
import Testing
@testable import Pulse

/// Notion AI's usage allowance.
///
/// **The fixtures are second-hand**: written from CodexBar's Notion provider
/// and its fixtures (MIT), not captured from a live account. They pin the
/// shape Pulse reads; they do not prove the shape is right.
@Suite("Notion AI")
struct NotionAITests {
    private let context = ProfileContext(provider: .notionAI, credential: "token_v2=abc", serverAddress: nil)
    private let now = Date(timeIntervalSince1970: 1_785_600_000)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The rolling window and the billing period are read as used over limit")
    func windows() throws {
        let usage = NotionAIUsageService.reading(
            from: try fixture("notion-ai-rate-limit"), plan: "Business", context: context, now: now
        )

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.notionAI))
        #expect(usage.plan == "Business")
        #expect(usage.windows.map(\.id) == ["notion.rolling", "notion.billing"])

        let rolling = usage.windows[0]
        #expect(rolling.kind == .other(seconds: 6 * 3_600))
        #expect(rolling.usedFraction == 0.425)
        #expect(rolling.reportsLength)
        #expect(rolling.resetsAt == now.addingTimeInterval(12_600))

        // A billing period states its end and not its length.
        let billing = usage.windows[1]
        #expect(billing.kind == .monthly)
        #expect(billing.usedFraction == 0.18)
        #expect(!billing.reportsLength)
        #expect(billing.resetsAt == Date(timeIntervalSince1970: 1_788_000_000))
    }

    @Test("The workspace with an allowance is chosen over one that sorts first")
    func workspace() throws {
        let spaces = try #require(NotionAIUsageService.workspaces(from: try fixture("notion-ai-spaces")))
        #expect(spaces.count == 2)
        let chosen = try #require(NotionAIUsageService.choose(from: spaces))
        #expect(chosen.id == "11111111-2222-3333-4444-555555555555")
        #expect(chosen.tier == "Business")
    }

    @Test("With no workspace on a paid plan, the first one is asked, and nothing is no plan")
    func fallbackWorkspace() {
        let free = NotionAIUsageService.Workspace(id: "a", subscriptionTier: "free")
        let plus = NotionAIUsageService.Workspace(id: "b", subscriptionTier: "plus")
        #expect(NotionAIUsageService.choose(from: [free, plus]) == free)
        #expect(NotionAIUsageService.choose(from: []) == nil)
    }

    @Test("A reply naming two users is refused rather than guessed between")
    func twoUsers() {
        let json = #"{"a":{"notion_user":{"a":{"value":{"id":"a"}}}},"b":{"notion_user":{"b":{"value":{"id":"b"}}}}}"#
        #expect(NotionAIUsageService.workspaces(from: Data(json.utf8)) == nil)
        #expect(NotionAIUsageService.workspaces(from: Data("[]".utf8)) == nil)
    }

    @Test("An older reply without the user's own id still reads, singly wrapped")
    func legacySpaces() throws {
        let json = #"{"u":{"space":{"s":{"value":{"name":"Acme","subscription_tier":"enterprise"}}}}}"#
        let spaces = try #require(NotionAIUsageService.workspaces(from: Data(json.utf8)))
        #expect(spaces == [.init(id: "s", subscriptionTier: "enterprise")])
    }

    @Test("A workspace without an allowance is no plan, not an outage")
    func notApplicable() {
        let usage = NotionAIUsageService.reading(from: Data(#"{"status":"not_applicable"}"#.utf8), context: context)
        #expect(usage.state == .unavailable(.noPlan))
    }

    @Test("A reply that isn't one can't be read", arguments: ["not json", "{}", #"{"status":"within_limit"}"#])
    func unreadable(json: String) {
        let usage = NotionAIUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A limit of nothing, or a figure missing, is left off, and nothing left is no limits")
    func noFigures() {
        let json = #"{"window":{"window":"6h","used":4,"limit":0},"billingPeriodWindow":{"limit":100}}"#
        let usage = NotionAIUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("The rolling window's length is the one Notion states, or none", arguments: [
        ("5h", UsageWindow.Kind.fiveHour, true), ("24h", .daily, true), ("1d", .daily, true),
        ("7d", .weekly, true), ("90m", .other(seconds: 5_400), true),
        ("soon", .credits, false), ("", .credits, false),
    ])
    func length(token: String, kind: UsageWindow.Kind, stated: Bool) {
        let (found, _, reportsLength) = NotionAIUsageService.length(of: token)
        #expect(found == kind)
        #expect(reportsLength == stated)
    }

    @Test("No session, or one without token_v2, is asked for, not sent", arguments: [nil, " ", "notion_user_id=1"])
    func missingSession(credential: String?) async {
        let empty = ProfileContext(provider: .notionAI, credential: credential, serverAddress: nil)
        #expect(await NotionAIUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }
}
