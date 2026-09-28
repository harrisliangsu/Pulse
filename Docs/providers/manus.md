# Manus

Profiled provider: [`Sources/Pulse/Providers/Profiled/ManusUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ManusUsageService.swift). User setup: [../setup/manus.md](../setup/manus.md).

- **Credential:** `sessionCookie(host: "manus.im", cookies: ["session_id"])`. The cookie's value is the bearer token; nothing else from the browser is kept or sent. 401/403 → "The browser session expired".
- **Route:** `POST https://api.manus.im/user.v1.UserService/GetAvailableCredits`, body `{}`, with `Authorization: Bearer <session_id>`, `Connect-Protocol-Version: 1`, `Origin`/`Referer` of manus.im and a Chrome `User-Agent` — the headers CodexBar sends.
- **Reply:** a credits object, bare or inside `data` / `result` / `response` / `availableCredits`: `{ totalCredits, periodicCredits, proMonthlyCredits, refreshCredits, maxRefreshCredits, nextRefreshTime, refreshInterval }`. Counts may be numbers or numeric strings. An object with no count at all is unreadable.
- **Windows:** refresh → `max(maxRefreshCredits − refreshCredits, 0) / maxRefreshCredits`; `.daily` with a stated length when `refreshInterval` says daily, otherwise `.credits`; reset from `nextRefreshTime` when it is an ISO 8601 string. Monthly → `(proMonthlyCredits − periodicCredits) / proMonthlyCredits`, `.monthly`, no reset (none is reported), 30-day sort key.
- **Balance:** `totalCredits` as a grouped number. Manus credits are not money, so no `creditRemaining` and no low-balance line.
- **Left out:** CodexBar reads a missing count as 0; Pulse leaves the window off. A numeric `nextRefreshTime` (CodexBar treats it as seconds since 2001, an artefact of its own cache format) is not read. `freeCredits`, `addonCredits`, `eventCredits` are parts of the total with no allowance.
- **Evidence:** second-hand. The shape comes from CodexBar's Manus plugin and its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/manus-credits.json`.
