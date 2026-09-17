import Foundation
import Testing
@testable import Pulse

/// The money formatter's two jobs: never show a positive amount as `$0.00`,
/// and never drop the digits a hover is there to reveal.
///
/// The locale is passed in rather than read from `LocalizationSource`, so the
/// language the machine happens to run in cannot decide whether these pass —
/// and so parallel tests never fight over one global.
@Suite("Spend format")
struct SpendFormatTests {
    private static let en = Locale(identifier: "en_US")
    private static let zh = Locale(identifier: "zh_CN")

    @Test("A real zero is a value and keeps its two places")
    func zeroKeepsTwoPlaces() {
        #expect(SpendFormat.money(0, locale: Self.en) == "$0.00")
        #expect(SpendFormat.money(0, locale: Self.zh).contains("0.00"))
        // The visible form of a zero does not take the "less than a cent" path.
        #expect(!SpendFormat.money(0, locale: Self.en).hasPrefix("<"))
    }

    @Test("A positive amount under a cent says so rather than reading as free")
    func underACentIsNotFree() {
        let shown = SpendFormat.money(0.0001, locale: Self.en)
        #expect(shown.hasPrefix("<"))
        #expect(shown != "$0.00")

        #expect(shown == "< $0.01")
        #expect(SpendFormat.money(0.0001, locale: Self.zh) == "< US$0.01")
    }

    @Test("A tiny positive amount survives the hover in both locales")
    func tinyAmountsKeepSignificantDigits() {
        // A fixed six places would print `$0.000000` for both of these.
        #expect(SpendFormat.moneyExact(1e-7, locale: Self.en).contains("0.0000001"))
        #expect(SpendFormat.moneyExact(1e-12, locale: Self.en).contains("0.000000000001"))
        #expect(SpendFormat.moneyExact(1e-7, locale: Self.en) != "$0.000000")

        let chinese = SpendFormat.moneyExact(1e-7, locale: Self.zh)
        #expect(chinese.contains("0.0000001"))
        #expect(chinese.contains("US$"))
    }

    @Test("A large amount keeps its real fraction in the hover")
    func largeAmountsKeepFractions() {
        #expect(SpendFormat.moneyExact(1_234_567.125, locale: Self.en).contains("1,234,567.125"))
        #expect(SpendFormat.moneyExact(1_234_567.125, locale: Self.zh).contains("1,234,567.125"))
    }

    @Test("The visible form rounds to cents below a thousand and to dollars above")
    func visiblePrecision() {
        #expect(SpendFormat.money(12.3456, locale: Self.en) == "$12.35")
        #expect(SpendFormat.money(1234.56, locale: Self.en).contains("1,235"))
    }

    @Test("A zero hover keeps the two places the page shows")
    func zeroHoverKeepsPlaces() {
        #expect(SpendFormat.moneyExact(0, locale: Self.en) == "$0.00")
    }
}
