// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

// The numbered cards of a recap each have their own file: `RecapOpenerView`,
// `RecapCalendarView`, `RecapTimetableView`, `RecapPaybackView` and
// `RecapScorecardView`, with the year-only cards in `RecapYearViews.swift`.
// What they share is here and in `RecapTiles.swift`.

/// A thin rule across the card, in ink or in the paler grey.
struct RecapRule: View {
    var strong = false
    var body: some View {
        Rectangle()
            .fill(strong ? RecapColor.ink : RecapColor.rule)
            .frame(height: strong ? 2 : 1)
    }
}
