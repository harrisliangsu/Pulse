# Raycast AI

Profiled provider: [`Sources/Pulse/Providers/Profiled/RaycastAIUsageService.swift`](../../Sources/Pulse/Providers/Profiled/RaycastAIUsageService.swift). User setup: [../setup/raycast-ai.md](../setup/raycast-ai.md).

- **Credential:** a browser session for `www.raycast.com`, read on request, kept to `__raycast_session` (required) and `csrf_token` — the two CodexBar keeps. 401/403 → session expired.
- **Route:** `GET https://www.raycast.com/frontend_api/current_user/ai_credits`, `Cookie`, `Accept: application/json`, `Origin`/`Referer` of raycast.com. CodexBar also sends a desktop Chrome `User-Agent`; Pulse doesn't, which is unverified against Raycast's edge.
- **Reply:** `{ remaining_balance_credits, total_balance_credits, next_credits_at, funding_subscription { tier } }`; amounts are numbers or numeric strings.
- **Windows:** one `.credits` window, used = (`total` − `remaining`) / `total`, reset `next_credits_at`, 30 days as sort key only (no length stated). Both figures must be there and the total positive; otherwise no ring ("No limits reported").
- **Plan:** `pro` → Pro, `pro_plus` → Pro+, `max` → Max, anything else as sent.
- **Discovery:** `/Applications/Raycast.app` (presence only).
- **Left out:** CodexBar's "Left / Total" detail rows when there is no meter — Pulse has no place for bare credit counts.
- **Evidence:** second-hand. The shape comes from CodexBar's Raycast plugin (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/raycast-ai-credits.json`.
