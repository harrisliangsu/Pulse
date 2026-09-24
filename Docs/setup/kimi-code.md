# Set up Kimi Code in Pulse

Pulse shows your Kimi Code plan's limits: the timed windows your plan states (for example a 5-hour or 3-hour limit) and your weekly allowance.

## What you need

A Kimi Code membership (Moonshot AI's coding plan).

## Steps

1. Open [www.kimi.com/code/console](https://www.kimi.com/code/console) — the **Kimi Code Console**, linked from Kimi Code's own docs — and sign in with your Kimi account. Create an API key there.
   - Use a key from this console, not from Moonshot's general API platform (`platform.kimi.ai`). That's a separate product billed per token; it's meant for building your own apps, not for reading your Kimi Code plan's windows. <!-- unverified: whether a platform.kimi.ai key is actively refused by Pulse's endpoint, or simply reads differently — not confirmed against a live account -->
2. In Pulse: **Settings → Accounts → Kimi Code**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists your plan's windows and your weekly allowance.

Kimi Code has no local fallback the way OpenCode Go does — there's nothing Pulse can find on its own, so a key has to be pasted.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key created in the Kimi Code Console. |
| That key was refused. Check it in Settings. | The key isn't valid here — create a fresh one in the Kimi Code Console and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Kimi sent something Pulse doesn't recognize, or your plan currently has no windows to report. Try again later. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Kimi's own service when Pulse checks your usage.
