# UI

The panel is SwiftUI inside a transparent, non-activating AppKit `NSPanel`. AppKit owns size, placement, and real mouse input.

| Doc | Owns |
|---|---|
| [panel-geometry.md](panel-geometry.md) | Frame, overlay vs stack, dock/float, top edge, scale, active display |
| [input.md](input.md) | Hover, drag, ring click, pointer hit testing, rail right-click menu, global shortcuts |
| [rings-and-surface.md](rings-and-surface.md) | Glass, colours, activity mark, halo, countdown |
| [settings.md](settings.md) | Settings window chrome and copy, shortcut fields, per-account panes |

- **Token spend in Settings**: agents, model details, daily/hourly history and chart hover live in [../token-spend.md](../token-spend.md); source formats and evidence live in [../token-spend-sources.md](../token-spend-sources.md). Per-account history is owned by [../refresh-and-data.md](../refresh-and-data.md).
- **Settings access without the menu bar**: rail right-click and global shortcut mechanics are in [input.md](input.md); their settings controls and copy are in [settings.md](settings.md).

Why the frame never grows with a card, why `.onHover` is banned, and why glass drag is not “verified”: [../decisions/README.md](../decisions/README.md).
