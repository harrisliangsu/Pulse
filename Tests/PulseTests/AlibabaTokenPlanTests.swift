import Foundation
import Testing
@testable import Pulse

/// Alibaba Token Plan's rolling windows, read from the Bailian CLI's output.
///
/// **The fixture is second-hand**: written from CodexBar's Alibaba Token Plan
/// provider and its tests (MIT), not captured from a live run of `bl`. It pins
/// the shape Pulse reads; it does not prove the shape is right.
@Suite("Alibaba Token Plan")
struct AlibabaTokenPlanTests {
    private let context = ProfileContext(provider: .alibabaTokenPlan, credential: nil, serverAddress: nil)
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func reading(_ json: String) -> ProviderUsage {
        AlibabaTokenPlanUsageService.reading(from: Data(json.utf8), context: context, now: now)
    }

    @Test("The three windows are read as the shares the CLI reports, shortest first")
    func windows() throws {
        let usage = AlibabaTokenPlanUsageService.reading(
            from: try fixture("alibaba-token-plan-cli-usage"), context: context, now: now)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.alibabaTokenPlan))
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        #expect(usage.windows.map(\.usedFraction) == [0.25, 0.7, 0.4])
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_787_000_400))
        #expect(usage.windows[1].resetsAt == Date(timeIntervalSince1970: 1_787_001_180))
        #expect(usage.windows.map(\.reportsLength) == [true, true, false])
    }

    @Test("The console's envelope, as `bl console call` prints it, is read the same")
    func envelope() {
        let usage = reading(#"{"code":"200","data":{"DataV2":{"data":{"success":true,"data":{"per5HourPercentage":0.5,"per5HourResetTime":1787000400000}},"success":true}},"successResponse":true}"#)
        #expect(usage.windows.map(\.usedFraction) == [0.5])
    }

    @Test("A figure outside a ratio's range, or not a number, is left off; none left is no limits", arguments: [
        #"{"per5HourPercentage":25,"per1WeekPercentage":-0.1}"#,
        #"{"per5HourPercentage":true,"per1WeekPercentage":"n/a"}"#,
        #"{"quota":{"total":100}}"#,
    ])
    func unreadFigures(json: String) {
        #expect(reading(json).state == .unavailable(.noLimitsReported))
    }

    @Test("A window without its figure takes no reset from beside it, and a past reset is dropped")
    func resets() {
        let usage = reading(#"{"per5HourPercentage":0.1,"per5HourResetTime":1786999000000,"per1WeekResetTime":1787001180000}"#)
        #expect(usage.windows.map(\.kind) == [.fiveHour])
        #expect(usage.windows[0].resetsAt == nil)
    }

    @Test("Output that isn't JSON can't be read")
    func unreadable() {
        #expect(reading("Usage: bl [command]").state == .unavailable(.unreadableReply))
    }

    @Test("A console that wants a sign-in is the saved login expiring")
    func signedOut() {
        let usage = reading(#"{"code":"ConsoleNeedLogin","message":"You need to log in.","successResponse":false}"#)
        #expect(usage.state == .unavailable(.localLoginExpired))
    }

    @Test("A non-zero exit is a sign-in problem only when the CLI says so", arguments: [
        ("Error: not logged in. Run `bl login` first.", ProviderUsage.Unavailability.localLoginExpired),
        ("Token expired, please login again", .localLoginExpired),
        ("unknown command \"token-plan\" for \"bl usage\"", .unreadableReply),
    ])
    func exits(stderr: String, reason: ProviderUsage.Unavailability) {
        #expect(AlibabaTokenPlanUsageService.reason(forExitOf: stderr) == reason)
    }

    @Test("Each site is asked in the CLI's own words")
    func arguments() {
        #expect(AlibabaTokenPlanUsageService.sites.map(\.site) == ["international", "domestic"])
        #expect(AlibabaTokenPlanUsageService.arguments(site: "domestic", region: "cn-beijing") == [
            "usage", "token-plan", "--console-region", "cn-beijing", "--console-site", "domestic", "--output", "json",
        ])
    }

    @Test("The CLI's environment finds its own directory and carries no secret of Pulse's")
    func environment() {
        let binary = URL(fileURLWithPath: "/tmp/somewhere/bl")
        let environment = AlibabaTokenPlanUsageService.environment(for: binary)
        #expect(environment["PATH"]?.hasPrefix("/tmp/somewhere:") == true)
        let allowed: Set<String> = [
            "PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
        ]
        #expect(Set(environment.keys).isSubset(of: allowed))
    }

    @Test("A stand-in CLI's output and its refusal both come back as they mean")
    func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pulse-bl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let working = directory.appending(path: "bl")
        try Data("#!/bin/sh\nprintf '%s' '{\"per5HourPercentage\":0.2}'\n".utf8).write(to: working)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: working.path)
        let output = try await AlibabaTokenPlanUsageService.run(working, ["usage"]).get()
        #expect(AlibabaTokenPlanUsageService.reading(from: output, context: context, now: now).windows.count == 1)

        let refusing = directory.appending(path: "bl-out")
        try Data("#!/bin/sh\necho 'not logged in' >&2\nexit 1\n".utf8).write(to: refusing)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: refusing.path)
        #expect(await AlibabaTokenPlanUsageService.run(refusing, []) == .failure(.localLoginExpired))

        let missing = directory.appending(path: "absent")
        #expect(await AlibabaTokenPlanUsageService.run(missing, []) == .failure(.localLoginMissing))
    }
}
