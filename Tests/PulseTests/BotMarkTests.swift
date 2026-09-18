import SwiftUI
import Testing
@testable import Pulse

/// The animated mark: what it says, and whether it can be seen saying it.
///
/// The animation itself is not testable from here — it is a per-frame spring
/// solve drawn into a `Canvas`, and what it looks like is a screenshot
/// question. What *is* checkable is the part that would fail silently: the
/// rule that turns a Pulse fact into a mood, and the rule that keeps a brand
/// colour visible on the disc it sits on. Both of those go wrong by drawing
/// something plausible rather than by crashing.
@Suite("Bot mark")
@MainActor
struct BotMarkTests {
    @Test("Busy outranks every other reading")
    func busyWins() {
        #expect(BotMarkMood.resolve(isBusy: true, isRefreshing: true,
                                    isSpent: true, hasReading: false) == .working)
        #expect(BotMarkMood.resolve(isBusy: true, isRefreshing: false,
                                    isSpent: false, hasReading: true) == .working)
    }

    @Test("A spent limit is only read once nothing is happening")
    func spentBelowActivity() {
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: true,
                                    isSpent: true, hasReading: true) == .fetching)
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: false,
                                    isSpent: true, hasReading: true) == .spent)
    }

    /// No reading is a mood, not a dimmed logo: the mark sleeps.
    @Test("Nothing known sleeps, and a plain reading is idle")
    func quietStates() {
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: false,
                                    isSpent: false, hasReading: false) == .asleep)
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: false,
                                    isSpent: false, hasReading: true) == .idle)
    }

    /// Every mood has to name a state the library actually carries, or the
    /// mark silently falls back to the first state in the table and the rail
    /// says "idle" about a provider that is signed out.
    @Test("Every mood names a state the data has")
    func moodsResolveToRealStates() {
        for mood in BotMarkMood.allCases {
            #expect(BotMarkLibrary.shared.state(mood.upstreamState).id == mood.upstreamState)
        }
    }

    /// The geometry is a bundled resource, and a resource that stops being
    /// copied is a blank rail rather than a build failure.
    @Test("The bundled geometry is the whole table")
    func libraryLoads() {
        let library = BotMarkLibrary.shared
        #expect(library.shapes.count == 18)
        #expect(library.shapeOrder.count == 18)
        #expect(library.expressions.count == 25)
        #expect(library.states.count == 39)
        // Two eyes, and the rings have to be the same length end to end or
        // the expression blend has nothing to interpolate between.
        for expression in library.expressions {
            #expect(expression.count == 2)
            #expect(expression[0].count == expression[1].count)
        }
        // Shape blending is point-by-point, so every body shares one count.
        let counts = Set(library.shapes.values.map(\.ring.count))
        #expect(counts == [96])
    }

    /// Every provider draws a body, and a dark brand is lifted rather than
    /// left as a hole in the disc.
    @Test("No provider's mark disappears into the disc")
    func bodiesStayVisible() {
        for provider in Provider.allCases {
            let body = BotMarkTint.body(for: provider)
            let luminance = Self.luminance(of: body)
            #expect(luminance >= 0.41, "\(provider.rawValue) draws too dark to see")
            // And the eyes have to read against whatever the body became.
            let eyes = BotMarkTint.eyes(on: body)
            #expect(abs(Self.luminance(of: eyes) - luminance) > 0.3,
                    "\(provider.rawValue) has no contrast between body and eyes")
        }
    }

    /// The whole point of dealing colours is that the rail is not a row of
    /// identical bots. A hash over the ids was tried first and collided: six
    /// of the ten shared two colours.
    @Test("A rail of colourless providers gets ten different colours")
    func dealtColoursAreDistinct() {
        let colourless = Provider.allCases.filter { BotMarkTint.brand(for: $0) == nil }
        let colours = BotMarkTint.deal(over: colourless).map(\.hexString)
        #expect(colours.allSatisfy { $0 != nil })
        #expect(Set(colours).count == colourless.count)
    }

    /// Distinct is not enough — two greens 20° apart are distinct and still
    /// read as one colour on a rail. What matters is the pair a reader
    /// actually sees together, which is the pair drawn next to each other.
    @Test("Neighbours on a rail are never near each other in hue")
    func neighboursAreFarApart() {
        // Every rail worth worrying about: the whole list, and the awkward
        // ones where a brand colour sits between two dealt colours.
        let rails: [[Provider]] = [
            Provider.allCases,
            [.claudeCode, .codex, .cursor, .openCodeGo, .kimiCode, .glmCoding, .devin],
            [.claudeCode, .codex],
            [.deepSeek, .grok, .volcengine, .grokBot, .antigravity, .copilot],
            [.minimax, .cursor, .minimaxCN, .devin],
        ]
        for rail in rails {
            let hues = BotMarkTint.deal(over: rail).map(Self.hue(of:))
            for index in hues.indices.dropLast() {
                // Two brand colours side by side are what those brands are —
                // MiniMax's two rows really are one red. Only a pair with a
                // dealt colour in it is this code's to get right.
                guard BotMarkTint.isDealt(rail[index]) || BotMarkTint.isDealt(rail[index + 1]) else {
                    continue
                }
                let gap = Self.separation(hues[index], hues[index + 1])
                #expect(gap >= 30,
                        "\(rail[index].rawValue) and \(rail[index + 1].rawValue) sit \(Int(gap))° apart")
            }
        }
    }

    /// Two accounts of one provider draw one brand, and a rail is dealt the
    /// same way every time it is built — a mark that changed colour between
    /// two frames would be worse than a white one.
    @Test("Dealing is stable for a given rail")
    func dealIsStable() {
        let rail: [Provider] = [.claudeCode, .codex, .cursor, .grok, .devin]
        let first = BotMarkTint.deal(over: rail).map(\.hexString)
        let second = BotMarkTint.deal(over: rail).map(\.hexString)
        #expect(first == second)
    }

    /// A colour somebody picked is used as picked — and the rings beside it
    /// are dealt away from it, exactly as they are from a brand colour.
    @Test("A chosen colour is kept, and neighbours still avoid it")
    func chosenColoursAreHonoured() {
        let rail: [Provider] = [.cursor, .grok, .devin]
        let pink = BotMarkPalette.rgb(0xFF66CC)
        let dealt = BotMarkTint.deal(over: rail, chosen: [nil, pink, nil])
        #expect(dealt[1].hexString == pink.hexString, "the chosen colour was overwritten")
        for index in [0, 2] {
            let gap = Self.separation(Self.hue(of: dealt[index]), Self.hue(of: pink))
            #expect(gap >= 30, "a neighbour was dealt \(Int(gap))° from the chosen colour")
        }
        // And with nothing chosen the rail deals as it always did.
        #expect(BotMarkTint.deal(over: rail).count == rail.count)
    }

    /// A provider that carries a brand colour keeps it — the dealt palette is
    /// only for the ones that do not.
    @Test("A brand colour is never overwritten")
    func brandWins() {
        #expect(BotMarkTint.brand(for: .claudeCode) != nil)
        #expect(BotMarkTint.body(for: .claudeCode).hexString
                == BotMarkTint.brand(for: .claudeCode)?.hexString)
    }

    /// A black brand keeps its hue when it is lifted — the point is to make it
    /// visible, not to turn every dark mark into the same grey.
    @Test("Lifting a dark colour keeps its hue")
    func liftKeepsHue() {
        let body = BotMarkTint.body(for: .deepSeek)
        let colour = NSColor(body).usingColorSpace(.sRGB)!
        #expect(colour.blueComponent > colour.redComponent)
    }

    /// A persona may change how a mood is said, never what it says. This is
    /// the rule that keeps the rail honest: no character may claim work is
    /// happening when it is not, or look idle about a spent limit.
    @Test("No persona contradicts the reading")
    func personasStayHonest() {
        // The states each mood is allowed to be played as, by meaning.
        let allowed: [BotMarkMood: Set<String>] = [
            // `bored` and `drowsy` are idle states with a fact behind them:
            // nothing has been written for twenty minutes, and it is late.
            // `listening` is idle with the pointer on this ring.
            .idle: ["idle", "listening", "humming", "bored", "drowsy",
                    "proud", "curious", "playful"],
            .working: ["working", "excited", "searching", "thinking"],
            .fetching: ["searching", "curious", "listening"],
            .spent: ["sad", "bored", "drowsy"],
            .asleep: ["sleeping", "drowsy", "powering-down"],
        ]
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                let state = persona.state(for: mood)
                #expect(allowed[mood]?.contains(state) == true,
                        "\(persona.rawValue) plays \(state) for \(mood.rawValue)")
                // And it has to be a state the bundled table actually carries.
                #expect(BotMarkLibrary.shared.state(state).id == state)
            }
        }
    }

    /// The shape list is offered to the reader, so every entry has to draw
    /// something — a picker row that renders nothing is worse than no row.
    @Test("Every shape in the picker exists in the data")
    func bodyShapesAreReal() {
        #expect(BotMarkBody.allCases.count == BotMarkLibrary.shared.shapes.count)
        for body in BotMarkBody.allCases {
            #expect(BotMarkLibrary.shared.shapes[body.shape] != nil,
                    "no shape named \(body.shape)")
        }
        // Round by default, and stored as an absence, so nothing has to be
        // written for the common case.
        #expect(BotMarkBody.default == .blob)
        #expect(BotMarkBody(rawValue: "a shape that was removed") == nil)
    }

    /// Automatic dealing exists so neighbours are different characters.
    @Test("Neighbouring rings are dealt different personas")
    func automaticPersonasDiffer() {
        for index in 0..<40 {
            #expect(BotMarkPersona.automatic(at: index)
                    != BotMarkPersona.automatic(at: index + 1))
        }
        // And a rail no longer than the cast has no repeats at all.
        let rail = (0..<BotMarkPersona.allCases.count).map(BotMarkPersona.automatic(at:))
        #expect(Set(rail).count == BotMarkPersona.allCases.count)
    }

    /// A rail on the right edge has to look left, and the only way to see
    /// that without a screenshot is to read where the eyes were actually put.
    ///
    /// The autonomous gaze is switched off for the comparison (`gazeScale` 0),
    /// so the two runs differ by the lean and nothing else — otherwise the
    /// random glances would make this flake.
    @Test("The gaze lean moves the eyes, and the right way")
    func gazeLeanMovesTheEyes() {
        func eyeCentre(bias: Double) -> Double {
            var programme = BotMarkProgramme(states: ["idle"])
            programme.gazeScale = 0
            programme.gazeBias = bias
            let engine = BotMarkEngine()
            var time = 0.0
            var frame = engine.advance(to: time, programme: programme)
            while time < 2 {
                time += 1.0 / 60
                frame = engine.advance(to: time, programme: programme)
            }
            // Both eyes, so a wink or a blink cannot tilt the reading.
            return frame.eyes.map { Double($0.transform.tx) }.reduce(0, +) / 2
        }

        let ahead = eyeCentre(bias: BotMarkGaze.ahead.bias)
        let left = eyeCentre(bias: BotMarkGaze.left.bias)
        let right = eyeCentre(bias: BotMarkGaze.right.bias)
        #expect(left < ahead - 3, "looking left did not move the eyes left")
        #expect(right > ahead + 3, "looking right did not move the eyes right")
    }

    /// Which way each edge looks. A rail on the right edge of the screen has
    /// the screen to its left.
    @Test("The rail's edge decides the lean")
    func edgesLeanInward() {
        #expect(BotMarkGaze(edge: .right) == .left)
        #expect(BotMarkGaze(edge: .left) == .right)
        // A top rail has screen on both sides of it.
        #expect(BotMarkGaze(edge: .top) == .ahead)
        #expect(BotMarkGaze.ahead.bias == 0)
    }

    /// Working has to be visible *as* working at ring size, which is the one
    /// thing the removal of the white activity arc put on this code. Measured
    /// as the peak-to-peak rotation of the body over three seconds, read off
    /// the frame transform — a still cannot show it and a screenshot cannot
    /// measure it.
    @Test("Working moves visibly more than idle")
    func workingIsVisiblyBusy() {
        /// Peak-to-peak rotation, and how much the drawn body's height
        /// changes as a fraction of itself.
        func swing(_ mood: BotMarkMood) -> (degrees: Double, pump: Double) {
            // One state, so the measurement is of the motion and not of the
            // playlist moving on.
            var programme = BotMarkProgramme(states: [BotMarkPersona.calm.state(for: mood)])
            programme.mood = mood
            programme.rotationScale = mood.rotationEmphasis
            programme.squashScale = mood.squashEmphasis
            programme.tempo = mood.tempoEmphasis
            let engine = BotMarkEngine()
            var time = 0.0
            var lowest = Double.infinity
            var highest = -Double.infinity
            var shortest = Double.infinity
            var tallest = -Double.infinity
            // Past the state's own settle, then sampled for three seconds.
            while time < 5 {
                time += 1.0 / 60
                let frame = engine.advance(to: time, programme: programme)
                guard time > 2 else { continue }
                let degrees = atan2(Double(frame.transform.b), Double(frame.transform.a))
                    * 180 / .pi
                lowest = min(lowest, degrees)
                highest = max(highest, degrees)
                shortest = min(shortest, Self.drawnHeight(frame))
                tallest = max(tallest, Self.drawnHeight(frame))
            }
            let pump = (tallest - shortest) / tallest
            print("\(mood.rawValue): \(String(format: "%.1f", highest - lowest))° swing, "
                  + "\(String(format: "%.1f", pump * 100))% pump")
            return (highest - lowest, pump)
        }

        let idle = swing(.idle)
        let working = swing(.working)
        #expect(working.pump > idle.pump * 1.5, "working does not breathe harder than idle")
        #expect(working.degrees > idle.degrees * 2, "working does not rock more than idle")
        // **And it has to stay a pulse.** An emphasis that resizes the mark
        // reads as a glitch, not as work: ten was tried, came out at 20% of
        // the body's height, and was reported as the bot growing and
        // shrinking. Every persona, every mood, inside a hand's breadth of
        // its resting height.
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                let engine = BotMarkEngine()
                var time = 0.0
                var resting: Double?
                while time < 6 {
                    time += 1.0 / 60
                    let frame = engine.advance(to: time,
                                               programme: Self.programme(persona, mood))
                    let height = Self.drawnHeight(frame)
                    // A second in, so the state's own arrival is not the
                    // baseline — and never mid-morph: `spawning` and `writing`
                    // shrink the character to a fifth *on purpose*, because
                    // the effect is what is being shown, and that is not the
                    // squash this is guarding.
                    guard time > 1, frame.morphAmount < 0.01 else { continue }
                    let base = resting ?? height
                    resting = base
                    let ratio = String(format: "%.2f", height / base)
                    #expect(height / base > 0.82 && height / base < 1.2,
                            "\(persona.rawValue)/\(mood.rawValue) drew at \(ratio) of its height")
                }
            }
        }
    }

    /// The ribbons are the one cue that unmistakably reads as "this is doing
    /// something" at ring size, and they only appear when the body spins. If
    /// a refactor ever stops the working state spinning, or leaves particles
    /// gated off at this size, nothing crashes — the rail just goes quiet
    /// again, which is the bug this is here to catch.
    @Test("A working mark throws ribbons")
    func workingDrawsRibbons() {
        var programme = Self.programme(.calm, .working)
        programme.viewWidth = 25
        let engine = BotMarkEngine()
        var time = 0.0
        var framesWithRibbons = 0
        // Long enough for the working state's own spin to come round: it
        // starts one every three to four and a half seconds at this tempo.
        // **Thirty seconds, not twelve.** The playlist takes its states in a
        // random order and two of the three are morphs, which do not spin: a
        // twelve-second sample happened to draw no `working` at all and the
        // test failed on a run where nothing was wrong. Long enough that the
        // state comes round several times whatever the draw.
        var states: Set<String> = []
        while time < 30 {
            time += 1.0 / 60
            let frame = engine.advance(to: time, programme: programme)
            states.insert(engine.state)
            if !frame.backParticles.isEmpty || !frame.frontParticles.isEmpty {
                framesWithRibbons += 1
            }
        }
        print("ribbons over 30s, states seen: \(states.sorted().joined(separator: ", "))")
        print("ribbons on \(framesWithRibbons) of \(Int(30 * 60)) frames")
        #expect(framesWithRibbons > 60, "no ribbons in thirty seconds of working")
    }

    /// The head may not leave the canvas: the viewBox has about 15 units of
    /// margin around the body, and `drowsy` nods 25.
    @Test("No state pushes the head off its canvas")
    func headStaysInsideTheCanvas() {
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                let engine = BotMarkEngine()
                var time = 0.0
                while time < 8 {
                    time += 1.0 / 60
                    let frame = engine.advance(to: time,
                                               programme: Self.programme(persona, mood))
                    // A morph moves the character on purpose — the pencil
                    // walks it across the canvas as it writes — and brings its
                    // own viewBox. Only the plain body is bounded.
                    guard frame.morphAmount < 0.01 else { continue }
                    // Where the body's own centre actually lands, by running
                    // it through the frame's transform — reading `tx` off the
                    // matrix instead mixes in the rotation about that centre.
                    let centre = BotMarkLibrary.shared.headCentre
                    let drawn = CGPoint(x: centre, y: centre).applying(frame.transform)
                    let slid = max(abs(Double(drawn.x) - centre), abs(Double(drawn.y) - centre))
                    #expect(slid < 13,
                            "\(persona.rawValue)/\(mood.rawValue) slid \(Int(slid)) units")
                }
            }
        }
    }

    /// A one-shot has to interrupt the playlist, play once, and hand it back
    /// — and it must not replay for as long as the fact stays true, which for
    /// a reset is twenty seconds of frames.
    @Test("An event plays once and gives the playlist back")
    func eventsPlayOnce() {
        var programme = Self.programme(.calm, .working)
        programme.event = .limitReset
        let engine = BotMarkEngine()
        var time = 0.0
        var celebrating = 0
        var afterwards: Set<String> = []
        while time < 14 {
            time += 1.0 / 60
            _ = engine.advance(to: time, programme: programme)
            if engine.state == "celebrate" { celebrating += 1 }
            if time > 8 { afterwards.insert(engine.state) }
        }
        // The celebrate cycle is 6.2s upstream and gets the whole of it.
        #expect(celebrating > 300, "the celebration did not hold")
        #expect(!afterwards.contains("celebrate"),
                "the event replayed while its fact was still true")
        #expect(!afterwards.isEmpty)
    }

    /// A quiet rail gets bored, and sleepy about it at night — and comes back
    /// to itself either way, because the persona's own idle state stays in
    /// the list.
    @Test("Quiet adds boredom, night adds sleep, neither takes over")
    func quietIdleStates() {
        for persona in BotMarkPersona.allCases {
            let busy = persona.idleStates(quiet: false, overtime: false)
            let quiet = persona.idleStates(quiet: true, overtime: false)
            let night = persona.idleStates(quiet: true, overtime: true)
            #expect(busy == [persona.state(for: .idle)])
            #expect(quiet.first == persona.state(for: .idle))
            #expect(quiet.contains("bored"))
            #expect(night.first == persona.state(for: .idle))
            #expect(night.contains("drowsy"))
            // No state twice: the sleepy character already rests at `bored`.
            #expect(Set(quiet).count == quiet.count)
            #expect(Set(night).count == night.count)
        }
    }

    /// Work out of hours is still work: `angry` joins the playlist and the
    /// states that mean work stay in it.
    @Test("Out of hours adds anger without dropping the work")
    func overtimeAddsAnger() {
        for persona in BotMarkPersona.allCases {
            let day = persona.workingStates(overtime: false)
            let night = persona.workingStates(overtime: true)
            #expect(!day.contains("angry"))
            #expect(night.contains("angry"))
            #expect(night.count == day.count + 1)
            #expect(Set(night).count == night.count)
            for state in day { #expect(night.contains(state)) }
            // Three at least, or it is a loop again.
            #expect(day.count >= 3)
            for state in day {
                #expect(BotMarkLibrary.shared.state(state).id == state)
            }
        }
    }

    /// The hours themselves are a guess, but the rule has to be the rule.
    @Test("Overtime is nights and weekends")
    func overtimeHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ day: Int, _ hour: Int) -> Date {
            // 2026-09-14 is a Monday, so day 14…20 walks a whole week.
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        #expect(!BotMarkHours.isOvertime(at: at(14, 10), calendar: calendar))
        #expect(!BotMarkHours.isOvertime(at: at(18, 20), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(14, 8), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(14, 21), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(14, 2), calendar: calendar))
        // Saturday and Sunday, in the middle of the working day.
        #expect(BotMarkHours.isOvertime(at: at(19, 14), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(20, 14), calendar: calendar))
    }

    /// The three shapes whose turn profile is solved from spheres in 3D are
    /// the only ones that touch `turnedShapeRing`'s solid branch — where a
    /// cached baseline and a per-point `profile[index]` live. Nothing else
    /// exercises them, so a body chosen from the picker could crash on a spin
    /// that no test had ever run.
    @Test("A solid body survives being spun")
    func solidBodiesTurn() {
        let solids: [BotMarkBody] = [.bean, .tablet, .cloud]
        for body in solids {
            #expect(BotMarkLibrary.shared.shape(body.shape).solid != nil,
                    "\(body.shape) is not one of the solid shapes any more")
            var programme = Self.programme(.playful, .working)   // playful spins
            programme.shape = body.shape
            let engine = BotMarkEngine()
            var time = 0.0
            // Long enough for the ambient gestures to spin it at least once.
            while time < 20 {
                time += 1.0 / 60
                let frame = engine.advance(to: time, programme: programme)
                let drawn = frame.headPath.boundingBoxOfPath
                #expect(drawn.width.isFinite && drawn.height.isFinite,
                        "\(body.shape) drew a non-finite outline")
                #expect(drawn.width > 0, "\(body.shape) collapsed to nothing")
            }
        }
    }

    /// The programme a ring would hand the engine for this pair, so a test
    /// measures what the rail actually plays.
    private static func programme(_ persona: BotMarkPersona,
                                  _ mood: BotMarkMood) -> BotMarkProgramme {
        var programme = BotMarkProgramme(
            states: mood == .working
                ? persona.workingStates(overtime: false)
                : [persona.state(for: mood)])
        programme.mood = mood
        programme.tempo = persona.tempo * mood.tempoEmphasis
        programme.motionScale = persona.motionScale
        programme.gazeScale = persona.gazeScale
        programme.eyeScale = persona.eyeScale
        programme.rotationScale = mood.rotationEmphasis
        programme.squashScale = mood.squashEmphasis
        return programme
    }

    /// The height of the body as it is actually drawn.
    ///
    /// **The path is transformed, not its bounding box.** Transforming the
    /// box rotates a rectangle, and the axis-aligned box of a rotated
    /// rectangle is taller than the shape inside it — which reads as the body
    /// growing every time it leans. That artefact is what made the first
    /// version of this measurement fail on a persona that merely tilts.
    private static func drawnHeight(_ frame: BotMarkFrame) -> Double {
        var transform = frame.transform
        guard let path = frame.headPath.copy(using: &transform) else { return 0 }
        return Double(path.boundingBoxOfPath.height)
    }

    private static func hue(of colour: Color) -> Double {
        guard let base = NSColor(colour).usingColorSpace(.sRGB) else { return 0 }
        return Double(base.hueComponent) * 360
    }

    /// The shorter way round the colour wheel.
    private static func separation(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func luminance(of colour: Color) -> Double {
        guard let base = NSColor(colour).usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * base.redComponent
            + 0.7152 * base.greenComponent
            + 0.0722 * base.blueComponent
    }
}
