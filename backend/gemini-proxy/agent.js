// Candor's fair-price agent, running on Cloud Run for the web demo.
//
// Gemini reads the photo and the question, then calls tools until it can judge the price:
// what other travellers paid (Firestore), Candor's reference prices, and the official fare chart.
// Every tool call is returned as a step, so the page can show how the verdict was reached.

import { priceStats } from "./community.js";

const UPSTREAM = (process.env.GEMINI_API_BASE || "https://generativelanguage.googleapis.com").replace(/\/+$/, "");

/** Indicative reference prices (INR). Same idea as DelhiData in the app; verify before relying on them. */
const REFERENCES = [
  { item: "masala chai (street stall)", keys: ["chai", "tea"], low: 10, high: 20, source: "Candor street-food reference" },
  { item: "bottled water 1 litre", keys: ["water", "bisleri", "bottle"], low: 20, high: 20, source: "Printed MRP (legal maximum)" },
  { item: "samosa", keys: ["samosa"], low: 15, high: 25, source: "Candor street-food reference" },
  { item: "lassi", keys: ["lassi"], low: 40, high: 80, source: "Candor street-food reference" },
  { item: "chole bhature (plate)", keys: ["chole", "bhature"], low: 60, high: 120, source: "Candor street-food reference" },
  { item: "thali (local restaurant)", keys: ["thali"], low: 120, high: 250, source: "Candor restaurant reference" },
  { item: "Delhi Metro single journey", keys: ["metro"], low: 11, high: 64, source: "DMRC fare table" },
  { item: "coconut water", keys: ["coconut", "nariyal"], low: 40, high: 70, source: "Candor street-food reference" },
  { item: "pashmina shawl (market)", keys: ["pashmina", "shawl"], low: 1500, high: 6000, source: "Candor market reference (quality varies widely)" },
  { item: "Taj Mahal entry, foreign national", keys: ["taj"], low: 1300, high: 1300, source: "ASI ticket price (verify on asi.payumoney.com)" },
];

/** Delhi Transport Dept. fares (2022 revision): verify against the current notification. */
function delhiFare(mode, km, night) {
  const distance = Math.max(0, Number(km) || 0);
  let fare;
  if (mode === "auto") fare = 30 + Math.max(0, distance - 1.5) * 11;
  else if (mode === "taxi_ac") fare = 40 + Math.max(0, distance - 1) * 20;
  else fare = 40 + Math.max(0, distance - 1) * 17;
  if (night) fare *= 1.25;
  return Math.round(fare);
}

const TOOLS = [{
  functionDeclarations: [
    { name: "community_prices", description: "What Candor travellers actually paid for an item in a city, shared anonymously.",
      parameters: { type: "object", properties: {
        item: { type: "string", description: "Short generic item name, e.g. 'masala chai' or 'auto rickshaw 5 km'." },
        city: { type: "string" } }, required: ["item", "city"] } },
    { name: "reference_price", description: "Candor's indicative reference price range for common food, drinks, tickets and goods.",
      parameters: { type: "object", properties: { item: { type: "string" } }, required: ["item"] } },
    { name: "delhi_fare", description: "Official metered fare for an auto-rickshaw or taxi in Delhi.",
      parameters: { type: "object", properties: {
        mode: { type: "string", enum: ["auto", "taxi", "taxi_ac"] },
        distance_km: { type: "number" },
        night: { type: "boolean", description: "True between 11 pm and 5 am." } }, required: ["mode", "distance_km"] } },
    { name: "report_verdict", description: "Give the final verdict. Call exactly once.",
      parameters: { type: "object", properties: {
        item: { type: "string" },
        fair_low_inr: { type: "number" }, fair_high_inr: { type: "number" },
        asked_inr: { type: "number" },
        verdict: { type: "string", enum: ["fair", "a little high", "overpriced", "unknown"] },
        source: { type: "string", description: "Where the fair range comes from, copied from a tool." },
        phrase_hindi: { type: "string", description: "A polite line to say, in Hindi (Devanagari) with Latin transliteration in brackets." } },
        required: ["item", "fair_low_inr", "fair_high_inr", "verdict", "source"] } },
  ],
}];

function systemPrompt(language) {
  return `You are Candor, a fair-price agent for foreign visitors in India. Reply in ${language || "English"}.
Rules:
- Never invent prices. Ground the fair range in a tool result, or in a printed MRP you can clearly read in the photo.
- Always call community_prices, and reference_price or delhi_fare, before judging.
- If community data has 3 or more reports, weigh it; say how many travellers it comes from.
- Call report_verdict exactly once, then answer in 2–4 short bullet points: verdict, why, what to say.
- Be respectful: most sellers are honest. Frame it as price transparency, not distrust.`;
}

export async function callGemini(body, models, apiKey) {
  let lastError;
  for (const model of models) {
    try {
      const response = await fetch(`${UPSTREAM}/v1beta/models/${model}:generateContent`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(60_000),
      });
      const json = await response.json().catch(() => ({}));
      if (response.ok) return { json, model };
      lastError = new Error(json?.error?.message || `Gemini error ${response.status}`);
      // Busy or unknown model: try the next one. Anything else is the request's fault.
      if (![404, 429, 500, 503].includes(response.status)) break;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("No Gemini model answered.");
}

async function runTool(name, args, ctx) {
  switch (name) {
    case "community_prices": {
      const stats = await priceStats(ctx.store, args.city || ctx.city, args.item || ctx.item);
      return { summary: stats.reports ? `${stats.reports} travellers, median ₹${stats.medianPaidINR}` : "No reports yet", result: stats };
    }
    case "reference_price": {
      const text = String(args.item || "").toLowerCase();
      const match = REFERENCES.find((ref) => ref.keys.some((key) => text.includes(key)));
      return match
        ? { summary: `${match.item}: ₹${match.low}–₹${match.high}`, result: { found: true, ...match, keys: undefined } }
        : { summary: "No reference", result: { found: false, guidance: "In bargaining markets, open around 50–60% of the first quote." } };
    }
    case "delhi_fare": {
      const fare = delhiFare(args.mode, args.distance_km, args.night);
      return { summary: `${args.mode}, ${args.distance_km} km: metered ≈ ₹${fare}`,
               result: { metered_fare_inr: fare, fair_upper_inr: Math.round(fare * 1.2), source: "Delhi Transport Dept. fare chart (2022)" } };
    }
    case "report_verdict":
      ctx.verdict = args;
      return { summary: `${args.verdict}: fair ₹${args.fair_low_inr}–₹${args.fair_high_inr}`, result: { shown: true } };
    default:
      return { summary: "Unknown tool", result: { error: `No tool named ${name}` } };
  }
}

/** Runs one price check: { city, question, askedINR, imageBase64?, language? } → verdict, answer, steps. */
export async function checkPrice(input, { store, models, apiKey }) {
  const city = String(input.city || "Delhi").slice(0, 60);
  const question = String(input.question || "").slice(0, 500);
  const asked = Number(input.askedINR) || undefined;
  const parts = [{ text: `City: ${city}. ${question}${asked ? ` I'm being asked ₹${asked}.` : ""}` }];
  if (input.imageBase64) {
    parts.push({ inline_data: { mime_type: input.imageMime || "image/jpeg", data: String(input.imageBase64) } });
  }
  const contents = [{ role: "user", parts }];
  const ctx = { store, city, item: question, verdict: null };
  const steps = [];
  let model;

  for (let round = 0; round < 6; round++) {
    const { json, model: used } = await callGemini({
      systemInstruction: { parts: [{ text: systemPrompt(input.language) }] },
      contents, tools: TOOLS,
    }, models, apiKey);
    model = used;
    const content = json?.candidates?.[0]?.content;
    if (!content) throw new Error("Gemini returned no answer.");
    contents.push(content);
    const calls = (content.parts || []).filter((part) => part.functionCall).map((part) => part.functionCall);
    if (!calls.length) {
      const answer = (content.parts || []).map((part) => part.text || "").join("").trim();
      return { verdict: ctx.verdict, answer, steps, model };
    }
    const responses = [];
    for (const call of calls) {
      const { summary, result } = await runTool(call.name, call.args || {}, ctx);
      steps.push({ tool: call.name, args: call.args || {}, summary });
      responses.push({ functionResponse: { name: call.name, response: result } });
    }
    contents.push({ role: "user", parts: responses });
  }
  return { verdict: ctx.verdict, answer: "Stopped after 6 rounds.", steps, model };
}

/** A short brief for a tourism office or police desk, written by Gemini from the hotspot data. */
export async function hotspotBrief(data, { models, apiKey }) {
  if (!data.reports) return { brief: "No reports yet for this city.", model: null };
  const prompt = `You advise a city tourism office in India. Here are anonymous scam reports from tourists using Candor (JSON):
${JSON.stringify({ city: data.city, reports: data.reports, scams: data.scams, areas: data.areas.slice(0, 10) })}
Write a brief in English: 1) the top 3 problems and where they cluster (use the lat/lon areas), 2) one concrete action
for each (signage, a tourist police post, a fixed-price board, etc.), 3) one line on trend or data limits. Max 150 words.`;
  const { json, model } = await callGemini({ contents: [{ role: "user", parts: [{ text: prompt }] }] }, models, apiKey);
  const brief = (json?.candidates?.[0]?.content?.parts || []).map((part) => part.text || "").join("").trim();
  return { brief, model };
}
