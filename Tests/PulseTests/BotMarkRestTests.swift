import Foundation
import Testing
@testable import Pulse

/// The actual playlist/timing the view uses, rather than a hand-built single
/// state. The old geometry tests never exercised the quiet/weekend playlist.
@Suite("Bot mark rest balance")
@MainActor
struct BotMarkRestTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    @Test("A quiet Saturday afternoon does not put readable marks to sleep")
    func weekendDayIsAwake() {
        for persona in BotMarkPersona.allCases {
            let programme = BotMarkProgramme.forMood(
                .idle, persona: persona, isQuiet: true, at: at(19, 14), calendar: calendar
            )
            #expect(!programme.states.contains("drowsy"))
            #expect(!programme.states.contains("sleeping"))
        }
    }

    @Test("Quiet readable marks spend most of their time awake by day and night", arguments: [14, 23])
    func restIsAnAccent(hour: Int) {
        for persona in BotMarkPersona.allCases {
            let programme = BotMarkProgramme.forMood(
                .idle, persona: persona, isQuiet: true, at: at(19, hour), calendar: calendar
            )
            let engine = BotMarkEngine()
            var resting = 0
            var narrowed = 0
            let frames = 1_200
            for frame in 0..<frames {
                _ = engine.advance(to: Double(frame) / 10, programme: programme)
                if ["bored", "drowsy", "sleeping"].contains(engine.state) { resting += 1 }
                if engine.eyelid < 0.7 { narrowed += 1 }
            }
            let restShare = Double(resting) / Double(frames)
            let narrowedShare = Double(narrowed) / Double(frames)
            print("\(hour):00 \(persona.rawValue): rest \(Int(restShare * 100))%, narrowed eyes \(Int(narrowedShare * 100))%")
            if persona != .sleepy || hour == 14 { #expect(resting == 0) }
            #expect(restShare < 0.25, "\(persona.rawValue) rests for \(restShare) of a readable idle session")
            // Laughing and a playful dizzy spin can narrow the eyes too. The
            // sleep regression is the state budget, not every expressive blink.
            if persona == .sleepy {
                #expect(narrowedShare < 0.3, "The sleepy persona is spending too long with its eyes low")
            }
        }
    }

    @Test("Night is 23:00–08:00, not an entire weekend or an early evening")
    func nightHours() {
        for day in [14, 19, 20] {
            #expect(BotMarkHours.isNight(at: at(day, 23), calendar: calendar))
            #expect(BotMarkHours.isNight(at: at(day, 0), calendar: calendar))
            #expect(BotMarkHours.isNight(at: at(day, 7), calendar: calendar))
            #expect(!BotMarkHours.isNight(at: at(day, 8), calendar: calendar))
            #expect(!BotMarkHours.isNight(at: at(day, 14), calendar: calendar))
            #expect(!BotMarkHours.isNight(at: at(day, 21), calendar: calendar))
            #expect(!BotMarkHours.isNight(at: at(day, 22), calendar: calendar))
        }
    }

    @Test("A readable mark enters idle awake, including the sleepy persona")
    func startsAwake() {
        for persona in BotMarkPersona.allCases {
            let programme = BotMarkProgramme.forMood(
                .idle, persona: persona, isQuiet: true, at: at(19, 23), calendar: calendar
            )
            let engine = BotMarkEngine()
            _ = engine.advance(to: 0, programme: programme)
            #expect(engine.state == persona.state(for: .idle))
            #expect(!["bored", "drowsy", "sleeping"].contains(engine.state))
            // The longest accent is shorter than a quarter of the shortest
            // awake interval: this is a timing budget, not a lucky sample.
            if persona == .sleepy {
                let awakeMinimum = programme.states.filter { $0 != "drowsy" }
                    .reduce(0.0) { $0 + programme.holdDuration(for: $1).lowerBound }
                #expect(programme.holdDuration(for: "drowsy").upperBound
                    <= awakeMinimum / 4)
            } else {
                #expect(programme.stateHolds["drowsy"] == nil)
            }
        }
    }

    @Test("Hover wakes idle attention without changing busy or unavailable meanings")
    func attentionAndOtherMoods() {
        for persona in BotMarkPersona.allCases {
            let idle = BotMarkProgramme.forMood(
                .idle, persona: persona, isQuiet: true, isPointedAt: true,
                at: at(19, 23), calendar: calendar
            )
            #expect(idle.states == persona.attentionRoutine.states)
            let recent = BotMarkProgramme.forMood(
                .idle, persona: persona, isQuiet: false, at: at(19, 23), calendar: calendar
            )
            #expect(recent.states == persona.idleStates(quiet: false, night: true))

            for mood in [BotMarkMood.working, .fetching, .spent, .unavailable] {
                let plain = BotMarkProgramme.forMood(mood, persona: persona, at: at(19, 23), calendar: calendar)
                let pointed = BotMarkProgramme.forMood(
                    mood, persona: persona, isQuiet: true, isPointedAt: true,
                    at: at(19, 23), calendar: calendar
                )
                #expect(plain.states == pointed.states)
                #expect(pointed.stateHolds == plain.stateHolds)
            }
        }
    }

    @Test("Other personas never receive a sleep state in any mood, time or quiet context")
    func sleepIsExclusiveToSleepyPersona() {
        let removed: Set<String> = ["sleeping", "powering-down", "bored"]
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                #expect(!removed.contains(persona.state(for: mood)))
                for day in [14, 19] {
                    for hour in [2, 14, 23] {
                        for quiet in [false, true] {
                            for pointed in [false, true] {
                                let programme = BotMarkProgramme.forMood(
                                    mood, persona: persona, isQuiet: quiet, isPointedAt: pointed,
                                    at: at(day, hour), calendar: calendar
                                )
                                #expect(Set(programme.states).isDisjoint(with: removed))
                                if persona != .sleepy {
                                    #expect(!programme.states.contains("drowsy"))
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(BotMarkPersona.sleepy.state(for: .unavailable) == "drowsy")
        #expect(BotMarkPersona.sleepy.state(for: .spent) == "drowsy")
        #expect(BotMarkMood.unavailable.upstreamState == "confused")
    }
}
