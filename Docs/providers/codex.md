# Codex

Service: [`CodexUsageService.swift`](../../Sources/Pulse/Providers/CodexUsageService.swift). App-server fallback: [`CodexAppServer.swift`](../../Sources/Pulse/Providers/CodexAppServer.swift). Extra accounts: [authentication.md](authentication.md).

`keepsLocalTranscripts` is true. Extra accounts are supported. Source choice: endpoint vs `codex app-server`.

## Routes (primary)

Default `.automatic`:

1. **HTTP usage endpoint** — read OAuth credentials Codex already stored in `~/.codex/auth.json`, then `GET https://chatgpt.com/backend-api/wham/usage` for account-wide windows plus any per-model limits. Nothing stays running. Works even when the `codex` command is not findable.
2. On missing or refused token (401/403): **`codex app-server`** — Codex’s own documented JSON-RPC protocol. It is signed in on its own terms so it renews credentials itself, and it pushes `account/rateLimits/updated`.
3. Cache, then an unavailable reason.

The HTTP endpoint is **not** a public documented usage API. It is what Codex’s own client calls and can change without notice. The stored token expires; Codex refreshes it while you use Codex, and nothing refreshes it for Pulse on the primary account.

Pinned `.endpoint` reports a dead token rather than falling through. Pinned `.tooling` never tries HTTP.

The two answers have **different field names** (`used_percent` / `limit_window_seconds` / `reset_at` versus `usedPercent` / `windowDurationMins` / `resetsAt`), hence two parsers.

## Windows

Never assume a fixed pair. `primary` / `secondary` are not tied to particular durations; which exist depends on the plan — ChatGPT Pro has no 5-hour limit at all, only the tiers below it do. A window’s kind is derived from its duration. The UI renders however many come back.

Codex reports `limit_reached` / `allowed` per group plus top-level `rate_limit_reached_type` and `spend_control.reached`. Those flags describe a whole group, which may hold both a 5-hour and a weekly window, so spent is pinned to the fullest window rather than smeared across both.

## Limit reset credits

How many one-off credits that clear a rate limit early the account holds. Only `codex app-server` reports them, under `rateLimitResetCredits` in `account/rateLimits/read` (`availableCount`, and `credits[]` with a `status` and `expiresAt`).

- **Settings, always:** the Usage history card leads with the count and the soonest expiry, fetched when that pane opens (`CodexAccountUsageService.fetch`).
- **The panel's card, opt-in:** **Reset credits on the card** in Codex's pane (`AppSettings.showsCodexResetCredits`, off by default; issue #67). The switch asks the store directly rather than through `onChange`, which would refetch every provider for one row. While it is on, every Codex refresh — the full pass or a click on the ring — also asks the app server for `account/rateLimits/read` (`UsageStore.refreshCodexResetCredits`), beside the ring's own fetch rather than inside it, so a slow app server never holds the ring up. Off by default because it starts or asks that process, which somebody reading Codex from its usage endpoint alone would otherwise never run. First account only: the app server reads the login the CLI saved.
- **Never a number Pulse worked out.** A reply without the reset-credit block, or an app server that did not answer, is `CodexResetCredits.unreported`, which the card says as "Not available". No `codex` anywhere Pulse looks is `.codexMissing`, said as "codex not found": the remedy differs, and one message for both left two Macs with several credits guessing which (#67, after 1.5.0).
- **Where `codex` is looked for** (`CodexAppServer.candidates`): `PATH`, Homebrew, `~/.local/bin`, bun, Volta, `~/.npm-global/bin`, pnpm, **the ChatGPT and Codex desktop apps' own `codex`** — `Contents/Resources/codex-cli/bin/codex` since ChatGPT 26.924, `Contents/Resources/codex` before it, both kept (`CodexAppServer.bundled`; the layout moved the day 1.5.1 shipped, #67) — (wherever Launch Services says the app with bundle id `com.openai.codex` is, then `/Applications` and `~/Applications` — somebody who uses Codex only through one of those apps has no other), then nvm, fnm and mise version folders, newest first. A block with no `availableCount` counts the `available` entries it lists. Settings' history card takes its count from the same `resetCredits(in:)`, so the two cannot disagree. When two asks overlap, only the latest may write: an app server timing out must not put "Not available" over a count a later ask brought back. Under the count the card shows when the soonest available credit expires, to the minute and with the year (`UsageDetailCard.resetCreditExpiryText`), because that decides whether to spend one now (#67). No row when there is none to spend or Codex gave no date.

## Plan name

The plan comes back as an internal tier name, not the name on the plan — `prolite` is the 5× Pro tier. `CodexUsageService.planName` maps the ones we know and passes anything else through verbatim rather than blanking it.

## App-server / SIGPIPE / PATH

**The folder `codex` was found in leads the helper's `PATH`** (`BoundedProcess.environment(leading:over:)`, which every launcher of another tool's CLI uses — Kiro's ACP client, `arkcli`, Alibaba's `bl` too). An npm install of `codex` is a Node script (`#!/usr/bin/env node`), and a GUI app's `PATH` has no `node` in it, so a `codex` found under `~/.nvm/versions/node/<v>/bin` started and died at once with `env: node: No such file or directory`: nothing only the app server reports — reset credits included — ever arrived, while the rings, read from the endpoint, looked fine (reported under #67; reproduced with `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and fixed: the same probe then read three credits). nvm, Homebrew and Volta put `node` beside the `codex` they installed. The path as found, not the link resolved: nvm's `codex` links into `lib/node_modules`, where there is no `node`.

**SIGPIPE is ignored process-wide** (`AppDelegate`), and it has to be. Writing to a pipe whose far end has closed raises it; default is to kill the process. The helper exiting, being killed with the terminal it was started from, or the user quitting Codex took Pulse down with it (`Terminated due to signal 13`). Ignored, the write returns `EPIPE` and `CodexAppServer.write` drops the helper so the next call starts a fresh one.

**Historical evidence:** reproduced both ways against a process that had already exited — unguarded the probe was killed before it could print a line; guarded it reported “Broken pipe” and carried on.

**The reader has to come off the pipe at EOF, and it has to come off synchronously.** `availableData` returning empty means the far end closed. A descriptor in that state is readable for ever, so a `readabilityHandler` that merely returns is called again straight away — a core at 100% for as long as the app runs, over a helper that has already exited. Shipped in 1.2.0 and reported as [#25](https://github.com/qunqin24/Pulse/issues/25): three spinning threads, 290% CPU, eleven hours, no child process left to blame. The handler clears **itself**, on the queue it is called on; hopping to the actor first leaves exactly the window the loop needs.

Two layers made it worse than one stuck handler. `ensureRunning` returns early while the process lives and starts a replacement when it does not — but it left the dead one's pipe wired up, so every restart added another spinning thread. It now tears the old reader down first, `shutDown` does the same, and EOF fails whatever was still pending instead of making it wait out the twenty-second timeout. A restart installing a new reader while the old one is still closing is fenced by handle identity, so a stale EOF cannot tear down its replacement.

`VolcengineUsageService` has cleared its handler at EOF since it was written; this path simply never learned it. `CodexAppServerTests` drives the reader against a plain `Pipe`, so it needs no `codex` on the machine.

Each pending RPC owns its 20-second timeout. A reply, write failure, EOF or shutdown completes it once and cancels that task. Request IDs continue across helper restarts, so an old callback cannot complete a new request. Closing the reader discards incomplete JSON, and queued data is accepted only from the current pipe. `RPCRequestLifecycleTests` exercises reconnects and deadlines with isolated subprocesses; it does not call a signed-in Codex.

Locating the executable cannot rely on `PATH`: a GUI app inherits almost none of it. `CodexAppServer.locateCodex` checks usual install locations, including versioned Node directories.

## Proxies

The HTTP endpoint uses Pulse's Network setting: macOS system proxy by default, or the manual HTTP/SOCKS5 proxy. On a machine behind a VPN, following the system is usually what you want (the endpoint may only be reachable through it). A tunnel that stumbles surfaces as a Pulse error, typically `-1005 networkConnectionLost`; transient `URLError`s are retried a couple of times.

`codex app-server` is different: it is a child process rather than a `URLSession`. Manual HTTP starts it with `HTTP_PROXY` / `HTTPS_PROXY`, manual SOCKS5 with `ALL_PROXY`, and both with loopback in `NO_PROXY`. Changing the proxy shuts down a running helper; the next request starts it with the new environment. Follow System injects nothing and preserves the environment Pulse itself inherited. Full boundary: [../networking.md](../networking.md).

## Added accounts

`fetch(account:credentials:)` uses Pulse’s stored tokens. Extra-account sign-in is **device code**, not redirect. Full published scopes, including connector scopes that looked optional and were not. See [authentication.md](authentication.md).

Codex’s usage endpoint wants the account named in a header of its own; `AccountCredentials.accountID` is taken from the token.

Settings can also show the account’s real lifetime total from `account/usage/read`, which is **larger than anything on this Mac**. Without that row the local ledger total reads as simply wrong.

## Ledger

Codex’s `input_tokens` **includes** cached tokens; `cached_input_tokens` is the subset. Session usage is a **running total** — difference it, do not sum per-turn `last_token_usage` (measured 6% high on one long session). Shared ledger rules: [`../refresh-and-data.md`](../refresh-and-data.md).

## Irregular reset forecast

The card's own windows are the account's 5-hour and weekly clocks (`resetsAt`). Separately, the Codex card shows what [Codex Resets](https://codex-resets.com) publishes about an irregular, account-wide reset.

`CodexResetClient` calls `GET https://codex-resets.com/api/v1/status` — the same document as that site's MCP server, without running an MCP process. `scheduled_reset.scheduled_for` is an explicit instant. The prediction then shows a countdown to it and the local date, weekday and time. If that field is null and `active_watch` is present, and `expires_at` is still ahead, the card counts down to that instant the way the site does: how long until a reset may happen, and the local date and weekday it is expected before. That instant is the end of the forecast window. It is not an announced reset — `explicitReset` ignores it, and a reminder never counts down to it. Once it has passed, those two lines are omitted rather than shown as a reset that already happened. The level (`elevated` / `strong`) and chance stay on the title row. `text` is the event note, with `forecast_window` when `text` is absent; a ? on the title row shows it, and it is not the line under the title. With no instant and no watch, the prediction row says there is no prediction. That row stays when `latest_reset` is also present. An explicit `scheduled_for` wins over a watch, including the watch's note.

`latest_reset` is the most recent public announcement, printed as its own row under the prediction. The card prints how long ago `announced_at` was, then the type and the local date and time: `regular` is “Regular reset” (常规重置), `banked` is “Banked reset credit” (备用重置额度). The clock uses the local calendar and the card's short date-and-time template, including when the announcement was earlier today. Hovering the type — the words, not an icon and not the clock — shows what that kind of reset was. A banked credit keeps the site's explanation: you apply it yourself, and it does not refill usage immediately. A regular reset, and any type the API adds later, shows `text` from that announcement, verbatim. Blank or missing `text` is no tooltip. `announced_at` is when the post went out. It is not a future reset, and a reminder never counts down to it. The same is true of a watch's `expires_at`. A `scheduled_for` sitting on `latest_reset` is unread.

The open card reads that status from the store, in the same body that draws the rings, and again inside the card. A copy taken when the card appeared is not enough: 「暂无预测」 is what both a missing status and an empty prediction say, so a `latest` that arrives while the pointer is still on the ring does not change any text already on screen, and the row — a branch that was not in the tree — never appears. The window is already tall enough for the row; it does not resize when the row shows up.

The prediction row carries the link to the site (`CodexResetClient.site`), an arrow rather than a credit line. It is on that row because the row is always drawn, including when there is no latest announcement. VoiceOver hears it as a link that opens Codex Resets. The ? sits beside that arrow and adds no row. It is absent when the watch has neither `text` nor `forecast_window`. VoiceOver reads the note as the mark's value.

A 304, a 429 (`Retry-After`), or any other failure keeps the last status; the panel does not blank or crash. Polling follows `Cache-Control` / `ETag`, and never faster than two minutes or slower than thirty.

Banked reset credits (`rateLimitResetCredits`: `availableCount`, soonest `expiresAt`) come from `codex app-server`, the same read settings already uses. The card asks only for rate limits, and only when the primary Codex card is opened, so a panel refresh does not also pull `account/usage/read`. If the app server is missing or the field is absent, the card omits the line — missing is not zero. A known zero is also omitted. Extra Codex accounts do not show credits; the app server is the local login. That line is this login's own cards. It is not the public `latest_reset`, which can also be a banked announcement.

Advance notice of an explicit `scheduled_for`, and of each account's own `resetsAt`, is the Reset reminders group. See [../notifications.md](../notifications.md).

## First run

Presence of `~/.codex`, never its contents.
