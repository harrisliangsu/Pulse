import Foundation
import Testing
@testable import Pulse

/// The segmented bar's ticks (`UsageBar.ticks`): as many as fit, lit in
/// proportion, never all for a limit not spent nor none for one touched.
@Suite("Usage bar ticks")
struct UsageBarTests {
    @Test("As many ticks as fit the width, with their gaps")
    func count() {
        // 4.5pt a tick and its gap, less the last gap: (200 + 2) / 4.5 = 44.9.
        #expect(UsageBar.ticks(width: 200, fraction: 0).count == 44)
        #expect(UsageBar.ticks(width: 200, fraction: 0, scale: 2).count == 22)
        #expect(UsageBar.ticks(width: 0, fraction: 0.5).count == 1)
    }

    @Test("Lit in proportion, at least one once touched, all only when spent")
    func lit() {
        #expect(UsageBar.ticks(width: 200, fraction: 0).lit == 0)
        #expect(UsageBar.ticks(width: 200, fraction: 0.001).lit == 1)
        #expect(UsageBar.ticks(width: 200, fraction: 0.5).lit == 22)
        #expect(UsageBar.ticks(width: 200, fraction: 0.999).lit == 43)
        #expect(UsageBar.ticks(width: 200, fraction: 1).lit == 44)
        #expect(UsageBar.ticks(width: 200, fraction: 1.4).lit == 44)
        #expect(UsageBar.ticks(width: 200, fraction: -1).lit == 0)
    }

    @Test("A segmented bar is taller on the card, and the card's budget knows it")
    func budget() {
        #expect(UsageBar.segmentedHeight > UsageBar.continuousHeight)
    }
}
