# IBM Bob

Profiled provider: [`Sources/Pulse/Providers/Profiled/IBMBobUsageService.swift`](../../Sources/Pulse/Providers/Profiled/IBMBobUsageService.swift). User setup: [../setup/ibm-bob.md](../setup/ibm-bob.md).

- **Credential:** an API key the user pastes, sent as `Authorization: Apikey <key>`; a key that is a JWT (a Bob sign-in token) is sent as `Bearer <key>`, as Bob Shell does. Nothing is read from this Mac.
- **Route:**
  1. `GET https://api.us-east.bob.ibm.com/admin/v1/profile` → `{ instances: [{ instance_id, user_id, plan_name, refresh_at, region_domain, teams: [{ id, budget_limit }] }] }`. `refresh_at` is Unix seconds or ISO 8601.
  2. For each team of each instance with a `user_id`: `GET https://api.<region_domain>/admin/v1/teams/<team>/users/<user>` with `x-instance-id` and `x-team-id` → `{ usage, budget_limit? }`. The team's `budget_limit` from step 1 stands in when step 2 has none.
- **Regional host:** `region_domain` gets `api.` prefixed unless it has it, and must then be a bare host (letters, digits, dots, hyphens) equal to `bob.ibm.com` or ending `.bob.ibm.com`; anything else → `.unreadableReply`, before the key is sent there. None named → the home host.
- **Window:** one, `.monthly` (IBM documents Bobcoins as a monthly metric; a billing month, so 30 days as a sort key, `reportsLength: false`): sum of usage / sum of budgets, reset the earliest `refresh_at`. Drawn only when **every** team states a budget and every figure is finite and non-negative, and the total budget is above zero.
- **Plan:** the distinct `plan_name`s, sorted, joined with ", ".
- **Reasons:** no team at all → `.noPlan`. A team without a budget (unlimited), or a figure that isn't one → `.noLimitsReported`. Any failed step fails the reading with its reason.
- **Left out:** CodexBar's per-team detail rows (Pulse has no rows for them; `scope` is for model names). Its 0% ring when a team is unlimited.
- **Evidence:** second-hand. The shape comes from CodexBar's IBM Bob provider and its tests (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/ibm-bob-profile.json`; the per-team replies are inline in `Tests/PulseTests/IBMBobTests.swift`.
