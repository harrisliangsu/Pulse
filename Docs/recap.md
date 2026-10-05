# Recap cards

Shareable 1080 × 1920 cards for a month or a year of Token spend: a one-page poster and a short deck. The facts are `Recap` (`Usage/Recap.swift`); this page owns how they are drawn. Views live in `Settings/` as `Recap*.swift` — the recap is something the settings window shows and exports, and the cards are not part of the panel.

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
