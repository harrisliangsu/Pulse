# Hugging Face

Profiled provider: [`Sources/Pulse/Providers/Profiled/HuggingFaceUsageService.swift`](../../Sources/Pulse/Providers/Profiled/HuggingFaceUsageService.swift). User setup: [../setup/hugging-face.md](../setup/hugging-face.md).

- **Credential:** `apiKey(optional: true)`. The pasted token first (401/403 → `.apiKeyRefused`); otherwise the first line of `~/.cache/huggingface/token`, which `hf auth login` writes (401/403 → `.localLoginExpired`). Neither → `.apiKeyMissing`. The file is only read.
- **Route:** `GET https://huggingface.co/api/spaces/zero-gpu/quota`, bearer token. A documented Hub endpoint.
- **Reply:** `{ base, current, resetsAt }` — the quota and what is left of it, in seconds of GPU time; `resetsAt` as ISO 8601 or seconds since 1970. Not a JSON object → unreadable.
- **Window:** one, `.daily`, scope "ZeroGPU": used = `max(0, base − current) / base`, only when `base > 0` and `current ≥ 0` are both reported; exhausted at `current ≤ 0`. Hugging Face's docs call it a daily quota that "resets exactly 24 hours after your first GPU usage", but the reply states only the reset — so 24 h is a sort key (`reportsLength: false`), the same way Kimi's weekly window is kept. No quota (`base` 0) or a figure that isn't one → "No limits reported".
- **Left out:**
  - Inference Providers charges (`GET /api/settings/billing/usage-v2?startDate=&endDate=`: `usedNanoUsd`, `includedNanoUsd`, `limitNanoUsd`). CodexBar shows `max(0, used − included)` as billable and the spending limit beside it, but draws no percentage; Pulse would have to decide what the limit is measured against, so neither the charges nor a ring are shown, and the request is not made.
  - The prepaid credit wallet: only on `/settings/billing` behind a browser session, trusted by CodexBar only after matching the session's `whoami-v2` id against the token's. One Pulse credential cannot be both a token and a session.
  - Plan (PRO/Free) from `whoami-v2`, which Hugging Face rate-limits hard; not worth a second request per refresh.
  - `HF_TOKEN`, `HF_HOME`, `HF_TOKEN_PATH`, `XDG_CACHE_HOME` — a menu-bar app does not see a shell's environment.
- **Icon:** Lobe Icons `huggingface` (monochrome). Brand colour `#FFD21E`, Hugging Face's yellow.
- **Evidence:** second-hand. The shape comes from CodexBar's Hugging Face plugin (`huggingface.ts`), `HuggingFaceSettingsReader` and their tests (MIT); no live account has been read. Fixture: `Tests/PulseTests/Fixtures/hugging-face-zero-gpu-quota.json`.
