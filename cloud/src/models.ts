// What models can do and cost, for stations (GET /v1/models; station/src/models/module.ts asks): models.dev's catalog
// cut to what still.fail reads, keyed as a station keys a model (claude-opus-5-5, gpt-6.1-sol: without its maker).
// What a model takes in and holds is its canonical entry's (models.json); its prices and effort levels are its maker's
// own (api.json, the provider its canonical id names): another provider's are what that one charges. Where models.dev
// is known to be wrong, CORRECTIONS says what is right. Made at most once an hour in each of Cloudflare's locations
// (the Cache API), and answered 304 to a station that has it already (its ETag).
import { reply } from "./auth";

const CANONICAL = "https://models.dev/models.json";
const PROVIDERS = "https://models.dev/api.json";
/// Where the made catalog is kept in a location's cache: no address anyone asks.
const KEPT = "https://models.cache.still.fail/v1/models";
const KEPT_SECONDS = 3600;

/// A model's API prices, in dollars per million tokens.
export type Cost = { input: number; output: number; cacheRead?: number; cacheWrite?: number };

/// What still.fail says of a model (station/src/accounts/catalog.ts reads it); a field not known is left out.
export type Facts = {
  name?: string;
  input?: string[];
  reasoning?: boolean;
  efforts?: string[];
  context?: number;
  output?: number;
  cost?: Cost;
};

/// models.dev's mistakes, by key: the fields to say instead, each checked against the maker's own list. None known
/// yet (2026-10-27: its prices for every model the stations priced by hand agree with the makers').
export const CORRECTIONS: Record<string, Partial<Facts>> = {};

type Json = any;
const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
const number = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : undefined);
const strings = (v: unknown) => (Array.isArray(v) && v.every((s) => typeof s === "string") ? (v as string[]) : undefined);

function costOf(raw: unknown): Cost | undefined {
  if (!isObject(raw)) return undefined;
  const [input, output] = [number(raw.input), number(raw.output)];
  if (input === undefined || output === undefined) return undefined;
  const cost: Cost = { input, output };
  const [cacheRead, cacheWrite] = [number(raw.cache_read), number(raw.cache_write)];
  if (cacheRead !== undefined) cost.cacheRead = cacheRead;
  if (cacheWrite !== undefined) cost.cacheWrite = cacheWrite;
  return cost;
}

/// The effort levels an entry's reasoning options name.
function effortsOf(raw: unknown): string[] | undefined {
  if (!Array.isArray(raw)) return undefined;
  const levels = raw.filter((o) => isObject(o) && o.type === "effort").flatMap((o) => strings(o.values) ?? []);
  return levels.length > 0 ? [...new Set(levels)] : undefined;
}

/// The entry a maker sells a model by (`id`, maker/model) in its own API (`offered`, its api.json models): the one of the
/// model's own name; else the one it names as this model (`canonical_model_id`), as a maker may sell a model under
/// another name (DeepSeek's deepseek-flash is deepseek-v4.1-flash-1017); else, for a name without a date, the one of
/// its dated versions it sells (deepseek-v4.1-flash, as deepseek-v4.1-flash-1017). None where those differ in price.
function sold(offered: unknown, id: string): Record<string, any> | null {
  if (!isObject(offered)) return null;
  const own = id.slice(id.indexOf("/") + 1);
  if (isObject(offered[own])) return offered[own];
  const entries = Object.values(offered).filter(isObject);
  const named = (m: Record<string, any>) => (typeof m.canonical_model_id === "string" ? m.canonical_model_id.trim().toLowerCase() : "");
  const lower = id.toLowerCase();
  let found = entries.filter((m) => named(m) === lower);
  if (found.length === 0) found = entries.filter((m) => named(m).startsWith(`${lower}-`) && /^[0-9]{4,}$/.test(named(m).slice(lower.length + 1)));
  if (found.length === 0) return null;
  const price = JSON.stringify(costOf(found[0]!.cost) ?? null);
  return found.every((m) => JSON.stringify(costOf(m.cost) ?? null) === price) ? found[0]! : null;
}

/// The catalog from models.dev's canonical models (`canonical`, models.json) and its providers' (`providers`, api.json).
export function catalog(canonical: Json, providers: Json): Record<string, Facts> {
  const out: Record<string, Facts> = {};
  if (!isObject(canonical)) return out;
  for (const [id, m] of Object.entries(canonical)) {
    if (!isObject(m)) continue;
    const slash = id.indexOf("/");
    const [maker, own] = slash > 0 ? [id.slice(0, slash), id.slice(slash + 1)] : ["", id];
    const key = own.trim().toLowerCase();
    if (key === "" || key in out) continue;
    const f: Facts = {};
    if (typeof m.name === "string") f.name = m.name;
    const input = strings(m.modalities?.input);
    if (input) f.input = input;
    if (typeof m.reasoning === "boolean") f.reasoning = m.reasoning;
    const context = number(m.limit?.context);
    if (context !== undefined) f.context = context;
    const output = number(m.limit?.output);
    if (output !== undefined) f.output = output;
    const made = sold(providers?.[maker]?.models, id);
    if (made !== null) {
      const efforts = effortsOf(made.reasoning_options);
      if (efforts) f.efforts = efforts;
      const cost = costOf(made.cost);
      if (cost) f.cost = cost;
    }
    out[key] = { ...f, ...CORRECTIONS[key] };
  }
  return out;
}

async function made(): Promise<Response> {
  const [canonical, providers] = await Promise.all([CANONICAL, PROVIDERS].map(async (url) => {
    const r = await fetch(url, { headers: { "user-agent": "stillfail-cloud" } });
    if (!r.ok) throw new Error(`${url} answered ${r.status}`);
    return r.json();
  }));
  const body = JSON.stringify({ models: catalog(canonical, providers) });
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
  const etag = `"${[...new Uint8Array(digest).slice(0, 16)].map((b) => b.toString(16).padStart(2, "0")).join("")}"`;
  return new Response(body, { headers: { "content-type": "application/json", etag, "cache-control": `public, max-age=${KEPT_SECONDS}` } });
}

export async function serveModels(request: Request): Promise<Response> {
  const cache = (caches as unknown as { default: Cache }).default;
  let answer = await cache.match(KEPT);
  if (!answer) {
    try {
      answer = await made();
    } catch (error) {
      return reply({ error: "models_unavailable", message: (error as Error).message }, 502);
    }
    await cache.put(KEPT, answer.clone());
  }
  const etag = answer.headers.get("etag");
  // Stations ask again on their own (every few hours, an app starting): no cache of theirs keeps it.
  const headers = { etag: etag ?? "", "cache-control": "no-cache" };
  if (etag !== null && request.headers.get("if-none-match") === etag) return new Response(null, { status: 304, headers });
  return new Response(answer.body, { headers: { ...headers, "content-type": "application/json" } });
}
