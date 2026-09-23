import Foundation

/// Codex's account-level history: how many tokens went through, day by day,
/// plus the one-off credits that reset a rate limit early.
///
/// The history stays in settings. The reset-credit summary is also shown on
/// the Codex card, from `rateLimits` alone, so opening that card does not
/// wait on `account/usage/read`.
///
/// Codex reports tokens here and never money, so the cost shown alongside it
/// in settings comes from `UsageLedger` instead — the local transcripts, which
/// record which model ran, priced at the rates `ModelPrices` publishes. What
/// stays here is what only Codex knows: the account's real lifetime total, and
/// the reset credits.
struct CodexAccountUsage: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let tokens: Int

        var id: Date { date }
    }

    /// A credit that clears a rate limit ahead of its reset.
    struct ResetCredit: Equatable, Sendable {
        let title: String
        let expiresAt: Date?
    }

    let days: [Day]
    let lifetimeTokens: Int
    let peakDailyTokens: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let availableResetCredits: Int
    /// The credit expiring soonest, which is the one worth spending first.
    let nextExpiringCredit: ResetCredit?
    /// False when the rate-limit payload omitted `rateLimitResetCredits`.
    /// That is "unknown", not a count of zero.
    let creditsKnown: Bool

    var todayTokens: Int { days.last?.tokens ?? 0 }

    func tokens(overLast days: Int) -> Int {
        self.days.suffix(days).reduce(0) { $0 + $1.tokens }
    }

    /// The tail of the history, for the chart.
    func recent(_ count: Int) -> [Day] { Array(days.suffix(count)) }
}

/// Banked reset credits, without the token history they travel with.
struct CodexCreditSummary: Equatable, Sendable {
    var available: Int
    var nextExpiresAt: Date?
    /// Kept for the settings history card, which names the credit.
    var next: CodexAccountUsage.ResetCredit?

    /// A known zero is still an answer, and the card stays quiet about it.
    /// An unknown read is not a summary at all.
    var showsOnCard: Bool { available > 0 || nextExpiresAt != nil }
}

/// Reads `account/usage/read` and the reset credits from `codex app-server`.
///
/// Only the app server offers these — the usage endpoint the panel normally
/// uses carries limits, not history — so this is unavailable when the `codex`
/// command can't be found.
struct CodexAccountUsageService: Sendable {
    let server: CodexAppServer

    func fetch() async -> CodexAccountUsage? {
        async let usage = server.accountUsage()
        async let limits = server.rateLimits()

        guard
            let usageData = try? await usage,
            let usageRoot = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any]
        else { return nil }

        let limitsRoot = (try? await limits)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        return parse(usage: usageRoot, limits: limitsRoot)
    }

    /// Credits alone. Nil when the app server cannot be asked, or when the
    /// payload does not carry `rateLimitResetCredits` — missing is unknown,
    /// not zero.
    func fetchCredits() async -> CodexCreditSummary? {
        guard
            let data = try? await server.rateLimits(),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Self.credits(from: root)
    }

    private func parse(usage: [String: Any], limits: [String: Any]) -> CodexAccountUsage {
        let summary = usage["summary"] as? [String: Any] ?? [:]

        let days = (usage["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { bucket -> CodexAccountUsage.Day? in
            guard
                let text = bucket["startDate"] as? String,
                let date = Self.dayFormatter.date(from: text),
                let tokens = Self.number(bucket["tokens"])
            else { return nil }
            return CodexAccountUsage.Day(date: date, tokens: Int(tokens))
        }

        let summaryCredits = Self.credits(from: limits)

        return CodexAccountUsage(
            days: days,
            lifetimeTokens: Int(Self.number(summary["lifetimeTokens"]) ?? 0),
            peakDailyTokens: Int(Self.number(summary["peakDailyTokens"]) ?? 0),
            currentStreakDays: Int(Self.number(summary["currentStreakDays"]) ?? 0),
            longestStreakDays: Int(Self.number(summary["longestStreakDays"]) ?? 0),
            availableResetCredits: summaryCredits?.available ?? 0,
            nextExpiringCredit: summaryCredits?.next,
            creditsKnown: summaryCredits != nil
        )
    }

    /// Nil when the field is absent. A present count of zero is a summary.
    static func credits(from limits: [String: Any]) -> CodexCreditSummary? {
        guard let credits = limits["rateLimitResetCredits"] as? [String: Any] else { return nil }

        let available = (credits["credits"] as? [[String: Any]] ?? [])
            .filter { ($0["status"] as? String) == "available" }

        // The one expiring soonest is the one worth spending first.
        let soonest = available
            .compactMap { credit -> CodexAccountUsage.ResetCredit? in
                guard let title = credit["title"] as? String else { return nil }
                return CodexAccountUsage.ResetCredit(
                    title: title,
                    expiresAt: number(credit["expiresAt"]).map { Date(timeIntervalSince1970: $0) }
                )
            }
            .min { lhs, rhs in
                (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
            }

        return CodexCreditSummary(
            available: Int(number(credits["availableCount"]) ?? Double(available.count)),
            nextExpiresAt: soonest?.expiresAt,
            next: soonest
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }
}
