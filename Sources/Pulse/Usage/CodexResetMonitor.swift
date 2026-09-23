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

    func start() {
        guard loop == nil else { return }
        load()
        loop = Task { [weak self] in
            await self?.run()
        }
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
                try? await Task.sleep(for: .seconds(wait))
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

    private struct Disk: Codable {
        var status: CodexResetStatus
        var etag: String?
        var fetchedAt: Date
        var maxAge: TimeInterval?
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: file),
            let disk = try? JSONDecoder().decode(Disk.self, from: data)
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
        let disk = Disk(status: status, etag: etag, fetchedAt: Date(), maxAge: maxAge)
        let destination = file
        let data = try? JSONEncoder().encode(disk)
        DispatchQueue.global(qos: .utility).async {
            PulseStorage.prepare()
            guard let data else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}
