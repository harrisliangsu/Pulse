import Foundation
import Testing
@testable import Pulse

/// Codex sends its credit balance as a ten-place decimal string; Settings
/// used to print `2500.0000000000` as it came.
@Suite("Codex credit balance")
struct CodexCreditBalanceTests {
    @Test("Trailing zeros are dropped")
    func trailingZeros() {
        let shown = CodexUsageService.creditBalance(["balance": "2500.0000000000"])
        #expect(shown != nil)
        #expect(shown?.contains("0000") == false)
        #expect(shown?.filter(\.isNumber) == "2500")
        #expect(CodexUsageService.creditBalance(["balance": "0.0000000000"]) == "0")
    }

    @Test("At most two places are kept")
    func twoPlaces() {
        let shown = CodexUsageService.creditBalance(["balance": "12.3456000000"])
        #expect(shown?.filter(\.isNumber) == "1235")
    }

    @Test("A number is formatted the same way")
    func numericBalance() {
        #expect(CodexUsageService.creditBalance(["balance": 7]) == "7")
    }

    @Test("Unlimited is no balance; prose is passed through")
    func unlimitedAndProse() {
        #expect(CodexUsageService.creditBalance(["unlimited": true, "balance": "0"]) == nil)
        #expect(CodexUsageService.creditBalance(["balance": "n/a"]) == "n/a")
        #expect(CodexUsageService.creditBalance(nil) == nil)
        #expect(CodexUsageService.creditBalance([:]) == nil)
    }
}
