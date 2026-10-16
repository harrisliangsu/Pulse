# Settings window: System Settings' title bar

**Decided 2026-10-15, macOS 26.7.** Current rules: [../architecture.md](../architecture.md#settings-window) (the settings window section). This page is how they were found, so the next person does not walk the same dead ends.

## What was wanted

System Settings' look: the sidebar running up behind the traffic lights, and the pane's content fading softly out under the title as it scrolls, with no line between them.

## What Pulse had, and what it believed

The settings window was an AppKit `NSWindow` whose content view was an `NSHostingView` holding a `NavigationSplitView`, with no toolbar. The sidebar stopped under a title bar of its own, and a note in `SettingsWindowController` said the sidebar *could not* run behind the traffic lights: "AppKit gives that treatment to an `NSSplitViewController` with a sidebar item, and SwiftUI's `NavigationSplitView` inside an `NSHostingView` doesn't get it — neither `.fullSizeContentView` nor a unified `NSToolbar` changes it." That was true of what it tried, and wrong as a conclusion.

## What was measured

A standalone harness: one AppKit window per variant, a `NavigationSplitView` with forty rows scrolled to the middle, captured with `screencapture -l <window number>`. Every variant used `.fullSizeContentView`.

| Variant | Sidebar behind the traffic lights | Under the title |
|---|---|---|
| `NSHostingView` as the content view, no toolbar (Pulse before) | no | — |
| `NSHostingController` as the content view controller | no | — |
| controller + an `NSToolbar` made in AppKit, `.unified` | **yes** | hard band and a line; content cut off |
| the same, `titlebarSeparatorStyle = .none` | yes | the line is still there |
| the same, `.scrollEdgeEffectStyle(.soft, for: .top)` on the scroll view | yes | no blur at all; rows printed over the title |
| the same, `.scrollEdgeEffectHidden(true, for: .top)` | yes | band and line still there — they are AppKit's toolbar, not SwiftUI's edge effect |
| the same, `titlebarAppearsTransparent = true` | yes | no blur; rows printed over the title |
| controller, `sceneBridgingOptions = [.toolbars, .title]`, no items | no | **soft fade**, title legible |
| controller with bridging plus an AppKit `NSToolbar` | — | SwiftUI removed the toolbar |
| `NSHostingView`, `sceneBridgingOptions = [.toolbars, .title]`, `.unified`, **back/forward toolbar items** | **yes** | **soft fade** |
| the same with no toolbar items | no | soft fade |

## What it comes down to

- **The soft fade is SwiftUI's**, drawn under a toolbar SwiftUI knows about. A toolbar made in AppKit is invisible to it, so the window got AppKit's opaque band and line instead.
- **The sidebar's full height needs a toolbar**, and **a toolbar with no items is not drawn.** The settings window needed items of its own; back and forward are what System Settings puts there, and they are useful.
- **A hosting view, not a hosting controller.** With a controller the window binds its title to the controller's, which is nil ("Untitled") — reported by unrot-your-brain's PR and consistent with the harness.
- A transparent title bar turns the edge effect off entirely, which is also what other developers reported.

## How it was found

Not from the harness alone: several variants had already failed when a search turned up [fc445/unrot-your-brain#17](https://github.com/fc445/unrot-your-brain/pull/17), whose AppKit-owned window used `NSHostingView.sceneBridgingOptions = [.toolbars, .title]` to hand SwiftUI's toolbar and title to the window. [oliverames/ping-warden#32](https://github.com/oliverames/ping-warden/issues/32) records the same goal and the dead ends of a `Settings` scene. Background on the scroll edge effect: WWDC25 [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/), and [workspace-sh/table-file-format#383](https://github.com/workspace-sh/table-file-format/issues/383) on `titlebarAppearsTransparent` disabling it.

Lesson kept: when a first-party app shows a look, it can be done — search for how others did it before concluding it cannot.

## Also changed with it

- **The sidebar cannot be hidden** (`.toolbar(removing: .sidebarToggle)`, `columnVisibility: .constant(.all)`). With SwiftUI's toggle, collapsing it and drawing it back at a width that could not hold sidebar and pane overflowed both ways and put an overflow "»" in the title bar.
- **The pane's name is the window's title**, so the heading the pane used to draw is gone; the Window menu and Mission Control show the pane's name, not "Pulse Settings".
