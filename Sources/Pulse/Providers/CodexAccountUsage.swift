// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Codex's account-level history: how many tokens went through, day by day,
/// plus the one-off credits that reset a rate limit early.
///
/// The history stays in settings. The card's reset-credit row is a separate
/// read of `rateLimits` (`CodexResetCredits`), so opening that card does not
/// wait on `account/usage/read`. The forecast and the latest-reset row are
/// not this history either.
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
///
/// The open card's "how many are left" row is `CodexResetCredits`, behind its
/// own switch. This summary is the line under the Codex Resets forecast: a
/// known zero stays quiet, and an unknown read is not a summary at all.
struct CodexCreditSummary: Equatable, Sendable {
    var available: Int
    var nextExpiresAt: Date?
    /// Kept for the settings history card, which names the credit.
    var next: CodexAccountUsage.ResetCredit?

    /// A known zero is still an answer, and the card stays quiet about it.
    /// An unknown read is not a summary at all. One card whose expiry has
    /// passed is quiet too: the count was true when it was stored, and it
    /// stops being true at that instant, before the next read lands.
    func showsOnCard(at now: Date = Date()) -> Bool {
        guard available > 0 else { return false }
        if available == 1, let nextExpiresAt, nextExpiresAt <= now { return false }
        return true
    }
}

/// What one `account/rateLimits/read` did to the card's reset-card line.
///
/// A summary replaces whatever was showing, including a known zero.
/// `absent` is a document that arrived without a reset-credit block: the
/// previous line comes off, so a card that was spent cannot stay up just
/// because this reply left the field out. `failed` is no document at all
/// (the app server did not answer), and the previous line stays.
enum CodexCreditRead: Equatable, Sendable {
    case summary(CodexCreditSummary)
    case absent
    case failed
}

extension CodexCreditSummary {
    static func reconcile(previous: CodexCreditSummary?, read: CodexCreditRead) -> CodexCreditSummary? {
        switch read {
        case .summary(let summary): summary
        case .absent: nil
        case .failed: previous
        }
    }
}

/// The reset credits alone, as the card shows them when the switch is on.
///
/// **What Codex said, or that it said nothing.** `unreported` is a reply with
/// no reset-credit block in it, or no app server to ask; it is shown as "Not
/// available" rather than a count Pulse worked out.
enum CodexResetCredits: Equatable, Sendable {
    case available(count: Int, nextExpiry: Date?)
    case unreported
    /// No `codex` anywhere Pulse looks, so nothing was asked. Said apart from
    /// `unreported` because the remedy is different, and "Not available" for
    /// both left two Macs with several credits guessing which (issue #67).
    case codexMissing
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

    /// Credits alone, for the forecast card.
    ///
    /// A thrown read is `.failed` (keep the previous line). A document with
    /// no reset-credit block is `.absent` (take the line off). A block that
    /// names a count, including zero, is a summary.
    func readCredits() async -> CodexCreditRead {
        let data: Data
        do {
            data = try await server.rateLimits()
        } catch {
            return .failed
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed }
        let field = root["rateLimitResetCredits"]
        if field == nil || field is NSNull { return .absent }
        guard let summary = Self.credits(from: root) else { return .absent }
        return .summary(summary)
    }

    /// Only the reset credits, from `account/rateLimits/read` — what the card
    /// asks for on every Codex refresh while its switch is on. One call, not
    /// the history's two.
    func resetCredits() async -> CodexResetCredits {
        let data: Data
        do {
            data = try await server.rateLimits()
        } catch CodexAppServer.Failure.executableNotFound {
            return .codexMissing
        } catch {
            return .unreported
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreported }
        return Self.resetCredits(in: root)
    }

    /// Internal and static so the parsing is testable without a server.
    ///
    /// `now` decides which `expiresAt` is still ahead. Callers that care
    /// about a fixed instant pass it; the app passes the clock.
    static func resetCredits(in limits: [String: Any], now: Date = Date()) -> CodexResetCredits {
        guard let block = limits["rateLimitResetCredits"] as? [String: Any] else { return .unreported }
        guard let inventory = inventory(in: block, now: now) else { return .unreported }
        return .available(count: inventory.count, nextExpiry: inventory.next?.expiresAt)
    }

    /// The cards still left in one `rateLimitResetCredits` object.
    ///
    /// Nil when the object names neither `availableCount` nor a `credits`
    /// array — that is "not reported", the same as a missing block.
    /// `credits: null` is count-only. An array is the inventory: a row counts
    /// while `status` is `available` and `expiresAt` is missing or still
    /// ahead. An empty array, or a list with nothing still usable, is zero
    /// even when `availableCount` is still positive — that count is the
    /// usage snapshot, and it lags a list that has already been spent.
    /// A list of only still-usable rows that is shorter than `availableCount`
    /// is capped, so the higher count stands.
    private struct CreditInventory {
        var count: Int
        var next: CodexAccountUsage.ResetCredit?
    }

    private static func inventory(in block: [String: Any], now: Date) -> CreditInventory? {
        // `Int(_:)` traps past its range, and a number in somebody's JSON
        // is not bounded by anything.
        let stated: Int?
        if let value = number(block["availableCount"]), value.isFinite, value >= 0, value < 1_000_000 {
            stated = Int(value)
        } else {
            stated = nil
        }
        guard let rows = creditRows(block["credits"]) else {
            guard let stated else { return nil }
            return CreditInventory(count: stated, next: nil)
        }

        let usable = rows.filter { isUsable($0, now: now) }
        guard !usable.isEmpty else { return CreditInventory(count: 0, next: nil) }
        // A shorter list of only still-usable rows is capped, so the stated
        // count stands. A list that also holds spent or expired rows is the
        // inventory, and the usable rows are the count.
        let count: Int
        if let stated, usable.count == rows.count, stated > usable.count {
            count = stated
        } else {
            count = usable.count
        }
        return CreditInventory(count: count, next: soonestCredit(in: usable))
    }

    /// `nil` when `credits` is null or absent: only the count is known.
    /// An array, including an empty one, is the inventory.
    private static func creditRows(_ value: Any?) -> [[String: Any]]? {
        if value == nil || value is NSNull { return nil }
        if let rows = value as? [[String: Any]] { return rows }
        // JSON null is already handled. An empty array from the parser is an
        // inventory of none; a list that is not all objects is not one.
        guard let rows = value as? [Any] else { return nil }
        if rows.isEmpty { return [] }
        let objects = rows.compactMap { $0 as? [String: Any] }
        guard objects.count == rows.count else { return nil }
        return objects
    }

    /// Still redeemable. Anything but `available` has been spent or is not
    /// a card yet. An `expiresAt` that has passed is the same, whichever
    /// status the snapshot still carries.
    private static func isUsable(_ credit: [String: Any], now: Date) -> Bool {
        guard (credit["status"] as? String) == "available" else { return false }
        if let expires = expiryDate(credit["expiresAt"]), expires <= now { return false }
        return true
    }

    private static func soonestCredit(in rows: [[String: Any]]) -> CodexAccountUsage.ResetCredit? {
        rows.compactMap { row -> (CodexAccountUsage.ResetCredit, Date)? in
            guard let expires = expiryDate(row["expiresAt"]) else { return nil }
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (CodexAccountUsage.ResetCredit(title: title, expiresAt: expires), expires)
        }
        .min { $0.1 < $1.1 }?
        .0
    }

    /// Unix seconds, as app-server sends them, or an ISO-8601 string from an
    /// older payload. Anything else is no date — the card is kept, and no
    /// expiry line is invented.
    private static func expiryDate(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            guard seconds.isFinite, seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        if let text = value as? String {
            return CodexResetDates.parse(text)
        }
        return nil
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

        let creditBlock = limits["rateLimitResetCredits"] as? [String: Any]
        let inventory: CreditInventory?
        if let creditBlock {
            inventory = Self.inventory(in: creditBlock, now: Date())
        } else {
            inventory = nil
        }

        return CodexAccountUsage(
            days: days,
            lifetimeTokens: Int(Self.number(summary["lifetimeTokens"]) ?? 0),
            peakDailyTokens: Int(Self.number(summary["peakDailyTokens"]) ?? 0),
            currentStreakDays: Int(Self.number(summary["currentStreakDays"]) ?? 0),
            longestStreakDays: Int(Self.number(summary["longestStreakDays"]) ?? 0),
            availableResetCredits: inventory?.count ?? 0,
            nextExpiringCredit: inventory?.next,
            creditsKnown: inventory != nil
        )
    }

    /// Nil when the field is absent, or present but names neither a count nor
    /// a list. A present count of zero is a summary.
    static func credits(from limits: [String: Any], now: Date = Date()) -> CodexCreditSummary? {
        guard
            let block = limits["rateLimitResetCredits"] as? [String: Any],
            let inventory = inventory(in: block, now: now)
        else { return nil }
        return CodexCreditSummary(
            available: inventory.count,
            nextExpiresAt: inventory.next?.expiresAt,
            next: inventory.next
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
