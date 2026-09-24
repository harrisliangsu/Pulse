# Set up GitHub Copilot in Pulse

Pulse shows how much of your monthly GitHub Copilot request quota is left, split into three allowances: Premium requests, Chat, and Completions (whichever ones your plan actually has).

## What you need

Any GitHub Copilot plan — Free, Pro, Pro+, Business, or Enterprise — and a GitHub account you can sign in to in a browser.

## Steps

1. In Pulse, go to Settings → Accounts → GitHub Copilot and turn on "Show in panel".
2. In the same pane, under "GitHub account", click "Sign in…".
3. Pulse copies a short code to your clipboard and opens GitHub's device sign-in page in your browser. If you're not already signed in to GitHub, sign in first. Paste the code when the page asks for it (GitHub never pre-fills this for you — that's deliberate on their side), then click "Authorize".
4. Back in Pulse, the "GitHub account" row updates to "Signed in. Pulse holds a read-only token for this Mac." and a ring for GitHub Copilot fills in on the Pulse panel.

Pulse only asks GitHub for `read:user` access — it can't see or touch your repositories or Copilot's own request logs beyond the quota numbers.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in to this account again in Settings. | Click "Sign in again…" and repeat the steps above. |
| The service didn't respond. | Click Retry — likely a temporary network hiccup. |
| Checking too often — easing off. | Click Retry after a minute; Pulse is pausing to avoid hammering GitHub. |
| The service returned an error. | Click Retry. If it keeps happening, GitHub's side may be having issues. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/harrisliangsu/Pulse/issues). |
| No limits reported. | This plan didn't report any of the three quotas Pulse looks for. |

## What Pulse reads

Your GitHub sign-in token is stored encrypted on this Mac and sent only to GitHub, with your Copilot request headers attached, to ask for your current quota. Pulse never sees your code or your Copilot chat history.
