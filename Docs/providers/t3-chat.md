# T3 Chat

Profiled provider: [`Sources/Pulse/Providers/Profiled/T3ChatUsageService.swift`](../../Sources/Pulse/Providers/Profiled/T3ChatUsageService.swift). User setup: [../setup/t3-chat.md](../setup/t3-chat.md).

- **Credential:** a browser session for `t3.chat`, read on request. Kept cookies: `wos-session` (required) and `_vcrcs` (Vercel's challenge cookie, if present). **Unverified:** CodexBar forwards every `t3.chat` cookie and names none; its tests use a placeholder `session=`. `wos-session` is WorkOS AuthKit's default name and is a best guess. If T3 Chat's session cookie has another name, "Read" will report no session found and this list must change.
- **Route:** `GET https://t3.chat/api/trpc/getCustomerData?batch=1&input={"0":{"json":{"sessionId":null},"meta":{"values":{"sessionId":["undefined"]}}}}` with `trpc-accept: application/jsonl`, `x-trpc-source: web-client`, `x-trpc-batch: true`, `Origin`/`Referer` of t3.chat. 401/403 → session expired.
- **Reply:** tRPC JSON lines; the customer record is the first object anywhere in any line that has `usageFourHourPercentage` or `usageMonthPercentage` (or both `subscription` and `usageBand`). Fields: `usageFourHourPercentage`, `usageFourHourNextResetAt`, `usageWindowNextResetAt`, `usageMonthPercentage`, `usagePeriodPercentage`, `billingNextResetAt`, `subTier`, `usageBand`, `subscription { productName, status, currentPeriodEnd, … }`. Timestamps are epoch ms, or seconds when ≤ 10¹⁰.
- **Windows:**
  - `usageFourHourPercentage` → `.other(seconds: 14400)` (the length is in the field's name), reset `usageFourHourNextResetAt` else `usageWindowNextResetAt`.
  - `usageMonthPercentage` → `.monthly`, reset `subscription.currentPeriodEnd` (not `billingNextResetAt`), sort key only.
- **Plan:** `subscription.productName` else `subTier`, dash-separated words capitalized.
- **Left out:** `usagePeriodPercentage` as a stand-in for the monthly figure (CodexBar does this; nothing says which period it is). A missing percentage is left off rather than drawn as 0% (CodexBar draws 0). CodexBar's manual cURL paste with captured browser headers (for Vercel challenges) has no equivalent: Pulse keeps cookies only.
- **Evidence:** second-hand. The fixture `Tests/PulseTests/Fixtures/t3-chat-customer-data.json` (JSON lines) is CodexBar's test body; no live account has been read.
