# Set up Codebuff in Pulse

Pulse shows your Codebuff credits: how much of your credit quota is used and when it resets, and how many credits are left. When Pulse uses the `codebuff` CLI's own login, it also shows your weekly limit and your plan.

## What you need

Either the `codebuff` command-line tool signed in on this Mac (`codebuff login`), or an API key from [codebuff.com](https://www.codebuff.com).

## Steps

1. Either run `codebuff login` in a terminal, or create an API key on codebuff.com.
2. In Pulse: **Settings → Accounts → Codebuff**. Turn on **Show in panel**. If you created a key, paste it into **API key** under **Connection** and click **Save**. A pasted key is used before the CLI's login.
3. Within a few seconds the ring appears, and the account's pane lists the credits and, with the CLI's login, the weekly limit.

An API key reads the credits only; the weekly limit and the plan come with the CLI's login.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key, or run `codebuff login`. |
| That key was refused. Check it in Settings. | The pasted key was refused. Create a fresh one and paste it again. |
| The saved login has expired. Sign in again with the service's own app or tool. | The CLI's login was refused. Run `codebuff login` again. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Codebuff sent something Pulse doesn't recognize, or reported no credits. |

## What Pulse reads

A pasted key is stored encrypted on this Mac. Otherwise Pulse reads the token in `~/.config/manicode/credentials.json` each time it checks, without changing it. Either way the token is sent only to Codebuff (`www.codebuff.com`).
