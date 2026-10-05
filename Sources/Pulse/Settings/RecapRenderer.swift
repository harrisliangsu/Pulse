// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// One card of a deck, chosen by case.
struct RecapCardView: View {
    let deck: RecapDeck
    let card: RecapCard

    var body: some View {
        Group {
            switch card {
            case .poster: RecapPosterView(deck: deck)
            case .opener: RecapOpenerView(deck: deck)
            case .calendar: RecapCalendarView(deck: deck)
            case .yearCalendar: RecapYearCalendarView(deck: deck)
            case .months: RecapMonthsView(deck: deck)
            case .timetable: RecapTimetableView(deck: deck)
            case .payback: RecapPaybackView(deck: deck)
            case .scorecard: RecapScorecardView(deck: deck)
            }
        }
        // The cards are paper whatever the Mac is set to: their colours are
        // fixed, and nothing in them should pick up the system's dark text.
        .environment(\.colorScheme, .light)
    }
}

/// Turns a card into a PNG.
///
/// `ImageRenderer` draws SwiftUI without a window, which is why the cards stay
/// to flat shapes and system text — no materials, no glass, no AppKit-backed
/// controls, none of which it can draw.
@MainActor
enum RecapRenderer {
    /// Every card is 1080 × 1920 points, rendered at scale 1: 1080 × 1920 pixels.
    static let cardSize = CGSize(width: 1080, height: 1920)

    static func image(of card: RecapCard, in deck: RecapDeck) -> CGImage? {
        let renderer = ImageRenderer(content: RecapCardView(deck: deck, card: card))
        renderer.proposedSize = ProposedViewSize(cardSize)
        renderer.scale = 1
        return renderer.cgImage
    }

    static func png(of card: RecapCard, in deck: RecapDeck) -> Data? {
        guard let image = image(of: card, in: deck) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

#if DEBUG
#Preview("Poster · month") {
    RecapCardView(deck: RecapSamples.monthDeck, card: .poster)
}

#Preview("Opener") {
    RecapCardView(deck: RecapSamples.monthDeck, card: .opener)
}

#Preview("Calendar") {
    RecapCardView(deck: RecapSamples.monthDeck, card: .calendar)
}

#Preview("Timetable") {
    RecapCardView(deck: RecapSamples.monthDeck, card: .timetable)
}

#Preview("Payback") {
    RecapCardView(deck: RecapSamples.monthDeck, card: .payback)
}

#Preview("Scorecard") {
    RecapCardView(deck: RecapSamples.monthDeck, card: .scorecard)
}

#Preview("Scorecard · running month") {
    RecapCardView(
        deck: RecapDeck(recap: RecapSamples.month(isInProgress: true, throughDay: 12), monthlyPrice: 200, hidesProjects: false),
        card: .scorecard
    )
}

#Preview("Scorecard · year") {
    RecapCardView(deck: RecapSamples.yearDeck, card: .scorecard)
}

#Preview("Poster · year") {
    RecapCardView(deck: RecapSamples.yearDeck, card: .poster)
}

#Preview("Year calendar") {
    RecapCardView(deck: RecapSamples.yearDeck, card: .yearCalendar)
}

#Preview("Months") {
    RecapCardView(deck: RecapSamples.yearDeck, card: .months)
}
#endif
