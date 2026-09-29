import Foundation

/// What [Codex Resets](https://codex-resets.com) currently says about an
/// irregular Codex reset — the public one, not an account's own 5-hour or
/// weekly clock.
///
/// `scheduled.scheduledFor` is an explicit instant. A watch is a forecast.
/// `windowEnds` is the end of that forecast (`expires_at`): the card counts
/// down to it the way the site does, as a bound a reset may fall before, and
/// it is not an announced reset. `explicitReset` never reads it, so a
/// reminder cannot count down to it either. `latest.announcedAt` is when the
/// last announcement went out. It is history, not a countdown, and the
/// parser does not read a `scheduled_for` off it.
struct CodexResetStatus: Equatable, Sendable, Codable {
    struct Scheduled: Equatable, Sendable, Codable {
        /// Announcement id. Advance reminders dedupe on this plus `scheduledFor`.
        var id: String
        var scheduledFor: Date?
    }

    /// An AI-classified forecast. Not an official reset time.
    struct Watch: Equatable, Sendable, Codable {
        /// `elevated`, `strong`, or a level the API added later.
        var level: String
        var chancePercent: Int?
        /// The API's window phrase. The help mark's fallback when `text` is
        /// absent. Not the line under the title.
        var forecastWindow: String
        /// End of the forecast window (`expires_at`). The card's "before"
        /// bound when it is still ahead. Not a reset time: `explicitReset`
        /// does not read it. Missing on a cache written before the field
        /// existed.
        var windowEnds: Date? = nil
        /// The watch's own note (`text`). The help mark prefers this to
        /// `forecastWindow`. Missing and blank are the same.
        var text: String? = nil
    }

    /// The most recent public announcement. Not an account's banked cards,
    /// and not a time a reminder may count down to.
    struct Latest: Equatable, Sendable, Codable {
        var id: String
        /// `regular`, `banked`, a type the API added later, or empty when
        /// the field was absent.
        var resetType: String
        var announcedAt: Date
        /// The announcement body, as published. Missing and blank are the
        /// same. A banked credit does not show this; a regular reset, and
        /// any type added later, uses it as the tooltip and shows nothing
        /// when it is absent.
        var text: String? = nil
    }

    var scheduled: Scheduled?
    var watch: Watch?
    var latest: Latest? = nil

    /// What the prediction row says. An explicit `scheduledFor` wins over a
    /// watch. Neither, or a schedule that names no instant, is `.empty`.
    /// A latest announcement does not change this: the card prints it on
    /// its own row.
    enum Card: Equatable, Sendable {
        case scheduled(Date)
        case watch(Watch)
        case empty
    }

    var card: Card {
        if let when = scheduled?.scheduledFor { return .scheduled(when) }
        if let watch { return .watch(watch) }
        return .empty
    }

    /// The only instant an advance reminder may count down to.
    /// A watch never contributes one, and neither does `latest`.
    var explicitReset: Date? { scheduled?.scheduledFor }

    /// The status document, or nil when the body is not one.
    ///
    /// A document whose schedule and watch are both null is a real answer
    /// (`.empty`), not a parse failure — the caller keeps its previous copy
    /// only when this returns nil. `latest_reset` may still be present on
    /// that empty prediction.
    static func parse(_ data: Data) -> CodexResetStatus? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let body = root["data"] as? [String: Any]
        else { return nil }

        return CodexResetStatus(
            scheduled: scheduled(body["scheduled_reset"]),
            watch: watch(body["active_watch"]),
            latest: latest(body["latest_reset"])
        )
    }

    private static func scheduled(_ value: Any?) -> Scheduled? {
        guard let object = value as? [String: Any] else { return nil }
        let id = (object["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let when = CodexResetDates.parse(object["scheduled_for"] as? String)
        // A schedule object with neither an id nor an instant says nothing.
        guard !id.isEmpty || when != nil else { return nil }
        return Scheduled(id: id, scheduledFor: when)
    }

    private static func watch(_ value: Any?) -> Watch? {
        guard
            let object = value as? [String: Any],
            let level = object["level"] as? String,
            !level.isEmpty
        else { return nil }

        let chance = object["reset_chance_percent"] as? Int
            ?? (object["reset_chance_percent"] as? Double).map { Int($0) }
            ?? (object["reset_chance_percent"] as? NSNumber)?.intValue
        let window = (object["forecast_window"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (note?.isEmpty == false) ? note : nil
        // The window end is the site's "before" bound. It is stored so the
        // card can count down to it, and nothing here treats it as a reset.
        let ends = CodexResetDates.parse(object["expires_at"] as? String)
        // A level on its own says nothing the card can show.
        guard !window.isEmpty || text != nil || ends != nil else { return nil }
        return Watch(
            level: level,
            chancePercent: chance,
            forecastWindow: window,
            windowEnds: ends,
            text: text
        )
    }

    private static func latest(_ value: Any?) -> Latest? {
        guard let object = value as? [String: Any] else { return nil }
        // When the post went out. A missing or unreadable instant cannot be
        // shown, so the announcement is dropped rather than failing the
        // document. `scheduled_for` on this object is deliberately unread.
        guard let announced = CodexResetDates.parse(object["announced_at"] as? String) else { return nil }
        let id = (object["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let type = (object["reset_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (text?.isEmpty == false) ? text : nil
        return Latest(id: id, resetType: type, announcedAt: announced, text: body)
    }
}

/// How the Codex card says a latest announcement.
///
/// Relative time follows `RelativeDateTimeFormatter` (the same full style as
/// the card's "as of" line). The absolute clock uses the same local template
/// as the card's other reset lines (`MMMdjmm`), and it keeps the date even
/// when the announcement was earlier today — the site's hero does, and the
/// date is which announcement this was. It is not pinned to UTC.
enum CodexResetPresentation {
    static func relative(
        announcedAt: Date,
        now: Date = Date(),
        locale: Locale = LocalizationSource.locale
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: announcedAt, relativeTo: now)
    }

    static func absolute(
        announcedAt: Date,
        locale: Locale = LocalizationSource.locale,
        calendar: Calendar = .current
    ) -> String {
        var calendar = calendar
        calendar.locale = locale
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        return formatter.string(from: announcedAt)
    }

    static func typeLabel(resetType: String) -> String {
        switch resetType {
        case "regular": String.localized("Regular reset")
        case "banked": String.localized("Banked reset credit")
        default: resetType
        }
    }

    /// `{type} · {local absolute}`, or just the clock when the API named no type.
    static func detail(resetType: String, absolute: String) -> String {
        let label = typeLabel(resetType: resetType)
        guard !label.isEmpty else { return absolute }
        return String.localized("\(label) · \(absolute)")
    }

    /// What hovering the type says.
    ///
    /// A banked credit keeps the site's own explanation: you apply it, and
    /// usage does not refill immediately. Every other type, including
    /// `regular` and a kind the API adds later, shows `latest_reset.text`
    /// verbatim. Blank text is no tooltip — the card does not invent one.
    static func help(resetType: String, announcement: String?) -> String? {
        if resetType == "banked" {
            return String.localized("A reset credit you apply yourself when you need it. It does not restore usage right away. In the Codex app, open your profile from the sidebar, go to Usage, and apply an available reset credit.")
        }
        guard let announcement else { return nil }
        let body = announcement.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    /// What VoiceOver reads for the row: relative time, then type and clock.
    static func spoken(relative: String, detail: String) -> String {
        String.localized("\(relative), \(detail)")
    }

    /// Compact confidence for the title row. The level, and the chance when
    /// the API sent one. A missing chance is the level alone — the live
    /// watch often has none, and a blank percent would be a number Pulse made.
    static func confidence(_ watch: CodexResetStatus.Watch) -> String {
        let level = switch watch.level {
        case "elevated": String.localized("Elevated")
        case "strong": String.localized("Strong")
        default: watch.level
        }
        guard let chance = watch.chancePercent else { return level }
        let figure = "\(chance)%"
        return String.localized("\(level) · \(figure) chance")
    }

    /// Local date, weekday and time. The bound's date is which day, so it
    /// stays even when that day is today. The hour cycle follows the locale,
    /// the same way the card's other clocks do.
    static func predictionStamp(
        date: Date,
        locale: Locale = LocalizationSource.locale,
        calendar: Calendar = .current
    ) -> String {
        var calendar = calendar
        calendar.locale = locale
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEEjmm")
        return formatter.string(from: date)
    }

    /// Countdown to a forecast window that is still ahead. `relative` is
    /// already a phrase ("in 21 hours", "21小时后").
    static func mayReset(relative: String) -> String {
        String.localized("May reset \(relative)")
    }

    /// Countdown to an announced instant. Definite: not "may".
    static func resets(relative: String) -> String {
        String.localized("Resets \(relative)")
    }

    /// The window end, as a bound rather than the instant of a reset.
    static func expectedBefore(_ stamp: String) -> String {
        String.localized("Expected before \(stamp)")
    }

    /// What the help mark says. The watch's own note when it has one; the
    /// window phrase otherwise. Blank is no mark — the card does not invent
    /// an event.
    static func context(forecastWindow: String, text: String?) -> String? {
        if let text {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
        }
        let window = forecastWindow.trimmingCharacters(in: .whitespacesAndNewlines)
        return window.isEmpty ? nil : window
    }
}

/// What the Codex card draws for the public forecast and the last announcement.
///
/// The prediction is separate from the latest row. An empty prediction
/// (`scheduled` and `watch` both absent) still produces a latest row when
/// `latest` is set — that is the banked announcement the site leads with.
/// The card draws these values; it does not decide the rules again inline.
struct CodexResetCardLines: Equatable, Sendable {
    /// The prediction block. The title row carries `trailing` (confidence, or
    /// "no prediction yet"). `countdown` and `bound` are the lines under it.
    /// `note` is the help mark; nil hides the mark. An event sentence is
    /// never one of the lines.
    struct Prediction: Equatable, Sendable {
        var trailing: String?
        var countdown: String?
        var bound: String?
        var note: String?
    }

    struct Latest: Equatable, Sendable {
        var relative: String
        /// The words the tooltip is attached to. Empty when the API named no type.
        var typeLabel: String
        var absolute: String
        var detail: String
        var help: String?
        var spoken: String
    }

    var prediction: Prediction
    var latest: Latest?

    static func make(
        _ status: CodexResetStatus?,
        now: Date = Date(),
        locale: Locale = LocalizationSource.locale,
        calendar: Calendar = .current
    ) -> CodexResetCardLines {
        let prediction = Self.prediction(status, now: now, locale: locale, calendar: calendar)
        guard let announcement = status?.latest else {
            return CodexResetCardLines(prediction: prediction, latest: nil)
        }
        let relative = CodexResetPresentation.relative(
            announcedAt: announcement.announcedAt, now: now, locale: locale
        )
        let absolute = CodexResetPresentation.absolute(
            announcedAt: announcement.announcedAt, locale: locale, calendar: calendar
        )
        let typeLabel = CodexResetPresentation.typeLabel(resetType: announcement.resetType)
        let detail = CodexResetPresentation.detail(resetType: announcement.resetType, absolute: absolute)
        let help = CodexResetPresentation.help(
            resetType: announcement.resetType, announcement: announcement.text
        )
        return CodexResetCardLines(
            prediction: prediction,
            latest: Latest(
                relative: relative,
                typeLabel: typeLabel,
                absolute: absolute,
                detail: detail,
                help: help,
                spoken: CodexResetPresentation.spoken(relative: relative, detail: detail)
            )
        )
    }

    /// Countdown and bound from a structured instant. A watch counts down
    /// only while its window end is still ahead — a bound already past is
    /// not shown as an upcoming reset. The event note never becomes a line.
    /// An announced time is definite ("resets"), a watch is not ("may reset"
    /// before the window ends).
    private static func prediction(
        _ status: CodexResetStatus?,
        now: Date,
        locale: Locale,
        calendar: Calendar
    ) -> Prediction {
        switch status?.card {
        case .scheduled(let date):
            let stamp = CodexResetPresentation.predictionStamp(
                date: date, locale: locale, calendar: calendar
            )
            let countdown = date > now
                ? CodexResetPresentation.resets(relative: CodexResetPresentation.relative(
                    announcedAt: date, now: now, locale: locale
                ))
                : nil
            return Prediction(trailing: nil, countdown: countdown, bound: stamp, note: nil)
        case .watch(let watch):
            let note = CodexResetPresentation.context(
                forecastWindow: watch.forecastWindow, text: watch.text
            )
            let trailing = CodexResetPresentation.confidence(watch)
            guard let ends = watch.windowEnds, ends > now else {
                return Prediction(trailing: trailing, countdown: nil, bound: nil, note: note)
            }
            let relative = CodexResetPresentation.relative(
                announcedAt: ends, now: now, locale: locale
            )
            let stamp = CodexResetPresentation.predictionStamp(
                date: ends, locale: locale, calendar: calendar
            )
            return Prediction(
                trailing: trailing,
                countdown: CodexResetPresentation.mayReset(relative: relative),
                bound: CodexResetPresentation.expectedBefore(stamp),
                note: note
            )
        case .empty, nil:
            return Prediction(
                trailing: String.localized("No prediction yet"),
                countdown: nil,
                bound: nil,
                note: nil
            )
        }
    }

    /// Identity of the intel block. Empty when there is nothing that can
    /// change which rows exist, so an open card can rebuild the branch when
    /// an announcement or a window end arrives. The note is part of it: a
    /// help mark that was absent and then is not has to replace the row.
    static func identity(_ status: CodexResetStatus?) -> String {
        let latestPart: String
        if let latest = status?.latest {
            latestPart = "\(latest.id)|\(latest.resetType)|\(latest.announcedAt.timeIntervalSinceReferenceDate)|\(latest.text ?? "")"
        } else {
            latestPart = ""
        }
        let when = status?.scheduled?.scheduledFor
        let watch = status?.watch
        if latestPart.isEmpty, when == nil, watch == nil { return "" }
        let whenText = when.map { String($0.timeIntervalSinceReferenceDate) } ?? ""
        let endsText = watch?.windowEnds.map { String($0.timeIntervalSinceReferenceDate) } ?? ""
        let prediction = "\(whenText)|\(watch?.level ?? "")|\(endsText)|\(watch?.text ?? "")|\(watch?.forecastWindow ?? "")"
        if latestPart.isEmpty { return prediction }
        return "\(latestPart)||\(prediction)"
    }
}

enum CodexResetDates {
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

/// How often to ask Codex Resets, given what its own headers said.
///
/// The floor keeps a short `max-age` from turning a menu-bar app into a
/// poller. The ceiling keeps a long one from hiding a newly announced time
/// for the rest of the day. A failure without `Retry-After` waits the
/// default, and never spins.
enum CodexResetSchedule {
    static let floor: TimeInterval = 120
    static let `default`: TimeInterval = 600
    static let ceiling: TimeInterval = 1800

    static func interval(maxAge: TimeInterval?) -> TimeInterval {
        min(max(maxAge ?? Self.default, floor), ceiling)
    }

    static func delay(maxAge: TimeInterval?, retryAfter: TimeInterval?, failed: Bool) -> TimeInterval {
        if let retryAfter { return min(max(retryAfter, 30), ceiling) }
        if failed { return Self.default }
        return interval(maxAge: maxAge)
    }

    static func maxAge(from header: String?) -> TimeInterval? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let item = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard item.hasPrefix("max-age=") else { continue }
            return TimeInterval(item.dropFirst("max-age=".count))
        }
        return nil
    }

    /// Seconds, or an HTTP-date. Anything else is ignored and the caller
    /// waits the ordinary interval.
    static func retryAfter(from header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header else { return nil }
        let text = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(text) { return max(seconds, 0) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: text) else { return nil }
        return max(date.timeIntervalSince(now), 0)
    }
}

/// One HTTP result, reduced to the fields the poller acts on.
struct CodexResetReply: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case parsed(CodexResetStatus)
        case notModified
        case failed
    }

    var payload: Payload
    var etag: String?
    var maxAge: TimeInterval?
    var retryAfter: TimeInterval?

    static func interpret(statusCode: Int, headers: [String: String], body: Data, now: Date = Date()) -> CodexResetReply {
        let fields = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        let etag = fields["etag"]
        let maxAge = CodexResetSchedule.maxAge(from: fields["cache-control"])
        let retry = CodexResetSchedule.retryAfter(from: fields["retry-after"], now: now)

        switch statusCode {
        case 304:
            return CodexResetReply(payload: .notModified, etag: etag, maxAge: maxAge, retryAfter: nil)
        case 200:
            guard let status = CodexResetStatus.parse(body) else {
                return CodexResetReply(payload: .failed, etag: nil, maxAge: nil, retryAfter: nil)
            }
            return CodexResetReply(payload: .parsed(status), etag: etag, maxAge: maxAge, retryAfter: nil)
        case 429:
            return CodexResetReply(payload: .failed, etag: nil, maxAge: nil, retryAfter: retry ?? CodexResetSchedule.floor)
        default:
            return CodexResetReply(payload: .failed, etag: nil, maxAge: nil, retryAfter: retry)
        }
    }
}
