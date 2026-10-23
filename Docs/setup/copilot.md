# Set up GitHub Copilot in Blinky

Blinky shows how much of your monthly GitHub Copilot request quota is left, split into three allowances: Premium requests, Chat, and Completions (whichever ones your plan actually has).

## What you need

Any GitHub Copilot plan — Free, Pro, Pro+, Business, or Enterprise — and a GitHub account you can sign in to in a browser.

## Steps

1. In Blinky, go to Settings → GitHub Copilot and turn on "Show in panel".
2. In the same pane, under "GitHub account", click "Sign in…".
3. Blinky copies a short code to your clipboard and opens GitHub's device sign-in page in your browser. If you're not already signed in to GitHub, sign in first. Paste the code when the page asks for it (GitHub never pre-fills this for you — that's deliberate on their side), then click "Authorize".
4. Back in Blinky, the "GitHub account" row updates to "Signed in. Blinky holds a read-only token for this Mac." and a ring for GitHub Copilot fills in on the Blinky panel.

Blinky only asks GitHub for `read:user` access — it can't see or touch your repositories or Copilot's own request logs beyond the quota numbers.

## If it doesn't work

| Message Blinky shows | What to do |
|---|---|
| Sign in to this account again in Settings. | Click "Sign in again…" and repeat the steps above. |
| The service didn't respond. | Click Retry — likely a temporary network hiccup. |
| Checking too often — easing off. | Click Retry after a minute; Blinky is pausing to avoid hammering GitHub. |
| The service returned an error. | Click Retry. If it keeps happening, GitHub's side may be having issues. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/harrisliangsu/blinky-mac/issues). |
| No limits reported. | This plan didn't report any of the three quotas Blinky looks for. |

## What Blinky reads

Your GitHub sign-in token is stored encrypted on this Mac and sent only to GitHub, with your Copilot request headers attached, to ask for your current quota. Blinky never sees your code or your Copilot chat history.
