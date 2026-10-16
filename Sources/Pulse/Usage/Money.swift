// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The currency estimated money is shown in (Settings → General → Currency).
///
/// One per language Pulse speaks: US dollars (English), yuan (Simplified
/// Chinese), Hong Kong and New Taiwan dollars (Traditional Chinese), yen,
/// won and roubles. **Only estimates are converted** — the money worked out
/// from US-dollar API prices: the value estimate, Token spend, the cards'
/// history, the recap. What a service reports itself — a balance, credits,
/// what a console charged — is that service's figure, shown in the currency
/// it was given in, or it would disagree with the service's own page.
enum DisplayCurrency: String, CaseIterable, Identifiable, Sendable {
    case usd
    case cny
    case hkd
    case twd
    case jpy
    case krw
    case rub

    static let `default` = DisplayCurrency.usd

    var id: String { rawValue }

    /// The ISO code, as `Money` and the rate table use it.
    var code: String { rawValue.uppercased() }

    var title: String {
        let name: String = switch self {
        case .usd: .localized("US dollar")
        case .cny: .localized("Chinese yuan")
        case .hkd: .localized("Hong Kong dollar")
        case .twd: .localized("New Taiwan dollar")
        case .jpy: .localized("Japanese yen")
        case .krw: .localized("South Korean won")
        case .rub: .localized("Russian rouble")
        }
        return "\(name) (\(Money.symbol(code)))"
    }
}

/// How money is written, and what an estimate is worth in the chosen
/// currency.
///
/// **A symbol, not "US$".** Chinese and Korean write a dollar "US$" in the
/// standard style, which on a card read as a different currency from the
/// figure beside it; the narrow symbol is "$" in every language Pulse speaks.
/// Hong Kong and New Taiwan dollars keep their prefix ("HK$", "NT$") — narrow,
/// both are "$" too, and so is the New Taiwan dollar in Traditional Chinese's
/// standard style.
///
/// Global, like `PanelMetrics`, because money is formatted by plain functions
/// on both sides of the AppKit/SwiftUI boundary. `AppSettings` sets the
/// currency, `ExchangeRates` the rates; the views that print money are rebuilt
/// when either changes (`AppSettings.moneyIdentity`).
enum Money {
    /// What converting an estimate needs: the chosen currency and the rates.
    /// A value, so a test converts with its own and never touches the one the
    /// app draws with.
    struct Conversion: Equatable, Sendable {
        var currency = DisplayCurrency.default
        /// Units of each currency to one US dollar, from `ExchangeRates`.
        var rates: [String: Double] = [:]
        /// A rate the reader typed, per currency, which wins over the fetched one.
        var manual: [String: Double] = [:]

        /// Units of `code` to one US dollar: the typed rate, else the fetched
        /// one; nil when there is neither.
        func rate(for code: String) -> Double? {
            guard code != "USD" else { return 1 }
            if let typed = manual[code], typed > 0, typed.isFinite { return typed }
            return rates[code].flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        }

        /// An estimate in US dollars, in the chosen currency. **Dollars still
        /// when there is no rate** — before the first fetch, or offline with
        /// none kept — rather than a figure converted at a rate Pulse does not
        /// have.
        func converted(_ usd: Double) -> (amount: Double, code: String) {
            let code = currency.code
            guard let rate = rate(for: code) else { return (usd, "USD") }
            return (usd * rate, code)
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = Conversion()

    /// The conversion the app draws with, set by `AppSettings.applyMoney`.
    static var conversion: Conversion { lock.withLock { stored } }
    static var currency: DisplayCurrency { conversion.currency }

    static func use(_ currency: DisplayCurrency, manualRates: [String: Double]) {
        lock.withLock {
            stored.currency = currency
            stored.manual = manualRates
        }
    }

    static func useRates(_ rates: [String: Double]) {
        lock.withLock { stored.rates = rates }
    }

    static func converted(_ usd: Double) -> (amount: Double, code: String) {
        conversion.converted(usd)
    }

    /// The code estimates are written in now: the chosen currency, or dollars
    /// while it has no rate.
    static var shownCode: String { converted(0).code }

    /// An estimate in US dollars, written in the chosen currency: two places
    /// below `wholeFrom` (in the currency written), whole units from there,
    /// and always whole for yen and won.
    ///
    /// **A positive amount too small to show is still not free.** Rounded it
    /// would print "$0.00", which reads as nothing spent; it says "< $0.01"
    /// (or "< ¥1") instead. A real zero prints as zero: that one is a
    /// measurement.
    static func estimate(
        _ usd: Double,
        wholeFrom: Double = 1000,
        locale: Locale = LocalizationSource.locale,
        conversion: Conversion = Money.conversion
    ) -> String {
        let (amount, code) = conversion.converted(usd)
        return format(amount, code: code, wholeFrom: wholeFrom, locale: locale)
    }

    /// The same estimate with every significant digit, for a help tag where
    /// the visible rounding hides the digits being checked.
    static func exactEstimate(
        _ usd: Double,
        locale: Locale = LocalizationSource.locale,
        conversion: Conversion = Money.conversion
    ) -> String {
        let (amount, code) = conversion.converted(usd)
        guard amount != 0 else { return format(amount, code: code, wholeFrom: .infinity, locale: locale) }
        return amount.formatted(style(code, locale: locale).precision(.significantDigits(1...15)))
    }

    /// An amount already in `code` — a balance a service reported, or an
    /// estimate `converted` — by the same rules as `estimate`.
    static func format(_ amount: Double, code: String, wholeFrom: Double = 1000, locale: Locale = LocalizationSource.locale) -> String {
        let style = style(code, locale: locale)
        let cents = hasCents(code)
        let unit = cents ? 0.01 : 1
        if amount > 0, amount < unit {
            return String.localized("< \(unit.formatted(style.precision(.fractionLength(cents ? 2 : 0))))")
        }
        return amount.formatted(style.precision(.fractionLength(cents && abs(amount) < wholeFrom ? 2 : 0)))
    }

    /// The format for an amount in `code`: the symbol alone where it is
    /// unambiguous, the prefixed one for HKD and TWD.
    static func style(_ code: String, locale: Locale = LocalizationSource.locale) -> FloatingPointFormatStyle<Double>.Currency {
        switch code {
        case "HKD":
            return .init(code: code, locale: locale)
        case "TWD":
            // Traditional Chinese writes its own dollar "$": "NT$" is what
            // Simplified Chinese writes, in the same digits.
            let prefixed = locale.identifier.hasPrefix("zh-Hant") || locale.identifier.hasPrefix("zh_TW")
                ? Locale(identifier: "zh-Hans") : locale
            return .init(code: code, locale: prefixed)
        default:
            return FloatingPointFormatStyle<Double>.Currency(code: code, locale: locale).presentation(.narrow)
        }
    }

    /// The format for an amount a service reported — a balance, credits, a
    /// charge — in the currency it gave: never converted, cents where the
    /// currency has them.
    static func reportedStyle(_ code: String, locale: Locale = LocalizationSource.locale) -> FloatingPointFormatStyle<Double>.Currency {
        style(code, locale: locale).precision(.fractionLength(hasCents(code) ? 2 : 0))
    }

    static func reported(_ amount: Double, code: String, locale: Locale = LocalizationSource.locale) -> String {
        amount.formatted(reportedStyle(code, locale: locale))
    }

    /// The symbol `style` writes, for a label.
    static func symbol(_ code: String, locale: Locale = LocalizationSource.locale) -> String {
        let written = 0.0.formatted(style(code, locale: locale).precision(.fractionLength(0)))
        return written.filter { !$0.isNumber && !$0.isWhitespace }
    }

    /// Whether `code` is written in whole units: yen and won have no cents.
    static func hasCents(_ code: String) -> Bool {
        !["JPY", "KRW"].contains(code)
    }
}
