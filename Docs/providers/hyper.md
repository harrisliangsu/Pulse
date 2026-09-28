# Hyper

Profiled provider: [`Sources/Pulse/Providers/Profiled/HyperUsageService.swift`](../../Sources/Pulse/Providers/Profiled/HyperUsageService.swift). User setup: [../setup/hyper.md](../setup/hyper.md).

- **Credential:** an API key the user pastes. Nothing is read from this Mac.
- **Route:** `GET https://hyper.charm.land/v1/credits`, bearer token.
- **Reply:** `{ balance }`, a non-negative number of Hypercredits. Anything else is "Couldn't read the reply".
- **Windows:** none. The balance goes in `creditBalance` as `<number> HC` (HC is Charm's own unit name, left untranslated). Hypercredits are not money, so there is no `creditRemaining` and `reportsSpendableBalance` is off.
- **Left out:** CodexBar's browser-session route for hyper.charm.land, tried before the key. Pulse has one credential per provider and the key reaches the same figure.
- **Evidence:** second-hand. The shape comes from CodexBar's Hyper plugin and docs (MIT); no live account has been read. The fixture is `Tests/PulseTests/Fixtures/hyper-credits.json`.
