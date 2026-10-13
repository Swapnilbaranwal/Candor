# Candor

**Explore India. Pay what locals pay.**
Candor is an AI travel companion for foreign visitors to India, starting with Delhi. Point it at a price tag, menu, bill or ride quote and it tells you, in your own language, what the fair price is, and shows every step it took to get there.

## Run it

1. Open `Candor.xcodeproj` in Xcode 26 or later.
2. Select the **Candor** target → *Signing & Capabilities* → pick your team.
3. Run on an iPhone or the iOS 26+ Simulator.

Sign in with **Apple, Google, email, a mobile number from any country, or as a guest**. No Indian number is needed. Prototype: nothing is verified and no SMS or email is sent.

## Turn on Gemini (optional)

**Build-time key:** copy `Keys.xcconfig.example` to `Keys.xcconfig` (git-ignored) and set `GEMINI_API_KEY`. The app reads it through Info.plist. A key typed in the app takes priority. Without it the project still builds.


The app works offline with an on-device agent. For photo reading, live reasoning and free translation:

*Me → AI settings → paste a Gemini API key* (from Google AI Studio), then tap **Test connection**. The default model is `gemini-3.8-flash` and you can edit it.

### Gemini through Google Cloud Run (no key in the app)

`backend/gemini-proxy` is a small Cloud Run service that holds the Gemini key in Secret Manager and forwards the app's requests. Deploy it with the steps in its README, then paste the service URL into `Candor/App/Backend.swift`:

```swift
static let geminiProxyURL = "https://YOUR_SERVICE_URL"
```

With a URL there, the app needs no key. A key typed in *Me → AI settings* still takes priority and goes straight to the Gemini API. With neither, the app uses `GEMINI_API_KEY` from `Keys.xcconfig`, or the on-device agent.

## 3D illustrations (one-time step)

The app uses free 3D illustrations from IconScout (free licence, no attribution required). Fetch them into the asset catalog once:

```sh
sh Get3DArt.command
```

The links in the script are signed and expire a few days after they were issued. Until the images are there, the app shows its drawn illustrations instead, so it always builds and runs.

## What's inside

| Area | What it does |
| --- | --- |
| Login | An illustrated landing page (*Get Started* / *Log in*) opening a sign-in sheet: Apple, Google, email, phone (country-code picker, number length checked per country) or guest. Apple and Google are prototype stubs until the real SDK flows are wired in. |
| Persona setup | Name, language (defaults to device), home currency, travel style, days, interests, then an animated "agent setup" sequence. |
| Home | Serif greeting with today's date, an *Ask Candor* search pill and camera button, an animated illustrated city card (sky follows the clock, India Gate in 3D) with today's plan, **Way back home**, the fair-price check, 3D tool tiles and the scam of the day. |
| Way back home | Candor keeps asking where you're staying (Home card, a bar above the tab bar, and a sheet on launch) until you answer. Then: route map from where you are, walk / Metro / auto / cab with fair fares, steps, *Start* in Apple Maps, and a full-screen *Show the driver* card in Hindi. |
| Explore | Map of verified Delhi places (sights, fixed-price shops, markets, transport) with tips, "Fair fare" and "Ask Candor". |
| Scan | Camera or Photos input plus the asked price. The agent reads it, then shows a verdict card with the fair range, a gauge and a phrase to say. |
| Agent | Chat with a visible tool trail. Tools: `lookup_price`, `route_distance`, `estimate_fare`, `check_scam`, `find_nearby`, `convert_currency`, `report_verdict`. |
| Ride fare | Destination search measures the road distance (MapKit), applies the Delhi fare chart and judges the driver's quote. |
| Interpreter | Hindi phrasebook with speech and a full-screen "show the driver" card, plus Gemini translation. |
| Scam radar | 8 known patterns, plus "describe your situation" checked by the agent. |
| Converter / Emergency / History | INR ↔ home currency, the 112 emergency number, the tourist helpline, location sharing and saved checks. |

## Languages

The whole app follows the language picked at persona setup (or under *Me → Preferences*), not the phone's language. English plus 17 others: Spanish, French, German, Italian, Portuguese, Russian, Japanese, Korean, Chinese, Arabic, Hebrew, Dutch, Turkish, Thai, Vietnamese, Indonesian and Polish. Arabic and Hebrew mirror the layout.

- Every user-facing string goes through `L("English text")` (`Services/Localizer.swift`). The English string is the key into `Localization/candor-<code>.json`; a missing key falls back to English.
- Placeholders are `%@` for one value and `%1$@`, `%2$@`… for several, so a translation can reorder them.
- Reference data in `DelhiData` stays in English, because it is matched on and sent to Gemini as tool results. Screens translate it at display time with `L(…)`.
- To add a string: use `L("…")` in code and add the key to each table. To add a language: add its code to `DelhiData.languages` and a `candor-<code>.json`.
- The translations were machine-written and have not been checked by native speakers.
- Gemini answers in the chosen language. Without a Gemini key, answers and screens are translated, but typed questions are still matched on English keywords.

## Design

- iOS 26 **Liquid Glass**: `glassEffect`, `GlassEffectContainer`, `.glass` and `.glassProminent` button styles, a minimizing tab bar and a `tabViewBottomAccessory` agent bar.
- An animated `MeshGradient` background gives the glass colour to refract.
- Agent orb, scan sweep and a live step trail make the agent's work visible.

## Project layout

```
Candor/
  App/          CandorApp, RootView, AppState, Backend (Cloud Run proxy address)
  Design/       Theme, glass helpers, agent and verdict components
  Models/       Persona, Verdict, RideMode, Spot, Scam, Phrase…
  Data/         DelhiData: places, reference prices, scams, phrases, currencies
  Services/     CandorAgent and AgentEngine, GeminiClient, Localizer, Location, Routing, Currency, Speech
  Localization/ candor-<code>.json: one string table per language
  Features/     Login, Onboarding, Home, Explore, Scan, Agent, Rides, Interpreter, Tools, Profile
backend/
  gemini-proxy/ Cloud Run service that forwards Gemini requests and keeps the API key on the server
```

## Data notes

- Fares follow the Delhi Transport Dept. 2022 revision: auto ₹30 for the first 1.5 km then ₹11/km; taxi ₹40 for the first km then ₹17/km (AC ₹20/km); +25% at night. **Verify these against the current notification.**
- Street-food and market ranges are indicative prototype values, and each one is labelled with its source in the app.
- Exchange rates use the ECB reference rate via frankfurter.app, with indicative fallback rates when offline.
