import Foundation

/// Polls Codex Resets while a Codex account is on the rail, or while the
/// predicted-reset reminder is on.
///
/// One in-flight request, then a sleep of whatever the last response asked
/// for. Opening the panel, or a Codex usage refresh, wakes that sleep once
/// two minutes have passed: a hover cannot hammer the endpoint, and it also
/// cannot sit out the document's `max-age` after the site has published the
/// reset. While the cached status still names a `scheduled_for`, the sleep
/// itself is those two minutes. A failure leaves the last status in place.
@MainActor
final class CodexResetMonitor {
    private let settings: AppSettings
    private let onUpdate: @MainActor (CodexResetStatus?) -> Void
    private let file: URL

    private var status: CodexResetStatus?
    private var etag: String?
    private var maxAge: TimeInterval?
    private var freshUntil = Date.distantPast
    private var fetchedAt = Date.distantPast
    private var sleepFor: TimeInterval = CodexResetSchedule.default
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    private var inFlight = false
    private var lookRequested = false
    /// A weekly refill dropped the countdown. Until this instant, a document
    /// that still names the same forecast is shown without it: the copy in
    /// hand is the one the refill has already outgrown. A document that
    /// names a different forecast is shown as it arrived.
    private var quietUntil = Date.distantPast
    private var quietKey = ""
    /// The file predates the stored window end. The next request must not
    /// send `If-None-Match`: a 304 has no body, so `expires_at` would never
    /// be parsed and the card would stay on confidence alone.
    private(set) var refetchingForecastTiming = false

    init(
        settings: AppSettings,
        file: URL = PulseStorage.directory.appending(path: "codex-resets.json"),
        onUpdate: @escaping @MainActor (CodexResetStatus?) -> Void
    ) {
        self.settings = settings
        self.file = file
        self.onUpdate = onUpdate
    }

    /// Restores the cache, then polls. The returned status is the one just
    /// loaded — the caller stores it itself, because the `onUpdate` closure
    /// is the only other path and a miss there leaves the file ahead of the
    /// card.
    @discardableResult
    func start() -> CodexResetStatus? {
        guard loop == nil else { return status }
        load()
        loop = Task { [weak self] in
            await self?.run()
        }
        return status
    }

    /// The on-disk status, without starting the poll. Tests use this so a
    /// cache round trip does not open the network loop.
    func restoreCache() -> CodexResetStatus? {
        load()
        return status
    }

    /// The panel was opened, the Codex card was opened, or a Codex usage
    /// refresh landed. No-op inside the floor, and while a request is
    /// already in flight: a hover cannot hammer the endpoint. Past the
    /// floor it asks even when the document's `max-age` has not elapsed.
    /// Cancelling the sleep is not enough on its own — the loop only
    /// fetches when it was asked, or when `freshUntil` has passed.
    func poke() {
        guard interested, !inFlight else { return }
        let now = Date()
        guard now >= freshUntil || CodexResetSchedule.lookIsDue(fetchedAt: fetchedAt, now: now) else { return }
        lookRequested = true
        sleeper?.cancel()
    }

    /// The primary Codex weekly window refilled. The countdown still on the
    /// card is a forecast of a reset the account has already received, so
    /// it comes off now, and the next document is fetched without waiting
    /// out the cache. The last announcement stays. A document that still
    /// names this same forecast stays quiet until the floor has passed; one
    /// that names a new announcement replaces the row immediately.
    func noteQuotaRestored() {
        guard let status, !status.predictionKey.isEmpty else {
            poke()
            return
        }
        quietKey = status.predictionKey
        quietUntil = Date().addingTimeInterval(CodexResetSchedule.floor)
        onUpdate(presenting(status))
        freshUntil = .distantPast
        lookRequested = true
        sleeper?.cancel()
    }

    private func presenting(_ status: CodexResetStatus, now: Date = Date()) -> CodexResetStatus {
        guard !quietKey.isEmpty else { return status }
        if now < quietUntil, status.predictionKey == quietKey {
            return status.withoutPrediction()
        }
        quietKey = ""
        quietUntil = .distantPast
        return status
    }

    private var interested: Bool {
        settings.remindsBeforePredictedReset
            || settings.shownAccounts.contains { $0.provider == .codex }
    }

    private func run() async {
        while !Task.isCancelled {
            let asked = lookRequested
            lookRequested = false
            if interested, asked || Date() >= freshUntil {
                await fetch()
            } else if !interested {
                sleepFor = CodexResetSchedule.ceiling
            } else if sleepFor <= 0 {
                sleepFor = CodexResetSchedule.floor
            }
            // A refill that landed during the request has to be asked
            // again. Sleeping out the wait would put the pre-announcement
            // document back in front of the one just requested.
            if lookRequested {
                sleepFor = 0
                freshUntil = .distantPast
            }
            let wait = sleepFor
            let sleep = Task {
                do { try await Task.sleep(for: .seconds(wait)) }
                catch { return }
            }
            sleeper = sleep
            await sleep.value
            if Task.isCancelled { return }
        }
    }

    private func fetch() async {
        inFlight = true
        defer { inFlight = false }
        let previousMaxAge = maxAge
        let reply = await CodexResetClient.fetch(etag: etag)
        switch reply.payload {
        case .parsed(let status):
            self.status = status
            refetchingForecastTiming = false
            if let etag = reply.etag { self.etag = etag }
            if let maxAge = reply.maxAge { self.maxAge = maxAge }
            onUpdate(presenting(status))
            save()
        case .notModified:
            // A 304 cannot fill in a window end the file never stored.
            // Saving here would stamp the incomplete watch as current.
            if refetchingForecastTiming {
                etag = nil
                break
            }
            if let etag = reply.etag { self.etag = etag }
            if let maxAge = reply.maxAge { self.maxAge = maxAge }
            save()
            // The store may be showing the countdown taken off after a
            // refill. A 304 says the cached document is still the server's,
            // and once the quiet window has passed that document is what
            // the card shows again.
            if !quietKey.isEmpty, let status {
                onUpdate(presenting(status))
            }
        case .failed:
            break
        }
        let failed = reply.payload == .failed
        let now = Date()
        fetchedAt = now
        var wait = CodexResetSchedule.delay(
            maxAge: reply.maxAge ?? (failed ? nil : previousMaxAge),
            retryAfter: reply.retryAfter,
            failed: failed
        )
        // A rate-limit wait is the server's, and a countdown does not
        // shorten it. Every other wait does, while a `scheduled_for` is
        // still what the card would count toward.
        if reply.retryAfter == nil {
            wait = CodexResetSchedule.paced(wait, status: status)
        }
        sleepFor = wait
        freshUntil = now.addingTimeInterval(wait)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: file),
            let disk = CodexResetDisk.decode(data)
        else { return }

        status = disk.status
        fetchedAt = disk.fetchedAt
        if disk.omitsForecastTiming {
            etag = nil
            maxAge = nil
            freshUntil = .distantPast
            sleepFor = 0
            refetchingForecastTiming = true
        } else {
            etag = disk.etag
            maxAge = disk.maxAge
            refetchingForecastTiming = false
            let now = Date()
            let elapsed = now.timeIntervalSince(disk.fetchedAt)
            let interval = CodexResetSchedule.interval(maxAge: disk.maxAge)
            let cadence = CodexResetSchedule.paced(interval, status: disk.status)
            let remaining = cadence - elapsed
            if remaining > 0 {
                freshUntil = now.addingTimeInterval(remaining)
                sleepFor = remaining
            } else {
                freshUntil = .distantPast
                sleepFor = 0
            }
        }
        onUpdate(presenting(disk.status))
    }

    /// The next request will send `If-None-Match`. Tests read this: a cache
    /// that predates the window end must not.
    var sendsConditionalRequest: Bool { !(etag ?? "").isEmpty }

    /// The poll is allowed to run now, rather than waiting out a `max-age`
    /// that belongs to a copy missing `expires_at`.
    var forecastFetchIsDue: Bool { Date() >= freshUntil }

    private func save() {
        guard let status else { return }
        let disk = CodexResetDisk(status: status, etag: etag, fetchedAt: Date(), maxAge: maxAge)
        let destination = file
        let data = CodexResetDisk.encode(disk)
        DispatchQueue.global(qos: .utility).async {
            PulseStorage.prepare()
            guard let data else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}

/// The `codex-resets.json` document: the parsed status, not the raw API body.
///
/// `schema` is how a file from before the window end was stored is told
/// apart from one that saved it. The synthesized decoder would treat a
/// missing key as a failure, or — if the property were optional — as "not
/// there", which is the same answer. A missing key is schema 1.
struct CodexResetDisk: Equatable, Codable, Sendable {
    /// Status without a stored `expires_at`. 1.4.7 never wrote the field.
    /// 1.4.8 parsed it, then a 304 re-saved the older copy without it.
    static let legacySchema = 1
    /// The watch's `windowEnds` and `text` are whatever the last body said.
    static let timingSchema = 2

    var status: CodexResetStatus
    var etag: String?
    var fetchedAt: Date
    var maxAge: TimeInterval?
    var schema: Int

    /// A 304 against this file would keep a watch that has no window end.
    var omitsForecastTiming: Bool { schema < Self.timingSchema }

    init(
        status: CodexResetStatus,
        etag: String?,
        fetchedAt: Date,
        maxAge: TimeInterval?,
        schema: Int = timingSchema
    ) {
        self.status = status
        self.etag = etag
        self.fetchedAt = fetchedAt
        self.maxAge = maxAge
        self.schema = schema
    }

    private enum CodingKeys: String, CodingKey {
        case status, etag, fetchedAt, maxAge, schema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(CodexResetStatus.self, forKey: .status)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        maxAge = try container.decodeIfPresent(TimeInterval.self, forKey: .maxAge)
        schema = try container.decodeIfPresent(Int.self, forKey: .schema) ?? Self.legacySchema
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(maxAge, forKey: .maxAge)
        try container.encode(schema, forKey: .schema)
    }

    static func decode(_ data: Data) -> CodexResetDisk? {
        try? JSONDecoder().decode(CodexResetDisk.self, from: data)
    }

    static func encode(_ disk: CodexResetDisk) -> Data? {
        try? JSONEncoder().encode(disk)
    }
}
