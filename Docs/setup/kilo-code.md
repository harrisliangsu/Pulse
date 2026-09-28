# Set up Kilo Code in Pulse

Pulse shows your Kilo Code credit balance and, if you have a Kilo Pass, how much of this billing period's pass credits (base plus bonus) you have used.

## What you need

A Kilo Code account. Either an API key from Kilo, or the Kilo CLI signed in on this Mac.

## Steps

1. Sign in at [app.kilo.ai](https://app.kilo.ai) and copy your API key from your profile page. (Or skip this if you use the Kilo CLI and have run `kilo auth login`.)
2. In Pulse: **Settings → Accounts → Kilo Code**. Turn on **Show in panel**. Under **Connection**, paste the key into **API key** and click **Save**. With no key, Pulse uses the Kilo CLI's login instead.
3. Within a few seconds the account appears. With a Kilo Pass there is a ring for the pass; the balance is shown either way.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Add an API key in Settings. | Paste a key from app.kilo.ai, or sign in with the Kilo CLI (`kilo auth login`). |
| That key was refused. Check it in Settings. | Copy the key again from app.kilo.ai and paste it. |
| Sign in with this service's own app or command-line tool first. | The Kilo CLI's login file has no token. Run `kilo auth login`, or paste a key. |
| The saved login has expired. Sign in again with the service's own app or tool. | Run `kilo auth login` again, or paste a key. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Kilo sent something Pulse doesn't recognize, or reported neither a balance nor a pass. |

## What Pulse reads

A pasted key is stored encrypted on this Mac. Without one, Pulse reads the token in `~/.local/share/kilo/auth.json` and never writes to it. Either is sent only to Kilo's own service (`app.kilo.ai`) when Pulse checks your usage. Organization accounts aren't shown yet — only your personal one.
