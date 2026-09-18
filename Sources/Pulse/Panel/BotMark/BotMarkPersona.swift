import Foundation

/// A mark's personality: which of the upstream's states it plays for each
/// mood, and how quickly it moves.
///
/// Eight of these exist so that a rail of marks is not eight copies of one
/// character. A colour tells two rings apart at a glance; a different rhythm
/// tells them apart while you watch them.
///
/// **A persona does not touch the body.** Which shape a mark wears is the
/// reader's choice — `BotMarkBody`, round by default — and tying it to
/// temperament would mean picking "sleepy" to get a bean.
///
/// **A persona may change how a mood is said, never what it says.** `spent`
/// plays `sad` for one persona and `bored` for another — both are "this limit
/// is finished", drawn by a character who takes it differently. None of them
/// may play `working` for a provider that is idle, or `idle` for one that is
/// spent: the mood is the reading, and the persona is only the accent.
enum BotMarkPersona: String, CaseIterable, Identifiable, Sendable {
    case calm
    case eager
    case steady
    case curious
    case sleepy
    case playful
    case stoic
    case proud

    var id: String { rawValue }

    /// How the mood is played.
    ///
    /// Every state named here means the same thing as the mood it stands for.
    /// The differences are temperament: an eager mark is *excited* to be
    /// working where a stoic one is merely working, and a sleepy one is
    /// *drowsy* about a spent limit where a proud one is *sad* about it.
    func state(for mood: BotMarkMood) -> String {
        switch mood {
        case .working:
            switch self {
            case .eager, .playful: "excited"
            case .curious: "searching"
            case .sleepy, .stoic, .calm, .steady, .proud: "working"
            }
        case .fetching:
            switch self {
            case .curious, .eager: "curious"
            case .sleepy, .steady: "listening"
            case .calm, .playful, .stoic, .proud: "searching"
            }
        case .spent:
            switch self {
            case .sleepy: "drowsy"
            case .stoic, .steady: "bored"
            case .calm, .eager, .curious, .playful, .proud: "sad"
            }
        case .asleep:
            switch self {
            case .stoic: "powering-down"
            case .sleepy: "drowsy"
            default: "sleeping"
            }
        case .idle:
            switch self {
            case .eager: "curious"
            case .steady: "humming"
            case .sleepy: "bored"
            case .playful: "playful"
            case .proud: "proud"
            case .calm, .curious, .stoic: "idle"
            }
        }
    }

    /// What a working mark takes in turn.
    ///
    /// **Work is not one state.** A single state loops every second and a half
    /// for as long as the turn lasts, which reads as a screensaver rather than
    /// as work. These are the upstream states that mean something is being
    /// done — `working` at it, `spawning` generating, `writing` with the
    /// pencil out, `searching` for something, `excited` about it — mixed a
    /// little differently per character.
    ///
    /// `angry` joins the list out of hours, and only then: a turn at eleven at
    /// night is still work, done by somebody who would rather not be. It is
    /// the one state here that says nothing about the work itself, which is
    /// why it is never in the list during the day.
    func workingStates(overtime: Bool) -> [String] {
        var states: [String]
        switch self {
        case .calm: states = ["working", "spawning", "writing"]
        case .eager: states = ["excited", "spawning", "working"]
        case .steady: states = ["working", "writing", "spawning"]
        case .curious: states = ["searching", "spawning", "working"]
        case .sleepy: states = ["working", "writing", "searching"]
        case .playful: states = ["excited", "writing", "spawning"]
        case .stoic: states = ["working", "writing", "thinking"]
        case .proud: states = ["working", "spawning", "excited"]
        }
        if overtime { states.append("angry") }
        return Self.distinct(states)
    }

    /// What an idle mark takes in turn.
    ///
    /// **Quiet is a fact, so it may be shown.** `quiet` is "no CLI has written
    /// anything for twenty minutes", which is the rail's own reading of
    /// nothing happening: a mark that gets visibly bored after a while, and
    /// sleepy about it late at night, is the same reading with a day in it.
    /// Neither replaces the persona's own idle state — they join it, so a
    /// bored mark still comes back to itself.
    func idleStates(quiet: Bool, overtime: Bool) -> [String] {
        let resting = state(for: .idle)
        guard quiet else { return [resting] }
        // Deduplicated, because the sleepy character rests *at* `bored`: its
        // quiet playlist would otherwise be that state twice, which rotates
        // between two identical entries.
        return Self.distinct([resting, overtime ? "drowsy" : "bored"])
    }

    /// First occurrences, in order. `Set` would lose the order, and the order
    /// is what makes the first entry the character's own.
    private static func distinct(_ states: [String]) -> [String] {
        var seen: Set<String> = []
        return states.filter { seen.insert($0).inserted }
    }

    /// How long it waits between things.
    ///
    /// **Larger is slower.** Upstream multiplies every gap by this — the wait
    /// until the next blink, the next glance, the next change of expression —
    /// so 1.5 is a mark that blinks half as often, not one that moves fast.
    var tempo: Double {
        switch self {
        case .playful, .eager: 0.85   // shorter waits between blinks and glances
        case .sleepy: 1.5
        case .stoic: 1.25
        case .calm, .steady, .curious, .proud: 1
        }
    }

    var motionScale: Double {
        switch self {
        case .playful: 1.15
        case .eager: 1.1
        case .sleepy: 0.8
        case .stoic: 0.6
        case .calm, .steady, .curious, .proud: 1
        }
    }

    var gazeScale: Double {
        switch self {
        case .curious, .eager: 1.2
        case .stoic: 0.5
        case .sleepy: 0.7
        case .calm, .steady, .playful, .proud: 1
        }
    }

    var eyeScale: Double {
        switch self {
        case .eager, .curious: 1.06
        case .stoic: 0.94
        case .calm, .steady, .sleepy, .playful, .proud: 1
        }
    }

    /// The name in the settings picker, in the shape the other settings
    /// enums use: a localized `title`, rendered with `Text(persona.title)`.
    var title: String {
        switch self {
        case .calm: .localized("Calm")
        case .eager: .localized("Eager")
        case .steady: .localized("Steady")
        case .curious: .localized("Curious")
        case .sleepy: .localized("Sleepy")
        case .playful: .localized("Playful")
        case .stoic: .localized("Stoic")
        case .proud: .localized("Proud")
        }
    }

    /// The persona for the nth ring on the rail, when nobody has chosen one.
    ///
    /// Walked in rail order rather than fixed per provider, for the same
    /// reason the colours are dealt that way: what matters is that the ring
    /// beside this one is a different character, and the rail only shows
    /// enabled accounts. Eight personas cover eight rings before anything
    /// repeats, and a repeat is four rings away.
    static func automatic(at index: Int) -> BotMarkPersona {
        let all = BotMarkPersona.allCases
        return all[((index % all.count) + all.count) % all.count]
    }
}
