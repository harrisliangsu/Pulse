// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
#if DEBUG
import Foundation

/// Made-up recaps for previews and the review render. Not a code path the app
/// ships: the numbers are the design mockup's (8.4亿 tokens in September 2026,
/// $1,342, 27 of 30 days, 412 sessions, peak at 23:00) worked out so they agree
/// with one another, and a year to go with them.
enum RecapSamples {
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// Tokens by hour of day, a night owl's: 62% of it from 21:00 to 04:59.
    private static let hourWeights: [Double] = [
        180, 115, 51, 20, 8, 2, 2, 4, 10, 25, 40, 55,
        50, 48, 60, 66, 62, 58, 50, 64, 78, 225, 246, 256,
    ]

    private static func hours(total: Int) -> [Int] {
        let weight = hourWeights.reduce(0, +)
        return hourWeights.map { Int($0 / weight * Double(total)) }
    }

    private static let sampleAgents: [(SpendAgent, Double, Int)] = [
        (.claudeCode, 0.58, 27), (.codex, 0.29, 21), (.openCode, 0.08, 9), (.gemini, 0.04, 6), (.kiro, 0.01, 3),
    ]

    /// The agents' shares, each with its own days: the first worked on every day
    /// with any work, the others on an evenly spread few of them, so what the
    /// agents did on a day is never more than the day had.
    private static func agentShares(total: Int, days: [Recap.Day], scale: Int) -> [Recap.AgentShare] {
        let active = days.filter { $0.tokens > 0 }.map(\.date)
        return sampleAgents.enumerated().map { index, row in
            let count = min(row.2 * scale, active.count)
            let dates = index == 0 ? active : (0..<count).map { active[($0 * active.count + index) / count % active.count] }
            return Recap.AgentShare(
                agent: row.0, tokens: Int(row.1 * Double(total)), share: row.1,
                activeDays: Set(dates).count, cost: nil, activeDates: Set(dates)
            )
        }
    }

    private static let sampleModels: [(String, Double, Double)] = [
        ("Claude Opus", 0.41, 812), ("GPT-5.6 Sol", 0.23, 268), ("Claude Sonnet", 0.17, 154),
        ("GPT-5.6 mini", 0.11, 61), ("GLM-5", 0.08, 47),
    ]

    private static let sampleProjects: [(String, Double, Int)] = [
        ("pulse", 0.38, 168), ("agent-lab", 0.21, 94), ("notes-site", 0.14, 61),
    ]

    /// A tiny deterministic generator, so the sample year is the same every run.
    private struct Lehmer {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    // MARK: - Month

    /// September 2026, finished (or another month of 2026, with the same days
    /// repeated or cut to its length, to look at a month that takes six weeks).
    static func month(
        monthNumber: Int = 9,
        agentCount: Int = 5,
        priced: Bool = true,
        hasHours: Bool = true,
        hasAgents: Bool = true,
        hasCache: Bool = true,
        persona: Recap.Persona? = .nightOwl,
        isInProgress: Bool = false,
        unpricedShare: Double = 0,
        cacheSavings: Double = 410,
        throughDay: Int? = nil
    ) -> Recap {
        // The 1st is a Tuesday; days 4, 10 and 11 are quiet.
        // `throughDay` is a month still running: only the days so far, so the
        // rest are to come.
        let weights: [Double] = [
            55, 70, 40, 0, 35, 90, 80, 62, 66, 0, 0, 74, 100, 88, 60,
            45, 120, 96, 60, 72, 84, 64, 78, 92, 86, 58, 66, 70, 82, 66,
        ]
        let tokensPerWeight = 428_800.0
        let costPerToken = 1342.0 / 840_019_200.0
        let monthLength = calendar.range(of: .day, in: .month, for: date(2026, monthNumber, 1))?.count ?? 30
        let length = min(throughDay ?? monthLength, monthLength)
        let days = (0..<length).map { index -> Recap.Day in
            let tokens = Int(weights[index % weights.count] * tokensPerWeight)
            return Recap.Day(date: date(2026, monthNumber, index + 1), tokens: tokens,
                             cost: priced && tokens > 0 ? Double(tokens) * costPerToken : nil)
        }
        let total = days.reduce(0) { $0 + $1.tokens }
        let busiest = days.max { $0.tokens < $1.tokens }
        let streaks = Recap.streaks(of: days, isInProgress: isInProgress)
        return Recap(
            period: .month(year: 2026, month: monthNumber),
            start: date(2026, monthNumber, 1),
            end: throughDay.map { date(2026, monthNumber, $0 + 1) } ?? date(2026, monthNumber + 1, 1),
            isInProgress: isInProgress,
            tokens: total, cost: priced ? (throughDay == nil ? 1342 : Double(total) * costPerToken) : nil,
            unpricedTokens: Int(unpricedShare * Double(total)),
            previousTokens: Int(Double(total) / 1.38),
            activeDays: days.filter { $0.tokens > 0 }.count, elapsedDays: length,
            sessions: throughDay == nil ? 412 : 14 * length,
            days: days, months: [],
            hours: hasHours ? hours(total: total) : nil,
            peakHour: hasHours ? 23 : nil, lateShare: hasHours ? 0.62 : nil,
            latestMinute: 134, lateNights: 11, persona: persona,
            models: sampleModels.map {
                Recap.ModelShare(name: $0.0, tokens: Int($0.1 * Double(total)), share: $0.1, cost: priced ? $0.2 : nil)
            },
            agents: hasAgents ? Array(agentShares(total: total, days: days, scale: 1).prefix(agentCount)) : [],
            projects: sampleProjects.map {
                Recap.ProjectShare(name: $0.0, tokens: Int($0.1 * Double(total)), share: $0.1, sessions: $0.2)
            },
            cacheHitRate: hasCache ? 0.91 : nil, cacheSavings: hasCache && priced ? cacheSavings : nil,
            currentStreak: streaks.current, longestStreak: streaks.longest, busiestDay: busiest,
            currency: "USD", isPartial: false
        )
    }

    // MARK: - Year

    /// 2025, finished: 6.76 billion tokens, September the busiest month.
    static func year(priced: Bool = true, throughMonth: Int? = nil) -> Recap {
        let monthTotals: [Double] = [310, 280, 420, 390, 520, 610, 580, 640, 840, 770, 710, 690].map { $0 * 1_000_000 }
        let costPerToken = 9820.0 / monthTotals.reduce(0, +)
        var random = Lehmer(state: 2025)
        var days: [Recap.Day] = []
        var months: [Recap.Month] = []
        for month in 1...12 {
            // A year still running has nothing in the months to come.
            if let through = throughMonth, month > through {
                months.append(Recap.Month(month: month, tokens: 0, cost: nil, activeDays: 0))
                continue
            }
            let count = calendar.range(of: .day, in: .month, for: date(2025, month, 1))?.count ?? 30
            let weights = (1...count).map { day -> Double in
                let weekday = calendar.component(.weekday, from: date(2025, month, day))
                let quiet = random.next() < (weekday == 1 || weekday == 7 ? 0.28 : 0.07)
                return quiet ? 0 : 0.35 + 0.65 * random.next()
            }
            let scale = monthTotals[month - 1] / weights.reduce(0, +)
            let monthDays = weights.enumerated().map { index, weight -> Recap.Day in
                let tokens = Int(weight * scale)
                return Recap.Day(date: date(2025, month, index + 1), tokens: tokens,
                                 cost: priced && tokens > 0 ? Double(tokens) * costPerToken : nil)
            }
            days += monthDays
            let tokens = monthDays.reduce(0) { $0 + $1.tokens }
            months.append(Recap.Month(month: month, tokens: tokens, cost: priced ? Double(tokens) * costPerToken : nil,
                                      activeDays: monthDays.filter { $0.tokens > 0 }.count))
        }
        let total = days.reduce(0) { $0 + $1.tokens }
        let streaks = Recap.streaks(of: days, isInProgress: false)
        return Recap(
            period: .year(2025),
            start: date(2025, 1, 1), end: date(2026, 1, 1), isInProgress: throughMonth != nil,
            tokens: total, cost: priced ? 9820 : nil, unpricedTokens: 0, previousTokens: Int(Double(total) / 2.4),
            activeDays: days.filter { $0.tokens > 0 }.count, elapsedDays: days.count, sessions: 3214,
            days: days, months: months,
            hours: hours(total: total), peakHour: 23, lateShare: 0.62,
            latestMinute: 207, lateNights: 96, persona: .nightOwl,
            models: sampleModels.map {
                Recap.ModelShare(name: $0.0, tokens: Int($0.1 * Double(total)), share: $0.1, cost: priced ? $0.2 * 7.3 : nil)
            },
            agents: agentShares(total: total, days: days, scale: 10),
            projects: sampleProjects.map {
                Recap.ProjectShare(name: $0.0, tokens: Int($0.1 * Double(total)), share: $0.1, sessions: $0.2 * 7)
            },
            cacheHitRate: 0.89, cacheSavings: priced ? 3120 : nil,
            currentStreak: streaks.current, longestStreak: streaks.longest, busiestDay: days.max { $0.tokens < $1.tokens },
            currency: "USD", isPartial: false
        )
    }

    /// A month in which nothing was recorded.
    static var empty: Recap {
        Recap(
            period: .month(year: 2026, month: 9),
            start: date(2026, 9, 1), end: date(2026, 10, 1), isInProgress: false,
            tokens: 0, cost: nil, unpricedTokens: 0, previousTokens: nil, activeDays: 0, elapsedDays: 30, sessions: 0,
            days: [], months: [], hours: nil, peakHour: nil, lateShare: nil, latestMinute: nil, lateNights: 0,
            persona: nil, models: [], agents: [], projects: [], cacheHitRate: nil, cacheSavings: nil,
            currentStreak: 0, longestStreak: 0, busiestDay: nil, currency: "USD", isPartial: false
        )
    }

    // MARK: - Decks

    static var monthDeck: RecapDeck { RecapDeck(recap: month(), monthlyPrice: 200, hidesProjects: false) }
    static var yearDeck: RecapDeck { RecapDeck(recap: year(), monthlyPrice: 200, hidesProjects: false) }
}
#endif
