import Foundation
import Testing
@testable import Pulse

extension PanelGlobalsSuite {
    @Suite("Pointer intent at the notch")
    @MainActor
    struct PanelIntentTests {
        private let visible = CGRect(x: 0, y: 72, width: 1800, height: 1058)
        private let notch = CGRect(x: 791, y: 1131, width: 221, height: 38)

        @Test("The dwell target is the physical notch, wherever the rail is in the window")
        func housingIsTheNotch() {
            let placement = PanelPlacement(dock: .edge(.top), horizontalRatio: 0.2)
            placement.notch = notch
            let panel = FloatingPanelController.Layout.size(for: .top, notchSize: notch.size, capacity: 12)
            for count in [1, 6, 12] {
                let rail = DockLayout.size(for: count, on: .horizontal)
                let layout = placement.layout(in: visible, topEdge: visible.maxY, panel: panel, rail: rail)
                let offsets = PanelPlacement.offsets(forRailTopLeft: layout.railOrigin, in: layout.frame, rail: rail)
                let localRail = CGRect(x: offsets.leading, y: offsets.top, width: rail.width, height: rail.height)
                let housing = PanelIntent.notchHousing(rail: localRail, notchSize: notch.size)
                // Back to screen space: the window's top-left origin, flipped.
                let onScreen = CGRect(x: layout.frame.minX + housing.minX,
                                      y: layout.frame.maxY - housing.maxY,
                                      width: housing.width, height: housing.height)
                #expect(abs(onScreen.minX - notch.minX) < 0.01)
                #expect(abs(onScreen.minY - notch.minY) < 0.01)
                #expect(onScreen.size == notch.size)
                // Above the rings, never over them.
                #expect(housing.maxY == localRail.minY)
            }
        }

        @Test("A press too soon after the rail opens is not a ring click")
        func ringClickGuard() {
            let opened = Date(timeIntervalSinceReferenceDate: 1000)
            #expect(!PanelIntent.acceptsRingClick(pressedAt: opened, railOpenedAt: nil))
            #expect(!PanelIntent.acceptsRingClick(pressedAt: opened, railOpenedAt: opened))
            #expect(!PanelIntent.acceptsRingClick(pressedAt: opened.addingTimeInterval(0.1), railOpenedAt: opened))
            #expect(PanelIntent.acceptsRingClick(
                pressedAt: opened.addingTimeInterval(PanelIntent.ringClickGuard + 0.01), railOpenedAt: opened))
            #expect(PanelIntent.acceptsRingClick(pressedAt: opened.addingTimeInterval(5), railOpenedAt: opened))
        }

        @Test("The dwell outlasts a crossing and stays short of a wait")
        func dwellBounds() {
            // 221pt of housing crossed at a brisk 1000pt/s takes about 220ms;
            // past half a second, pointing at the notch starts to feel ignored.
            #expect(PanelIntent.notchDwell >= .milliseconds(200))
            #expect(PanelIntent.notchDwell <= .milliseconds(400))
        }
    }
}
