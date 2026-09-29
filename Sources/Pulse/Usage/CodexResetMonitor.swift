import Foundation

/// Polls Codex Resets while a Codex account is on the rail, or while the
/// predicted-reset reminder is on.
///
/// One in-flight request, then a sleep of whatever the last response asked
/// for. Opening the panel fetches only once that interval has elapsed, so a
/// hover cannot hammer the endpoint. A failure leaves the last status in
/// place.
@MainActor
final class CodexResetMonitor {
    private let settings: AppSettings
    private let onUpdate: @MainActor (CodexResetStatus?) -> Void
    private let file: URL

    private var status: CodexResetStatus?
    private var etag: String?
    private var maxAge: TimeInterval?
    private var freshUntil = Date.distantPast
    private var sleepFor: TimeInterval = CodexResetSchedule.default
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    private var inFlight = false
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

    /// The panel was opened or the reminder was switched on. No-op while the
    /// last response is still fresh.
    func poke() {
        guard interested, Date() >= freshUntil, !inFlight else { return }
        sleeper?.cancel()
    }

    private var interested: Bool {
        settings.remindsBeforePredictedReset
            || settings.shownAccounts.contains { $0.provider == .codex }
    }

    private func run() async {
        while !Task.isCancelled {
            if interested, Date() >= freshUntil {
                await fetch()
            } else if !interested {
                sleepFor = CodexResetSchedule.ceiling
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
            onUpdate(status)
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
        case .failed:
            break
        }
        let failed = reply.payload == .failed
        let wait = CodexResetSchedule.delay(
            maxAge: reply.maxAge ?? (failed ? nil : previousMaxAge),
            retryAfter: reply.retryAfter,
            failed: failed
        )
        sleepFor = wait
        freshUntil = Date().addingTimeInterval(wait)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: file),
            let disk = CodexResetDisk.decode(data)
        else { return }

        status = disk.status
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
            let interval = CodexResetSchedule.interval(maxAge: disk.maxAge)
            let remaining = interval - Date().timeIntervalSince(disk.fetchedAt)
            if remaining > 0 {
                freshUntil = Date().addingTimeInterval(remaining)
                sleepFor = remaining
            }
        }
        onUpdate(disk.status)
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
