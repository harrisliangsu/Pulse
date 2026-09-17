import Foundation
import Testing
@testable import Pulse

/// Which languages count by ten thousands, and in whose characters.
///
/// This is worth pinning because the failure is silent and looks fine: every
/// one of these languages breaks at 10⁴ and 10⁸, so a single shared pair of
/// characters produces a number that is arithmetically right and spelled for
/// the wrong country. 亿 in front of a Taiwanese or Japanese reader is the
/// same class of mistake as leaving the figure in millions.
@Suite("Myriad units")
struct MyriadUnitsTests {
    /// The production accessor reads whatever language the app is set to, so
    /// these go through the same switch with a locale supplied.
    private static func units(_ identifier: String) -> (tenThousand: String, hundredMillion: String)? {
        LocalizationSource.myriadUnits(for: Locale(identifier: identifier))
    }

    @Test("English and the other latin-script languages group by thousands")
    func latinGroupsByThousands() {
        #expect(Self.units("en_US") == nil)
        #expect(Self.units("fr_FR") == nil)
    }

    @Test("Each language gets its own characters")
    func characters() {
        #expect(Self.units("zh_Hans")?.hundredMillion == "亿")
        #expect(Self.units("zh_Hant")?.hundredMillion == "億")
        #expect(Self.units("ja_JP")?.hundredMillion == "億")
        #expect(Self.units("ko_KR")?.hundredMillion == "억")

        #expect(Self.units("zh_Hans")?.tenThousand == "万")
        #expect(Self.units("zh_Hant")?.tenThousand == "萬")
        #expect(Self.units("ja_JP")?.tenThousand == "万")
        #expect(Self.units("ko_KR")?.tenThousand == "만")
    }

    /// A locale that names the region but not the script is what a system set
    /// to Taiwanese or Hong Kong Chinese can produce.
    @Test("Traditional Chinese is recognised by region as well as by script")
    func traditionalByRegion() {
        for identifier in ["zh_TW", "zh_HK", "zh_MO"] {
            #expect(Self.units(identifier)?.hundredMillion == "億", "\(identifier)")
        }
        #expect(Self.units("zh_CN")?.hundredMillion == "亿")
    }

    /// The whole point of the units: the breaks fall at 10⁴ and 10⁸, not at
    /// 10³ and 10⁶, so the same token count is written differently.
    @Test("The figure is grouped at the myriad breaks")
    func grouping() {
        #expect(TokenCount.short(419_000_000, units: ("万", "亿")) == "4.19亿")
        #expect(TokenCount.short(419_000_000, units: ("萬", "億")) == "4.19億")
        #expect(TokenCount.short(47_640_000, units: ("만", "억")) == "4764만")
        // Below 10⁴ there is no unit to reach for, in any of them.
        #expect(TokenCount.short(9_999, units: ("万", "亿")) == "9999")
        // And with no units it is the thousands ladder.
        #expect(TokenCount.short(419_000_000, units: nil) == "419M")
    }
}
