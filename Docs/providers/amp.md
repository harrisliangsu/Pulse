# Amp

Profiled provider: [`Sources/Pulse/Providers/Profiled/AmpUsageService.swift`](../../Sources/Pulse/Providers/Profiled/AmpUsageService.swift). User setup: [../setup/amp.md](../setup/amp.md).

- **Credential:** an Amp access token the user pastes (from ampcode.com/settings). Nothing is read from this Mac; `~/.local/share/amp` and `~/.config/amp` are presence-only discovery hints.
- **Route:** `POST https://ampcode.com/api/internal?userDisplayBalanceInfo`, bearer token, body `{"method":"userDisplayBalanceInfo","params":{}}`. A read-only RPC — the one the Amp CLI calls for `amp usage`.
- **Reply:** `{ ok, result: { displayText }, error: { code, message } }`. `ok: false` with `code: "auth-required"` is a refused key; any other `ok: false` is a server error. `displayText` is the text `amp usage` prints — **there are no structured fields**, and no other route gives these figures as data (the settings page embeds only the old free-tier object), so the lines are parsed. ANSI colour codes and Markdown `**` are stripped first.
- **Windows:**
  - `Amp Free: $R/$L remaining (replenishes +$x/hour)` → `.credits`, scope `Amp Free`, used `(L−R)/L`. It refills hourly and never turns over, so no reset and no length (`reportsLength: false`). Preferred over the percentage line when both are printed.
  - `Amp Free: P% remaining today (resets daily)` → `.daily`, scope `Amp Free`, used `100−P`. `reportsLength` only when "today" or "resets daily" is printed. No reset time: the hour is not in the text.
  - `Amp <Plan> Tier: agent usage $R of $L remaining …` → `.monthly` (`amp.agent`), used `(L−R)/L` from the dollars, not the rounded percentage beside them. Same line's `orb usage Rh of Lh a1.small orb hours remaining` → `.monthly`, scope `Orb` (`amp.orb`). Any other Orb unit is left off. Reset: the end date of `period YYYY-MM-DD to YYYY-MM-DD`, taken as UTC midnight (day precision). A billing period, so `reportsLength: false`, 30 days as sort key.
  - Older `Amp <Plan> Subscription: X% other usage and Y% orb usage remaining` (or `Subscription <Plan>: …`) → the same two ids from the percentages. No reset: only a rounded countdown is printed.
  - `Individual credits: $N remaining` → `creditBalance` / `creditRemaining` in USD (`reportsSpendableBalance`).
- **Figures:** a limit of zero drops that window; more remaining than the limit reads as nothing used. A reply with no line Pulse knows is "Couldn't read the reply", or a refused key when the text asks to sign in.
- **Left out, deliberately:**
  - CodexBar's "time to full" for dollar-based Amp Free — an estimate from the replenishment rate, never a stated reset.
  - The "resets upon renewal in N days/months" countdown — rounded, moves every refresh.
  - Amp Free's 8 PM New York reset time — known to CodexBar's docs, not stated in the reply.
  - `Workspace <name>: $N remaining` balances — Pulse has one balance per account and nowhere to show a workspace's beside it.
  - CodexBar's other routes: running `amp usage` (the RPC gives the same text without a subprocess) and the browser-cookie settings page.
- **Evidence:** second-hand. The lines come from CodexBar's Amp provider (`AmpUsageParser`, `AmpUsageFetcher`) and its tests (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/amp-balance-*.json`.
