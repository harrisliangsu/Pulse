# Set up Nous Portal in Pulse

Pulse shows your Nous Portal subscription's monthly credit grant as a ring (how much of this month's grant is used, and when it renews) and the credit you can still spend as a balance.

## What you need

[Hermes Agent](https://github.com/NousResearch/hermes-agent) signed in to Nous Portal on this Mac. Nous Portal's account page only accepts the login Hermes makes; a Nous API key can't read it, so there is no key to paste.

## Steps

1. In a terminal, run `hermes` and choose Nous Portal (or `hermes auth add nous`), and finish signing in. Hermes saves the login in `~/.hermes/auth.json`.
2. In Pulse: **Settings → Accounts → Nous Portal**. Turn on **Show in panel**.
3. Within a few seconds the ring appears, and the account's pane shows the plan, the balance and when the grant renews.

Hermes's login lasts about an hour, and Pulse never renews it (renewing it from a second app would sign Hermes out). Using Hermes renews it; any `hermes` command will do.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Sign in with this service's own app or command-line tool first. | Sign in to Nous Portal with Hermes Agent (step 1). |
| The saved login has expired. Sign in again with the service's own app or tool. | Run any `hermes` command so Hermes renews its login, then refresh Pulse. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. / No limits reported. | Nous sent something Pulse doesn't recognize, or the account has neither a monthly grant nor a balance. |

## What Pulse reads

Pulse reads the access token from `~/.hermes/auth.json` (or Hermes's shared copy, `~/.hermes/shared/nous_auth.json`) and sends it only to Nous Portal (`portal.nousresearch.com`, or another `nousresearch.com` address Hermes saved). Pulse doesn't store the token, doesn't change Hermes's files and doesn't renew the login.
