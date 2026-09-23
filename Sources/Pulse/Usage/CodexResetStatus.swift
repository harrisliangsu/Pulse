import Foundation

/// What [Codex Resets](https://codex-resets.com) currently says about an
/// irregular Codex reset — the public one, not an account's own 5-hour or
/// weekly clock.
///
/// `scheduled.scheduledFor` is an explicit instant. A watch is a forecast:
/// its `expiresAt` is when the forecast itself goes stale, and is not a reset
/// time. The parser drops that field so nothing downstream can print it.
/// `latest.announcedAt` is when the last announcement went out. It is history,
/// not a countdown, and the parser does not read a `scheduled_for` off it.
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
        /// The API's own window phrase, shown as written.
        var forecastWindow: String
    }

    /// The most recent public announcement. Not an account's banked cards,
    /// and not a time a reminder may count down to.
    struct Latest: Equatable, Sendable, Codable {
        var id: String
        /// `regular`, `banked`, a type the API added later, or empty when
        /// the field was absent.
        var resetType: String
        var announcedAt: Date
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
            !level.isEmpty,
            let window = object["forecast_window"] as? String,
            !window.isEmpty
        else { return nil }

        let chance = object["reset_chance_percent"] as? Int
            ?? (object["reset_chance_percent"] as? Double).map { Int($0) }
            ?? (object["reset_chance_percent"] as? NSNumber)?.intValue
        // `expires_at` is deliberately unread.
        return Watch(level: level, chancePercent: chance, forecastWindow: window)
    }

    private static func latest(_ value: Any?) -> Latest? {
        guard let object = value as? [String: Any] else { return nil }
        // When the post went out. A missing or unreadable instant cannot be
        // shown, so the announcement is dropped rather than failing the
        // document. `scheduled_for` on this object is deliberately unread.
        guard let announced = CodexResetDates.parse(object["announced_at"] as? String) else { return nil }
        let id = (object["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let type = (object["reset_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Latest(id: id, resetType: type, announcedAt: announced)
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

    /// The site's explanation of a banked credit. Other types have none.
    static func help(resetType: String) -> String? {
        guard resetType == "banked" else { return nil }
        return String.localized("A reset credit you apply yourself when you need it. It does not restore usage right away. In the Codex app, open your profile from the sidebar, go to Usage, and apply an available reset credit.")
    }

    /// What VoiceOver reads for the row: relative time, then type and clock.
    static func spoken(relative: String, detail: String) -> String {
        String.localized("\(relative), \(detail)")
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
