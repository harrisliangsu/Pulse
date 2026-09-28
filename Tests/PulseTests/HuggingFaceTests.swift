import Foundation
import Testing
@testable import Pulse

/// Hugging Face's ZeroGPU quota, and the token `hf auth login` saves.
///
/// **The fixture is second-hand**: written from CodexBar's Hugging Face plugin
/// and its tests (MIT), not captured from a live account. It pins the shape
/// Pulse reads; it does not prove the shape is right.
@Suite("Hugging Face")
struct HuggingFaceTests {
    private let context = ProfileContext(provider: .huggingFace, credential: "hf_key", serverAddress: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func home(token: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "hf-\(UUID().uuidString)")
        let cache = home.appending(path: ".cache/huggingface")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        if let token { try Data(token.utf8).write(to: cache.appending(path: "token")) }
        return home
    }

    @Test("The ZeroGPU quota is read from what is left of it")
    func quota() throws {
        let usage = HuggingFaceUsageService.reading(from: try fixture("hugging-face-zero-gpu-quota"), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.huggingFace))
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.kind == .daily)
        #expect(window.scope == "ZeroGPU")
        // 900 of 1,500 seconds left: 600 used.
        #expect(window.usedFraction == 0.4)
        #expect(window.resetsAt == ProfileHTTP.date("2025-08-31T18:00:00Z"))
        // Only the reset is in the reply, not the length.
        #expect(!window.reportsLength)
        #expect(usage.creditBalance == nil)
    }

    @Test("A reset given as seconds since 1970 reads the same")
    func unixReset() throws {
        let json = #"{"base":600,"current":0,"resetsAt":1756663200}"#
        let window = try #require(HuggingFaceUsageService.reading(from: Data(json.utf8), context: context).windows.first)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_756_663_200))
        #expect(window.usedFraction == 1)
        #expect(window.isExhausted)
    }

    @Test("No quota, or figures that aren't ones, draw nothing", arguments: [
        #"{"base":0,"current":0}"#, #"{"base":1500}"#, #"{"base":-1,"current":3}"#,
        #"{"base":1500,"current":-5}"#, #"{"base":true,"current":1}"#, "{}",
    ])
    func noQuota(json: String) {
        let usage = HuggingFaceUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that can't be read", arguments: ["not json", "[]", "<html></html>"])
    func unreadable(json: String) {
        let usage = HuggingFaceUsageService.reading(from: Data(json.utf8), context: context)
        #expect(usage.state == .unavailable(.unreadableReply))
    }

    @Test("The saved token is the file's first line, unquoted")
    func savedToken() throws {
        #expect(HuggingFaceUsageService.savedToken(home: try home(token: "hf_abc\n")) == "hf_abc")
        #expect(HuggingFaceUsageService.savedToken(home: try home(token: "\"hf_q\"\nnext")) == "hf_q")
        #expect(HuggingFaceUsageService.savedToken(home: try home(token: "  \n")) == nil)
        #expect(HuggingFaceUsageService.savedToken(home: try home(token: nil)) == nil)
    }

    @Test("No token pasted and none saved is asked for, not sent")
    func missing() async throws {
        let empty = ProfileContext(provider: .huggingFace, credential: nil, serverAddress: nil)
        let usage = await HuggingFaceUsageService.fetch(empty, home: try home(token: nil))
        #expect(usage.state == .unavailable(.apiKeyMissing))
    }

    @Test("Statuses mean what they mean everywhere", arguments: [
        (401, ProviderUsage.Unavailability.apiKeyRefused), (403, .apiKeyRefused),
        (429, .rateLimited), (500, .serverError), (404, .serverError),
    ])
    func statuses(status: Int, reason: ProviderUsage.Unavailability) {
        #expect(ProfileHTTP.classify(.init(data: Data(), status: status)) == .failure(reason))
    }
}
