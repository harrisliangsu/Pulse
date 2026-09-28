import Foundation
import Testing
@testable import Pulse

/// Starting a usage window after it resets: when it is due, which windows
/// count, the hours it may act in, and what is sent.
@Suite("Window primer")
struct WindowPrimerTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func window(_ kind: UsageWindow.Kind, resets: Date?, scope: String? = nil) -> UsageWindow {
        UsageWindow(id: "w", kind: kind, scope: scope, usedFraction: 0, windowSeconds: 18_000, resetsAt: resets)
    }

    // MARK: Hours

    @Test("Daytime hours, overnight hours, and all day")
    func hoursContain() {
        let day = PrimerHours(start: 7, end: 23)
        #expect(day.contains(Self.at(7), calendar: Self.calendar))
        #expect(!day.contains(Self.at(23), calendar: Self.calendar))
        #expect(!day.contains(Self.at(3), calendar: Self.calendar))
        let night = PrimerHours(start: 22, end: 6)
        #expect(night.contains(Self.at(23), calendar: Self.calendar))
        #expect(night.contains(Self.at(2), calendar: Self.calendar))
        #expect(!night.contains(Self.at(12), calendar: Self.calendar))
        #expect(PrimerHours(start: 9, end: 9).contains(Self.at(3), calendar: Self.calendar))
    }

    @Test("Outside the hours, the next start is when they open, today or tomorrow")
    func nextStart() {
        let day = PrimerHours(start: 7, end: 23)
        #expect(day.next(after: Self.at(3), calendar: Self.calendar) == Self.at(7))
        #expect(day.next(after: Self.at(23, 30), calendar: Self.calendar) == Self.at(7, day: 2))
        #expect(day.next(after: Self.at(12), calendar: Self.calendar) == Self.at(12))
    }

    // MARK: When

    @Test("Due once the reset and its grace have passed, inside the hours")
    func dueAfterReset() {
        let hours = PrimerHours(start: 7, end: 23)
        let reset = Self.at(10)
        #expect(!WindowPrimer.isDue(reset: reset, current: nil, now: Self.at(10, 0), hours: hours, calendar: Self.calendar))
        #expect(WindowPrimer.isDue(reset: reset, current: nil, now: Self.at(10, 2), hours: hours, calendar: Self.calendar))
        #expect(!WindowPrimer.isDue(reset: nil, current: nil, now: Self.at(10, 2), hours: hours, calendar: Self.calendar))
    }

    @Test("Not due outside the hours")
    func notDueAtNight() {
        let hours = PrimerHours(start: 7, end: 23)
        #expect(!WindowPrimer.isDue(reset: Self.at(1), current: nil, now: Self.at(2), hours: hours, calendar: Self.calendar))
    }

    @Test("Not due when a reading since shows a later reset: it has been used")
    func notDueWhenAlreadyStarted() {
        let hours = PrimerHours(start: 7, end: 23)
        let reset = Self.at(10)
        let restarted = window(.fiveHour, resets: Self.at(15, 30))
        #expect(!WindowPrimer.isDue(reset: reset, current: restarted, now: Self.at(11), hours: hours, calendar: Self.calendar))
        // The same reset, still reported, is not a restart.
        let stale = window(.fiveHour, resets: reset)
        #expect(WindowPrimer.isDue(reset: reset, current: stale, now: Self.at(11), hours: hours, calendar: Self.calendar))
    }

    // MARK: Which

    @Test("Claude Code's five hours only; Codex's five hours and week; nothing scoped or inferred")
    func eligibility() {
        #expect(WindowPrimer.eligible(window(.fiveHour, resets: nil), of: .claudeCode))
        #expect(!WindowPrimer.eligible(window(.weekly, resets: nil), of: .claudeCode))
        #expect(WindowPrimer.eligible(window(.fiveHour, resets: nil), of: .codex))
        #expect(WindowPrimer.eligible(window(.weekly, resets: nil), of: .codex))
        #expect(!WindowPrimer.eligible(window(.weekly, resets: nil, scope: "Spark"), of: .codex))
        #expect(!WindowPrimer.eligible(window(.fiveHour, resets: nil), of: .cursor))
    }

    // MARK: What is sent

    @Test("Claude is asked with Haiku, no tools, no MCP, no user settings, nothing saved")
    func claudeArguments() {
        let arguments = WindowStarter.claudeArguments()
        #expect(arguments.starts(with: ["-p", "hi"]))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "--model" && $1 == "haiku" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "--tools" && $1 == "" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "--setting-sources" && $1 == "project" })
        #expect(arguments.contains("--strict-mcp-config"))
    }

    @Test("Codex is asked ephemerally, read-only, at low effort, with the model when one was found")
    func codexArguments() {
        let folder = URL(fileURLWithPath: "/tmp/starter")
        let arguments = WindowStarter.codexArguments(model: "gpt-5.6-luna", folder: folder)
        #expect(arguments.first == "exec")
        #expect(arguments.last == "hi")
        #expect(arguments.contains("--ephemeral"))
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-m" && $1 == "gpt-5.6-luna" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-s" && $1 == "read-only" })
        #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-C" && $1 == "/tmp/starter" })
        #expect(!WindowStarter.codexArguments(model: nil, folder: folder).contains("-m"))
    }

    @Test("The cheapest Codex model: Luna by name, else one described as fast, else none")
    func cheapestModel() {
        func reply(_ models: [[String: Any]]) -> Data {
            try! JSONSerialization.data(withJSONObject: ["data": models])
        }
        let current = reply([
            ["id": "gpt-5.6-sol", "description": "Older coding model for complex work."],
            ["id": "gpt-5.6-luna", "description": "Older fast and efficient model."],
            ["id": "gpt-5.6-terra", "description": "Older balanced model."],
        ])
        #expect(WindowStarter.cheapestCodexModel(in: current) == "gpt-5.6-luna")
        let renamed = reply([
            ["id": "gpt-7-big", "description": "Frontier model."],
            ["id": "gpt-7-swift", "description": "Fast and cheap."],
        ])
        #expect(WindowStarter.cheapestCodexModel(in: renamed) == "gpt-7-swift")
        let hidden = reply([["id": "gpt-5.6-luna", "hidden": true, "description": "fast"]])
        #expect(WindowStarter.cheapestCodexModel(in: hidden) == nil)
        #expect(WindowStarter.cheapestCodexModel(in: reply([["id": "only", "description": "A model."]])) == nil)
        #expect(WindowStarter.cheapestCodexModel(in: Data("nope".utf8)) == nil)
    }

    @Test("Claude is looked for on PATH, then its own installer's folder, then the usual places")
    func claudeLocator() {
        let listed = CommandLocator.candidates(
            "claude", home: "/Users/me", path: "/usr/bin",
            extra: ["/Users/me/.claude/local/claude"],
            versions: { $0.hasSuffix(".nvm/versions/node") ? ["v20.0.0", "v24.1.0"] : [] }
        )
        #expect(Array(listed.prefix(3)) == ["/usr/bin/claude", "/Users/me/.claude/local/claude", "/opt/homebrew/bin/claude"])
        #expect(listed.contains("/Users/me/.local/bin/claude"))
        #expect(listed.filter { $0.contains(".nvm") } == [
            "/Users/me/.nvm/versions/node/v24.1.0/bin/claude", "/Users/me/.nvm/versions/node/v20.0.0/bin/claude",
        ])
    }

    @Test("Claude's project folder for the starter's directory is named the way Claude names it")
    func claudeProjectFolderName() {
        let folder = URL(fileURLWithPath: "/Users/me/Library/Application Support/Pulse/Window starter")
        #expect(WindowStarter.claudeProjectFolder(for: folder, home: "/Users/me").path
            == "/Users/me/.claude/projects/-Users-me-Library-Application-Support-Pulse-Window-starter")
    }
}

