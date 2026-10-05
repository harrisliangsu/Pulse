import Foundation
import Testing
@testable import Pulse

/// Which cards a recap gets: a card whose data is missing is left out.
@Suite("Recap deck")
struct RecapDeckTests {
    private static func deck(_ recap: Recap, price: Double? = 200, hidesProjects: Bool = false) -> RecapDeck {
        RecapDeck(recap: recap, monthlyPrice: price, hidesProjects: hidesProjects)
    }

    @Test("A full month has all six cards, in order")
    func fullMonth() {
        #expect(Self.deck(RecapSamples.month()).cards == [.poster, .opener, .calendar, .timetable, .payback, .scorecard])
    }

    @Test("A full year has the year's own cards")
    func fullYear() {
        #expect(Self.deck(RecapSamples.year()).cards
            == [.poster, .opener, .yearCalendar, .months, .timetable, .payback, .scorecard])
    }

    @Test("No price, no payback")
    func noPrice() {
        #expect(!Self.deck(RecapSamples.month(), price: nil).cards.contains(.payback))
        #expect(!Self.deck(RecapSamples.month(), price: 0).cards.contains(.payback))
        #expect(Self.deck(RecapSamples.month(), price: nil).payback == nil)
    }

    @Test("No cost, no payback, whatever the price")
    func noCost() {
        let deck = Self.deck(RecapSamples.month(priced: false))
        #expect(!deck.cards.contains(.payback))
        #expect(deck.payback == nil)
    }

    @Test("No hour shape, no timetable")
    func noHours() {
        #expect(!Self.deck(RecapSamples.month(hasHours: false)).cards.contains(.timetable))
    }

    @Test("No agents, no opener")
    func noAgents() {
        #expect(!Self.deck(RecapSamples.month(hasAgents: false)).cards.contains(.opener))
    }

    @Test("A recap with nothing in it has no deck")
    func empty() {
        #expect(Self.deck(RecapSamples.empty).cards.isEmpty)
    }

    @Test("The page counter counts the numbered cards the deck really has")
    func pageCounter() throws {
        let full = Self.deck(RecapSamples.month())
        #expect(full.stories.count == 5)
        #expect(full.page(of: .poster) == nil)
        #expect(try #require(full.page(of: .opener)) == (1, 5))
        #expect(try #require(full.page(of: .scorecard)) == (5, 5))

        let bare = Self.deck(RecapSamples.month(priced: false, hasHours: false, hasAgents: false), price: nil)
        #expect(bare.cards == [.poster, .calendar, .scorecard])
        #expect(try #require(bare.page(of: .calendar)) == (1, 2))
        #expect(try #require(bare.page(of: .scorecard)) == (2, 2))
        #expect(bare.page(of: .payback) == nil)
    }

    @Test("Payback divides the estimate by the price")
    func paybackMultiple() throws {
        let payback = try #require(Self.deck(RecapSamples.month()).payback)
        #expect(payback.months == 1)
        #expect(payback.paid == 200)
        #expect(abs(payback.multiple - 6.71) < 0.001)
    }

    @Test("A year's payback is against twelve months of the price")
    func yearPayback() throws {
        let payback = try #require(Self.deck(RecapSamples.year()).payback)
        #expect(payback.months == 12)
        #expect(payback.paid == 2400)
    }

    @Test("Hidden projects are numbered; shown ones keep their name")
    func projects() {
        let recap = RecapSamples.month()
        let shown = Self.deck(recap)
        let hidden = Self.deck(recap, hidesProjects: true)
        #expect(shown.projectName(0, recap.projects[0]) == "pulse")
        #expect(hidden.projectName(0, recap.projects[0]) == String.localized("Project \("1")"))
        #expect(hidden.projectName(2, recap.projects[2]) == String.localized("Project \("3")"))
        #expect(hidden.projectName(0, recap.projects[0]) != "pulse")
    }

    @Test("Money is left out of the cards when nothing was priced")
    func unpricedHidesMoney() {
        let deck = Self.deck(RecapSamples.month(priced: false))
        #expect(deck.recap.cost == nil)
        #expect(deck.provenance.first == String.localized("Counted from this Mac's local records"))
    }
}
