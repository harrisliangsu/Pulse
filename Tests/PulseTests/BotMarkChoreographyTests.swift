import AppKit
import SwiftUI
import Testing
@testable import Pulse

@Suite("Bot mark choreography")
@MainActor
struct BotMarkChoreographyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var weekday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
    }

    private func programme(_ persona: BotMarkPersona, _ mood: BotMarkMood) -> BotMarkProgramme {
        BotMarkProgramme.forMood(mood, persona: persona, at: weekday, calendar: calendar)
    }

    @Test("Every persona has a distinct idle pose and distinct action sets in each mood")
    func charactersAreDistinct() {
        #expect(Set(BotMarkPersona.allCases.map { $0.state(for: .idle) }).count == 8)
        for mood in BotMarkMood.allCases {
            let sets = BotMarkPersona.allCases.map { Set($0.routine(for: mood).states) }
            #expect(Set(sets).count == 8, "\(mood) still differs only by ordering or speed")
        }
        let attention = BotMarkPersona.allCases.map { Set($0.attentionRoutine.states) }
        #expect(Set(attention).count == 8)
        #expect(Set(BotMarkPersona.allCases.map(\.completionState)).count == 8)
    }

    @Test("Routines are nonempty, timed, and use the real catalogue without reviving sleep")
    func catalogueCoverage() {
        var used: Set<String> = [BotMarkEvent.limitReset.state]
        let removed: Set<String> = ["sleeping", "powering-down", "bored", "waking"]
        // These imply a specific action or an amount of progress Pulse did
        // not observe. They are not filler for a cheerful idle character.
        let unobserved: Set<String> = ["uploading", "sending", "dictating", "notifying", "dragging", "progress"]
        for persona in BotMarkPersona.allCases {
            for routine in BotMarkMood.allCases.map({ persona.routine(for: $0) }) + [persona.attentionRoutine] {
                #expect(routine.states.count >= 2)
                #expect(Set(routine.states).count == routine.states.count)
                #expect(Set(routine.states).isDisjoint(with: removed.union(unobserved)))
                for beat in routine.beats {
                    #expect(BotMarkLibrary.shared.state(beat.state).id == beat.state)
                    #expect(beat.hold.lowerBound >= 1_000 && beat.hold.upperBound <= 8_000)
                    #expect(routine.holds[beat.state] == beat.hold)
                }
                used.formUnion(routine.states)
            }
            used.insert(persona.completionState)
        }
        #expect(used.count >= 27)
        #expect(Set(["orbit", "radar", "loading", "receiving", "bouncing", "alerting"]).isSubset(of: used))
        print("Choreography uses \(used.count) catalogue states: \(used.sorted().joined(separator: ", "))")
    }

    @Test("A real engine plays every authored beat in order instead of randomly skipping signatures")
    func fullScenesArePlayed() {
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                let programme = programme(persona, mood)
                #expect(programme.order == .sequence)
                let engine = BotMarkEngine()
                let duration = programme.states.reduce(0.0) { $0 + programme.holdDuration(for: $1).upperBound } / 1000 + 2
                var seen: [String] = []
                var maximumSlide = 0.0
                for index in 0...Int(duration * 10) {
                    let frame = engine.advance(to: Double(index) / 10, programme: programme)
                    if seen.last != engine.state { seen.append(engine.state) }
                    if frame.morphAmount < 0.01 {
                        let centre = BotMarkLibrary.shared.headCentre
                        let point = CGPoint(x: centre, y: centre).applying(frame.transform)
                        maximumSlide = max(maximumSlide, max(abs(Double(point.x) - centre), abs(Double(point.y) - centre)))
                    }
                }
                #expect(Array(seen.prefix(programme.states.count)) == programme.states,
                        "\(persona)/\(mood) omitted an authored beat")
                #expect(maximumSlide < 13, "\(persona)/\(mood) moved its head out of the rail budget")
            }
        }
    }

    @Test("Task effects and celebration do not masquerade as idle or unavailable work")
    func statesKeepTheirMeaning() {
        let taskEffects: Set<String> = ["working", "writing", "thinking", "spawning", "radar", "receiving", "loading", "orbit"]
        for persona in BotMarkPersona.allCases {
            for mood in [BotMarkMood.idle, .spent, .unavailable] {
                let states = Set(programme(persona, mood).states)
                #expect(states.isDisjoint(with: taskEffects))
                #expect(!states.contains("celebrate"))
            }
            for mood in [BotMarkMood.spent, .unavailable] {
                #expect(Set(programme(persona, mood).states).isDisjoint(with: ["happy", "laughing", "playful", "bouncing", "excited", "proud"]))
            }
        }
    }

    @Test("No persona's everyday or attention state appears in any persona's working scene")
    func workAndEverydayStatesAreDisjoint() {
        var everyday: Set<String> = []
        for persona in BotMarkPersona.allCases {
            everyday.formUnion(persona.attentionRoutine.states)
            for quiet in [false, true] {
                for night in [false, true] {
                    everyday.formUnion(persona.idleStates(quiet: quiet, night: night))
                }
            }
        }
        for persona in BotMarkPersona.allCases {
            for overtime in [false, true] {
                let working = Set(persona.workingStates(overtime: overtime))
                #expect(working.isDisjoint(with: everyday),
                        "\(persona)'s work reuses everyday states: \(working.intersection(everyday))")
            }
        }
    }

    @Test("Idle characters and their pointer responses never draw busy ribbons")
    func everydayHasNoBusyParticles() {
        for persona in BotMarkPersona.allCases {
            for pointed in [false, true] {
                let programme = BotMarkProgramme.forMood(
                    .idle, persona: persona, isPointedAt: pointed, at: weekday, calendar: calendar
                )
                let engine = BotMarkEngine()
                var particleFrames = 0
                for index in 0..<600 {
                    let frame = engine.advance(to: Double(index) / 10, programme: programme)
                    if !frame.backParticles.isEmpty || !frame.frontParticles.isEmpty { particleFrames += 1 }
                }
                #expect(particleFrames == 0, "\(persona) looks busy while idle")
            }
        }
    }

    @Test("Returning from work to idle clears live ribbons and queued emissions")
    func busyParticlesStopWithWork() throws {
        let engine = BotMarkEngine()
        let busy = programme(.eager, .working)
        var time = 0.0
        var sawParticles = false
        for index in 0..<300 {
            time = Double(index) / 30
            let frame = engine.advance(to: time, programme: busy)
            if !frame.backParticles.isEmpty || !frame.frontParticles.isEmpty {
                sawParticles = true
                break
            }
        }
        try #require(sawParticles, "The setup must catch a real live ribbon before switching to idle")
        let idle = programme(.steady, .idle)
        for _ in 0..<90 {
            time += 1.0 / 30
            let frame = engine.advance(to: time, programme: idle)
            #expect(frame.backParticles.isEmpty && frame.frontParticles.isEmpty)
        }
    }

    @Test("Event particles end with the one-shot even while its observed flag is still true",
          arguments: [BotMarkEvent.workFinished, .limitReset])
    func eventParticlesDoNotLeakIntoIdle(event: BotMarkEvent) {
        var programme = programme(.steady, .idle)
        programme.event = event
        let engine = BotMarkEngine()
        var eventParticleFrames = 0
        var afterwardsParticleFrames = 0
        for index in 0...Int((event.duration / 1000 + 4) * 30) {
            let time = Double(index) / 30
            let frame = engine.advance(to: time, programme: programme)
            let hasParticles = !frame.backParticles.isEmpty || !frame.frontParticles.isEmpty
            if time < event.duration / 1000, hasParticles { eventParticleFrames += 1 }
            if time > event.duration / 1000 + 0.1, hasParticles { afterwardsParticleFrames += 1 }
        }
        #expect(eventParticleFrames > 0)
        #expect(afterwardsParticleFrames == 0)
        // Reduce Motion's explicit master switch outranks even an event.
        programme.particlesEnabled = false
        #expect(!programme.configuration(for: programme.state(for: event), isEvent: true).particlesEnabled)
    }

    @Test("Each character acknowledges a witnessed finish; a reset still gets the full celebration")
    func eventResponses() {
        for persona in BotMarkPersona.allCases {
            for event in [BotMarkEvent.workFinished, .limitReset] {
                var programme = programme(persona, .idle)
                programme.event = event
                let engine = BotMarkEngine()
                let expected = event == .limitReset ? "celebrate" : persona.completionState
                _ = engine.advance(to: 0, programme: programme)
                #expect(engine.state == expected)
                var afterwards: [String] = []
                for frame in 1...Int((event.duration / 1000 + 4) * 10) {
                    let time = Double(frame) / 10
                    _ = engine.advance(to: time, programme: programme)
                    if time < event.duration / 1000 - 0.1 { #expect(engine.state == expected) }
                    if time > event.duration / 1000 + 0.2 { afterwards.append(engine.state) }
                }
                #expect(afterwards.allSatisfy { programme.states.contains($0) })
            }
        }
    }

    @Test("Idle retains the face for most frames while exposing the playful ball effect")
    func idleKeepsItsFace() {
        for persona in BotMarkPersona.allCases {
            let programme = programme(persona, .idle)
            let engine = BotMarkEngine()
            var morphed = 0
            var seen: Set<String> = []
            for index in 0..<600 {
                let frame = engine.advance(to: Double(index) / 10, programme: programme)
                if frame.morphAmount > 0.5 { morphed += 1 }
                if frame.morphAmount > 0.9 {
                    seen.insert(engine.state)
                    if engine.state == "bouncing" {
                        var transform = frame.transform
                        let height = frame.headPath.copy(using: &transform)?.boundingBoxOfPath.height ?? 0
                        #expect(height > 0 && height < 80, "Bouncing should actually draw the small ball body")
                    }
                }
            }
            #expect(Double(morphed) / 600 < 0.4, "\(persona) spent too long without its own face")
            if persona == .playful { #expect(seen.contains("bouncing")) }
        }
    }

    @Test("Short returning poses use their whole expression pool")
    func expressionsDoNotRestartAtZero() throws {
        var programme = programme(.curious, .idle)
        programme.stateHolds = Dictionary(uniqueKeysWithValues: programme.states.map { ($0, 500.0...500.0) })
        let pool = BotMarkLibrary.shared.state("curious").expressionPool
        try #require(pool.count > 1)
        let engine = BotMarkEngine()
        var seen: Set<Int> = []
        var previous = ""
        for index in 0..<(pool.count * programme.states.count * 8) {
            _ = engine.advance(to: Double(index) / 10, programme: programme)
            if engine.state != previous, engine.state == "curious" { seen.insert(engine.expressionIndex) }
            previous = engine.state
        }
        #expect(seen == Set(pool))
    }

    /// Optional contact sheet using the production Canvas drawing. It is a
    /// local render, not evidence of AppKit input or a running panel.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_BOT_PREVIEW"] != nil))
    func renderContactSheet() throws {
        let destination = try #require(ProcessInfo.processInfo.environment["PULSE_BOT_PREVIEW"])
        var rows: [PoseRow] = []
        for persona in BotMarkPersona.allCases {
            var poses: [Pose] = []
            let idle = programme(persona, .idle)
            let engine = BotMarkEngine()
            var seen: Set<String> = []
            for frameIndex in 0..<900 {
                let time = Double(frameIndex) / 30
                let frame = engine.advance(to: time, programme: idle)
                if time * 1000 - engine.stateStartedAt > 900, seen.insert(engine.state).inserted {
                    poses.append(Pose(id: "idle-\(engine.state)", label: engine.state,
                                      frame: frame, config: idle.configuration(for: engine.state)))
                }
                if poses.count == idle.states.count { break }
            }
            for mood in [BotMarkMood.working, .fetching] {
                let programme = programme(persona, mood)
                let engine = BotMarkEngine()
                var frame = engine.advance(to: 0, programme: programme)
                for tick in 1...30 { frame = engine.advance(to: Double(tick) / 30, programme: programme) }
                poses.append(Pose(id: mood.rawValue, label: "\(mood.rawValue):\(engine.state)",
                                  frame: frame, config: programme.configuration(for: engine.state)))
            }
            rows.append(PoseRow(id: persona.rawValue, poses: poses))
        }
        let content = VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Text(verbatim: row.id).frame(width: 70, alignment: .leading)
                    ForEach(row.poses) { pose in
                        VStack {
                            Canvas { context, size in
                                var config = pose.config
                                config.color = BotMarkPalette.rgb(0x7AA5FF)
                                config.eyeColor = .black
                                drawBotMark(pose.frame, config: config, in: &context, size: size)
                            }
                            .frame(width: 64, height: 64)
                            Text(verbatim: pose.label).font(.system(size: 9))
                        }
                        .frame(width: 100)
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: destination))
    }

    private struct PoseRow: Identifiable {
        let id: String
        let poses: [Pose]
    }

    private struct Pose: Identifiable {
        let id: String
        let label: String
        let frame: BotMarkFrame
        let config: BotMarkConfig
    }
}
