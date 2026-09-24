# Set up OpenCode Go in Pulse

Pulse shows how much of your OpenCode Go plan is left: the 5-hour limit, the weekly limit, and the monthly limit.

## What you need

An OpenCode Go subscription ($10/month). You don't need to install anything — a key is enough — but if you already use the `opencode` CLI and signed in there, Pulse can pick that up automatically (see below).

## Steps

1. Open [opencode.ai/auth](https://opencode.ai/auth) and sign in (or create an account). Add a payment method if you haven't, then copy the API key shown there.
   - Already signed in through the `opencode` CLI (`opencode auth login`, or `/connect` inside it)? You can skip this — Pulse reads the key OpenCode already saved for itself.
2. In Pulse: **Settings → Accounts → OpenCode Go**. Turn on **Show in panel** if it isn't already. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the OpenCode Go ring appears on the panel, and the account's pane lists the 5-hour, weekly and monthly limits.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Nothing was pasted, and Pulse couldn't find a key OpenCode saved for itself either. Paste a key from opencode.ai/auth. |
| That key was refused. Check it in Settings. | The key isn't valid here. Get a fresh one from opencode.ai/auth and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | OpenCode sent something Pulse doesn't recognize yet. Nothing you can fix locally — try again later. |

## What Pulse reads

Your key is stored encrypted on this Mac. If the field in Settings is left blank, Pulse looks for the key OpenCode's own CLI saved for itself after you signed in there — nothing is sent anywhere unless a key exists one way or the other. The key is sent only to OpenCode's own servers when Pulse asks for your usage.
