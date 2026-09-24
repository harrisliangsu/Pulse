# Set up Antigravity in Pulse

Pulse shows Antigravity's quota buckets — a 5-hour and a weekly limit for Gemini models, and the same pair for Claude/GPT models — plus your plan name.

## What you need

Antigravity (the desktop app or the standalone IDE), installed, signed in, and **running**. There is no separate credential to add: Pulse can only read these figures while something of Antigravity's is open.

## Steps

1. Download Antigravity from https://antigravity.google/download, install it, open it, and sign in.
2. In Pulse, go to Settings → Accounts → Antigravity and turn on "Show in panel". There is nothing to paste — Pulse talks to Antigravity's own local server while it is running. If you want separate rings for your Gemini allowance and your Claude/GPT allowance instead of one combined ring, turn on "A ring for each model group" in the same pane.
3. Success looks like a ring for Antigravity on the Pulse panel while Antigravity is open. It shows no reading while Antigravity is closed — that is expected, not a fault.

Antigravity does not support adding a second account in Pulse.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Open Antigravity to see its usage. | Open Antigravity (the app or the IDE) and sign in. |
| Antigravity is open but didn't answer. Restarting it usually helps. | Quit and reopen Antigravity, then click Retry. |
| No limits reported. | Refresh again once Antigravity has fully started; if it persists, confirm your account has an active plan in Antigravity itself. |

## What Pulse reads

While Antigravity is running, Pulse asks its local language-server process — over this Mac's own loopback address, not the internet — for your quota summary, using a connection token that process generated for this run only. Pulse stores no Antigravity credential and reads nothing while Antigravity is closed.
