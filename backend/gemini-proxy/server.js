// Candor's Gemini proxy for Google Cloud Run.
//
// The app posts the same JSON it would send to the Gemini API. This service adds the API key,
// which lives in Secret Manager, and forwards the request. No key ships inside the app.
//
// POST /v1beta/models/<model>:generateContent   forwarded to the Gemini API
// POST /v1/places:searchText                    forwarded to Google Maps (Places API, Text Search)
// POST /v1/check                                the fair-price agent (Gemini + tools), for the web demo
// GET/POST /v1/community/...                    shared prices and scam hotspots (Firestore), see community.js
// GET  /v1/community/insights?city=             Gemini's brief for a tourism office
// POST /v1/ask, GET /v1/place, POST /v1/place/ask, POST /v1/translate, GET /v1/staticmap
//                                               the web app's own routes, see web.js
// GET  /                                        the web app (public/)
// GET  /healthz                                 "ok"

import http from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { openStore } from "./store.js";
import { addPrice, addReport, hotspots, priceStats } from "./community.js";
import { checkPrice, hotspotBrief } from "./agent.js";
import { ask, place, placeAsk, staticMap, translate } from "./web.js";

const PORT = Number(process.env.PORT || 8080);
const API_KEY = (process.env.GEMINI_API_KEY || "").trim();
const MAPS_API_KEY = (process.env.GOOGLE_MAPS_API_KEY || "").trim();
const PLACES_UPSTREAM = "https://places.googleapis.com/v1/places:searchText";
// Only the fields the app uses (viewport gives a city its search area).
const PLACES_FIELD_MASK = "places.id,places.displayName,places.formattedAddress,places.location,places.viewport";
const UPSTREAM = (process.env.GEMINI_API_BASE || "https://generativelanguage.googleapis.com").replace(/\/+$/, "");
const ALLOWED_MODELS = new Set(
  // The app's first choice, then the fallbacks it tries when a model is busy (GeminiClient.fallbackModels).
  (process.env.ALLOWED_MODELS ||
    "gemini-3.8-flash,gemini-3.6-flash,gemini-3.5-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite,gemini-3-flash-preview")
    .split(",").map((name) => name.trim()).filter(Boolean)
);
// A price-tag photo is sent as base64 JPEG (longest side 1280 px), well under this.
const MAX_BODY_BYTES = 6 * 1024 * 1024;
// Per client address, per instance. A price check is three to five requests.
const REQUESTS_PER_MINUTE = Number(process.env.REQUESTS_PER_MINUTE || 30);
const UPSTREAM_TIMEOUT_MS = 60_000;

const ROUTE = /^\/v1beta\/models\/([A-Za-z0-9.\-]+):generateContent$/;
const recent = new Map(); // client address -> request times in the last minute

function send(res, status, body) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(text);
}

// Same shape as a Gemini API error, so the app shows these the way it shows Gemini's own.
function fail(res, status, message) {
  send(res, status, { error: { code: status, message } });
}

function clientAddress(req) {
  // Cloud Run puts the caller's address first in X-Forwarded-For.
  const forwarded = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
  return forwarded || req.socket.remoteAddress || "unknown";
}

function overLimit(address, now = Date.now()) {
  const times = (recent.get(address) || []).filter((time) => now - time < 60_000);
  if (times.length >= REQUESTS_PER_MINUTE) {
    recent.set(address, times);
    return true;
  }
  times.push(now);
  recent.set(address, times);
  return false;
}

// Forget addresses that have gone quiet, so the map stays small.
setInterval(() => {
  const now = Date.now();
  for (const [address, times] of recent) {
    if (times.every((time) => now - time >= 60_000)) recent.delete(address);
  }
}, 60_000).unref();

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        // Stop keeping the upload, but let it drain so the caller can read the 413.
        chunks.length = 0;
        reject(Object.assign(new Error("Request is too large."), { status: 413 }));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

const { store, kind: storeKind } = await openStore();
const PUBLIC_DIR = join(fileURLToPath(new URL(".", import.meta.url)), "public");
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css",
                ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon",
                ".ttf": "font/ttf", ".json": "application/json", ".webmanifest": "application/manifest+json" };

async function serveStatic(res, path) {
  const file = normalize(path === "/" ? "/index.html" : path).replace(/^(\.\.[/\\])+/, "");
  try {
    const data = await readFile(join(PUBLIC_DIR, file));
    res.writeHead(200, { "Content-Type": TYPES[extname(file)] || "application/octet-stream",
                         // The page is always fresh, so a redeploy shows at once; its files are versioned (?v=).
                         "Cache-Control": extname(file) === ".html" ? "no-cache" : "public, max-age=300" });
    res.end(data);
  } catch {
    fail(res, 404, "Not found.");
  }
}

async function readJSON(req, res) {
  try {
    const body = await readBody(req);
    return JSON.parse(body.toString("utf8") || "{}");
  } catch (error) {
    if (error.status === 413) res.setHeader("Connection", "close");
    fail(res, error.status || 400, error.status ? error.message : "The request body is not valid JSON.");
    return null;
  }
}

const MODELS = [...ALLOWED_MODELS];

async function handleApp(req, res, url) {
  const path = url.pathname;
  const city = url.searchParams.get("city") || "Delhi";
  const write = req.method === "POST";
  if (write && overLimit(clientAddress(req))) return fail(res, 429, "Too many requests. Try again in a minute."), true;
  try {
    if (path === "/v1/check" && write) {
      if (!API_KEY) return fail(res, 500, "The service has no Gemini API key. Set GEMINI_API_KEY."), true;
      const input = await readJSON(req, res);
      if (input) send(res, 200, await checkPrice(input, { store, models: MODELS, apiKey: API_KEY }));
      return true;
    }
    const ctx = { store, models: MODELS, apiKey: API_KEY, mapsKey: MAPS_API_KEY };
    const needsGemini = () => (API_KEY ? false : (fail(res, 500, "The service has no Gemini API key. Set GEMINI_API_KEY."), true));
    if (path === "/v1/ask" && write) {
      if (needsGemini()) return true;
      const input = await readJSON(req, res);
      if (input) send(res, 200, await ask(input, ctx));
      return true;
    }
    if (path === "/v1/place" && req.method === "GET") {
      if (overLimit(clientAddress(req))) return fail(res, 429, "Too many requests. Try again in a minute."), true;
      send(res, 200, await place(url.searchParams, ctx));
      return true;
    }
    if (path === "/v1/place/ask" && write) {
      if (needsGemini()) return true;
      const input = await readJSON(req, res);
      if (input) send(res, 200, await placeAsk(input, ctx));
      return true;
    }
    if (path === "/v1/translate" && write) {
      if (needsGemini()) return true;
      const input = await readJSON(req, res);
      if (input) send(res, 200, await translate(input, ctx));
      return true;
    }
    if (path === "/v1/staticmap" && req.method === "GET") {
      if (!MAPS_API_KEY) return fail(res, 500, "The service has no Google Maps key. Set GOOGLE_MAPS_API_KEY."), true;
      const image = await staticMap(url.searchParams, MAPS_API_KEY);
      res.writeHead(200, { "Content-Type": image.type, "Cache-Control": "public, max-age=3600" });
      res.end(image.data);
      return true;
    }
    if (path === "/v1/community/prices") {
      if (write) {
        const input = await readJSON(req, res);
        if (input) send(res, 201, { saved: await addPrice(store, input) });
      } else {
        send(res, 200, await priceStats(store, city, url.searchParams.get("item") || ""));
      }
      return true;
    }
    if (path === "/v1/community/reports" && write) {
      const input = await readJSON(req, res);
      if (input) send(res, 201, { saved: await addReport(store, input) });
      return true;
    }
    if (path === "/v1/community/hotspots" && req.method === "GET") {
      send(res, 200, await hotspots(store, city));
      return true;
    }
    if (path === "/v1/community/insights" && req.method === "GET") {
      if (!API_KEY) return fail(res, 500, "The service has no Gemini API key. Set GEMINI_API_KEY."), true;
      if (overLimit(clientAddress(req))) return fail(res, 429, "Too many requests. Try again in a minute."), true;
      const data = await hotspots(store, city);
      send(res, 200, { ...data, ...(await hotspotBrief(data, { models: MODELS, apiKey: API_KEY })) });
      return true;
    }
  } catch (error) {
    fail(res, error.status || 502, error.message || "Something went wrong.");
    return true;
  }
  return false;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  const path = url.pathname;

  if (req.method === "GET" && path === "/healthz") {
    return send(res, 200, { status: "ok", store: storeKind });
  }

  if (path === "/v1/places:searchText") return searchPlaces(req, res);
  if (path.startsWith("/v1/") && !path.startsWith("/v1beta/")) {
    if (await handleApp(req, res, url)) return;
  }
  if (req.method === "GET" && !path.startsWith("/v1")) return serveStatic(res, path);

  const match = ROUTE.exec(path);
  if (!match) return fail(res, 404, "Not found.");
  if (req.method !== "POST") return fail(res, 405, "Use POST.");

  const model = match[1];
  if (!ALLOWED_MODELS.has(model)) return fail(res, 400, `Model ${model} is not enabled on this proxy.`);
  if (!API_KEY) return fail(res, 500, "The proxy has no Gemini API key. Set GEMINI_API_KEY.");
  if (overLimit(clientAddress(req))) return fail(res, 429, "Too many requests. Try again in a minute.");

  let body;
  try {
    body = await readBody(req);
    JSON.parse(body.toString("utf8"));
  } catch (error) {
    if (error.status === 413) res.setHeader("Connection", "close");
    return fail(res, error.status || 400, error.status ? error.message : "The request body is not valid JSON.");
  }

  try {
    const upstream = await fetch(`${UPSTREAM}/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": API_KEY },
      body,
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
    // Gemini's status and JSON go back unchanged, errors included.
    send(res, upstream.status, await upstream.text());
  } catch (error) {
    const timedOut = error.name === "TimeoutError";
    fail(res, timedOut ? 504 : 502, timedOut ? "Gemini took too long to answer." : "Could not reach Gemini.");
  }
});

async function searchPlaces(req, res) {
  if (req.method !== "POST") return fail(res, 405, "Use POST.");
  if (!MAPS_API_KEY) return fail(res, 500, "The proxy has no Google Maps key. Set GOOGLE_MAPS_API_KEY.");
  if (overLimit(clientAddress(req))) return fail(res, 429, "Too many requests. Try again in a minute.");

  let body;
  try {
    body = await readBody(req);
    JSON.parse(body.toString("utf8"));
  } catch (error) {
    if (error.status === 413) res.setHeader("Connection", "close");
    return fail(res, error.status || 400, error.status ? error.message : "The request body is not valid JSON.");
  }

  try {
    const upstream = await fetch(PLACES_UPSTREAM, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": MAPS_API_KEY,
        "X-Goog-FieldMask": PLACES_FIELD_MASK,
      },
      body,
      signal: AbortSignal.timeout(15_000),
    });
    send(res, upstream.status, await upstream.text());
  } catch (error) {
    const timedOut = error.name === "TimeoutError";
    fail(res, timedOut ? 504 : 502, timedOut ? "Google Maps took too long to answer." : "Could not reach Google Maps.");
  }
}

server.listen(PORT, () => {
  console.log(`Candor backend on ${PORT}. Store: ${storeKind}. Models: ${[...ALLOWED_MODELS].join(", ")}`);
});
