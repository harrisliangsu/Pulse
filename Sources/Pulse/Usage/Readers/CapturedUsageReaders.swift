// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The Group E agents, read **only** from a local export, cache or capture.
///
/// None of these six products writes an unauthenticated native usage log that
/// Pulse can read on its own. Each one depends on a prior step performed by a
/// different tool, and that prerequisite is a hard condition — with no export
/// there is simply nothing to read:
///
/// - `cursor` reads the Cursor usage cache (dashboard export) and its legacy
///   CSVs.
/// - `antigravity` reads the Antigravity IDE language-server cache as JSONL.
///   This is **not** `antigravity-cli`, a different product with its own
///   on-disk conversations.
/// - `trae` reads a dump of the Trae usage API (a JSON array).
/// - `warp` reads a synced account snapshot that carries requests and money but
///   **no tokens at all**.
/// - `hindsight` reads a JSONL ledger mirrored out of a self-hosted service.
/// - `mcode` reads a captured `mcode exec --output-format stream-json` stream
///   — and, unlike the rest, MiniMax Code's own session log too, which the
///   desktop app now writes as it runs (`MiniMaxCodeSessionReader`). Where that
///   log has records, it is the reading and captures are left unread: the
///   same work in both would otherwise count twice, and the two do not share
///   an id to fold one into the other.
///
/// Pulse itself does not log in, capture a cookie, call a language server or
/// sync anything. `inputs` names the standard cache/capture location plus
/// Pulse's own drop folder, `UsageImports/<client>`; the readers only ever read
/// what is already there. Nothing here creates, copies or runs a program.
enum CapturedUsageReaders {
    /// Every client this family answers for. The catalog dispatch test walks
    /// this set and expects an input root and a record reader for each.
    static let supportedClients: Set<String> = [
        "cursor",
        "antigravity",
        "trae",
        "warp",
        "hindsight",
        "mcode",
    ]

    /// Every root this client is read from.
    ///
    /// A root names a directory even when it does not exist yet: it is part of
    /// the store's identity, so a file dropped into Pulse's import folder later
    /// moves the store's stamp and is noticed. Reading a missing root yields no
    /// records, never a fabricated one.
    static func inputs(client: String, home: URL, environment: [String: String]) -> [URL] {
        let cache = cacheRoot(home: home, environment: environment)
        let imported = importRoot(home: home, client: client)

        return switch client {
        case "cursor": [cache.appending(path: "cursor-cache"), imported]
        case "antigravity": [cache.appending(path: "antigravity-cache/sessions"), imported]
        case "trae": [cache.appending(path: "trae-cache/sessions"), imported]
        case "warp": [cache.appending(path: "warp-cache"), imported]
        case "hindsight": [hindsightRoot(home: home, environment: environment), imported]
        case "mcode": [MiniMaxCodeSessionReader.root(home: home), cache.appending(path: "headless/mcode"), imported]
        default: []
        }
    }

    /// Records decoded from the files under `roots`, ready for
    /// `AgentUsageLedger.build`. The caller owns the ledger's origin; a record
    /// here carries only what the store actually said.
    static func records(client: String, roots: [URL]) -> [AgentUsageRecord] {
        switch client {
        case "cursor": CapturedCursorReader.records(roots: roots)
        case "antigravity": CapturedAntigravityReader.records(roots: roots)
        case "trae": CapturedTraeReader.records(roots: roots)
        case "warp": CapturedWarpReader.records(roots: roots)
        case "hindsight": CapturedHindsightReader.records(roots: roots)
        case "mcode": mcodeRecords(roots: roots)
        default: []
        }
    }

    /// MiniMax Code's own log where it has records, else the captures — and
    /// which of the two it was. **One read decides both**: the origin once
    /// asked only whether the log had files, so a log of nothing but zeroed
    /// migration lines sent the read to the captures while the ledger still
    /// called them this Mac's own transcripts.
    static func mcodeRead(roots: [URL]) -> (records: [AgentUsageRecord], ownLog: Bool) {
        let logged = MiniMaxCodeSessionReader.records(roots: roots.filter(isMiniMaxCodeLog))
        if !logged.isEmpty { return (logged, true) }
        return (CapturedMcodeReader.records(roots: roots.filter { !isMiniMaxCodeLog($0) }), false)
    }

    private static func mcodeRecords(roots: [URL]) -> [AgentUsageRecord] {
        mcodeRead(roots: roots).records
    }

    private static func isMiniMaxCodeLog(_ root: URL) -> Bool {
        root.standardizedFileURL.path.hasSuffix("/.minimax/v2/sessions")
    }

    /// Whether a read of these roots is a product's own log rather than an
    /// export or capture: MiniMax Code's, when its session log yields records
    /// (`mcodeRead`). The ledger takes it from the read itself
    /// (`AgentRecordReaders.Read.readsOwnLog`); this asks again, for a caller
    /// with no read in hand.
    static func readsOwnLog(client: String, roots: [URL]) -> Bool {
        client == "mcode" && mcodeRead(roots: roots).ownLog
    }

    // MARK: - Roots

    /// Where the synced caches live. `TOKSCALE_CONFIG_DIR` is honoured because
    /// that is the tree the shared cache format defines; otherwise it sits at
    /// `~/.config/tokscale`. Pulse reads it, never writes it.
    static func cacheRoot(home: URL, environment: [String: String]) -> URL {
        if let custom = environment["TOKSCALE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return home.appending(path: ".config/tokscale")
    }

    /// Where the Hindsight ledger mirror lives. `HINDSIGHT_HOME` overrides the
    /// `~/.hindsight` default; the ledger itself is in its `usage/` subfolder.
    static func hindsightRoot(home: URL, environment: [String: String]) -> URL {
        if let custom = environment["HINDSIGHT_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true).appending(path: "usage")
        }
        return home.appending(path: ".hindsight/usage")
    }

    /// Pulse's own drop folder for a client's export. Nothing is created here;
    /// it is read only when the user has put a file in it.
    static func importRoot(home: URL, client: String) -> URL {
        home.appending(path: "Library/Application Support/Pulse/UsageImports/\(client)")
    }
}
