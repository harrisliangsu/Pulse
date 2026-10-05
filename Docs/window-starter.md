# Window starter

Owns: starting Claude Code's and Codex's usage windows as soon as they reset. Sources: `Sources/Pulse/Usage/WindowPrimer.swift` (when) and `Sources/Pulse/Providers/WindowStarter.swift` (what is sent). Pinned by `Tests/PulseTests/WindowPrimerTests.swift`.

## Why

Claude Code's five-hour window and Codex's windows start at the **first message after a reset**, not at the reset. Somebody who comes back three hours after a reset starts a fresh window then, and if they run dry waits all of it out, where a window started at the reset would already be three hours through. The starter sends one "hi" after each reset so the clock starts then.

Claude Code's weekly limit resets at a fixed hour whatever anybody does, so only its five hours are started. Codex's five hours and week both wait for a first message, so both are. Account-wide limits only; a limit scoped to one model is left alone.

## It is not the providers' feature

Off by default, per provider, in the account's pane (**Start windows automatically**). Switching it on shows a confirmation that says, in every language Pulse ships, that this is not a feature of Anthropic or OpenAI, may be treated as getting around usage limits, could get the account restricted or suspended, and that Pulse is not responsible for what happens to the account. It turns on only from that confirmation's **I understand the risk, turn it on**.

It is also the one place Pulse acts rather than reads. It holds no credential for it: it runs the provider's own command-line tool, which sends as whoever that tool is signed in as — hence the first account of each provider only.

## When (`WindowPrimer`)

**By the clock, not by guessing from the reply.** How a window that has reset but not restarted is reported differs by provider and is documented by neither. What is certain is the reset time the last reading stated. So:

- Every reading of an eligible window with a future `resetsAt` is remembered.
- Before each timer is set, the resets of a provider whose starter or account is now off are forgotten (`WindowPrimer.kept`). They were kept, and once they had passed the timer came due every five seconds for as long as Pulse ran, only for `fire` to skip them.
- A one-shot timer is set for the earliest remembered reset plus a minute's grace (`WindowPrimer.grace`), moved to the start of the allowed hours if it falls outside them.
- When it fires, a window is due if its reset and grace have passed, it is inside the hours, and the latest reading does not show a **later** reset — which would mean the user has used it since (`WindowPrimer.isDue`). One message starts every due window of the account.
- The account is then refreshed, so its new reset is remembered and the next start scheduled from it.

**Hours** (`PrimerHours`, default 07:00–23:00, shared by both providers, overnight ranges allowed, equal start and end is all day): a reset outside them is started when they begin. A window started at 3 a.m. resets at 8, while somebody is asleep, and again five hours later.

## What is sent (`WindowStarter`)

The cheapest thing that counts, and nothing kept:

| | Claude Code | Codex |
|---|---|---|
| Tool | `claude` (`CommandLocator`: `PATH`, `~/.claude/local`, then the usual installer and version-manager folders) | `codex` (`CodexAppServer.locateCodex`, including the ChatGPT and Codex apps' own) |
| Model | `--model haiku` | The cheapest in Codex's own `model/list`: one named Luna, else one described as fast, efficient or mini, else the default (`cheapestCodexModel`). Read each time, because OpenAI renames these. |
| Nothing saved | `--no-session-persistence` | `exec --ephemeral` |
| Nothing else run | `--tools ""`, `--strict-mcp-config`, `--setting-sources project` (the empty folder's settings, so none of the user's hooks — sounds, notifications, Pulse's own status line) | `-s read-only`, `model_reasoning_effort="low"` |
| Where | `~/Library/Application Support/Pulse/Window starter`, empty and Pulse's own, so no project's settings or instructions are picked up | same |

Claude Code makes a project folder for that directory under `~/.claude/projects` even with persistence off — empty, but listed with the user's own. It is removed afterwards when it holds no file (`removeEmptyClaudeProject`); anything with a file in it is left alone.

Measured 2026-09-27: Codex answered in about eight seconds on `gpt-5.6-luna` at low effort, 7,876 tokens (mostly Codex's own instructions), and wrote no session file (136 before and after). Claude Code's run failed with "OAuth session expired and could not be refreshed" — the CLI's login on that Mac had lapsed while the desktop app's had not — which is reported in the pane rather than retried.

## What the pane shows

**Last started**: the time of the last attempt and, when it did not go through, why — the tool not found, not signed in or failing, or not answering within two minutes (`WindowStarter.deadline`). Stored in `AppSettings.primerRunTimes` / `primerRunOutcomes`. A failure is not retried until the next reset.
