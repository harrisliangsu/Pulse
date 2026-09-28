# Set up Chutes in Pulse

Pulse shows your Chutes subscription's usage: the rolling window and the monthly allowance, each as used out of the limit Chutes reports.

## What you need

A Chutes subscription and an API key (`cpk_…`). Pay-as-you-go accounts without a subscription have no allowance for Pulse to show.

## Steps

1. Sign in at [chutes.ai](https://chutes.ai) and create an API key (see Chutes' [authentication guide](https://chutes.ai/docs/getting-started/authentication)).
2. In Pulse: **Settings → Accounts → Chutes**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists each allowance and when it resets.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from chutes.ai. |
| That key was refused. Check it in Settings. | Create a fresh key and paste it again. |
| This account has no plan with usage limits. | Chutes says the account has no active subscription. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Chutes sent something Pulse doesn't recognize, or reported no allowance with a stated length. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to Chutes' own API (`api.chutes.ai`) when Pulse checks your usage.
