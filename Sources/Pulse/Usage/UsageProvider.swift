import Foundation

/// The coding agents Pulse tracks.
///
/// Each reports its own usage, by routes that have almost nothing in common —
/// see `ClaudeCodeUsageService`, `CodexUsageService`, `AntigravityUsageService`,
/// `CursorUsageService` and the two key-based ones.
enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claudeCode
    case codex
    case kiro
    case antigravity
    case cursor
    case openCodeGo
    case kimiCode
    case ollamaCloud
    case zai
    case glmCoding
    case minimax
    case minimaxCN
    case copilot
    case grok
    case grokBot
    case volcengine
    case qoder
    case commandCode
    case deepSeek
    case devin
    case xiaomiMiMo
    case sub2api
    case newAPI
    case v2ex

    var id: String { rawValue }

    /// When set, the rail's automatic ring follows this window rather than
    /// whichever is fullest. Cursor's "Other Models" is a small overflow
    /// pool: as a percentage it looks spent long before Composer does.
    var preferredHeadlineWindowID: String? {
        switch self {
        case .cursor: "cursorModels"
        default: nil
        }
    }

    /// Product names, left untranslated.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .kiro: "Kiro"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .openCodeGo: "OpenCode Go"
        case .kimiCode: "Kimi Code"
        case .ollamaCloud: "Ollama Cloud"
        // Two entries rather than one with a region switch, because they are
        // two accounts on two services: a key for one is refused by the other,
        // and plenty of people have only one of them.
        // **Named for the two shops, not for the product.** Both sell the
        // same thing under the same name — "GLM Coding Plan" — so a row
        // called that is a row half the buyers will pick wrongly: an
        // international subscriber chose it, pasted a z.ai key, and had it
        // sent to the mainland service, which refused it (issue #13). The
        // company is the one thing that differs and the one thing a buyer
        // knows, so it is the whole name.
        case .zai: "z.ai"
        case .glmCoding: "Zhipu"
        // Same product, two storefronts and two accounts. There is no separate
        // brand name for the mainland one, so the region is the distinction.
        case .minimax: "MiniMax"
        case .minimaxCN: "MiniMax CN"
        case .copilot: "GitHub Copilot"
        // The account's pool is spent across every Grok product, not just
        // Grok Build's CLI, so the ring is about the account and the name
        // says so. See `GrokUsageService`.
        case .grok: "Grok"
        // xAI's, sold through Cursor and billed against that account — a
        // different bill from the SuperGrok pool above, under a name people
        // already use for it. See `GrokBotUsageService`.
        case .grokBot: "Grok Bot"
        // The official name. Volcengine is the platform, Ark (方舟) the model
        // service on it, and Doubao the model — the plan is sold as the Ark
        // Coding Plan, and the account, the keys and the CLI are all
        // Volcengine's. Naming it for the model would name the one part of
        // that chain the ring is not about.
        case .volcengine: "Volcengine"
        // One entry for both sites. Unlike MiniMax's two storefronts, these
        // are one product under one name; the site is a setting (`QoderSite`).
        case .qoder: "Qoder"
        // The product's own name. Its command is `cmd`, which names nothing on
        // a rail of brands and collides with the key on every Mac keyboard.
        case .commandCode: "Command Code"
        // The shop, not the model family: the balance belongs to the account
        // and is spent across whatever the key is pointed at.
        case .deepSeek: "DeepSeek"
        // Cognition's agent. The Mac app is the renamed Windsurf editor and
        // still identifies itself as `com.exafunction.windsurf`, but the plan,
        // the quota and the account are Devin's, and Devin is what the reader
        // subscribed to.
        case .devin: "Devin"
        // The plan, not the platform. Xiaomi's open platform sells inference
        // by the yuan to anyone with a key; this ring is about the monthly
        // token allowance bought on top of that, which is the thing with a
        // denominator and the thing the buyer signed up for. "Xiaomi MiMo"
        // would name the platform and leave the two products sharing a row.
        case .xiaomiMiMo: "Xiaomi Coding Plan"
        // The gateway's own name, lower case, as the project writes it. Not
        // "Relay" or "中转站": those name the *kind* of thing, which would be
        // the one row a second gateway could not be added beside — and the
        // rule here is that a ring is named for the product behind it.
        // The operator of somebody's deployment may never have said what it
        // runs; the reply's own field names are what identify it.
        case .sub2api: "sub2api"
        // The project's own name, spaced as its README writes it. Not
        // "NewAPI" and not "new-api", which are the repository and the Docker
        // image rather than what the thing is called.
        case .newAPI: "New API"
        // The site, not "AI Chat". The allowance is granted to the V2EX
        // account and sized from what that account has done there — years of
        // top-ups, and a Solana balance — so it belongs to the membership
        // rather than to a product bought separately.
        case .v2ex: "V2EX"
        }
    }

    /// The parent brand's mark rather than the CLI-specific one — these read
    /// better at ring size and are what people recognise.
    var iconResource: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "openai"
        case .kiro: "kiro"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .openCodeGo: "opencode"
        case .kimiCode: "kimi"
        case .ollamaCloud: "ollama"
        // One mark for both storefronts, the way MiniMax's two rows share
        // theirs. The rail stops distinguishing them: the ring names do it,
        // and those are only read on the card. Deliberate — a rail carrying
        // both rows shows one mark twice.
        case .zai, .glmCoding: "zai"
        // One mark for both, since there is only one brand. Two accounts of one
        // provider already share a mark on the rail; this is the same case.
        case .minimax, .minimaxCN: "minimax"
        case .copilot: "github"
        case .grok: "grok"
        // The parent brand's mark rather than Grok's own, which is the one
        // thing that tells the two apart on a rail carrying both.
        case .grokBot: "xai"
        case .volcengine: "volcengine"
        case .qoder: "qoder"
        // The command-key glyph from its own editor extension, rather than the
        // wordmark the site leads with: at ring size a wordmark is a grey
        // smudge, and this is the mark the product is recognised by anyway.
        case .commandCode: "commandcode"
        case .deepSeek: "deepseek"
        case .devin: "devin"
        // Xiaomi publishes no symbol for MiMo — the mark is a two-line
        // "Xiaomi / MiMo" lockup and that is what the console's own favicon
        // is. Shipped as it stands rather than cropped to something Xiaomi
        // does not use; at ring size it reads as a shape rather than as words,
        // which is the trade for being the real mark.
        case .xiaomiMiMo: "xiaomimimo"
        // The interlocking mark from the project's own logo, without the
        // badge it is drawn on: a rounded square goes grey at ring size and
        // the rail already sets every mark on the same ground.
        case .sub2api: "sub2api"
        // **The brand mark, not the one in New API's own web UI.** That one
        // is the command-key glyph, which is exactly what Command Code's mark
        // already is — two rings a reader could not tell apart, which is the
        // one thing a rail of logos must not do. This is the project's own
        // logo reduced to a monochrome outline: two crescents and the spark
        // between them.
        case .newAPI: "newapi"
        case .v2ex: "v2ex"
        }
    }

    /// Whether this agent leaves transcripts on disk that Pulse can read.
    ///
    /// The two CLIs write one JSONL file per session, carrying both the token
    /// counts every local spend figure is built from. This is intentionally
    /// narrower than `supportsLocalActivity`: lifecycle-only records can drive
    /// an honest activity mark without being usable for a cost estimate.
    var keepsLocalTranscripts: Bool {
        switch self {
        case .claudeCode, .codex: true
        // Antigravity is an editor and keeps nothing. OpenCode *does* keep
        // sessions with token counts — `opencode stats` adds them up — but in
        // its own store rather than the JSONL both CLIs above write, so the
        // ledger cannot read it yet. False here means "no history shown",
        // which is true today and better than a column of zeroes.
        case .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .volcengine, .commandCode, .deepSeek, .devin, .xiaomiMiMo, .sub2api,
             .newAPI, .v2ex, .qoder: false
        }
    }

    /// Whether Pulse can determine that this provider's local agent is in the
    /// middle of a turn. This is deliberately separate from
    /// `keepsLocalTranscripts`: Kiro and ZCode leave enough lifecycle records
    /// for an activity mark, but not the token buckets the spend ledger needs.
    var supportsLocalActivity: Bool {
        switch self {
        case .claudeCode, .codex, .kiro, .zai, .glmCoding: true
        case .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .minimax, .minimaxCN, .copilot, .grok, .grokBot, .volcengine,
             .commandCode, .deepSeek, .devin, .xiaomiMiMo,
             .sub2api, .newAPI, .v2ex, .qoder: false
        }
    }

    /// Whether this provider's limits can be drawn as one ring per model
    /// group.
    ///
    /// Antigravity alone: its plan carries a Gemini allowance and a separate
    /// one for Claude and GPT, reported as two `scope`s of one login. They are
    /// independent budgets — spending one says nothing about the other — so a
    /// single ring can only show the worse of the two and silently drop the
    /// other. Every other provider reports one pool, or several that are
    /// facets of one.
    var splitsByModelGroup: Bool { self == .antigravity }

    /// How many rings a split account can produce. Fixed rather than counted
    /// from a reading, so the rail's own budget does not move when a provider
    /// answers with one group short.
    var modelGroupCount: Int { splitsByModelGroup ? 2 : 1 }

    /// Whether a spending history can be shown for this provider at all.
    ///
    /// **Not the same question as `keepsLocalTranscripts`**, which it used to
    /// be. Two different sources answer it: the CLIs leave session files on
    /// this Mac, and Z.ai and Zhipu publish the account's own statistics — the
    /// endpoint their console draws its charts from. The second is the better
    /// data (it covers every machine) and the poorer (one token total per
    /// model, so nothing can be priced), which is what `UsageLedger.Origin`
    /// exists to keep straight.
    var providesHistory: Bool { keepsLocalTranscripts || self == .zai || self == .glmCoding }

    /// Whether the route to this provider's figures is a choice.
    ///
    /// The two CLIs can each be read two ways, which is a setting. Antigravity
    /// and Cursor have exactly one route each — a server one of them runs
    /// itself, a login the other one stored — so it is stated rather than
    /// offered.
    /// **Not `keepsLocalTranscripts`**, which it used to be. The two happened
    /// to agree while only the CLIs had a choice, and reading one for the other
    /// is the kind of coincidence that breaks silently: Volcengine has two routes
    /// and no transcripts, and would have been given a stated route it does not
    /// have instead of the picker it needs.
    var hasSourceChoice: Bool {
        switch self {
        case .claudeCode, .codex, .volcengine, .kimiCode, .devin: true
        case .kiro, .antigravity, .cursor, .openCodeGo, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .commandCode, .deepSeek, .xiaomiMiMo, .sub2api, .newAPI, .v2ex, .qoder: false
        }
    }

    /// The one route this provider has, named for the settings row that
    /// states it rather than offering a picker. Nil where the row is never
    /// drawn — a provider with a choice of routes, or one whose credential is
    /// a key the user pastes.
    ///
    /// **Exhaustive on purpose.** This was a ternary in `SettingsView` that
    /// named Cursor's route and let *everything else* fall through to
    /// Antigravity's words, so Grok's pane read "Antigravity's language
    /// server · Only while Antigravity is open." — about a route it does not
    /// have and an app it has nothing to do with. A switch here means the next
    /// provider added cannot inherit somebody else's sentence in silence.
    var soleRoute: (name: String, note: String)? {
        switch self {
        case .antigravity:
            (String.localized("Antigravity's language server"),
             String.localized("Only while Antigravity is open."))
        case .cursor:
            (String.localized("Cursor's own login"),
             String.localized("Uses the login Cursor already saved."))
        case .grok:
            (String.localized("Grok's own login"),
             String.localized("Uses the login Grok's CLI already saved."))
        // The credential really is Cursor's: Grok Bot is billed against that
        // account, so this names where the login comes from rather than the
        // product it reports on.
        case .grokBot:
            (String.localized("Cursor's own login"),
             String.localized("Grok Bot is billed to your Cursor account."))
        case .kiro:
            (String.localized("Kiro CLI ACP"),
             String.localized("Uses Kiro CLI's signed-in session without reading its credentials."))
        // Either a choice of routes, or a key the user pastes: both are asked
        // about elsewhere, so there is nothing here to state.
        case .claudeCode, .codex, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .volcengine,
             .commandCode, .deepSeek, .devin, .xiaomiMiMo, .sub2api, .newAPI, .v2ex, .qoder:
            nil
        }
    }

    /// Whether Pulse needs an API key from the user for this one.
    ///
    /// The others borrow a login their own CLI stored. OpenCode stores one too,
    /// and that is the route taken first — but a key can also be pasted in for
    /// anyone on the plan who doesn't run the CLI on this Mac.
    var usesAPIKey: Bool {
        [.openCodeGo, .kimiCode, .ollamaCloud, .zai, .glmCoding, .minimax, .minimaxCN, .volcengine,
         .commandCode, .deepSeek, .devin, .xiaomiMiMo, .sub2api, .newAPI,
         .v2ex, .qoder].contains(self)
    }

    /// Whether this Mac can see the thing this provider is billing for.
    ///
    /// True for the agents that write transcripts here, and true enough for a
    /// subscription whose window turns over on a clock. False for credit spent
    /// through an API on somebody else's servers: nothing local moves when it
    /// drains, so `AdaptiveRefresh`'s signals are blind to it and it would sit
    /// on the ceiling for ever. See `AdaptiveRefresh.unwatchedCeiling`.
    var spendingIsWatchedLocally: Bool {
        // Money spent through an API on somebody else's servers: the shape
        // this rule was written for.
        if reportsSpendableBalance { return false }
        // **V2EX is the exception the money test cannot see.** Its allowance
        // is counted in tokens rather than in currency, so the test above says
        // nothing about it — and it is spent in a browser on v2ex.com, which
        // moves nothing on this Mac. Its window does not even turn over on a
        // clock: V2EX starts one when a message arrives *there*. So neither
        // half of "watched" holds, and inheriting `true` from a test about
        // currency would leave it half an hour behind a window it never saw
        // start. See `AdaptiveRefresh.unwatchedCeiling`.
        return self != .v2ex
    }

    /// Whether this provider reports a prepaid balance that can be compared
    /// against a figure — so a "warn me below" line is worth offering.
    ///
    /// **Not "reports a `creditBalance`".** Six providers set that, but it is
    /// a display string and Codex's is sometimes the word "Unlimited". This is
    /// the shorter list that also hands over `creditRemaining`, which is a
    /// number and a currency.
    /// sub2api joins them for its wallet groups, which are the same thing
    /// under another name: money in an account, spent by the call, with no
    /// allowance behind it. Its quota and subscription groups report no
    /// wallet, and this asks about the provider rather than about one
    /// reading — a group with no balance simply never hands one over.
    var reportsSpendableBalance: Bool {
        [.deepSeek, .commandCode, .sub2api, .newAPI].contains(self)
    }

    /// Whether this provider is somebody's own deployment, so Pulse has to be
    /// **told where it is** before it can ask anything.
    ///
    /// The only two, and the reason `GatewayAddress` exists: every other
    /// provider here ships its host, while these can be pointed at any machine
    /// on the internet with a credential attached. What Settings draws an
    /// address field for, and what `AppSettings.serverAddress(for:)` is keyed
    /// by.
    var usesServerAddress: Bool { [.sub2api, .newAPI].contains(self) }

    /// Whether the pasted credential is a **pair** rather than one token.
    ///
    /// Volcengine signs with an access key id and a secret, so Volcengine's field
    /// takes `AccessKeyID:SecretAccessKey`. One field rather than two because
    /// the whole store, the whole settings row and the whole "is it set" test
    /// are built around one string per provider — and because it is optional
    /// anyway: `arkcli` is the other route and needs nothing pasted at all.
    var usesKeyPair: Bool { self == .volcengine }

    /// Whether what the user pastes is a browser session rather than an API
    /// key. Ollama has no quota API at all — the figures are read from its
    /// signed-in settings page — so a session is the only credential there is,
    /// and calling it an API key in Settings would send people looking for one
    /// that does not exist.
    /// Xiaomi joins it for the same reason: the platform's API keys buy
    /// inference and answer none of the console's account routes, so the plan
    /// and the balance are behind the web session and nothing else.
    /// Qoder is the third: it publishes no usage API at all, and its account
    /// page reads its credits with the signed-in session.
    var usesSessionCookie: Bool { [.ollamaCloud, .xiaomiMiMo, .qoder].contains(self) }

    /// Whether this provider's credential is read out of a browser rather than
    /// out of another tool's files.
    ///
    /// **Not `usesSessionCookie`**, which is the narrower question of whether
    /// what is read is a *cookie*. Devin's is a `localStorage` entry, which
    /// lives in a different file in a different format and — because it is not
    /// encrypted — needs no keychain permission. Both want the same row in
    /// Settings: which browser, and a button to go and look.
    var readsBrowserStorage: Bool { usesSessionCookie || self == .devin }

    /// Whether Pulse holds a credential of its own for this provider.
    ///
    /// **Not the same question as `usesAPIKey`**, which asks whether the user
    /// pastes one and so decides what Settings draws. Copilot is signed in to
    /// rather than pasted, but its token lives in the same encrypted store —
    /// and reading `usesAPIKey` where the *storage* was meant is what left a
    /// signed-in account reporting "sign in again": the token was saved and
    /// then never loaded back for the fetch.
    var keepsOwnCredential: Bool { usesAPIKey || self == .copilot }
}
