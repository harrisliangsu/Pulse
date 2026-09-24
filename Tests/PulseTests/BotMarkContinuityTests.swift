import CoreGraphics
import Foundation
import Testing
@testable import Pulse

/// A change of state never moves the body further in one frame than the
/// mark's own motion does.
///
/// Several parts of the pose are drawn straight rather than through a spring —
/// celebrate's turns, a gesture's shake, a morph's pose — and each used to be
/// recomputed from the new state on the first frame after a switch. Interrupted
/// mid-motion by a scene beat, a mood, a one-shot or the pointer, the body
/// turned up to 144° or moved 108 units in one frame at 30fps, against ~15 for
/// the fastest ordinary motion. A one-frame glitch: easy to glimpse on the
/// rail, impossible to catch again by watching. `BotMarkEngine.render` now
/// hands the difference to springs that ease it away.
///
/// The scenario is deterministic; the engine's own glances and holds are not,
/// so the bound is set well above ordinary motion (measured maximum ~16 units
/// and ~15° over eighty simulated minutes) rather than at it.
@Suite("Bot mark continuity")
struct BotMarkContinuityTests {
    @Test("Interrupting a motion never teleports the body", arguments: BotMarkPersona.allCases)
    func switchesAreContinuous(persona: BotMarkPersona) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 15))!
        let centre = BotMarkLibrary.shared.headCentre

        var seed: UInt64 = 0x5eed + UInt64(BotMarkPersona.allCases.firstIndex(of: persona)!) * 7919
        func roll() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }

        var mood = BotMarkMood.idle
        var pointedAt = false
        var pointer: CGPoint?
        var event: BotMarkEvent?
        var eventEnds = 0.0
        var nextChange = 2.0
        let engine = BotMarkEngine()
        var previous: (point: CGPoint, degrees: Double)?
        var worstMove = 0.0
        var worstTurn = 0.0

        var time = 0.0
        while time < 90 {
            if time >= nextChange {
                let choice = roll()
                if choice < 0.35 {
                    let moods: [BotMarkMood] = [.idle, .idle, .working, .fetching, .spent, .unavailable]
                    mood = moods[Int(roll() * Double(moods.count))]
                } else if choice < 0.6 {
                    pointedAt.toggle()
                    pointer = pointedAt ? CGPoint(x: roll() * 2 - 1, y: roll() * 2 - 1) : nil
                } else if choice < 0.8 {
                    pointer = CGPoint(x: roll() * 2 - 1, y: roll() * 2 - 1)
                } else if choice < 0.9 {
                    event = .workFinished
                    eventEnds = time + 3
                } else {
                    event = .limitReset
                    eventEnds = time + 7
                }
                nextChange = time + 1 + roll() * 5
            }
            if event != nil, time > eventEnds { event = nil }

            var programme = BotMarkProgramme.forMood(mood, persona: persona, isPointedAt: pointedAt,
                                                     at: afternoon, calendar: calendar)
            programme.event = event
            programme.gazeBias = BotMarkGaze.left.bias
            programme.flipX = BotMarkGaze.left.mirrored
            programme.viewWidth = 28
            programme.pointer = pointer
            let transform = engine.advance(to: time, programme: programme).transform

            let point = CGPoint(x: centre, y: centre).applying(transform)
            // Explicit: CI's toolchain will not convert a CGFloat into the
            // tuple's Double on assignment, though a newer one does.
            let degrees = Double(atan2(transform.b, transform.a) * 180 / .pi)
            if let previous {
                worstMove = max(worstMove, Double(hypot(point.x - previous.point.x, point.y - previous.point.y)))
                let turned = abs(degrees - previous.degrees)
                worstTurn = max(worstTurn, min(turned, 360 - turned))
            }
            previous = (point, degrees)
            time += 1.0 / 30
        }

        #expect(worstMove < 30, "\(persona) moved \(worstMove) units in one frame")
        #expect(worstTurn < 30, "\(persona) turned \(worstTurn)° in one frame")
    }
}
