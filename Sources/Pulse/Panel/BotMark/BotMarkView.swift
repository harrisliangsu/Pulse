import SwiftUI

/// Draws one frame of the mark.
///
/// The frame is in the upstream's own unit space, so all this adds is the
/// viewBox mapping — `-15 -15 259 259`, the box the web component uses, which
/// is what keeps the margin around the body the same at 16pt as at 200.
func drawBotMark(_ frame: BotMarkFrame, config: BotMarkConfig,
                 in context: inout GraphicsContext, size: CGSize) {
    let extent = min(size.width, size.height)
    let scale = extent / (frame.viewBoxRadius * 2)
    let origin = BotMarkFrame.viewBoxCentre - frame.viewBoxRadius
    var base = CGAffineTransform(scaleX: scale, y: scale)
        .translatedBy(x: -origin, y: -origin)
    if frame.flipX {
        base = base.concatenating(
            CGAffineTransform(translationX: extent / 2, y: 0)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -extent / 2, y: 0))
    }

    func paint(_ items: [BotMarkFrame.Painted], in context: inout GraphicsContext) {
        for item in items {
            var transform = base
            guard let path = item.path.copy(using: &transform) else { continue }
            var layer = context
            layer.opacity = item.opacity
            switch item.paint {
            case .solid(let colour):
                layer.fill(Path(path), with: .color(colour))
            case .gradient(let stops, let from, let to):
                layer.fill(Path(path), with: .linearGradient(
                    Gradient(colors: stops),
                    startPoint: from.applying(base), endPoint: to.applying(base)))
            }
        }
    }

    paint(frame.backParticles, in: &context)

    // Morph parts and humming markers sit under the character and take the
    // body's colour, as the upstream layers them.
    for shape in frame.shapes {
        var transform = base
        guard let path = shape.path.copy(using: &transform) else { continue }
        let tint = config.color.opacity(shape.opacity)
        if let width = shape.strokeWidth {
            context.stroke(Path(path), with: .color(tint),
                           style: StrokeStyle(lineWidth: width * scale,
                                              lineCap: .round, lineJoin: .round))
        } else {
            context.fill(Path(path), with: .color(tint))
        }
    }

    var combined = frame.transform.concatenating(base)
    guard let headPath = frame.headPath.copy(using: &combined) else { return }
    let head = Path(headPath)
    var character = context
    character.opacity = frame.opacity
    character.fill(head, with: .color(config.color))

    var eyeLayer = character
    eyeLayer.clip(to: head)
    for eye in frame.eyes where eye.visible {
        var eyeTransform = eye.transform.concatenating(combined)
        guard let path = eye.path.copy(using: &eyeTransform) else { continue }
        eyeLayer.fill(Path(path), with: .color(config.eyeColor))
    }

    paint(frame.frontParticles, in: &context)

    if let badge = frame.badge {
        let rect = CGRect(x: badge.centre.x - badge.radius, y: badge.centre.y - badge.radius,
                          width: badge.radius * 2, height: badge.radius * 2)
        let path = Path(ellipseIn: rect).applying(combined)
        character.stroke(path, with: .color(config.eyeColor), lineWidth: 10 * scale)
        character.fill(path, with: .color(config.badgeColor))
    }
}

/// Which way a mark habitually looks.
///
/// A rail against the right-hand edge of the screen has everything worth
/// looking at to its left, and a mark staring off the edge of the display
/// looks like it is facing a wall. The lean is added to the mark's own
/// wandering gaze, not substituted for it, so it still glances about — from a
/// head that is turned the right way.
enum BotMarkGaze: Sendable {
    case ahead
    case left
    case right

    /// Enough to read as a direction at 16pt, and well short of the span
    /// clamp that pins an eye against the inside of the body.
    private static let lean = 7.0

    var bias: Double {
        switch self {
        case .ahead: 0
        case .left: -Self.lean
        case .right: Self.lean
        }
    }

    /// The rail's own edge decides it: docked right, look left; docked left,
    /// look right. A top rail runs horizontally and has screen on both sides,
    /// so it looks straight ahead.
    init(edge: PanelEdge) {
        switch edge {
        case .right: self = .left
        case .left: self = .right
        case .top: self = .ahead
        }
    }
}

/// The animated mark that stands in for a provider's logo inside a ring.
///
/// One engine per view, kept across frames in `@State`, stepped off the
/// display's clock. What the mark is doing comes from `BotMarkMood`, which is
/// the only place a Pulse fact is turned into one of the upstream's states.
struct BotMarkView: View {
    /// What the ring is saying right now.
    let mood: BotMarkMood
    /// Which character says it: the states it plays and how it moves.
    let persona: BotMarkPersona
    /// The shape it wears, which is the reader's choice rather than the
    /// persona's. Named `bodyShape` because `body` is SwiftUI's.
    let bodyShape: BotMarkBody
    /// Which way it leans its gaze — away from the screen edge it sits on.
    var gaze: BotMarkGaze = .ahead
    /// Something that just happened and is worth a one-shot: a limit that
    /// reset, a turn that finished.
    var event: BotMarkEvent?
    /// Where the pointer is in the panel's coordinate space, or nil when it is
    /// off the panel.
    var pointer: CGPoint?
    /// Whether this ring is the one being pointed at. An idle mark stops what
    /// it is doing and listens.
    var isPointedAt = false
    /// Whether nothing has happened on this machine for a while — see
    /// `BotMarkPersona.idleStates`.
    var isQuiet = false
    /// The body colour: the provider's brand, lifted if it would disappear
    /// into the disc behind it. See `BotMarkTint`.
    let tint: Color
    /// The eye colour, which has to read against `tint`.
    let eyeTint: Color
    let size: CGFloat

    /// A still mark, for anyone who has asked the system for less motion.
    ///
    /// Not a frozen first frame: the engine is run far enough for the springs
    /// to settle into the mood, so a reduced-motion rail still shows *which*
    /// mood it is.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var engine = BotMarkEngine()
    /// This mark's own frame in the panel's space, so it can tell where the
    /// pointer is relative to itself.
    @State private var frameInPanel: CGRect = .zero

    /// The panel's coordinate space, which is also the space the pointer is
    /// reported in.
    static let panelSpace = "pulse.panel"

    /// The pointer as the engine wants it: a fraction of this mark's own
    /// radius, from its centre.
    ///
    /// Divided by four radii rather than one, so a pointer on the next ring
    /// along pulls the eyes part of the way rather than all of it. The whole
    /// rail turning to look at the cursor at full deflection reads as a stunt;
    /// the near ones looking hardest reads as attention.
    private var pointerOffset: CGPoint? {
        guard let pointer, frameInPanel.width > 0 else { return nil }
        let radius = frameInPanel.width / 2
        return CGPoint(x: (pointer.x - frameInPanel.midX) / (radius * 4),
                       y: (pointer.y - frameInPanel.midY) / (radius * 4))
    }

    var body: some View {
        Group {
            if reduceMotion {
                // **Solved outside the draw closure.** A still is three
                // seconds of simulated animation, about 1.5ms of work; inside
                // the closure it was re-solved on every draw, and a draw
                // happens every time the pointer moves anywhere on the panel.
                let still = BotMarkView.still(for: programme())
                Canvas(rendersAsynchronously: false) { context, canvasSize in
                    drawBotMark(still.frame, config: still.config,
                                in: &context, size: canvasSize)
                }
            } else {
                // **30fps, not the display's rate.** Everything the rail
                // actually plays is slow — a bob, a blink, a lean — and at
                // ring size the difference is invisible, while the whole rail
                // is seven of these redrawing at once behind a menu-bar app
                // that is meant to cost nothing. Measured settled on a docked
                // rail of seven rings: ~19% of a core at display rate against
                // ~15% here, over a ~10% baseline with marks off.
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                    let step = advance(timeline.date)
                    Canvas(rendersAsynchronously: false) { context, canvasSize in
                        drawBotMark(step.frame, config: step.config,
                                    in: &context, size: canvasSize)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background {
            GeometryReader { geometry in
                // Written on change rather than read during the draw: a
                // `GeometryReader` cannot be consulted from inside the
                // `Canvas` closure, and the frame only moves when the rail
                // does.
                let frame = geometry.frame(in: .named(Self.panelSpace))
                Color.clear
                    .onAppear { frameInPanel = frame }
                    .onChange(of: frame) { frameInPanel = $1 }
            }
        }
        .accessibilityHidden(true)
    }

    /// What this mark should be taking in turn.
    ///
    /// Being pointed at outranks the idle playlist and nothing else: a mark
    /// that is working carries on working while you look at it, and one that
    /// is spent does not cheer up because the pointer arrived.
    private func states(overtime: Bool) -> [String] {
        switch mood {
        case .working: persona.workingStates(overtime: overtime)
        case .idle: isPointedAt ? ["listening"] : persona.idleStates(quiet: isQuiet,
                                                                     overtime: overtime)
        case .fetching, .spent, .asleep: [persona.state(for: mood)]
        }
    }

    private func programme() -> BotMarkProgramme {
        let overtime = BotMarkHours.isOvertime()
        var programme = BotMarkProgramme(states: states(overtime: overtime))
        programme.event = event
        programme.mood = mood
        programme.shape = bodyShape.shape
        programme.tempo = persona.tempo * mood.tempoEmphasis
        programme.motionScale = persona.motionScale
        programme.gazeScale = persona.gazeScale
        programme.eyeScale = persona.eyeScale
        programme.gazeBias = gaze.bias
        programme.rotationScale = mood.rotationEmphasis
        programme.squashScale = mood.squashEmphasis
        programme.color = tint
        programme.eyeColor = eyeTint
        programme.viewWidth = size
        // **On at every size, including 25pt.** These were gated off below
        // 48pt on the theory that confetti at ring size is a few stray
        // pixels — and the confetti is, but the *ribbons* are not: they orbit
        // at half the body's width and the particle system scales them up on
        // a small canvas (`sizeScale`, up to 2.6×). They are also the only
        // thing in this whole vocabulary that unmistakably reads as "this is
        // doing something" at ring size, which is the question the rail exists
        // to answer. They appear when the body spins, which `working` does
        // every few seconds.
        programme.particlesEnabled = true
        programme.pointer = pointerOffset
        return programme
    }

    private func advance(_ date: Date) -> (frame: BotMarkFrame, config: BotMarkConfig) {
        let programme = programme()
        let frame = engine.advance(to: date.timeIntervalSinceReferenceDate, programme: programme)
        // The colours are the only part of the config the drawing needs, and
        // they do not change with the state of the playlist.
        return (frame, programme.configuration(for: engine.state))
    }

    /// What a still frame is of: everything that changes one.
    private struct StillKey: Hashable {
        var state: String
        var shape: String
        var tempo: Double
        var motionScale: Double
        var gazeBias: Double
        var squashScale: Double
        var rotationScale: Double
    }

    /// Stills already solved, keyed by what they are of.
    ///
    /// Memoised rather than kept in `@State`: the value is a pure function of
    /// the programme, several rings can want the same one, and a `@State`
    /// cache cannot be filled from inside `body` without writing state during
    /// a view update. Bounded by the shapes × states a rail can ask for, and
    /// only ever touched from the main actor's draw path.
    private nonisolated(unsafe) static var stills: [StillKey: (frame: BotMarkFrame,
                                                               config: BotMarkConfig)] = [:]

    /// The settled pose for a programme, with a fresh engine so nothing is
    /// carried between calls.
    private static func still(for programme: BotMarkProgramme) -> (frame: BotMarkFrame,
                                                                   config: BotMarkConfig) {
        var quiet = programme
        // A still has no playlist and no event: one state, held.
        quiet.states = [programme.states.first ?? "idle"]
        quiet.event = nil
        quiet.particlesEnabled = false
        quiet.pointer = nil

        let key = StillKey(state: quiet.states[0], shape: quiet.shape, tempo: quiet.tempo,
                           motionScale: quiet.motionScale, gazeBias: quiet.gazeBias,
                           squashScale: quiet.squashScale, rotationScale: quiet.rotationScale)
        if let cached = stills[key] {
            // The colours are not part of the key: they change nothing about
            // the pose, and the config is rebuilt from the live programme.
            return (cached.frame, quiet.configuration(for: key.state))
        }

        let engine = BotMarkEngine()
        var time = 0.0
        var frame = engine.advance(to: time, programme: quiet)
        while time < 3 {
            time += 1.0 / 60
            frame = engine.advance(to: time, programme: quiet)
        }
        // Never mid-blink: a still mark caught with its eyes shut reads as
        // broken. Waiting on `isBlinking` and not on the eyelid — see the
        // engine, where that mistake is written down.
        var guardrail = 0
        while engine.isBlinking && guardrail < 120 {
            time += 1.0 / 60
            frame = engine.advance(to: time, programme: quiet)
            guardrail += 1
        }
        let config = quiet.configuration(for: engine.state)
        stills[key] = (frame, config)
        return (frame, config)
    }
}

#Preview("Bot marks") {
    HStack(spacing: 18) {
        ForEach(BotMarkPersona.allCases) { persona in
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(white: 0.11)).frame(width: 20, height: 20)
                    BotMarkView(mood: .idle, persona: persona, bodyShape: .blob, tint: .white,
                                eyeTint: Color(white: 0.06), size: 16)
                }
                BotMarkView(mood: .working, persona: persona, bodyShape: .blob, tint: .white,
                            eyeTint: Color(white: 0.06), size: 64)
                Text(verbatim: persona.rawValue)
                    .font(.system(size: 9, design: .monospaced))
            }
        }
    }
    .padding()
    .background(.black)
}
