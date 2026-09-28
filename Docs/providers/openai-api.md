# OpenAI API

Profiled provider: [`Sources/Pulse/Providers/Profiled/OpenAIPlatformUsageService.swift`](../../Sources/Pulse/Providers/Profiled/OpenAIPlatformUsageService.swift). User setup: [../setup/openai-api.md](../setup/openai-api.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://api.openai.com/v1/dashboard/billing/credit_grants`, bearer token. Legacy: not in OpenAI's current public reference, and answered for older user keys only.
- **Refusal check:** any status other than 2xx, 429 or 5xx from that route sends one `GET https://api.openai.com/v1/organization/costs?start_time=<now − 1 day>&limit=1`. A 2xx there means the key is good (an Admin key) and the reading is "No limits reported"; its failure is the reason shown. The figures in it are not read.
- **Reply:** `{ total_granted, total_used, total_available, grants: { data: [{ grant_amount, used_amount, expires_at }] } }`, in US dollars (the route names no currency; the platform bills in one). At least one of the three totals must be there or the reply is unreadable.
- **Balance:** `total_available` → `creditBalance` and `creditRemaining` (USD). `reportsSpendableBalance` is on. Negative or missing: no balance, and "No limits reported".
- **Windows:** none. Granted/used is money in, money out; there is no allowance or period to draw a ring for.
- **Left out:** the Admin API's daily costs and completion usage (`/v1/organization/costs`, `/v1/organization/usage/completions`), which CodexBar charts. They are spend with no limit, and Pulse has no place for spend yet. Project scoping (`OPENAI_PROJECT_ID`) goes with them. CodexBar's ring from `total_used / total_granted` — and its 0%/100% when nothing was granted — is not drawn: grants lapse on their own dates, so that fraction is of no single allowance.
- **Evidence:** second-hand. The shape comes from CodexBar's OpenAI plugin (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/openai-api-credit-grants.json`.
