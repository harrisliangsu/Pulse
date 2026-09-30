import Foundation
import Testing
@testable import Pulse

/// Which providers the detailed card can show a history for, from where, and
/// how several agents' records become one.
struct CardHistoryTests {
    @Test func eachSourceGoesToTheProvidersItBelongsTo() {
        #expect(Provider.claudeCode.cardHistory == .transcripts)
        #expect(Provider.codex.cardHistory == .transcripts)
        // The statistics Z.ai and Zhipu publish: asked of the provider, not read here.
        #expect(Provider.zai.cardHistory == .accountStatistics)
        #expect(Provider.glmCoding.cardHistory == .accountStatistics)
        #expect(Provider.kimiCode.cardHistory == .agents([.kimiCLI]))
        // A provider with no records anywhere has no section to show.
        #expect(Provider.deepSeek.cardHistory == nil)
    }

    @Test func onlyThisMacsRecordsWaitForTokenSpend() {
        #expect(CardHistorySource.transcripts.readsThisMac)
        #expect(CardHistorySource.agents([.grok]).readsThisMac)
        #expect(!CardHistorySource.accountStatistics.readsThisMac)
    }

    @Test func severalAgentsAddUpDayByDayWithTheGapsClosed() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        func day(_ offset: Int, _ tokens: Int, _ model: String) -> LedgerDay {
            LedgerDay(date: calendar.date(byAdding: .day, value: offset, to: start)!,
                      tokens: tokens, cost: Double(tokens) / 100, unpricedTokens: 0, models: [model: tokens])
        }
        func ledger(_ days: [LedgerDay]) -> UsageLedger {
            UsageLedger(days: days, earliest: days.first?.date, unpricedModels: [], modelNames: [:], slots: [])
        }

        let added = UsageLedger.adding([
            ledger([day(0, 100, "a"), day(1, 50, "a")]),
            ledger([day(1, 30, "b"), day(3, 20, "b")]),
            .empty,
        ])

        #expect(added.days.map(\.tokens) == [100, 80, 0, 20])
        #expect(added.days[1].models == ["a": 50, "b": 30])
        #expect(abs(added.allTime.cost - 2.0) < 0.0001)
        #expect(added.earliest == start)
    }

    @Test func oneLedgerIsPassedThroughUntouched() {
        let only = UsageLedger(days: [LedgerDay(date: Date(timeIntervalSince1970: 0), tokens: 5, cost: 0,
                                                unpricedTokens: 5, models: [:])],
                               earliest: nil, unpricedModels: ["x"], modelNames: [:], slots: [])
        #expect(UsageLedger.adding([.empty, only]) == only)
        #expect(UsageLedger.adding([]).days.isEmpty)
    }
}
