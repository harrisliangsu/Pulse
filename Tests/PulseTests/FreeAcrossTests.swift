import Foundation
import Testing
@testable import Pulse

extension PanelGlobalsSuite {
    /// A rail lying across the screen and standing free.
    ///
    /// It is the top dock's shape placed the way the upright floating rail is, so
    /// what has to hold is the part neither of those already pins: the card opens
    /// into the roomier half, the window keeps the rail where the ratios put it,
    /// and nothing about it is mistaken for the top dock.
    @Suite("Free across")
    struct FreeAcrossTests {
        /// A 16" laptop: 1169pt tall, 35pt of menu bar, 72pt of Dock.
        private let visible = CGRect(x: 0, y: 72, width: 1800, height: 1058)
        private var panel: CGSize { FloatingPanelController.Layout.size(for: .top) }
        private var rail: CGSize { DockLayout.size(for: 5, on: .horizontal, docked: false) }

        private func layout(_ h: Double, _ v: Double) -> (PanelPlacement, PanelPlacement.Layout) {
            let placement = PanelPlacement(dock: .floating(.horizontal), horizontalRatio: h, verticalRatio: v)
            return (placement, placement.layout(in: visible, topEdge: 1169, panel: panel, rail: rail))
        }

        @Test("The card opens down in the top half and up in the bottom half")
        func cardOpensIntoTheRoomierHalf() {
            #expect(layout(0.5, 0.2).0.edge == .top)
            #expect(layout(0.5, 0.8).0.edge == .bottom)
            #expect(layout(0.5, 0.8).0.edge.axis == .horizontal)
        }

        @Test("The window hangs down from the rail, or stands up from it")
        func windowFollowsTheCard() {
            let (_, high) = layout(0.5, 0.2)
            #expect(abs(high.frame.maxY - high.railOrigin.y) < 0.01)

            let (_, low) = layout(0.5, 0.8)
            #expect(abs(low.frame.minY - (low.railOrigin.y - rail.height)) < 0.01)
        }

        @Test("The rail goes where both ratios say, flush into the corners (#85)")
        func railIsPlacedByBothRatios() {
            for v in [0.0, 0.3, 0.7, 1.0] {
                for h in [0.0, 0.5, 1.0] {
                    let (_, placed) = layout(h, v)
                    let railBottom = placed.railOrigin.y - rail.height
                    #expect(abs(railBottom - (visible.minY + (1 - v) * (visible.height - rail.height))) < 0.01)
                    #expect(abs(placed.railOrigin.x - (visible.minX + h * (visible.width - rail.width))) < 0.01)
                    #expect(visible.contains(placed.frame), "h \(h), v \(v): \(placed.frame)")
                }
            }
        }

        @Test("With snapping off a rail lying across reaches the screen's own top and bottom (#85)")
        func reachesTheWholeScreenWithSnappingOff() {
            let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
            for v in [0.0, 1.0] {
                let placement = PanelPlacement(dock: .floating(.horizontal), horizontalRatio: 1, verticalRatio: v)
                placement.snapsToEdges = false
                let room = placement.room(visible: visible, screen: screen)
                let placed = placement.layout(in: room, topEdge: 1169, panel: panel, rail: rail)
                let expectedTop = v == 0 ? screen.maxY : screen.minY + rail.height
                #expect(abs(placed.railOrigin.y - expectedTop) < 0.01, "v \(v)")
                #expect(abs(placed.railOrigin.x + rail.width - screen.maxX) < 0.01)
                #expect(PanelPlacement.isBeyond(visible, railOrigin: placed.railOrigin, rail: rail))
            }
        }

        @Test("An upright free rail keeps off the sides only while snapping is on")
        func uprightMarginFollowsSnapping() {
            let upright = DockLayout.size(for: 5, on: .vertical, docked: false)
            let uprightPanel = FloatingPanelController.Layout.size(for: .right)
            for snaps in [true, false] {
                let margin = snaps ? PanelPlacement.dockDistance : 0
                for h in [0.0, 1.0] {
                    let placement = PanelPlacement(dock: .floating(.vertical), horizontalRatio: h, verticalRatio: 0.5)
                    placement.snapsToEdges = snaps
                    let placed = placement.layout(in: visible, topEdge: 1169, panel: uprightPanel, rail: upright)
                    let expected = h == 0 ? visible.minX + margin : visible.maxX - upright.width - margin
                    #expect(abs(placed.railOrigin.x - expected) < 0.01, "snaps \(snaps), h \(h)")
                }
            }
        }

        @Test("The two free placements are different docks, and neither is docked")
        func freePlacementsAreDistinct() {
            #expect(PanelDock.floating(.horizontal) != .floating(.vertical))
            #expect(!PanelDock.floating(.horizontal).isDocked)
            #expect(PanelDock.floating(.horizontal).edge == nil)
        }
    }
}
