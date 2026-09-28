# Windsurf

Profiled provider: [`Sources/Pulse/Providers/Profiled/WindsurfUsageService.swift`](../../Sources/Pulse/Providers/Profiled/WindsurfUsageService.swift). User setup: [../setup/windsurf.md](../setup/windsurf.md).

**Not Devin's route.** Windsurf is Cognition's now, and [Devin](devin.md) already reads both other ways to this plan: the Devin/Windsurf app's saved plan in `state.vscdb` (which it looks for under both `Application Support/Devin` and `…/Windsurf`), and `app.devin.ai`'s quota endpoint with a session out of the browser. Reading either here would count one account twice under two names. This provider reads windsurf.com's own endpoint, and nothing else.

- **Credential:** `.browserStorage(origin: "https://windsurf.com", keys: …)` — the four values windsurf.com keeps in `localStorage` (`devin_session_token`, `devin_auth1_token`, `devin_account_id`, `devin_primary_org_id`), read from a Chromium browser when the user presses Read and saved together as one JSON object (`ProviderProfile.storageCredential`, which unwraps JSON-quoted values). All four or nothing: anything less is "Read a browser session", with no request sent. A 401/403 or a redirect is "session expired".
- **Route:** `POST https://windsurf.com/_backend/exa.seat_management_pb.SeatManagementService/GetPlanStatus`, Connect over protobuf. Headers: `Content-Type: application/proto`, `Connect-Protocol-Version: 1`, `Origin: https://windsurf.com`, `Referer: https://windsurf.com/profile`, `x-auth-token` and `x-devin-session-token` (the session token), `x-devin-auth1-token`, `x-devin-account-id`, `x-devin-primary-org-id`. Body: field 1 the session token, field 2 `include_top_up_status = true`.
- **Reply:** field 1 `plan_status`, of which: 1 `plan_info` (its 2 is the plan's name), 14 `daily_quota_remaining_percent`, 15 `weekly_quota_remaining_percent`, 17 and 18 their resets in Unix seconds. Every other field is skipped by wire type; a reply that can't be walked to the end is unreadable.
- **Windows:** `.daily` (86,400 s) and `.weekly` (604,800 s), both `reportsLength: true` — the service names them. `usedFraction = (100 − remaining) / 100`. A remaining figure over 100 is dropped.
- **Plan:** `plan_info.plan_name`.

## Left out, deliberately

- **A quota that is absent.** Protobuf does not write a zero, so "0% remaining" and "no such quota" arrive the same way. CodexBar leaves it off; so does this, rather than guess that it is spent. Unverified against a spent account — if Windsurf's schema marks the field `optional`, a zero would arrive and be read.
- **`plan_end`, top-up status, grace period** — not usage.
- **The app's saved plan** (`state.vscdb`) — CodexBar's other route, and Devin's.

## Evidence

Second-hand. Field numbers from CodexBar's Windsurf provider (which took them from Windsurf's bundled protobuf metadata and re-checked them against browser traffic) and values from its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/windsurf-plan-status.json`, the reply as base64.
