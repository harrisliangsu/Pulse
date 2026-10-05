import Foundation
import Testing
@testable import Pulse

/// The Token spend pane opens on the last finished scan, which the background
/// read keeps while the switch is on and drops when it goes off.
@Suite("Kept spend scan")
struct KeptSpendScanTests {
    @Test("A finished scan is kept until forgotten")
    func keptAndForgotten() async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseKeptSpend-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ledgers = AgentLedgers(home: root, environment: [:], cacheDirectory: root, prices: { [:] })

        #expect(await ledgers.keptSnapshot() == nil)

        let before = Date()
        _ = try await ledgers.scan()
        let kept = try #require(await ledgers.keptSnapshot())
        #expect(kept.at >= before)

        await ledgers.forget()
        #expect(await ledgers.keptSnapshot() == nil)
    }
}
