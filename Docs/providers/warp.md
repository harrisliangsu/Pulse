# Warp

Profiled provider: [`Sources/Pulse/Providers/Profiled/WarpUsageService.swift`](../../Sources/Pulse/Providers/Profiled/WarpUsageService.swift). User setup: [../setup/warp.md](../setup/warp.md).

- **Credential:** an API key (`wk-…`) the user pastes. Discovery hints only: `/Applications/Warp.app`, `~/.warp`.
- **Route:** `POST https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo`, bearer token, the read-only GraphQL query `GetRequestLimitInfo` (`user.requestLimitInfo`, `user.bonusGrants`, `user.workspaces[].bonusGrantsInfo.grants`). Headers as Warp's app sends them: `x-warp-client-id: warp-app`, `x-warp-os-category/-name: macOS`, `x-warp-os-version`, `User-Agent: Warp/1.0` — per CodexBar, the edge limiter answers 429 to any other agent.
- **Reply:** `{ data: { user: { __typename, user: { requestLimitInfo: { isUnlimited, nextRefreshTime, requestLimit, requestsUsedSinceLastRefresh }, bonusGrants: [{ requestCreditsGranted, requestCreditsRemaining, expiration }], workspaces: [{ bonusGrantsInfo: { grants: […] } }] } } } }`. The API names credits "requests". A non-empty `errors` array (GraphQL answers failures with 200) → `.serverError`. No `requestLimitInfo` → `.unreadableReply`.
- **Windows:**
  - Plan credits → `.credits`: `requestsUsedSinceLastRefresh / requestLimit`, reset `nextRefreshTime`, 30 days as a sort key (the period's length is not stated). Left off when `isUnlimited`, or when either figure is missing, negative, or the limit is 0.
  - Add-on credits → `.topUp`: user and workspace grants with both figures, summed; used = granted − remaining. No reset. `nextExpiry` is the soonest-lapsing remaining credits (`UsageWindow.Expiry.soonest`). Warp spends these after the plan's.
- **Reasons:** neither window → `.noLimitsReported`.
- **Left out:** CodexBar's "Unlimited" full-remaining bar (no limit, no ring). Its 100%-used add-on bar when a grant reports remaining credit but no granted total — a denominator nobody stated.
- **Evidence:** second-hand. The shape comes from CodexBar's Warp provider and its tests (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/warp-request-limit.json`.
