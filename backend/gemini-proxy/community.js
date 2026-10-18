// Community data: what travellers actually paid, and where tricks were reported.
//
// Every price check and every matched scam can be shared anonymously by the app (the traveller
// can turn this off). Nothing personal is stored: no name, no account, no device id, and
// locations are rounded to about 1 km.
//
// POST /v1/community/prices     { city, item, category?, paidINR?, askedINR?, fairLowINR?, fairHighINR? }
// GET  /v1/community/prices?city=Delhi&item=masala%20chai
// POST /v1/community/reports    { city, scam, lat?, lon? }
// GET  /v1/community/hotspots?city=Delhi
// GET  /v1/community/insights?city=Delhi    Gemini's brief for a tourism office or police desk

const MAX_TEXT = 80;

/** "Masala Chai (small)" → "masala chai small": the key prices are grouped by. */
export function itemKey(text) {
  return String(text || "").toLowerCase().normalize("NFKD")
    .replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim().slice(0, MAX_TEXT);
}

export function cityKey(text) {
  return itemKey(text) || "delhi";
}

function clean(text) {
  return String(text || "").replace(/[\u0000-\u001f]/g, " ").trim().slice(0, MAX_TEXT);
}

function amount(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 && number < 1_000_000 ? Math.round(number) : undefined;
}

function coarse(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number * 100) / 100 : undefined;
}

function percentile(sorted, p) {
  if (!sorted.length) return undefined;
  const index = (sorted.length - 1) * p;
  const low = Math.floor(index), high = Math.ceil(index);
  return Math.round(sorted[low] + (sorted[high] - sorted[low]) * (index - low));
}

/** What travellers paid for an item in a city: count, median and the middle half. */
export async function priceStats(store, city, item) {
  const rows = await store.find("prices", { cityKey: cityKey(city), itemKey: itemKey(item) }, 300);
  const paid = rows.map((row) => row.paidINR ?? row.askedINR).filter((n) => typeof n === "number").sort((a, b) => a - b);
  const asked = rows.map((row) => row.askedINR).filter((n) => typeof n === "number").sort((a, b) => a - b);
  return {
    city: clean(city), item: clean(item), reports: paid.length,
    medianPaidINR: percentile(paid, 0.5), lowPaidINR: percentile(paid, 0.25), highPaidINR: percentile(paid, 0.75),
    medianAskedINR: percentile(asked, 0.5),
    note: paid.length < 3 ? "Too few reports to rely on yet." : "Shared anonymously by Candor travellers.",
  };
}

export async function addPrice(store, body) {
  const item = clean(body.item);
  if (!item) throw Object.assign(new Error("Say what was priced (item)."), { status: 400 });
  const row = {
    city: clean(body.city) || "Delhi", cityKey: cityKey(body.city), item, itemKey: itemKey(item),
    category: clean(body.category) || undefined,
    paidINR: amount(body.paidINR), askedINR: amount(body.askedINR),
    fairLowINR: amount(body.fairLowINR), fairHighINR: amount(body.fairHighINR),
  };
  if (!row.paidINR && !row.askedINR) throw Object.assign(new Error("Give paidINR or askedINR."), { status: 400 });
  await store.add("prices", row);
  return row;
}

export async function addReport(store, body) {
  const scam = clean(body.scam);
  if (!scam) throw Object.assign(new Error("Say which trick it was (scam)."), { status: 400 });
  const row = { city: clean(body.city) || "Delhi", cityKey: cityKey(body.city), scam, lat: coarse(body.lat), lon: coarse(body.lon) };
  await store.add("reports", row);
  return row;
}

/** Reports grouped by trick and by ~1 km area, most reported first. */
export async function hotspots(store, city) {
  const rows = await store.find("reports", { cityKey: cityKey(city) }, 1000);
  const byScam = new Map(), byArea = new Map();
  for (const row of rows) {
    byScam.set(row.scam, (byScam.get(row.scam) || 0) + 1);
    if (typeof row.lat === "number" && typeof row.lon === "number") {
      const key = `${row.lat},${row.lon}`;
      const area = byArea.get(key) || { lat: row.lat, lon: row.lon, reports: 0, scams: {} };
      area.reports += 1;
      area.scams[row.scam] = (area.scams[row.scam] || 0) + 1;
      byArea.set(key, area);
    }
  }
  return {
    city: clean(city) || "Delhi", reports: rows.length,
    scams: [...byScam].map(([scam, reports]) => ({ scam, reports })).sort((a, b) => b.reports - a.reports),
    areas: [...byArea.values()].sort((a, b) => b.reports - a.reports).slice(0, 25),
  };
}
