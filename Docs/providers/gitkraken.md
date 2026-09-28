# GitKraken AI

Profiled provider: [`Sources/Pulse/Providers/Profiled/GitKrakenUsageService.swift`](../../Sources/Pulse/Providers/Profiled/GitKrakenUsageService.swift). User setup: [../setup/gitkraken.md](../setup/gitkraken.md).

- **Credential:** an account-session access token the user copies by hand from gitkraken.dev's usage request (`.apiKey(optional: false)`). A leading `Bearer ` is stripped; anything with inner whitespace left is not a token. No OAuth or refresh — an expired token is "That key was refused".
- **Route:** `GET https://api.gitkraken.dev/v1/ai-tasks/usage`, bearer token, `Client-Name: Pulse`, `Client-Version: <app version>`.
- **Reply:** `{ data: { used, limit, resetsOn, organization: { used, limit }, sharedUsed } }`. `resetsOn` is ISO 8601 with an offset.
- **Windows:** personal → `.credits`; organization pool → `.sharedCredits`; each used / limit, reset `resetsOn`. CodexBar calls the allowance weekly (from GitLens); the reply states no length, so 7 days is a sort key only (`reportsLength: false`). `limit` `-1` (unlimited) and `0` (no allowance) draw nothing.
- **Left out:** `sharedUsed` (your slice of the pool — a spend figure with no limit of its own); the `gk-org-id` organization picker (Pulse has no per-provider setting for it — the token's default organization is read).
- **Evidence:** second-hand. The shape comes from CodexBar's GitKraken plugin and docs (MIT), which cite GitLens's parser; no live account has been read. The fixture is `Tests/PulseTests/Fixtures/gitkraken-usage.json`.
