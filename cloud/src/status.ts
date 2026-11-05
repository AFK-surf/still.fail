// What still.fail/status shows (status/status.html, GET /v1/status): each of still.fail's services, checked by the cron
// every minute, and how each has done on each of the last days. What is checked is only what still.fail runs itself: a
// station's own state is seen from the devices that reach it (docs/cloud.md), and a client that fails on what a service
// answers is not seen here.
import { DurableObject } from "cloudflare:workers";
import { nowSeconds, reply } from "./auth";
import type { Env } from "./env";
import { relayUrls } from "./relays";

/** How many days the page shows. */
export const DAYS = 30;
/** A relay is up while its counters came this recently (seconds): they come about a minute apart (relay-load.ts). It is
 * not fetched from here: a Worker cannot fetch an IP address, and the relay's Worker is on this Worker's own zone. */
const RELAY_SAMPLED = 300;
/** Nothing checked for this long (seconds): the cron has stopped, and what was last found says nothing of now. */
const STALE = 300;
/** A service is down from this many failed checks in a row: a single one is as often the check's own line. */
const DOWN_AFTER = 2;
/** How long a page is given to answer a check. */
const CHECK_MS = 10_000;

/** `degraded`: running, but refusing some: still.fail's own relay at its budget's limit (relay.ts admit). */
type Found = "up" | "degraded" | "down";
export type Check = { id: string; found: Found };
export type ServiceView = {
  id: string;
  state: Found | "unknown";
  /** What it is called, and where a browser can time it (its /ping), for a relay. */
  name?: string;
  relay?: string;
  /** The share of its checks that passed on each day, oldest first, the last today; null: not checked that day. */
  days: (number | null)[];
};

const dayOf = (seconds: number) => Math.floor(seconds / 86_400);

/** What was last found of each service and its days, in one object ("primary"). */
export class ServiceStatus extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS last (service TEXT PRIMARY KEY, at INTEGER NOT NULL, found TEXT NOT NULL, fails INTEGER NOT NULL)");
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS days (service TEXT NOT NULL, day INTEGER NOT NULL, ok INTEGER NOT NULL, total INTEGER NOT NULL, PRIMARY KEY (service, day))");
  }

  record(checks: Check[]): void {
    const now = nowSeconds();
    const today = dayOf(now);
    for (const { id, found } of checks) {
      const ok = found === "up" ? 1 : 0;
      this.ctx.storage.sql.exec("INSERT INTO last (service, at, found, fails) VALUES (?, ?, ?, ?) ON CONFLICT (service) DO UPDATE SET at = excluded.at, found = excluded.found, fails = CASE WHEN excluded.fails = 0 THEN 0 ELSE last.fails + 1 END", id, now, found, 1 - ok);
      this.ctx.storage.sql.exec("INSERT INTO days (service, day, ok, total) VALUES (?, ?, ?, 1) ON CONFLICT (service, day) DO UPDATE SET ok = ok + excluded.ok, total = total + 1", id, today, ok);
    }
    this.ctx.storage.sql.exec("DELETE FROM days WHERE day <= ?", today - DAYS);
  }

  view(ids: string[]): Omit<ServiceView, "name" | "relay">[] {
    const now = nowSeconds();
    const first = dayOf(now) - DAYS + 1;
    return ids.map((id) => {
      const last = this.ctx.storage.sql.exec<{ at: number; found: Found; fails: number }>("SELECT at, found, fails FROM last WHERE service = ?", id).toArray()[0];
      const days: (number | null)[] = Array.from({ length: DAYS }, () => null);
      for (const row of this.ctx.storage.sql.exec<{ day: number; ok: number; total: number }>("SELECT day, ok, total FROM days WHERE service = ? AND day >= ?", id, first)) days[row.day - first] = row.ok / row.total;
      const state = !last || now - last.at > STALE ? "unknown" : last.found === "down" && last.fails < DOWN_AFTER ? "up" : last.found;
      return { id, state, days };
    });
  }
}

/** The services, in the order the page shows them: the pages STATUS_PAGES names, the API, the releases, then the relays. */
function serviceIds(env: Env): string[] {
  return [...Object.keys(env.STATUS_PAGES ?? {}), "api", ...(env.RELEASES && !env.RELEASES_UPSTREAM ? ["releases"] : []), ...relayUrls(env).map((url) => `relay:${url}`)];
}

const passes = async (check: () => Promise<boolean>) => (await check().catch(() => false)) ? "up" : "down";

/** One round of checks (the cron's, a minute apart). `full`: which limits of its budget still.fail's own relay has reached (relay-load.ts). */
export async function checkServices(env: Env, full: string[]): Promise<void> {
  const loads = env.RELAY_LOAD.getByName("primary");
  const now = nowSeconds();
  const pages = Object.entries(env.STATUS_PAGES ?? {}).map(async ([id, url]): Promise<Check> => ({
    id,
    found: await passes(async () => (await fetch(url, { method: "HEAD", signal: AbortSignal.timeout(CHECK_MS) })).ok),
  }));
  // The API: this Worker runs, as the cron shows, and reaches the object every signed-in call goes through.
  const api = passes(async () => (await env.DIRECTORY.getByName("primary").isBeta("status"), true)).then((found): Check => ({ id: "api", found }));
  // What installing and updating read first.
  const releases = env.RELEASES && !env.RELEASES_UPSTREAM ? [passes(async () => (await env.RELEASES!.head("station.json")) !== null).then((found): Check => ({ id: "releases", found }))] : [];
  const relays = relayUrls(env).map(async (url, i): Promise<Check> => {
    const at = await loads.lastSampled(url);
    const found = at === null || now - at > RELAY_SAMPLED ? "down" : i === 0 && full.length > 0 ? "degraded" : "up";
    return { id: `relay:${url}`, found };
  });
  await env.SERVICE_STATUS.getByName("primary").record(await Promise.all([...pages, api, ...releases, ...relays]));
}

/** GET /v1/status. From any page, as the site's status page is on a host of its own; what it says is no secret. */
export async function serveStatus(env: Env): Promise<Response> {
  const views = await env.SERVICE_STATUS.getByName("primary").view(serviceIds(env));
  const services = views.map((view): ServiceView => {
    if (!view.id.startsWith("relay:")) return view;
    const relay = view.id.slice("relay:".length);
    return { ...view, id: "relay", relay, name: env.RELAY_NAMES?.[relay] ?? new URL(relay).host };
  });
  return reply({ now: nowSeconds(), days: DAYS, services }, 200, { "access-control-allow-origin": "*", "cache-control": "public, max-age=30" });
}
