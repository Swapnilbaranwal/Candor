# Candor design system

Candor is a calm, honest travel companion. The interface should feel like a well-made
guidebook: quiet surfaces, clear type, and colour only where it means something. Every
token below lives in `Candor/Design/Theme.swift`; use it instead of literal values.

## Principles

1. **Content first.** Prices, places and times are the interface. Decoration that doesn't
   help someone decide what to pay or where to go comes out.
2. **Colour carries meaning.** One accent for actions and selection. Other colours only
   signal something: fair or overcharge, a place category, a Metro line.
3. **Glass is for system chrome.** Tab bar, toolbars, sheets and system controls keep
   Liquid Glass. Content sits on plain surfaces.
4. **Say it once.** One title, one supporting line. No label above a heading, no repeated hints.
5. **Honest by design.** Every price shows its source. Verified data and estimates look
   different ("Verified guide" vs "AI guide", "Estimate:" tips).

## Colour

| Token | Use |
|---|---|
| `Theme.accent` (saffron) | Primary buttons, selection, progress, links |
| `Theme.accentSoft` | Fills behind accent icons and selected rows |
| `Theme.canvas` | Page background (warm off-white / near black) |
| `Theme.surface` | Cards and grouped rows (white / dark grey) |
| `Theme.field` | Text fields and inputs on a card |
| `Theme.hairline` | Unselected outlines, dividers |
| `Theme.mint` | Fair price, verified, success |
| `Theme.rose` | Overcharge, scams, warnings |
| `Theme.teal`, `Theme.indigo` | Categories and travel modes only (map pins, Metro, walk/auto/cab) |
| `Theme.brandGradient` | The logo, launch screen and splash. Nowhere else |

Never use gradients on text, buttons or backgrounds.

## Type

System font (SF Pro), Dynamic Type styles only.

| Role | Style |
|---|---|
| Screen title | `.largeTitle.bold` (tab roots) or `.title2.bold` (flows, sheets) |
| Section title | `.headline` |
| Body | `.body` / `.subheadline` |
| Supporting text | `.subheadline` or `.caption`, `.secondary` |
| Numbers (prices, times) | `.monospacedDigit()` |

One title and at most one supporting line per screen or card.

## Shape and space

| Token | Value | Use |
|---|---|---|
| `Theme.Radius.small` | 10 | Badges, small tiles |
| `Theme.Radius.medium` | 14 | Rows, text fields, buttons |
| `Theme.Radius.large` | 16 | Cards (the maximum) |

Spacing on a 4-point grid: 4, 8, 12, 16, 20, 24. Screen side margins are 20.
Cards pad 16. Cards don't nest inside cards, and have no shadows or coloured side borders.

## Components

- **Card** (`.card()`): padded content on `Theme.surface`. Optional `tint` for meaning
  (a verdict, a warning), never decoration.
- **Chip** (`Chip`): selected = filled with the accent (or a category colour), white text;
  unselected = surface with a hairline. Lay chips out with `FlowLayout`, left-aligned.
- **Buttons:** `.borderedProminent` with the accent for the main action, `.bordered` for the
  rest. One prominent button per screen.
- **Agent** (`AgentMark`): the brand seal on a soft accent disc; a spinner while working.
  No orbs, glows or sparkle icons for AI. Icons describe the action (`text.bubble`,
  `calendar`, `checkmark.shield`).
- **Icons:** SF Symbols, beside text rather than stacked in tiles above headings.
- **Lists and forms in sheets:** native `Form`/`List` styling.

## Motion

Short and functional: `.snappy` for selection, `.smooth` for screen changes. No looping
animation in content (the only exception is the progress spinner).

## Copy

Plain, short and specific. Sentence case. Say what happens: "Plan it for me", "Check a
driver's quote". Every user-facing string goes through `L("English")`.
