# Set up Amp in Pulse

Pulse shows what Amp reports for your account: Amp Free's allowance, a paid tier's monthly agent allowance and its Orb hours, and your individual credit balance.

## What you need

An Amp account at [ampcode.com](https://ampcode.com). Amp Free, a paid tier, or credits — whichever the account has is what shows.

## Steps

1. Sign in at [ampcode.com/settings](https://ampcode.com/settings) and create an access token.
2. In Pulse: **Settings → Accounts → Amp**. Turn on **Show in panel**. Under **Connection**, paste the token into **API key** and click **Save**.
3. Within a few seconds the ring appears. The account's pane lists each allowance and, on a paid tier, when the billing period renews. Individual credits show as a balance.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste an access token from ampcode.com/settings. |
| That key was refused. Check it in Settings. | The token was revoked or has expired. Create a fresh one and paste it again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Amp sent its usage in a form Pulse doesn't recognize. Running `amp usage` in a terminal shows what it says. |

## What Pulse reads

Your token is stored encrypted on this Mac and sent only to Amp's own service (`ampcode.com`) when Pulse checks your usage. Pulse asks the same question `amp usage` asks and reads the lines it answers with. It doesn't run the Amp CLI or read its files. Workspace credit balances aren't shown.
