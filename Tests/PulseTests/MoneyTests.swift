import Foundation
import Testing
@testable import Pulse

/// How money is written, and what an estimate becomes in another currency.
///
/// Every conversion here is a `Money.Conversion` the test builds, and every
/// locale is passed in: the app's own conversion is a global that parallel
/// tests must not fight over, and the machine's language must not decide
/// whether these pass.
@Suite("Money")
struct MoneyTests {
    private static let en = Locale(identifier: "en_US")
    private static let zhHans = Locale(identifier: "zh-Hans")
    private static let zhHant = Locale(identifier: "zh-Hant")
    private static let ko = Locale(identifier: "ko")
    private static let ja = Locale(identifier: "ja")

    private static func conversion(_ currency: DisplayCurrency, rates: [String: Double] = [:], manual: [String: Double] = [:]) -> Money.Conversion {
        Money.Conversion(currency: currency, rates: rates, manual: manual)
    }

    @Test("A dollar is \"$\" in every language, never \"US$\"")
    func dollarIsPlain() {
        for locale in [Self.en, Self.zhHans, Self.zhHant, Self.ko, Self.ja, Locale(identifier: "ru")] {
            #expect(Money.symbol("USD", locale: locale) == "$", "\(locale.identifier)")
            #expect(!Money.reported(12.5, code: "USD", locale: locale).contains("US"), "\(locale.identifier)")
        }
    }

    @Test("Hong Kong and New Taiwan dollars keep their prefix, Traditional Chinese included")
    func prefixedDollars() {
        #expect(Money.symbol("HKD", locale: Self.zhHant) == "HK$")
        #expect(Money.symbol("TWD", locale: Self.zhHant) == "NT$")
        #expect(Money.symbol("TWD", locale: Self.en) == "NT$")
    }

    @Test("Yuan, yen, won and roubles are written with their own signs")
    func otherSymbols() {
        #expect(Money.symbol("CNY", locale: Self.zhHans) == "¥")
        #expect(Money.symbol("KRW", locale: Self.ko) == "₩")
        #expect(Money.symbol("RUB", locale: Locale(identifier: "ru")) == "₽")
    }

    @Test("Without a rate an estimate stays in dollars rather than being converted at a guess")
    func noRateStaysInDollars() {
        let conversion = Self.conversion(.cny)
        #expect(conversion.converted(10).code == "USD")
        #expect(conversion.converted(10).amount == 10)
        #expect(Money.estimate(12.5, locale: Self.en, conversion: conversion) == "$12.50")
    }

    @Test("With a rate an estimate is converted and written in the chosen currency")
    func convertsAtTheRate() {
        let conversion = Self.conversion(.cny, rates: ["CNY": 7])
        #expect(conversion.converted(10).code == "CNY")
        #expect(conversion.converted(10).amount == 70)
        #expect(Money.estimate(10, locale: Self.zhHans, conversion: conversion) == "¥70.00")
    }

    @Test("A typed rate wins over the fetched one; nonsense is ignored")
    func typedRateWins() {
        #expect(Self.conversion(.cny, rates: ["CNY": 7], manual: ["CNY": 7.5]).rate(for: "CNY") == 7.5)
        #expect(Self.conversion(.cny, rates: ["CNY": 7], manual: ["CNY": 0]).rate(for: "CNY") == 7)
        #expect(Self.conversion(.cny, rates: ["CNY": -1]).rate(for: "CNY") == nil)
        #expect(Self.conversion(.cny, rates: ["CNY": .infinity]).rate(for: "CNY") == nil)
        #expect(Self.conversion(.cny).rate(for: "USD") == 1)
    }

    @Test("Yen and won have no cents, and a sliver of one is still not free")
    func wholeUnits() {
        let yen = Self.conversion(.jpy, rates: ["JPY": 150])
        #expect(Money.estimate(1.234, locale: Self.ja, conversion: yen).hasSuffix("185"))
        #expect(!Money.estimate(1.234, locale: Self.ja, conversion: yen).contains("."))
        #expect(Money.estimate(0.001, locale: Self.ja, conversion: yen).hasPrefix("<"))
        #expect(Money.reported(1500, code: "KRW", locale: Self.ko) == "₩1,500")
    }

    @Test("The visible estimate drops cents from the threshold up, in the currency written")
    func wholeFrom() {
        let yuan = Self.conversion(.cny, rates: ["CNY": 7])
        #expect(Money.estimate(20, wholeFrom: 100, locale: Self.zhHans, conversion: yuan) == "¥140")
        #expect(Money.estimate(10, wholeFrom: 100, locale: Self.zhHans, conversion: yuan) == "¥70.00")
    }

    @Test("A hover keeps every digit of a converted estimate")
    func exactEstimate() {
        let yuan = Self.conversion(.cny, rates: ["CNY": 7])
        #expect(Money.exactEstimate(1e-7, locale: Self.zhHans, conversion: yuan).contains("0.0000007"))
        #expect(Money.exactEstimate(0, locale: Self.zhHans, conversion: yuan) == "¥0.00")
    }

    @Test("Every offered currency has a name and a symbol")
    func everyCurrencyIsTitled() {
        for currency in DisplayCurrency.allCases {
            #expect(!Money.symbol(currency.code, locale: Self.en).isEmpty, "\(currency)")
            #expect(currency.code.count == 3)
        }
    }

    @Test("The rate field is read whole: a sign, a letter or a stray separator refuses it")
    func typedRates() {
        #expect(CurrencySettingsGroup.rateEntry("7.12") == .rate(7.12))
        #expect(CurrencySettingsGroup.rateEntry(" 7,12 ") == .rate(7.12))
        #expect(CurrencySettingsGroup.rateEntry("1,339.81") == .rate(1339.81))
        #expect(CurrencySettingsGroup.rateEntry("") == .blank)
        // Stripping characters once turned "-7.12" into 7.12.
        #expect(CurrencySettingsGroup.rateEntry("-7.12") == .refused)
        #expect(CurrencySettingsGroup.rateEntry("7.1.2") == .refused)
        #expect(CurrencySettingsGroup.rateEntry("7 CNY") == .refused)
        #expect(CurrencySettingsGroup.rateEntry("¥7") == .refused)
        #expect(CurrencySettingsGroup.rateEntry("0") == .refused)
        #expect(CurrencySettingsGroup.rateEntry("inf") == .refused)
        #expect(CurrencySettingsGroup.rateEntry("9999999") == .refused)
        #expect(CurrencySettingsGroup.text(7.0, locale: Self.en) == "7")
        #expect(CurrencySettingsGroup.text(6.706494, locale: Self.en) == "6.7065")
    }
}

/// The open access endpoint's reply, and when it is asked again.
@Suite("Exchange rates")
struct ExchangeRatesTests {
    private static let reply = Data("""
    {"result":"success","provider":"https://www.exchangerate-api.com","time_last_update_unix":1792022551,
     "time_next_update_unix":1792109501,"base_code":"USD",
     "rates":{"USD":1,"AED":3.6725,"CNY":6.706494,"HKD":7.848465,"TWD":32.207621,"JPY":158.305497,"KRW":1339.811585,"RUB":83.931439}}
    """.utf8)

    @Test("A success keeps the offered currencies and the source's own update times")
    func parsesSuccess() throws {
        let fetched = Date(timeIntervalSince1970: 1_792_030_000)
        let stored = try #require(ExchangeRates.parse(Self.reply, fetchedAt: fetched))
        #expect(stored.rates == [
            "CNY": 6.706494, "HKD": 7.848465, "TWD": 32.207621, "JPY": 158.305497, "KRW": 1339.811585, "RUB": 83.931439,
        ])
        #expect(stored.updatedAt == Date(timeIntervalSince1970: 1_792_022_551))
        #expect(stored.nextUpdateAt == Date(timeIntervalSince1970: 1_792_109_501))
        #expect(stored.fetchedAt == fetched)
    }

    @Test("An error, another base or no offered currency is no reading")
    func refusesOthers() {
        let error = Data(#"{"result":"error","error-type":"unsupported-code"}"#.utf8)
        let euro = Data(#"{"result":"success","base_code":"EUR","time_last_update_unix":1,"time_next_update_unix":2,"rates":{"CNY":7.8}}"#.utf8)
        let none = Data(#"{"result":"success","base_code":"USD","time_last_update_unix":1,"time_next_update_unix":2,"rates":{"AED":3.67}}"#.utf8)
        for data in [error, euro, none, Data("not json".utf8)] {
            #expect(ExchangeRates.parse(data, fetchedAt: Date()) == nil)
        }
    }

    @Test("Nothing is asked before the source's next update, nor twice in an hour")
    func dueOnlyAfterTheNextUpdate() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        let kept = ExchangeRates.Stored(
            updatedAt: fetched, nextUpdateAt: fetched.addingTimeInterval(86_400), fetchedAt: fetched, rates: ["CNY": 7]
        )
        #expect(ExchangeRates.isDue(nil))
        #expect(!ExchangeRates.isDue(kept, now: fetched.addingTimeInterval(3_600)))
        #expect(ExchangeRates.isDue(kept, now: fetched.addingTimeInterval(86_401)))

        // A next update already past when fetched still waits the hour.
        let stale = ExchangeRates.Stored(
            updatedAt: fetched, nextUpdateAt: fetched.addingTimeInterval(-10), fetchedAt: fetched, rates: ["CNY": 7]
        )
        #expect(!ExchangeRates.isDue(stale, now: fetched.addingTimeInterval(600)))
        #expect(ExchangeRates.isDue(stale, now: fetched.addingTimeInterval(3_600)))
    }

    @Test("What is saved is what a launch loads")
    func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pulse-rates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stored = try #require(ExchangeRates.parse(Self.reply, fetchedAt: Date(timeIntervalSince1970: 5)))
        ExchangeRates.save(stored, in: directory)
        #expect(ExchangeRates.load(from: directory) == stored)
    }
}
