# OpenCode Go

Service: [`OpenCodeGoUsageService.swift`](../../Sources/Pulse/Providers/OpenCodeGoUsageService.swift).

Extra accounts are not supported. `keepsLocalTranscripts` is false today. The detailed card's history is the console's request log once its session is kept, and OpenCode's local store (a Token spend agent) until then (`Provider.cardHistory`).

## Credential

Two places, in this order:

1. A key pasted into Settings (`keys.dat`). It wins — otherwise a stale key left behind by OpenCode would quietly override a deliberate choice.
2. What OpenCode saved for itself in `~/.local/share/opencode/auth.json`. Anyone already signed in there configures nothing.

A key the service refuses reports `.apiKeyRefused`, **not** `.signInRequired` (that message names Codex). There is no `.openCodeKeyRefused` case.

### The console session (second credential)

Settings › OpenCode Go › **OpenCode console** reads the signed-in console's session out of the browser (`OpenCodeConsoleGroup`, the default browser first; Chromium asks for the keychain) and keeps it in its **own slot** of `keys.dat` — `openCodeGo#console` (`APIKeyStore.key(for:slot:)`) — beside the key, so neither replaces the other. Only `__Host-console_session` and `auth` are kept (`OpenCodeConsole.keep`); Stripe's `__stripe_mid` / `__stripe_sid` and `oc_locale` come along from the browser and are dropped. A header without `__Host-console_session` is no session. Whether one is kept is cached in memory (`OpenCodeConsole.hasSession`, refreshed in `UsageStore.loadAPIKeys`), because the detailed card asks every frame.

It answers two things:

1. **The plan's limits**, when there is no key at all, or the key route came back `.apiKeyRefused` / `.unreachable` / `.serverError` / `.unreadableReply`. Never instead of a key that works. Reading: `origin = .webSession`.
2. **The account's request log** for the detailed card ([../ui/panel-geometry.md](../ui/panel-geometry.md#detailed-card)).

## Route

`GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer …`.

OpenCode’s own docs cover model endpoints; this usage path is **not documented** there, so it can change without notice. Do not call it an official quota API.

Reply: `usage.{rolling,weekly,monthly}`, each with `status`, `percent` (how much is **gone**), and `resetsAt`. A `status` other than `ok` is treated as spent.

**The window the reply calls `rolling` is the five-hour one** — the reset lands five hours out — so it is shown as “5-hour limit”. Only its *id* keeps the provider’s key, which is what a pinned window is matched on. `Kind.monthly` exists because a billing period had nowhere to map. `windowSeconds` orders the rows; only the reset stamp is displayed. The monthly one is marked `reportsLength = false`: a month is 28 to 31 days, and with no start in the reply its thirty only orders the row — claimed as reported, it set the window clock and burn rate by thirty. A week is seven days whatever, so the weekly one keeps its length.

## Console routes

All undocumented, read with the `Cookie` header; a 401/403 **or an HTML reply** (the sign-in page) is a session gone stale — `.sessionExpired` for the limits, "read it again in Settings" on the card.

**Every route but the list wants the workspace in an `x-org-id` header** (`wrk_…`). Without it each answers `400 {"_tag":"BadRequest"}` — measured; neither a `workspaceID`/`workspace` query nor `x-workspace-id`/`x-opencode-workspace`/`workspace` headers stand in for it, and the console page's own requests carry `x-org-id` (seen in the browser's "Copy as fetch", which leaves the cookie out). **`GET /console/api/orgs`** lists the session's workspaces as `[{id, name}]`; `OpenCodeConsoleWorkspace` asks once per session, uses the only one, or with several the first whose `go/status` has `access`. Settings tries it the moment a session is read and says which workspace answered (or that the console turned the session away), and that the log shows on the detailed card while that is off — a read that changed nothing on screen looked like a read that did nothing.

**`GET https://opencode.ai/console/api/go/status`** — the plan. `access.meters.{fiveHour,week,month}`, each `limitMicroCents` / `usedMicroCents` (**strings**, decoded as `Decimal`), `resetsAt`, and `startsAt` for the five-hour and weekly ones. Mapped to the **same ids as the key route** (`rolling`, `weekly`, `monthly`) so a pinned limit survives either route; fraction = used ÷ limit; spent when used ≥ limit. A meter with a `startsAt` states its length (`reportsLength`); the monthly one starts with the billing period, taken from `access.startsAt` only when `access.endsAt` equals the month's `resetsAt`. `product: "go"` becomes the plan name "Go". Measured on one account (historical): limits of 1,200,000,000 / 3,000,000,000 / 6,000,000,000 micro-cents, i.e. $12 / $30 / $60. The reply also names the payment method and the account; neither is decoded.

**`GET https://opencode.ai/console/api/request-logs?since=<ms>[&until=<ms>]&category=inference&limit=100[&cursor=…]`** — the request log, newest first, kept 30 days (`OpenCodeConsole.span` asks for 31). `limit` is at most **100** (200 and 500 answer `400`); `until` bounds a walk from above; `cursor` is each page's `nextCursor` (an opaque JSON string) — both verified: the second page shared no id with the first, and an `until` walk's newest entry was before its bound.

**Adaptive paging** lives in [`OpenCodeConsolePager`](../../Sources/Pulse/Providers/OpenCodeConsolePager.swift). It starts with one request for the whole interval, so an empty or short history costs one page instead of 31 daily requests. A page with a continuation proves the newer portion has been read. Its timestamp spread sizes the next older slice (roughly a page at the observed density); that slice and the older remainder can run independently, sharing a maximum of **six concurrent requests**. Busy days can use several workers. Bounds meet inclusively and the oldest returned timestamp is read again, so requests sharing a boundary are preserved and merged by id. A same-timestamp burst or an interval too narrow to split follows the server's opaque cursor. A repeated cursor, exhausted **200-page budget across the entire scan**, or failed page leaves explicit pending intervals and `hasPartialCounts`, never a claim that the month is complete. Failed pages retry after one and two seconds; cancellation and rejected sessions do not retry. Authentication rejection stays a rejection even after earlier pages arrived.

Historical measurements before adaptive paging, on one month of 2,135 requests: 143 s as one walk of 50s; 36–44 s as six equal stretches, held up by one busy stretch; 56 s as twelve concurrent walks; 49 s by days. A single day held 1,293 requests, so the daily design still left a long sequential chain while asking about empty dates too. These are measurements from that account, not an endpoint latency guarantee.

**Kept on disk** (`opencode-console-log.json` in Pulse's folder, owner-only): the compact decoded entries, workspace, completeness, pending intervals and last attempted upper time bound — **never the session**. [`OpenCodeConsoleHistory`](../../Sources/Pulse/Providers/OpenCodeConsoleHistory.swift) restores only the resolved workspace's cache. A complete result is fresh for **60 seconds**, including an empty result; otherwise it reads the new tail with **fifteen minutes** of overlap (`tailOverlap` — the log is placed by when a request started and its counts are only known when it ends, so a request still running at the last read began before it), plus any unfinished intervals; a read cancelled or turned away leaves a complete cache complete, so the next read is the tail again rather than the month. With several workspaces, only one that answered with Go access is remembered; if none did (none has it, or the console blinked), the first is used for that read and asked about again next time. A failed old interval is retried without downloading already completed history again. Finding a known request id does **not** prove other intervals are complete. Original complete caches remain usable and take one incremental check to acquire the new metadata; original incomplete caches without known intervals must backfill the month.

**One read per session at a time**: the card, Settings and warm-up share the same task. A different cookie waits and then resolves its own workspace instead of borrowing that task's answer. Settings receives the saved figures before the network read finishes, then page-by-page snapshots, including when it joins a warm-up already in progress. Its history card shows “Reading…” during the update and “Counts may be incomplete.” for a partial snapshot; the cache hit rate stays unavailable until the read is complete. Request identities and the pane's history key fence stale progress after navigation or credential changes. **Warm-up**: `UsageStore.loadAPIKeys` starts a read in the background while OpenCode Go is on and a console session is kept. Leaving Settings does not cancel this shared warm-up; another observer can reuse it.

**Settings shows the same history** as Claude Code's and Codex's panes: `providesHistory` includes OpenCode Go while a console session is kept, `loadHistory` reads it from the shared history, and `AccountUsageCard` shows money for `.providerLogs` (charged, not estimated), "Last 7 days" in place of "All time" (the log keeps 30), and a footnote naming the request log. Reading or removing the session bumps the pane's history key, so the group appears or goes at once. **The log starts when the console began keeping it**, not with the billing period: on the measured account its oldest entry was 19 September while the monthly meter counted from the 14th, so the card's 31 days ($3.38) sat under the monthly meter ($12.83) — while the weekly sum matched the weekly meter to the cent ($2.55). That gap closes on its own as the log fills its 30 days. Per entry, only `id`, `startedAt` (ms), `product`, `model`, `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens` and `cost` (dollars charged) are decoded — the entry also carries country, region, city, key ids and request headers, which are never read. `inputTokens` is **fresh** input: measured, one request logged 184 input beside 294,272 cache reads. `reasoningTokens` is taken to be inside `outputTokens` (the console's own "Tokens" column is input + output). Only `product == "go"` counts — the workspace's other products are not the Go plan. Clients other than OpenCode that use the key (one measured: `HermesAgent`) are in the log, which is the point.

The ledger is `origin = .providerLogs`: whole account **and** priced as charged — the card shows the money without "≈". A renewed session for the same resolved workspace can reuse that workspace's cache; another workspace cannot. The card's own five-minute hold (`CardLedgers`) is keyed on the kept session as well: reading another account's session in Settings rereads the card at once, and an answer that arrives after the session changed is dropped rather than shown under the new one.

`OpenCodeConsolePagingTests` uses an original synthetic paginated server to check sparse-history request counts, busy-day concurrency, inclusive-boundary deduplication, coincident timestamps, the global budget and resumption, cancellation and authentication failures. Its server applies the production URL's millisecond conversion: rounding instead of truncating preserves requests sharing a boundary even where a floating-point `Date` round trip falls just below the original integer millisecond. `OpenCodeConsoleHistoryTests` covers fresh/empty disk caches, old-cache compatibility, failed-interval repair without false completeness from overlapping ids, early cached/partial snapshots, joining warm-up and workspace isolation. These tests make no live calls.

### Local timing probe (2026-10-01)

A separate, temporary command-line probe linked the production reader and read the same account with the saved session, using an isolated cache and a fixed upper bound; it was not added to the test suite. Both strategies returned the same **2,135 request ids, token total and charged amount**. The old daily walk took **43.33 s / 48 requests**. The adaptive walk delivered its first partial snapshot in **2.02 s**, used **30 requests**, and finished in **49.19 s**. Thus this run proves fewer requests and earlier usable results, **not a faster full cold download**. The same completed result read in **5.6 ms from memory** and **12.9 ms from an isolated disk cache**; workspace resolution was already cached in that process. A trial splitting off two predicted pages used 41 requests and took 68.72 s, including a 21 s stalled request, so the less speculative single-slice strategy was retained. Server stalls still govern full backfill time; the pane shows progress and incomplete counts rather than making the reader wait on an empty card or calling the early subset complete. These are API/reader timings, not real-input or first-painted-frame measurements.

## Transcripts later

`opencode stats` proves the CLI keeps sessions with token counts and cost, so a spending history is possible later, unlike Antigravity. It lives in OpenCode’s own store rather than the JSONL both other CLIs write, which is why `keepsLocalTranscripts` is false for now.

## First run

Presence of `~/.local/share/opencode/auth.json` marks the chooser row as detected. Its contents are not read until OpenCode Go is selected. An empty or unreadable file still counts as detected; the hint neither verifies a key nor enables the provider.
