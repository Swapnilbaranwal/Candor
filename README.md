# Candor

**Explore India. Pay what locals pay.**
Candor is an AI travel companion for foreign visitors to India, starting with Delhi. Point it at a price tag, menu, bill or ride quote and it tells you, in your own language, what the fair price is, and shows every step it took to get there.

## Run it

1. Open `Candor.xcodeproj` in Xcode 26 or later.
2. Select the **Candor** target → *Signing & Capabilities* → pick your team.
3. Run on an iPhone or the iOS 26+ Simulator.

Log in with **any 10-digit number**. Continue unlocks at exactly 10 digits.

## Turn on Gemini (optional)

**Build-time key:** copy `Secrets.swift.example` to `Candor/Config/Secrets.swift` (that file is git-ignored) and paste your key there. The app picks it up automatically. A key typed in the app takes priority.


The app works offline with an on-device agent. For photo reading, live reasoning and free translation:

*Me → AI settings → paste a Gemini API key* (from Google AI Studio), then tap **Test connection**. The default model is `gemini-2.5-flash` and you can edit it.

> The prototype stores the key on the device. For the hackathon submission, move the Gemini calls behind a Cloud Run proxy so the key never ships in the app.

## What's inside

| Area | What it does |
| --- | --- |
| Login | Country-code picker and a 10-digit gate with a progress bar. |
| Persona setup | Name, language (defaults to device), home currency, travel style, days, interests, then an animated "agent setup" sequence. |
| Home | Fair-price shield (overcharge flagged in your currency), tools grid, Ask Candor prompts, scam of the day, recent checks and the live exchange rate. |
| Explore | Map of verified Delhi places (sights, fixed-price shops, markets, transport) with tips, "Fair fare" and "Ask Candor". |
| Scan | Camera or Photos input plus the asked price. The agent reads it, then shows a verdict card with the fair range, a gauge and a phrase to say. |
| Agent | Chat with a visible tool trail. Tools: `lookup_price`, `route_distance`, `estimate_fare`, `check_scam`, `find_nearby`, `convert_currency`, `report_verdict`. |
| Ride fare | Destination search measures the road distance (MapKit), applies the Delhi fare chart and judges the driver's quote. |
| Interpreter | Hindi phrasebook with speech and a full-screen "show the driver" card, plus Gemini translation. |
| Scam radar | 8 known patterns, plus "describe your situation" checked by the agent. |
| Converter / Emergency / History | INR ↔ home currency, the 112 emergency number, the tourist helpline, location sharing and saved checks. |

## Design

- iOS 26 **Liquid Glass**: `glassEffect`, `GlassEffectContainer`, `.glass` and `.glassProminent` button styles, a minimizing tab bar and a `tabViewBottomAccessory` agent bar.
- An animated `MeshGradient` background gives the glass colour to refract.
- Agent orb, scan sweep and a live step trail make the agent's work visible.

## Project layout

```
Candor/
  App/          CandorApp, RootView, AppState
  Design/       Theme, glass helpers, agent and verdict components
  Models/       Persona, Verdict, RideMode, Spot, Scam, Phrase…
  Data/         DelhiData: places, reference prices, scams, phrases, currencies
  Services/     CandorAgent and AgentEngine, GeminiClient, Location, Routing, Currency, Speech
  Features/     Login, Onboarding, Home, Explore, Scan, Agent, Rides, Interpreter, Tools, Profile
```

## Data notes

- Fares follow the Delhi Transport Dept. 2022 revision: auto ₹30 for the first 1.5 km then ₹11/km; taxi ₹40 for the first km then ₹17/km (AC ₹20/km); +25% at night. **Verify these against the current notification.**
- Street-food and market ranges are indicative prototype values, and each one is labelled with its source in the app.
- Exchange rates use the ECB reference rate via frankfurter.app, with indicative fallback rates when offline.
