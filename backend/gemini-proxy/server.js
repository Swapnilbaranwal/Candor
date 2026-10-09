// Candor's Gemini proxy for Google Cloud Run.
//
// The app posts the same JSON it would send to the Gemini API. This service adds the API key,
// which lives in Secret Manager, and forwards the request. No key ships inside the app.
//
// POST /v1beta/models/<model>:generateContent   forwarded to the Gemini API
// POST /v1/places:searchText                    forwarded to Google Maps (Places API, Text Search)
// GET  /healthz                                 "ok"

import http from "node:http";

const PORT = Number(process.env.PORT || 8080);
const API_KEY = (process.env.GEMINI_API_KEY || "").trim();
const MAPS_API_KEY = (process.env.GOOGLE_MAPS_API_KEY || "").trim();
const PLACES_UPSTREAM = "https://places.googleapis.com/v1/places:searchText";
// Only the fields the app uses (viewport gives a city its search area).
const PLACES_FIELD_MASK = "places.id,places.displayName,places.formattedAddress,places.location,places.viewport";
const UPSTREAM = (process.env.GEMINI_API_BASE || "https://generativelanguage.googleapis.com").replace(/\/+$/, "");
const ALLOWED_MODELS = new Set(
  (process.env.ALLOWED_MODELS || "gemini-3.8-flash,gemini-3.5-flash,gemini-3.5-flash-lite")
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

const server = http.createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;

  if (req.method === "GET" && path === "/healthz") {
    return send(res, 200, { status: "ok" });
  }

  if (path === "/v1/places:searchText") return searchPlaces(req, res);

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
  console.log(`Candor Gemini proxy listening on ${PORT}. Models: ${[...ALLOWED_MODELS].join(", ")}`);
});
