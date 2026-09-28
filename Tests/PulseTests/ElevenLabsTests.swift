import Foundation
import Testing
@testable import Pulse

/// ElevenLabs' subscription credits.
///
/// **The fixture is second-hand**: written from CodexBar's ElevenLabs plugin
/// and its docs (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("ElevenLabs")
struct ElevenLabsTests {
    private let context = ProfileContext(provider: .elevenLabs, credential: "key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Character credits are read as used out of the limit, with the stated reset")
    func credits() throws {
        let usage = ElevenLabsUsageService.reading(from: try fixture("elevenlabs-subscription"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.elevenLabs))
        #expect(usage.plan == "Creator")
        #expect(usage.windows.count == 1)
        let window = try #require(usage.windows.first)
        #expect(window.kind == .credits)
        #expect(window.usedFraction == 0.25)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_780_000_000))
        // The billing period's length is not stated.
        #expect(!window.reportsLength)
    }

    @Test("Voice slots are not an allowance and are left off")
    func voiceSlots() throws {
        let usage = ElevenLabsUsageService.reading(from: try fixture("elevenlabs-subscription"), context: context)
        #expect(!usage.windows.contains { $0.id.contains("voice") })
    }

    @Test("The key goes in ElevenLabs' own header")
    func header() {
        let request = ElevenLabsUsageService.request(key: "abc")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "abc")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.host == "api.elevenlabs.io")
    }

    @Test("Plan names are tidied, not translated")
    func plan() {
        #expect(ElevenLabsUsageService.plan("growing_business") == "Growing Business")
        #expect(ElevenLabsUsageService.plan("  ") == nil)
    }

    @Test("A reply that isn't an object can't be read", arguments: ["not json", "[]", #"{"character_count":"many"}"#])
    func unreadable(json: String) {
        let usage = ElevenLabsUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("A zero limit or a negative count is no allowance, not an empty ring", arguments: [
        #"{"character_count":10,"character_limit":0}"#,
        #"{"character_count":-1,"character_limit":100}"#,
        #"{"character_limit":100}"#,
    ])
    func noFigures(json: String) {
        let usage = ElevenLabsUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .elevenLabs, credential: " ", serverAddress: nil)
        #expect(await ElevenLabsUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }
}
