# Set up Grok Bot in Pulse

Pulse shows your weekly Grok Bot allowance — xAI's assistant sold through Cursor and billed against your **Cursor** account, not your Grok/SuperGrok account. It's a different bill from the "Grok" ring — see [Grok setup](grok.md) if that's the one you're after.

## What you need

Grok Bot access through Cursor Pro, Cursor Pro+, Cursor Ultra, a Cursor Teams seat, or a linked SuperGrok/X Premium+ account — and Cursor signed in on this Mac (the editor, or the standalone Grok Bot app, both use the same Cursor login).

## Steps

1. Make sure you're signed in to Cursor on this Mac — open Cursor (or the Grok Bot app) and sign in if you haven't already.
2. In Pulse, go to Settings → Accounts → Grok Bot and turn on "Show in panel". There's nothing to paste: the "Read usage from" row says "Cursor's own login", because Pulse borrows the session Cursor already saved.
3. Refresh Pulse (or wait for its next automatic check). A ring for Grok Bot fills in on the Pulse panel once Cursor's login is readable.

### Adding another account

If you have more than one Cursor account with Grok Bot, go to Settings → Accounts → Grok Bot, and click "Add another account" in its Accounts group, then "Sign in…". Pulse opens Cursor's own sign-in page in your browser — sign in there. This login is kept separately from the one Cursor's app uses, and lasts about 60 days before you'll need to sign in again.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in to Cursor to see usage. | Click "Open Cursor" and sign in there. |
| Cursor's saved login was refused. Open Cursor to renew it. | Click "Open Cursor" and sign in again. |
| This Cursor plan doesn't include Grok Bot. | Your current Cursor/Grok plan doesn't include a Grok Bot allowance. |
| Sign in to this account again in Settings. (added accounts) | Click "Sign in again…" next to that account. |
| The service didn't respond. | Click Retry. |
| Checking too often — easing off. | Click Retry after a minute. |
| The service returned an error. | Click Retry. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/harrisliangsu/Pulse/issues). |

## What Pulse reads

For your main account, Pulse reads the login Cursor's own app already stored on this Mac — nothing is pasted and nothing extra is saved. For added accounts, Pulse keeps the sign-in it obtained through Cursor's own login page, encrypted on this Mac.
