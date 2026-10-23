// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// How a limit is being spent against its own window: whether you are ahead of
/// an even burn, and whether it will last.
///
/// **Everything here comes from one reading.** How much is gone and how far
/// through the window the clock is are both in it already — the second is what
/// draws the window-clock arc — so the pace is the difference between two
/// figures the provider reported, and the rate is the first divided by the
/// second. No history is kept, nothing is sampled, and there is no reset to
/// detect: a window that has turned over simply reports a small elapsed share
/// again.
///
/// That is not the first thing this did. It kept the last two dozen readings
/// of every window in a file and measured a *trailing* rate, which is more
/// responsive — it sees you change pace, where an average since the window
/// opened cannot. Measured over the same bursty five-hour window, that
/// responsiveness is not worth having: the trailing estimate ranged over a
/// factor of **24**, the cumulative one over 13.4, and the cumulative one is
/// free. The idea is CodexBar's; the arithmetic was checked against this
/// machine's own transcripts before it was adopted.
///
/// Two statements, and they are **not** equally trustworthy. Each is offered
/// only when the evidence carries it:
///
/// 1. **The verdict** — "expected to last". An extrapolation, but of the
///    coarsest kind: a yes or a no, which survives bursty usage far better
///    than any number does.
/// 2. **When** — "in about an hour", or, on a weekly window, "in 1d 13h".
///    A prediction, and the fragile one. The card states it only inside the
///    reader's horizon (`AppSettings.exhaustionCardHours`, six hours unless
///    they move it). Further out, the verdict can still be said.
///
/// A third was tried and taken out: the pace itself, as a signed figure
/// against an even burn. It read as a balance — "8% in reserve" under a line
/// saying "20% used" is read as *8% left*, when 80% is left — and the verdict
/// already answers the question it was supporting. A number nobody can read
/// without being taught it first is worse than no number.
enum BurnRate {
    /// Nothing is said about a window barely open. Early on, the elapsed share
    /// is so small that dividing by it turns a single burst into a rate that
    /// would empty the account before lunch — measured at 9,574 minutes on a
    /// five-hour window when the guard was missing.
    static let minimumElapsed = 0.03

    struct Reading: Equatable, Sendable {
        /// Whether it is on course to run out before the window resets.
        let exhaustsBeforeReset: Bool
        /// How long until it runs out, when that is before the reset.
        /// Nil when the window lasts, or when nothing may be divided.
        /// The card, not this value, decides how far out a time is worth showing.
        let timeToExhaustion: TimeInterval?
    }

    /// What may be said about a window, or nil when nothing may be.
    static func reading(for window: UsageWindow, now: Date = Date()) -> Reading? {
        // `elapsedFraction` already refuses a window whose length was chosen
        // to sort by rather than reported — which is exactly the length this
        // would otherwise divide by. Codex's 5-hour and weekly windows state
        // both, so they are included; a sort key is not.
        guard let elapsed = window.elapsedFraction(at: now),
              elapsed >= minimumElapsed,
              let resetsAt = window.resetsAt
        else { return nil }

        let used = min(max(window.usedFraction, 0), 1)
        let untilReset = resetsAt.timeIntervalSince(now)
        guard untilReset > 0 else { return nil }

        // The window's own length, from the two figures that describe it.
        let elapsedSeconds = untilReset / (1 - elapsed) * elapsed
        guard elapsedSeconds > 0 else { return nil }

        let perHour = used / elapsedSeconds * 3600
        guard used < 1, perHour > 0 else {
            return Reading(exhaustsBeforeReset: used >= 1, timeToExhaustion: used >= 1 ? 0 : nil)
        }

        let untilEmpty = (1 - used) / perHour * 3600
        let first = untilEmpty < untilReset

        return Reading(
            exhaustsBeforeReset: first,
            timeToExhaustion: first ? untilEmpty : nil
        )
    }

    /// "about an hour", "about 40 minutes", "1d 13h" — **rounded, because the
    /// precision is not real.** "53 minutes" claims a minute's accuracy from a
    /// figure that moves by a factor of thirteen over one afternoon. Past a
    /// day the same idea is a count of days and hours, which is what a weekly
    /// window needs: "about 37 hours" is not how anyone says a day and a half.
    static func approximate(_ seconds: TimeInterval) -> String {
        switch rounded(seconds) {
        case .underQuarter:
            return .localized("under 15 minutes")
        case .minutes(let minutes):
            return .localized("about \("\(minutes)") minutes")
        case .hour:
            return .localized("about an hour")
        case .hours(let text):
            return .localized("about \("\(text)") hours")
        case .days(let days, nil):
            return .localized("about \("\(days)")d")
        case .days(let days, let hours?):
            return .localized("about \("\(days)")d \("\(hours)")h")
        }
    }

    /// The same rounding, without the word "about". The reset sentence already
    /// says "about", and saying it twice is how "约 约 1天" gets onto the card.
    static func span(_ seconds: TimeInterval) -> String {
        switch rounded(seconds) {
        case .underQuarter:
            return .localized("\("15") minutes")
        case .minutes(let minutes):
            return .localized("\("\(minutes)") minutes")
        case .hour:
            return .localized("1 hour")
        case .hours(let text):
            return .localized("\("\(text)") hours")
        case .days(let days, nil):
            return .localized("\("\(days)")d")
        case .days(let days, let hours?):
            return .localized("\("\(days)")d \("\(hours)")h")
        }
    }

    /// What the card draws under one limit, or nil when this setting leaves
    /// the row quiet.
    struct CardLine: Equatable, Sendable {
        enum Tone: Equatable, Sendable {
            /// Inside the reader's horizon: the window's name and a time.
            case countdown
            /// Further out, but before the reset, with the time said once.
            case beforeReset
            /// The same fact, without a time.
            case hint
            /// On course to last.
            case lasts
        }

        var text: String
        var tone: Tone
    }

    /// The line under a limit.
    ///
    /// A time only inside `horizon` (six hours unless the reader moves it).
    /// Past that, the reset sentence when they asked for it, otherwise the
    /// quieter hint, otherwise nothing about an exhaustion that is still only
    /// a verdict. A window that lasts still says so: the line is either there
    /// or it is not, and appearing only for bad news makes the card jump.
    static func cardLine(
        for window: UsageWindow,
        reading: Reading,
        horizon: TimeInterval,
        softHint: Bool,
        beforeReset: Bool
    ) -> CardLine? {
        if let seconds = reading.timeToExhaustion, seconds <= horizon {
            let name = window.forecastName
            let when = approximate(seconds)
            return CardLine(
                text: .localized("\(name) · may run out in \(when)"),
                tone: .countdown
            )
        }
        if reading.exhaustsBeforeReset, beforeReset, let seconds = reading.timeToExhaustion {
            let when = span(seconds)
            return CardLine(
                text: .localized("At the current pace, about \(when) before the next reset."),
                tone: .beforeReset
            )
        }
        if reading.exhaustsBeforeReset, softHint {
            let name = window.forecastName
            return CardLine(
                text: .localized("\(name) · may run out before the reset"),
                tone: .hint
            )
        }
        if !reading.exhaustsBeforeReset {
            return CardLine(text: .localized("Expected to last the window"), tone: .lasts)
        }
        return nil
    }

    private enum Rounded: Equatable {
        case underQuarter
        case minutes(Int)
        case hour
        case hours(String)
        case days(Int, Int?)
    }

    /// Under an hour in quarters; past that in halves of an hour, until a
    /// day, and then in whole hours beside whole days. The cut under an hour
    /// is at 68 rather than 75 because five quarters *is* an hour and a
    /// quarter — printing "about 75 minutes" between "about an hour" and
    /// "about 1.5 hours" reads as a different scale for one step.
    private static func rounded(_ seconds: TimeInterval) -> Rounded {
        let minutes = Int((max(seconds, 0) / 60).rounded())
        if minutes < 15 { return .underQuarter }
        if minutes < 68 {
            let quarters = max(Int((Double(minutes) / 15).rounded()), 1)
            return quarters >= 4 ? .hour : .minutes(quarters * 15)
        }
        let hours = (Double(minutes) / 60 * 2).rounded() / 2
        if hours < 24 {
            let text = hours.formatted(
                .number.precision(.fractionLength(0...1)).locale(LocalizationSource.locale)
            )
            return .hours(text)
        }
        let whole = Int(hours.rounded())
        let days = whole / 24
        let rest = whole % 24
        return .days(max(days, 1), rest == 0 ? nil : rest)
    }
}

/// One remaining-time notice. Several may be on at once; each fires on its own.
///
/// Stored with the notification settings. The id stays put when the hours
/// change, and the memory key includes the hours, so moving the line asks
/// again — the same rule as the low-balance figure — while a pace that
/// wobbles across the old line does not.
struct ExhaustionStage: Codable, Equatable, Sendable, Identifiable {
    var id: String
    /// Whole hours still left when this stage should speak. One hour through
    /// fourteen days: long enough for a weekly window, short of a made-up month.
    var hours: Int

    var remaining: TimeInterval { TimeInterval(hours) * 3600 }

    /// What `AlertMemory` records. The hours are part of it, so editing them
    /// is a new question and a wobble of the estimate is not.
    var memoryKey: String { "\(id)|\(hours)" }

    static let minimumHours = 1
    static let maximumHours = 24 * 14

    static func clamped(_ hours: Int) -> Int {
        min(max(hours, minimumHours), maximumHours)
    }

    /// The stage a fresh install starts with: one notice at 24 hours left.
    static let defaultStage = ExhaustionStage(id: "24h", hours: 24)
    static let defaultStages = [defaultStage]
}
