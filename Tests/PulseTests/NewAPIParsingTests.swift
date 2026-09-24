import Foundation
import Testing
@testable import Pulse

/// New API answers OpenAI's billing routes, and **two of the three things
/// those routes report mean something other than their names**: the "limit" is
/// a total, the "usage" is in hundredths, and the `_usd` is whatever unit the
/// operator chose. Most of these are about not taking a field name at its word.
@Suite("New API parsing")
struct NewAPIParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static func decode<Reply: Decodable>(_ type: Reply.Type, _ name: String) throws -> Reply {
        try JSONDecoder().decode(Reply.self, from: try fixture(name))
    }

    // MARK: - The two figures

    /// `hard_limit_usd` is `remaining + used` and `total_usage` is the amount
    /// times a hundred, so what is left is the subtraction of the two — and
    /// getting either wrong is off by a factor of a hundred.
    @Test("What is left is the reported total less the reported usage, in hundredths")
    func remainingIsTotalLessUsage() throws {
        let subscription = try Self.decode(NewAPIUsageService.Subscription.self, "newapi-subscription")
        let usage = try Self.decode(NewAPIUsageService.Usage.self, "newapi-usage")

        let remaining = try #require(
            NewAPIUsageService.remaining(subscription: subscription, usage: usage)
        )
        // 25.5 − 1234.5/100 = 13.155
        #expect(abs(remaining - 13.155) < 0.0001)
    }

    /// **The factor of a hundred is the whole trap.** Read as units, a wallet
    /// with $13 left comes out at −$1,209 — a red ring and a notification
    /// announcing an account as spent.
    @Test("Usage read as units rather than hundredths would be a hundred times too large")
    func hundredthsAreNotUnits() throws {
        let subscription = try Self.decode(NewAPIUsageService.Subscription.self, "newapi-subscription")
        let usage = try Self.decode(NewAPIUsageService.Usage.self, "newapi-usage")
        let remaining = try #require(
            NewAPIUsageService.remaining(subscription: subscription, usage: usage)
        )
        #expect(remaining > 0)
    }

    @Test("A figure that is missing or not finite reports nothing")
    func absentFiguresReportNothing() throws {
        let usage = try Self.decode(NewAPIUsageService.Usage.self, "newapi-usage")
        let empty = try JSONDecoder().decode(
            NewAPIUsageService.Subscription.self, from: Data("{}".utf8)
        )
        #expect(NewAPIUsageService.remaining(subscription: empty, usage: usage) == nil)

        let subscription = try Self.decode(NewAPIUsageService.Subscription.self, "newapi-subscription")
        let noUsage = try JSONDecoder().decode(
            NewAPIUsageService.Usage.self, from: Data("{}".utf8)
        )
        #expect(NewAPIUsageService.remaining(subscription: subscription, usage: noUsage) == nil)
    }

    // MARK: - Unlimited

    /// New API substitutes a literal hundred million rather than setting a
    /// flag, so it has to be recognised by value — and a key read as having
    /// that much would show a hundred million of something.
    @Test("An unlimited key is recognised by its sentinel")
    func unlimitedIsRecognised() throws {
        #expect(try NewAPIUsageService.isUnlimited(
            Self.decode(NewAPIUsageService.Subscription.self, "newapi-unlimited")
        ))
        #expect(try !NewAPIUsageService.isUnlimited(
            Self.decode(NewAPIUsageService.Subscription.self, "newapi-subscription")
        ))
    }

    /// All three fields are written from the same variable upstream, so
    /// agreement across them is what separates the sentinel from a deployment
    /// that genuinely sold somebody exactly that much.
    @Test("One field at the sentinel is not an unlimited key")
    func partialSentinelIsNotUnlimited() throws {
        let subscription = try JSONDecoder().decode(
            NewAPIUsageService.Subscription.self,
            from: Data("""
            {"hard_limit_usd": 100000000, "soft_limit_usd": 25, "system_hard_limit_usd": 25}
            """.utf8)
        )
        #expect(!NewAPIUsageService.isUnlimited(subscription))
    }

    // MARK: - The unit

    /// The `_usd` in the field names is not evidence: New API converts into
    /// the operator's display type and keeps OpenAI's field name, so a CNY
    /// site reports yuan in `hard_limit_usd`.
    @Test("The currency comes from the site's own setting, not the field name")
    func currencyComesFromStatus() throws {
        #expect(try NewAPIUsageService.currency(
            of: Self.decode(NewAPIUsageService.Status.self, "newapi-status-usd")
        ) == "USD")
        #expect(try NewAPIUsageService.currency(
            of: Self.decode(NewAPIUsageService.Status.self, "newapi-status-cny")
        ) == "CNY")
    }

    /// A site counting tokens has no money to report, and tokens wearing a
    /// dollar sign is a figure with the wrong name on it.
    @Test("A site counting tokens reports no money")
    func tokensAreNotMoney() throws {
        #expect(try NewAPIUsageService.currency(
            of: Self.decode(NewAPIUsageService.Status.self, "newapi-status-tokens")
        ) == nil)
    }

    /// Older builds and one-api forks carry a bool instead, which distinguishes
    /// money from tokens and nothing more — so it can only ever answer USD,
    /// which is what those builds assumed.
    @Test("An older build's bool is read only when the newer field is absent")
    func legacyFlagIsRead() throws {
        #expect(try NewAPIUsageService.currency(
            of: Self.decode(NewAPIUsageService.Status.self, "newapi-status-legacy")
        ) == "USD")
    }

    /// **Nil rather than a default, three ways.** A status route that did not
    /// answer, a display type added upstream that Pulse has not been taught,
    /// and an operator's own unit are all "cannot say" — and a default of USD
    /// would put a dollar sign on every one of them.
    @Test("An unknown or unanswered unit reports no money rather than dollars")
    func unknownUnitIsNotDollars() throws {
        #expect(NewAPIUsageService.currency(of: nil) == nil)

        let custom = try JSONDecoder().decode(
            NewAPIUsageService.Status.self,
            from: Data(#"{"success": true, "data": {"quota_display_type": "CUSTOM"}}"#.utf8)
        )
        #expect(NewAPIUsageService.currency(of: custom) == nil)

        let future = try JSONDecoder().decode(
            NewAPIUsageService.Status.self,
            from: Data(#"{"success": true, "data": {"quota_display_type": "EUR"}}"#.utf8)
        )
        #expect(NewAPIUsageService.currency(of: future) == nil)

        let bare = try JSONDecoder().decode(
            NewAPIUsageService.Status.self, from: Data(#"{"success": true}"#.utf8)
        )
        #expect(NewAPIUsageService.currency(of: bare) == nil)
    }

    // MARK: - The address

    /// People paste the base URL out of their client's config, which for an
    /// OpenAI-compatible endpoint ends in `/v1`.
    @Test("A base URL ending in /v1 does not produce /v1/v1")
    func clientBaseURLIsAccepted() throws {
        for typed in ["https://relay.example.com", "https://relay.example.com/v1"] {
            let url = try #require(
                NewAPIUsageService.url(from: typed, path: "/v1/dashboard/billing/usage"), "\(typed)"
            )
            #expect(
                url.absoluteString == "https://relay.example.com/v1/dashboard/billing/usage",
                "\(typed)"
            )
        }
    }

    /// The status route is not under `/v1`, so trimming has to happen before
    /// the path is chosen rather than after.
    @Test("The status route sits beside /v1, not under it")
    func statusRouteIsNotUnderV1() throws {
        let url = try #require(
            NewAPIUsageService.url(from: "https://relay.example.com/v1", path: "/api/status")
        )
        #expect(url.absoluteString == "https://relay.example.com/api/status")
    }

    @Test("An address the shared rule refuses is refused here too")
    func sharedRuleApplies() {
        #expect(NewAPIUsageService.url(from: "http://relay.example.com", path: "/api/status") == nil)
        #expect(NewAPIUsageService.url(from: "https://user:pw@evil.example", path: "/api/status") == nil)
    }
}
