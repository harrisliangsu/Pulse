import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// A rail docked to the bottom of the screen: on the screen's own edge, level
/// with the Dock, so it can sit in the empty stretch either side of it.
@Suite("Bottom dock")
struct BottomDockTests {
    /// A 16" laptop: 1169pt tall, 35pt of menu bar, 72pt of Dock — which
    /// `visibleFrame` takes off the whole width.
    private let visible = CGRect(x: 0, y: 72, width: 1800, height: 1058)
    private let screenBottom: CGFloat = 0
    private var panel: CGSize { FloatingPanelController.Layout.size(for: .bottom) }
    private var rail: CGSize { DockLayout.size(for: 5, on: .horizontal, docked: true) }

    private func layout(_ h: Double) -> (PanelPlacement, PanelPlacement.Layout) {
        let placement = PanelPlacement(dock: .edge(.bottom), horizontalRatio: h, verticalRatio: 0.5)
        return (placement, placement.layout(in: visible, topEdge: 1169, bottomEdge: screenBottom, panel: panel, rail: rail))
    }

    @Test("The rail stands on the screen's own bottom, below the visible frame, and the window stands up from it")
    func standsOnTheScreenEdge() {
        let (placement, layout) = layout(0.1)
        #expect(placement.edge == .bottom)
        #expect(placement.isDocked)
        #expect(abs(layout.railOrigin.y - rail.height - screenBottom) < 0.01)
        #expect(abs(layout.frame.minY - screenBottom) < 0.01)
        #expect(layout.frame.height == panel.height)
    }

    @Test("Along the bottom the rail goes where the ratio says, from one side to the other")
    func slidesAlongTheBottom() {
        let (_, left) = layout(0)
        let (_, right) = layout(1)
        #expect(abs(left.railOrigin.x - visible.minX) < 0.01)
        #expect(abs(right.railOrigin.x + rail.width - visible.maxX) < 0.01)
        let (_, middle) = layout(0.5)
        #expect(abs(middle.railOrigin.x + rail.width / 2 - visible.midX) < 0.01)
    }

    @Test("The bottom berth is the top one upside down")
    func berthIsTheTopTurnedOver() {
        let rect = CGRect(origin: .zero, size: rail)
        let top = DockBerthShape(edge: .top, isDocked: true).path(in: rect)
        let bottom = DockBerthShape(edge: .bottom, isDocked: true).path(in: rect)
        #expect(abs(bottom.boundingRect.width - top.boundingRect.width) < 0.5)
        #expect(abs(bottom.boundingRect.height - top.boundingRect.height) < 0.5)
        for x in stride(from: 1.0, to: rect.width, by: 7) {
            for y in stride(from: 1.0, to: rect.height, by: 3) {
                #expect(top.contains(CGPoint(x: x, y: y)) == bottom.contains(CGPoint(x: x, y: rect.height - y)))
            }
        }
    }
}
