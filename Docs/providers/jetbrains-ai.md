# JetBrains AI

Profiled provider: [`Sources/Pulse/Providers/Profiled/JetBrainsAIUsageService.swift`](../../Sources/Pulse/Providers/Profiled/JetBrainsAIUsageService.swift). User setup: [../setup/jetbrains-ai.md](../setup/jetbrains-ai.md).

- **Credential:** `localLogin` — nothing pasted. The route shown on the pane is "The quota your JetBrains IDE saved · As current as the IDE last left it."
- **Route:** no network. `~/Library/Application Support/JetBrains/<IDE><version>/options/AIAssistantQuotaManager2.xml`, and `~/Library/Application Support/Google/AndroidStudio<version>/…`. Only folders whose name starts with a known IDE prefix are looked in; of those, the file modified last is read. Read-only.
- **Shape:** XML; `component[@name='AIAssistantQuotaManager2']` has `option` elements whose `value` attribute is JSON (escaped with `&quot;` / `&#10;`, undone by the XML parser):
  - `quotaInfo`: `{ type, current, maximum, until, tariffQuota: { current, maximum, available } }`, figures as strings.
  - `nextRefill`: `{ type, next, tariff: { amount, duration } }`, `duration` an ISO 8601 length such as `PT720H`.
- **Window:** one, `current / maximum`, both stated. `resetsAt` is `nextRefill.next` (not `quotaInfo.until`, the subscription's end). Kind `.other(seconds:)` with `reportsLength: true` when `duration` is an exact ISO 8601 length (weeks, days, hours, minutes, seconds); otherwise `.credits`, 30 days as a sort key, length not claimed.
- **Reasons:** no quota file anywhere, or a file without `quotaInfo` → `.localAppMissing`. Not XML → `.unreadableReply`. `maximum` missing or ≤ 0, or `current` missing or negative → `.noLimitsReported`.
- **Left out:** `tariffQuota.available` (CodexBar's remaining figure) — `current` of `maximum` states the same thing directly. CodexBar's custom IDE-path setting and IDE picker: Pulse has no per-provider path control, so it always picks the most recently written file. CodexBar draws 0% when `maximum` is zero; Pulse draws nothing.
- **Staleness:** the IDE rewrites the file only while running. The reading is marked live on each refresh even though the file may be old; the route note says so on the pane.
- **Evidence:** second-hand. The shape comes from CodexBar's JetBrains provider and its tests (MIT); no IDE's file on this Mac has been read. The fixture is inline in `Tests/PulseTests/JetBrainsAITests.swift`.
