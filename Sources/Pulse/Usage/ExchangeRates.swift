// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The day's rates from US dollars, for showing estimates in another currency
/// (`Money`, `DisplayCurrency`).
///
/// **Source:** ExchangeRate-API's open access endpoint — no key, updated once
/// a day, one small JSON file with every currency per US dollar and the time
/// of the next update. Its terms ask for two things, and Pulse does both:
/// a "Rates By Exchange Rate API" link where the rates are used (the currency
/// row in Settings, `attribution`), and no more than a request a day or so —
/// a caller that asks more often than hourly is answered 429 for twenty
/// minutes. The data may be kept, and is: `exchange-rates.json`, so a launch
/// offline still converts at the last day's rate rather than not at all.
///
/// **Asked only while a currency other than the dollar is chosen**
/// (`ExchangeRateKeeper`), and only once the source's own next-update time
/// has passed. A rate the reader types wins over the fetched one
/// (`AppSettings.manualExchangeRates`).
enum ExchangeRates {
    struct Stored: Codable, Equatable, Sendable {
        /// When the source last moved its rates.
        var updatedAt: Date
        /// When the source says it will move them next; nothing is asked
        /// before then.
        var nextUpdateAt: Date
        var fetchedAt: Date
        /// Units of each currency to one US dollar, by ISO code.
        var rates: [String: Double]
    }

    static let source = URL(string: "https://open.er-api.com/v6/latest/USD")!
    /// The page the terms ask the rates to link to.
    static let attribution = URL(string: "https://www.exchangerate-api.com")!

    /// The least time between two requests, whatever the source says: the
    /// rate the terms promise is never limited.
    static let minimumInterval: TimeInterval = 60 * 60

    static func file(in directory: URL = PulseStorage.directory) -> URL {
        directory.appending(path: "exchange-rates.json")
    }

    static func load(from directory: URL = PulseStorage.directory) -> Stored? {
        guard let data = try? Data(contentsOf: file(in: directory)) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static func save(_ stored: Stored, in directory: URL = PulseStorage.directory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: file(in: directory), options: .atomic)
    }

    /// Whether `kept` is old enough to ask again: none kept, or the source's
    /// next update has passed and the last request is an hour gone.
    static func isDue(_ kept: Stored?, now: Date = Date()) -> Bool {
        guard let kept else { return true }
        return now >= kept.nextUpdateAt && now.timeIntervalSince(kept.fetchedAt) >= minimumInterval
    }

    /// `{"result": "success", "base_code": "USD", "time_last_update_unix": …,
    /// "time_next_update_unix": …, "rates": {"CNY": 6.71, …}}`, the offered
    /// currencies only, each a positive number. Nil for anything else — an
    /// `"error"` result, another base, no rates Pulse offers.
    static func parse(_ data: Data, fetchedAt: Date) -> Stored? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["result"] as? String == "success",
            object["base_code"] as? String == "USD",
            let table = object["rates"] as? [String: Any],
            let updated = (object["time_last_update_unix"] as? NSNumber)?.doubleValue,
            let next = (object["time_next_update_unix"] as? NSNumber)?.doubleValue
        else { return nil }

        var rates: [String: Double] = [:]
        for currency in DisplayCurrency.allCases where currency != .usd {
            if let value = (table[currency.code] as? NSNumber)?.doubleValue, value > 0, value.isFinite {
                rates[currency.code] = value
            }
        }
        guard !rates.isEmpty else { return nil }
        return Stored(
            updatedAt: Date(timeIntervalSince1970: updated),
            nextUpdateAt: Date(timeIntervalSince1970: next),
            fetchedAt: fetchedAt,
            rates: rates
        )
    }

    /// One request, through the proxy Settings chose. Nil on any failure.
    static func download() async -> Data? {
        var request = URLRequest(url: source)
        request.timeoutInterval = 20
        guard
            let (data, response) = try? await NetworkSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

/// Keeps `AppSettings.exchangeRates` current while a currency other than the
/// dollar is chosen, and does nothing while it is not.
///
/// The kept rates are put into effect at launch, before any request, so the
/// first panel drawn is already in the chosen currency. Then a look every
/// `checkInterval`, which asks only when `ExchangeRates.isDue` — in practice
/// once a day. A failed request is tried again at the next look, not before.
@MainActor
final class ExchangeRateKeeper {
    static let checkInterval: TimeInterval = 20 * 60

    private let settings: AppSettings
    private var loop: Task<Void, Never>?
    private var lastAttempt: Date?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        if settings.exchangeRates == nil { settings.exchangeRates = ExchangeRates.load() }
        follow()
    }

    /// Re-arms on every change of currency, the way `SpendWarmer` follows its
    /// switch.
    private func follow() {
        withObservationTracking {
            _ = settings.displayCurrency
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        loop?.cancel()
        guard settings.displayCurrency != .usd else {
            loop = nil
            return
        }
        loop = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.fetchIfDue()
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
    }

    private func fetchIfDue() async {
        let now = Date()
        guard ExchangeRates.isDue(settings.exchangeRates, now: now) else { return }
        // A currency switched back and forth must not become a request each time.
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.checkInterval { return }
        lastAttempt = now
        guard
            let data = await ExchangeRates.download(),
            let fresh = ExchangeRates.parse(data, fetchedAt: now)
        else { return }
        ExchangeRates.save(fresh)
        settings.exchangeRates = fresh
    }
}
