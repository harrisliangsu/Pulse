// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// `Pulse --recap 2026-09` / `--recap 2026`: one month's or one year's `Recap`,
/// as readable JSON on stdout — a way to see the real numbers behind the recap
/// cards without a window.
///
/// **It reads exactly as the Token spend pane does** (`RecapSource.load`:
/// `AgentLedgers.scan`, the agents present on this Mac, the same price table) and **only while Token
/// spend reading is on** (`AppSettings.storedReadsTokenSpend`): an explicit
/// command is not a reason to open stores the reader switched off. With it off
/// the command says so on stderr and exits 2.
///
/// **It writes nothing of its own.** No setting is stored (it uses the read-only
/// `storedReadsTokenSpend`, never `AppSettings`), no file is made beyond the
/// ledger and price caches the readers already keep. Like `--json` it is
/// dispatched before `LegacyDefaults.migrateIfNeeded()`.
///
/// A figure Pulse cannot stand behind is **absent from the JSON**, not zero;
/// nothing is translated. See [Docs/token-spend.md](../../Docs/token-spend.md#the-recap-and---recap).
enum RecapReport {
    static let modeArgument = "--recap"

    /// "2026-09" is a month, "2026" a year, and nothing at all is this month.
    static func period(from text: String?, now: Date = Date(), calendar: Calendar = Recap.calendar) -> Recap.Period? {
        guard let text else {
            let parts = calendar.dateComponents([.year, .month], from: now)
            return parts.year.flatMap { year in parts.month.map { .month(year: year, month: $0) } }
        }
        let pieces = text.split(separator: "-", omittingEmptySubsequences: false)
        switch pieces.count {
        case 1:
            guard pieces[0].count == 4, let year = Int(pieces[0]) else { return nil }
            return .year(year)
        case 2:
            guard pieces[0].count == 4, let year = Int(pieces[0]),
                  pieces[1].count == 2, let month = Int(pieces[1]), (1...12).contains(month) else { return nil }
            return .month(year: year, month: month)
        default:
            return nil
        }
    }

    /// Validates the arguments; the exit code of a refusal, or nil to go on.
    static func refusal(arguments: [String]) -> Int32? {
        guard period(from: value(in: arguments)) != nil else {
            fail("usage: Pulse --recap [YYYY-MM | YYYY]")
            return 2
        }
        guard AppSettings.storedReadsTokenSpend(in: .standard) else {
            fail("Token spend reading is off. Turn it on in Settings, then run this again.")
            return 2
        }
        return nil
    }

    private static func value(in arguments: [String]) -> String? {
        let at = arguments.firstIndex(of: modeArgument).map { $0 + 1 }
        return at.flatMap { $0 < arguments.count && !arguments[$0].hasPrefix("-") ? arguments[$0] : nil }
    }

    /// Prints the recap and exits.
    ///
    /// **Not a semaphore, unlike `UsageReport`.** The scan reports progress on
    /// the main actor, so a main thread parked on a semaphore would wait for a
    /// hop that can never run. The main queue is left running (`dispatchMain`)
    /// and the task ends the process.
    static func run(arguments: [String]) -> Never {
        if let code = refusal(arguments: arguments) { exit(code) }
        let period = period(from: value(in: arguments))!

        Task {
            guard let loaded = try? await RecapSource.load() else {
                fail("could not read the ledgers")
                exit(1)
            }
            guard let recap = await RecapSource.build(period, from: loaded),
                  let data = encode(recap) else {
                fail("could not build the recap")
                exit(1)
            }
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        }
        dispatchMain()
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("Pulse: \(message)\n".utf8))
    }

    static func encode(_ recap: Recap, calendar: Calendar = Recap.calendar) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try? encoder.encode(Report(recap, calendar: calendar))
    }

    // MARK: - Shape

    /// A day, as the calendar date it is in the reader's zone.
    private static func dateString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private struct Report: Encodable {
        struct Day: Encodable {
            let date: String
            let tokens: Int
            let cost: Double?
        }

        struct Month: Encodable {
            let month: Int
            let tokens: Int
            let cost: Double?
            let activeDays: Int
        }

        struct Model: Encodable {
            let name: String
            let tokens: Int
            let share: Double
            let cost: Double?
        }

        struct Agent: Encodable {
            let agent: String
            let name: String
            let tokens: Int
            let share: Double
            let activeDays: Int
            /// The days of those, as dates, oldest first.
            let days: [String]
            let cost: Double?
        }

        struct Project: Encodable {
            let name: String
            let tokens: Int
            let share: Double
            let sessions: Int
        }

        let period: String
        /// First day of the period, and the first day **after** the span (it
        /// stops at the end of today while the period is running).
        let start: String
        let end: String
        let inProgress: Bool
        let tokens: Int
        let cost: Double?
        /// Tokens with no published price: above zero, `cost` is a floor.
        let unpricedTokens: Int
        let currency: String
        let partial: Bool
        let previousTokens: Int?
        let activeDays: Int
        let elapsedDays: Int
        let sessions: Int
        let currentStreak: Int
        let longestStreak: Int
        let busiestDay: Day?
        let days: [Day]
        let months: [Month]
        let hours: [Int]?
        let peakHour: Int?
        let lateShare: Double?
        /// Minutes after midnight, 0..<300.
        let latestMinute: Int?
        let lateNights: Int
        let persona: String?
        let cacheHitRate: Double?
        let cacheSavings: Double?
        let models: [Model]
        let agents: [Agent]
        let projects: [Project]

        init(_ recap: Recap, calendar: Calendar) {
            switch recap.period {
            case .month(let year, let month): period = String(format: "%04d-%02d", year, month)
            case .year(let year): period = String(format: "%04d", year)
            }
            start = RecapReport.dateString(recap.start, calendar: calendar)
            end = RecapReport.dateString(recap.end, calendar: calendar)
            inProgress = recap.isInProgress
            tokens = recap.tokens
            cost = recap.cost
            unpricedTokens = recap.unpricedTokens
            currency = recap.currency
            partial = recap.isPartial
            previousTokens = recap.previousTokens
            activeDays = recap.activeDays
            elapsedDays = recap.elapsedDays
            sessions = recap.sessions
            currentStreak = recap.currentStreak
            longestStreak = recap.longestStreak
            busiestDay = recap.busiestDay.map {
                Day(date: RecapReport.dateString($0.date, calendar: calendar), tokens: $0.tokens, cost: $0.cost)
            }
            days = recap.days.map {
                Day(date: RecapReport.dateString($0.date, calendar: calendar), tokens: $0.tokens, cost: $0.cost)
            }
            months = recap.months.map {
                Month(month: $0.month, tokens: $0.tokens, cost: $0.cost, activeDays: $0.activeDays)
            }
            hours = recap.hours
            peakHour = recap.peakHour
            lateShare = recap.lateShare
            latestMinute = recap.latestMinute
            lateNights = recap.lateNights
            persona = recap.persona?.rawValue
            cacheHitRate = recap.cacheHitRate
            cacheSavings = recap.cacheSavings
            models = recap.models.map { Model(name: $0.name, tokens: $0.tokens, share: $0.share, cost: $0.cost) }
            agents = recap.agents.map {
                Agent(
                    agent: $0.agent.rawValue, name: $0.agent.displayName, tokens: $0.tokens,
                    share: $0.share, activeDays: $0.activeDays,
                    days: $0.activeDates.sorted().map { RecapReport.dateString($0, calendar: calendar) }, cost: $0.cost
                )
            }
            projects = recap.projects.map {
                Project(name: $0.name, tokens: $0.tokens, share: $0.share, sessions: $0.sessions)
            }
        }
    }
}
