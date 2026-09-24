# Set up Codex in Pulse

Pulse shows Codex's usage windows (for example a 5-hour and a weekly limit — which ones exist depends on your plan) and your plan name (for example "Plus", "Pro 5x", "Team").

## What you need

A ChatGPT plan that includes Codex, signed in to the Codex CLI (`codex`).

## Steps

1. Install the Codex CLI and run `codex login` in Terminal. It opens your browser to sign in with your ChatGPT account; approve there. On a machine with no browser, run `codex login --device-auth` instead and enter the code at https://auth.openai.com/codex/device.
2. In Pulse, go to Settings → Accounts → Codex and turn on "Show in panel". Nothing else is required — Pulse reads the login Codex already saved in `~/.codex/auth.json`. If you want to see or change which route Pulse uses, the Connection group's "Read usage from" picker offers Automatic, Usage endpoint, and Provider tooling (Codex's own app-server helper); Automatic is the right choice for almost everyone.
3. To add a second Codex account, go to Settings → Accounts → Codex, and click "Add another account" in its Accounts group. Pulse shows a short code — type it on the page that opens. This is a separate device-code sign-in from the CLI's own login, so both accounts keep reporting even if the CLI's token later expires.
4. Success looks like a ring for Codex on the Pulse panel, filled in with your usage windows.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in to Codex to see usage. | Run `codex login` in Terminal, then click Retry. |
| Codex isn't installed. | Install the Codex CLI, then click Retry. |
| Couldn't start the Codex helper. | Click Retry. If it keeps failing, quit and reopen Codex (or restart your Mac) and try again. |
| Sign in to this account again in Settings. (on an added account) | Open that account's Accounts section and click "Sign in again…". |

## What Pulse reads

Pulse reads the OAuth login Codex's CLI already stored in `~/.codex/auth.json` on this Mac, and sends it only to OpenAI to ask for your usage. An account added through "Add another account" is signed in separately through a device code, and its login is stored on this Mac only.
