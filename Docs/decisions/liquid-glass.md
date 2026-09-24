# Liquid Glass: diagnosis uncertain

**Status:** current implementation is hit-testable `PanelSurface` + `FloatingPanel.sendEvent`. **Evidence:** historical measurements of materials; drag diagnosis **uncertain**; real input **not** re-verified.

## What we still believe

Black default: the panel sits over work all day. ~~No scrim~~ — superseded once the glass rendered active (below): clear glass does not manage its own legibility, so it is dimmed (`PanelGlass.dim`, black 0.3) and the panel is pinned dark on both surfaces. Measured on 26.7 over white / busy / black: undimmed white text vanished over white; 0.15–0.35 all readable, 0.3 chosen as the least grey over white that still reads. (The historical "black tint barely moved luminance" was on the frosted rendering.)

`Glass.clear` not `.regular`. Historical: five variants in a transparent panel over a bright busy backdrop — SwiftUI `.regular` opaque milky white; `NSVisualEffectView` worse; `.clear` and `NSGlassEffectView` kept content visible. All five *did* sample behind the window, so a transparent `NSPanel` was not the problem. `NSGlassEffectView` was pixel-for-pixel the same material but only knows a corner radius; the modifier takes the morphing shape.

Halo: opaque disc over blur is invisible on black and a white coin on glass. Historical checkerboard: clearing 213/205/212 with the disc vs 193/128/181 with a mask. Shadow on the composed view leaked usage colour through the icon’s antialiased edge (green cast +16 over neutral on a 35% ring, +0 unhovered).

## What we no longer assert

The first write-up treated rings-only drag with glass on as a **system** bug: macOS 26 material implementing interactivity outside SwiftUI’s hit-testing chain (developer.apple.com/forums/thread/816366). `.allowsHitTesting(false)`, `.disabled(true)`, opaque ink above and below were tried; none helped. `hitTest` and synthesised events reported the handle reachable throughout.

**Suspect that was never a glass bug.** The same symptom (“only the rings can be dragged”) is exactly what the SwiftUI-hosted handle produced on the **black** panel once the berth stopped claiming presses. Window-owned events give the material no say. If dragging works on glass, the settings caption (“Drag it by a ring while this is on.”) and this suspicion should be revisited — **after real input**, not after another probe.

This cannot be reproduced in a harness: probes bypass whatever the material installs. When a symptom survives every local probe, that is not evidence it is glass.

## Frosted, not liquid: the active-appearance gate

For its whole life the panel's glass never looked like Liquid Glass — a uniform frosted blur, text behind it a smear — and the setting was renamed "frosted glass" to match. Harness on 26.7, every case over the same busy text, one window per process:

- SwiftUI `.clear` / `.regular`, AppKit `NSGlassEffectView` `.clear` / `.regular`, inside `GlassEffectContainer`, dark scheme, glass in the **same** window as the backdrop, sizes 44pt to 160×220 — all frosted in a window that cannot become key.
- Key-eligible (`canBecomeKey` `true`, `becomesKeyOnlyIfNeeded` `false`): liquid — but **only until the app has once been active and then lost it**. After that every window the app owns, new ones included, is frosted. With several key-eligible windows at once, only one rendered liquid.
- Forcing `\.appearsActive` / `\.controlActiveState` in the environment, re-ordering the window, rebuilding it or its content view after deactivation: no effect.
- Overriding private `NSWindow` methods in the panel subclass, after activate → deactivate: `_hasActiveAppearance`, `_hasActiveAppearanceIgnoringKeyFocus` and `hasKeyAppearance` → liquid; `_hasKeyAppearance` → still frosted. `_hasActiveAppearanceIgnoringKeyFocus` stays liquid with `canBecomeKey` `false` and `becomesKeyOnlyIfNeeded` `true`, so the panel's focus behaviour is untouched. That is what shipped.

So every earlier measurement on this page (`.regular` "opaque milky white", `.clear` "kept content visible") was taken on the **inactive** rendering. With the gate open, `.clear` is still the clearer of the two.

Why the narrowest-sounding selector: `_hasActiveAppearance` also worked but reads as broader (window controls, shadows). The panel has no controls either way.

Current rules: [../ui/rings-and-surface.md](../ui/rings-and-surface.md), [../ui/input.md](../ui/input.md).
