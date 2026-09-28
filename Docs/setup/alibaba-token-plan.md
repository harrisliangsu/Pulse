# Set up Alibaba Token Plan in Pulse

Pulse shows your Alibaba Cloud Token Plan's rolling allowances: the 5-hour window, the weekly window and, with a recent CLI, the monthly allowance, each as the share Alibaba reports used.

## What you need

- A Token Plan subscription in Alibaba Cloud Model Studio (百炼), on the international or the China mainland site.
- Alibaba's Bailian CLI, `bl`, installed and signed in on this Mac. Pulse runs it; it does not ask you for a key or a password.

## Steps

1. Install the Bailian CLI and sign in with it, following Alibaba's instructions. Check that `bl usage token-plan --output json` works in Terminal.
2. In Pulse: **Settings → Accounts → Alibaba Token Plan**. Turn on **Show in panel**. There is nothing to paste.
3. Within a few seconds the ring appears, and the account's pane lists the windows and when each resets.

There is no site to choose. Pulse asks for the international site first and the China mainland site second, and reads whichever one your login belongs to.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Sign in with this service's own app or command-line tool first. | Pulse can't find `bl`. Install it where Pulse looks (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.npm-global/bin` or `~/.bun/bin`). |
| The saved login has expired. Sign in again with the service's own app or tool. | Sign in again with `bl`, then refresh. |
| No limits reported. | `bl` answered with no 5-hour, weekly or monthly figure. A Team plan's shared credit pool is not read yet. |
| Couldn't read the reply. | `bl` printed something Pulse doesn't recognize — often a version too old for `usage token-plan`. Update it. |
| The service didn't respond. / The service returned an error. | `bl` took longer than 15 seconds, or the console reported a failure. Try again later. |

## What Pulse reads

Pulse runs `bl usage token-plan --console-region … --console-site … --output json` with the login `bl` already saved. It passes `bl` no credential, reads none of its files, and gives it only your home folder, locale, time zone, `PATH` and proxy settings — no keys or cookies from Pulse's own environment.
