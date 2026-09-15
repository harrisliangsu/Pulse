# Token spend

Owns: the Settings pane that answers *across everything I use, where did the work go* — its agents, its readers, and what may and may not be said about the figures. The per-provider history card is a different thing and lives in [refresh-and-data.md](refresh-and-data.md).

Source: [`SpendAgent`](../Sources/Pulse/Usage/SpendAgent.swift), [`AgentLedgers`](../Sources/Pulse/Usage/AgentLedgers.swift), [`SpendSummary`](../Sources/Pulse/Usage/SpendSummary.swift), [`TokenSpendView`](../Sources/Pulse/Settings/TokenSpendView.swift).

## An agent is not a provider

A **provider** is something Pulse can draw a ring for: it reports a quota, it has a settings pane, it can be signed in to. An **agent** is something that has *spent* tokens on this Mac. The two lists overlap and are not the same:

- Kimi's CLI, Kilo CLI and OpenCode leave transcripts here and sell no plan Pulse watches.
- Cursor and Copilot report a quota and leave nothing here to read.

Folding the first group into `Provider` would put rings on the rail for products with no limit anyone can check. So the pane has its own type, and nothing it does reaches the panel.

## Nothing on this page is on the rail

The rail is what is **left**; this is what is **gone**. It is Settings-only for the same reason the per-provider card is: it is read off hundreds of megabytes of transcripts rather than from a live endpoint, and it answers a sit-down question rather than a glance.

## Which agents, and why only these

| Agent | Store | Read |
|---|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` | `UsageLedgerReader` |
| Codex | `~/.codex/sessions/**/*.jsonl` | `UsageLedgerReader` |
| OpenCode | `~/.local/share/opencode/opencode.db` | `OpenCodeStore` |
| Kilo CLI | `~/.local/share/kilo/kilo.db` | `OpenCodeStore` — same schema, it is a fork |
| Grok Build | `~/.grok/sessions/<cwd>/<id>/updates.jsonl` | `GrokStore` |
| Kimi CLI | `~/.kimi/sessions/**/wire.jsonl` | `KimiCLIStore` |
| Devin CLI | `~/.local/share/devin/cli/sessions.db` | `DevinCLIStore` |

**Every one of these was read on a real machine**, against a store with real work in it. That is the whole admission rule. tokscale lists about fifty agents; the other forty-odd are not installed on any machine this was written against, and **a transcript format guessed from somebody else's parser fails silently** — it does not throw, it produces a wrong cost that nobody can see is wrong. Adding one blind would be [volcengine.md](providers/volcengine.md)'s second-hand evidence forty times over, on a page whose entire content is numbers.

**Kimi Code is installed here and is deliberately absent.** Its `state.json` carries a title, an agent and a first-token latency, and no token counts anywhere. An agent that can only ever report zero is worse than a missing one: the zero reads as a measurement.

Paths worth reading if somebody turns up with one of the rest are in tokscale's own table; there is no point copying it here until there is a machine to check it against.

## What the readers agree on

- **Money is `ModelPrices`, always.** OpenCode's store keeps its own `cost` column and it is ignored: it is whatever that app believed at the time, is zero for a plan it has no rate for, and mixing it in would put two differently-sourced figures in one total.
- **A model with no published price is counted and not costed**, and the spelling is resolved first. See below.
- **`ModelPrices` covers twelve vendors, not two.** It was Anthropic and OpenAI while only the two CLIs were read, which put four of the seven agents at $0.00 for no better reason than that their vendor was missing — along with every third-party model the two CLIs were pointed at. Ids are unique within a vendor and not across all 213 of them, so the list is deliberate and ordered; `github-copilot` is left out because it re-lists other vendors' models and Pulse reads no Copilot transcripts.
- **Reasoning tokens count as output**, where every price list bills them.
- **Quarter-hour buckets and one pricing function.** `UsageLedgerReader.slotKey` and `.price` are shared, so an agent read out of a database is bucketed and priced exactly as a transcript is. Two ways of turning tokens into dollars in one app is two figures that eventually disagree.

## One model, several spellings

The agents do not all write a model id the same way, and a name that misses the table is not a free model — it is a bill that quietly reads zero. `ModelPrices.price(for:in:)` resolves, in order: the id as written, the same id case-folded, then a short list of **aliases, each one a named product's known habit**:

| Written | Means | Whose habit |
|---|---|---|
| `grok-4.6-build` | `grok-4.6` | Grok Build tags its own build |
| `k3-256k`, `kimi-k3-256k` | `kimi-k3` | a context window is the same model with more room |
| `k3`, `k2p6` | `kimi-k3`, `kimi-k2.6` | Kimi's CLI abbreviates the version |
| `gpt-5-6-sol-medium` | `gpt-5.6-sol` | Devin writes dashes for dots and an effort on the end |
| `minimax-m3` | `MiniMax-M3` | case only |

**Rules, not fuzzy matching.** The failure mode of a loose match is a model priced at another model's rate, which is a wrong number that looks right; `grok-build-0.1` is a real xAI model and must not be stripped into `grok`. A lookup that still misses stays unpriced — eleven ids on this machine do, and four of those are `…-free` models that genuinely cost nothing.

## Titles and projects come from the transcript

Both CLIs state the working directory they ran in, and Pulse reads it: **the folder name is only a fallback**. Claude Code names its project folders for the path with every separator replaced by a dash (`-Users-me-Code-Pulse`), which cannot be reversed — a folder whose own name contains a dash is indistinguishable from a separator, and this machine has several. Reading the stated `cwd` instead took the project count from 19 to 34 with correct names.

A session's title is the one the user set where there is one (`custom-title`), else the words the conversation opened with, trimmed to a line. A command envelope (`<…>`) or the sandbox caveat is not a title — either would name most sessions the same thing. Claude Code's sidechains carry no prompt of their own and so no title; the row falls back to the project.

**The user's title is looked for on every line, not only while the session is still unnamed.** Claude Code writes `customTitle` when a conversation is renamed, often long after it stated its `cwd` and opening prompt; the old parser stopped reading once it had both, so every rename was lost. The last valid custom title wins, and an unreadable one (empty, or an envelope) leaves the title already found alone.

**A session is counted by the part of it that falls in the span.** A conversation resumed across midnight, or over several days, carries its own priced quarter-hour buckets, and a project's total over a span is the sum of the buckets inside it — the same arithmetic as the span's own total, never the whole conversation and never a share of it guessed from a ratio. The session row carries the span's portion too; its `start` and `end` stay the conversation's own, which is when it ran. A model with no published price is counted among those buckets and not costed, so the tokens and the money stay honest side by side. A ledger read before sessions kept their buckets cannot place the work inside a window at all: it falls back to counting the session whole when it ended inside the span, which is the old, coarse rule — not an exact interval, and only ever a path for old data.

## Caching

Two layers, and they answer different costs:

- `UsageLedgerReader` caches **per transcript file** (`ledger-4-*.json`), keyed on size and modification date, and prices afresh each read — so a price change costs nothing and does not mean rescanning hundreds of megabytes.
- `AgentLedgers` caches **the whole ledger** per agent (`agent-2-*.json`). These stores are read from several places rather than file-by-file, so there is nothing finer than the ledger to keep — but the store root's own size and date are **not** a valid key for them. Grok's and Kimi's stores are directories, and appending to a log inside one does not move the directory; OpenCode's, Kilo's and Devin's are SQLite databases, and a commit lands in the `-wal` before a checkpoint touches the `.db`, so even a restart could read a stale cache. The stamp is therefore a digest of the store's *real inputs*: every regular file under a directory store, recursively — logs, and the `state.json` a Kimi title sits in — by path, size and modification date; or the `.db` plus its `-wal` and `-journal` for a database. The shared-memory `-shm` is deliberately left out, because merely opening the store touches it and a read must not invalidate the cache it was about to validate.

**Money is part of the kept ledger, so the price table is part of the key too.** The stamp carries a digest of `ModelPrices`' rates and names. A fetched table with unchanged contents invalidates nothing; one changed rate invalidates the saved ledger; and an **empty** table is its own stamp, so a later cold load with prices available rejects an offline `$0.00` cache even if the store has not changed. Within one process, opening the pane reuses memory; **Rescan** explicitly reads again. Changing the span only recomputes the displayed totals.

A new ledger is persisted only if the store's fingerprint still matches after the read. If the source changed during scanning, that result stays in process memory and is not written as a stable disk cache; there is no retry loop.

**A cache file's number is part of the contract.** `model-prices-3.json` invalidates the older two-vendor price table. `ledger-4-*.json` invalidates both entries without titles/working directories and `ledger-3` entries whose titles were parsed before the rename fix; otherwise an unchanged transcript would never reach the corrected parser. `agent-2-*.json` invalidates the old root-only stamp and sessions without priced buckets, which cannot be counted accurately within a selected span. These names force the one rescan that fills the missing information in.

Loading and recomputing are separate tasks in the pane. Reading every store is seconds on a cold launch; adding the numbers up for a different span is microseconds — keyed together, changing the span put the spinner back on screen and made a cached read look like a rescan.

## What the page will not say

- **No per-model cost.** The logs price a *day's* work and count tokens *per model*; there is no per-model cost to add up, and applying a day's blended rate to one model would be a number nobody reported. The model list is tokens, and says so.
- **No "other" bucket for sessions without a project.** Codex's own path carries no directory, and a bucket that large would outrank every real project on the list. Those sessions are in every total above and simply not on that list.
- **Not a bill.** Everything is what the same work would have cost through the API at published rates; the plans are subscriptions. Work done on another machine is not here.

## Tests

`ModelPriceAliasTests` (every alias rule above, and that an unknown id stays unpriced rather than being matched to something near it), `SpendSummaryTests` (spans as calendar windows, padded days, agent and model rollups, streaks, the peak hour, sessions and projects windowed by their own buckets — including one resumed across midnight and one resumed over days — table sorting), `AgentStoreTests` (each store built by hand in its measured shape — nobody's transcripts are committed), `AgentCacheTests` (a nested log append that the directory's own stamp misses, a session file added and removed, a title file changed, a database's `-wal` counting while its `-shm` does not — including a real SQLite WAL writer left open across an `INSERT`, an empty price table being its own stamp, and an old `agent-1` ledger refusing to decode), `AgentSessionTests` (each production reader built by hand — OpenCode, Grok, Devin and Kimi — with work on two days, proving the session's buckets sum to its own totals and `SpendSummary` over a one-day span counts only the in-window half), `SessionTitleTests` (titles trimmed to a line, envelopes refused, the two message-body shapes, and — through the real parser — the custom title read even when it arrives after the opening prompt).
