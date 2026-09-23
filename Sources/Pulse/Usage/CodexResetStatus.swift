import Foundation

/// What [Codex Resets](https://codex-resets.com) currently says about an
/// irregular Codex reset — the public one, not an account's own 5-hour or
/// weekly clock.
///
/// `scheduled.scheduledFor` is an explicit instant. A watch is a forecast:
/// its `expiresAt` is when the forecast itself goes stale, and is not a reset
/// time. The parser drops that field so nothing downstream can print it.
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

    var scheduled: Scheduled?
    var watch: Watch?

    /// What the Codex card says. An explicit `scheduledFor` wins over a watch.
    /// Neither, or a schedule that names no instant, is `.empty`.
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
    /// A watch never contributes one.
    var explicitReset: Date? { scheduled?.scheduledFor }

    /// The status document, or nil when the body is not one.
    ///
    /// A document whose schedule and watch are both null is a real answer
    /// (`.empty`), not a parse failure — the caller keeps its previous copy
    /// only when this returns nil.
    static func parse(_ data: Data) -> CodexResetStatus? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let body = root["data"] as? [String: Any]
        else { return nil }

        return CodexResetStatus(
            scheduled: scheduled(body["scheduled_reset"]),
            watch: watch(body["active_watch"])
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
