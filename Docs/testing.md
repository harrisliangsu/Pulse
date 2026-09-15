# Testing

Owns: what `swift test` covers, what it deliberately does not, and the two conventions the suite depends on. Toolchain and build flags: [build-from-source.md](build-from-source.md).

```bash
swift test
```

There was no test target until 2026-09-07. What prompted one was not a policy: two real faults were found by reading code in a single afternoon — Antigravity taking the first matching helper and giving up when the one that answers was second, and `.stale` being treated as a failed fetch when a *successful* one produces it too — and the notification rules had shipped with nothing proving them at all.

## What is covered

| Suite | Covers |
|---|---|
| `AlertMemoryTests` | Every notification rule: thresholds, spent, resets, the failure streak, the stale-age gate, and the low-balance line — said once, re-armed by a top-up, said again when the line moves, and never from a stale reading or a balance with no figure behind it. [notifications.md](notifications.md) |
| `AlertsThroughTheCacheTests` | The same rules reached the way production reaches them: service → `UsageCache.reconciled` → state machine |
| `NotificationAuthorizationTests` | An injected authorization decision, concurrent requests, no warning consumed while a grant is pending, and the foreground delegate selector; no system permission or notification delivery |
| `UsageCacheTests` | `reconciled` — fallback, "a reading never goes backwards", credentials that must not be papered over, expiry, and that a live reading carrying a balance and no limits is an **answer** rather than a failure to paper over (DeepSeek's "balance only"), while one carrying nothing at all still is |
| `UsageWindowTests` | The reported figure at both ends, and when the window clock may divide |
| `UsageTintTests` | The configurable amber→red boundary, including exact-threshold equality, the fixed green boundary, and spent overriding the setting. [ui/rings-and-surface.md](ui/rings-and-surface.md) |
| `ClaudeCodeSeverityTests` | Warning severities leave room; locked reasons and unknown severities still mark the limit spent. [providers/claude-code.md](providers/claude-code.md) |
| `RailGeometryTests` | Every ring the rail draws is reachable: each centre inside the rail, the last ring whole rather than clipped, each ring hit-testing to its own slot — across left/right/top and docked/floating. Plus the count itself: `shownSlotCount` is called with a reading that really splits, so a window measuring its rects in accounts rather than rings fails a test instead of a click (verified by reintroducing the bug). `PanelChromeTests` pins that tiny is below small, and that appearance pins or follows the Mac. |
| `RailOffsetTests` | The rail's offsets measured against the frame the window was **granted**, not the one it asked for — the panel is taller than a laptop's usable screen and AppKit refuses that frame. [ui/panel-geometry.md](ui/panel-geometry.md) |
| `ZaiHistoryReadTests` | What a history read found *out*: no key is not a failed request, and a successful reply with no rows is an answer |
| `ActiveDisplayTests` | Following the pointer onto another display: the move keeps dock and both ratios, a held panel refuses and the refusal is *reported* so the display stays on offer, and returning to the display it is already on is quiet rather than a refusal. [ui/panel-geometry.md](ui/panel-geometry.md) |
| `PanelHoldTests` | Nothing re-places the panel while it is held — including the gap between mouse-down and the first movement, where `isDragging` is still false. [ui/input.md](ui/input.md) |
| `RefreshPacingTests` | Automatic cadence, the unwatched-spend cap, and the timer being the only caller that skips providers not yet due. The production batch-result comparison includes Devin and every other represented provider; timestamps alone and an empty batch do not count as usage changes. [refresh-and-data.md](refresh-and-data.md) |
| `RailSlotTests` | The rail's order — including the order before anybody arranges it, which is by name, and that an arrangement somebody made is not re-sorted under them: when a split account becomes two slots, when it stays one, and that unscoped windows never form a group. [ui/rings-and-surface.md](ui/rings-and-surface.md) |
| `AntigravityParsingTests` | A captured `RetrieveUserQuotaSummary` reply → `[UsageWindow]` |
| `KimiCodeTests` | A captured `/usages` reply → windows, and that device-code sign-in is configured. [providers/kimi-code.md](providers/kimi-code.md) |
| `QoderParsingTests` | A captured Credits dashboard reply → plan and shared monthly windows, and that Add-on Credits inherits Team Plan's reset. [providers/qoder.md](providers/qoder.md) |
| `UsageReportTests` | The `--json` shape, which is a contract other people build on. [json-output.md](json-output.md) |
| `ConnectionDiagnosticTests` | Failures through real cache reconciliation, persisted origin, legacy unknown sources, capture freshness versus cache selection, allowlisted diagnostic copy, account-specific repair choices, and credential failures at pinned service boundaries without network calls |
| `PulseLinkTests` | Encoded added-account ids, malformed/action-bearing URL rejection, existing-account navigation and repeated-link requests |
| `VolcengineSignerTests` | Volcengine's request signature, cross-checked against a second implementation |
| `ZaiHistoryTests` | The statistics endpoint's shape → a day-by-day ledger, and what may not be said about it |
| `SecondWindowTests` | Which limit the second ring shows: the fullest in the headline's own model group, and the fallback when that group holds nothing more |
| `ZaiQuotaTests` | The GLM Coding Plan quota reply → windows, including a spend of zero being a reading rather than a gap |
| `ZaiErrorTests` | What the GLM Coding Plan's HTTP-200 refusals mean, from envelopes taken off both live hosts |
| `VolcengineParsingTests` | Ark's three reply shapes, from second-hand fixtures. [providers/volcengine.md](providers/volcengine.md) |
| `VolcengineProcessTests` | The `arkcli` subprocess: a stderr flood, an output flood, a child that ignores SIGTERM, one that closes its pipes and lives, descendant termination after the leader exits (with and without TERM handling), and how a non-zero exit is classified |
| `CommandCodeParsingTests` | Command Code's four replies → windows, from second-hand fixtures. Chiefly **which question the monthly row answers**: a running plan against its inferred, labelled grant; an account without one against the pool it bought; a plan the table cannot size against *nothing* — not zero, not the pool. Plus what absence may not be read as: absent credit pots are not an empty wallet, a summary that never arrived is not nothing spent, an answered `data: null` is not a failed lookup, and a ceiling of zero or less is not a limit already reached — each of those drew a wrong ring before it was a test. Also stable org ids across a reordered array, epoch-millisecond resets, `exceeded` outranking the arithmetic, and equal lengths not shuffling. [providers/command-code.md](providers/command-code.md) |
| `RailMoneyTests` | The figure a ring shows when a provider reports money: abbreviated past a thousand, truncated rather than rounded up, no early rollover at 999,999, the narrow currency symbol — and every form measured against the room the rail actually has, which is the bug it exists for. [providers/deepseek.md](providers/deepseek.md) |
| `ChromiumLocalStorageTests` | Origin filtering, sequence ordering and deletions, both text encodings, table prefix skipping, Snappy, 32KB padding and fragment assembly (including a zero-length FIRST). Malformed lengths pass through the real log/table parsers: overflowing varints, oversized key/value lengths, invalid block handles, truncated or undercounted batches, orphaned fragments, records crossing block boundaries, and values that would consume the restart array. All stores are synthetic. [providers/devin.md](providers/devin.md) |
| `ModelPriceAliasTests` | One model, several spellings: Grok Build's `-build` tag, a context window (`k3-256k`) being the same model, Kimi's abbreviations, Devin's dashed versions and effort suffixes, MiniMax's casing — and that an id nobody publishes a price for stays unpriced rather than being matched to something near it, since a loose match bills a model at another model's rate. [token-spend.md](token-spend.md) |
| `SpendSummaryTests` | Calendar spans and padded quiet days, excluding provider statistics from priced totals, agent/model ranking, streaks, peak hours and table sorting. Cross-midnight and resumed sessions contribute only their in-span priced buckets, so session and project totals agree with the selected span. Sessions without a project do not form an "other" bucket. [token-spend.md](token-spend.md) |
| `AgentStoreTests` | The readers for agents that keep their work somewhere other than a Claude-shaped transcript: OpenCode's message JSON (reasoning counted as output, priced from `ModelPrices` and never from the store's own `cost`), Grok's per-model `modelUsage` winning over the flat totals beside it, Kimi's `input_other` being fresh input, and a store that is not there reading as absent rather than as an empty account. Every store is built by hand in its measured shape; nobody's transcripts are committed. [token-spend.md](token-spend.md) |
| `AgentCacheTests` | Nested transcript additions, appends and removals; title metadata; SQLite WAL inputs with shared memory excluded; price-table fingerprints and cache serialization. A real SQLite writer remains open across a committed insert to prove that a WAL update invalidates the fingerprint while the database file stays unchanged. [token-spend.md](token-spend.md) |
| `AgentSessionTests` | Synthetic OpenCode, Grok, Devin CLI and Kimi stores with work on two days, through the production reader and then the spend summary. Session buckets reconcile with reader totals; Today keeps only today's tokens and published-rate cost. [token-spend.md](token-spend.md) |
| `SessionTitleTests` | Title trimming, envelope rejection, both message-body shapes and directory fallback. Tests also run the real Claude transcript parser: a rename after the opening prompt is read, the last valid custom title wins, and token counts remain intact. [token-spend.md](token-spend.md) |
| `DevinParsingTests` | A provider read out of a file another app wrote: `used = 100 − remaining` on both windows, a paid plan's `-1` message counters being absent rather than an allowance of minus one, a free plan's message pool carrying no window, `hideDailyQuota` dropping a row rather than zeroing it, the live plan winning where two accounts share one store, and the launch stamp coming from the log directory's name — plus the endpoint half: a whole `Authorization:` line, a slug, an internal id and an organization URL all parsing into the right path segment, the candidate paths being ordered and unique, and the endpoint's percentages being **spent** where the saved plan's are **left**. [providers/devin.md](providers/devin.md) |
| `DevinSnapshotTests` | Saved-plan freshness, expired windows, balance-only expiry, and missing/future/unrecognized launch stamps. The direct-fetch cache path applies age/reset limits too; an idle app-cache route is not classified as an outage. All stores and timestamps are fixtures. [providers/devin.md](providers/devin.md) |
| `DevinAccountMixingTests` | Injected production service routes through cache reconciliation: different users and organizations cannot borrow readings; the same endpoint credential and organization can. Endpoint failures never cross to the app's saved plan, expired content cannot bypass scope checks, and scope plus newest-reading selection survive a cache restart. [providers/devin.md](providers/devin.md) |
| `DeepSeekParsingTests` | Where each denominator comes from, for the one provider that reports none: the watched mark advancing only on a rise, a peak of zero drawing nothing, a budget of nothing drawing nothing, money strings parsed with absent kept distinct from zero, which currency the ring follows, and `is_available` being the only thing that may say spent. [providers/deepseek.md](providers/deepseek.md) |

## What is not, and why

Developer integrations also have `Integrations/raycast/tests/report.mjs`: run `npm test` from that extension directory after `npm ci`. It exercises the TypeScript consumer and launches the actual shell formatter with synthetic JSON, covering gaps, balance-only accounts, estimates, age, exact account selection and tmux escaping. `npm run build` and `npm run typecheck` check the Raycast extension. These are not evidence of real Raycast/sketchybar UI or macOS URL delivery; those need the host applications and a bundled Pulse. Installation: [integrations.md](integrations.md).

**No UI tests.** The panel is an accessory `NSPanel` whose hover cannot be driven by synthesised events — `hitTest` and synthetic `NSEvent`s both reported a handle as perfectly reachable while real clicks were being dropped, which is the lesson in [ui/input.md](ui/input.md). A UI test here would report the same thing.

**A rule test is not a chain test.** `AlertMemoryTests` hands the state machine readings directly, and two rounds of review missed a defect that lives *between* the service and the machine: the cache swaps a failure for cached figures and the reason is gone with it. Where a rule depends on something upstream, test it through that thing.

**No live provider calls.** Every route needs somebody's real credential and answers differently by plan. Fixtures are captured by hand from a real reply and committed; the capture is recorded in that provider's page.

**A fixture written from another project's parser, or from a vendor's own shipped client, is second-hand**, and has to say so where it lives. Volcengine's are, because nobody here holds that plan; Command Code's are written from the field names in its published npm bundle. A captured one replaces either the moment somebody with an account can produce one. Second-hand is enough to pin a shape against change, and not enough to claim the shape is right.

**A subprocess test really spawns one.** `VolcengineProcessTests` runs `/bin/sh` on purpose: the two failures it covers — a child that fills the stderr pipe, and one that never exits — cannot be produced by a fake, and neither is visible by reading the code. The first version of that runner looked correct and had both; the *second* looked correct and still hung on a child that ignored SIGTERM. Neither was findable by reading. The deadline is a parameter so a test can use one second.

**No network, no clock, no disk in a rule test.** `AlertMemory.alerts` takes `now` as an argument for exactly this reason. `UsageCache.init(file:)` takes a path for exactly this reason. Anything that has to reach for a real one is not a rule test.

## Two conventions

**The executable target is tested directly** (`@testable import Pulse`), not through a library split. Pulse is one app, not a framework with an app on top; carving seventy-eight files into two targets to make them reachable would be a refactor in service of the test runner. SwiftPM has allowed this since Swift 5.5.

**A symbol may be `internal` instead of `private` so a test can hold it**, and when it is, the comment says so and says not to tidy it back. `AntigravityUsageService.Reply` and `windows(from:)` are the first two. Nothing outside the module can see them either way; the difference is only whether the fixture test compiles.

## Fixtures

`Tests/PulseTests/Fixtures/`, copied whole into the test bundle so a schema change diffs readably. Read them with `Bundle.module.url(forResource:withExtension:subdirectory:)`.

Captured payloads carry no account name, email, or token — check before committing one. A quota reply is bucket ids, display names, fractions and reset times, and that is all it should be.

**A temporary fixture removes only the root it created.** A test asks for a unique root, writes its database and logs inside that root, and deletes just the root on the way out. It never calls `deletingLastPathComponent()` from a fixture path to find something to clean up: one level above a file in the system temporary directory is the system temporary directory, which is not the test's to remove. `AgentStoreTests` is the example — its `temporary(_:)` hands back the owned root, and every test defers a `removeItem` on exactly that URL.
