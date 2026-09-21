# The SDK stamp decides which design macOS draws

**Historical, not newly verified.** Current rule: [../releasing.md](../releasing.md), [../build-from-source.md](../build-from-source.md).

macOS picks an app's control design from the SDK version recorded in its
binary's `LC_BUILD_VERSION`, not from the version it is running on. Below 26 it
draws the pre-Tahoe controls. There is an `Info.plist` key that opts *out*
(`UIDesignRequiresCompatibility`) and none that opts back in, so a wrong stamp
can only be fixed by linking again.

## What happened

Xcode was upgraded from 26.x to 27 on 2026-09-19. Nothing in Pulse changed.
Builds after it were drawn the old way: segmented pickers went from a filled
accent-coloured selection to the raised white capsule of the previous design.

Measured 2026-09-20, both architecture slices, same source:

| Build | Recorded `sdk` | On screen |
|---|---|---|
| 1.3.0 release (CI, earlier toolchain) | 26.5 | current design |
| Local build, 2026-09-18, earlier Xcode | 26.5 | — |
| Local build under Xcode 27 | **14.0** | **old design** |
| Package run from Xcode 27 | **14.0** | **old design** |
| Same source stamped 26.5 | 26.5 | current design |
| Same source stamped 27.0 | 27.0 | current design |

The last three were looked at on screen, one instance at a time, with only the
stamp differing. 26.5 and 27.0 are indistinguishable, so the rule is a floor at
26 rather than a match against the running system — 27.0 on macOS 26.7 is fine.

`Package.swift` declares `.macOS(.v14)`. Under Xcode 27's toolchain SwiftPM
stamped that **deployment target** into the SDK field. It did not under the
previous one, which is the point: the stamp is a toolchain behaviour, not
something the manifest states, so it can move again with nothing here changing.

Read a slice with `otool -arch arm64 -l <binary> | grep -A 4 LC_BUILD_VERSION`.
A universal binary carries one per slice, and reading only the first hid the
difference for a while during this diagnosis.

## Why it is set in the manifest and checked in the bundler

`Scripts/bundle.sh` is not the only way this package is built. Running it from
Xcode produced the same wrong stamp and never touches that script, and a
developer chasing what looks like a UI regression would be chasing a build
artefact. So the stamp is a `linkerSettings` flag in `Package.swift`, which
every build path shares — confirmed on 2026-09-20 by running the package from
Xcode after the change and finding the current design, the one case the
bundler could not have fixed.

It states **26.0**, the floor this app already requires — `glassEffect` needs
that SDK to compile even behind `#available` — rather than whichever SDK is
installed, because a manifest cannot ask the toolchain. The measurements above
are what make a floor sufficient.

`bundle.sh` then reads the stamp back off each slice and refuses to package
anything below 26. The flag alone would not be enough: when it stops taking
effect there is no error and no failing test, and what ships is an app that
merely looks wrong. The check does not care how the stamp got there, which is
the only property worth having against a toolchain that has already changed
this behaviour once.
