# Replicate

Profiled provider: [`Sources/Pulse/Providers/Profiled/ReplicateUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ReplicateUsageService.swift). User setup: [../setup/replicate.md](../setup/replicate.md).

- **Credential:** `sessionCookie(host: "replicate.com", cookies: ["sessionid", "csrftoken"])`. `sessionid` is required; the CSRF cookie is optional. The Replicate API token authenticates model runs, not billing, and is not used.
- **Route:** two GETs, both with the `Cookie` header, 401/403 → `.sessionExpired`:
  1. `https://replicate.com/account/billing` (`Accept: text/html`). The account is found in a `<script type="application/json" id="react-component-props…">` block, as the first object anywhere in it with `account: { kind: "user" | "organization", username }` (breadth-first, at most 4,000 nodes). No such block: if the page is Replicate's sign-in page (title "Sign in | Replicate" **and** a `/login/github/` link) → `.sessionExpired`, otherwise `.unreadableReply`.
  2. `https://replicate.com/api/{users|organizations}/{username}/unused-credit` (`Accept: application/json`), username percent-encoded as one path segment.
- **Reply (2):** `{ unused_credit: "80.00" }` — a non-negative decimal string (a plain number is also accepted). Missing or null → "No limits reported"; anything else malformed → unreadable.
- **Windows:** none. Replicate reports no allowance and no percentage.
- **Balance:** `unused_credit` as USD (`creditRemaining`, `reportsSpendableBalance`). The reply carries no currency code; Replicate bills in dollars.
- **Left out:** this month's spend — CodexBar reads it from `/api/{…}/invoices` (the current `monthly-usage` invoice's `total_cost_before_adjustments`). It has no limit and Pulse has nowhere to show spend alone yet, so that request is not made. CodexBar's cached-candidate, multi-browser fallback is Settings' job here (Read picks one browser, or tries each).
- **Icon:** Lobe Icons `replicate` (monochrome).
- **Evidence:** second-hand. The shapes come from CodexBar's Replicate plugin (`replicate.ts`) and its tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/replicate-unused-credit.json`; the billing-page snippets are inline in `ReplicateTests`.
