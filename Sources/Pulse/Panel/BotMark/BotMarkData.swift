import CoreGraphics
import Foundation
import SwiftUI

/// The upstream geometry and state tables, loaded from `bot-data.json`.
///
/// The JSON is produced by `Scripts/extract-bot-data.py` out of the upstream
/// `original-data.js` and `catalog.js`: 18 body shapes (a 96-point ring, the
/// original Bézier outline, eye-placement spans), 25 two-eye expressions of
/// 48 points each, and the per-state expression pools and cadences for all
/// 39 states. Nothing here is computed — it is the same numbers the web
/// component draws from.
struct BotMarkLibrary {
    let headCentre: Double
    let eyeHalf: Double
    let circleRing: [CGPoint]
    /// The confetti star, a unit outline scaled per particle.
    let starPath: CGPath
    let starGold: Color
    let shapes: [String: BotMarkShape]
    let shapeOrder: [String]
    let shapeLabels: [String: BotMarkLabel]
    /// 25 expressions, each a pair of eye rings.
    let expressions: [[[CGPoint]]]
    let states: [BotMarkStateInfo]

    /// How far off the head's centre the boldest expression puts its pair of
    /// eyes, in the upstream's units.
    ///
    /// **An expression is drawn already looking somewhere.** The glance is in
    /// the artwork rather than added on top of it, and across the twenty-five
    /// of them the pair's own centre runs from 44 units left of the head's to
    /// 76 right. That furthest one is as far as a face in this vocabulary ever
    /// looks, which makes it the natural ceiling for everything Pulse adds —
    /// see `BotMarkEngine.renderEyes`. Read from the data rather than written
    /// down, so re-extracting the table cannot leave a stale number here.
    let eyeReach: Double

    /// Loaded once and never written to afterwards; the drawing code that
    /// reads it all runs on the main actor.
    nonisolated(unsafe) static let shared: BotMarkLibrary = {
        guard let url = Bundle.module.url(forResource: "bot-data", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("bot-data.json is missing from the bundle")
        }
        do {
            return try BotMarkLibrary(decoding: data)
        } catch {
            fatalError("bot-data.json could not be decoded: \(error)")
        }
    }()

    func shape(_ identifier: String) -> BotMarkShape {
        shapes[identifier] ?? shapes["blob"]!
    }

    func state(_ identifier: String) -> BotMarkStateInfo {
        states.first { $0.id == identifier } ?? states[0]
    }
}

struct BotMarkLabel: Decodable {
    let en: String
    let zh: String
}

/// One body shape. `ring` is the 96-point outline every shape shares, which
/// is what makes shape-to-shape blending a point-by-point interpolation.
struct BotMarkShape {
    let ring: [CGPoint]
    /// The original outline. Used whenever the shape is neither turning nor
    /// mid-blend, because it is the real curve rather than a 96-point
    /// approximation of it.
    let path: CGPath
    let face: BotMarkFace
    let tiltScale: Double
    let beltRadius: Double
    let radius: Double
    let top: Double
    let bottom: Double
    let sides: Int
    /// Sphere list for the three shapes whose turn profile is solved in 3D.
    let solid: [[Double]]?
    /// 160 pre-sampled `(left, right)` pairs down the shape, so the eyes can
    /// be kept inside the silhouette without re-scanning the ring.
    let spanSamples: [(Double, Double)]?
}

/// Where the face sits on a given body, and how much of it there is.
struct BotMarkFace {
    var x: Double
    var y: Double
    var sx: Double
    var sy: Double
    var eye: Double

    static func blend(_ from: BotMarkFace, _ to: BotMarkFace, _ amount: Double) -> BotMarkFace {
        BotMarkFace(x: BotMath.mix(from.x, to.x, amount),
                       y: BotMath.mix(from.y, to.y, amount),
                       sx: BotMath.mix(from.sx, to.sx, amount),
                       sy: BotMath.mix(from.sy, to.sy, amount),
                       eye: BotMath.mix(from.eye, to.eye, amount))
    }
}

struct BotMarkStateInfo {
    let id: String
    let en: String
    let zh: String
    /// The one-shot effect this state morphs into, if any.
    let morph: String?
    /// Milliseconds between blinks. Nil means the state does not blink.
    let blinkCadence: (Double, Double)?
    /// Milliseconds between expression changes.
    let expressionCadence: (Double, Double)
    /// Which of the 25 expressions this state draws from.
    let expressionPool: [Int]
}

// MARK: - Decoding

private struct RawFile: Decodable {
    let headC: Double
    let eyeHalf: Double
    let circleRing: [[Double]]
    let starPath: [RawSegment]
    let starGold: String
    let shapes: [String: RawShape]
    let shapeOrder: [String]
    let shapeLabels: [String: BotMarkLabel]
    let expressions: [[[[Double]]]]
    let states: [RawState]
}

private struct RawShape: Decodable {
    let ring: [[Double]]
    let path: [RawSegment]
    let face: RawFace
    let tiltScale: Double
    let beltRadius: Double
    let radius: Double
    let top: Double
    let bottom: Double
    let sides: Int
    let solid: [[Double]]?
    let spanSamples: [[Double]]?
}

private struct RawFace: Decodable {
    let x: Double
    let y: Double
    let sx: Double
    let sy: Double
    let eye: Double
}

private struct RawSegment: Decodable {
    let op: String
    let values: [Double]
}

private struct RawState: Decodable {
    let id: String
    let en: String
    let zh: String
    let morph: String?
    let blinkCadence: [Double]?
    let expressionCadence: [Double]
    let expressionPool: [Int]
}

extension BotMarkLibrary {
    init(decoding data: Data) throws {
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        headCentre = raw.headC
        eyeHalf = raw.eyeHalf
        circleRing = raw.circleRing.map(BotMarkLibrary.point)
        starPath = BotMarkLibrary.path(raw.starPath)
        starGold = BotMarkPalette.rgb(UInt32(raw.starGold.dropFirst(), radix: 16) ?? 0xf4c34e)
        shapeOrder = raw.shapeOrder
        shapeLabels = raw.shapeLabels
        expressions = raw.expressions.map { $0.map { $0.map(BotMarkLibrary.point) } }
        // Empty rings are skipped rather than divided by. A malformed table
        // would otherwise make this NaN, and `eyeReach` is a clamp bound —
        // NaN there is every eye on the rail positioned at NaN and nothing
        // drawn, with no error anywhere to say why.
        eyeReach = expressions.reduce(0.0) { furthest, pair in
            let centres = pair.compactMap { ring -> Double? in
                guard !ring.isEmpty else { return nil }
                return ring.reduce(0.0) { $0 + Double($1.x) } / Double(ring.count)
            }
            guard !centres.isEmpty else { return furthest }
            let centre = centres.reduce(0, +) / Double(centres.count)
            return max(furthest, abs(centre - raw.headC))
        }
        states = raw.states.map { state in
            BotMarkStateInfo(
                id: state.id, en: state.en, zh: state.zh, morph: state.morph,
                blinkCadence: state.blinkCadence.flatMap {
                    $0.count == 2 ? (min($0[0], $0[1]), max($0[0], $0[1])) : nil
                },
                expressionCadence: (state.expressionCadence[0], state.expressionCadence[1]),
                expressionPool: state.expressionPool)
        }
        shapes = raw.shapes.mapValues { shape in
            BotMarkShape(
                ring: shape.ring.map(BotMarkLibrary.point),
                path: BotMarkLibrary.path(shape.path),
                face: BotMarkFace(x: shape.face.x, y: shape.face.y,
                                     sx: shape.face.sx, sy: shape.face.sy, eye: shape.face.eye),
                tiltScale: shape.tiltScale,
                beltRadius: shape.beltRadius,
                radius: shape.radius,
                top: shape.top,
                bottom: shape.bottom,
                sides: shape.sides,
                solid: shape.solid,
                spanSamples: shape.spanSamples.map { samples in
                    samples.map { ($0[0], $0[1]) }
                })
        }
    }

    private static func point(_ pair: [Double]) -> CGPoint {
        CGPoint(x: pair[0], y: pair[1])
    }

    /// Replays the pre-parsed outline. The extractor has already reduced the
    /// upstream path to absolute M/L/C/Q/Z segments.
    private static func path(_ segments: [RawSegment]) -> CGPath {
        let path = CGMutablePath()
        for segment in segments {
            let values = segment.values
            switch segment.op {
            case "M":
                path.move(to: CGPoint(x: values[0], y: values[1]))
            case "L":
                path.addLine(to: CGPoint(x: values[0], y: values[1]))
            case "C":
                path.addCurve(to: CGPoint(x: values[4], y: values[5]),
                              control1: CGPoint(x: values[0], y: values[1]),
                              control2: CGPoint(x: values[2], y: values[3]))
            case "Q":
                path.addQuadCurve(to: CGPoint(x: values[2], y: values[3]),
                                  control: CGPoint(x: values[0], y: values[1]))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}
