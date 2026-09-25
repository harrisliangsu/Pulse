import CoreGraphics
import Foundation
import Testing
@testable import Pulse

/// A pointer arriving on the panel is noticed and looked at, not snapped to.
///
/// Watching the pointer damps the mark's own gaze and takes most of the
/// expression's glance back out. That used to happen in the one frame the
/// pointer arrived, so every ring on the rail jerked to the cursor together.
/// `BotMarkEngine.attention` eases it over about 0.4s, after a short delay
/// that differs from mark to mark.
///
/// Measured as the sideways step of each eye's centre in the face's own
/// space, so the body's bounce does not count, and a blink — which scales an
/// eye about its centre — does not move it. The engine's own glances are random, so the
/// median of several runs is taken.
@Suite("Bot mark attention")
struct BotMarkAttentionTests {
    /// The largest sideways step of either eye against the body, in one frame
    /// at 60fps, over the half second after `from` — with the pointer
    /// arriving at `from` when one is given.
    static func worstGazeStep(persona: BotMarkPersona, pointer: CGPoint?, from: Double = 3) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 15))!
        let engine = BotMarkEngine()
        var previous: [Double]?
        var worst = 0.0
        var time = 0.0
        while time < from + 0.5 {
            let arrived = time >= from
            var programme = BotMarkProgramme.forMood(.idle, persona: persona, isPointedAt: false,
                                                     at: afternoon, calendar: calendar)
            programme.gazeBias = BotMarkGaze.left.bias
            programme.flipX = BotMarkGaze.left.mirrored
            programme.viewWidth = 28
            programme.pointer = arrived ? pointer : nil
            let frame = engine.advance(to: time, programme: programme)
            // An eye turned out of sight has no position worth comparing.
            let eyes = frame.eyes.map { eye -> Double in
                guard eye.visible else { return .nan }
                let box = eye.path.boundingBox
                return Double(CGPoint(x: box.midX, y: box.midY).applying(eye.transform).x)
            }
            if arrived, let previous, previous.count == eyes.count {
                for (a, b) in zip(previous, eyes) where a.isFinite && b.isFinite {
                    worst = max(worst, abs(a - b))
                }
            }
            previous = eyes
            time += 1.0 / 60
        }
        return worst
    }

    static func median(_ runs: Int, _ measure: () -> Double) -> Double {
        let values = (0..<runs).map { _ in measure() }.sorted()
        return values[values.count / 2]
    }

    /// Every persona but playful, whose gestures dart the eyes about thirty
    /// units in a frame on their own, pointer or not — a glance, and not
    /// something the pointer does. Measured when this was written: 30 to 60
    /// units in a frame on arrival before the fix, 1 to 5 after. Proud's own
    /// gestures dart too, in about one window in seven, which is why this is
    /// a median of twenty-one runs rather than one.
    @Test("The eyes travel to the pointer rather than jump",
          arguments: BotMarkPersona.allCases.filter { $0 != .playful })
    func arrivalIsEased(persona: BotMarkPersona) {
        let arriving = Self.median(21) { Self.worstGazeStep(persona: persona, pointer: CGPoint(x: 0.5, y: 0.2)) }
        #expect(arriving < 12, "\(persona)'s eyes moved \(arriving) units in one frame")
    }
}
