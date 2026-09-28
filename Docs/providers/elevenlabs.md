# ElevenLabs

Profiled provider: [`Sources/Pulse/Providers/Profiled/ElevenLabsUsageService.swift`](../../Sources/Pulse/Providers/Profiled/ElevenLabsUsageService.swift). User setup: [../setup/elevenlabs.md](../setup/elevenlabs.md).

- **Credential:** an API key the user pastes, which needs `user_read`. Nothing is read from this Mac.
- **Route:** `GET https://api.elevenlabs.io/v1/user/subscription`, key in the `xi-api-key` header (not a bearer).
- **Reply:** `{ tier, status, character_count, character_limit, next_character_count_reset_unix, voice_slots_used, voice_limit, professional_voice_slots_used, professional_voice_limit, current_overage }`.
- **Windows:** one `.credits` window, used = `character_count` / `character_limit`, reset from `next_character_count_reset_unix` (epoch seconds). The billing period's length is not stated, so 30 days is a sort key only (`reportsLength: false`). A limit of 0 draws nothing (CodexBar draws 0%).
- **Plan:** `tier`, underscores to spaces, capitalized.
- **Left out:** voice slots and professional voice slots — a count of voices kept, not an allowance spent over time, and no window kind reads as one. CodexBar's distinct messages for a 401/403 carrying `invalid_api_key` versus `missing_permissions` collapse to Pulse's shared "That key was refused"; the setup page names the permission.
- **Evidence:** second-hand. The shape comes from CodexBar's ElevenLabs plugin and docs (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/elevenlabs-subscription.json`.
