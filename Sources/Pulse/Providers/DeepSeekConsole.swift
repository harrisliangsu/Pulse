// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// DeepSeek's web console, read with the console's own sign-in: the account's
/// usage day by day — tokens of each kind and what was charged, per model —
/// and the balance, for anyone who has not pasted a key.
///
/// **A second credential beside the key, never instead of it.** The key reads
/// `/user/balance` and nothing else; DeepSeek gives an API key no usage
/// history at all. The console's routes want the console's login token and
/// refuse a key outright (`40003`). That token lives in the browser's
/// `localStorage` under `https://platform.deepseek.com`, key `userToken`,
/// wrapped by the console's storage class:
///
/// ```json
/// {"value":"<token>","__version":"0"}
/// ```
///
/// with `"value":null` once signed out. `ChromiumLocalStorage` reads it
/// without a keychain prompt; it is kept in its own slot of the key store,
/// `deepSeek#console`, and read again from the browser when the console
/// turns the kept copy away.
///
/// Undocumented, like every console route Pulse reads; the shapes below are
/// the console's own bundle's (checked 2026-10-03) and can change.
enum DeepSeekConsole {
    static let origin = "https://platform.deepseek.com"
    static let storageKey = "userToken"
    /// The `APIKeyStore` slot the token is kept in, beside the key.
    static let slot = "console"
    /// The console's own "last 30 days": today and the twenty-nine before it.
    static let days = 30

    // MARK: - Whether a session is kept

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = false

    /// Whether a console token is kept, read from memory: the detailed card
    /// asks on every frame which history it has. Refreshed with the keys
    /// (`UsageStore.loadAPIKeys`).
    static var hasSession: Bool { lock.withLock { stored } }

    static func refreshSession() {
        let present = APIKeyStore.key(for: .deepSeek, slot: slot) != nil
        lock.withLock { stored = present }
    }

    static var keptToken: String? { APIKeyStore.key(for: .deepSeek, slot: slot) }

    // MARK: - The browser's copy

    /// The token out of the console's `localStorage` entry. Nil for a signed-
    /// out console (`"value":null`), an empty one, or anything not shaped like
    /// the storage class's wrapper.
    static func token(fromStorage values: [String: String]) -> String? {
        guard let raw = values[storageKey], let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["value"] as? String
        else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// The first Chromium browser signed in to the console, default first.
    static func fromBrowser(
        in browsers: [BrowserCookies.Browser] = ChromiumLocalStorage.present()
    ) -> (token: String, browser: BrowserCookies.Browser)? {
        guard let found = ChromiumLocalStorage.find(origin: origin, in: browsers, accept: { token(fromStorage: $0) != nil }),
              let token = token(fromStorage: found.values)
        else { return nil }
        return (token, found.browser)
    }

    /// The kept token was turned away: the browser's current one, kept in its
    /// place, if the browser holds a different one. Nil when it does not —
    /// the console has signed this account out everywhere.
    ///
    /// **Only in place of the token that was refused** (`APIKeyStore.replaceKey`):
    /// one removed in Settings while the browser was being read stays removed,
    /// and one saved meanwhile is not written over.
    static func renewedFromBrowser(replacing refused: String) -> String? {
        guard let found = fromBrowser(), found.token != refused else { return nil }
        guard APIKeyStore.replaceKey(refused, with: found.token, for: .deepSeek, slot: slot) else { return nil }
        return found.token
    }

    /// The same, off the caller's thread — a LevelDB per browser profile —
    /// with the in-memory flag brought up to date.
    static func renewed(replacing refused: String) async -> String? {
        let renewed = await Task.detached(priority: .utility) { renewedFromBrowser(replacing: refused) }.value
        if renewed != nil { refreshSession() }
        return renewed
    }

    // MARK: - The replies

    /// Every console route answers `{code, msg, data: {biz_code, biz_msg,
    /// biz_data}}` with HTTP 200, including a refused token (`40002` missing,
    /// `40003` invalid) — the status code alone says nothing.
    struct Envelope<Body: Decodable>: Decodable {
        struct Inner: Decodable {
            let bizCode: Int?
            let bizData: Body?

            enum CodingKeys: String, CodingKey {
                case bizCode = "biz_code"
                case bizData = "biz_data"
            }
        }

        let code: Int?
        let data: Inner?
    }

    /// A number the console may send as a number or as a string: the token
    /// counts are added as numbers by the console, the money is handed to a
    /// decimal type, which takes either. Absent or unreadable is nil, never 0.
    struct Figure: Decodable, Sendable, Equatable {
        let value: Double?

        init(_ value: Double?) { self.value = value }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let read: Double? = if let number = try? container.decode(Double.self) {
                number
            } else if let text = try? container.decode(String.self) {
                Double(text.trimmingCharacters(in: .whitespaces))
            } else {
                nil
            }
            // "nan", "inf" and absurd sizes parse as Doubles too, and turning
            // one into an Int traps: such a figure is absent, not a crash.
            value = read.flatMap { $0.isFinite && abs($0) < 1e15 ? $0 : nil }
        }
    }

    /// `GET /api/v0/usage/by_api_key/amount` — tokens per key, model and bucket.
    struct Amount: Decodable, Sendable {
        struct Series: Decodable, Sendable {
            struct Bucket: Decodable, Sendable {
                struct Usage: Decodable, Sendable {
                    let cacheHit: Figure?
                    let cacheMiss: Figure?
                    let response: Figure?
                    let requests: Figure?

                    enum CodingKeys: String, CodingKey {
                        case cacheHit = "PROMPT_CACHE_HIT_TOKEN"
                        case cacheMiss = "PROMPT_CACHE_MISS_TOKEN"
                        case response = "RESPONSE_TOKEN"
                        case requests = "REQUEST"
                    }
                }

                /// The bucket's start, seconds since 1970.
                let time: Double
                let usage: Usage?
            }

            let model: String?
            let buckets: [Bucket]?
        }

        let bucket: Double?
        let series: [Series]?
    }

    /// `GET /api/v0/usage/by_api_key/cost` — money per currency, key, model
    /// and bucket.
    struct Cost: Decodable, Sendable {
        struct Purse: Decodable, Sendable {
            struct Series: Decodable, Sendable {
                struct Bucket: Decodable, Sendable {
                    let time: Double
                    let cost: Figure?
                }

                let model: String?
                let buckets: [Bucket]?
            }

            let currency: String?
            let series: [Series]?
        }

        let data: [Purse]?
    }

    /// `GET /api/v0/users/get_user_summary` — the wallets. Only the balances
    /// are decoded; the summary also estimates tokens left, which is a guess
    /// of the console's and not repeated here.
    struct Summary: Decodable, Sendable {
        struct Wallet: Decodable, Sendable {
            let balance: Figure?
            let currency: String?
        }

        /// Money topped up.
        let normalWallets: [Wallet]?
        /// Money granted.
        let bonusWallets: [Wallet]?

        enum CodingKeys: String, CodingKey {
            case normalWallets = "normal_wallets"
            case bonusWallets = "bonus_wallets"
        }
    }

    enum Failure: Error, Equatable { case signedOut, failed }

    // MARK: - Asking

    private static func get<Body: Decodable>(
        _ path: String, query: [URLQueryItem] = [], token: String, as: Body.Type
    ) async -> Result<Body, Failure> {
        guard var components = URLComponents(string: origin + path) else { return .failure(.failed) }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return .failure(.failed) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        guard let (data, response) = try? await NetworkSession.shared.data(for: request) else { return .failure(.failed) }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        // Only 401. A refused token answers 200 with a 400xx code; a 403 is
        // the WAF in front of the console, which a new sign-in cannot fix.
        case 401: return .failure(.signedOut)
        default: return .failure(.failed)
        }
        guard let envelope = try? JSONDecoder().decode(Envelope<Body>.self, from: data) else { return .failure(.failed) }
        return outcome(of: envelope)
    }

    static func outcome<Body>(of envelope: Envelope<Body>) -> Result<Body, Failure> {
        // 40002 "Missing Token", 40003 "Authorization Failed (invalid token)",
        // and the rest of the 400xx family is the sign-in's business too.
        if let code = envelope.code, code != 0 {
            return .failure((40_000..<40_100).contains(code) ? .signedOut : .failed)
        }
        guard envelope.data?.bizCode ?? 0 == 0, let body = envelope.data?.bizData else { return .failure(.failed) }
        return .success(body)
    }

    /// The query every usage route takes: `start`/`end` in seconds and `tz`
    /// as a whole number of hours in seconds. A zone off the hour (India's
    /// +5:30) is sent as the hour below with the remainder moved into the
    /// range — exactly what the console does, so the buckets are its own.
    static func range(endingAt now: Date, calendar: Calendar = .current) -> [URLQueryItem]? {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today)
        else { return nil }
        let offset = (calendar.timeZone).secondsFromGMT(for: now)
        let hours = Int((Double(offset) / 3600).rounded(.down)) * 3600
        let remainder = offset - hours
        return [
            URLQueryItem(name: "start", value: String(Int(first.timeIntervalSince1970) + remainder)),
            URLQueryItem(name: "end", value: String(Int(end.timeIntervalSince1970) + remainder)),
            URLQueryItem(name: "tz", value: String(hours)),
        ]
    }

    // MARK: - The history

    /// The last thirty days as a ledger, or why there is none.
    static func ledger(token: String, currency: String?, now: Date = Date()) async -> OpenCodeConsole.Read {
        guard let query = range(endingAt: now) else { return .failed }
        async let amount = get("/api/v0/usage/by_api_key/amount", query: query, token: token, as: Amount.self)
        async let cost = get("/api/v0/usage/by_api_key/cost", query: query, token: token, as: Cost.self)
        switch (await amount, await cost) {
        case (.success(let amount), .success(let cost)):
            return .answered(ledger(amount: amount, cost: cost, preferring: currency, now: now))
        case (.failure(.signedOut), _), (_, .failure(.signedOut)):
            return .signedOut
        default:
            return .failed
        }
    }

    /// Which currency's money the ledger carries. Yuan and dollars cannot be
    /// added, and one is not picked over the other by comparing amounts: the
    /// reader's choice for the ring, else the first the reply lists with any
    /// money in it, else the first at all.
    static func currency(of cost: Cost, preferring preferred: String?) -> Cost.Purse? {
        let purses = (cost.data ?? []).filter { !($0.currency ?? "").isEmpty }
        let hasMoney = { (purse: Cost.Purse) in
            (purse.series ?? []).contains { ($0.buckets ?? []).contains { ($0.cost?.value ?? 0) > 0 } }
        }
        // The ring's currency, unless nothing was charged in it and something
        // was in another — zeroes in yuan beside tokens paid in dollars would
        // say the work was free.
        let chosen = preferred.flatMap { code in purses.first { $0.currency == code } }
        if let chosen, hasMoney(chosen) { return chosen }
        return purses.first(where: hasMoney) ?? chosen ?? purses.first
    }

    /// Day buckets into ledger days, every day of the thirty present so the
    /// chart reads as a calendar.
    ///
    /// Cache-miss input is the ledger's input, cache hits its cache reads,
    /// the response its output — DeepSeek writes no cache, it only reads one.
    /// **No quarter-hours**: a day bucket does not say when in the day the
    /// work ran, so the ledger has no slots and says its timing is aggregate.
    static func ledger(
        amount: Amount, cost: Cost, preferring preferred: String?,
        now: Date, calendar: Calendar = .current
    ) -> UsageLedger {
        // A bucket's middle, not its start: the buckets follow the offset in
        // force *now*, so across a daylight-saving change a day's start sits
        // an hour off local midnight — and an hour early is the day before.
        let half = (amount.bucket.flatMap { $0 > 0 ? $0 : nil } ?? 86_400) / 2
        let day = { (time: Double) in calendar.startOfDay(for: Date(timeIntervalSince1970: time + half)) }

        var tallies: [Date: [String: TokenTally]] = [:]
        for series in amount.series ?? [] {
            let model = series.model ?? ""
            for bucket in series.buckets ?? [] {
                guard let usage = bucket.usage else { continue }
                let kinds = TokenTally(
                    input: Int(usage.cacheMiss?.value ?? 0),
                    cacheWrite: 0,
                    cacheRead: Int(usage.cacheHit?.value ?? 0),
                    output: Int(usage.response?.value ?? 0)
                )
                guard kinds.total > 0 else { continue }
                let date = day(bucket.time)
                tallies[date, default: [:]][model] = (tallies[date]?[model] ?? TokenTally()) + kinds
            }
        }

        let purse = currency(of: cost, preferring: preferred)
        var money: [Date: Double] = [:]
        for series in purse?.series ?? [] {
            for bucket in series.buckets ?? [] {
                guard let charged = bucket.cost?.value, charged != 0 else { continue }
                money[day(bucket.time), default: 0] += charged
            }
        }

        let today = calendar.startOfDay(for: now)
        var days: [LedgerDay] = []
        var date = calendar.date(byAdding: .day, value: -(Self.days - 1), to: today) ?? today
        while date <= today {
            let models = tallies[date] ?? [:]
            let tally = models.values.reduce(TokenTally(), +)
            var entry = LedgerDay(
                date: date, tokens: tally.total, cost: money[date] ?? 0, unpricedTokens: 0,
                models: models.filter { !$0.key.isEmpty }.mapValues(\.total)
            )
            entry.tally = tally
            entry.modelTallies = models.filter { !$0.key.isEmpty }
            days.append(entry)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        var ledger = UsageLedger(
            // No money came back at all: the tokens alone, and no "$0.00"
            // claiming the work was free.
            origin: purse == nil ? .providerStatistics : .providerLogs,
            currency: purse?.currency,
            days: days,
            earliest: days.first { $0.tokens > 0 || $0.cost != 0 }?.date,
            unpricedModels: [],
            modelNames: [:],
            slots: []
        )
        ledger.hasAggregateTiming = true
        return ledger
    }

    // MARK: - The balance

    /// The wallets as the key route's reply, so the ring is drawn by exactly
    /// the same rule whichever credential answered: topped-up plus granted
    /// money per currency. The console states no `is_available`, so nothing
    /// here may call the account spent.
    static func balance(token: String) async -> Result<DeepSeekUsageService.Reply, Failure> {
        await get("/api/v0/users/get_user_summary", token: token, as: Summary.self).map(reply(from:))
    }

    /// The balance, renewing a refused token from the browser once — the
    /// refresh loop is what notices an expired sign-in first when no key is
    /// set, and it should not wait for a history read to mend it.
    static func balanceRenewing(token: String) async -> Result<DeepSeekUsageService.Reply, Failure> {
        let first = await balance(token: token)
        guard case .failure(.signedOut) = first, let renewed = await renewed(replacing: token) else { return first }
        return await balance(token: renewed)
    }

    static func reply(from summary: Summary) -> DeepSeekUsageService.Reply {
        var order: [String] = []
        var topped: [String: Double] = [:]
        var granted: [String: Double] = [:]
        for (wallets, isBonus) in [(summary.normalWallets, false), (summary.bonusWallets, true)] {
            for wallet in wallets ?? [] {
                guard let currency = wallet.currency, !currency.isEmpty, let amount = wallet.balance?.value else { continue }
                if !order.contains(currency) { order.append(currency) }
                if isBonus { granted[currency, default: 0] += amount } else { topped[currency, default: 0] += amount }
            }
        }
        let text = { (amount: Double?) in amount.map { String(format: "%.2f", $0) } }
        return DeepSeekUsageService.Reply(
            isAvailable: nil,
            balanceInfos: order.map { currency in
                DeepSeekUsageService.Reply.Info(
                    currency: currency,
                    totalBalance: text((topped[currency] ?? 0) + (granted[currency] ?? 0)),
                    grantedBalance: text(granted[currency]),
                    toppedUpBalance: text(topped[currency])
                )
            }
        )
    }
}

/// One console read at a time, and a fresh answer reused for a minute: the
/// card, Settings and the warm-up all ask, and two routes a read is cheap
/// enough not to need more than that.
actor DeepSeekConsoleHistory {
    static let shared = DeepSeekConsoleHistory()

    static let freshFor: TimeInterval = 60

    private var last: (token: String, currency: String?, at: Date, read: OpenCodeConsole.Read)?
    private var running: (token: String, currency: String?, task: Task<OpenCodeConsole.Read, Never>)?

    func ledger(token: String, currency: String?, now: Date = Date()) async -> OpenCodeConsole.Read {
        // Any outcome, not only an answer: a refused token asked again at
        // every settings change would cost two requests and a browser scan
        // each time.
        if let last, last.token == token, last.currency == currency, now.timeIntervalSince(last.at) < Self.freshFor {
            return last.read
        }
        if let running, running.token == token, running.currency == currency { return await running.task.value }

        let task = Task { await Self.read(token: token, currency: currency) }
        running = (token, currency, task)
        let read = await task.value
        if running?.task == task { running = nil }
        last = (token, currency, Date(), read)
        return read
    }

    /// Reads with the kept token, and once more with the browser's if the
    /// console turned the kept one away.
    private static func read(token: String, currency: String?) async -> OpenCodeConsole.Read {
        let first = await DeepSeekConsole.ledger(token: token, currency: currency)
        guard case .signedOut = first, let renewed = await DeepSeekConsole.renewed(replacing: token) else { return first }
        return await DeepSeekConsole.ledger(token: renewed, currency: currency)
    }

    func forget() {
        last = nil
        running = nil
    }
}
