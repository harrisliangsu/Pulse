import Foundation
import Testing
@testable import Pulse

@Suite("Spend summary snapshots")
struct SpendSummaryCacheTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let today = ISO8601DateFormatter().date(from: "2026-09-20T00:00:00Z")!

    private func ledger(_ tokens: Int, at date: Date, model: String = "model") -> UsageLedger {
        UsageLedger(days: [.init(date: date, tokens: tokens, cost: 0, unpricedTokens: tokens,
                                models: [model: tokens])], earliest: date, unpricedModels: [model],
                    modelNames: [:], slots: [])
    }

    @Test("Agent, model, span, date and replacement snapshot each use their own figures")
    func navigationAndInvalidation() async throws {
        let cache = SpendSummaryCache()
        let snapshot = UUID()
        let yesterday = today.addingTimeInterval(-86400)
        let ledgers: [SpendAgent: UsageLedger] = [
            .codex: ledger(10, at: today), .claudeCode: ledger(20, at: yesterday),
        ]
        func request(days: Int? = nil, date: Date? = nil, id: UUID? = nil,
                     agent: SpendAgent? = nil, model: String? = nil) -> SpendSummaryCache.Request {
            .init(window: .init(snapshot: id ?? snapshot, days: days, today: date ?? today, calendar: calendar, language: "en"),
                  agent: agent, model: model)
        }
        let all = try await cache.summaries(for: request(model: "model"), ledgers: ledgers)
        #expect(all.overview.tokens == 30)
        #expect(all.model.tokens == 30)
        let codex = try await cache.summaries(for: request(agent: .codex, model: "model"), ledgers: ledgers)
        #expect(codex.overview.tokens == 30)
        #expect(codex.agent.tokens == 10)
        #expect(codex.model.tokens == 10)
        let claude = try await cache.summaries(for: request(agent: .claudeCode, model: "model"), ledgers: ledgers)
        #expect(claude.agent.tokens == 20)
        #expect(claude.model.tokens == 20)
        let missing = try await cache.summaries(for: request(model: "missing"), ledgers: ledgers)
        #expect(missing.model.isEmpty)
        #expect(missing.model.name == "missing")
        let narrowed = try await cache.summaries(for: request(days: 1, model: "model"), ledgers: ledgers)
        #expect(narrowed.overview.tokens == 10)
        #expect(narrowed.model.tokens == 10)
        let tomorrow = try await cache.summaries(for: request(days: 1, date: today.addingTimeInterval(86400)), ledgers: ledgers)
        #expect(tomorrow.overview.tokens == 0)
        let replaced = try await cache.summaries(for: request(id: UUID(), agent: .codex, model: "model"),
                                               ledgers: [.codex: ledger(90, at: today)])
        #expect(replaced.overview.tokens == 90)
        #expect(replaced.agent.tokens == 90)
        #expect(replaced.model.tokens == 90)
    }

    @Test("The year's activity ignores the span, follows the agent, and is rebuilt for a new snapshot or day")
    func activityIsIndependentOfTheSpan() async throws {
        let cache = SpendSummaryCache()
        let snapshot = UUID()
        let old = today.addingTimeInterval(-40 * 86400)
        let ledgers: [SpendAgent: UsageLedger] = [.codex: ledger(10, at: today), .claudeCode: ledger(20, at: old)]
        func request(days: Int?, agent: SpendAgent? = nil, id: UUID? = nil, date: Date? = nil) -> SpendSummaryCache.Request {
            .init(window: .init(snapshot: id ?? snapshot, days: days, today: date ?? today, calendar: calendar, language: "en"),
                  agent: agent, model: nil)
        }
        // A one-day span still carries the whole year.
        let day = try await cache.summaries(for: request(days: 1), ledgers: ledgers)
        #expect(day.overview.tokens == 10)
        #expect(day.activity.total == 30)
        let all = try await cache.summaries(for: request(days: nil), ledgers: ledgers)
        #expect(all.activity == day.activity)
        // Narrowed to an agent, it is that agent's year.
        let codex = try await cache.summaries(for: request(days: 1, agent: .codex), ledgers: ledgers)
        #expect(codex.activity.total == 10)
        let claude = try await cache.summaries(for: request(days: 7, agent: .claudeCode), ledgers: ledgers)
        #expect(claude.activity.total == 20)
        // A replacement snapshot and a new day are new figures.
        let replaced = try await cache.summaries(for: request(days: 1, id: UUID()), ledgers: [.codex: ledger(90, at: today)])
        #expect(replaced.activity.total == 90)
        let later = try await cache.summaries(
            for: request(days: 1, id: UUID(), date: today.addingTimeInterval(86400)), ledgers: [.codex: ledger(90, at: today)])
        #expect(later.activity.total == 90)
        #expect(later.activity.weeks.flatMap(\.drawn).last?.date == today.addingTimeInterval(86400))
    }

    @Test("A cancelled request cannot poison the next summary")
    func cancelledRequest() async throws {
        let cache = SpendSummaryCache()
        let request = SpendSummaryCache.Request(
            window: .init(snapshot: UUID(), days: 1, today: today, calendar: calendar, language: "en"), agent: nil, model: nil)
        let ledgers: [SpendAgent: UsageLedger] = [.codex: ledger(10, at: today)]
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await cache.summaries(for: request, ledgers: ledgers)
                Issue.record("A cancelled summary must not return figures")
            } catch is CancellationError {
                // Expected; a subsequent live request still computes this key.
            } catch { Issue.record("Unexpected error: \(error)") }
        }
        await cancelled.value
        let result = try await cache.summaries(for: request, ledgers: ledgers)
        #expect(result.overview.tokens == 10)
    }

    @Test("The figures on screen stay through a new span or snapshot, never into another agent or model")
    func displayScope() {
        let window = SpendSummaryCache.Window(snapshot: UUID(), days: 1, today: today, calendar: calendar, language: "en")
        let old = SpendSummaryCache.Request(window: window, agent: .codex, model: "one")
        let refreshed = SpendSummaryCache.Request(
            window: .init(snapshot: UUID(), days: 1, today: today, calendar: calendar, language: "en"), agent: .codex, model: "one")
        #expect(old != refreshed)
        #expect(refreshed.canKeepShowing(old))
        // A new span keeps the figures until its own land — no spinner, no
        // lost scroll position, as when this was main-thread arithmetic.
        let widened = SpendSummaryCache.Request(
            window: .init(snapshot: window.snapshot, days: 30, today: today, calendar: calendar, language: "zh-Hans"),
            agent: .codex, model: "one")
        #expect(widened.canKeepShowing(old))
        #expect(!old.canKeepShowing(.init(window: window, agent: .codex, model: "two")))
        #expect(!old.canKeepShowing(.init(window: window, agent: .claudeCode, model: "one")))
        let parent = SpendSummaryCache.Request(window: window, agent: .codex, model: nil)
        #expect(parent.canKeepShowing(old), "Back can immediately render the model list's existing summary")
        #expect(!old.canKeepShowing(parent), "A parent result does not contain the newly opened model")
    }
}
