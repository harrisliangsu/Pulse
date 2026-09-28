# Notion AI

Profiled provider: [`Sources/Pulse/Providers/Profiled/NotionAIUsageService.swift`](../../Sources/Pulse/Providers/Profiled/NotionAIUsageService.swift). User setup: [../setup/notion-ai.md](../setup/notion-ai.md).

- **Credential:** a browser session read for host `notion.com` (which covers `app.notion.com` and `.notion.com`), kept to the `token_v2` cookie. The fetch applies the same filter again, so a hand-pasted header sends nothing else. Sessions still on the legacy `notion.so` domain are not read — a browser would not send them to `app.notion.com` either.
- **Route:** two `POST`s to `https://app.notion.com`, both Notion's internal, unsupported `/api/v3` API, with `Cookie`, `Origin` and `Referer`. Redirects are refused (a hand-set `Cookie` would follow one anywhere); a 3xx, 401 or 403 is an expired session.
  1. `/api/v3/getSpaces`, body `{}` — the workspaces the account can see.
  2. `/api/v3/getCreditRateLimitStatus`, body `{"spaceId": "<uuid>"}` — the allowance.
- **Workspace:** `getSpaces` is a record map keyed by user id; records are wrapped once or twice in `value`. Only a reply that identifies exactly one user is read (or, for older replies without the id, one with a single key). The first workspace (by id) whose `subscription_tier` is `business` or `enterprise` is used, else the first there is. None → "no plan". There is no workspace picker; CodexBar's workspace-id setting has no Pulse equivalent.
- **Reply:** `{ status, window: { window, used, limit }, resetsInSeconds, billingPeriodWindow: { used, limit, periodEndMs }, enforcement }`. `status: "not_applicable"` → "no plan". A reply with neither window is unreadable.
- **Windows:**
  - `window` → used/limit. Length from the stated token (`6h` → `.other(21600)`, "6-hour limit"; `5h`, `1d`/`24h`, `7d` map to the named kinds). An unreadable token → `.credits` with no length claimed. Reset: now + `resetsInSeconds`.
  - `billingPeriodWindow` → `.monthly`, used/limit, reset at `periodEndMs`. A billing period: `reportsLength: false`, 30 days as sort key.
  - The plan (`subscription_tier`, capitalised) is shown as the plan.
- **Figures:** a missing figure or a limit of zero or less drops that window; none left is "No limits reported". Over the limit is kept as reported, not clamped.
- **Left out, deliberately:** Notion credits for Custom Agents and Workers (`getAIUsageEligibilityV2`), which CodexBar doesn't read either; account email and workspace name (Pulse has no identity line for profiled providers); CodexBar's cURL-capture header forwarding.
- **Evidence:** second-hand. The shapes come from CodexBar's Notion provider and its fixtures (MIT); no live account has been read. Fixtures: `Tests/PulseTests/Fixtures/notion-ai-*.json`.
