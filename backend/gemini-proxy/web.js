// Routes for the web version of the app (public/): Ask Candor, the place guide on the Trip tab,
// the Interpreter, and Google Maps images. Keys stay on the server; the page never sees them.
//
// POST /v1/ask             { message, history?, language?, name? }       → { text, verdict?, steps?, model }
// GET  /v1/place?name=&lat=&lng=&language=                                → { summary, rating, hoursToday, thingsToDo, source }
// POST /v1/place/ask       { name, question, context?, language? }       → { text, model }
// POST /v1/translate       { text, to }                                   → { translation, roman, model }
// GET  /v1/staticmap?w=&h=&markers=lat,lng;…&path=lat,lng;…&home=lat,lng → PNG from the Maps Static API

import { callGemini, checkPrice } from "./agent.js";

const PLACES_URL = "https://places.googleapis.com/v1/places:searchText";
const STATIC_URL = "https://maps.googleapis.com/maps/api/staticmap";
const placeCache = new Map();
const mapCache = new Map();

function text(json) {
  return (json?.candidates?.[0]?.content?.parts || []).map((part) => part.text || "").join("").trim();
}

function jsonIn(raw) {
  const match = String(raw).match(/\{[\s\S]*\}/);
  try { return match ? JSON.parse(match[0]) : null; } catch { return null; }
}

async function gemini(prompt, { models, apiKey, system, json = false }) {
  const body = { contents: [{ role: "user", parts: [{ text: prompt }] }] };
  if (system) body.systemInstruction = { parts: [{ text: system }] };
  if (json) body.generationConfig = { responseMimeType: "application/json" };
  const { json: reply, model } = await callGemini(body, models, apiKey);
  return { text: text(reply), model };
}

/** A price question goes to the fair-price agent; anything else is a plain answer. */
function isPriceQuestion(message) {
  return /₹|\brs\.?\s?\d|\binr\b|\d+\s?(rupees|rs)\b|\b(price|fare|cost|charge|asking|pay|paid|fair|overcharg|expensive)\b/i.test(message);
}

/** "Add a place to day 3", "put Akshardham in my trip": a change to the itinerary, not a question. */
function isTripEdit(message) {
  return /\b(add|include|put|squeeze|fit in)\b/i.test(message) && /\b(day|trip|itinerary|plan|schedule)\b/i.test(message);
}

/** Gemini picks the place and the day; the page finds it on Google Maps and adds it to the trip. */
async function addPlace(message, input, ctx) {
  const trip = (Array.isArray(input.trip) ? input.trip : []).slice(0, 10)
    .map((day) => `Day ${Number(day.day)}: ${(Array.isArray(day.places) ? day.places : []).slice(0, 8).map(String).join(", ") || "free"}`).join("\n");
  const loves = (Array.isArray(input.interests) ? input.interests : []).slice(0, 8).join(", ");
  // "Add Red Fort to day 2" names the place already: if Gemini is busy, the page can still add it.
  const named = message.match(/\b(?:add|include|put)\s+(?:the\s+)?(.+?)\s+(?:to|in|into|on)\s+(?:my\s+)?(?:day\s*(\d+)|trip|itinerary|plan)/i);
  const fallback = named && !/^(a|an|some|one)\s+(place|spot|stop)/i.test(named[1])
    ? { text: "", action: { type: "add_place", place: named[1].slice(0, 120), day: Number(named[2]) || Number(input.day) || 1 }, model: null }
    : null;
  let raw, model;
  try {
    ({ text: raw, model } = await gemini(
    `A traveller in Delhi asks: "${message}"
Their trip:
${trip || "Not planned yet."}
They love: ${loves || "a bit of everything"}. Today they're looking at day ${Number(input.day) || 1}.
Pick ONE real, specific place in Delhi to add (named in the request if they named one, otherwise one that fits their trip and
is near that day's other places), and the day number to add it to. Don't pick a place already in the trip.
Reply in ${String(input.language || "English").slice(0, 30)} as JSON:
{"place": "the place's name as on Google Maps", "day": 3, "why": "2 or 3 short lines: why it fits and the best way to get there. Do not say it has been added."}`,
    { ...ctx, json: true }));
  } catch (error) {
    if (fallback) return fallback;
    throw error;
  }
  const parsed = jsonIn(raw) || {};
  if (!parsed.place && fallback) return fallback;
  if (!parsed.place) return { text: "I couldn't tell which place to add. Try \"Add Akshardham to day 3\".", model };
  return { text: String(parsed.why || ""), action: { type: "add_place", place: String(parsed.place).slice(0, 120), day: Number(parsed.day) || Number(input.day) || 1 }, model };
}

export async function ask(input, ctx) {
  const message = String(input.message || "").slice(0, 600);
  const language = String(input.language || "English").slice(0, 30);
  if (!message) throw Object.assign(new Error("Ask Candor something."), { status: 400 });

  if (isTripEdit(message)) return addPlace(message, input, ctx);

  if (isPriceQuestion(message)) {
    // The web app's traveller is staying on Janpath, so "auto to Red Fort" has a distance to work from.
    const where = input.near ? ` (I'm near ${String(input.near).slice(0, 80)}.)` : "";
    const result = await checkPrice({ city: input.city || "Delhi", question: message + where, language,
                                      imageBase64: input.imageBase64 }, ctx);
    return { text: result.answer, verdict: result.verdict, steps: result.steps, model: result.model };
  }

  const history = (Array.isArray(input.history) ? input.history : []).slice(-6)
    .map((turn) => `${turn.role === "user" ? "Traveller" : "Candor"}: ${String(turn.text || "").slice(0, 400)}`).join("\n");
  const system = `You are Candor, an honest travel companion for visitors to Delhi, India${input.name ? `, talking to ${String(input.name).slice(0, 40)}` : ""}.
Reply in ${language}, in at most 5 short lines, warm and practical. Use **bold** for key facts. Give prices in rupees.
Never invent exact prices or timings you're unsure of: say so. Most people in India are honest; be respectful.
For emergencies, the number is 112.`;
  const { text: answer, model } = await gemini(`${history ? `${history}\n` : ""}Traveller: ${message}`, { ...ctx, system });
  return { text: answer, model };
}

/** Candor's own ideas for a kind of place, when Gemini has nothing. */
function offlineIdeas(types) {
  const has = (names) => names.some((name) => types.includes(name));
  if (has(["park", "garden", "national_park", "botanical_garden"])) {
    return ["Take a slow walk; mornings are cooler and quieter.", "Find a shaded lawn for a break, and carry water.",
            "Look out for the monuments and old trees along the paths."];
  }
  if (has(["hindu_temple", "mosque", "church", "place_of_worship", "sikh_temple"])) {
    return ["Dress modestly, with shoulders and knees covered.", "Leave your shoes at the counter, which is usually free.",
            "Ask before taking photos inside."];
  }
  if (has(["museum", "art_gallery"])) {
    return ["Buy tickets at the official counter and check the foreigner rate.", "Ask about an audio guide at the entrance.",
            "Give the main galleries at least an hour."];
  }
  if (has(["market", "shopping_mall", "store", "clothing_store", "jewelry_store"])) {
    return ["Ask the price first, then check it with Candor before you pay.", "Carry small notes; change is often short.",
            "Keep your bag in front in crowded lanes."];
  }
  return ["Buy tickets only at the official counter or online.", "Hire a guide only at the official desk, never at the gate.",
          "Go early for fewer crowds and softer light."];
}

export async function place(params, ctx) {
  const name = String(params.get("name") || "").slice(0, 120);
  const lat = Number(params.get("lat")), lng = Number(params.get("lng"));
  const language = String(params.get("language") || "English").slice(0, 30);
  if (!name) throw Object.assign(new Error("Which place?"), { status: 400 });
  // ideas=0: Google Maps only, which is quick; the page asks again for Gemini's ideas.
  const withIdeas = params.get("ideas") !== "0";
  const key = `${name}|${language}|${withIdeas}`;
  if (placeCache.has(key)) return placeCache.get(key);

  let details = {};
  const plain = placeCache.get(`${name}|${language}|false`);
  if (plain) details = plain.details;
  else if (ctx.mapsKey) {
    try {
      const response = await fetch(PLACES_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Goog-Api-Key": ctx.mapsKey,
                   "X-Goog-FieldMask": "places.editorialSummary,places.generativeSummary,places.types,places.rating,places.regularOpeningHours.weekdayDescriptions,places.regularOpeningHours.periods" },
        body: JSON.stringify({ textQuery: name, maxResultCount: 1,
                               ...(lat && lng ? { locationBias: { circle: { center: { latitude: lat, longitude: lng }, radius: 2000 } } } : {}) }),
        signal: AbortSignal.timeout(15_000),
      });
      const found = (await response.json())?.places?.[0];
      if (found) {
        const days = found.regularOpeningHours?.weekdayDescriptions || [];
        // Google lists Monday first; getDay() is 0 for Sunday. India time.
        const weekday = new Date(Date.now() + 5.5 * 3600_000).getUTCDay();
        const today = days.length === 7 ? days[(weekday + 6) % 7] : null;
        details = {
          summary: found.editorialSummary?.text || found.generativeSummary?.overview?.text || null,
          types: found.types || [],
          rating: found.rating || null,
          hoursToday: today ? today.split(/:\s(.+)/)[1] || null : null,
          // Every opening window in the week, in minutes from midnight; day 0 is Sunday, as in Google's data.
          periods: (found.regularOpeningHours?.periods || []).map(({ open, close }) => ({
            day: open?.day ?? 0,
            open: (open?.hour || 0) * 60 + (open?.minute || 0),
            // No close means open around the clock.
            close: close ? (close.hour || 0) * 60 + (close.minute || 0) + (close.day !== open?.day ? 1440 : 0) : null,
          })),
        };
      }
    } catch { /* Fall through to Gemini and Candor's own ideas. */ }
  }

  const info = { summary: details.summary || null, rating: details.rating || null, hoursToday: details.hoursToday || null,
                 periods: details.periods || null,
                 thingsToDo: offlineIdeas(details.types || []), source: "Google Maps" };
  if (ctx.apiKey && withIdeas) {
    try {
      const { text: raw } = await gemini(
        `A traveller from abroad has just reached ${name} in Delhi. ${details.summary || ""}
List 4 specific things to do there, in ${language}, each under 14 words, practical and honest
(what to see, where to go inside, what it costs if anything, one thing to watch for).
Reply as JSON: {"things": ["…", "…"]}`, { ...ctx, json: true });
      const things = jsonIn(raw)?.things;
      if (Array.isArray(things) && things.length) {
        info.thingsToDo = things.slice(0, 5).map(String);
        info.source = details.summary ? "Google Maps and Gemini" : "Gemini";
      }
    } catch { /* Keep Candor's own ideas. */ }
  }
  placeCache.set(key, info);
  if (!withIdeas) Object.defineProperty(info, "details", { value: details, enumerable: false });
  return info;
}

export async function placeAsk(input, ctx) {
  const name = String(input.name || "").slice(0, 120);
  const question = String(input.question || "").slice(0, 400);
  const context = String(input.context || "").slice(0, 800);
  const system = `You are Candor, a fair-price travel companion in Delhi. Answer in ${String(input.language || "English").slice(0, 30)},
in at most 4 short lines, plain and practical. Use **bold** for key facts. Give prices in rupees. If you're not sure, say so.`;
  return gemini(`About ${name}, Delhi. ${context}\nQuestion: ${question}`, { ...ctx, system });
}

export async function translate(input, ctx) {
  const source = String(input.text || "").slice(0, 400);
  const to = String(input.to || "Hindi").slice(0, 30);
  if (!source) throw Object.assign(new Error("Type something to translate."), { status: 400 });
  const { text: raw, model } = await gemini(
    `Translate for a traveller in India, into natural, polite spoken ${to}: "${source}".
Reply as JSON: {"translation": "in the target script", "roman": "Latin-letter pronunciation, or empty if already Latin"}`,
    { ...ctx, json: true });
  const parsed = jsonIn(raw) || {};
  return { translation: String(parsed.translation || ""), roman: String(parsed.roman || ""), model };
}

function points(value) {
  return String(value || "").split(";").map((pair) => pair.split(",").map(Number))
    .filter(([lat, lng]) => Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180)
    .slice(0, 12);
}

/** A Google map image, drawn by the Maps Static API on the server so the key stays private. */
export async function staticMap(params, mapsKey) {
  const w = Math.min(640, Math.max(100, Number(params.get("w")) || 640));
  const h = Math.min(640, Math.max(100, Number(params.get("h")) || 400));
  const markers = points(params.get("markers"));
  const path = points(params.get("path"));
  const home = points(params.get("home"))[0];
  const query = new URLSearchParams({ size: `${w}x${h}`, scale: "2", language: "en", key: mapsKey });
  const url = new URL(STATIC_URL);
  for (const [k, v] of query) url.searchParams.append(k, v);
  for (const style of ["feature:poi|visibility:off", "feature:transit|element:labels.icon|visibility:off",
                       "feature:landscape|color:0xf6efe6", "feature:water|color:0xbfdcea", "feature:road|element:geometry|color:0xffffff"]) {
    url.searchParams.append("style", style);
  }
  if (path.length > 1) url.searchParams.append("path", `color:0xE8973Bff|weight:5|${path.map((p) => p.join(",")).join("|")}`);
  markers.forEach(([lat, lng], index) => {
    url.searchParams.append("markers", `color:0x7A1F36|label:${index < 9 ? index + 1 : ""}|${lat},${lng}`);
  });
  if (home) url.searchParams.append("markers", `color:0x1AA8B8|${home[0]},${home[1]}`);

  const cacheKey = url.toString();
  if (mapCache.has(cacheKey)) return mapCache.get(cacheKey);
  const response = await fetch(url, { signal: AbortSignal.timeout(15_000) });
  if (!response.ok || !String(response.headers.get("content-type")).startsWith("image/")) {
    throw Object.assign(new Error(`Google Maps could not draw the map (${response.status}). Is the Maps Static API enabled?`), { status: 502 });
  }
  const image = { type: response.headers.get("content-type"), data: Buffer.from(await response.arrayBuffer()) };
  if (mapCache.size > 200) mapCache.clear();
  mapCache.set(cacheKey, image);
  return image;
}
