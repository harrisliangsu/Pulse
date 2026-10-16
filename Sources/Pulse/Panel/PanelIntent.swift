// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Telling a pointer that means the panel from one that is passing by.
///
/// At a notch the collapsed rail has no surface of its own: the target is the
/// camera housing, which lies on the way between the two halves of the menu
/// bar. Opening the moment the pointer crossed it put the rail over whatever
/// the pointer was heading for, and a click aimed there landed on a ring.
enum PanelIntent {
    /// How long the pointer stays in the housing before the rail opens.
    ///
    /// A pointer crossing the housing on its way across the menu bar is out
    /// of it again well inside this; one that has stopped there is not.
    static let notchDwell: Duration = .milliseconds(250)

    /// How long after the rail opens a press on a ring is not taken as a click.
    ///
    /// A press this soon was started before the rings were there to aim at:
    /// it was meant for what was under the pointer a moment earlier.
    static let ringClickGuard: TimeInterval = 0.3

    /// The camera housing above a notch rail, in the panel's top-left space.
    static func notchHousing(rail: CGRect, notchSize: CGSize) -> CGRect {
        CGRect(x: rail.midX - notchSize.width / 2, y: rail.minY - notchSize.height,
               width: notchSize.width, height: notchSize.height)
    }

    /// Whether a press that began at `pressedAt` may refresh a ring on a rail
    /// that opened at `railOpenedAt`. Nil means the rail is not open.
    static func acceptsRingClick(pressedAt: Date, railOpenedAt: Date?) -> Bool {
        guard let railOpenedAt else { return false }
        return pressedAt.timeIntervalSince(railOpenedAt) >= ringClickGuard
    }
}
