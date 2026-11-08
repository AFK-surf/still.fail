// What Comma keeps of the workspace's statistics through a Comma connect: the Stats index a Comma station sends
// (`stats.index`, as Cue's systems/station/src/stats has it), here of one source, `stillfail`: what the workspace's
// agents spent, by day, chat, person, account and model, and the chats they worked in, of this station and of the
// other stations of its workspace (read of them as `outflow.read`, peer.ts). The index is kept in <data>/comma-stats.db,
// numbered as its rows change, and each connection sends Comma what it does not hold yet, a page at a time.
//
// Built as the station starts, a minute after its agents' spending was recorded, and every hour (another station's
// spending reaches it so); one build at a time.
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";

type Json = any;

/// The days a build takes again: what can still change (a call recorded late, a chat going on).
export const BUILD_DAYS = 31;
const DAY_MS = 24 * 60 * 60_000;
const SETTLE_MS = 60_000;
const EVERY_MS = 60 * 60_000;
/// The source the rows are of, as Comma's analysis names it.
export const SOURCE = "stillfail";
const SEP = "\u0000";

/// What one station of the workspace gave: its usage rows (`outflowUsage`'s) and chats (`outflowChats`'), and the
/// people its rows name. `station`: another station's id; none for this one.
export type StationRows = { station?: string; usage: Json; chats: Json[] };

/// What a build reads: this station's rows, and those of each other station of the workspace that answered
/// (`unread`, the ids of those that did not: their rows stay as they were).
export type Read = (from: number, to: number) => Promise<{ stations: StationRows[]; unread: string[] }>;

/// A row as the index keeps it and `stats.index` carries it.
export type StatsRow = { key: string; source: string; kind: string; rev: number; removed: boolean; json: string };

/// Who a person is, as Comma counts them: their email, so one heard in the app and in a chat app adds up to one, else
/// their name, else the station's reference.
function who(person: Json, ref: string | null): string | null {
  if (typeof person?.email === "string" && person.email !== "") return person.email;
  if (typeof person?.name === "string" && person.name !== "") return person.name;
  return ref;
}

/// One station's rows as the index keeps them, by key.
export function rowsOf(given: StationRows, fromDay: string): Map<string, { kind: string; json: string }> {
  const at = given.station === undefined ? [] : [`@${given.station}`];
  const station = given.station === undefined ? {} : { station: given.station };
  const people = given.usage?.people ?? {};
  const rows = new Map<string, { kind: string; json: string }>();
  for (const r of Array.isArray(given.usage?.rows) ? given.usage.rows : []) {
    if (typeof r?.day !== "string" || typeof r?.session !== "string" || r.day < fromDay) continue;
    const row = {
      day: r.day, session: r.session, thread: r.thread ?? null, person: who(people[r.person], r.person ?? null), personRef: r.person ?? null,
      account: r.account ?? null, runtime: r.runtime, model: r.model ?? null, calls: r.calls, input: r.input, cacheRead: r.cacheRead,
      cacheWrite: r.cacheWrite, output: r.output, cost: r.cost ?? null, ...station,
    };
    rows.set([SOURCE, "usage", ...at, r.day, r.session, r.person ?? "", r.account ?? "", r.runtime, r.model ?? ""].join(SEP), { kind: "usage", json: JSON.stringify(row) });
  }
  for (const c of given.chats) {
    if (typeof c?.thread !== "number") continue;
    const row = {
      thread: c.thread, surface: c.surface ?? "unknown", title: c.title ?? "", state: c.state ?? null,
      creator: c.creator === null || c.creator === undefined ? null : who(c.creator, c.creator.ref ?? null),
      createdAt: c.createdAt ?? 0, lastActiveAt: c.lastActiveAt ?? 0, archived: c.archived === true, agents: c.agents ?? [], ...station,
    };
    rows.set([SOURCE, "task", ...at, String(c.thread)].join(SEP), { kind: "task", json: JSON.stringify(row) });
  }
  return rows;
}

export class CommaStats {
  readonly #db: DatabaseSync;
  readonly #listeners = new Set<() => void>();
  /// What each connection's Comma holds: tombstones go once every one holds them.
  readonly #held = new Map<string, number>();
  #building: Promise<void> | null = null;
  #again = false;
  #stops: (() => void)[] | null = null;

  /// `usage`: tells when the agents spent, until the function it answers is called.
  readonly #read: Read;
  readonly #usage: (changed: () => void) => () => void;

  constructor(path: string, read: Read, usage: (changed: () => void) => () => void) {
    this.#read = read;
    this.#usage = usage;
    this.#db = new DatabaseSync(path);
    this.#db.exec(`
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS stats_index (key TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL, rev INTEGER NOT NULL,
        json TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0);
      CREATE INDEX IF NOT EXISTS stats_index_rev ON stats_index (rev);`);
  }

  static at(data: string, read: Read, usage: (changed: () => void) => () => void): CommaStats {
    mkdirSync(data, { recursive: true });
    return new CommaStats(join(data, "comma-stats.db"), read, usage);
  }

  /// Once Comma is connected first: builds now, a minute after the agents spent, and every hour, until close.
  start(): void {
    if (this.#stops !== null) return;
    let settle: (() => void) | null = null;
    const stopUsage = this.#usage(() => {
      if (settle !== null) return;
      settle = wall.after(SETTLE_MS, () => {
        settle = null;
        this.build();
      });
    });
    const tick = () => {
      this.build();
      hourly = wall.after(EVERY_MS, tick);
    };
    let hourly = wall.after(EVERY_MS, tick);
    this.#stops = [stopUsage, () => settle?.(), () => hourly()];
    this.build();
  }

  close(): void {
    for (const stop of this.#stops ?? []) stop();
    this.#stops = null;
    this.#db.close();
  }

  /// A build, after the one under way when there is one.
  build(): void {
    if (this.#building !== null) {
      this.#again = true;
      return;
    }
    const now = wall.now();
    this.#building = this.#read(now - BUILD_DAYS * DAY_MS, now)
      .then(({ stations, unread }) => void this.apply(stations, unread, now - BUILD_DAYS * DAY_MS))
      .catch((e) => log.info("comma", "the statistics were not read this time", { error: (e as Error).message }))
      .finally(() => {
        this.#building = null;
        if (this.#again) {
          this.#again = false;
          this.build();
        }
      });
  }

  /// Settles once the build under way (tests).
  async settled(): Promise<void> {
    while (this.#building !== null) await this.#building;
  }

  epoch(): string {
    const had = this.#meta("epoch");
    if (had !== null) return had;
    const epoch = randomBytes(16).toString("hex");
    this.#setMeta("epoch", epoch);
    return epoch;
  }

  rev(): number {
    return Number(this.#meta("rev") ?? 0);
  }

  since(since: number, limit: number): StatsRow[] {
    return (this.#db.prepare("SELECT key, source, kind, rev, removed, json FROM stats_index WHERE rev > ? ORDER BY rev LIMIT ?").all(since, limit) as Json[]).map((r) => ({
      key: r.key, source: r.source, kind: r.kind, rev: r.rev, removed: r.removed !== 0, json: r.json,
    }));
  }

  /// What connection `host`'s Comma holds now; tombstones every one holds go.
  held(host: string, through: number): void {
    this.#held.set(host, through);
    this.#db.prepare("DELETE FROM stats_index WHERE removed = 1 AND rev <= ?").run(Math.min(...this.#held.values()));
  }

  /// A connection gone: what it held no longer keeps tombstones.
  gone(host: string): void {
    this.#held.delete(host);
  }

  listen(changed: () => void): () => void {
    this.#listeners.add(changed);
    return () => void this.#listeners.delete(changed);
  }

  /// The stations' rows from the day of `from` on, written where they changed; a usage row of those days no longer
  /// given is tombstoned, but not one of a station not read this time. How many rows changed.
  apply(stations: StationRows[], unread: string[], from: number): number {
    const fromDay = new Date(Math.floor(from / DAY_MS) * DAY_MS).toISOString().slice(0, 10);
    const given = new Map<string, { kind: string; json: string }>();
    for (const s of stations) for (const [key, row] of rowsOf(s, fromDay)) given.set(key, row);
    const skipped = new Set(unread);
    let rev = this.rev();
    let changed = 0;
    this.#db.exec("BEGIN");
    try {
      const get = this.#db.prepare("SELECT json, removed FROM stats_index WHERE key = ?");
      const put = this.#db.prepare(
        "INSERT INTO stats_index (key, source, kind, rev, json, removed) VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT (key) DO UPDATE SET rev = excluded.rev, json = excluded.json, removed = 0",
      );
      for (const [key, row] of given) {
        const had = get.get(key) as { json: string; removed: number } | undefined;
        if (had !== undefined && had.removed === 0 && had.json === row.json) continue;
        put.run(key, SOURCE, row.kind, ++rev, row.json);
        changed++;
      }
      const kept = this.#db.prepare("SELECT key, json FROM stats_index WHERE kind = 'usage' AND removed = 0").all() as { key: string; json: string }[];
      const drop = this.#db.prepare("UPDATE stats_index SET removed = 1, rev = ? WHERE key = ?");
      for (const k of kept) {
        if (given.has(k.key)) continue;
        const row = JSON.parse(k.json);
        if ((row.day ?? "") < fromDay || skipped.has(row.station ?? "")) continue;
        drop.run(++rev, k.key);
        changed++;
      }
      if (changed > 0) this.#setMeta("rev", String(rev));
      this.#db.exec("COMMIT");
    } catch (e) {
      this.#db.exec("ROLLBACK");
      throw e;
    }
    if (changed > 0) for (const l of this.#listeners) l();
    return changed;
  }

  #meta(key: string): string | null {
    return (this.#db.prepare("SELECT value FROM meta WHERE key = ?").get(key) as { value: string } | undefined)?.value ?? null;
  }

  #setMeta(key: string, value: string): void {
    this.#db.prepare("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value").run(key, value);
  }
}

// ── the pages a connection sends ───────────────────────────────────────────────────────────────────────────────────

/// What Comma holds of the index.
export type Held = { epoch: string | null; through: number };

/// A `stats.index` page.
export type Page = { epoch: string; reset: boolean; since: number; through: number; rows: Json[] };

/// Comma's bounds on a page: rows, and bytes of its rows as JSON.
export const PAGE_ROWS = 200;
export const PAGE_BYTES = 60 * 1024;

/// The page that only asks what Comma holds: applying it changes nothing.
export function probePage(stats: CommaStats): Page {
  const rev = stats.rev();
  return { epoch: stats.epoch(), reset: false, since: rev, through: rev, rows: [] };
}

/// The next page to send after Comma answered `held`; null once it holds all of the index.
export function nextPage(stats: CommaStats, held: Held): Page | null {
  const epoch = stats.epoch();
  const rev = stats.rev();
  const reset = held.epoch !== epoch;
  const since = reset ? 0 : held.through;
  if (!reset && since >= rev) return null;
  const changed = stats.since(since, PAGE_ROWS + 1);
  const rows: Json[] = [];
  let bytes = 2;
  let taken = 0;
  let last = since;
  for (const row of changed.slice(0, PAGE_ROWS)) {
    const sent = wireRow(row);
    const size = sent === null ? 0 : Buffer.byteLength(JSON.stringify(sent)) + 1;
    if (rows.length > 0 && bytes + size > PAGE_BYTES) break;
    if (sent !== null) rows.push(sent);
    bytes += size;
    taken += 1;
    last = row.rev;
  }
  // A page short of the end brings Comma to its last row; the last page to the index's rev, past pruned tombstones.
  const through = taken < changed.length ? last : rev;
  return { epoch, reset, since, through, rows };
}

function wireRow(row: StatsRow): Json | null {
  if (row.removed) return { key: row.key, source: row.source, kind: row.kind, rev: row.rev, removed: true };
  try {
    return { key: row.key, source: row.source, kind: row.kind, rev: row.rev, row: JSON.parse(row.json) };
  } catch {
    return null;
  }
}

/// Comma's answer to a page, or null when it is not one.
export function heldFrom(result: unknown): Held | null {
  if (typeof result !== "object" || result === null) return null;
  const { epoch, through } = result as Record<string, unknown>;
  if (epoch !== null && epoch !== undefined && typeof epoch !== "string") return null;
  return { epoch: (epoch as string | null | undefined) ?? null, through: typeof through === "number" && through >= 0 ? through : 0 };
}
