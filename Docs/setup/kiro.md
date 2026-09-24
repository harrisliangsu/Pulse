# Set up Kiro in Pulse

Pulse shows Kiro's subscription credit pools (for example vibe or spec credits) as monthly windows, using the totals and limits Kiro itself reports, plus your plan name and billing-cycle reset date.

## What you need

Kiro CLI, installed and signed in, on a plan that reports usage.

## Steps

1. Install Kiro CLI (`curl -fsSL https://cli.kiro.dev/install | bash`, or Homebrew if you already use it for other tools), then run `kiro-cli login` and choose your sign-in method (AWS Builder ID, Google, GitHub, or your organization) in the browser that opens. On a machine with no browser, use `kiro-cli login --device` instead.
2. In Pulse, go to Settings → Accounts → Kiro and turn on "Show in panel". There is nothing to paste: Pulse asks Kiro CLI itself for your usage over its own local protocol, the same way Kiro's own `/usage` panel does.
3. Success looks like a ring for Kiro on the Pulse panel, filled in with your credit pools.

Kiro does not support adding a second account in Pulse.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Kiro CLI isn't installed. | Install Kiro CLI (step 1), then click Retry. |
| Update Kiro CLI to read subscription usage. | Update Kiro CLI to the latest version, then click Retry. |
| Sign in to Kiro CLI to see usage. | Run `kiro-cli login`, then click Retry. |
| No limits reported. | Check that your Kiro account has a subscription plan with usage limits — Kiro's own usage view will show the same thing. |

## What Pulse reads

Pulse starts a short-lived Kiro CLI process, asks it for your usage over its own local protocol, and closes it again. Pulse does not open Kiro's database, request Keychain access, copy an access token, or store any Kiro credential — Kiro itself stays responsible for signing you in and keeping you signed in.
