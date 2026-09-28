# Set up GitKraken AI in Pulse

Pulse shows your GitKraken AI credits: how much of your allowance is used, and your organization's shared pool beside it when there is one.

## What you need

A GitKraken account with AI credits. GitKraken issues no API key for this; Pulse uses the access token GitKraken's own usage page sends, which you copy by hand. It expires, and then you copy a fresh one.

## Steps

1. Sign in at [gitkraken.dev/account#ai-usage](https://gitkraken.dev/account#ai-usage). Open your browser's developer tools (Network tab), reload the page, and select the request to `api.gitkraken.dev/v1/ai-tasks/usage`. Copy the value of its **Authorization** header — everything after `Bearer `. (Pasting it with `Bearer ` in front is fine too.)
2. In Pulse: **Settings → Accounts → GitKraken AI**. Turn on **Show in panel**. Under **Connection**, paste the token into **API key** and click **Save**.
3. Within a few seconds the ring appears, and the account's pane lists your credits (and the organization's pool) and when they reset.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste the token from the usage request. |
| That key was refused. Check it in Settings. | The token has expired or was copied incompletely. Copy a fresh one the same way. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | GitKraken sent something Pulse doesn't recognize, or your allowance is unlimited or zero — neither has a percentage to show. |

## What Pulse reads

Your token is stored encrypted on this Mac and sent only to GitKraken's own API (`api.gitkraken.dev`) when Pulse checks your usage. It reads your token's default organization; picking another organization isn't supported yet.
