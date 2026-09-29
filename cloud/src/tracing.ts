// Traces (docs/telemetry.md). Clients and stations send their spans here, to
// POST /v1/telemetry/traces, and still.fail cloud passes them on to Axiom with its
// own token, which never leaves the Worker. It records spans of its own for
// the /v1/* calls that carry a recorded W3C traceparent, sent straight to
// Axiom once the answer is out.
import { DurableObject } from "cloudflare:workers";
import { readText, reply } from "./auth";
import { header, publicOrigins, signedMessages } from "./compat";
import type { Env } from "./env";
import { validKeyHex, verifyAnySignature } from "./grants";
import { TELEMETRY_BATCHES_PER_MINUTE } from "./limits";

const AXIOM = "https://api.axiom.co/v1/traces";
const MAX_BYTES = 512 * 1024;
const MAX_SPANS = 1000;

export interface TraceParent {
  trace: string;
  span: string;
  sampled: boolean;
}

/** `00-<trace>-<span>-<flags>`; anything else is no context. */
export function parseTraceparent(header: string | null): TraceParent | null {
  const match = /^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$/.exec(header?.trim() ?? "");
  if (!match || match[1] === "ff" || /^0+$/.test(match[2]!) || /^0+$/.test(match[3]!)) return null;
  return { trace: match[2]!, span: match[3]!, sampled: (parseInt(match[4]!, 16) & 1) === 1 };
}

/** Collections whose next path segment is an id, whatever it looks like (as the client core has it). */
const COLLECTIONS = new Set(["sessions", "threads", "connects", "profiles", "logins", "workspaces", "stations", "members", "enrollments", "accounts"]);

/** A request path as a span shows it: no query, ids as `:id`. */
export function route(path: string): string {
  let afterCollection = false;
  return path.split(/[?#]/)[0]!.split("/").map((segment) => {
    const word = segment.length > 0 && segment.length <= 24 && /^[a-z0-9._-]+$/.test(segment) && /[a-z]/.test(segment);
    const id = segment.length > 0 && (afterCollection || !word);
    afterCollection = !id && COLLECTIONS.has(segment);
    return id ? ":id" : segment;
  }).join("/");
}

/** Counts each sender's batches per minute, in memory: losing the count when evicted only forgives a little. */
export class TelemetryLimiter extends DurableObject<Env> {
  #minute = 0;
  #count = 0;
  consume(): boolean {
    const minute = Math.floor(Date.now() / 60_000);
    if (minute !== this.#minute) {
      this.#minute = minute;
      this.#count = 0;
    }
    if (this.#count >= TELEMETRY_BATCHES_PER_MINUTE) return false;
    this.#count++;
    return true;
  }
}

async function toAxiom(env: Env, body: string): Promise<boolean> {
  const response = await fetch(AXIOM, {
    method: "POST",
    headers: { authorization: `Bearer ${env.AXIOM_TOKEN}`, "x-axiom-dataset": env.AXIOM_DATASET ?? "ember", "content-type": "application/json" },
    body,
  });
  await response.body?.cancel();
  return response.ok;
}

const hex = (bytes: ArrayBuffer | Uint8Array) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");

/**
 * Who sends a batch: an account (`sub`, checked by the caller from its access token), or a station signing
 * "stillfail-station-telemetry-v1:<origin>:<station>:<ts>:<sha256 of the body, hex>" with its key, like its presence
 * socket (x-stillfail-station, x-stillfail-ts within 5 minutes, x-stillfail-signature), that is still enrolled.
 * (Stations from before the rename: "ember-station-telemetry-v1:…" and x-ember-*; the origin is any of the cloud's.)
 */
async function stationSender(request: Request, env: Env, body: string): Promise<string | null> {
  const station = header(request, "station");
  const ts = Number(header(request, "ts"));
  if (!validKeyHex(station) || !Number.isSafeInteger(ts) || Math.abs(ts - Date.now() / 1000) > 300) return null;
  const digest = hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body)));
  const messages = signedMessages("station-telemetry-v1", publicOrigins(env), `${station}:${ts}:${digest}`);
  if (!(await verifyAnySignature(station, header(request, "signature") ?? "", messages))) return null;
  return (await env.DIRECTORY.getByName("primary").isStation(station)) ? station : null;
}

/** POST /v1/telemetry/traces: a batch of spans (OTLP JSON), passed on to Axiom. `account` is the signed-in sender, if any. */
export async function receiveTraces(request: Request, env: Env, account: string | null): Promise<Response> {
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return reply({ error: "invalid_request" }, 400);
  let body: string;
  try {
    body = await readText(request, MAX_BYTES);
  } catch {
    return reply({ error: "too_large" }, 413);
  }
  const sender = account ? `account:${account}` : await stationSender(request, env, body).then((s) => (s ? `station:${s}` : null));
  if (!sender) return reply({ error: "invalid_session" }, 401);
  if (!(await env.TELEMETRY_LIMITS.getByName(sender).consume())) return reply({ error: "rate_limited" }, 429, { "retry-after": "60" });
  let spans = 0;
  try {
    const value = JSON.parse(body) as { resourceSpans?: { scopeSpans?: { spans?: unknown[] }[] }[] };
    if (!Array.isArray(value.resourceSpans)) throw new Error("shape");
    for (const resource of value.resourceSpans) for (const scope of resource.scopeSpans ?? []) spans += scope.spans?.length ?? 0;
  } catch {
    return reply({ error: "invalid_request" }, 400);
  }
  if (spans > MAX_SPANS) return reply({ error: "too_large" }, 413);
  if (!env.AXIOM_TOKEN) return reply({ error: "telemetry_not_configured" }, 503);
  return (await toAxiom(env, body)) ? reply({ ok: true }, 202) : reply({ error: "telemetry_unavailable" }, 502);
}

/** The span of a /v1/* call made in a recorded trace, sent to Axiom (dropped if that fails). */
export async function recordCall(env: Env, parent: TraceParent, request: Request, response: Response, startMs: number, endMs: number): Promise<void> {
  if (!env.AXIOM_TOKEN) return;
  const path = route(new URL(request.url).pathname);
  const nanos = (ms: number) => (BigInt(Math.round(ms)) * 1_000_000n).toString();
  const attribute = (key: string, value: string | number) => ({ key, value: typeof value === "number" ? { intValue: String(value) } : { stringValue: value } });
  const size = Number(response.headers.get("content-length") ?? NaN);
  const span = {
    traceId: parent.trace,
    spanId: hex(crypto.getRandomValues(new Uint8Array(8))),
    parentSpanId: parent.span,
    name: `${request.method} ${path}`,
    kind: 2,
    startTimeUnixNano: nanos(startMs),
    endTimeUnixNano: nanos(endMs),
    attributes: [
      attribute("http.request.method", request.method),
      attribute("url.path", path),
      attribute("http.response.status_code", response.status),
      ...(Number.isFinite(size) ? [attribute("http.response.body.size", size)] : []),
    ],
    status: { code: response.status >= 500 ? 2 : 1 },
  };
  // Named after the Worker (ember-cloud, which keeps its name), as the queries in docs/telemetry.md know it.
  const body = JSON.stringify({ resourceSpans: [{ resource: { attributes: [attribute("service.name", "ember-cloud")] }, scopeSpans: [{ scope: { name: "ember-cloud" }, spans: [span] }] }] });
  await toAxiom(env, body).catch(() => false);
}
