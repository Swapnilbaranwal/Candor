// Candor for the web: the iOS app's Home, Trip and Check tabs, Ask Candor and the tools,
// talking to this Cloud Run service (Gemini, Google Maps and Firestore stay on the server).

// MARK: Helpers

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const inr = (n) => "₹" + Math.round(Number(n) || 0).toLocaleString("en-IN");
const range = (low, high) => (high <= 0 ? "Free" : Math.round(low) === Math.round(high) ? inr(low) : `${inr(low)}–${inr(high)}`);
const duration = (minutes) => {
  const h = Math.floor(minutes / 60), m = Math.round(minutes % 60);
  return h === 0 ? `${m} min` : m === 0 ? `${h} h` : `${h} h ${m} min`;
};

const store = {
  get(key, fallback) {
    try { const raw = localStorage.getItem(`candor.${key}`); return raw == null ? fallback : JSON.parse(raw); } catch { return fallback; }
  },
  set(key, value) { try { localStorage.setItem(`candor.${key}`, JSON.stringify(value)); } catch { /* Private mode: keep it in memory. */ } },
};

async function api(path, options = {}) {
  const response = await fetch(path, { headers: { "Content-Type": "application/json" }, ...options });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(json?.error?.message || `Something went wrong (${response.status}).`);
  return json;
}

/** **bold**, *italic*, bullets and paragraphs: all Candor's answers need. */
function md(text) {
  const inline = (line) => esc(line).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>").replace(/(^|[^*])\*(?!\s)(.+?)\*/g, "$1<em>$2</em>");
  const blocks = String(text || "").trim().split(/\n{2,}/);
  return blocks.map((block) => {
    const lines = block.split("\n");
    if (lines.every((line) => /^\s*([-•*]|\d+\.)\s+/.test(line))) {
      return `<ul>${lines.map((line) => `<li>${inline(line.replace(/^\s*([-•*]|\d+\.)\s+/, ""))}</li>`).join("")}</ul>`;
    }
    return `<p>${lines.map(inline).join("<br>")}</p>`;
  }).join("");
}

let toastTimer;
function toast(message) {
  const el = $("#toast");
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 2600);
}

/** India time, wherever the browser is. */
function indiaNow() {
  const now = new Date();
  return new Date(now.getTime() + now.getTimezoneOffset() * 60_000 + 5.5 * 3600_000);
}
const clock = (date) => date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });

function speak(text, lang = "hi-IN") {
  try {
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = lang;
    utterance.rate = 0.9;
    speechSynthesis.cancel();
    speechSynthesis.speak(utterance);
  } catch { toast("Your browser can't speak this aloud."); }
}

// MARK: Data (the same places, fares and phrases as the app)

// Where the traveller is staying in Delhi: from onboarding, or a central hotel for the demo.
const HOTEL = store.get("hotel", null) || { name: "The Imperial, Janpath", lat: 28.6254, lng: 77.2181 };

const SPOTS = {
  cp: { name: "Connaught Place", cat: "market", lat: 28.6315, lng: 77.2167, blurb: "Georgian-style circles of shops, cafés and the Palika Bazaar underground market.", tip: "Ignore strangers who offer to take you to a 'tourist office'. CP has none." },
  indiagate: { name: "India Gate", cat: "sight", lat: 28.6129, lng: 77.2295, blurb: "War memorial arch on Kartavya Path; lovely at dusk.", tip: "Free to visit. Balloons and snacks are sold at fixed, low prices." },
  redfort: { name: "Red Fort", cat: "sight", lat: 28.6562, lng: 77.2410, blurb: "17th-century Mughal fort and UNESCO site. Closed on Mondays.", tip: "Buy tickets at the official ASI counter or online. Ignore 'closed today' claims." },
  humayun: { name: "Humayun's Tomb", cat: "sight", lat: 28.5933, lng: 77.2507, blurb: "Garden tomb that inspired the Taj Mahal. Quiet in the morning.", tip: "Official ASI tickets only; card and UPI accepted at the counter." },
  lodhi: { name: "Lodhi Garden", cat: "sight", lat: 28.5931, lng: 77.2197, blurb: "Park with 15th-century tombs, a lake and shaded lawns.", tip: "Free entry. Best early in the morning or around sunset." },
  qutub: { name: "Qutub Minar", cat: "sight", lat: 28.5245, lng: 77.1855, blurb: "73 m sandstone minaret from 1193 with intricate carvings.", tip: "Take the Metro to Qutub Minar station, then a short auto ride." },
  lotus: { name: "Lotus Temple", cat: "sight", lat: 28.5535, lng: 77.2588, blurb: "Bahá'í house of worship shaped like a lotus. Free entry, closed Mondays.", tip: "Entry is free. Anyone charging for entry or 'fast lane' is a tout." },
  akshardham: { name: "Akshardham", cat: "sight", lat: 28.6127, lng: 77.2773, blurb: "Huge carved temple complex with an evening water show.", tip: "Phones aren't allowed inside; use the free cloakroom." },
  chandnichowk: { name: "Chandni Chowk", cat: "market", lat: 28.6506, lng: 77.2303, blurb: "Old Delhi's spice, textile and street-food lanes.", tip: "Agree on cycle-rickshaw prices before you sit down." },
  dillihaat: { name: "Dilli Haat (INA)", cat: "market", lat: 28.5733, lng: 77.2079, blurb: "Open-air crafts and regional food market run by Delhi Tourism.", tip: "Prices are often marked; bargaining is gentle here." },
  khan: { name: "Khan Market", cat: "market", lat: 28.6003, lng: 77.2270, blurb: "Upmarket bookstores, boutiques and cafés.", tip: "Mostly fixed prices and card payments." },
  emporium: { name: "Central Cottage Industries Emporium", cat: "fixed", lat: 28.6238, lng: 77.2190, blurb: "Government-run crafts store on Janpath with fixed, marked prices.", tip: "Use it as a price benchmark before bargaining elsewhere." },
  itb: { name: "International Tourist Bureau", cat: "transport", lat: 28.6430, lng: 77.2194, blurb: "Official foreign-tourist train booking office, 1st floor of New Delhi Railway Station.", tip: "It's inside the station. Offices outside claiming to be it are fake." },
};
const STAY = { sight: 90, market: 75, fixed: 45, transport: 30 };

const DAYS = [
  { title: "India Gate · Humayun's Tomb", stops: ["indiagate", "humayun", "lodhi", "khan"] },
  { title: "Connaught Place · Chandni Chowk", stops: ["cp", "chandnichowk", "redfort"] },
  { title: "Qutub Minar · Lotus Temple", stops: ["qutub", "lotus", "dillihaat"] },
  { title: "Akshardham · Janpath", stops: ["akshardham", "emporium"] },
];

const MODES = {
  walk: { title: "Walk", icon: "ph-person-simple-walk", color: "var(--mint)" },
  metro: { title: "Metro", icon: "ph-train", color: "var(--indigo)" },
  bus: { title: "Bus", icon: "ph-bus", color: "var(--bus)" },
  erick: { title: "E-rickshaw", icon: "ph-lightning", color: "var(--teal)" },
  auto: { title: "Auto", icon: "ph-car-profile", color: "var(--saffron)" },
  bike: { title: "Bike taxi", icon: "ph-moped", color: "var(--violet)" },
  cab: { title: "Cab", icon: "ph-car", color: "var(--sky)" },
  car: { title: "Candor car", icon: "ph-steering-wheel", color: "var(--ink)" },
};

const PHRASES = [
  ["How much is this?", "यह कितने का है?", "Yeh kitne ka hai?", "Prices"],
  ["That's too expensive.", "यह बहुत महँगा है।", "Yeh bahut mehenga hai.", "Prices"],
  ["Please give it at MRP.", "MRP पर दीजिए।", "MRP par dijiye.", "Prices"],
  ["Please reduce the price a little.", "थोड़ा कम कीजिए।", "Thoda kam kijiye.", "Prices"],
  ["What is the final price?", "आख़िरी दाम क्या है?", "Aakhri daam kya hai?", "Prices"],
  ["No, thank you.", "नहीं, धन्यवाद।", "Nahin, dhanyavaad.", "Prices"],
  ["Please go by the meter.", "मीटर से चलिए।", "Meter se chaliye.", "Rides"],
  ["Take me to this address.", "मुझे इस पते पर ले चलिए।", "Mujhe is pate par le chaliye.", "Rides"],
  ["Stop here, please.", "यहाँ रोकिए।", "Yahan rokiye.", "Rides"],
  ["No shopping stops, please.", "कोई दुकान नहीं जाना है।", "Koi dukaan nahin jaana hai.", "Rides"],
  ["Not spicy, please.", "कम तीखा, प्लीज़।", "Kam teekha, please.", "Food"],
  ["Vegetarian, please.", "शाकाहारी, प्लीज़।", "Shakahari, please.", "Food"],
  ["The bill, please.", "बिल दीजिए।", "Bill dijiye.", "Food"],
  ["Where is the toilet?", "शौचालय कहाँ है?", "Shauchalay kahan hai?", "Help"],
  ["I need a doctor.", "मुझे डॉक्टर चाहिए।", "Mujhe doctor chahiye.", "Help"],
  ["Please call the police.", "पुलिस को बुलाइए।", "Police ko bulaiye.", "Help"],
].map(([english, hindi, roman, category]) => ({ english, hindi, roman, category }));
const phrase = (english) => PHRASES.find((p) => p.english === english);

const TIPS = [
  { title: "Check your hotel yourself", icon: "ph-bed", how: "You might hear: \"Your hotel is closed or full, I know a better one.\"", todo: "Call the hotel on the number from your booking, and ask to go to the original address." },
  { title: "Book trains at the official counter", icon: "ph-buildings", how: "You might hear: \"Your ticket is cancelled, the tourist office is this way.\"", todo: "The real tourist bureau is inside New Delhi station, 1st floor. Check tickets on IRCTC." },
  { title: "Ask for the meter, or use a prepaid booth", icon: "ph-gauge", how: "You might hear: \"Meter is broken, fixed price.\"", todo: "Check the fare in Candor and say \"Meter se chaliye\", or take a prepaid or app cab." },
  { title: "Skip 'easy profit' offers", icon: "ph-diamond", how: "A friendly stranger offers a profit if you carry gems abroad 'to avoid tax'. The stones are near-worthless.", todo: "Never buy goods for resale from strangers. Walk away." },
  { title: "Politely decline 'free' gifts", icon: "ph-gift", how: "Someone ties a bracelet or gives a flower, then asks for money or a 'donation'.", todo: "Politely say \"Nahin, dhanyavaad\" and don't accept the item." },
  { title: "Say no to shopping stops on tours", icon: "ph-shopping-bag", how: "You might hear: \"City tour for ₹10, just a quick stop at a government shop.\"", todo: "Say \"Koi dukaan nahin jaana hai\". For fixed prices, try Central Cottage Industries Emporium." },
  { title: "Buy monument tickets at the official counter", icon: "ph-bank", how: "You might hear: \"Closed today, come with me\" or \"Fast-lane ticket\" outside the gate.", todo: "Buy at the official ASI counter or online." },
];

const GUIDES = [
  { name: "Aarav Mehta", langs: "English, Hindi, French", tags: "Heritage · Photography", rating: 4.9, tours: 412, rate: 650, bio: "Old Delhi lanes, Mughal stories and the best light for photos.", color: "#7A1F36" },
  { name: "Meera Iyer", langs: "English, Hindi, German, Spanish", tags: "Street food · Markets", rating: 4.9, tours: 538, rate: 600, bio: "Food walks from Chandni Chowk to Majnu ka Tilla, with fair prices at every stall.", color: "#C4621A" },
  { name: "Kabir Singh", langs: "English, Hindi, Japanese", tags: "Spiritual · Heritage", rating: 4.8, tours: 296, rate: 700, bio: "Temples, gurdwaras and Sufi shrines, explained with care.", color: "#0F543F" },
  { name: "Zoya Khan", langs: "English, Hindi, Arabic, Chinese", tags: "Nature · Photography", rating: 4.9, tours: 344, rate: 600, bio: "Gardens, step-wells and quiet corners away from the crowds.", color: "#5C54E6" },
];

// Indicative rates per rupee. Labelled as such wherever they show.
const RATES = { USD: 0.01136, EUR: 0.00976, GBP: 0.00852, JPY: 1.72, AUD: 0.0174, CAD: 0.0158, SGD: 0.0147, AED: 0.0417, CNY: 0.0809, KRW: 15.6 };
const SYMBOLS = { USD: "$", EUR: "€", GBP: "£", JPY: "¥", AUD: "A$", CAD: "C$", SGD: "S$", AED: "AED ", CNY: "¥", KRW: "₩" };
const LANGUAGES = ["English", "Spanish", "French", "German", "Italian", "Portuguese", "Japanese", "Korean", "Chinese", "Arabic", "Russian", "Hindi"];
const foreign = (rupees) => {
  const code = state.currency;
  const value = rupees * RATES[code];
  return `${SYMBOLS[code]}${value >= 100 ? Math.round(value).toLocaleString() : value.toFixed(2)}`;
};

// MARK: State

const state = {
  tab: "home",
  name: store.get("name", ""),
  language: store.get("language", "English"),
  currency: store.get("currency", "USD"),
  style: store.get("style", "comfort"),
  day: Math.min(store.get("day", 0), DAYS.length - 1),
  visited: new Set(store.get("visited", [])),
  choices: store.get("choices", {}),
  records: store.get("records", [
    { title: "Samosa (street)", asked: 60, verdict: "over", icon: "ph-receipt" },
    { title: "Auto to Red Fort", asked: 250, verdict: "high", icon: "ph-car-profile" },
  ]),
  chat: [],
  // Each day's stops, as place ids: Candor's plan until the traveller adds, removes or reorders.
  dayStops: store.get("dayStops", null) || DAYS.map((d) => [...d.stops]),
  // Places added from Google Maps or by Ask Candor, by id.
  custom: store.get("custom", {}),
};
const placeById = (id) => SPOTS[id] || state.custom[id];
const save = () => {
  store.set("visited", [...state.visited]);
  store.set("choices", state.choices);
  store.set("records", state.records.slice(0, 12));
  store.set("style", state.style);
  store.set("day", state.day);
  store.set("dayStops", state.dayStops);
  store.set("custom", state.custom);
};

// MARK: Fares and plans (same rules as TripPlanner in the app)

function km(a, b) {
  const rad = Math.PI / 180, dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}
const isNight = (date = indiaNow()) => date.getHours() >= 23 || date.getHours() < 5;
/** Delhi Transport Dept. fare chart (2022 revision). */
function meter(mode, road, night = false) {
  let fare = mode === "auto" ? 30 + Math.max(0, road - 1.5) * 11 : mode === "ac" ? 40 + Math.max(0, road - 1) * 20 : 40 + Math.max(0, road - 1) * 17;
  if (night) fare *= 1.25;
  return Math.round(fare);
}
function metroFare(road) {
  return road <= 2 ? 11 : road <= 5 ? 21 : road <= 12 ? 32 : road <= 21 ? 43 : road <= 32 ? 54 : 64;
}

function legBetween(from, to) {
  const straight = km(from, to), road = straight * 1.35, night = isNight();
  const options = [];
  if (straight <= 2.2) options.push({ mode: "walk", minutes: Math.ceil(straight / 4.5 * 60), low: 0, high: 0, summary: `About ${straight.toFixed(1)} km on foot.` });
  if (road >= 3) {
    const fare = metroFare(road);
    options.push({ mode: "metro", minutes: Math.ceil(road / 30 * 60 + 14), low: fare, high: fare, summary: "Metro plus a short walk at each end. Buy a token or use a card at the station." });
  }
  if (road <= 6) options.push({ mode: "erick", minutes: Math.ceil(road / 12 * 60 + 4), low: 10, high: Math.min(60, Math.round(10 + 4 * road)), summary: "Shared e-rickshaw: agree the price before you sit down." });
  const auto = meter("auto", road, night);
  options.push({ mode: "auto", minutes: Math.ceil(road / 18 * 60 + 3), low: auto, high: Math.round(auto * 1.2), summary: "Ask for the meter, or agree on this fare before you get in." });
  options.push({ mode: "bike", minutes: Math.ceil(road / 24 * 60 + 5), low: Math.round(20 + 6 * road), high: Math.round(30 + 9 * road), summary: "Book in Rapido or Uber Moto. Helmet provided." });
  const cabLow = meter("taxi", road, night), cabHigh = Math.round(meter("ac", road, night) * 1.3);
  options.push({ mode: "cab", minutes: Math.ceil(road / 22 * 60 + 6), low: cabLow, high: cabHigh, summary: "App cab (Uber, Ola) from a marked pickup point." });
  const fixed = Math.ceil(Math.max(cabLow, cabHigh) * 1.1 / 10) * 10;
  options.push({ mode: "car", minutes: Math.ceil(road / 22 * 60 + 10), low: fixed, high: fixed, summary: "A verified Candor driver at a fixed price, booked ahead." });

  const has = (mode) => options.some((o) => o.mode === mode);
  let best;
  if (straight <= 1.2) best = "walk";
  else if (state.style === "budget") best = has("metro") && road > 4 ? "metro" : has("erick") ? "erick" : "auto";
  else if (state.style === "luxury") best = "car";
  else best = has("metro") && road > 9 ? "metro" : "auto";
  return { from: from.name, to: to.name, road, straight, options, best, fromPt: from, toPt: to };
}
const sorted = (leg) => [...leg.options].sort((a, b) => (a.mode === leg.best ? -1 : b.mode === leg.best ? 1 : a.minutes - b.minutes));
const chosen = (leg, key) => leg.options.find((o) => o.mode === (state.choices[key] || leg.best)) || leg.options[0];

// MARK: Opening hours (Google Maps first, Candor's usual hours until it answers)

const t = (h, m = 0) => h * 60 + m;
/** Same hours every day except `closed` (0 = Sunday). */
const H = (open, close, closed = []) => ({ periods: [0, 1, 2, 3, 4, 5, 6].filter((d) => !closed.includes(d)).map((day) => ({ day, open, close })) });
const USUAL_HOURS = {
  redfort: H(t(9, 30), t(16, 30), [1]), indiagate: { always: true }, humayun: H(t(6), t(18)), lodhi: H(t(5), t(20)),
  qutub: H(t(7), t(17)), lotus: H(t(9), t(17), [1]), akshardham: H(t(10), t(20), [1]), chandnichowk: H(t(10), t(21), [0]),
  dillihaat: H(t(10, 30), t(22)), khan: H(t(10), t(22)), cp: H(t(10), t(22)), emporium: H(t(10), t(19)),
  itb: H(t(8), t(20)),
};
const hoursCache = store.get("hours", {});
const hoursAsked = new Set();
const hoursFor = (id) => hoursCache[id] || USUAL_HOURS[id] || null;

/** Opening windows on that date as [open, close] minutes; "always"; or null when Candor doesn't know. */
function openWindows(id, date) {
  const hours = hoursFor(id);
  if (!hours) return null;
  if (hours.always || (hours.periods?.length === 1 && hours.periods[0].close == null)) return "always";
  return hours.periods.filter((p) => p.day === date.getDay()).map((p) => [p.open, p.close ?? 1440]).sort((a, b) => a[0] - b[0]);
}

const minuteText = (m) => { const d = new Date(2000, 0, 1, 0, m); return clock(d); };
const WEEKDAYS = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"];
/** Minutes before closing that the gate stops letting people in. Monuments stop selling tickets about 30 minutes before. */
const LAST_ENTRY = { redfort: 30, humayun: 30, qutub: 30, lotus: 30, akshardham: 60 };
const lastEntryGap = (id, cat) => LAST_ENTRY[id] ?? (cat === "sight" ? 30 : 0);

function hoursText(id, date) {
  const w = openWindows(id, date);
  if (w == null) return "";
  if (w === "always") return "Open 24 hours";
  if (!w.length) return `Closed on ${WEEKDAYS[date.getDay()]}`;
  const gap = lastEntryGap(id, placeById(id)?.cat);
  return w.map(([o, c]) => `${minuteText(o)}–${minuteText(c)}${gap ? `, last entry ${minuteText(c - gap)}` : ""}`).join("; ");
}

/** Asks Google Maps for real opening hours of places that don't have them yet, then re-times the days. */
async function loadHours(ids) {
  const todo = ids.filter((id) => !hoursCache[id] && !hoursAsked.has(id) && placeById(id));
  if (!todo.length) return;
  todo.forEach((id) => hoursAsked.add(id));
  const found = await Promise.all(todo.map(async (id) => {
    const p = placeById(id);
    try {
      const info = await api(`/v1/place?name=${encodeURIComponent(p.name + ", Delhi")}&lat=${p.lat}&lng=${p.lng}&ideas=0`);
      if (info.periods?.length) { hoursCache[id] = { periods: info.periods, source: "Google Maps" }; return true; }
    } catch { /* Keep Candor's usual hours. */ }
    return false;
  }));
  if (found.some(Boolean)) { store.set("hours", hoursCache); renderAll(); }
}

/** "India Gate · Humayun's Tomb": the day's first two places, like the app. */
function dayTitle(ids) {
  const names = ids.map((id) => placeById(id)?.name).filter(Boolean);
  return names.length ? names.slice(0, 2).join(" · ") : "A free day";
}

function dayPlan(index) {
  const ids = (state.dayStops[index] || []).filter(placeById);
  const day = { title: dayTitle(ids), stops: ids };
  const start = dayDate(index);
  start.setHours(9, 30, 0, 0);
  let cursor = start, from = HOTEL;
  const entries = day.stops.map((id) => {
    const spot = { id, cat: "sight", ...placeById(id) };
    const leg = legBetween(from, spot);
    const option = chosen(leg, `${index}:${id}`);
    let arrival = new Date(cursor.getTime() + option.minutes * 60_000);
    let stay = STAY[spot.cat] || 75;
    // Fit the visit inside the opening hours: wait for it to open, leave when it closes,
    // or flag it when it's shut by the time you'd get there.
    let closed = false, note = "";
    const windows = openWindows(id, arrival);
    if (Array.isArray(windows)) {
      const at = arrival.getHours() * 60 + arrival.getMinutes();
      // Get in before last entry, with time for a proper visit: at least an hour, or most of the planned stay.
      const last = (c) => c - lastEntryGap(id, spot.cat);
      const minVisit = Math.min(stay, Math.max(60, Math.round(stay * 0.6)));
      const open = windows.find(([o, c]) => Math.max(at, o) <= last(c) && c - Math.max(at, o) >= minVisit);
      if (!windows.length) { closed = true; note = `Closed on ${WEEKDAYS[arrival.getDay()]}`; }
      else if (!open) { closed = true; note = `Too late to go in · ${hoursText(id, arrival)}`; }
      else {
        if (open[0] > at) { arrival = new Date(arrival.getTime() + (open[0] - at) * 60_000); note = `Opens at ${minuteText(open[0])}`; }
        const begin = Math.max(at, open[0]);
        if (begin + stay > open[1]) {
          stay = open[1] - begin;
          const gap = lastEntryGap(id, spot.cat);
          note = gap ? `Get in by ${minuteText(open[1] - gap)} · closes ${minuteText(open[1])}` : `Closes at ${minuteText(open[1])}`;
        }
      }
    }
    const departure = new Date(arrival.getTime() + (closed ? 0 : stay) * 60_000);
    cursor = departure;
    from = spot;
    return { spot, leg, option, arrival, departure, stay, closed, note };
  });
  const travel = entries.reduce((sum, e) => sum + e.option.minutes, 0);
  const low = entries.reduce((sum, e) => sum + e.option.low, 0), high = entries.reduce((sum, e) => sum + e.option.high, 0);
  return { day, start, entries, travel, fare: range(low, high), closed: entries.filter((e) => e.closed).length };
}

/** Days planned in Delhi: the trip's length from onboarding, up to Candor's four suggested days. */
const planDays = () => {
  const profile = store.get("profile", null);
  const delhi = profile?.stops?.find((s) => s.name === "Delhi");
  if (!delhi) return DAYS.length;
  return Math.max(1, Math.min(DAYS.length, Math.round((new Date(delhi.leave) - new Date(delhi.arrive)) / 86_400_000)));
};
const dayDate = (index) => {
  const arrive = store.get("profile", null)?.stops?.find((s) => s.name === "Delhi")?.arrive;
  const d = arrive ? new Date(`${arrive}T12:00:00`) : indiaNow();
  d.setDate(d.getDate() + index);
  return d;
};
const wayHome = () => {
  const plan = dayPlan(state.day);
  const last = plan.entries.filter((e) => state.visited.has(`${state.day}:${e.spot.id}`)).pop()?.spot || HOTEL;
  if (last === HOTEL) return { text: "Way back home · 15 min · Free", leg: null };
  const leg = legBetween(last, HOTEL);
  const best = leg.options.find((o) => o.mode === leg.best);
  return { text: `Way back home · ${duration(best.minutes)} · ${range(best.low, best.high)}`, leg };
};

// MARK: Maps (drawn by Google on the server, so the key stays private)

function mapImage(points, { w = 640, h = 380, home = HOTEL, path = true } = {}) {
  const list = points.map((p) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`).join(";");
  const route = path ? [home, ...points].map((p) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`).join(";") : "";
  const src = `/v1/staticmap?w=${w}&h=${h}&markers=${list}${route ? `&path=${route}` : ""}${home ? `&home=${home.lat},${home.lng}` : ""}`;
  return `<img src="${src}" alt="Google map of the day's stops" loading="lazy" onerror="this.replaceWith(window.candorSketch(this))" data-points="${esc(JSON.stringify([home, ...points].filter(Boolean)))}">`;
}

/** Without the Maps Static API, a sketch of the same stops so the card is never empty. */
window.candorSketch = (img) => {
  const pts = JSON.parse(img.dataset.points || "[]");
  const lats = pts.map((p) => p.lat), lngs = pts.map((p) => p.lng);
  const [minLat, maxLat, minLng, maxLng] = [Math.min(...lats), Math.max(...lats), Math.min(...lngs), Math.max(...lngs)];
  const x = (lng) => 70 + (lng - minLng) / ((maxLng - minLng) || 1) * 260;
  const y = (lat) => 240 - (lat - minLat) / ((maxLat - minLat) || 1) * 180;
  const wrap = document.createElement("div");
  wrap.style.cssText = "width:100%;height:100%";
  wrap.innerHTML = `<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" style="background:#F3ECE2">
    <path d="M0 210 C 90 180, 160 250, 400 200" stroke="#fff" stroke-width="10" fill="none"/>
    <path d="M120 0 C 140 120, 90 200, 130 300" stroke="#fff" stroke-width="8" fill="none"/>
    <path d="M0 80 L 400 120" stroke="#fff" stroke-width="6" fill="none"/>
    <polyline points="${pts.map((p) => `${x(p.lng)},${y(p.lat)}`).join(" ")}" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>
    <polyline points="${pts.map((p) => `${x(p.lng)},${y(p.lat)}`).join(" ")}" fill="none" stroke="#E8973B" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    ${pts.map((p, i) => i === 0
      ? `<circle cx="${x(p.lng)}" cy="${y(p.lat)}" r="11" fill="#1AA8B8" stroke="#fff" stroke-width="3"/>`
      : `<circle cx="${x(p.lng)}" cy="${y(p.lat)}" r="15" fill="#7A1F36" stroke="#fff" stroke-width="3"/><text x="${x(p.lng)}" y="${y(p.lat) + 5}" font-size="14" font-weight="700" text-anchor="middle" fill="#fff" font-family="Lato">${i}</text>`).join("")}
  </svg>`;
  return wrap;
};

const mapsLink = (to, mode = "transit") =>
  `https://www.google.com/maps/dir/?api=1&destination=${to.lat},${to.lng}&travelmode=${mode}`;

// MARK: Pieces shared by the tabs

function citySky() {
  const hour = indiaNow().getHours();
  const night = hour >= 19 || hour < 6, dusk = hour >= 17 && hour < 19;
  const sky = night ? ["#0E1640", "#1F2463", "#2D2B6B"] : dusk ? ["#3B2E7E", "#B85A7A", "#F2A65A"] : ["#7DB8F0", "#B9DCF7", "#F8E5C8"];
  const silhouette = night ? "#141A45" : dusk ? "#4A2A55" : "#C9A98A";
  const stars = night ? Array.from({ length: 16 }, (_, i) => `<circle cx="${(i * 53) % 380 + 10}" cy="${(i * 37) % 120 + 10}" r="${i % 3 ? 1.2 : 1.8}" fill="#fff" opacity="${0.5 + (i % 4) / 8}"/>`).join("") : "";
  const orb = night
    ? `<circle cx="300" cy="105" r="32" fill="#FFF6DA"/><circle cx="314" cy="95" r="30" fill="${sky[1]}"/><circle cx="300" cy="105" r="60" fill="#FFF6DA" opacity="0.08"/>`
    : `<circle cx="300" cy="80" r="28" fill="#FFE9A8"/><circle cx="300" cy="80" r="52" fill="#FFE9A8" opacity="0.25"/>`;
  return `<svg class="sky" viewBox="0 0 400 230" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
    <defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${sky[0]}"/><stop offset="0.6" stop-color="${sky[1]}"/><stop offset="1" stop-color="${sky[2]}"/></linearGradient></defs>
    <rect width="400" height="230" fill="url(#sky)"/>${stars}${orb}
    <g fill="#fff" opacity="${night ? 0.12 : 0.6}"><ellipse cx="110" cy="50" rx="58" ry="16"/><ellipse cx="140" cy="40" rx="34" ry="18"/><ellipse cx="80" cy="44" rx="26" ry="12"/></g>
    <g fill="${silhouette}">
      <path d="M0 190 Q 40 175 80 186 L 80 230 L 0 230 Z"/>
      <rect x="150" y="95" width="10" height="135"/><rect x="146" y="120" width="18" height="4"/><rect x="146" y="150" width="18" height="4"/><path d="M148 95 L155 80 L162 95 Z"/>
      <path d="M220 230 L220 180 Q 245 140 270 180 L270 230 Z"/><rect x="243" y="128" width="4" height="16"/>
      <path d="M300 230 L300 196 L330 186 L360 196 L360 230 Z"/><path d="M0 210 L400 205 L400 230 L0 230 Z"/>
      <circle cx="40" cy="200" r="14"/><circle cx="380" cy="198" r="16"/><circle cx="190" cy="206" r="12"/>
    </g>
    ${night ? `<g fill="#FFC86B"><circle cx="155" cy="135" r="1.6"/><circle cx="155" cy="165" r="1.6"/><circle cx="245" cy="190" r="1.6"/><circle cx="330" cy="205" r="1.6"/></g>` : ""}
  </svg>`;
}

const iconCircle = (icon, color, size = 44) =>
  `<span class="soft-icon tint" style="--c:${color};width:${size}px;height:${size}px;font-size:${Math.round(size * 0.52)}px"><i class="ph-fill ${icon}"></i></span>`;

function verdictCard(v, { asked } = {}) {
  if (!v) return "";
  const kinds = { fair: ["fair", "ph-check-circle", "Fair"], "a little high": ["high", "ph-warning-circle", "A little high"],
                  overpriced: ["over", "ph-x-circle", "Overpriced"], range: ["range", "ph-info", "Fair range"] };
  const [kind, icon, label] = kinds[v.verdict] || ["unknown", "ph-question", "Not sure"];
  const low = Number(v.fair_low_inr) || 0, high = Number(v.fair_high_inr) || low;
  const ask = Number(v.asked_inr || asked) || 0;
  const max = Math.max(high * 1.6, ask * 1.1, 1);
  const say = phrase(v.say || (/(auto|taxi|cab|ride|rickshaw)/i.test(v.item) ? "Please go by the meter." : /(water|bottle|mrp|packaged)/i.test(v.item) ? "Please give it at MRP." : "Please reduce the price a little."));
  return `<div class="verdict ${kind} reveal">
    <span class="badge"><i class="ph-fill ${icon}"></i>${label}</span>
    <div class="item">${esc(v.item)}</div>
    <div><div class="caption">Fair price</div><div class="price num">${range(low, high).replace("–", " – ")}</div>
      <div class="caption">${foreign((low + high) / 2)}${ask ? ` · You were asked ${inr(ask)}` : ""}</div></div>
    <div class="bar"><div class="fair" style="left:${low / max * 100}%;width:${Math.max(2, (high - low) / max * 100)}%"></div>${ask ? `<div class="asked" style="left:calc(${Math.min(ask / max, 1) * 100}% - 2px)"></div>` : ""}</div>
    ${v.source ? `<div class="src"><i class="ph ph-receipt"></i>${esc(v.source)}</div>` : ""}
    ${say ? `<div class="say"><div class="grow"><div class="caption" style="font-weight:600">Say it</div><div class="headline">${esc(say.roman)}</div>
      <div class="caption">${esc(say.hindi)}</div><div class="caption">${esc(say.english)}</div></div>
      <button class="speak" data-speak="${esc(say.hindi)}" aria-label="Say it aloud"><i class="ph-fill ph-speaker-high"></i></button></div>` : ""}
  </div>`;
}

function stepsBlock(steps) {
  if (!steps?.length) return "";
  return `<details><summary class="steps-toggle"><i class="ph ph-list-checks"></i> Steps: ${steps.length} <i class="ph ph-caret-right"></i></summary>
    <ol class="steps-list" style="margin-top:10px">${steps.map((s) => `<li><code>${esc(s.tool)}</code><span>${esc(s.summary)}</span></li>`).join("")}</ol></details>`;
}

function addRecord(title, asked, verdict, icon) {
  if (!title) return;
  const kind = { fair: "fair", "a little high": "high", overpriced: "over" }[verdict] || "unknown";
  state.records.unshift({ title, asked, verdict: kind, icon });
  save();
}

// MARK: Home

function renderHome() {
  const now = indiaNow();
  const hour = now.getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening";
  const plan = dayPlan(state.day);
  const visited = plan.entries.filter((e) => state.visited.has(`${state.day}:${e.spot.id}`)).length;
  const next = plan.entries.find((e) => !state.visited.has(`${state.day}:${e.spot.id}`)) || plan.entries[0]
    || { spot: { id: "indiagate", ...SPOTS.indiagate } };
  const leg = legBetween(HOTEL, next.spot);
  const name = state.name || "Traveller";
  const home = wayHome();

  $("#screen-home").innerHTML = `
    <header class="home-header">
      <div class="grow" style="display:grid;gap:6px">
        <div class="greeting"><i class="ph ${hour >= 18 || hour < 6 ? "ph-moon-stars" : "ph-sun"}"></i>${greeting} · ${now.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" })}</div>
        <h1 class="large-title">Namaste, ${esc(name)}</h1>
        <div class="place-line"><i class="ph-fill ph-navigation-arrow"></i>New Delhi</div>
      </div>
      <button class="circle-btn ask-btn pressable" data-action="ask" aria-label="Ask Candor anything"><i class="ph-fill ph-sparkle"></i></button>
      <button class="avatar pressable" data-action="me" aria-label="Me">${esc(name.trim()[0]?.toUpperCase() || "T")}<span class="dot"></span></button>
    </header>

    <div class="quick">
      ${[["sos", "SOS", "#FF3B30", "#FF6B5C", "conic-gradient(#FF3B30, #FF6B5C, #FF3B30)", '<span class="sos-text">SOS</span>'],
         ["interpreter", "Interpreter", "#409EFA", "#1AA8B8", "conic-gradient(#409EFA, #1AA8B8, #409EFA)", '<i class="ph-fill ph-chats-teardrop"></i>'],
         ["converter", "Converter", "#21B887", "#FFA83D", "conic-gradient(#21B887, #FFA83D, #21B887)", '<i class="ph-bold ph-currency-circle-dollar"></i>']]
        .map(([id, title, a, b, ring, glyph]) => `<button class="bubble pressable" data-tool="${id}" aria-label="${title}">
          <span class="ring" style="background:${ring}"><span class="inner"><span class="disc" style="background:linear-gradient(135deg, ${a}, ${b})">${glyph}</span></span></span>${title}</button>`).join("")}
    </div>

    <button class="hero pressable" data-goto="trip" aria-label="Open today's plan">
      <div class="scene">${citySky()}<img class="gate" src="/assets/img/IndiaGate3D.png" alt="">
        <div class="shade"></div>
        <div class="words">
          <span class="city-pill"><i class="ph-fill ph-map-pin"></i>Delhi</span>
          <div class="title2" style="color:#fff">${esc(plan.day.title)}</div>
          <div style="font-size:15.5px;opacity:0.9">Delhi · Day ${state.day + 1} of ${planDays()}</div>
        </div>
      </div>
      <div class="bottom">
        <div class="row" style="flex-wrap:wrap;gap:8px">
          <span class="chip"><i class="ph-bold ph-map-pin-line"></i>${plan.entries.length} places</span>
          <span class="chip"><i class="ph-fill ph-clock"></i>${duration(plan.travel)}</span>
          <span class="chip"><i class="ph-bold ph-currency-inr"></i>${plan.fare}</span>
        </div>
        ${visited ? `<div class="row" style="font-size:14px;color:var(--emerald);font-weight:600"><progress max="${plan.entries.length}" value="${visited}" style="flex:1;accent-color:var(--emerald)"></progress>${visited} of ${plan.entries.length} visited</div>` : ""}
        <div class="row"><span class="grow ink" style="font-weight:600;font-size:16px">Open today's plan</span><span class="go-arrow"><i class="ph-bold ph-arrow-right"></i></span></div>
      </div>
    </button>

    <div class="section-title"><h2 class="title2">Explore your way</h2>
      <p class="sub">Wander on your own with Candor in your pocket, or walk with a verified local who knows every lane.</p></div>

    <div class="velvet emerald guide-card">
      <img class="art" src="/assets/img/Adventure3D.png" alt="">
      <div class="copy">
        <h3 class="title2" style="color:#fff;font-weight:600">Want a local by your side?</h3>
        <p class="sub">Verified guides who know every lane, by the hour or for the day, from ₹500/h.</p>
        <button class="pill cream pressable" data-action="guides"><i class="ph-fill ph-person-simple-walk"></i>Travel with a guide</button>
      </div>
    </div>

    <button class="card home-card pressable" data-action="wayhome" style="width:100%;text-align:left">
      <span class="home-art"><img src="/assets/img/HomePin3D.png" alt=""></span>
      <span class="grow" style="display:grid;gap:3px">
        <span class="title3" style="font-weight:500">Way back home</span>
        <span class="muted" style="font-size:15.5px">${esc(HOTEL.name)}</span>
        <span style="color:var(--emerald);font-size:15px;font-weight:500"><i class="ph-bold ph-person-simple-walk"></i> ${esc(home.text.replace("Way back home · ", ""))}</span>
      </span>
      <span class="round-go"><i class="ph-bold ph-arrow-up-right"></i></span>
    </button>

    <div class="section-title"><h2 class="title2">Getting around</h2>
      <p class="sub">Every honest way to your next stop, from Metro to cab, with the fare a local would pay.</p></div>
    <div style="display:grid;gap:10px">
      <div class="row" style="font-size:15.5px"><i class="ph-fill ph-navigation-arrow" style="color:var(--teal)"></i><span class="ellipsis">${esc(HOTEL.name.split(",")[0])}</span>
        <i class="ph-bold ph-arrow-right" style="color:var(--faint);font-size:13px"></i><strong class="ellipsis" style="font-weight:600">${esc(next.spot.name)}</strong></div>
      <div class="hscroll">${sorted(leg).map((o) => `<button class="mode-card pressable" style="--c:${MODES[o.mode].color}" data-journey="${o.mode}" data-to="${next.spot.id}">
        <div class="row" style="justify-content:space-between">${iconCircle(MODES[o.mode].icon, MODES[o.mode].color, 42)}${o.mode === leg.best ? '<span class="best">Best</span>' : ""}</div>
        <span style="flex:1"></span><span class="headline">${MODES[o.mode].title}</span><span class="fare num">${range(o.low, o.high)}</span><span class="caption">${duration(o.minutes)}</span></button>`).join("")}</div>
    </div>

    <div class="velvet saffron" style="display:grid;gap:16px">
      <div class="row top">
        <div class="grow" style="display:grid;gap:6px"><h2 class="title2" style="font-size:25px">What are you being asked to pay?</h2>
          <p class="sub" style="color:rgba(43,26,16,0.68)">Snap the menu or tell us the fare. Candor shows what locals pay, how far over the ask is, and the polite words to bargain.</p></div>
        <span class="price-art"><i class="ph-fill ph-tag"></i><span class="ok"><i class="ph-bold ph-check"></i></span></span>
      </div>
      <div class="row"><button class="pill amber grow pressable" data-goto="check/scan"><i class="ph ph-scan"></i>Scan a price</button>
        <button class="pill cream grow pressable" data-goto="check/ride"><i class="ph-fill ph-car-profile"></i>Check a ride</button></div>
      <button class="pill cream block pressable" data-tool="interpreter"><i class="ph-fill ph-translate"></i>Say it in Hindi</button>
      <button class="example pressable" data-ask="Auto to India Gate, driver wants ₹300">
        <i class="ph-fill ph-chat-text" style="color:var(--mint);font-size:22px"></i>
        <span class="grow"><span class="caption" style="font-weight:700;display:block">Try an example</span><span style="font-weight:500">Auto to India Gate, driver wants ₹300</span></span>
        <i class="ph-bold ph-arrow-up-right muted"></i></button>
    </div>`;
}

// MARK: Trip

function renderTrip() {
  const plan = dayPlan(state.day);
  const date = dayDate(state.day);
  const stops = plan.entries.map((e) => e.spot);
  const el = $("#screen-trip");
  const scroll = el.scrollTop;

  el.innerHTML = `
    <div class="top-bar"><span style="width:96px"></span><h1 class="nav-title">Trip</h1>
      <div class="top-actions"><button class="ask-btn" data-action="ask" aria-label="Ask Candor"><i class="ph-fill ph-sparkle"></i></button>
        <button data-action="me" aria-label="More"><i class="ph ph-dots-three-circle"></i></button></div></div>

    <div class="days" role="group" aria-label="Days">${DAYS.slice(0, planDays()).map((_, i) => `<button class="day-pill" aria-pressed="${i === state.day}" data-day="${i}">Day ${i + 1}</button>`).join("")}
      <button class="day-pill" data-action="addday"><i class="ph ph-plus"></i> Add day</button></div>

    <div class="card day-card" style="display:grid;gap:12px">
      <div class="date"><i class="ph ph-calendar-dots"></i>${date.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })} · Delhi</div>
      <h2 class="large-title" style="font-size:30px">${esc(plan.day.title)}</h2>
      <div class="row" style="flex-wrap:wrap;gap:8px"><span class="chip"><i class="ph-bold ph-map-pin-line"></i>${plan.entries.length} stops</span>
        <span class="chip"><i class="ph-fill ph-clock"></i>${duration(plan.travel)}</span><span class="chip"><i class="ph-bold ph-currency-inr"></i>${plan.fare}</span>
        ${plan.closed ? `<button class="chip closed-chip" data-action="fixday"><i class="ph-fill ph-warning-circle"></i>${plan.closed} closed · Fix it</button>` : ""}</div>
    </div>

    <div class="styles" role="group" aria-label="Travel style">
      ${[["budget", "ph-backpack", "Budget", "₹"], ["comfort", "ph-suitcase-rolling", "Comfort", "₹₹"], ["luxury", "ph-crown", "Luxury", "₹₹₹"]]
        .map(([id, icon, title, tier]) => `<button class="style ${id} pressable" aria-pressed="${state.style === id}" data-style="${id}"><i class="ph-fill ${icon}"></i>${title}<span class="tier">${tier}</span></button>`).join("")}
    </div>

    <div class="map-card">${mapImage(stops)}
      <span class="map-note">Google Maps</span>
      <a class="pill cream map-open" style="height:38px;font-size:14px" target="_blank" rel="noopener"
         href="https://www.google.com/maps/dir/${[HOTEL, ...stops].map((p) => `${p.lat},${p.lng}`).join("/")}"><i class="ph ph-arrow-square-out"></i>Open in Maps</a>
    </div>

    <div class="card start-card"><span class="start-dot"><i class="ph-fill ph-navigation-arrow"></i></span>
      <span class="grow"><span class="caption" style="display:block">Start</span><span style="font-size:17px">${esc(HOTEL.name)}</span></span>
      <span class="muted num" style="font-size:17px">${clock(plan.start)}</span></div>

    <div class="hint-row"><span><i class="ph ph-check-circle" style="color:var(--mint)"></i> Tick each place when you get there</span>
      <span class="ink"><i class="ph ph-arrows-down-up"></i> ${plan.entries.filter((e) => state.visited.has(`${state.day}:${e.spot.id}`)).length}/${plan.entries.length}</span></div>

    ${plan.entries.map((entry, index) => {
      const key = `${state.day}:${entry.spot.id}`;
      const pick = state.choices[key] || entry.leg.best;
      return `
      <div class="leg">
        <div class="leg-head"><i class="ph-bold ph-path"></i><span class="grow">How will you get to ${esc(entry.spot.name)}?</span>
          <button class="ink" style="font-size:15.5px" data-journey="${pick}" data-to="${entry.spot.id}" data-from-index="${index}">Compare</button></div>
        <div class="leg-options">${sorted(entry.leg).map((o) => `<button class="opt" aria-pressed="${o.mode === pick}" data-pick="${o.mode}" data-key="${key}">
          <span class="ic tint" style="--c:${MODES[o.mode].color}"><i class="ph-fill ${MODES[o.mode].icon}"></i></span>
          <span class="t">${MODES[o.mode].title}</span><span class="f num">${range(o.low, o.high)}</span><span class="m">${duration(o.minutes)}</span></button>`).join("")}</div>
      </div>
      <div class="card stop ${state.visited.has(key) ? "visited" : ""}" data-stop="${entry.spot.id}">
        <button class="stop-head" data-toggle="${entry.spot.id}">
          <span class="stop-num">${state.visited.has(key) ? '<i class="ph-bold ph-check"></i>' : index + 1}</span>
          <span class="grow"><span class="stop-name" style="display:block">${esc(entry.spot.name)}</span>
            ${entry.closed
              ? `<span class="closed-note"><i class="ph-fill ph-warning-circle"></i>${esc(entry.note)}</span>`
              : `<span class="muted num" style="font-size:15.5px">${clock(entry.arrival)}–${clock(entry.departure)} · ${duration(entry.stay)} there</span>
                 ${entry.note ? `<span class="hours-note"><i class="ph ph-clock"></i>${esc(entry.note)}</span>` : ""}`}</span>
          <i class="ph ph-caret-down chev"></i></button>
        <div class="stop-body"><div><div class="inner" data-guide="${entry.spot.id}"></div></div></div>
      </div>`;
    }).join("")}

    <div class="row"><button class="pill ink grow pressable" data-action="addplace"><i class="ph-bold ph-plus"></i>Add a place</button>
      <button class="pill outline grow pressable" data-action="editday"><i class="ph ph-pencil-simple"></i>Edit day</button></div>`;
  el.scrollTop = scroll;
  if (openStop) expandStop(openStop, false);
  loadHours(state.dayStops.slice(0, planDays()).flat());
}

let openStop = null;
const guides = {};

async function expandStop(id, toggle = true) {
  const card = $(`.stop[data-stop="${id}"]`);
  if (!card) return;
  if (toggle && card.hasAttribute("open")) { card.removeAttribute("open"); openStop = null; return; }
  $$(".stop[open]").forEach((other) => other !== card && other.removeAttribute("open"));
  card.setAttribute("open", "");
  openStop = id;
  const spot = placeById(id);
  const key = `${state.day}:${id}`;
  const inner = $(`[data-guide="${id}"]`, card);
  const draw = (info) => {
    inner.innerHTML = `
      <button class="visit-btn" data-visit="${key}"><i class="${state.visited.has(key) ? "ph-fill" : "ph"} ph-check-circle"></i>${state.visited.has(key) ? "Visited" : "Mark as visited"}</button>
      <div class="headline">What to do there</div>
      ${info ? `${info.rating || info.hoursToday || hoursText(id, dayDate(state.day)) ? `<div class="muted" style="font-size:15px">${info.rating ? `<i class="ph-fill ph-star"></i> ${info.rating}` : ""}${info.rating && info.hoursToday ? " · " : ""}${hoursText(id, dayDate(state.day)) ? `${hoursText(id, dayDate(state.day))} on ${dayDate(state.day).toLocaleDateString("en-US", { weekday: "long" })}` : info.hoursToday ? `Open today ${esc(info.hoursToday)}` : ""}</div>` : ""}
        <div style="font-size:16px">${esc(info.summary || spot.blurb)}</div>
        <ul class="todo">${info.thingsToDo.map((t) => `<li><i class="ph-fill ph-sparkle"></i><span>${esc(t)}</span></li>`).join("")}</ul>
        <div class="caption" style="color:var(--faint)">From ${esc(info.source)}</div>`
        : `<div class="skeleton" style="width:70%"></div><div class="skeleton"></div><div class="skeleton" style="width:85%"></div>`}
      <div class="suggests">${["Best time to go?", "What should it cost?", "Any scams to watch for?", "What should I eat nearby?"].map((q) => `<button class="suggest" data-place-q="${esc(q)}" data-place="${id}">${q}</button>`).join("")}</div>
      <div class="place-answers" data-answers="${id}">${(guides[id]?.answers || []).map(answerHTML).join("")}</div>
      <form class="ask-row" data-place-form="${id}"><input type="text" placeholder="Ask about ${esc(spot.name)}…" aria-label="Ask about ${esc(spot.name)}" autocomplete="off">
        <button class="send" type="submit" aria-label="Ask"><i class="ph-bold ph-arrow-up"></i></button></form>`;
  };
  draw(guides[id]?.info);
  if (!guides[id]?.info) {
    guides[id] = guides[id] || { answers: [] };
    const url = `/v1/place?name=${encodeURIComponent(spot.name + ", Delhi")}&lat=${spot.lat}&lng=${spot.lng}&language=${encodeURIComponent(state.language)}`;
    // Google Maps first, which is quick; then Gemini's ideas replace Candor's own.
    try {
      guides[id].info = await api(`${url}&ideas=0`);
    } catch {
      guides[id].info = { summary: spot.blurb, thingsToDo: [spot.tip, "Go early for fewer crowds and softer light.", "Carry water and small notes."], source: "Candor" };
    }
    if (openStop === id) draw(guides[id].info);
    try {
      const full = await api(url);
      if (full.source !== guides[id].info.source || full.thingsToDo.join() !== guides[id].info.thingsToDo.join()) {
        guides[id].info = full;
        if (openStop === id) {
          const list = $(`[data-guide="${id}"] .todo`);
          if (list) {
            list.outerHTML = `<ul class="todo reveal">${full.thingsToDo.map((t) => `<li><i class="ph-fill ph-sparkle"></i><span>${esc(t)}</span></li>`).join("")}</ul>`;
            const source = $(`[data-guide="${id}"] .todo + .caption`);
            if (source) source.textContent = `From ${full.source}`;
          }
        }
      }
    } catch { /* Keep what's there. */ }
  }
}

const answerHTML = (a) => `<div class="answer reveal"><div class="q">${esc(a.q)}</div><div class="prose">${a.text ? md(a.text) : '<span class="typing"><span></span><span></span><span></span></span>'}</div></div>`;

async function askPlace(id, question) {
  const spot = placeById(id);
  guides[id] = guides[id] || { answers: [] };
  const entry = { q: question, text: "" };
  guides[id].answers.push(entry);
  const box = $(`[data-answers="${id}"]`);
  box.insertAdjacentHTML("beforeend", answerHTML(entry));
  const node = box.lastElementChild;
  const plan = dayPlan(state.day);
  const leg = plan.entries.find((e) => e.spot.id === id)?.leg;
  const fares = leg ? `Fair fares from ${leg.from}: ${sorted(leg).slice(0, 4).map((o) => `${MODES[o.mode].title} ${range(o.low, o.high)}`).join(", ")}.` : "";
  const info = guides[id].info;
  try {
    const reply = await api("/v1/place/ask", { method: "POST", body: JSON.stringify({
      name: spot.name, question, language: state.language,
      context: [info?.summary || spot.blurb, info?.hoursToday ? `Open today ${info.hoursToday}.` : "", spot.tip, fares].join(" ") }) });
    entry.text = reply.text;
  } catch (error) {
    entry.text = /cost|price|fare/i.test(question) ? `${spot.tip}\n\n${fares}` : `${spot.tip}\n\n_${error.message}_`;
  }
  node.outerHTML = answerHTML(entry);
}

// MARK: Check

function renderCheck() {
  const colors = { fair: "var(--mint)", high: "#D9932F", over: "#C2412E", unknown: "var(--faint)" };
  $("#screen-check").innerHTML = `
    <div style="display:grid;gap:8px;padding-top:12px"><h1 class="large-title">Check</h1>
      <p class="sub">Know the fair price before you pay, ride safely, and get help the moment you need it.</p></div>
    <div style="display:grid;gap:14px">
      <button class="velvet burgundy check-card pressable" data-goto="check/scan"><span class="glyph"><i class="ph ph-scan" style="color:#F3C9A8"></i></span>
        <span class="grow" style="display:grid;gap:4px"><span class="title2" style="color:#fff;font-weight:500">Scan a price</span><span class="sub">Point at a menu, tag or bill and see what it should cost</span></span>
        <span class="arrow"><i class="ph-bold ph-arrow-right"></i></span></button>
      <button class="velvet emerald check-card pressable" data-goto="check/ride"><span class="glyph"><i class="ph-fill ph-car" style="color:#58E0A8"></i></span>
        <span class="grow" style="display:grid;gap:4px"><span class="title2" style="color:#fff;font-weight:500">Check a ride</span><span class="sub">The meter fare for autos and taxis, before you get in</span></span>
        <span class="arrow"><i class="ph-bold ph-arrow-right"></i></span></button>
    </div>
    <h2 class="title2">Stay safe</h2>
    <div class="grid2">
      ${[["tips", "ph-lightbulb", "var(--teal)", "Travel smart", "Simple tips to travel with ease"],
         ["interpreter", "ph-chats-teardrop", "var(--sky)", "Interpreter", "Speak your language, they hear theirs"],
         ["converter", "ph-currency-circle-dollar", "var(--mint)", "Converter", "Rupees to your money"],
         ["sos", "ph-siren", "var(--coral)", "Emergency", "Police, help and helplines"]]
        .map(([id, icon, color, title, desc]) => `<button class="card tool-card pressable" data-tool="${id}">${iconCircle(icon, color, 48)}<span class="t">${title}</span><span class="d">${desc}</span></button>`).join("")}
    </div>
    <div class="row" style="justify-content:space-between"><h2 class="title2">Recent checks</h2><span class="ink">${state.records.length} saved</span></div>
    <div class="list">${state.records.slice(0, 6).map((r) => `<div class="card record flat">
        <span class="soft-icon tint" style="--c:${colors[r.verdict]}"><i class="ph-fill ${esc(r.icon)}"></i></span>
        <span class="grow ellipsis" style="font-weight:500">${esc(r.title)}</span>
        <span style="text-align:right"><span class="num" style="font-weight:700;display:block">${r.asked ? inr(r.asked) : ""}</span>
          <span style="color:${colors[r.verdict]};font-size:13px;font-weight:600">${{ fair: "Fair", high: "A little high", over: "Overpriced", unknown: "Checked" }[r.verdict]}</span></span></div>`).join("")}</div>`;
}

// MARK: Pushed pages: Scan a price, Check a ride

let pageCleanup = null;
function openPage(title, body, { onMount } = {}) {
  const page = $("#page");
  page.className = "page";
  page.hidden = false;
  page.innerHTML = `<div class="top-bar"><button class="circle-btn" data-action="back" aria-label="Back"><i class="ph-bold ph-caret-left"></i></button>
    <h1 class="nav-title">${esc(title)}</h1><span style="width:46px"></span></div>${body}`;
  page.scrollTop = 0;
  pageCleanup = onMount?.(page) || null;
}
function closePage() {
  const page = $("#page");
  if (page.hidden) return;
  page.classList.add("closing");
  setTimeout(() => { page.hidden = true; page.innerHTML = ""; pageCleanup?.(); pageCleanup = null; }, 240);
}

function scanPage() {
  let photo = null;
  openPage("Price check", `
    <form class="card" id="scanForm" style="display:grid;gap:14px">
      <label class="photo-drop" id="drop"><i class="ph ph-camera"></i><span><strong>Snap a menu, price tag or bill</strong><br><span class="caption">or choose a photo. Optional.</span></span>
        <input type="file" accept="image/*" capture="environment" hidden id="photoIn"></label>
      <div class="field"><label for="what">What is it?</label><textarea class="input" id="what" placeholder="e.g. 1 L bottle of water at a stall near Red Fort">Masala chai and two samosas at a stall in Connaught Place</textarea></div>
      <div class="field"><label for="askedIn">What are they asking? (₹)</label><input class="input num" id="askedIn" type="number" inputmode="numeric" min="1" placeholder="e.g. 150" value="150"></div>
      <button class="pill ink block pressable" id="scanBtn" type="submit"><i class="ph-fill ph-seal-check"></i>Check fair price</button>
    </form>
    <div id="scanOut" style="display:grid;gap:16px"></div>`, {
    onMount(page) {
      $("#photoIn", page).addEventListener("change", async (event) => {
        const file = event.target.files?.[0];
        if (!file) return;
        photo = await shrink(file);
        $("#drop", page).innerHTML = `<img src="data:image/jpeg;base64,${photo}" alt="Your photo"><span class="caption">Tap to change</span>`;
        $("#drop", page).appendChild(event.target);
      });
      $("#scanForm", page).addEventListener("submit", async (event) => {
        event.preventDefault();
        const button = $("#scanBtn", page), out = $("#scanOut", page);
        const question = $("#what", page).value.trim(), asked = Number($("#askedIn", page).value) || undefined;
        if (!question && !photo) return toast("Add a photo or say what it is.");
        button.disabled = true;
        button.innerHTML = '<span class="typing"><span></span><span></span><span></span></span> Candor is checking';
        out.innerHTML = `<div class="card"><div class="skeleton" style="width:60%"></div><div class="skeleton" style="margin-top:10px"></div></div>`;
        try {
          const result = await api("/v1/check", { method: "POST", body: JSON.stringify({ city: "Delhi", question: question || "What is in this photo, and is the price fair?",
            askedINR: asked, imageBase64: photo || undefined, language: state.language }) });
          out.innerHTML = `${stepsBlock(result.steps)}${verdictCard(result.verdict, { asked })}
            ${result.answer ? `<div class="card prose reveal">${md(result.answer)}</div>` : ""}
            ${result.verdict ? `<form class="card" id="shareForm" style="display:grid;gap:10px"><div class="headline">What did you end up paying?</div>
              <p class="sub">Share it anonymously to help the next traveller. No names, no accounts.</p>
              <div class="row"><input class="input num grow" type="number" inputmode="numeric" min="1" id="paidIn" placeholder="₹"><button class="pill outline" type="submit">Share</button></div></form>` : ""}`;
          if (result.verdict) {
            addRecord(result.verdict.item, asked, result.verdict.verdict, "ph-receipt");
            $("#shareForm", page)?.addEventListener("submit", async (e) => {
              e.preventDefault();
              const paid = Number($("#paidIn", page).value);
              if (!paid) return toast("Enter what you paid.");
              try {
                await api("/v1/community/prices", { method: "POST", body: JSON.stringify({ city: "Delhi", item: result.verdict.item, paidINR: paid, askedINR: asked,
                  fairLowINR: result.verdict.fair_low_inr, fairHighINR: result.verdict.fair_high_inr }) });
                toast("Thank you. The next traveller will see it.");
                e.target.remove();
              } catch (error) { toast(error.message); }
            });
          }
        } catch (error) {
          out.innerHTML = `<div class="card" style="color:#B42318;font-weight:600">${esc(error.message)}</div>`;
        } finally {
          button.disabled = false;
          button.innerHTML = '<i class="ph-fill ph-seal-check"></i>Check fair price';
        }
      });
    },
  });
}

async function shrink(file) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1280 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL("image/jpeg", 0.72).split(",")[1];
}

function ridePage() {
  const places = [{ id: "hotel", ...HOTEL }, ...Object.entries(SPOTS).map(([id, s]) => ({ id, ...s }))];
  const ride = { from: "hotel", to: "cp", mode: "auto", night: isNight(), asked: "" };
  const options = (selected) => places.map((p) => `<option value="${p.id}" ${p.id === selected ? "selected" : ""}>${esc(p.name)}</option>`).join("");
  openPage("Ride fare", `
    <div class="map-card" id="rideMap" style="height:200px"></div>
    <div class="card" style="display:grid;gap:12px">
      <div class="field"><label for="fromIn">From</label><select class="input" id="fromIn">${options(ride.from)}</select></div>
      <div class="field"><label for="toIn">To</label><select class="input" id="toIn">${options(ride.to)}</select></div>
      <div class="segmented" role="group" aria-label="Ride">${[["auto", "Auto"], ["taxi", "Taxi"], ["ac", "AC taxi"]].map(([id, t]) => `<button type="button" data-ride-mode="${id}" aria-pressed="${id === ride.mode}">${t}</button>`).join("")}</div>
      <div class="toggle"><span>Night fare (11 pm to 5 am)</span><button class="switch" role="switch" aria-checked="${ride.night}" id="nightIn" aria-label="Night fare"></button></div>
      <div class="field"><label for="rideAsk">What is the driver asking? (₹)</label><input class="input num" id="rideAsk" type="number" inputmode="numeric" min="1" placeholder="Optional"></div>
    </div>
    <div id="rideOut"></div>
    <div class="card" style="display:grid;gap:12px">
      <div class="row"><i class="ph-fill ph-notebook" style="font-size:24px"></i><span class="title3">Official fare chart</span></div>
      ${[["ph-car-profile", "var(--teal)", "Auto", "₹30 for the first 1.5 km, then ₹11/km. +25% from 11 pm to 5 am."],
         ["ph-car", "var(--teal)", "Taxi", "₹40 for the first 1 km, then ₹17/km. +25% from 11 pm to 5 am."],
         ["ph-snowflake", "var(--teal)", "AC Taxi", "₹40 for the first 1 km, then ₹20/km. +25% from 11 pm to 5 am."]]
        .map(([icon, color, t, d]) => `<div class="row top"><i class="ph-fill ${icon}" style="color:${color};font-size:26px;margin-top:2px"></i><div><div style="font-size:17px">${t}</div><div class="muted" style="font-size:15px">${d}</div></div></div>`).join("")}
      <div class="caption">Delhi Transport Dept. fare chart (2022 revision). Fair range allows +20% for traffic and rounding. Verify current rates before relying on them.</div>
    </div>`, {
    onMount(page) {
      const draw = () => {
        const from = places.find((p) => p.id === ride.from), to = places.find((p) => p.id === ride.to);
        const road = km(from, to) * 1.35;
        const fare = meter(ride.mode, road, ride.night);
        const asked = Number(ride.asked) || 0;
        const high = Math.round(fare * 1.2);
        const verdict = !asked ? "range" : asked <= high ? "fair" : asked <= high * 1.3 ? "a little high" : "overpriced";
        $("#rideMap", page).innerHTML = `${mapImage([to], { home: from, h: 260 })}<span class="map-note">${road.toFixed(1)} km by road</span>`;
        $("#rideOut", page).innerHTML = verdictCard({ item: `${{ auto: "Auto", taxi: "Taxi", ac: "AC taxi" }[ride.mode]} to ${to.name}`, fair_low_inr: fare, fair_high_inr: high,
          asked_inr: asked, verdict, source: "Delhi Transport Dept. fare chart (2022 revision)", say: "Please go by the meter." });
      };
      $("#fromIn", page).addEventListener("change", (e) => { ride.from = e.target.value; draw(); });
      $("#toIn", page).addEventListener("change", (e) => { ride.to = e.target.value; draw(); });
      $("#rideAsk", page).addEventListener("input", (e) => { ride.asked = e.target.value; draw(); });
      $("#rideAsk", page).addEventListener("change", () => {
        const to = places.find((p) => p.id === ride.to);
        if (Number(ride.asked)) addRecord(`${{ auto: "Auto", taxi: "Taxi", ac: "AC taxi" }[ride.mode]} to ${to.name}`, Number(ride.asked),
          $("#rideOut .badge", page)?.textContent.trim().toLowerCase().replace("not sure", ""), "ph-car-profile");
      });
      $("#nightIn", page).addEventListener("click", (e) => { ride.night = !ride.night; e.currentTarget.setAttribute("aria-checked", ride.night); draw(); });
      $$("[data-ride-mode]", page).forEach((b) => b.addEventListener("click", () => {
        ride.mode = b.dataset.rideMode;
        $$("[data-ride-mode]", page).forEach((x) => x.setAttribute("aria-pressed", x === b));
        draw();
      }));
      draw();
    },
  });
}

// MARK: Sheets

let sheetCleanup = null;
function openSheet(html, { onMount, foot = "" } = {}) {
  const sheet = $("#sheet"), backdrop = $("#backdrop");
  sheet.className = "sheet";
  sheet.innerHTML = `<div class="grabber"></div>${html}${foot ? `<div class="sheet-foot">${foot}</div>` : ""}`;
  sheet.hidden = false;
  backdrop.hidden = false;
  sheetCleanup = onMount?.(sheet) || null;
}
function closeSheet() {
  const sheet = $("#sheet");
  if (sheet.hidden) return;
  sheet.classList.add("closing");
  $("#backdrop").hidden = true;
  setTimeout(() => { sheet.hidden = true; sheet.innerHTML = ""; sheetCleanup?.(); sheetCleanup = null; }, 230);
}
const sheetHead = (title, extra = "") =>
  `<div class="sheet-head"><span style="width:40px"></span><span class="title">${esc(title)}</span>
    <div class="row" style="gap:4px">${extra}<button class="circle-btn" data-action="close" aria-label="Close" style="width:40px;height:40px"><i class="ph-bold ph-x"></i></button></div></div>`;

function tipsSheet() {
  openSheet(`${sheetHead("Travel smart")}<div class="sheet-body">
    <p class="sub">Most people you'll meet are honest and helpful. These few tips help you travel with confidence.</p>
    <div class="list">${TIPS.map((t) => `<details class="tip"><summary>${iconCircle(t.icon, "var(--teal)", 40)}<span class="grow">${esc(t.title)}</span><i class="ph ph-caret-down muted"></i></summary>
      <div class="body"><div class="muted">${esc(t.how)}</div><div><strong>What to do:</strong> ${esc(t.todo)}</div></div></details>`).join("")}</div></div>`);
}

function interpreterSheet() {
  const categories = ["Prices", "Rides", "Food", "Help"];
  let category = "Prices";
  openSheet(`${sheetHead("Interpreter")}<div class="sheet-body">
    <form class="card" id="trForm" style="display:grid;gap:10px">
      <div class="headline">Say anything in Hindi</div>
      <textarea class="input" id="trIn" placeholder="Type in ${esc(state.language)}, e.g. Can you take me to the metro station?" style="min-height:70px"></textarea>
      <button class="pill ink block" id="trBtn" type="submit"><i class="ph-bold ph-translate"></i>Translate</button>
      <div id="trOut"></div>
    </form>
    <div class="segmented" role="group" aria-label="Phrases">${categories.map((c) => `<button type="button" data-cat="${c}" aria-pressed="${c === category}">${c}</button>`).join("")}</div>
    <div class="list" id="phrases"></div></div>`, {
    onMount(sheet) {
      const draw = () => {
        $("#phrases", sheet).innerHTML = PHRASES.filter((p) => p.category === category).map((p) => `<div class="phrase">
          <div class="grow"><div class="hi">${esc(p.hindi)}</div><div class="ro">${esc(p.roman)}</div><div class="en">${esc(p.english)}</div></div>
          <button class="say speak" data-speak="${esc(p.hindi)}" aria-label="Say it aloud" style="width:52px;height:40px;border-radius:999px;background:rgba(122,31,54,0.12);color:var(--ink);display:grid;place-items:center;font-size:20px"><i class="ph-fill ph-speaker-high"></i></button></div>`).join("");
      };
      $$("[data-cat]", sheet).forEach((b) => b.addEventListener("click", () => {
        category = b.dataset.cat;
        $$("[data-cat]", sheet).forEach((x) => x.setAttribute("aria-pressed", x === b));
        draw();
      }));
      $("#trForm", sheet).addEventListener("submit", async (event) => {
        event.preventDefault();
        const text = $("#trIn", sheet).value.trim();
        if (!text) return;
        const button = $("#trBtn", sheet), out = $("#trOut", sheet);
        button.disabled = true;
        out.innerHTML = '<div class="skeleton" style="width:70%"></div>';
        try {
          const r = await api("/v1/translate", { method: "POST", body: JSON.stringify({ text, to: "Hindi" }) });
          out.innerHTML = `<div class="phrase reveal" style="background:var(--ink-soft)"><div class="grow"><div class="hi">${esc(r.translation)}</div><div class="ro">${esc(r.roman)}</div></div>
            <button data-speak="${esc(r.translation)}" aria-label="Say it aloud" style="width:52px;height:40px;border-radius:999px;background:rgba(122,31,54,0.12);color:var(--ink);display:grid;place-items:center;font-size:20px"><i class="ph-fill ph-speaker-high"></i></button></div>`;
        } catch (error) { out.innerHTML = `<div class="caption">${esc(error.message)}</div>`; }
        finally { button.disabled = false; }
      });
      draw();
    },
  });
}

function converterSheet() {
  openSheet(`${sheetHead("Converter")}<div class="sheet-body">
    <div class="velvet pearl" style="display:grid;gap:12px">
      <div class="field"><label for="amt">Amount in rupees</label><input class="input num" id="amt" type="number" inputmode="decimal" value="1500" style="font-size:28px;font-weight:700"></div>
      <div class="field"><label for="cur">Your money</label><select class="input" id="cur">${Object.keys(RATES).map((c) => `<option ${c === state.currency ? "selected" : ""}>${c}</option>`).join("")}</select></div>
      <div class="title2 num" id="convOut" style="font-size:34px"></div>
      <div class="caption">Indicative rate. Check your bank's rate before large payments.</div>
    </div>
    <div class="card" style="display:grid;gap:10px"><div class="headline">Quick reference</div><div id="quickRef" style="display:grid;gap:8px"></div></div></div>`, {
    onMount(sheet) {
      const draw = () => {
        state.currency = $("#cur", sheet).value;
        store.set("currency", state.currency);
        $("#convOut", sheet).textContent = foreign(Number($("#amt", sheet).value) || 0);
        $("#quickRef", sheet).innerHTML = [[20, "Bottle of water"], [30, "Masala chai"], [60, "Auto, short hop"], [250, "Thali"], [1300, "Taj Mahal entry"]]
          .map(([n, t]) => `<div class="row"><span class="grow">${t}</span><span class="num" style="font-weight:700">${inr(n)}</span><span class="muted num" style="width:80px;text-align:right">${foreign(n)}</span></div>`).join("");
      };
      $("#amt", sheet).addEventListener("input", draw);
      $("#cur", sheet).addEventListener("change", draw);
      draw();
    },
  });
}

function sosSheet() {
  openSheet(`${sheetHead("Emergency")}<div class="sheet-body">
    <a class="big-call" href="tel:112" style="background:linear-gradient(135deg,#FF3B30,#C2412E)"><i class="ph-fill ph-phone-call" style="font-size:34px"></i>
      <span><span style="display:block;font-size:15px;opacity:0.9">Emergency (police, fire, ambulance)</span><span class="n">112</span></span></a>
    <a class="big-call" href="tel:1800111363" style="background:linear-gradient(135deg,#0F543F,#1B7556)"><i class="ph-fill ph-headset" style="font-size:34px"></i>
      <span><span style="display:block;font-size:15px;opacity:0.9">Incredible India tourist helpline (24×7, multilingual)</span><span class="n" style="font-size:24px">1800-11-1363</span></span></a>
    <button class="pill outline block" data-action="share-location"><i class="ph-fill ph-crosshair"></i>Share my location</button>
    <div class="card" style="display:grid;gap:8px"><div class="headline"><i class="ph-fill ph-lightbulb" style="color:var(--saffron)"></i> Quick tips</div>
      <div>• Move to a busy, official place: station counter, hotel lobby or police booth.</div>
      <div>• Never hand over your passport or cards under pressure.</div>
      <div>• Keep a photo of your passport and visa on your phone.</div></div></div>`);
}

function guidesSheet() {
  openSheet(`${sheetHead("Travel with a guide")}<div class="sheet-body">
    <p class="sub">Every guide is verified by Candor, with a fixed hourly rate you see before you book. Two hours minimum.</p>
    <div class="list">${GUIDES.map((g) => `<div class="guide"><span class="face" style="background:${g.color}">${g.name.split(" ").map((w) => w[0]).join("")}</span>
      <div class="grow" style="display:grid;gap:2px"><div class="headline">${esc(g.name)} <span class="caption"><i class="ph-fill ph-star" style="color:var(--saffron)"></i> ${g.rating} · ${g.tours} tours</span></div>
        <div class="caption">${esc(g.tags)} · ${esc(g.langs)}</div><div style="font-size:15px">${esc(g.bio)}</div></div>
      <button class="pill ink" style="height:40px;padding:0 14px;font-size:14px" data-request="${esc(g.name)}">${inr(g.rate)}/h</button></div>`).join("")}</div></div>`);
}

function journeySheet(toId, mode, fromIndex) {
  let from = toId === "hotel" ? (wayHome().leg?.fromPt || HOTEL) : HOTEL;
  if (fromIndex != null) {
    const plan = dayPlan(state.day);
    from = Number(fromIndex) > 0 ? plan.entries[Number(fromIndex) - 1].spot : HOTEL;
  }
  const to = toId === "hotel" ? HOTEL : placeById(toId);
  const leg = legBetween(from, to);
  let pick = mode || leg.best;
  openSheet(`${sheetHead(`To ${to.name}`)}<div class="sheet-body">
    <div class="map-card" style="height:200px">${mapImage([to], { home: from, h: 260 })}<span class="map-note">${leg.road.toFixed(1)} km by road</span></div>
    <div class="leg-options" style="padding:2px 0 4px;margin-right:-20px" id="jOpts"></div>
    <div id="jDetail"></div></div>`, {
    onMount(sheet) {
      const draw = () => {
        $("#jOpts", sheet).innerHTML = sorted(leg).map((o) => `<button class="opt" aria-pressed="${o.mode === pick}" data-jmode="${o.mode}">
          <span class="ic tint" style="--c:${MODES[o.mode].color}"><i class="ph-fill ${MODES[o.mode].icon}"></i></span>
          <span class="t">${MODES[o.mode].title}</span><span class="f num">${range(o.low, o.high)}</span><span class="m">${duration(o.minutes)}</span></button>`).join("");
        const o = leg.options.find((x) => x.mode === pick);
        const travel = { walk: "walking", metro: "transit", bus: "transit" }[o.mode] || "driving";
        $("#jDetail", sheet).innerHTML = `<div class="card reveal" style="display:grid;gap:12px">
          <div class="row">${iconCircle(MODES[o.mode].icon, MODES[o.mode].color, 48)}<div class="grow"><div class="title3">${MODES[o.mode].title}${o.mode === leg.best ? ' <span class="best">Best</span>' : ""}</div>
            <div class="muted">${duration(o.minutes)} · <span class="num">${range(o.low, o.high)}</span></div></div></div>
          <div>${esc(o.summary)}</div>
          ${["auto", "cab", "erick"].includes(o.mode) ? `<div class="say"><div class="grow"><div class="caption" style="font-weight:600">Say it</div><div class="headline">Meter se chaliye.</div><div class="caption">मीटर से चलिए। · Please go by the meter.</div></div>
            <button class="speak" data-speak="मीटर से चलिए।" aria-label="Say it aloud"><i class="ph-fill ph-speaker-high"></i></button></div>` : ""}
          <a class="pill ink block" target="_blank" rel="noopener" href="${mapsLink(to, travel)}"><i class="ph-fill ph-navigation-arrow"></i>Directions in Google Maps</a></div>`;
        $$("[data-jmode]", sheet).forEach((b) => b.addEventListener("click", () => { pick = b.dataset.jmode; draw(); }));
      };
      draw();
    },
  });
}

function meSheet() {
  openSheet(`${sheetHead("Me")}<div class="sheet-body">
    <div class="row" style="gap:14px"><span class="avatar" style="width:64px;height:64px;font-size:24px">${esc((state.name || "T")[0].toUpperCase())}</span>
      <div><div class="title2">${esc(state.name || "Traveller")}</div><div class="muted">${esc(store.get("profile", null)?.email && !["guest", "Apple", "Google"].includes(store.get("profile", null).email) ? store.get("profile", null).email : "Delhi")} · ${planDays()} days</div></div></div>
    <div class="card" style="display:grid;gap:12px">
      <div class="field"><label for="nameIn">Your name</label><input class="input" id="nameIn" value="${esc(state.name)}" placeholder="What should Candor call you?"></div>
      <div class="field"><label for="langIn">Candor answers in</label><select class="input" id="langIn">${LANGUAGES.map((l) => `<option ${l === state.language ? "selected" : ""}>${l}</option>`).join("")}</select></div>
      <div class="field"><label for="curIn">Your money</label><select class="input" id="curIn">${Object.keys(RATES).map((c) => `<option ${c === state.currency ? "selected" : ""}>${c}</option>`).join("")}</select></div>
    </div>
    <div class="card" style="display:grid;gap:12px" id="tastes"></div>
    <div class="card" style="display:grid;gap:8px"><div class="headline">About this prototype</div>
      <div class="muted" style="font-size:15px">Candor's web version runs on Google Cloud Run. Gemini answers questions and judges prices with tools, Google Maps draws the trip and describes each place, and prices travellers share are kept anonymously in Firestore.</div></div>
    <button class="pill outline block" data-action="reset"><i class="ph ph-arrow-counter-clockwise"></i>Reset trip progress</button>
    <button class="pill outline block" data-action="signout"><i class="ph ph-sign-out"></i>Sign out and start again</button></div>`, {
    onMount(sheet) {
      // What you love and how you like it, as in the app's Me page. Changes re-pick the ideas.
      const profile = store.get("profile", null) || { interests: [], prefs: [] };
      const drawTastes = () => {
        $("#tastes", sheet).innerHTML = `<div class="headline"><i class="ph ph-heart"></i> What you love</div>
          <div class="chips">${INTERESTS.map(([n]) => `<button class="pref" aria-pressed="${profile.interests.includes(n)}" data-me-love="${esc(n)}">${esc(n)}</button>`).join("")}</div>
          <div class="headline" style="margin-top:4px">How you like it</div>
          <div class="chips">${PREFERENCES.map(([n]) => `<button class="pref taste" aria-pressed="${profile.prefs.includes(n)}" data-me-taste="${esc(n)}">${esc(n)}</button>`).join("")}</div>`;
        $$("[data-me-love]", sheet).forEach((b) => b.addEventListener("click", () => {
          const n = b.dataset.meLove;
          profile.interests = profile.interests.includes(n) ? profile.interests.filter((x) => x !== n) : [...profile.interests, n];
          store.set("profile", profile); drawTastes();
        }));
        $$("[data-me-taste]", sheet).forEach((b) => b.addEventListener("click", () => {
          const n = b.dataset.meTaste;
          if (profile.prefs.includes(n)) profile.prefs = profile.prefs.filter((x) => x !== n);
          else if (profile.prefs.length < 3) profile.prefs.push(n);
          else return toast("Up to three.");
          store.set("profile", profile); drawTastes();
        }));
      };
      drawTastes();
      $("#nameIn", sheet).addEventListener("change", (e) => { state.name = e.target.value.trim(); store.set("name", state.name); renderAll(); });
      $("#langIn", sheet).addEventListener("change", (e) => { state.language = e.target.value; store.set("language", state.language); Object.keys(guides).forEach((k) => delete guides[k]); });
      $("#curIn", sheet).addEventListener("change", (e) => { state.currency = e.target.value; store.set("currency", state.currency); });
    },
  });
}

// MARK: Welcome, sign in and onboarding (the app's first run)

const INTERESTS = [
  ["Heritage", "ph-bank", "#C2662E"], ["Street food", "ph-fork-knife", "#E8476A"], ["Markets", "ph-shopping-bag", "#F2A33A"],
  ["Spiritual", "ph-sparkle", "#8C5CF5"], ["Art & crafts", "ph-palette", "#5C54E6"], ["Nightlife", "ph-moon-stars", "#3B3F8F"],
  ["Nature", "ph-leaf", "#1F9D6B"], ["Photography", "ph-camera", "#1AA8B8"],
];
// The app's taste statements (Persona.tasteOptions), with its icons.
const PREFERENCES = [
  ["Street food over fine dining", "ph-bowl-food", "#E8476A"], ["Local gems over famous sights", "ph-diamond", "#5C54E6"],
  ["Happy to walk", "ph-person-simple-walk", "#21B887"], ["Avoid crowds", "ph-users-three", "#C2662E"],
  ["Early starts", "ph-sun-horizon", "#F2A33A"], ["Slow mornings", "ph-coffee", "#8A5A3C"],
  ["Kid-friendly", "ph-baby", "#409EFA"], ["Vegetarian", "ph-carrot", "#1F9D6B"],
];
const PEOPLE = [
  ["solo", "Solo", "Just me, at my own pace", "ph-user"], ["couple", "Couple", "The two of us", "ph-heart"],
  ["family", "Family", "With kids or parents", "ph-users-three"], ["friends", "Friends", "A group of friends", "ph-users"],
];
const CITIES = [
  { name: "Delhi", label: "Delhi, India", guide: "Verified guide", lat: 28.6139, lng: 77.2090 },
  { name: "Agra", label: "Agra, India", guide: "AI guide", lat: 27.1767, lng: 78.0081 },
  { name: "Jaipur", label: "Jaipur, India", guide: "AI guide", lat: 26.9124, lng: 75.7873 },
];

const ob = store.get("profile", null) || {
  email: "", people: "", style: "comfort", interests: [], prefs: [], name: "", language: "English", currency: "USD",
  stops: [],
};
const saveProfile = () => store.set("profile", ob);
const isoDate = (date) => date.toISOString().slice(0, 10);
const dayCount = (stop) => Math.max(1, Math.round((new Date(stop.leave) - new Date(stop.arrive)) / 86_400_000));
const tripDays = () => ob.stops.reduce((sum, s) => sum + dayCount(s), 0);
const shortDate = (iso) => new Date(`${iso}T12:00:00`).toLocaleDateString("en-US", { month: "short", day: "numeric" });

/** The app's postcard: a sunny skyline with India Gate, the Qutub Minar and domes. */
function postcard({ road = false, route = "" } = {}) {
  return `<svg viewBox="0 0 360 170" class="postcard" aria-hidden="true" preserveAspectRatio="xMidYMid slice">
    <defs><linearGradient id="pc-sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7EC3EE"/><stop offset="1" stop-color="#D8EEF8"/></linearGradient></defs>
    <rect width="360" height="170" fill="url(#pc-sky)"/>
    <circle cx="300" cy="44" r="18" fill="#FFE7A0"/><circle cx="300" cy="44" r="30" fill="#FFE7A0" opacity="0.3"/>
    <g fill="#fff"><ellipse cx="250" cy="70" rx="34" ry="11"/><ellipse cx="270" cy="62" rx="20" ry="11"/><ellipse cx="80" cy="40" rx="28" ry="9"/></g>
    <path d="M30 50 q5 -5 10 0 q5 -5 10 0 M60 38 q4 -4 8 0 q4 -4 8 0" stroke="#3A5A7A" stroke-width="1.6" fill="none"/>
    ${route ? `<path d="M60 92 Q 180 10 300 80" stroke="#fff" stroke-width="2" stroke-dasharray="5 5" fill="none"/><circle cx="60" cy="92" r="4" fill="#F2A33A"/><circle cx="300" cy="80" r="4" fill="#F2A33A"/>` : ""}
    <g fill="#C8643A">
      <path d="M40 140 V104 h44 V140 h-12 V122 a10 10 0 0 0 -20 0 V140 Z"/><rect x="36" y="98" width="52" height="8"/><rect x="50" y="90" width="24" height="9"/>
      <rect x="158" y="56" width="10" height="84"/><rect x="154" y="74" width="18" height="4"/><rect x="154" y="98" width="18" height="4"/><rect x="155" y="120" width="16" height="4"/><path d="M158 56 L163 46 L168 56 Z"/>
      <path d="M210 140 V118 q20 -26 40 0 V140 Z"/><rect x="228" y="84" width="4" height="12"/><path d="M220 118 q10 -22 20 0 Z"/>
      <rect x="262" y="112" width="60" height="28"/><path d="M262 112 l30 -14 l30 14 Z"/><rect x="104" y="116" width="40" height="24"/><rect x="110" y="104" width="10" height="12"/><rect x="128" y="108" width="10" height="8"/>
    </g>
    <g fill="#B85530" opacity="0.6"><rect x="46" y="110" width="6" height="8"/><rect x="72" y="110" width="6" height="8"/><rect x="270" y="120" width="8" height="8"/><rect x="288" y="120" width="8" height="8"/><rect x="306" y="120" width="8" height="8"/></g>
    <g fill="#3E8E4E"><circle cx="20" cy="136" r="10"/><circle cx="100" cy="138" r="9"/><circle cx="196" cy="136" r="10"/><circle cx="340" cy="134" r="12"/><circle cx="252" cy="138" r="8"/></g>
    ${road
      ? `<rect y="140" width="360" height="30" fill="#4A4D57"/><path d="M0 155 H360" stroke="#fff" stroke-width="2" stroke-dasharray="12 10"/>
         <g><rect x="40" y="146" width="30" height="10" rx="4" fill="#E5484D"/><circle cx="47" cy="157" r="3" fill="#222"/><circle cx="63" cy="157" r="3" fill="#222"/></g>
         <g><rect x="230" y="150" width="30" height="10" rx="4" fill="#409EFA"/><circle cx="237" cy="161" r="3" fill="#222"/><circle cx="253" cy="161" r="3" fill="#222"/></g>`
      : `<rect y="140" width="360" height="30" fill="#7DB46C"/><rect y="140" width="360" height="5" fill="#5F9A55"/>`}
  </svg>`;
}

const floatCard = (style, icon, color, title, sub) =>
  `<div class="float-card" style="${style}"><span class="fc-icon" style="background:${color}"><i class="ph-fill ${icon}"></i></span><span><b>${title}</b><small>${sub}</small></span></div>`;

function heroArt() {
  return `<div class="hero-art">${postcard()}
    ${floatCard("left:14%;top:-6%", "ph-check-circle", "#21B887", "Auto to India Gate", "₹180 · fair")}
    ${floatCard("right:4%;top:36%", "ph-translate", "#1AA8B8", "कितना हुआ?", "How much is it?")}
    ${floatCard("left:10%;bottom:-10%", "ph-house-line", "#F2A33A", "Way back home", "12 min by metro")}
    <span class="scan-dot"><i class="ph-bold ph-scan"></i></span></div>`;
}

let obStep = "welcome";
function onboard(step = obStep) {
  obStep = step;
  const layer = $("#onboard");
  layer.hidden = false;
  const steps = ["trip", "people", "taste", "you"];
  const index = steps.indexOf(step);
  const progress = index >= 0 ? `<div class="ob-progress">${steps.map((_, i) => `<span class="${i <= index ? "on" : ""}"></span>`).join("")}</div>` : "";
  const back = `<button class="circle-btn" data-ob="back" aria-label="Back"><i class="ph-bold ph-caret-left"></i></button>`;
  const header = (title, sub) => `${progress}<h1 class="ob-title">${title}</h1><p class="sub">${sub}</p>`;
  let body = "", foot = "";

  if (step === "welcome") {
    body = `<div class="wordmark">Candor</div>${heroArt()}
      <div class="ob-center"><h1 class="ob-title" style="text-align:center">Discover India like a local</h1>
      <p class="sub" style="text-align:center">Fair prices, safe rides and your way back home, in your language.</p></div>`;
    foot = `<button class="pill ink block" data-ob="signup">Get Started</button><button class="pill outline block" data-ob="login">Log in</button>`;
  } else if (step === "trip") {
    const ready = ob.stops.length > 0;
    body = `${header("Where are you going?", "Add each city in the order you'll travel. Your dates and hotel let Candor time every day and always guide you home.")}
      <div class="ob-art">${postcard({ road: true, route: ob.stops.length > 1 ? "x" : "" })}</div>
      <div class="ob-stops">${ob.stops.map((s, i) => `<div class="ob-stop"><span class="ob-num">${i + 1}</span>
        <button class="card ob-city" data-ob-edit="${i}"><span class="grow"><span class="title3" style="display:block">${esc(s.label)}</span>
          <span class="muted" style="font-size:14.5px">${shortDate(s.arrive)}–${shortDate(s.leave)} · ${dayCount(s)} days</span>
          ${s.hotel ? `<span class="muted" style="display:block;font-size:14px"><i class="ph ph-bed"></i> ${esc(s.hotel.name)}</span>` : ""}
          <span style="display:block;font-size:13px;color:${s.guide === "Verified guide" ? "var(--mint)" : "var(--muted)"}"><i class="ph-fill ${s.guide === "Verified guide" ? "ph-seal-check" : "ph-map-trifold"}"></i> ${s.guide}</span></span>
          <i class="ph ph-caret-right muted"></i></button></div>`).join("")}
        <button class="ob-add" data-ob="addcity"><span class="plus"><i class="ph-bold ph-plus"></i></span><span><b>${ready ? "Add another city" : "Add your first city"}</b><small>City, dates and where you're staying</small></span></button>
        ${ready ? `<div class="caption"><i class="ph ph-calendar-blank"></i> ${ob.stops.length === 1 ? ob.stops[0].name : `${ob.stops.length} cities`} · ${tripDays()} days</div>` : ""}</div>`;
    foot = `${ready ? "" : '<div class="caption ob-hint"><i class="ph ph-info"></i> Add at least one city to continue</div>'}
      <button class="pill ink block" data-ob="next" ${ready ? "" : "disabled"}>Continue <i class="ph-bold ph-arrow-right"></i></button>`;
  } else if (step === "people") {
    body = `${header("Who's going?", "Travelling alone or with family? Candor sets the pace, picks the places and suggests rides that fit your group.")}
      <div class="grid2">${PEOPLE.map(([id, title, sub, icon]) => `<button class="card ob-choice" aria-pressed="${ob.people === id}" data-people="${id}">
        <span class="ob-face"><i class="ph-fill ${icon}"></i></span><span class="title3">${title}</span><span class="caption">${sub}</span></button>`).join("")}</div>`;
    foot = `<div class="row">${back}<button class="pill ink grow" data-ob="next" ${ob.people ? "" : "disabled"}>Continue <i class="ph-bold ph-arrow-right"></i></button></div>`;
  } else if (step === "taste") {
    const ok = ob.interests.length > 0 && ob.prefs.length > 0;
    body = `${header("How do you like to travel?", "Choose your style, what you love and up to three preferences. Candor uses them to pick places and fair ways to get around.")}
      <h2 class="title3">Travel style</h2>
      <div class="styles">${[["budget", "ph-backpack", "Budget", "₹"], ["comfort", "ph-suitcase-rolling", "Comfort", "₹₹"], ["luxury", "ph-crown", "Luxury", "₹₹₹"]]
        .map(([id, icon, title, tier]) => `<button class="style ${id}" aria-pressed="${ob.style === id}" data-ob-style="${id}"><i class="ph-fill ${icon}"></i>${title}<span class="tier">${tier}</span></button>`).join("")}</div>
      <div class="caption">${{ budget: "Metro, buses, street food", comfort: "Cabs, cafés, good hotels", luxury: "Private car, fine dining" }[ob.style]}</div>
      <h2 class="title3">What do you love?</h2>
      <div class="interests">${INTERESTS.map(([name, icon, color]) => `<button class="interest" aria-pressed="${ob.interests.includes(name)}" data-interest="${name}">
        <span class="tile" style="--c:${color}"><i class="ph-fill ${icon}"></i></span><span>${name}</span></button>`).join("")}</div>
      <div class="row" style="justify-content:space-between"><h2 class="title3">Your preferences</h2><span class="caption">${ob.prefs.length} of 3</span></div>
      <div class="interests">${PREFERENCES.map(([name, icon, color]) => `<button class="interest" aria-pressed="${ob.prefs.includes(name)}" data-pref="${name}">
        <span class="tile" style="--c:${color}"><i class="ph-fill ${icon}"></i></span><span>${name}</span></button>`).join("")}</div>`;
    foot = `${ok ? "" : `<div class="caption ob-hint"><i class="ph ph-info"></i> ${ob.interests.length ? "Pick at least one preference" : "Pick at least one thing you love"}</div>`}
      <div class="row">${back}<button class="pill ink grow" data-ob="next" ${ok ? "" : "disabled"}>Continue <i class="ph-bold ph-arrow-right"></i></button></div>`;
  } else if (step === "you") {
    const route = ob.stops.map((s) => s.name).join(" → ");
    body = `${header("A little about you", "Your name, the language you read best and the money you think in. Every price shows in rupees and your own currency.")}
      <div class="card pass"><div class="row" style="justify-content:space-between"><span class="pass-label">Travel pass</span><i class="ph-fill ph-globe-hemisphere-east muted"></i></div>
        <div class="row" style="gap:14px;margin-top:10px"><span class="avatar" style="width:56px;height:56px;font-size:22px" id="passInitial">${esc((ob.name || "?")[0].toUpperCase())}</span>
          <div class="field grow"><label for="obName">What should we call you?</label><input class="input pass-name" id="obName" value="${esc(ob.name)}" placeholder="Your name" autocomplete="given-name"></div></div>
        <div class="row" style="margin-top:12px;font-size:15px"><i class="ph-fill ph-airplane-tilt" style="color:var(--saffron)"></i> ${esc(route)} · ${tripDays()} days</div>
        <span class="stamp">${esc((ob.stops[0]?.name || "Delhi").toUpperCase())}<br>★<br>WELCOME</span></div>
      <label class="card row" for="obLang" style="gap:12px">${iconCircle("ph-translate", "var(--teal)", 44)}
        <span class="grow"><span class="caption" style="display:block">Candor answers in</span><b id="helloWord">${{ English: "नमस्ते → Hello", Spanish: "नमस्ते → Hola", French: "नमस्ते → Bonjour", German: "नमस्ते → Hallo", Japanese: "नमस्ते → こんにちは" }[ob.language] || "नमस्ते → Hello"}</b></span>
        <select class="input" id="obLang" style="width:auto;min-height:40px">${LANGUAGES.map((l) => `<option ${l === ob.language ? "selected" : ""}>${l}</option>`).join("")}</select></label>
      <label class="card row" for="obCur" style="gap:12px">${iconCircle("ph-currency-inr", "var(--mint)", 44)}
        <span class="grow"><span class="caption" style="display:block">Home currency</span><b id="autoLine"></b></span>
        <select class="input" id="obCur" style="width:auto;min-height:40px">${Object.keys(RATES).map((c) => `<option ${c === ob.currency ? "selected" : ""}>${c}</option>`).join("")}</select></label>
      <div class="caption"><i class="ph ph-device-mobile"></i> Change them any time in Me.</div>`;
    foot = `<div class="row">${back}<button class="pill ink grow" data-ob="build" ${ob.name ? "" : "disabled"}>Build my travel persona <i class="ph-bold ph-arrow-right"></i></button></div>`;
  } else if (step === "setup") {
    const city = ob.stops[0]?.name || "Delhi";
    const lines = [
      ["ph-translate", `Speaking ${ob.language}`, "The app and the agent use your language"],
      ["ph-currency-circle-dollar", `Linking ${ob.currency}`, "Indicative exchange rates"],
      ["ph-book-open-text", `Loading the ${city} guide`, "Fair fares, prices and known scams"],
      ["ph-heart", "Picking places you'll love", ob.interests.join(", ")],
      ["ph-path", "Timing your days and fair fares", "Metro, buses, autos and cabs"],
    ];
    body = `<div style="padding-top:40px;display:grid;gap:8px"><span class="ob-spark"><i class="ph-fill ph-sparkle"></i></span><h1 class="ob-title">Setting up Candor for you</h1>
      <p class="sub" id="setupStep">Step 1 of ${lines.length}</p></div>
      <div class="list" id="setupList">${lines.map(([icon, title, sub], i) => `<div class="list-item setup" data-i="${i}">
        <span class="soft-icon tint" style="--c:var(--ink);border-radius:50%"><i class="ph-fill ${icon}"></i></span>
        <span class="grow"><b style="display:block;font-weight:600">${esc(title)}</b><span class="caption">${esc(sub)}</span></span><span class="state"></span></div>`).join("")}</div>`;
  } else if (step === "plan") {
    const route = ob.stops.map((s) => s.name).join(" → ");
    body = `<div class="ob-art" style="margin-top:20px">${postcard({ road: true, route: "x" })}</div>
      <h1 class="ob-title">Want Candor to plan your days?</h1><p class="sub">${esc(route)} · ${tripDays()} days from ${shortDate(ob.stops[0].arrive)}</p>
      <button class="velvet maroon plan-opt" data-ob="planit"><span class="po-icon"><i class="ph-fill ph-sparkle"></i></span>
        <span class="grow"><b>Plan it for me</b><small>Places for your interests, grouped by area, with travel times and fair fares.</small></span><i class="ph-bold ph-arrow-right"></i></button>
      <button class="card plan-opt" data-ob="ownplan" style="color:var(--text)"><span class="po-icon" style="background:var(--teal);color:#fff"><i class="ph-bold ph-note-pencil"></i></span>
        <span class="grow"><b>I have my own plan</b><small class="muted">Start with Candor's suggestions and change any place.</small></span><i class="ph-bold ph-arrow-right muted"></i></button>
      <button class="ink" data-ob="later" style="justify-self:center;font-weight:600">Later</button>`;
  } else if (step === "ready") {
    const n = Math.min(tripDays(), DAYS.length);
    const places = DAYS.slice(0, n).reduce((sum, d) => sum + d.stops.length, 0);
    const route = ob.stops.map((s) => s.name).join(" → ");
    body = `<div style="padding-top:30px;display:grid;gap:6px"><span class="ob-spark"><i class="ph-fill ph-sparkle"></i></span>
      <h1 class="ob-title">Your plan is ready</h1><p class="sub">${esc(route)} · ${tripDays()} days from ${shortDate(ob.stops[0].arrive)}</p></div>
      <div class="stat-tiles">${[["ph-calendar-blank", "var(--indigo)", tripDays(), "days"], ["ph-map-pin", "var(--rose)", places, "places"], ["ph-currency-inr", "var(--teal)", "Fair", "fares"]]
        .map(([icon, color, n2, label]) => `<div class="card stat"><i class="ph-fill ${icon}" style="color:${color}"></i><b>${n2}</b><span class="caption">${label}</span></div>`).join("")}</div>
      ${Array.from({ length: tripDays() }, (_, i) => {
        const date = new Date(`${ob.stops[0].arrive}T12:00:00`); date.setDate(date.getDate() + i);
        const plan = state.dayStops[i]?.length ? { title: dayTitle(state.dayStops[i]), stops: state.dayStops[i] } : null;
        return `<div class="card day-row"><span class="cal"><small>${date.toLocaleDateString("en-US", { weekday: "short" }).toUpperCase()}</small><b>${date.getDate()}</b></span>
          <span class="grow"><span class="caption">Day ${i + 1} · Delhi</span><b style="display:block;font-size:18px">${plan ? esc(plan.title) : "Free day"}</b>
          ${plan ? `<ol>${plan.stops.map((id) => `<li>${esc(placeById(id)?.name || "")}</li>`).join("")}</ol>` : '<span class="caption">A free day. Add places any time.</span>'}</span></div>`;
      }).join("")}`;
    foot = `<button class="pill ink block" data-ob="finish">Open my trip <i class="ph-bold ph-arrow-right"></i></button>`;
  }

  layer.innerHTML = `<div class="ob-body">${body}</div>${foot ? `<div class="ob-foot">${foot}</div>` : ""}`;
  layer.scrollTop = 0;
  $(".ob-body", layer).scrollTop = 0;

  if (step === "you") {
    const line = () => {
      const code = $("#obCur").value;
      const v = 150 * RATES[code];
      $("#autoLine").textContent = `An auto ride of ₹150 ≈ ${SYMBOLS[code]}${v >= 100 ? Math.round(v) : v.toFixed(2)}`;
    };
    $("#obName").addEventListener("input", (e) => {
      ob.name = e.target.value.trim();
      $("#passInitial").textContent = (ob.name || "?")[0].toUpperCase();
      $('[data-ob="build"]').disabled = !ob.name;
    });
    $("#obLang").addEventListener("change", (e) => { ob.language = e.target.value; });
    $("#obCur").addEventListener("change", (e) => { ob.currency = e.target.value; line(); });
    line();
  }
  if (step === "setup") runSetup();
}

function runSetup() {
  const items = $$("#setupList .setup");
  items.forEach((el, i) => {
    setTimeout(() => {
      el.querySelector(".state").innerHTML = '<span class="spinner"></span>';
      $("#setupStep").textContent = `Step ${i + 1} of ${items.length}`;
    }, i * 650);
    setTimeout(() => { el.querySelector(".state").innerHTML = '<i class="ph-fill ph-check-circle" style="color:var(--mint);font-size:24px"></i>'; el.classList.add("done"); }, i * 650 + 600);
  });
  setTimeout(() => { if (obStep === "setup") onboard("plan"); }, items.length * 650 + 500);
}

function signInSheet(kind) {
  let mode = "email";
  openSheet(`<div class="sheet-body" style="padding-top:12px">
    <div class="hero-art small">${postcard()}</div>
    <div class="card" style="display:grid;gap:14px">
      <div><h2 class="title2">${kind === "login" ? "Log in" : "Sign in"}</h2><p class="sub">Use whatever you have. No Indian number needed.</p></div>
      <div class="row"><button class="pill grey grow" data-signin="Apple"><i class="ph-fill ph-apple-logo"></i>Apple</button>
        <button class="pill grey grow" data-signin="Google"><i class="ph-bold ph-google-logo"></i>Google</button></div>
      <div class="or"><span>or</span></div>
      <div class="segmented" role="group" aria-label="Sign in with"><button type="button" data-mode="email" aria-pressed="true">Email</button><button type="button" data-mode="phone" aria-pressed="false">Phone</button></div>
      <form id="signForm" style="display:grid;gap:12px"><input class="input" id="signIn" type="email" placeholder="you@example.com" autocomplete="email" style="background:var(--field);border:0">
        <button class="pill ink block" type="submit" id="signBtn" disabled>Continue <i class="ph-bold ph-arrow-right"></i></button></form>
      <button class="ink" data-signin="guest" style="font-weight:600">Continue as guest</button>
      <div class="caption" style="text-align:center" id="signNote">Prototype: nothing is verified. No email is sent.</div>
    </div></div>`, {
    onMount(sheet) {
      const input = $("#signIn", sheet);
      const valid = () => (mode === "email" ? /\S+@\S+\.\S+/.test(input.value) : input.value.replace(/\D/g, "").length >= 7);
      input.addEventListener("input", () => { $("#signBtn", sheet).disabled = !valid(); });
      $$("[data-mode]", sheet).forEach((b) => b.addEventListener("click", () => {
        mode = b.dataset.mode;
        $$("[data-mode]", sheet).forEach((x) => x.setAttribute("aria-pressed", x === b));
        input.type = mode === "email" ? "email" : "tel";
        input.placeholder = mode === "email" ? "you@example.com" : "+44 7700 900123";
        input.value = "";
        $("#signBtn", sheet).disabled = true;
        $("#signNote", sheet).textContent = mode === "email" ? "Prototype: nothing is verified. No email is sent." : "Any country's number works. Prototype: no SMS is sent.";
      }));
      $("#signForm", sheet).addEventListener("submit", (e) => { e.preventDefault(); if (valid()) signedIn(input.value); });
      $$("[data-signin]", sheet).forEach((b) => b.addEventListener("click", () => signedIn(b.dataset.signin)));
    },
  });
}

function signedIn(who) {
  ob.email = who;
  saveProfile();
  closeSheet();
  // Someone who already set up Candor on this browser goes straight in.
  if (kindOfStart === "login" && ob.name && ob.stops.length) return finishOnboarding();
  setTimeout(() => onboard("trip"), 200);
}
let kindOfStart = "signup";

function citySheet(editIndex) {
  const existing = editIndex != null ? ob.stops[editIndex] : null;
  const last = ob.stops[ob.stops.length - 1];
  const arrive = existing?.arrive || last?.leave || isoDate(indiaNow());
  const leave = existing?.leave || (() => { const d = new Date(`${arrive}T12:00:00`); d.setDate(d.getDate() + 3); return isoDate(d); })();
  const draft = { ...(existing || { ...CITIES[0] }), arrive, leave, hotel: existing?.hotel || null, staying: existing?.hotel ? "booked" : "booked" };
  openSheet(`${sheetHead(existing ? "Edit city" : "Add a city")}<div class="sheet-body">
    <p class="sub" style="margin-top:-8px">When, and where you'll sleep</p>
    <div class="city-pick">${CITIES.map((c) => `<button class="pill ${c.name === draft.name ? "ink" : "outline"}" data-city="${c.name}">${c.name}</button>`).join("")}</div>
    <div class="caption" id="cityGuide"></div>
    <div class="card" style="display:grid;gap:12px"><div class="headline"><i class="ph-fill ph-calendar-blank" style="color:var(--saffron)"></i> Dates</div>
      <div class="dates"><label class="date-tile"><span class="caption">Arriving</span><input type="date" id="arrIn" value="${draft.arrive}"></label>
        <span class="caption" id="nights" style="text-align:center"></span>
        <label class="date-tile"><span class="caption">Leaving</span><input type="date" id="levIn" value="${draft.leave}"></label></div></div>
    <div class="card" style="display:grid;gap:12px"><div class="headline"><i class="ph-fill ph-bed" style="color:var(--saffron)"></i> Where are you staying?</div>
      <div class="search"><i class="ph ph-magnifying-glass"></i><input id="hotelIn" placeholder="Search your hotel on Google Maps" value="${esc(draft.hotel?.name || "")}" autocomplete="off"></div>
      <div class="list" id="hotelList"></div>
      <div class="caption" id="hotelNote">${draft.hotel ? `<i class="ph-fill ph-check-circle" style="color:var(--mint)"></i> ${esc(draft.hotel.address || draft.hotel.name)}` : "No problem if you don't know yet. Candor will keep asking so it can show you the way back home."}</div></div>
  </div>`, {
    foot: `<button class="pill ink block" id="cityDone">${existing ? "Save" : `Add ${draft.name} to my trip`} <i class="ph-bold ph-check"></i></button>`,
    onMount(sheet) {
      const refresh = () => {
        draft.arrive = $("#arrIn", sheet).value;
        draft.leave = $("#levIn", sheet).value;
        if (draft.leave <= draft.arrive) { const d = new Date(`${draft.arrive}T12:00:00`); d.setDate(d.getDate() + 1); draft.leave = isoDate(d); $("#levIn", sheet).value = draft.leave; }
        $("#nights", sheet).innerHTML = `<i class="ph-fill ph-moon" style="color:var(--indigo)"></i><br>${dayCount(draft)} days`;
        $("#cityGuide", sheet).innerHTML = draft.name === "Delhi"
          ? '<i class="ph-fill ph-seal-check" style="color:var(--mint)"></i> Verified guide: official fare chart, reference prices and known scams'
          : '<i class="ph ph-map-trifold"></i> AI guide with Google Maps. This web preview plans Delhi; other cities come with the app.';
        $("#cityDone", sheet).innerHTML = `${existing ? "Save" : `Add ${draft.name} to my trip`} <i class="ph-bold ph-check"></i>`;
      };
      $$("[data-city]", sheet).forEach((b) => b.addEventListener("click", () => {
        Object.assign(draft, CITIES.find((c) => c.name === b.dataset.city));
        draft.hotel = null;
        $("#hotelIn", sheet).value = "";
        $("#hotelList", sheet).innerHTML = "";
        $$("[data-city]", sheet).forEach((x) => { x.className = `pill ${x === b ? "ink" : "outline"}`; });
        refresh();
      }));
      $("#arrIn", sheet).addEventListener("change", refresh);
      $("#levIn", sheet).addEventListener("change", refresh);
      let timer;
      $("#hotelIn", sheet).addEventListener("input", (e) => {
        clearTimeout(timer);
        const q = e.target.value.trim();
        if (q.length < 3) { $("#hotelList", sheet).innerHTML = ""; return; }
        timer = setTimeout(async () => {
          try {
            const r = await api("/v1/places:searchText", { method: "POST", body: JSON.stringify({ textQuery: `${q}, ${draft.name}`, maxResultCount: 5,
              locationBias: { circle: { center: { latitude: draft.lat, longitude: draft.lng }, radius: 30000 } } }) });
            const places = r.places || [];
            $("#hotelList", sheet).innerHTML = places.map((p, i) => `<button class="list-item" data-hotel="${i}" style="padding:10px 12px">
              <i class="ph-fill ph-buildings" style="color:var(--sky);font-size:22px"></i><span class="grow"><b style="display:block;font-weight:500">${esc(p.displayName?.text)}</b>
              <span class="caption ellipsis" style="display:block">${esc(p.formattedAddress)}</span></span></button>`).join("") || '<div class="caption">No places found.</div>';
            $$("[data-hotel]", sheet).forEach((b) => b.addEventListener("click", () => {
              const p = places[Number(b.dataset.hotel)];
              draft.hotel = { name: p.displayName?.text, address: p.formattedAddress, lat: p.location.latitude, lng: p.location.longitude };
              $("#hotelIn", sheet).value = draft.hotel.name;
              $("#hotelList", sheet).innerHTML = "";
              $("#hotelNote", sheet).innerHTML = `<i class="ph-fill ph-check-circle" style="color:var(--mint)"></i> ${esc(draft.hotel.address)}`;
            }));
          } catch (error) { $("#hotelList", sheet).innerHTML = `<div class="caption">${esc(error.message)}</div>`; }
        }, 350);
      });
      $("#cityDone", sheet).addEventListener("click", () => {
        const stop = { name: draft.name, label: draft.label, guide: draft.guide, lat: draft.lat, lng: draft.lng, arrive: draft.arrive, leave: draft.leave, hotel: draft.hotel };
        if (existing) ob.stops[editIndex] = stop; else ob.stops.push(stop);
        saveProfile();
        closeSheet();
        onboard("trip");
      });
      refresh();
    },
  });
}

function finishOnboarding() {
  state.name = ob.name;
  state.language = ob.language;
  state.currency = ob.currency;
  state.style = ob.style;
  state.day = 0;
  state.choices = {};
  const delhi = ob.stops.find((s) => s.name === "Delhi");
  if (delhi?.hotel) Object.assign(HOTEL, { name: delhi.hotel.name, lat: delhi.hotel.lat, lng: delhi.hotel.lng });
  store.set("hotel", HOTEL);
  store.set("name", state.name);
  store.set("language", state.language);
  store.set("currency", state.currency);
  store.set("onboarded", true);
  saveProfile();
  save();
  const layer = $("#onboard");
  layer.classList.add("leaving");
  setTimeout(() => { layer.hidden = true; layer.classList.remove("leaving"); layer.innerHTML = ""; }, 300);
  renderAll();
  location.hash = obOpenTrip ? "trip" : "home";
}
let obOpenTrip = true;

function startOnboarding() {
  obStep = "welcome";
  onboard("welcome");
}

$("#onboard").addEventListener("click", (event) => {
  const t = event.target.closest("button");
  if (!t) return;
  const d = t.dataset;
  const order = ["trip", "people", "taste", "you"];
  if (d.ob === "signup" || d.ob === "login") { kindOfStart = d.ob; return signInSheet(d.ob); }
  if (d.ob === "addcity") return citySheet();
  if (d.obEdit != null) return citySheet(Number(d.obEdit));
  if (d.ob === "next") return onboard(order[order.indexOf(obStep) + 1]);
  if (d.ob === "back") return onboard(order[order.indexOf(obStep) - 1] || "trip");
  if (d.ob === "build") { saveProfile(); return onboard("setup"); }
  if (d.ob === "planit" || d.ob === "ownplan") { obOpenTrip = true; return onboard("ready"); }
  if (d.ob === "later") { obOpenTrip = false; return finishOnboarding(); }
  if (d.ob === "finish") return finishOnboarding();
  if (d.people) { ob.people = d.people; return onboard("people"); }
  if (d.obStyle) { ob.style = d.obStyle; return onboard("taste"); }
  if (d.interest) {
    ob.interests = ob.interests.includes(d.interest) ? ob.interests.filter((x) => x !== d.interest) : [...ob.interests, d.interest];
    return keepScroll(() => onboard("taste"));
  }
  if (d.pref) {
    if (ob.prefs.includes(d.pref)) ob.prefs = ob.prefs.filter((x) => x !== d.pref);
    else if (ob.prefs.length < 3) ob.prefs.push(d.pref);
    else toast("Up to three preferences.");
    return keepScroll(() => onboard("taste"));
  }
});

function keepScroll(fn) {
  const top = $("#onboard .ob-body")?.scrollTop || 0;
  fn();
  const body = $("#onboard .ob-body");
  if (body) body.scrollTop = top;
}

// MARK: Changing a day: add a place, remove or reorder

/** A place from Google Maps (Places API) as one of Candor's stops. */
function customPlace(p) {
  const id = `g:${p.id || `${p.location.latitude.toFixed(4)},${p.location.longitude.toFixed(4)}`}`;
  state.custom[id] = { name: p.displayName?.text || p.name, lat: p.location.latitude, lng: p.location.longitude, cat: "sight",
                       blurb: p.formattedAddress || "", tip: "Check opening hours and ticket prices at the official counter." };
  return id;
}

async function searchPlaces(query) {
  const r = await api("/v1/places:searchText", { method: "POST", body: JSON.stringify({ textQuery: `${query}, Delhi`, maxResultCount: 5,
    locationBias: { circle: { center: { latitude: 28.6139, longitude: 77.2090 }, radius: 30000 } } }) });
  return r.places || [];
}

/** Adds a place to a day, if it isn't there already. Returns false when it was. */
/**
 * Puts a place where it will be open: the asked day first, at the latest slot that keeps every stop open,
 * then the other days. Returns { added, day } or { added: false, reason }.
 */
async function addToDay(id, day) {
  if (state.dayStops.some((ids) => ids.includes(id))) {
    return { added: false, reason: "already", day: state.dayStops.findIndex((ids) => ids.includes(id)) };
  }
  await loadHours([id]);
  const slot = bestSlot(id, day);
  if (!slot) return { added: false, reason: "closed" };
  state.dayStops[slot.day].splice(slot.pos, 0, id);
  save();
  renderAll();
  return { added: true, day: slot.day, moved: slot.day !== day, before: state.dayStops[slot.day][slot.pos + 1] };
}

/** The first day (asked day first) and latest position where adding `id` leaves no stop closed. */
function bestSlot(id, day) {
  const days = [day, ...Array.from({ length: planDays() }, (_, i) => i).filter((d) => d !== day)];
  for (const d of days) {
    const ids = state.dayStops[d] || (state.dayStops[d] = []);
    const before = dayPlan(d).closed;
    for (let pos = ids.length; pos >= 0; pos--) {
      ids.splice(pos, 0, id);
      const after = dayPlan(d);
      ids.splice(pos, 1);
      if (after.closed <= before && !after.entries.find((e) => e.spot.id === id)?.closed) return { day: d, pos };
    }
  }
  return null;
}

/** Re-orders a day so every stop is open when you get there, keeping the order where it can. */
function fixDay(day) {
  const ids = [...state.dayStops[day]];
  const closed = dayPlan(day).entries.filter((e) => e.closed).map((e) => e.spot.id);
  state.dayStops[day] = ids.filter((id) => !closed.includes(id));
  const moved = [], dropped = [];
  for (const id of closed) {
    const slot = bestSlot(id, day);
    if (slot) { state.dayStops[slot.day].splice(slot.pos, 0, id); moved.push({ id, day: slot.day }); }
    else { state.dayStops[day].push(id); dropped.push(id); }
  }
  save();
  renderAll();
  return { moved, dropped };
}

/** "Red Fort is open 9:30 AM–4:30 PM and closed on Mondays": why it couldn't go in. */
function closedReason(id) {
  const days = Array.from({ length: planDays() }, (_, i) => dayDate(i));
  const parts = days.map((d) => hoursText(id, d)).filter(Boolean);
  return `**${placeById(id)?.name}** wouldn't be open when you could get there on any of your days (${[...new Set(parts)].join("; ")}). Try **Edit day** to free up a morning.`;
}

/** Finds a place by name: one of Candor's own first, then Google Maps. */
async function resolvePlace(name) {
  const key = name.toLowerCase().replace(/[^a-z]/g, "");
  const own = Object.entries(SPOTS).find(([, s]) => {
    const n = s.name.toLowerCase().replace(/[^a-z]/g, "");
    return n === key || n.includes(key) || key.includes(n);
  });
  if (own) return own[0];
  const found = (await searchPlaces(name))[0];
  return found ? customPlace(found) : null;
}

function addPlaceSheet(day) {
  const planned = new Set(state.dayStops.flat());
  const loves = store.get("profile", null)?.interests || [];
  const fits = { sight: ["Heritage", "Photography", "Spiritual"], market: ["Markets", "Street food", "Art & crafts"], fixed: ["Art & crafts", "Markets"] };
  const ideas = Object.entries(SPOTS).filter(([id, s]) => !planned.has(id) && s.cat !== "transport")
    .sort(([, a], [, b]) => (fits[b.cat] || []).filter((x) => loves.includes(x)).length - (fits[a.cat] || []).filter((x) => loves.includes(x)).length);
  openSheet(`${sheetHead(`Add to day ${day + 1}`)}<div class="sheet-body">
    <div class="search"><i class="ph ph-magnifying-glass"></i><input id="placeQ" placeholder="Search any place in Delhi on Google Maps" autocomplete="off"></div>
    <div class="list" id="placeResults"></div>
    <div class="headline">Ideas for you</div>
    <div class="list">${ideas.map(([id, s]) => `<button class="list-item" data-add-id="${id}">
      ${iconCircle(s.cat === "market" ? "ph-storefront" : s.cat === "fixed" ? "ph-tag" : "ph-bank", s.cat === "market" ? "var(--saffron)" : "var(--ink)", 40)}
      <span class="grow"><b style="display:block;font-weight:600">${esc(s.name)}</b><span class="caption">${esc(s.blurb)}</span></span>
      <i class="ph-bold ph-plus-circle ink" style="font-size:24px"></i></button>`).join("")}</div></div>`, {
    onMount(sheet) {
      const add = async (id) => {
        const name = placeById(id).name;
        const r = await addToDay(id, day);
        if (r.added) { closeSheet(); toast(r.moved ? `${name} is closed then on day ${day + 1}, so it's on day ${r.day + 1}.` : `Added ${name} to day ${r.day + 1}.`); }
        else if (r.reason === "already") toast(`${name} is already on day ${r.day + 1}.`);
        else { closeSheet(); toast(`${name} wouldn't be open when you'd get there. ${hoursText(id, dayDate(day))}.`); }
      };
      $$("[data-add-id]", sheet).forEach((b) => b.addEventListener("click", () => add(b.dataset.addId)));
      let timer;
      $("#placeQ", sheet).addEventListener("input", (e) => {
        clearTimeout(timer);
        const q = e.target.value.trim();
        if (q.length < 3) { $("#placeResults", sheet).innerHTML = ""; return; }
        timer = setTimeout(async () => {
          try {
            const places = await searchPlaces(q);
            $("#placeResults", sheet).innerHTML = places.map((p, i) => `<button class="list-item" data-found="${i}">
              <i class="ph-fill ph-map-pin" style="color:var(--rose);font-size:22px"></i><span class="grow"><b style="display:block;font-weight:500">${esc(p.displayName?.text)}</b>
              <span class="caption ellipsis" style="display:block">${esc(p.formattedAddress)}</span></span><i class="ph-bold ph-plus-circle ink" style="font-size:24px"></i></button>`).join("")
              || '<div class="caption">No places found.</div>';
            $$("[data-found]", sheet).forEach((b) => b.addEventListener("click", () => add(customPlace(places[Number(b.dataset.found)]))));
          } catch (error) { $("#placeResults", sheet).innerHTML = `<div class="caption">${esc(error.message)}</div>`; }
        }, 350);
      });
    },
  });
}

function editDaySheet(day) {
  openSheet(`${sheetHead(`Edit day ${day + 1}`)}<div class="sheet-body"><p class="sub">Move places up or down, or remove them. Times and fares update as you go.</p>
    <div class="list" id="editList"></div>
    <button class="pill outline block" id="resetDay"><i class="ph ph-arrow-counter-clockwise"></i>Back to Candor's plan</button></div>`, {
    onMount(sheet) {
      const draw = () => {
        const ids = state.dayStops[day] || [];
        $("#editList", sheet).innerHTML = ids.map((id, i) => `<div class="list-item"><span class="stop-num" style="width:34px;height:34px;font-size:14px">${i + 1}</span>
          <span class="grow" style="min-width:0"><span class="ellipsis" style="display:block;font-weight:500">${esc(placeById(id)?.name)}</span>
            ${(() => { const e = dayPlan(day).entries.find((x) => x.spot.id === id); return e?.closed ? `<span class="closed-note" style="font-size:13px"><i class="ph-fill ph-warning-circle"></i>${esc(e.note)}</span>` : e ? `<span class="caption">Arrive ${clock(e.arrival)}${hoursText(id, e.arrival) ? ` · open ${esc(hoursText(id, e.arrival))}` : ""}</span>` : ""; })()}</span>
          <button class="circle-btn" style="width:36px;height:36px" data-move="${i}:-1" aria-label="Move up" ${i === 0 ? "disabled" : ""}><i class="ph-bold ph-caret-up"></i></button>
          <button class="circle-btn" style="width:36px;height:36px" data-move="${i}:1" aria-label="Move down" ${i === ids.length - 1 ? "disabled" : ""}><i class="ph-bold ph-caret-down"></i></button>
          <button class="circle-btn" style="width:36px;height:36px;color:#C2412E" data-remove="${i}" aria-label="Remove"><i class="ph-bold ph-trash"></i></button></div>`).join("")
          || '<div class="caption">No places yet. Add one from the Trip tab.</div>';
        $$("[data-move]", sheet).forEach((b) => b.addEventListener("click", () => {
          const [i, step] = b.dataset.move.split(":").map(Number);
          const list = state.dayStops[day];
          [list[i], list[i + step]] = [list[i + step], list[i]];
          save(); renderAll(); draw();
        }));
        $$("[data-remove]", sheet).forEach((b) => b.addEventListener("click", () => {
          state.dayStops[day].splice(Number(b.dataset.remove), 1);
          save(); renderAll(); draw();
        }));
      };
      $("#resetDay", sheet).addEventListener("click", () => {
        state.dayStops[day] = [...(DAYS[day]?.stops || [])];
        save(); renderAll(); draw();
        toast(`Day ${day + 1} is back to Candor's plan.`);
      });
      draw();
    },
  });
}

// MARK: Ask Candor

const PROMPTS = [
  ["ph-car-profile", "Auto to Red Fort, he's asking ₹250"],
  ["ph-tag", "Is ₹60 fair for a samosa?"],
  ["ph-shield", "Someone says the station office is closed and I must book elsewhere"],
  ["ph-map-trifold", "Plan my day around heritage and street food"],
  ["ph-currency-circle-dollar", "How much is ₹1500 in my currency?"],
];

const EDIT_PROGRESS = ["Finding a place that fits…", "Checking opening hours…", "Fitting it into your day…"];
const PROGRESS = ["Checking what travellers paid…", "Looking up the fare chart…", "Comparing reference prices…", "Writing the verdict…"];
let progress;

function askSheet(prompt) {
  let photo = null;
  openSheet(`<div class="sheet-head"><span class="status-pill"><span class="d"></span>Gemini</span><span class="title">Ask Candor</span>
      <div class="icon-pair"><button data-action="close" aria-label="Close"><i class="ph-bold ph-x"></i></button><button data-action="newchat" aria-label="New chat"><i class="ph ph-note-pencil"></i></button></div></div>
    <div class="sheet-body" id="chat"></div>`, {
    foot: `<form class="composer" id="composer"><label class="attach" aria-label="Add a photo"><i class="ph ph-image"></i><input type="file" accept="image/*" hidden id="askPhoto"></label>
      <input type="text" id="askIn" placeholder="Ask about a price, ride or situation…" autocomplete="off" aria-label="Ask Candor">
      <button class="send" type="submit" aria-label="Send"><i class="ph-bold ph-arrow-up"></i></button></form>`,
    onMount(sheet) {
      const chat = $("#chat", sheet);
      const draw = () => {
        chat.innerHTML = state.chat.length ? state.chat.map(messageHTML).join("") : `
          <div class="ask-hello"><span class="badge"><i class="ph-fill ph-seal-check"></i></span><h2>Hi ${esc(state.name || "there")}, I'm Candor</h2>
            <p class="sub">I check fares, prices and situations for you, using real fare charts and price references. You'll see every step I take.</p></div>
          <div class="list">${PROMPTS.map(([icon, text]) => `<button class="prompt-card" data-prompt-text="${esc(text)}"><i class="ph-fill ${icon}"></i><span>${esc(text)}</span><i class="ph ph-arrow-up-right"></i></button>`).join("")}</div>`;
        // A finished answer opens at its question, so the verdict is the first thing in view.
        const last = state.chat[state.chat.length - 1];
        const asked = $$(".msg.me", chat).pop();
        chat.scrollTop = last && !last.pending && asked ? asked.offsetTop - chat.offsetTop - 12 : chat.scrollHeight;
        clearInterval(progress);
        if (last?.pending) {
          let step = 0;
          progress = setInterval(() => {
            const label = $(".pending-label", chat);
            const steps = last.edit ? EDIT_PROGRESS : PROGRESS;
            if (label) label.textContent = steps[++step % steps.length];
          }, 2600);
        }
        $$("[data-prompt-text]", chat).forEach((b) => b.addEventListener("click", () => send(b.dataset.promptText)));
      };
      const send = async (text) => {
        text = text.trim();
        if (!text && !photo) return;
        const image = photo;
        photo = null;
        $(".attach i", sheet).className = "ph ph-image";
        state.chat.push({ role: "user", text: text || "Is this price fair?", image });
        const reply = { role: "candor", pending: true, edit: /\b(add|include|put)\b/i.test(text) && /\b(day|trip|itinerary|plan)\b/i.test(text) };
        state.chat.push(reply);
        draw();
        try {
          const currency = /currency|convert|in my money/i.test(text) ? ` (My currency is ${state.currency}; ₹1 ≈ ${RATES[state.currency]} ${state.currency}.)` : "";
          const r = await api("/v1/ask", { method: "POST", body: JSON.stringify({ message: (text || "Is this price fair?") + currency, language: state.language, name: state.name, near: HOTEL.name,
            day: state.day + 1, interests: store.get("profile", null)?.interests || [],
            trip: state.dayStops.slice(0, planDays()).map((ids, i) => ({ day: i + 1, places: ids.map((id) => placeById(id)?.name).filter(Boolean) })),
            imageBase64: image || undefined, history: state.chat.filter((m) => !m.pending).slice(0, -1).map((m) => ({ role: m.role, text: m.text })) }) });
          Object.assign(reply, { pending: false, text: r.text, verdict: r.verdict, steps: r.steps });
          if (r.action?.type === "add_place") {
            // Only say it's added once it really is on the Trip tab.
            const day = Math.min(Math.max(1, r.action.day), planDays()) - 1;
            const id = await resolvePlace(r.action.place).catch(() => null);
            if (!id) reply.text = `I couldn't find **${r.action.place}** on Google Maps. Try the **Add a place** button on the Trip tab.`;
            else {
              // Only say it's added once it really is, at a time it's open.
              const result = await addToDay(id, day);
              const name = placeById(id).name;
              const when = result.added ? dayPlan(result.day).entries.find((e) => e.spot.id === id) : null;
              const at = when ? ` You'll get there at **${clock(when.arrival)}** (open ${hoursText(id, when.arrival) || "today"}).` : "";
              if (result.added) {
                r.text = r.text || "";
                reply.text = `**${result.moved ? `${name} would be closed by the time you'd reach it on day ${day + 1}, so I added it to day ${result.day + 1}.` : `Added ${name} to day ${result.day + 1}.`}**${at}\n\n${r.text}`;
                reply.link = { day: result.day, label: `See day ${result.day + 1}` };
              } else if (result.reason === "already") {
                reply.text = `**${name} is already on day ${result.day + 1}.**`;
                reply.link = { day: result.day, label: `See day ${result.day + 1}` };
              } else {
                reply.text = `I didn't add it. ${closedReason(id)}`;
              }
            }
          }
          if (r.verdict) addRecord(r.verdict.item, r.verdict.asked_inr, r.verdict.verdict, "ph-chat-text");
        } catch (error) {
          Object.assign(reply, { pending: false, text: `Sorry, I couldn't reach Gemini just now. ${error.message}` });
        }
        if (!$("#sheet").hidden) draw();
        renderCheck();
      };
      $("#composer", sheet).addEventListener("submit", (e) => { e.preventDefault(); const input = $("#askIn", sheet); send(input.value); input.value = ""; });
      $("#askPhoto", sheet).addEventListener("change", async (e) => {
        const file = e.target.files?.[0];
        if (!file) return;
        photo = await shrink(file);
        $(".attach i", sheet).className = "ph-fill ph-image";
        toast("Photo added. Ask about it, or just send.");
      });
      $('[data-action="newchat"]', sheet).addEventListener("click", () => { state.chat = []; draw(); });
      draw();
      if (prompt) send(prompt);
      else setTimeout(() => $("#askIn", sheet)?.focus(), 350);
      return () => clearInterval(progress);
    },
  });
}

function messageHTML(m) {
  if (m.role === "user") {
    return `<div class="msg me reveal">${m.image ? `<img class="thumb" src="data:image/jpeg;base64,${m.image}" alt="" style="margin-bottom:6px">` : ""}${esc(m.text)}</div>`;
  }
  if (m.pending) return `<div class="msg candor reveal"><span class="typing"><span></span><span></span><span></span></span> <span class="caption pending-label">${(m.edit ? EDIT_PROGRESS : PROGRESS)[0]}</span></div>`;
  return `<div style="display:grid;gap:12px" class="reveal">${stepsBlock(m.steps)}${verdictCard(m.verdict)}<div class="msg candor ${m.verdict ? "wide" : ""} prose">${md(m.text)}
    ${m.link ? `<button class="pill cream" style="height:40px;margin-top:10px;font-size:15px" data-see-day="${m.link.day}"><i class="ph-fill ph-map-trifold"></i>${esc(m.link.label)}</button>` : ""}</div></div>`;
}

// MARK: Navigation

function setTab(tab) {
  state.tab = tab;
  $$(".screen").forEach((s) => { s.hidden = s.dataset.tab !== tab; });
  $$("#tabbar button").forEach((b) => {
    const on = b.dataset.tab === tab;
    b.toggleAttribute("aria-current", on);
    if (on) b.setAttribute("aria-current", "page");
    const icon = { home: "ph-house", trip: "ph-map-trifold", check: "ph-seal-check" }[b.dataset.tab];
    b.querySelector("i").className = `${on ? "ph-fill" : "ph"} ${icon}`;
  });
}

function route() {
  const hash = location.hash.replace(/^#\/?/, "") || "home";
  const [tab, sub] = hash.split("/");
  setTab(["home", "trip", "check"].includes(tab) ? tab : "home");
  if (tab === "home" || !tab) requestAnimationFrame(() => fitTitle($(".home-header h1")));
  if (tab === "check" && sub === "scan") scanPage();
  else if (tab === "check" && sub === "ride") ridePage();
  else closePage();
}

function renderAccessory() {
  const home = wayHome();
  $("#accessory").className = "accessory glass";
  $("#accessory").innerHTML = `<i class="ph-fill ph-house-line home"></i><span class="grow ellipsis">${esc(home.text)}</span><i class="ph-bold ph-caret-right muted"></i>`;
}

/** Like the app's minimumScaleFactor: shrink a one-line title until it fits, then let it wrap. */
function fitTitle(el, min = 24) {
  if (!el) return;
  el.style.fontSize = "";
  el.style.whiteSpace = "nowrap";
  let size = parseFloat(getComputedStyle(el).fontSize);
  while (el.scrollWidth > el.clientWidth && size > min) el.style.fontSize = `${--size}px`;
  if (el.scrollWidth > el.clientWidth) el.style.whiteSpace = "normal";
}

function renderAll() {
  renderHome();
  requestAnimationFrame(() => fitTitle($(".home-header h1")));
  renderTrip();
  renderCheck();
  renderAccessory();
}

document.addEventListener("click", (event) => {
  const t = event.target.closest("button, a, [data-goto], summary");
  if (!t) {
    if (event.target.id === "backdrop") closeSheet();
    return;
  }
  const d = t.dataset;
  if (t.closest("#tabbar") && d.tab) {
    closeSheet();
    if (state.tab === d.tab && location.hash.replace("#", "") === d.tab) $(`#screen-${d.tab}`).scrollTo({ top: 0, behavior: "smooth" });
    location.hash = d.tab;
    return;
  }
  if (d.goto) { closeSheet(); location.hash = d.goto; return; }
  if (d.speak) return speak(d.speak);
  if (d.tool) return ({ sos: sosSheet, interpreter: interpreterSheet, converter: converterSheet, tips: tipsSheet })[d.tool]();
  if (d.ask) return askSheet(d.ask);
  if (d.promptText) return;
  if (d.seeDay) { closeSheet(); state.day = Number(d.seeDay); save(); renderAll(); location.hash = "trip"; setTimeout(() => $("#screen-trip").scrollTo({ top: $("#screen-trip").scrollHeight, behavior: "smooth" }), 350); return; }
  if (d.day) { state.day = Number(d.day); openStop = null; save(); renderAll(); $("#screen-trip").scrollTo({ top: 0 }); return; }
  if (d.style) { state.style = d.style; state.choices = {}; save(); renderAll(); toast(`${d.style[0].toUpperCase() + d.style.slice(1)}: fares and the best way updated.`); return; }
  if (d.pick) { state.choices[d.key] = d.pick; save(); renderAll(); return; }
  if (d.toggle) return expandStop(d.toggle);
  if (d.visit) {
    state.visited.has(d.visit) ? state.visited.delete(d.visit) : state.visited.add(d.visit);
    save();
    renderAll();
    if (state.visited.has(d.visit)) toast("Lovely. Marked as visited.");
    return;
  }
  if (d.placeQ) return askPlace(d.place, d.placeQ);
  if (d.journey) return journeySheet(d.to, d.journey, d.fromIndex);
  if (d.request) { toast(`Request sent to ${d.request}. They'll confirm in the app.`); return; }
  switch (d.action) {
    case "ask": return askSheet(d.prompt);
    case "me": return meSheet();
    case "addplace": return addPlaceSheet(state.day);
    case "editday": return editDaySheet(state.day);
    case "fixday": {
      const { moved, dropped } = fixDay(state.day);
      const parts = moved.map((m) => `${placeById(m.id).name} moved${m.day !== state.day ? ` to day ${m.day + 1}` : " earlier"}`);
      if (dropped.length) parts.push(`${dropped.map((id) => placeById(id).name).join(", ")} has no open slot`);
      toast(parts.join(". ") + ".");
      return;
    }
    case "guides": return guidesSheet();
    case "close": return closeSheet();
    case "back": history.length > 1 ? history.back() : (location.hash = "check"); return;
    case "addday": return askSheet("Suggest a fifth day in Delhi that fits my trip");
    case "wayhome": {
      const { leg } = wayHome();
      return leg ? journeySheet("hotel", null, null) : toast("You're starting from your hotel. Tick a place on the Trip tab first.");
    }
    case "signout":
      try { Object.keys(localStorage).filter((k) => k.startsWith("candor.")).forEach((k) => localStorage.removeItem(k)); } catch { /* Nothing stored. */ }
      location.hash = "home";
      location.reload();
      return;
    case "reset": state.visited.clear(); state.choices = {}; save(); renderAll(); closeSheet(); toast("Trip progress reset."); return;
    case "share-location":
      if (!navigator.geolocation) return toast("Location isn't available in this browser.");
      navigator.geolocation.getCurrentPosition((p) => {
        const url = `https://maps.google.com/?q=${p.coords.latitude.toFixed(5)},${p.coords.longitude.toFixed(5)}`;
        if (navigator.share) navigator.share({ text: "I'm here. Candor shared my location.", url }).catch(() => {});
        else navigator.clipboard?.writeText(url).then(() => toast("Location link copied."));
      }, () => toast("Allow location to share it."));
      return;
    default:
  }
});

document.addEventListener("submit", (event) => {
  const form = event.target.closest("[data-place-form]");
  if (!form) return;
  event.preventDefault();
  const input = $("input", form);
  if (input.value.trim()) askPlace(form.dataset.placeForm, input.value.trim());
  input.value = "";
});

$("#accessory").addEventListener("click", () => {
  const { leg } = wayHome();
  leg ? journeySheet("hotel", null, null) : toast("You're starting from your hotel. Tick a place on the Trip tab first.");
});
document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeSheet(); });
window.addEventListener("hashchange", route);

renderAll();
route();
document.fonts?.ready.then(() => fitTitle($(".home-header h1")));
window.addEventListener("resize", () => fitTitle($(".home-header h1")));
if (!store.get("onboarded", false)) startOnboarding();
