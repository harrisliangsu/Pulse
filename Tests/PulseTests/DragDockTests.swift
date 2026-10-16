import Foundation
import Testing
@testable import Pulse

/// Where a rail being dragged lands: which edge it fuses to, or how it stands
/// free (`PanelPlacement.dragDock`).
@Suite("Drag docking")
struct DragDockTests {
    /// A 16" laptop: 1169pt tall, 35pt of menu bar, 72pt of Dock.
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    private let visible = CGRect(x: 0, y: 72, width: 1800, height: 1062)
    private let across = CGSize(width: 900, height: 80)
    private let upright = CGSize(width: 64, height: 700)

    private func land(
        pointer: CGPoint,
        railAt origin: CGPoint,
        size: CGSize,
        from current: PanelDock,
        snaps: Bool = true
    ) -> PanelDock {
        let axis: PanelEdge.Axis = switch current {
        case .edge(let edge): edge.axis
        case .floating(let axis): axis
        }
        return PanelPlacement.dragDock(
            pointer: pointer,
            rail: CGRect(origin: origin, size: size),
            screen: screen,
            visible: visible,
            current: current,
            axis: axis,
            snaps: snaps
        )
    }

    @Test("A rail lying across stays across in a bottom corner, its end against the side (#85)")
    func acrossStaysAcrossInACorner() {
        // Held by the middle, the rail's right end is at the side while the
        // pointer is still 450pt from it.
        let dock = land(
            pointer: CGPoint(x: 1350, y: 200),
            railAt: CGPoint(x: 900, y: 160),
            size: across,
            from: .floating(.horizontal)
        )
        #expect(dock == .floating(.horizontal))
    }

    @Test("A rail lying across docks to a side once the pointer reaches it")
    func acrossDocksToASideByThePointer() {
        let right = land(
            pointer: CGPoint(x: 1790, y: 500),
            railAt: CGPoint(x: 900, y: 460),
            size: across,
            from: .floating(.horizontal)
        )
        let left = land(
            pointer: CGPoint(x: 10, y: 500),
            railAt: CGPoint(x: 0, y: 460),
            size: across,
            from: .edge(.top)
        )
        #expect(right == .edge(.right))
        #expect(left == .edge(.left))
    }

    @Test("An upright rail still docks to a side by its own edge")
    func uprightDocksByItsEdge() {
        let dock = land(
            pointer: CGPoint(x: 1750, y: 600),
            railAt: CGPoint(x: 1720, y: 300),
            size: upright,
            from: .floating(.vertical)
        )
        #expect(dock == .edge(.right))
    }

    @Test("The top, the bottom and the Dock's line are still the pointer's")
    func topAndBottomUnchanged() {
        let top = land(pointer: CGPoint(x: 900, y: 1125), railAt: CGPoint(x: 600, y: 400), size: upright, from: .floating(.vertical))
        let bottom = land(pointer: CGPoint(x: 900, y: 10), railAt: CGPoint(x: 450, y: 0), size: across, from: .floating(.horizontal))
        let aboveDock = land(pointer: CGPoint(x: 900, y: 90), railAt: CGPoint(x: 870, y: 72), size: upright, from: .floating(.vertical))
        #expect(top == .edge(.top))
        #expect(bottom == .edge(.bottom))
        #expect(aboveDock == .floating(.horizontal))
    }

    @Test("With snapping off a drag never docks or turns the rail")
    func snappingOff() {
        let cases: [(CGPoint, CGPoint, CGSize, PanelDock, PanelDock)] = [
            (CGPoint(x: 900, y: 1160), CGPoint(x: 450, y: 1000), across, .floating(.horizontal), .floating(.horizontal)),
            (CGPoint(x: 1790, y: 500), CGPoint(x: 900, y: 460), across, .floating(.horizontal), .floating(.horizontal)),
            (CGPoint(x: 900, y: 10), CGPoint(x: 868, y: 72), upright, .floating(.vertical), .floating(.vertical)),
            (CGPoint(x: 1790, y: 600), CGPoint(x: 1736, y: 300), upright, .edge(.right), .floating(.vertical)),
            (CGPoint(x: 900, y: 1160), CGPoint(x: 450, y: 1089), across, .edge(.top), .floating(.horizontal)),
        ]
        for (pointer, origin, size, from, expected) in cases {
            #expect(land(pointer: pointer, railAt: origin, size: size, from: from, snaps: false) == expected)
        }
    }

    @Test("With snapping off a free rail's room is the whole screen; otherwise, and docked, the usable area")
    func roomFollowsSnapping() {
        #expect(PanelPlacement.room(snaps: false, dock: .floating(.horizontal), visible: visible, screen: screen) == screen)
        #expect(PanelPlacement.room(snaps: false, dock: .floating(.vertical), visible: visible, screen: screen) == screen)
        #expect(PanelPlacement.room(snaps: true, dock: .floating(.horizontal), visible: visible, screen: screen) == visible)
        #expect(PanelPlacement.room(snaps: false, dock: .edge(.top), visible: visible, screen: screen) == visible)
    }

    @Test("A rail reaching over the menu bar or the Dock is beyond the usable area; one inside it is not")
    func beyondTheUsableArea() {
        // Top-left origins.
        #expect(!PanelPlacement.isBeyond(visible, railOrigin: CGPoint(x: 0, y: visible.maxY), rail: across))
        #expect(!PanelPlacement.isBeyond(visible, railOrigin: CGPoint(x: 900, y: visible.minY + across.height), rail: across))
        #expect(PanelPlacement.isBeyond(visible, railOrigin: CGPoint(x: 0, y: screen.maxY), rail: across))
        #expect(PanelPlacement.isBeyond(visible, railOrigin: CGPoint(x: 900, y: across.height), rail: across))
    }
}
