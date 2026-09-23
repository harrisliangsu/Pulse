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
            if let etag = reply.etag { self.etag = etag }
            if let maxAge = reply.maxAge { self.maxAge = maxAge }
            onUpdate(status)
            save()
        case .notModified:
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
        etag = disk.etag
        maxAge = disk.maxAge
        let interval = CodexResetSchedule.interval(maxAge: disk.maxAge)
        let remaining = interval - Date().timeIntervalSince(disk.fetchedAt)
        if remaining > 0 {
            freshUntil = Date().addingTimeInterval(remaining)
            sleepFor = remaining
        }
        onUpdate(disk.status)
    }

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
struct CodexResetDisk: Equatable, Codable, Sendable {
    var status: CodexResetStatus
    var etag: String?
    var fetchedAt: Date
    var maxAge: TimeInterval?

    static func decode(_ data: Data) -> CodexResetDisk? {
        try? JSONDecoder().decode(CodexResetDisk.self, from: data)
    }

    static func encode(_ disk: CodexResetDisk) -> Data? {
        try? JSONEncoder().encode(disk)
    }
}
