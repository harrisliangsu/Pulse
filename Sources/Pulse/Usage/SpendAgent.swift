import Foundation

/// A coding agent that leaves a record of its work on this Mac.
///
/// **Not a `Provider`, deliberately.** A provider is something Pulse can draw a
/// ring for: it reports a quota, it has a pane, it can be signed in to. An
/// agent is something that has *spent* tokens here. The two overlap and are
/// not the same list — Kimi's CLI and Kilo keep transcripts and sell no plan
/// Pulse watches, while Cursor and Copilot report quota and leave nothing here
/// to read. Folding these into `Provider` would put four rings on the rail for
/// products nobody can check a limit for.
///
/// **Only agents whose store was read on a real machine are here.** tokscale
/// lists about fifty; forty of them are not installed on any machine this was
/// written against, and a transcript format guessed from someone else's parser
/// fails silently — it does not error, it produces a wrong number that nobody
/// can see is wrong. The rest are recorded in
/// [Docs/token-spend.md](../../Docs/token-spend.md) as paths to read when
/// somebody has one.
///
/// **Kimi Code is not here, and it is installed.** Its session state carries a
/// title, an agent and a first-token latency, and no token counts anywhere —
/// so there is nothing to add up. An agent that can only ever report zero is
/// worse than an absent one: the zero looks like a reading.
enum SpendAgent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case openCode
    case kiloCLI
    case grok
    case kimiCLI
    case devinCLI

    var id: String { rawValue }

    /// Product names, left untranslated.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        // A fork of OpenCode, down to the database schema — which is why one
        // reader serves both.
        case .kiloCLI: "Kilo CLI"
        case .grok: "Grok Build"
        case .kimiCLI: "Kimi CLI"
        case .devinCLI: "Devin CLI"
        }
    }

    /// The provider whose mark this agent is recognised by, where Pulse
    /// carries one. Nil where the agent is not a provider at all and there is
    /// no mark to borrow.
    var iconProvider: Provider? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .openCode: .openCodeGo
        case .kiloCLI: nil
        case .grok: .grok
        case .kimiCLI: .kimiCode
        case .devinCLI: .devin
        }
    }

    /// Whether its history comes from `UsageLedgerReader`, which already reads
    /// these two for the per-provider card.
    var provider: Provider? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        default: nil
        }
    }

    private static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    /// The file or directory this agent's work is read from, if it has one
    /// here. Nil means nothing to read — which is the ordinary case for most
    /// agents on most machines.
    var store: URL? {
        let url: URL? = switch self {
        case .claudeCode: Self.home.appending(path: ".claude/projects")
        case .codex: Self.home.appending(path: ".codex/sessions")
        case .openCode: Self.home.appending(path: ".local/share/opencode/opencode.db")
        case .kiloCLI: Self.home.appending(path: ".local/share/kilo/kilo.db")
        case .grok: Self.home.appending(path: ".grok/sessions")
        case .kimiCLI: Self.home.appending(path: ".kimi/sessions")
        case .devinCLI: Self.home.appending(path: ".local/share/devin/cli/sessions.db")
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The agents with something to read here. Everything downstream works
    /// from this rather than from `allCases`, so a machine with two agents on
    /// it never sees a row for the other six.
    static var present: [SpendAgent] { allCases.filter { $0.store != nil } }
}
