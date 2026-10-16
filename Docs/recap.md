# Recap cards

Shareable 1080 × 1920 cards for a month or a year of Token spend: a one-page poster and a short deck. The facts are `Recap` (`Usage/Recap.swift`); this page owns how they are drawn and the window that shows and exports them. Views are `Settings/Recap*.swift`: the recap belongs to the settings side, not the panel.

Named **月报** / 年报 in Chinese and `Monthly Recap` / `Yearly Recap` in English; Japanese, Korean and Russian (**Итоги месяца** / **Итоги года**) have their own words, written rather than converted.

## The cards

| Card | Month | Year | Needs |
|---|---|---|---|
| Poster (`poster`) | yes | yes, with twelve month bars where the month has its calendar | any tokens |
| Opener (`opener`) | month number, headline, an agent lineup (the top agent a big ink tile, up to three more, a lime "in all" tile), a roster with each agent's days as a strip | the year, the same, the strip a cell per month | `agents` |
| Calendar (`calendar`) | the total with its change on the month before, every day a cell, three tiles (active days ring, streak chain, busiest day), the weeks, weekdays against the weekend | — | a day with tokens |
| Year calendar (`yearCalendar`) | — | the total, twelve small calendars, the same three tiles | a day with tokens |
| Months (`months`) | — | twelve rows (busiest in ink) and weekdays against the weekend | twelve months |
| Timetable (`timetable`) | peak hour, a 24-hour dial, when the day starts and ends, four parts of the day, 24 bars, seven weekdays | same | `hours` and `peakHour` |
| Payback (`payback`) | cost and multiple, a ruler (the used bar cut by model), three tiles, cache against no cache, spend by model with the maker's mark, money by day | the same, money by month | `cost` **and** a price |
| Scorecard (`scorecard`) | the total with its change, money with its daily line, days / sessions / peak hour / cache, a bar per day, tools, top model, persona | same, with a bar per month | any tokens |

The poster is not numbered; the others carry "01 / 05", counted over the cards the deck really has. The year calendar is twelve month grids; a 53-week strip was unreadable at 1080 wide.

## Nil means left out

`RecapDeck` (`RecapDeck.swift`) returns the cards in order. **A card whose data is nil is not drawn, and a nil figure is never drawn as zero:**

- no agents, no opener; no hour shape, no timetable; no cost or no price (`monthlyPrice`, typed by the reader, in `Recap.currency`), no payback — and with no cost, no money figure anywhere (poster tiles, scorecard cells);
- an empty recap has no deck;
- the poster's rows appear only when their facts exist and share the height, so a thin recap is a shorter poster, not one with holes; the scorecard likewise drops a row, cell or chart it cannot fill;
- **a day or month still to come in a running period is not a quiet one** (`RecapInsights.isMonthToCome`): drawn hollow or dashed with no figure (opener strip, payback money by month, Months card, scorecard) and never a point on a cost line.

**The change chip** (poster, calendar, scorecard) reads "vs same period in August": `Recap.previousTokens` covers the same number of days of the period before. Left out without it.

**Payback** is `cost / (price × months)` (`RecapPayback`), one month for a month, twelve for a year. **A running period is prorated by days**: `months = (1 or 12) × elapsed days ÷ days in the month (or year)` — the 5th of a 31-day month is 5/31; March 1 of a 365-day year is 12 × 60/365 — and the card says "Figures are to date, and the plan price is prorated by the days so far." Below 1 it is shown as is; a positive multiple rounding to 0.0 reads "<0.1".

**Partly unpriced money.** `Recap.unpricedTokens` counts tokens with no published price. Above zero, `cost` is a floor, and the poster footer, payback footnote and scorecard say "Some work had no published price, so the money is a floor." Unpriced work does **not** remove the payback card (once it did above 1%, hiding it with no explanation for any heavy month with one unpublished model); the multiple is then a floor too. `cost` stays nil when nothing was priced.

**Cost lines and money bars** (`RecapDeck.costSeries`, the poster's cost line under the total, `RecapInsights.costliestDay` / `costBars`) are drawn only when every day or month *with work* has a cost: a quiet day is a real zero, an unpriced one is not. Cache savings (the sentence, the "cache saved you" row, the cache tile and bars) appear only from $0.50 (`RecapDeck.minimumSavings`, via `RecapDeck.cacheSavings`).

**Streaks belong to the period.** `currentStreak` and `longestStreak` (`Recap.streaks`) count the recap's own `days`: the longest run inside it, and the run ending on its last day — a past period's final day, or a running period's today (yesterday while today is quiet). Only a running period's run is "still going"; a past one says **Longest streak** only.

`hidesProjects` replaces project names with "Project 1", "Project 2"… (`RecapDeck.projectName`). The footer says when figures are to date (`isInProgress`), when the total is a floor (`isPartial`), and that money is an estimate at API prices.

## The scorecard

`RecapScorecardView` (`RecapScorecardView.swift`); chart data `RecapScoreData.swift` (`RecapScoreDataTests`). Top to bottom:

1. Running head with an outlined stamp (`NO. 2026·10`, a year `NO. 2026`) and the page counter; headline.
2. **The total** on a lime bar, the dark change chip, the label (`Tokens · to Oct 5` only while running).
3. **The money** with a mini cost line per day (per month in a year).
4. A **2 × 2**: active days (pips — ink for work, grey for a past quiet day, hollow for a day to come; a year's twelve months in two rows); sessions (average per day *with work*, rounded, left out where it rounds to nothing); peak hour (24 bars, peak in ink, hours with work lime); cache hit (thin meter).
5. **A bar per day** (per month in a year) against grey full-height slots, busiest in ink and named on the right, days to come dashed.
6. **Tools** as one segmented bar (lime, ink, grey; past three, everything after the second is "Other") with share legend.
7. **Top model** with its share, **persona** as a dark chip, footnotes, footer.

A nil cell (no hour shape, no cache) is not drawn; an odd one out takes the whole row. Payback and streak are not repeated here. Pictures shrink before figures, figures before being dropped (`ViewThatFits`), so a long chip, a four-digit session count or a 6,240万 total never collide.

## The four redesigned cards

Opener, calendar, timetable and payback follow the approved mockups (lineup, dial, tiles, rulers). Files: `RecapOpenerView`, `RecapCalendarView`, `RecapTimetableView`, `RecapPaybackView`; shared pieces (tiles, section heads, segment ring, streak chain, brand marks) in `RecapTiles.swift`. Every figure `Recap` does not carry is computed in **`RecapInsights`** (`Usage/RecapInsights.swift`, `RecapInsightsTests`), never in a view:

- **Weekdays and weeks.** `weekdayTokens` (Monday first; **nil for a weekday the period never had** — unknown, not quiet); `workSplit` (weekday vs weekend tokens, days had and used; Saturday and Sunday are the weekend); `weeks` (Monday–Sunday, **clipped to the period**); `busiestWeek` / `busiestWeekday` (earliest of a tie).
- **The streak.** `longestRun` is the earliest of equal runs; `streakChain` is a nine-day window around it, kept inside the period (against the edge if it cannot be centred), run days marked. A run of nine or more shows its first nine; the label names where it ends.
- **Time of day.** `firstHour` ("Earliest start") is the earliest hour from 05:00 with work (the after-midnight tail belongs to the night before; nil when only it has work). `quarters` are the four six-hour shares, `leadingQuarter` the largest. Under one percent is `RecapFormat.percent`'s `<1%`, never zero.
- **Money.** `costPerMillion` is over **priced** tokens only; `costPerActiveDay`; `costliestDay` and `costBars` follow the cost-line rule above. "N× what you spent" appears only when the cache saving exceeds the spend.
- **Who worked when.** `Recap.AgentShare.activeDates` (also `days` in `--recap`) feed `dayMarks` (used / another agent / quiet weekend / quiet weekday) for a month and `monthMarks` (used / another agent / quiet) for a year. No dates, no strip.

**Brand marks.** Agents: `SpendAgent.iconResource` through `LobeIconView` (template image tinted ink or lime). Models: `RecapVendorMark.resource(forModel:)`, a table of name fragments (claude, gpt and the o-series, gemini, glm, kimi, deepseek, qwen, mistral, minimax, grok, and a few more). **No mark is guessed**: no match gets a first-letter tile. `RecapVendorMarkTests` checks every named resource ships.

**Never squeeze a scaled label vertically**: a `Text` with a scale floor in a stack a few points short shrinks to the floor. Use `View.recapFit(_:)` (`lineLimit(1)` + `minimumScaleFactor` + `fixedSize(horizontal: false, vertical: true)`) for any label that may shrink.

## Drawing

Flat colour and type only: paper `#F5F5F1`, white cards with a hairline, ink `#1B1B1E`, lime `#C8F03C` (the icon's accent). **Lime is a fill, never text on paper.** No gradient, blur, shadow, material or emoji, and nothing `ImageRenderer` cannot draw. System face with its CJK fallback; labels and digits monospaced. The Pulse mark is `AppIcon/pulse-mark.svg`'s path.

Hero numbers are set tight and trimmed to their digits (`RecapFigureText.trimmed`; ascender and descender fractions measured against the system font). **Use `Text(tight:tracking:)`, never a negative `.tracking`**: SwiftUI tracks after the last glyph too, which clipped the last digit's right edge; `Text(tight:)` tracks all but the last character. `minimumScaleFactor` on a `Text` in an `HStack` with a `Spacer` can collapse to its floor; give the row a fixed frame or drop the factor.

`RecapRenderer.png(of:in:)` renders a card at scale 1.

## One calendar

Recaps are built, offered and named in `Recap.calendar` (Gregorian, weeks from Monday, system time zone), **not** `Calendar.current`: a Buddhist or Japanese system calendar numbers the year 2569 or Reiwa 8, so "2026" would cover another span than it names. `Recap.build`, `RecapPeriods`, `RecapNoticeRule` and `--recap` default to it; `RecapFormat.calendar(locale:)` is it with a locale. A `Recap` carries its calendar, and the year calendar derives its months from `start` by month offsets (`Recap.monthStarts`), not from the year number. Busiest-day highlights (poster, month calendar) mark only `recap.busiestDay`, the earliest of a tie.

## Language

Copy goes through `String.localized` ([development.md](development.md)), plus four rules:

- **Figures inside a sentence are marked, not split.** The value goes into the key wrapped in `RecapEmphasis.mark`, so each translation places it; `RecapRichText` sets it bold (on a lime bar where asked).
- **Numbers, hours and dates come from the locale** (`RecapFormat`). Token units: 万/亿 (Simplified Chinese), 萬/億 (Traditional), 万/億 (Japanese), 만/억 (Korean), K/M/B otherwise — by `TokenCount.parts`, the rule of `TokenCount.short`, so panel and cards agree. Weekdays start Monday; headings are one character in Chinese, Japanese and Korean. Hours are 24-hour except in English ("11 PM"), since CJK put the half-day before the hour, which a number with a unit cannot say. Money is the API-price estimate in dollars, shown in the currency chosen in Settings → General like every estimate ([refresh-and-data.md](refresh-and-data.md#currency)); the payback ruler converts before choosing its steps, so its labels are round numbers in that currency, and the "for every $1" line is a ratio, not converted. The `--recap` report stays in dollars.
- **Cards say "AI tools"; the pane says "Agent".** Card readers do not use the pane's *Agent* (エージェント, 에이전트, Агент), so cards use 工具 / ツール / 도구 / инструменты ("AI tools", "Tools", "Worked beside you"). Deliberate; do not "fix" it. Likewise an active day (the pane's 有记录的天数, дни с записями) has one recap term per language: 活跃日, 活躍日, 活動日, 활동일, активный день.
- **Longer copy must survive.** Headlines wrap or scale; long labels are one line with a scale floor, or two lines. Check every language after changing copy.

Persona names are written per language (`Recap.Persona.title`), not translated from one another.

## Reviewing

```bash
PULSE_RECAP_PREVIEW=/tmp/recap swift test --filter RecapRenderTests
```

Writes every card of the sample month and year in every language to `/tmp/recap/<language>/<deck>-<n>-<card>.png`, a `sheet.png` per language, and `/tmp/recap/edge/` for recaps missing a field (no price, unpriced, bare, in progress, a year in progress, no hours, no cache, a floor, mostly unpriced) plus `edge/one-agent`, `two-agents`, `three-agents` and `six-weeks` (August 2026). `in-progress`, `floor` and `mostly-unpriced` also render in `edge-zh-Hans`, `edge-ja` and `edge-ko`. Samples are `RecapSamples` (`#if DEBUG`), shared with `RecapRenderer.swift`'s `#Preview` blocks. No pixels are pinned; fit is judged by reading.

Pinned: `RecapInsightsTests` ([above](#the-four-redesigned-cards)); `RecapVendorMarkTests` (mark table); `RecapTests` (past and running streaks, `unpricedTokens`, a Buddhist-calendar build); `RecapDeckTests` (payback with unpriced share and proration, cost line, savings floor, streak wording, which cards a recap gets); `RecapScoreDataTests` (stamp, quiet / future / busiest slots, session average, tool grouping); `RecapFormatTests` (per-locale number split, dates and hours, the ruler); `RecapWindowTests` (price grammar, `RecapPeriods.earliest`, the read-generation race, `takesArrows`). Details: [testing.md](testing.md).

## The window

`RecapWindowController` (`Settings/RecapWindowController.swift`) owns an AppKit window, like Settings: an `.accessory` app must activate itself or the window opens behind everything. `RecapWindowModel` is its state, `RecapWindowView` its SwiftUI, `RecapExport` its way out.

**Entry points** (neither menu has one; the rail's and menu bar's menus stay to the panel, Settings and Quit):

- the Token spend pane's **Monthly and Yearly Recap** row: **View September recap** (`TokenSpendPane.recapPeriod`, the window's default rule) and **View 2026 recap** (`RecapPeriods.defaultYear`; the year is a plain string, never "2,026");
- a clicked "recap is ready" notification, on its month ([notifications.md](notifications.md#the-monthly-recap)).

**Layout.** Left: one card at a time, drawn live and scaled to fit (`RecapCardView` at 1080 × 1920, `scaleEffect`), previous / next beside it, dots and "1 / 5" under it. Right: period, price, privacy switch, four buttons. The window follows system light or dark; only the cards are paper.

**Keys are the window's own.** `RecapWindow.sendEvent` takes a bare ← or → while the window is key, **no text field is being edited**, and the first responder does not use arrows itself — Month / Year segments, popup, slider, stepper, text view (`RecapWindow.takesArrows`). No global monitor and no `NSEvent.addLocalMonitorForEvents`. It also ends field editing on a click outside the field (`NSWindow.endFieldEditing(ifOutside:)`, shared with Settings).

### Which period

- **Offered:** every month and year from the earliest record to now, newest first (`RecapPeriods.months` / `years`). The earliest comes from ledgers the Token spend pane may show (`Origin.supportsTokenSpend`, not providers' own statistics), clamped to 2020-01-01 (`RecapPeriods.floor`) so a bogus timestamp cannot add hundreds of empty months. Until the read finishes only the default is offered.
- **Opened on** (`RecapPeriods.defaultMonth` / `defaultYear`): the month that **just ended during days 1–7** (October 1–7 opens September), **the running month from the 8th**; years likewise with January 1–7. Moved up to the earliest record if before it; until the read knows that, the rule stands alone, so the Token spend button may say September and later October. A requested period (notification, button) beats the default.
- **Month / Year** is a segmented control; switching keeps the year (a month becomes its year, a year its last offered month). The window title follows.

### The price and the privacy switch

- **Monthly price** in US dollars (subscriptions are priced in them), converted for the cards like every other amount, typed in the window ("$" before the field, one line saying it only feeds the payback card). `AppSettings.recapMonthlyPrice` (`Double?`): **empty and 0 both mean no price**, so no payback card. **Strict, locale-free parsing** (`RecapPrice.entry`): after trimming whitespace and one leading "$", either digits with an optional "." or "," and one or two decimals (`20`, `12.5`, `12,5` = 12.5), or "," groups of three with optional ".dd" (`1,200`, `1,200.50`). Anything else (`abc`, `free`, a lone `$`, `1e3`, `20 USD`, `-5`, `1,2,3`, `12.345`) or over `RecapPrice.maximum` (10,000) is refused and the field reverts. Taken on Return, on losing focus and before any export.
- **Hide project names** (`AppSettings.recapHidesProjects`, **off**) is `RecapDeck.hidesProjects`.
- Both persist app-wide and change the deck live.

### States

| State | Left side | Right side |
|---|---|---|
| Token spend reading **off** (`needsReading`) | Icon, "The recap needs Token spend", a sentence saying it is built from this Mac's usage records read only while reading is on, and **Open Token spend** (Settings on that pane). **Nothing is switched on for the person**; switched on while the window is up, it starts reading. | Controls visible, export disabled |
| Reading (`loading`) | Progress through the agents (`Reading Claude Code…`, `4/12`, as in the pane), a spinner before that, and "The first read of a long history can take a minute or two." (about forty seconds on a large history; a fresh kept `SpendWarmer` scan skips it) | Export disabled |
| Working out a period (`isBuilding`) | Small spinner. Built off the main actor, cached per period while open. Records are re-read on showing the window or choosing a period when the last read is half an hour old or from another day (`RecapWindowModel.isStale`). | |
| **No records** | "No records for September 2026" and a line saying nothing in this Mac's records falls in the period. | Export disabled |
| Could not read (`failed`) | A message and **Retry**. | |
| Ready | The card. | All four buttons |

**Cancellation.** Each read carries a generation (`RecapWindowModel.loadGeneration`), so a cancelled read finishing late neither clears the newer read's reference nor hands over its result. One read serves every period; changing period only rebuilds a `Recap`, and a rebuild for a period no longer shown is dropped. **Closing the window cancels a read in progress** and drops the ledgers and built recaps (`RecapWindowModel.windowDidClose`); nothing is read while closed. Switching Token spend reading off under an open window drops them too.

### The ledgers

`RecapSource.load` (`Usage/RecapSource.swift`) is the one path, shared with `--recap`: the scan `SpendWarmer` keeps while Token spend is on if younger than `SpendWarmer.paneFreshness`, otherwise `AgentLedgers.scan` with progress, plus the price table. It does not check the setting; callers do.

### Export

Every export re-renders at full size with `RecapRenderer`, never a screenshot of the preview. `ImageRenderer` is main-actor, so rendering stays on main (well under a second per card; **Save all** yields between cards).

| Button | Does |
|---|---|
| **Save image** | The card on screen → `NSSavePanel` (window sheet), `pulse-recap-2026-09-02-opener.png` |
| **Save all** | `NSOpenPanel` for a folder, then every card including the poster as `pulse-recap-<period>-<nn>-<card>.png` in deck order. **Overwrites** same-named files; nothing else in the folder is touched |
| **Copy image** | PNG (and TIFF, for apps that read only that) on `NSPasteboard.general`; "Copied" |
| **Share image** | One PNG in its own temporary folder `…/Pulse Recap/<UUID>/` (a later share never removes an earlier one the receiving app may still read), handed to `NSSharingServicePicker` anchored to the button. The whole `Pulse Recap` folder is deleted when the window closes (`RecapExport.removeShareFolder`) |

A line under the buttons says "Saved", "Copied" or "Couldn't make the image." for three seconds; cancelling a panel or opening the share sheet says nothing.

### The Dock icon

Shared with Settings through one owner, `DockPresence` (`App/DockPresence.swift`): Pulse shows a Dock icon while **any** of its windows is on screen and `AppSettings.showsDockIconInSettings` allows it (one controller per window let closing Settings remove the icon from an open recap). Label: "Show Dock icon while Settings or a recap is open". See [architecture.md](architecture.md).

## Before the first record

`Recap.recordsBegin` is the first day this Mac has any record (`RecapPeriods.earliest`), when it falls inside the period after its first day. **Before it Pulse saw nothing, which is not a quiet day** (a 2026 recap with records from May once read "active 88 of 282 days"). So `Recap.observedDays` (days from `recordsBegin`) is the denominator for active days, the daily average and the workday/weekend split; months wholly before it are drawn unrecorded like months to come (`RecapInsights.isMonthUnrecorded`); the year calendar draws those days dashed; the plan price counts from that day (`RecapDeck.paidMonths`); footers say where records begin. The "same period" comparison keeps `elapsedDays`.

**Pruned history does not move it.** The ledgers keep work from transcripts the tools have since deleted ([token-spend.md](token-spend.md#history-the-tools-have-deleted)), so days, money, hours and `recordsBegin` survive Claude Code's `cleanupPeriodDays` or another agent's cleanup. A record deleted before Pulse first read it is gone, so `recordsBegin` can be later than the tool's first use.

The month calendar draws every day without work the same way, a dashed outline, weekend or not, and its legend says so.
