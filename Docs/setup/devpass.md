# Set up DevPass in Pulse

Pulse shows your DevPass plan's credits for the billing cycle, the premium models' weekly allowance, and — if your key has one — the key's own spending limit.

## What you need

An LLM Gateway account and a regular API key. Publishable keys can't read plan state.

## Steps

1. Sign in at [llmgateway.io](https://llmgateway.io) and create or copy an API key.
2. In Pulse: **Settings → Accounts → DevPass**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the pane lists the weekly limit, the credit allowance and any spend limit.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from llmgateway.io. |
| That key was refused. Check it in Settings. | The key is inactive or a publishable key. Paste a regular API key. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| This account has no plan with usage limits. | The account is pay as you go and the key has no spending limit. |
| Couldn't read the reply. / No limits reported. | LLM Gateway sent something Pulse doesn't recognize, or every allowance is zero. |

## What Pulse reads

Your key is stored encrypted on this Mac and sent only to LLM Gateway's own API (`api.llmgateway.io`) when Pulse checks your usage.
