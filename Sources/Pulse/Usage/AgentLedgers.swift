import Foundation

/// One ledger per agent, however that agent keeps its records.
///
/// `UsageLedgerReader` reads the two CLIs that write JSONL transcripts and is
/// keyed by `Provider`, because what it was built for is the per-provider
/// history card. This is the other axis: every agent that has spent tokens on
/// this Mac, whether or not Pulse draws a ring for it.
///
/// **The two it already reads are delegated, not re-read.** Claude Code and
/// Codex go through the same reader and the same cache as before. The five
/// other legacy agents keep their own store readers (`OpenCodeStore`,
/// `GrokStore`, `KimiCLIStore`, `DevinCLIStore`). Everything added since is
/// handed to `AgentRecordReaders` and built by `AgentUsageLedger.build`, so
/// there is one pricing path for all of them. Devin Desktop additionally
/// receives the native databases being counted, to exclude matched mirrors.
///
/// **An agent can have more than one root.** Its inputs are resolved to the
/// ones that exist, the cache stamp is taken over that whole set, and the set
/// is resolved *again* after the read: a root appended to — or one that
/// disappeared — while Pulse was reading produces a ledger the before stamp no
/// longer describes, so it is kept for this process only and never written as
/// a stable disk cache.
///
/// **A partially decoded read is never a stable cache.** A reader can meet
/// history it cannot decode — a compressed transcript, say — and return fewer
/// records than the store holds. That ledger is still shown, but it is not
/// written to disk: a later build that *can* decode the same, unchanged files
/// would otherwise be blocked by the old partial cache. Only a read that had
/// no such limit and left the stores where it found them is persisted.
actor AgentLedgers {
    static let shared = AgentLedgers()

    private var cached: [SpendAgent: UsageLedger] = [:]

    /// What each agent's stores really looked like when it was last read, so a
    /// relaunch does not repeat the work.
    ///
    /// **The in-memory cache is not enough.** It answers for the life of the
    /// process; the page is opened once a day for a minute, and a cold read of
    /// a ten-thousand-row database is the whole of that minute. The stamp is
    /// computed from the store's own inputs — see `AgentCache.Stamp` for why
    /// the store's size and date are not one of them.
    private var stamps: [SpendAgent: AgentCache.Stamp] = [:]

    /// Reader limits met by the last read of each agent, kept so the UI can
    /// state them without re-opening — and re-decompressing — the stores.
    ///
    /// A partial read stays here with its in-memory ledger until a refresh
    /// reads again; a valid disk-cache hit clears the entry, because a cache
    /// written from a complete read has nothing to report.
    private var notesByAgent: [SpendAgent: [String]] = [:]

    func ledgers(refresh: Bool = false) async -> [SpendAgent: UsageLedger] {
        var all: [SpendAgent: UsageLedger] = [:]

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let environment = ProcessInfo.processInfo.environment
        let prices = await ModelPrices.shared.prices()

        for agent in SpendAgent.present(home: home, environment: environment) {
            if !refresh, let known = cached[agent] {
                // Its notes, if any, belong to this same in-memory read and
                // stay beside it.
                all[agent] = known
                continue
            }

            let ledger: UsageLedger
            if let provider = agent.provider {
                // Its own cache, its own file, unchanged.
                ledger = await UsageLedgerReader.shared.ledger(for: provider, refresh: refresh)
                notesByAgent[agent] = nil
            } else {
                let before = Self.stamp(agent, home: home, environment: environment, prices: prices)

                if !refresh, let before, let saved = AgentCache.load(agent), saved.stamp == before {
                    // **A valid cache is a complete read, and is not
                    // re-decoded.** It was only ever written when the reader
                    // had no limit to report, so it neither re-opens the store
                    // nor claims a new failure. Nothing to say about it.
                    ledger = saved.ledger
                    notesByAgent[agent] = nil
                } else {
                    let outcome = Self.read(agent, prices: prices, home: home, environment: environment)
                    ledger = outcome.ledger
                    // Kept whether or not it is cached: the UI must be able to
                    // say what could not be read.
                    notesByAgent[agent] = outcome.notes.isEmpty ? nil : outcome.notes

                    // **Confirm the read left the stores where it found them**,
                    // and that nothing could not be decoded. A root appended to
                    // while Pulse was reading it, a root that appeared or was
                    // removed, or a compressed transcript this build could not
                    // open, all produce a ledger that is not the whole and must
                    // not be frozen as one — no retry loop, just an honest miss
                    // next time.
                    let after = Self.stamp(agent, home: home, environment: environment, prices: prices)
                    if Self.canPersist(notes: outcome.notes, before: before, after: after),
                       let before {
                        AgentCache.save(ledger, stamp: before, for: agent)
                    }
                }
                stamps[agent] = before
            }

            cached[agent] = ledger
            all[agent] = ledger
        }

        return all
    }

    /// Whether a read may be written to the disk cache.
    ///
    /// Three conditions, and all three are required: the reader reported no
    /// limit (a partial ledger would hide history a fixed reader could later
    /// recover), the stores existed before the read, and they are unchanged
    /// after it. Kept as a pure rule so the guard itself is testable without an
    /// actor or a store.
    static func canPersist(
        notes: [String],
        before: AgentCache.Stamp?,
        after: AgentCache.Stamp?
    ) -> Bool {
        guard notes.isEmpty, let before, let after else { return false }
        return after == before
    }

    /// The reader limits from this process's reads, per agent.
    ///
    /// **It does not rescan anything.** The limits were found while the ledgers
    /// were read and are returned as they stand, so opening the pane again does
    /// not re-open a store or re-decompress it. A source that has since been
    /// removed is dropped, so a stale note never outlives its store.
    func readNotes() -> [SpendAgent: [String]] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let environment = ProcessInfo.processInfo.environment
        let present = Set(SpendAgent.present(home: home, environment: environment))
        notesByAgent = notesByAgent.filter { present.contains($0.key) }
        return notesByAgent
    }

    /// The stamp for an agent's existing roots, or nil when it has none.
    private static func stamp(
        _ agent: SpendAgent,
        home: URL,
        environment: [String: String],
        prices: [String: ModelPrice]
    ) -> AgentCache.Stamp? {
        let stores = agent.stores(home: home, environment: environment)
        guard !stores.isEmpty else { return nil }
        return AgentCache.stamp(for: stores, prices: prices)
    }

    /// One agent's read: the ledger it produced, and any limit the reader met.
    struct ReadResult {
        let ledger: UsageLedger
        let notes: [String]
    }

    // Internal so fixture tests exercise the production dispatch, including
    // which plan vendor each agent passes to its shared store reader.
    static func read(
        _ agent: SpendAgent,
        prices: [String: ModelPrice],
        home: URL,
        environment: [String: String]
    ) -> ReadResult {
        let stores = agent.stores(home: home, environment: environment)

        switch agent {
        // The legacy store readers, each with the one store it was built for,
        // and no reader-level limits to report.
        case .openCode, .kiloCLI:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(
                ledger: OpenCodeStore.ledger(at: store, prices: prices, vendor: agent.priceVendor), notes: []
            )
        case .grok:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(ledger: GrokStore.ledger(at: store, prices: prices), notes: [])
        case .kimiCLI:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(ledger: KimiCLIStore.ledger(at: store, prices: prices), notes: [])
        case .devinCLI:
            guard let store = stores.first else { return ReadResult(ledger: .empty, notes: []) }
            return ReadResult(ledger: DevinCLIStore.ledger(at: store, prices: prices), notes: [])
        case .devinDesktop:
            let records = DevinDesktopReader.records(
                roots: stores,
                authoritativeDatabases: SpendAgent.devinCLI.stores(home: home, environment: environment)
            )
            return ReadResult(
                ledger: AgentUsageLedger.build(records, prices: prices, namespace: agent.rawValue), notes: []
            )
        // Read by `UsageLedgerReader`, and never routed here.
        case .claudeCode, .codex:
            return ReadResult(ledger: .empty, notes: [])
        // Every catalog client, from its family's normalized records.
        default:
            guard !stores.isEmpty else { return ReadResult(ledger: .empty, notes: []) }
            let records = AgentRecordReaders.records(client: agent.sourceID, roots: stores)
            let ledger = AgentUsageLedger.build(
                records,
                prices: prices,
                namespace: agent.rawValue,
                vendor: agent.priceVendor,
                // An export or capture is the account's movement, not
                // necessarily this Mac's own transcript; it can still be
                // priced, but it is not claimed as a local transcript.
                origin: agent.requiresUsageExport ? .importedRecords : .localTranscripts
            )
            // A source that reports no token counters has nothing to be a
            // *partial* read of; its note is a permanent "no counters" string
            // and is left to the zero-record list instead. Only a source that
            // does report counts can have a decode limit worth stating.
            let notes = agent.reportsTokenCounts
                ? AgentRecordReaders.notes(client: agent.sourceID, roots: stores)
                : []
            return ReadResult(ledger: ledger, notes: notes)
        }
    }
}
