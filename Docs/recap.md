# Recap cards

Shareable 1080 × 1920 cards for a month or a year of Token spend: a one-page poster and a short deck. The facts are `Recap` (`Usage/Recap.swift`); this page owns how they are drawn and the window that shows and exports them. Views live in `Settings/` as `Recap*.swift` — the recap belongs to the settings side of the app, and the cards are not part of the panel.

Called **月报** in Chinese (`Monthly Recap` in English; the year is `Yearly Recap` / 年报, and Japanese and Korean have their own words, written rather than converted).

## The cards

| Card | Month | Year | Needs |
|---|---|---|---|
| Poster (`poster`) | yes | yes, with twelve month bars where the month has its calendar | any tokens |
| Opener (`opener`) | month number, headline, agents | the year, headline, agents | `agents` |
| Calendar (`calendar`) | every day, quiet days dashed, busiest in ink | — | a day with tokens |
| Year calendar (`yearCalendar`) | — | twelve small calendars | a day with tokens |
| Months (`months`) | — | twelve rows, busiest in ink | twelve months |
| Timetable (`timetable`) | peak hour, 24 rows | same | `hours` and `peakHour` |
| Payback (`payback`) | cost against the price, ruler, spend by model, cache savings | against twelve months of it | `cost` **and** a price |
| Scorecard (`scorecard`) | eight figures, top model, persona | same | any tokens |

The poster stands alone and is not numbered; the others carry "01 / 05", counted over the cards the deck really has.

A year calendar was drawn both as twelve month grids and as one 53-week strip. The strip is unreadable at 1080 wide (14 pt cells, no month names) and was dropped.

## Nil means left out

`RecapDeck` (`RecapDeck.swift`) returns the cards in order. **A card whose data is nil is not drawn**, and a figure inside a card whose data is nil is not drawn with a zero:

- no agents, no opener; no hour shape, no timetable; no cost or no price (`monthlyPrice`, typed by the reader, in `Recap.currency`), no payback — and no money figure anywhere, including the poster's tiles and the scorecard's cells;
- an empty recap has no deck;
- the poster is a stack of rows that appear only when their facts exist; the rows that remain share the height, so a thin recap is a shorter poster, not one with holes;
- the scorecard drops a cell it cannot fill, and pairs an odd one out with the busiest day.

Payback is `cost / (price × months)`: one month for a month, twelve for a year, or as many as have started when the year is still running. Below 1 it is shown as it is.

`hidesProjects` replaces project names with "Project 1", "Project 2"… (`RecapDeck.projectName`). The footer says when figures are to date (`isInProgress`) and when the total is a floor (`isPartial`), and that money is an estimate at API prices.

## Drawing

Flat colour and type only — paper `#F5F5F1`, white cards with a hairline, ink `#1B1B1E`, lime `#C8F03C` (the icon's accent). **Lime is a fill, never text on paper.** No gradient, blur, shadow, material or emoji, and nothing `ImageRenderer` cannot draw. Type is the system face and its CJK fallback; labels and digits use the monospaced design. The Pulse mark is drawn from `AppIcon/pulse-mark.svg`'s path.

Hero numbers are set tight and trimmed to their digits (`RecapFigureText.trimmed`; the ascender and descender fractions are measured against the system font). `minimumScaleFactor` on a `Text` inside an `HStack` with a `Spacer` can be shrunk to its floor for no visible reason; give such a row a fixed frame or leave the factor off.

`RecapRenderer.png(of:in:)` renders a card at scale 1.

## Language

Copy goes through `String.localized` like the rest of the app ([development.md](development.md)); the cards add three rules.

- **Figures inside a sentence are marked, not split.** A translation puts a number where its language wants it, so the card hands the value to the key wrapped in `RecapEmphasis.mark`, and `RecapRichText` finds it again to set it bold (on a lime bar where the card asks for one).
- **Numbers, hours and dates come from the locale** (`RecapFormat`). A token count is a big number and a small unit: 万/亿 in Simplified Chinese, 萬/億 in Traditional Chinese, 万/億 in Japanese, 만/억 in Korean, K/M/B otherwise — by `TokenCount.parts`, the same rule as `TokenCount.short`, so the panel and the cards never disagree about where 亿 begins. Weekdays start on Monday; headings are one character in Chinese, Japanese and Korean and the short name elsewhere. Hours are 24-hour except in English, where they read "11 PM" (the other three put the half-day before the hour, which a number with a unit cannot say). Dollars are "$" in every language.
- **Longer copy must survive.** Headlines wrap or scale; every label that can be long is a single line with a scale floor or two lines. Look at all five languages after changing any copy.

Persona names are written per language (`Recap.Persona.title`), not translated from one another.

## Reviewing

```bash
PULSE_RECAP_PREVIEW=/tmp/recap swift test --filter RecapRenderTests
```

writes every card of the sample month and year in all five languages to `/tmp/recap/<language>/<deck>-<n>-<card>.png`, one `sheet.png` contact sheet per language, and `/tmp/recap/edge/` for recaps with a field missing (no price, unpriced, bare, in progress). The samples are `RecapSamples` (`#if DEBUG`), which the `#Preview` blocks in `RecapRenderer.swift` share. The test pins nothing about pixels: a card either fits its language or it does not, and the only judge is reading it.

`RecapFormatTests` and `RecapDeckTests` pin the number split per locale, the date and hour formats, the ruler, and which cards each recap gets.

## The window

`RecapWindowController` (`Settings/RecapWindowController.swift`) owns an AppKit window, as the settings window is owned, for the same reason: Pulse is an `.accessory` app and has to activate itself or the window opens behind everything. `RecapWindowModel` is its state, `RecapWindowView` its SwiftUI, `RecapExport` its way out.

**Entry points** — all three open the same window:

- the menu bar menu's **Monthly Recap…** (next to Settings…; the rail's menu is the same menu);
- the Token spend pane's **Monthly Recap** row, whose button reads **View September recap** and opens on that month (`SettingsView.recapPeriod`, the window's own default rule);
- a clicked "recap is ready" notification, on the month it names ([notifications.md](notifications.md#the-monthly-recap)).

**Layout.** The deck on the left, one card at a time, drawn live and scaled to fit (`RecapCardView` at 1080 × 1920, `scaleEffect`), with previous / next buttons beside it and dots with a "1 / 5" counter under it; **← and →** turn the page. On the right: the period, the price, the privacy switch and four buttons. The window follows the system's light or dark; only the cards are paper.

**Keys are the window's own.** `RecapWindow.sendEvent` takes a bare ← or → while this window is key and **no text field is being edited** (the price field keeps its caret keys). No global monitor and no `NSEvent.addLocalMonitorForEvents`. The same method ends field editing on a click outside the field (`NSWindow.endFieldEditing(ifOutside:)`, shared with the settings window).

### Which period

- **Offered:** every month, and every year, from the earliest record on this Mac to now, newest first (`RecapPeriods.months` / `years`; the earliest is the earliest of the ledgers' `earliest`). Nothing before the first record, nothing after today. Until the read has finished only the default is offered.
- **Opened on:** the month that **just ended during the first seven days of a month** (October 1–7 opens on September), **the running month from the 8th**. For years the same rule with January 1–7. If that falls before the earliest record it moves up to it; until the read has said where records begin (the Token spend button's label, a window still reading) the rule stands alone, so the button can read "View September recap" first and move to October if records only begin then. `RecapPeriods.defaultMonth` / `defaultYear`; a period asked for (the notification's, the Token spend button's) is kept over the default.
- **Month / Year** is a segmented control; switching keeps the year (a month becomes its year, a year becomes its last offered month). The window title follows it.

### The price and the privacy switch

- **Monthly price**, in US dollars, typed into the window (a "$" before the field and one line saying it is only used for the payback card). Stored as `AppSettings.recapMonthlyPrice` (`Double?`): **empty and 0 both mean no price**, and no payback card is drawn — never a guess, never a zero. Only a positive amount up to `RecapPrice.maximum` (10,000) is kept; a negative, a word or a larger figure is refused and the field goes back to what was kept. It is taken on Return, when the field loses focus, and before any export — so a price typed and a button pressed straight away exports the payback card.
- **Hide project names** (`AppSettings.recapHidesProjects`, **off**: names are shown) is `RecapDeck.hidesProjects`.
- Both are stored and read back whole-app, like every setting, and both change the deck live.

### States

| State | What the left side shows | Right side |
|---|---|---|
| Token spend reading **off** (`needsReading`) | An icon, "The recap needs Token spend", one sentence saying it is built from this Mac's usage records and read only while reading is on, and an **Open Token spend** button that opens Settings on that pane. **Nothing is switched on for the person**; if they switch it on while the window is up, it starts reading. | Controls visible, export disabled |
| Reading (`loading`) | A bar through the agents (`Reading Claude Code…`, `4/12`, as the pane's own row) once there is progress, a spinner before; and "The first read of a long history can take a minute or two." The first read is long (about forty seconds on a large history); a kept fresh scan (`SpendWarmer`) skips it. | export disabled |
| Working out a period (`isBuilding`) | A small spinner. Off the main actor; cached per period for as long as the window is open. | |
| **No records** | "No records for September 2026" and a line saying nothing in this Mac's records falls in the period. | export disabled |
| Could not read (`failed`) | A message and **Retry**. | |
| Ready | The card. | all four buttons |

**Cancellation.** The read is one read for every period, so changing period never restarts it — a month change only rebuilds a `Recap`, and a rebuild for a period no longer on screen is dropped. **Closing the window cancels a read in progress** and drops the ledgers and every recap built from them (`RecapWindowModel.windowDidClose`); nothing is read while it is closed. Switching Token spend reading off under an open window drops them too.

### The ledgers

`RecapSource.load` (`Usage/RecapSource.swift`) is the one path to them, shared with `--recap`: the scan `SpendWarmer` keeps while Token spend is on if it is younger than `SpendWarmer.paneFreshness`, otherwise `AgentLedgers.scan` with progress, and the price table. It does not check the setting; the callers do.

### Export

All of it renders the card again at full size with `RecapRenderer` — never a screenshot of the preview. `ImageRenderer` is main-actor, so rendering stays on main (one card is well under a second; **Save all** yields between cards).

| Button | Does |
|---|---|
| **Save image** | The card on screen → `NSSavePanel` (a sheet on the window), `pulse-recap-2026-09-02-opener.png` |
| **Save all** | `NSOpenPanel` for a folder, then every card including the poster, `pulse-recap-<period>-<nn>-<card>.png` in deck order |
| **Copy image** | PNG (and TIFF, for apps that read only that) on `NSPasteboard.general`; "Copied" |
| **Share image** | One PNG written to `…/Pulse Recap/` in the temporary folder (replaced on the next share) and handed to `NSSharingServicePicker`, anchored to the button |

A line under the buttons says "Saved", "Copied" or "Couldn't make the image." for three seconds; cancelling a panel and opening the share sheet say nothing.

### The Dock icon

The window shares the Dock-icon-while-open rule with Settings, through one owner, `DockPresence` (`App/DockPresence.swift`): Pulse is a regular app (Dock icon, ⌘-Tab) while **any** of its windows is on screen and `AppSettings.showsDockIconInSettings` allows it, and a menu bar app again when the last closes. With one controller per window, closing Settings under an open recap took the icon from the recap. The setting keeps its name and label ("Show Dock icon while Settings is open"); it governs the recap window too.

