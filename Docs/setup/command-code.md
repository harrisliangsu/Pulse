# Set up Command Code in Pulse

Pulse shows Command Code's spending: your 5-hour and weekly rolling limits, any organization spend limits, and your credit balance. If you're on a running subscription plan, it also shows an estimated monthly limit — marked "estimated" on screen, because Command Code doesn't report the size of your plan's monthly grant, only what's left of it.

## What you need

A Command Code account (free to create) at [commandcode.ai](https://commandcode.ai), and either the Command Code CLI signed in, or an API key from your account's Studio page.

## Steps

Turn on the provider first: go to Settings → Accounts → Command Code and turn on "Show in panel". Then connect it one of two ways — a key you paste wins if both are present, since a key you typed on purpose shouldn't be overridden by a stale CLI login.

**Option A — the CLI's own login (no pasting required)**
1. Install the CLI: `npm install -g command-code@latest`. Check it with `cmd --version` (on native Windows it's `cmdc` instead of `cmd`).
2. Run `cmd login`. It opens your browser — sign in and click "Authorize". Your terminal confirms "API key stored in ~/.commandcode/auth.json".
3. Back in Settings → Accounts → Command Code, there's nothing to enter — Pulse reads that saved login automatically. Refresh Pulse and a ring for Command Code fills in.

**Option B — a pasted API key**
1. Sign in to Command Code at [commandcode.ai](https://commandcode.ai), then go to your [API keys page](https://commandcode.ai/studio/) and click "Generate API key".
2. In Settings → Accounts → Command Code, in the "API key" field, paste the key, then click "Save".

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Add an API key in Settings. | Paste a key (Option B), or sign in with the CLI (Option A) instead. |
| That key was refused. Check it in Settings. | Re-check the key for typos, or generate a fresh one from your API keys page. |
| The service didn't respond. | Click Retry. |
| Checking too often — easing off. | Click Retry after a minute. |
| The service returned an error. | Click Retry. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/harrisliangsu/Pulse/issues). |
| No limits reported. | Your account may not have any windows, plan, or balance to report yet. |

## What Pulse reads

A pasted key is stored encrypted on this Mac and sent only to Command Code's account API. If you sign in with the CLI instead, Pulse reads the key the CLI already saved at `~/.commandcode/auth.json` on this Mac — it doesn't hold a separate copy.
