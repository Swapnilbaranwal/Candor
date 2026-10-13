# Candor design system

Candor should feel like a beautiful printed travel guide that came alive: airy white pages,
elegant serif headings, rich illustrations, and gentle motion that makes India feel close and
safe. Every token below lives in `Candor/Design/Theme.swift`, `Components.swift` and
`Illustrations.swift`; use them instead of literal values.

## Principles

1. **Illustration leads, content decides.** Each screen opens with art (the living Delhi scene,
   a floating 3D object) and then gets straight to prices, places and times.
2. **Calm surfaces, one ink.** Soft grey canvas, white cards with soft shadows, an ink pill for
   the main action. Colour comes from the art and from meaning (fair, overcharge, travel modes).
3. **Motion with purpose.** Screens assemble top to bottom, cards sink when pressed, the sky
   moves, home glows. Respect Reduce Motion: every looping animation pauses when it is on.
4. **Say it once.** One serif title, one supporting line.
5. **Honest by design.** Every price shows its source; estimates look like estimates.

## Colour

| Token | Use |
|---|---|
| `Theme.ink` | Primary pill buttons, selected chips and modes, the camera button |
| `Theme.accent` | System tint: ink in light mode, saffron in dark mode |
| `Theme.saffron` | Brand highlight: icons in the search bar, "keep asking" glow, route line |
| `Theme.canvas` | Page background (soft grey / near black) |
| `Theme.surface` | Cards (white / dark grey) |
| `Theme.shadow` | The soft drop shadow under cards and floating controls |
| `Theme.mint` / `Theme.rose` | Fair / overcharge, success / warning |
| `Theme.teal`, `Theme.indigo` | Travel modes and categories |
| `DayPeriod` palettes | Illustration skies and hills (dawn, day, dusk, night) |

Gradients belong to illustrations and the logo, never to text or buttons.

## Type

- **Headings:** the system serif (New York) via `.heading(_:)` and `.display(size:)`. Screen
  titles `.heading(.largeTitle)`, card titles `.heading(.title3)`, hero titles `.display(size: 34)`.
- **Reading:** SF Pro via `.candor(_:_:)`. Prices and times add `.monospacedDigit()`.
- Scripts the serif doesn't cover (Devanagari, CJK, Arabic, Thai…) fall back automatically.

## Shape and space

| Token | Value | Use |
|---|---|---|
| `Theme.Radius.small` | 12 | Badges, tiles |
| `Theme.Radius.medium` | 18 | Rows, inputs |
| `Theme.Radius.large` | 26 | Cards |

Hero cards use 30. Buttons and search fields are capsules (56 pt tall, 50–52 in tight rows).
Screen margins 20, card padding 16–20, 4-point grid.

## Components

- **Pill buttons:** `.buttonStyle(.pill)` (ink, the main action), `.pillOutline`, `.pillSoft`.
- **Pressable cards:** wrap tappable cards in `Button` + `.buttonStyle(.pressable)`.
- **Circle icons:** `CircleIcon` for back, edit, profile, the camera button (`filled: true`).
- **Cards:** `.card()`: white surface, soft shadow, radius 26.
- **Tags:** `TagPill` (icon + label on canvas) and `Chip` for selectable filters.
- **Page dots:** `PageDots` under hero art.
- **Entrances:** `.reveal(order)` on each top-level section of a screen.

## Logo

An open "C" in a sunrise gradient (coral to saffron) holding a mint map pin: honest guidance,
right to the place. `CandorLogo(size:tile:)` draws it in code (on the night-indigo tile of the
app icon, or bare with `tile: false`); `AppIcon` and `LaunchLogo` are the same mark as PNGs.
The landing screen shows only the wordmark over the city, not the logo.

## Day and night

The whole app follows the sky: light from dawn to dusk, dark at night (`DayPeriod.colorScheme`,
checked every minute and when the app returns). The drawn scenes use the same clock: sun and
clouds by day, a crescent moon, stars and lit windows at night.

## Illustrations

- **Drawn scenes** (`Illustrations.swift`): `CityScene` (Delhi skyline, sky follows the clock),
  `HomeNestArt` (house at the end of a marching dotted path), `StayQuestionArt` (suitcase and a
  hopping pin). Original vector art, animated with `TimelineView`, paused under Reduce Motion.
- **First run** (`OnboardingArt.swift`): `ProductArt` (sign-in: fair price, translation, way
  back home and Lens floating over Delhi), `JourneyArt` (a plane flies town to town while a car,
  an auto and a scooter take the road), `PartyArt` (60 pt portraits for solo, couple, family,
  friends), `StyleArt` and `InterestArt` (travel style tiles and interest icons), and `RecipeRing`
  (setting up as a recipe: ingredients orbit and drop into the pot as the ring fills). All
  vector and `Canvas`, no Lottie or image downloads, so screens stay fast.
- **3D objects** (`Art3D`, IconScout, free licence, no attribution): India Gate, home with pin,
  suitcase, hot-air-balloon adventure, translator, train, location pin, camera. Show them with
  `Floating3D`, which floats them gently over a soft contact shadow and falls back to a drawn
  scene or symbol if the image isn't in the bundle. Run `Get3DArt.command` to fetch them.

## Motion

- Entrances: `.reveal(n)` (spring, staggered ~70 ms).
- Presses: `PressableStyle` (scale 0.975, spring).
- Selection: `.snappy`; mode tiles slide with `matchedGeometryEffect`.
- Ambient: drifting clouds, breathing sun, flapping birds, twinkling stars, glowing windows,
  floating 3D objects, the pulsing "where are you staying?" card. All stop under Reduce Motion.

## Way back home

The traveller's stay is home. Until Candor knows it, it keeps asking: a pulsing card on Home,
a bar above the tab bar on every tab, and the "You're new to the city" sheet on launch and on
return (at most every 10 minutes). Once set, Home shows the way back with the best mode, time
and fair fare, and the full screen shows the route, every mode, steps, "Start" in Apple Maps
and a "Show the driver" card in Hindi.

## Copy

Plain, short and warm. Sentence case. Every user-facing string goes through `L("English")`
and gets a key in each `Localization/candor-<code>.json`.
