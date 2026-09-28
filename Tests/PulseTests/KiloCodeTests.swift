import Foundation
import Testing
@testable import Pulse

/// Kilo Code's credit balance and Kilo Pass allowance.
///
/// **The fixture is second-hand**: written from CodexBar's Kilo provider and
/// its tests (MIT), not captured from a live account. It pins the shape Pulse
/// reads; it does not prove the shape is right.
@Suite("Kilo Code")
struct KiloCodeTests {
    private let context = ProfileContext(provider: .kiloCode, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("The pass is its period's base and bonus credits, and the balance is Kilo's own total")
    func passAndBalance() throws {
        let usage = KiloCodeUsageService.reading(from: try fixture("kilo-code-trpc-batch"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.kiloCode))
        #expect(usage.plan == "Starter")
        #expect(usage.windows.count == 1)
        let pass = try #require(usage.windows.first)
        #expect(pass.kind == .credits)
        // 7.125 used of 19 base + 9.5 bonus.
        #expect(pass.usedFraction == 0.25)
        #expect(!pass.reportsLength)
        #expect(pass.resetsAt == ProfileHTTP.date("2026-03-28T04:00:00.000Z"))
        // `totalBalance_mUsd` is micro-dollars: 12,750,000 is $12.75.
        #expect(usage.creditRemaining == .init(amount: 12.75, currency: "USD"))
        #expect(usage.creditBalance?.contains("12.75") == true)
    }

    @Test("Without Kilo's total, the balance is what is left in each block")
    func balanceFromBlocks() {
        let json = #"[{"result":{"data":{"creditBlocks":[{"balance_mUsd":1500000},{"balance_mUsd":500000}]}}},{"result":{"data":{"subscription":null}}}]"#
        let usage = KiloCodeUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.creditRemaining == .init(amount: 2, currency: "USD"))
        // No pass: a balance and no ring, and no plan named.
        #expect(usage.windows.isEmpty)
        #expect(usage.plan == nil)
    }

    @Test("A tier this build doesn't know is still a Kilo Pass, called only that")
    func unknownTier() {
        let json = #"{"0":{"result":{"data":{"json":{"totalBalance_mUsd":0}}}},"1":{"result":{"data":{"json":{"subscription":{"tier":"tier_999","currentPeriodUsageUsd":1,"currentPeriodBaseCreditsUsd":4}}}}}}"#
        let usage = KiloCodeUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.plan == "Kilo Pass")
        #expect(usage.windows.map(\.usedFraction) == [0.25])
        #expect(usage.creditRemaining == .init(amount: 0, currency: "USD"))
    }

    @Test("A pass with no size, or figures that aren't figures, draws nothing")
    func noFigures() {
        let json = #"[{"result":{"data":{"totalBalance_mUsd":-5}}},{"result":{"data":{"subscription":{"tier":"tier_19","currentPeriodUsageUsd":3,"currentPeriodBaseCreditsUsd":0}}}}]"#
        let usage = KiloCodeUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))

        let noUsed = #"[{"result":{"data":{}}},{"result":{"data":{"subscription":{"currentPeriodBaseCreditsUsd":19}}}}]"#
        #expect(KiloCodeUsageService.reading(from: Data(noUsed.utf8), context: context).state
            == .unavailable(.noLimitsReported))
    }

    @Test("A procedure that refuses the key is a refused key; any other error can't be read")
    func procedureErrors() {
        let refused = #"[{"error":{"json":{"message":"UNAUTHORIZED","data":{"code":"UNAUTHORIZED","httpStatus":401}}}},{"result":{"data":{"subscription":null}}}]"#
        #expect(KiloCodeUsageService.reading(from: Data(refused.utf8), context: context).state
            == .unavailable(.apiKeyRefused))
        #expect(KiloCodeUsageService.reading(from: Data(refused.utf8), context: context, refused: .localLoginExpired).state
            == .unavailable(.localLoginExpired))

        let broken = #"[{"result":{"data":{"totalBalance_mUsd":1}}},{"error":{"json":{"message":"Internal","data":{"code":"INTERNAL_SERVER_ERROR"}}}}]"#
        #expect(KiloCodeUsageService.reading(from: Data(broken.utf8), context: context).state
            == .unavailable(.unreadableReply))
    }

    @Test("A reply that isn't a batch can't be read", arguments: ["not json", "[]", "{}", #"[1,2]"#])
    func unreadable(json: String) {
        let usage = KiloCodeUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("The CLI's saved token is kilo.access")
    func savedToken() {
        #expect(KiloCodeUsageService.savedToken(from: Data(#"{"kilo":{"type":"oauth","access":" tok "}}"#.utf8)) == "tok")
        #expect(KiloCodeUsageService.savedToken(from: Data(#"{"kilo":{"access":""}}"#.utf8)) == nil)
        #expect(KiloCodeUsageService.savedToken(from: Data(#"{"openai":{"access":"x"}}"#.utf8)) == nil)
    }

    @Test("No key and no CLI login is asked for, not sent")
    func missingCredential() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("kilo-\(UUID().uuidString)")
        let empty = ProfileContext(provider: .kiloCode, credential: "  ", serverAddress: nil)
        #expect(await KiloCodeUsageService.fetch(empty, home: home).state == .unavailable(.apiKeyMissing))

        // A CLI file with no token in it is a CLI that is signed out.
        let folder = home.appendingPathComponent(".local/share/kilo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"kilo":{}}"#.utf8).write(to: folder.appendingPathComponent("auth.json"))
        #expect(await KiloCodeUsageService.fetch(empty, home: home).state == .unavailable(.localLoginMissing))
    }

    @Test("The batch asks for the two procedures, each with no input")
    func endpoint() throws {
        let components = try #require(URLComponents(url: KiloCodeUsageService.endpoint, resolvingAgainstBaseURL: false))
        #expect(components.host == "app.kilo.ai")
        #expect(components.path == "/api/trpc/user.getCreditBlocks,kiloPass.getState")
        #expect(components.queryItems?.first { $0.name == "batch" }?.value == "1")
        let input = try #require(components.queryItems?.first { $0.name == "input" }?.value)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: [String: Any]])
        #expect(Set(object.keys) == ["0", "1"])
        #expect(object.values.allSatisfy { $0["json"] is NSNull })
    }
}
