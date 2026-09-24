# Set up V2EX in Pulse

Pulse shows your V2EX AI Chat allowance: tokens used out of your current 5-hour quota window, plus a second "top-up" allowance if you've bought one. V2EX's window doesn't start running until you actually send a chat message, so a ring showing 0% used with no countdown just means the window hasn't started yet — not a problem.

## What you need

A V2EX account with AI Chat access.

## Steps

1. Sign in at https://v2ex.com, then go to https://v2ex.com/settings/tokens (also reachable from the site's help pages under "个人访问令牌" / Personal Access Token). Create a new token, choosing an expiry of up to 180 days, and copy it right away — V2EX only shows the full token for about ten minutes after you create it.
2. In Pulse, go to Settings → Accounts → V2EX and turn on "Show in panel". Paste the token into "API key" and click Save.
3. Success looks like a ring for V2EX on the Pulse panel, showing tokens used in your current 5-hour window (and a second ring for your top-up pack, if you have one).

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Add an API key in Settings. | Paste your Personal Access Token into "API key". |
| That key was refused. Check it in Settings. | The token is wrong or has expired (V2EX tokens last at most 180 days). Create a new one at v2ex.com/settings/tokens and paste it in. |

## What Pulse reads

Pulse sends your Personal Access Token as a bearer token to `https://edge.v2ex.com/api/v2/chat/quota` and reads back your current window's totals. Checking this never starts a new window on its own. The token is kept encrypted on this Mac (`keys.dat`) and sent only to V2EX.
