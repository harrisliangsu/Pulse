# Set up Cursor in Pulse

Pulse shows Cursor's two usage pools — "Cursor Models" (Composer and Cursor's own models) and "Other Models" (everything else) — plus, if your plan has them, an extra-spend limit and a credit balance.

## What you need

A Cursor account, signed in to the Cursor editor on this Mac. There is nothing to install beyond Cursor itself.

## Steps

1. Open Cursor and sign in with your Cursor account, if you have not already.
2. In Pulse, go to Settings → Accounts → Cursor and turn on "Show in panel". There is nothing to paste — Pulse builds its request from the sign-in Cursor's editor already stored locally.
3. Success looks like a ring for Cursor on the Pulse panel, filled in with the "Cursor Models" and "Other Models" pools.

Cursor does not support adding a second account in Pulse: usage always comes from whichever account this Mac's Cursor editor is signed in to. Note that Grok Bot is a separate Pulse provider — it is billed to the same Cursor account but has its own ring and its own sign-in.

## If it doesn't work

| Message Pulse shows | What to do |
|---|---|
| Sign in to Cursor to see usage. | Open Cursor and sign in, then click Retry. |
| Cursor's saved login was refused. Open Cursor to renew it. | Open Cursor and use it for a moment — it renews its own login automatically — then click Retry. |

## What Pulse reads

Pulse reads Cursor's own sign-in token from the editor's local database on this Mac (the same one Cursor itself uses) and sends it only to Cursor, to build the request that asks for your usage summary. Pulse does not store a Cursor credential of its own, and does not read your browser's cookies to get it.
