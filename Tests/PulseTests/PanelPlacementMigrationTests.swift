import Foundation
import Testing
@testable import Pulse

/// What a stored placement comes back as.
///
/// Before there were two free placements, "free" was `panel.floating` alone
/// and always upright. Anyone who chose it then has no `panel.floatingAxis`,
/// and must get the upright rail they left, not one lying across.
@Suite("Panel placement migration")
struct PanelPlacementMigrationTests {
    /// The placement restored from a throwaway domain holding `values`, so
    /// nothing here reads or writes the real settings.
    private func restored(_ values: [String: Any]) -> PanelPlacement {
        let (defaults, cleanup) = TestDefaults.make("panelPlacement")
        defer { cleanup() }
        for (key, value) in values { defaults.set(value, forKey: key) }
        return PanelPlacement.restored(from: defaults)
    }

    @Test("A free placement stored before the axis existed stays upright")
    func earlierFreePlacementStaysUpright() {
        let placement = restored(["panel.floating": true])
        #expect(placement.dock == .floating(.vertical))
    }

    @Test("A stored axis is the one restored")
    func storedAxisIsRestored() {
        let across = restored(["panel.floating": true, "panel.floatingAxis": "horizontal"])
        #expect(across.dock == .floating(.horizontal))
        let upright = restored(["panel.floating": true, "panel.floatingAxis": "vertical"])
        #expect(upright.dock == .floating(.vertical))
    }

    @Test("An axis Pulse does not know is read as upright")
    func unknownAxisIsUpright() {
        let placement = restored(["panel.floating": true, "panel.floatingAxis": "diagonal"])
        #expect(placement.dock == .floating(.vertical))
    }

    @Test("A docked placement ignores the axis")
    func dockedIgnoresTheAxis() {
        let placement = restored([
            "panel.floating": false, "panel.edge": "top", "panel.floatingAxis": "horizontal",
        ])
        #expect(placement.dock == .edge(.top))
        #expect(restored([:]).dock == .edge(.right))
    }
}
