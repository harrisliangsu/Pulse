import Foundation
import Testing
@testable import Pulse

@Suite("Bounded process output ceiling")
struct BoundedProcessCeilingTests {
    @Test("Output is cut at the ceiling exactly, not at the end of the chunk that crosses it")
    func ceilingIsExact() async throws {
        // 300,000 bytes against a ceiling that is not a multiple of any pipe
        // read size, so the crossing chunk is certain to straddle it.
        let result = await BoundedProcess.run(
            URL(filePath: "/bin/sh"), ["-c", "head -c 300000 /dev/zero"],
            environment: nil, deadline: 20, outputCeiling: 100_003
        )
        let data = try result.get()
        #expect(data.count == 100_003)
    }

    @Test("Output under the ceiling is kept whole")
    func underCeilingIsWhole() async throws {
        let result = await BoundedProcess.run(
            URL(filePath: "/bin/sh"), ["-c", "head -c 5000 /dev/zero"],
            environment: nil, deadline: 20, outputCeiling: 100_003
        )
        #expect(try result.get().count == 5_000)
    }
}
