// How loaded still.fail's relays are, for the admin's console (its 中继 page, GET /v1/admin/relays): each relay's
// counters (relay-metrics.ts Load) about a minute apart, kept a week. The relays on machines of their own send theirs
// (POST /v1/relays/load, relay-load.sh run by a timer there, believed by the address they send from); Cloudflare's is read by this Worker's cron from the
// relay process (index.ts). What is shown is worked out from the counters when asked (relay-load-view.ts). What each did
// in the minute between two samples goes to Axiom as well (a `relay minute` log line, docs/telemetry.md), beside the
// devices' and stations' records of the same minutes.
import { DurableObject } from "cloudflare:workers";
import { nowSeconds, reply } from "./auth";
import type { Env } from "./env";
import { LIMITS } from "./limits";
import { relayConns, relayLoad, type Load } from "./relay-metrics";
import { GAP, relayLoadView, relayMinute, type RelayLoadView, type RelayMinute } from "./relay-load-view";
import { relayToAxiom } from "./tracing";
import { relayUrls, sameUrl } from "./relays";

/** How long samples are kept: the week the console shows, and a day more. */
const KEEP = 8 * 86_400;

/** Every relay's samples, in one object ("primary"). */
export class RelayLoad extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS samples (relay TEXT NOT NULL, at INTEGER NOT NULL, load TEXT NOT NULL, PRIMARY KEY (relay, at))");
  }

  /** A relay's counters now; what it did since its sample before (relay-load-view.ts `relayMinute`). */
  record(relay: string, load: Load): RelayMinute | null {
    const now = nowSeconds();
    const before = this.ctx.storage.sql.exec<{ at: number; load: string }>("SELECT at, load FROM samples WHERE relay = ? ORDER BY at DESC LIMIT 1", relay).toArray()[0];
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO samples (relay, at, load) VALUES (?, ?, ?)", relay, now, JSON.stringify(load));
    this.ctx.storage.sql.exec("DELETE FROM samples WHERE relay = ? AND at < ?", relay, now - KEEP);
    return relayMinute(before ? { at: before.at, load: JSON.parse(before.load) as Load } : null, { at: now, load });
  }

  /** What a relay has carried since midnight UTC, as its budget counts (relay.ts): from its samples since then. */
  today(relay: string): { bytes: number; frames: number } {
    const now = nowSeconds();
    const midnight = Math.floor(now / 86_400) * 86_400;
    const rows = this.ctx.storage.sql.exec<{ at: number; load: string }>("SELECT at, load FROM samples WHERE relay = ? AND at >= ? ORDER BY at", relay, midnight - GAP).toArray();
    return relayLoadView(relay, rows.map((r) => ({ at: r.at, load: JSON.parse(r.load) as Load })), now).today;
  }

  /** The relays' views, in the order given. */
  view(relays: string[]): RelayLoadView[] {
    const now = nowSeconds();
    return relays.map((url) => {
      const rows = this.ctx.storage.sql.exec<{ at: number; load: string }>("SELECT at, load FROM samples WHERE relay = ? AND at >= ? ORDER BY at", url, now - 7 * 86_400 - GAP).toArray();
      return relayLoadView(url, rows.map((r) => ({ at: r.at, load: JSON.parse(r.load) as Load })), now);
    });
  }
}

/** At most this much of a relay's metrics is read (iroh-relay's are a few kilobytes). */
const MAX_METRICS = 256 * 1024;

/**
 * A relay's counters, from relay-load.sh on its machine: its metrics as iroh-relay gives them, with node_rx, node_tx and
 * node_load1 lines for the machine's; `x-stillfail-relay` says which relay (its URL among RELAY_URLS). Ours are named by
 * their IP, which is where they send from: one is believed when Cloudflare saw the request come from its own address.
 */
export async function receiveLoad(request: Request, env: Env): Promise<Response> {
  const named = request.headers.get("x-stillfail-relay") ?? "";
  const url = relayUrls(env).find((u) => sameUrl(u) === sameUrl(named));
  if (!url) return reply({ error: "unknown_relay" }, 400);
  const from = request.headers.get("cf-connecting-ip");
  if (!from || new URL(url).hostname.replace(/^\[|\]$/g, "") !== from) return reply({ error: "not_from_relay" }, 403);
  if (Number(request.headers.get("content-length") ?? 0) > MAX_METRICS) return reply({ error: "too_large" }, 413);
  const text = await request.text();
  if (text.length > MAX_METRICS) return reply({ error: "too_large" }, 413);
  const minute = await env.RELAY_LOAD.getByName("primary").record(url, relayLoad(text));
  await relayToAxiom(env, url, minute, relayConns(text).map((fields) => ({ what: "relay conn", fields })));
  return reply({ ok: true });
}

/**
 * still.fail's own relay's counters (the cron's, a minute apart): none while its process is not running. Its minute in
 * Axiom says how near it is to each of its budget's limits (relay.ts admit: LIMITS), and which it has reached
 * (`full`): 2026-10-30 it answered every new connection 429 from 12:22 in Beijing, and nothing said whether the day's
 * bytes or the connections held had run out. Said while the process is not running too (the budget run out stops it).
 */
export async function sampleOwnRelay(env: Env): Promise<void> {
  if (!env.RELAY || env.RELAY_URL) return;
  const text = await env.RELAY.getByName("primary").metrics().catch(() => null);
  const url = relayUrls(env)[0]!;
  const loads = env.RELAY_LOAD.getByName("primary");
  const load = text === null ? null : relayLoad(text);
  const minute = load === null ? null : await loads.record(url, load);
  const today = await loads.today(url);
  const open = load === null ? 0 : Math.max(0, load.accepts - load.disconnects);
  const connects = minute === null ? null : Math.round((minute.accepts * 60) / minute.secs);
  const full = [
    ...(today.bytes >= LIMITS.bytesPerDay ? ["bytes"] : []),
    ...(today.frames >= LIMITS.framesPerDay ? ["frames"] : []),
    ...(open >= LIMITS.connections ? ["connections"] : []),
    ...(connects !== null && connects >= LIMITS.connectsPerMinute ? ["connects"] : []),
  ];
  await relayToAxiom(env, url, {
    ...(minute ?? {}),
    running: text !== null,
    open,
    today_bytes: today.bytes,
    today_frames: today.frames,
    limit_bytes: LIMITS.bytesPerDay,
    limit_frames: LIMITS.framesPerDay,
    limit_connections: LIMITS.connections,
    limit_connects: LIMITS.connectsPerMinute,
    full: full.join(",") || "none",
  });
}

/** The console's 中继 page: every relay, named, still.fail's own with the budget it is held to (relay.ts). */
export async function relaysLoad(env: Env): Promise<{ relays: (RelayLoadView & { name: string; limits?: { bytes: number; frames: number } })[] }> {
  const urls = relayUrls(env);
  const views = await env.RELAY_LOAD.getByName("primary").view(urls);
  return {
    relays: views.map((v, i) => ({
      ...v,
      name: env.RELAY_NAMES?.[v.url] ?? new URL(v.url).host,
      ...(i === 0 && !env.RELAY_URL ? { limits: { bytes: LIMITS.bytesPerDay, frames: LIMITS.framesPerDay } } : {}),
    })),
  };
}
