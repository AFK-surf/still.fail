import type { DatabaseSync } from "node:sqlite";
import { Refused } from "../api/request.ts";
import { wall } from "../ops/fibers.ts";
import type { InWorkspace } from "../store/rows.ts";
import { compactScopeReady, hasCompactUsage } from "../store/usage-compact.ts";
import { type UsageGroup, usageGroupOf } from "../store/usage.ts";
import type { Store } from "./store.ts";

/// The requested time index, ownership lookup, and the selected session's minute index.
export function batchedUsageQueries(viewer: InWorkspace | null): { selected: string; owner: string; buckets: string; pending: string; pendingRange: string; anyPending: string } {
  const index = viewer === null ? "usage_compact_time" : "usage_compact_scope_time";
  const scope = viewer === null ? "" : viewer.home === false ? "scope = ?3 AND " : "scope IN (?3, 'H') AND ";
  const bucketScope = viewer === null ? "" : viewer.home === false ? " AND scope = ?5" : " AND scope IN (?5, 'H')";
  const pendingIndex = viewer === null ? "usage_compact_pending_session" : "usage_compact_pending_scope";
  const pendingScope = viewer === null ? "" : viewer.home === false ? " AND scope = ?1" : " AND scope IN (?1, 'H')";
  const pendingFrom = " FROM usage_compact INDEXED BY " + pendingIndex + " WHERE pending = 1" + pendingScope;
  return {
    selected: "SELECT session FROM usage_compact INDEXED BY " + index + " WHERE " + scope + "minute >= ?1 AND minute < ?2",
    owner: "SELECT ws FROM usage_minute_scope WHERE session = ?",
    buckets: "SELECT strftime('%Y-%m-%d', (minute + ?1) * 60, 'unixepoch') AS day, minute, " +
      "session, thread, person, profile, runtime, model, fast, calls, input, cache_read, cache_write, cache_write_long, output " +
      "FROM usage_compact WHERE session = ?2 AND minute >= ?3 AND minute < ?4" + bucketScope + " AND records > 0",
    pending: "SELECT session, minute" + pendingFrom,
    pendingRange: "SELECT session, minute, pending FROM usage_compact INDEXED BY " + index + " WHERE " + scope + "minute >= ?1 AND minute < ?2",
    anyPending: "SELECT 1" + pendingFrom + " LIMIT 1",
  };
}

type Part = { day: string | null; session: string; thread: bigint; person: string; profile: string;
  runtime: string; model: string; fast: bigint; calls: bigint; input: bigint; cache_read: bigint;
  cache_write: bigint; cache_write_long: bigint; output: bigint };
type Bucket = Part & { minute: bigint };
type Hour = { session: string; minute: bigint; groups: Map<string, Part>; bytes: number };
type Cached = { seq: bigint; hours: Map<string, Hour>; cells: number; bytes: number };
const names = ["calls", "input", "cache_read", "cache_write", "cache_write_long", "output"] as const;
const MAX_CELLS = 8192;
const MAX_BYTES = 8 * 1024 * 1024;
const MAX_ENTRIES = 3;

/// Kept by one reader, never shared across connections. Bound both the number and size of cached answers.
export class UsageSummaryCache {
  private db: DatabaseSync | null = null;
  private readonly entries = new Map<string, Cached>();
  private use(db: DatabaseSync): void {
    if (this.db !== db) { this.entries.clear(); this.db = db; }
  }
  get(db: DatabaseSync, key: string): Cached | undefined {
    this.use(db);
    const found = this.entries.get(key);
    if (found) { this.entries.delete(key); this.entries.set(key, found); }
    return found;
  }
  put(db: DatabaseSync, key: string, value: Cached): void {
    this.use(db);
    this.entries.delete(key);
    if (value.cells > MAX_CELLS || value.bytes > MAX_BYTES) return;
    while (this.entries.size >= MAX_ENTRIES ||
      [...this.entries.values()].reduce((n, e) => n + e.cells, 0) + value.cells > MAX_CELLS ||
      [...this.entries.values()].reduce((n, e) => n + e.bytes, 0) + value.bytes > MAX_BYTES) {
      this.entries.delete(this.entries.keys().next().value!);
    }
    this.entries.set(key, value);
  }
  drop(db: DatabaseSync, key: string): void { this.use(db); this.entries.delete(key); }
}

const groupKey = (r: Part) => JSON.stringify([r.day, r.thread.toString(), r.person, r.profile, r.runtime, r.model, r.fast.toString()]);
const hourKey = (session: string, minute: bigint) => JSON.stringify([session, minute.toString()]);
const floorDiv = (n: bigint, d: bigint) => n >= 0n ? n / d : -1n - ((-1n - n) / d);
const hourOf = (minute: bigint, offset: bigint) => floorDiv(minute + offset, 60n) * 60n - offset;

function add(map: Map<string, Part>, key: string, row: Part): boolean {
  const held = map.get(key);
  if (held === undefined) { map.set(key, { ...row }); return true; }
  for (const name of names) held[name] += row[name];
  return false;
}

function answer(groups: Part[]): UsageGroup[] {
  const safe = (n: bigint) => {
    if (n > BigInt(Number.MAX_SAFE_INTEGER) || n < BigInt(Number.MIN_SAFE_INTEGER)) throw new RangeError("integer is too large to be represented as a JavaScript number");
    return Number(n);
  };
  // SQLite's GROUP BY order: binary text comparison, with NULL before other values.
  const cmp = (a: string | bigint | null, b: string | bigint | null): number => a === b ? 0 : a === null ? -1 : b === null ? 1
    : typeof a === "bigint" && typeof b === "bigint" ? (a < b ? -1 : 1) : Buffer.compare(Buffer.from(String(a)), Buffer.from(String(b)));
  groups.sort((a, b) => cmp(a.day, b.day) || cmp(a.session, b.session) || cmp(a.thread, b.thread)
    || cmp(a.person, b.person) || cmp(a.profile, b.profile) || cmp(a.runtime, b.runtime) || cmp(a.model, b.model) || cmp(a.fast, b.fast));
  return groups.map((r) => usageGroupOf({ ...r, thread: r.thread === 0n ? null : safe(r.thread), person: r.person || null,
    profile: r.profile || null, model: r.model || null, fast: safe(r.fast), calls: safe(r.calls), input: safe(r.input),
    cache_read: safe(r.cache_read), cache_write: safe(r.cache_write), cache_write_long: safe(r.cache_write_long), output: safe(r.output) }));
}

function combine(hours: Map<string, Hour>): Part[] {
  const groups = new Map<string, Part>();
  for (const hour of hours.values()) for (const row of hour.groups.values()) {
    add(groups, JSON.stringify([row.session, groupKey(row)]), row);
  }
  return [...groups.values()];
}

/// An aligned compact summary, read in bounded steps on the caller's snapshot. Cached hours are only reused when
/// the journal still covers every subsequent change; otherwise this takes the ordinary full indexed path.
export async function usageGroupsBatched(s: Store, from: bigint, to: bigint, utcOffsetMin: bigint, viewer: InWorkspace | null = null,
  pause: (ms: number) => Promise<void> = (ms) => ms > 0 ? wall.sleep(ms) : new Promise((resolve) => setImmediate(resolve)),
  cache?: UsageSummaryCache, kind: "summary" | "history" = "summary"): Promise<{
    groups: UsageGroup[]; diagnostics: { parts: number; candidates: number; selectedMs: number; rests: number; restMs: number; reused: boolean }; ms: number;
  } | null> {
  const max = 9223372036854775807n;
  if (!hasCompactUsage(s.db) || (from < to && (from % 60_000n !== 0n || (to !== max && to % 60_000n !== 0n)))) return null;
  if (!compactScopeReady(s.db, viewer)) throw new Refused(503, "usage statistics are moving between workspaces");
  const start = from >= to ? 0n : floorDiv(from, 60_000n);
  const end = from >= to ? 0n : to === max ? max : floorDiv(to, 60_000n);
  const queries = batchedUsageQueries(viewer);
  const started = performance.now();
  let batchAt = started, steps = 0, rests = 0, restMs = 0, candidates = 0, parts = 0;
  const rest = async () => {
    const ms = Math.min(100, Math.floor(performance.now() - batchAt));
    const pausedAt = performance.now();
    await pause(ms);
    restMs += performance.now() - pausedAt;
    rests++;
    steps = 0;
    batchAt = performance.now();
  };
  const result = (groups: Part[], selectedMs: number, reused = false) => ({ groups: answer(groups),
    diagnostics: { parts, candidates, selectedMs, rests, restMs: Math.round(restMs), reused }, ms: Math.round(performance.now() - started) });
  const key = JSON.stringify([kind, from.toString(), to.toString(), utcOffsetMin.toString(), viewer?.workspace ?? null,
    viewer === null ? null : viewer.home !== false]);
  const journal = cache !== undefined && s.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_changes'").get() !== undefined;
  if (kind === "history" && !journal) return null;
  let first = 0n, last = 0n;
  if (journal) {
    const bounds = s.db.prepare("SELECT (SELECT seq FROM usage_summary_changes ORDER BY seq LIMIT 1) AS first, " +
      "(SELECT seq FROM usage_summary_changes ORDER BY seq DESC LIMIT 1) AS last");
    bounds.setReadBigInts(true);
    const row = bounds.get() as { first: bigint | null; last: bigint | null };
    first = row.first ?? 0n;
    last = row.last ?? 0n;
  }
  const prior = journal ? cache!.get(s.db, key) : undefined;
  const usable = prior !== undefined && prior.seq <= last && (first === 0n ? prior.seq === last : prior.seq >= first - 1n);

  // A cache is updated only after the complete read succeeds. Unchanged hour maps remain immutable and can be shared
  // with the preceding snapshot while new ones are built.
  let hours: Map<string, Hour> | null = journal ? new Map(usable ? prior.hours : []) : null;
  let cells = usable ? prior.cells : 0;
  let bytes = usable ? prior.bytes : 0;
  const putBucket = (row: Bucket) => {
    if (hours === null) return;
    const hour = hourOf(row.minute, utcOffsetMin);
    const key = hourKey(row.session, hour);
    let held = hours.get(key);
    if (!held) {
      held = { session: row.session, minute: hour, groups: new Map(), bytes: 128 + key.length * 2 };
      hours.set(key, held);
      bytes += held.bytes;
    }
    const group = groupKey(row);
    if (add(held.groups, group, row)) {
      cells++;
      // Count the key, retained strings, bigint fields and object overhead conservatively. Long names cannot make
      // an otherwise small number of groups retain an unbounded share of a reader's 128 MB heap.
      const size = 256 + 2 * (group.length + row.session.length + (row.day?.length ?? 0) + row.person.length
        + row.profile.length + row.runtime.length + row.model.length);
      held.bytes += size;
      bytes += size;
      if (cells > MAX_CELLS || bytes > MAX_BYTES) hours = null;
    }
  };
  let bucket: ReturnType<DatabaseSync["prepare"]> | undefined;
  const visible = viewer === null ? null : s.db.prepare(queries.owner);
  const readSession = async (session: string, low: bigint, high: bigint, groups?: Map<string, Part>) => {
    const found = visible?.get(session) as { ws: string | null } | undefined;
    const seen = viewer === null || (found !== undefined && (found.ws === viewer.workspace || (viewer.home !== false && found.ws === null)));
    if (++steps >= 64) await rest();
    if (!seen || low >= high) return true;
    if (bucket === undefined) { bucket = s.db.prepare(queries.buckets); bucket.setReadBigInts(true); }
    const args: (string | bigint)[] = [utcOffsetMin, session, low, high];
    if (viewer !== null) args.push("W" + viewer.workspace);
    for (const bucketRow of bucket.iterate(...args) as Iterable<Bucket>) {
      // History groups only by day, session, runtime and model. Do not retain a row for every person or thread.
      const row = kind === "history" ? { ...bucketRow, thread: 0n, person: "", profile: "", fast: 0n } : bucketRow;
      parts++;
      if (groups) add(groups, groupKey(row), row);
      putBucket(row);
      // A very large history can have far more details than its answer. Leave it to the existing SQL aggregate.
      if (kind === "history" && hours === null) return false;
      if (++steps >= 64) await rest();
    }
    return true;
  };

  if (usable) {
    const scope = viewer === null ? "" : viewer.home === false ? " AND scope = ?3" : " AND scope IN (?3, 'H')";
    const changes = s.db.prepare("SELECT session, minute FROM usage_summary_changes WHERE seq > ?1 AND seq <= ?2" + scope);
    changes.setReadBigInts(true);
    const args: (string | bigint)[] = [prior.seq, last];
    if (viewer !== null) args.push("W" + viewer.workspace);
    const whole = new Set<string>();
    const dirty = new Map<string, { session: string; minute: bigint }>();
    const changedMinute = (session: string, minute: bigint, target = dirty) => {
      if (minute < start || minute >= end) return;
      const hour = hourOf(minute, utcOffsetMin);
      target.set(hourKey(session, hour), { session, minute: hour });
    };
    for (const row of changes.iterate(...args) as Iterable<{ session: string; minute: bigint | null }>) {
      if (row.minute === null) whole.add(row.session);
      else changedMinute(row.session, row.minute);
      if (++steps >= 128) await rest();
    }
    // Repeated writes to a pending bucket are coalesced until the totals worker accounts it. A pending bucket may
    // have changed since this snapshot, so refresh its hour; accounting it records a change before it disappears.
    const pendingArgs = viewer === null ? [] : ["W" + viewer.workspace];
    if (s.db.prepare(queries.anyPending).get(...pendingArgs)) {
      // Usually only a few buckets are pending. If there are many, compare that index with the requested time
      // range and stop as soon as either is exhausted: a narrow request must not walk another year's pending work,
      // and a wide request must not walk every minute merely to find a handful of pending buckets.
      type Pending = { session: string; minute: bigint };
      const pending = s.db.prepare(queries.pending);
      pending.setReadBigInts(true);
      const pendingRows = (pending.iterate(...pendingArgs) as IterableIterator<Pending>)[Symbol.iterator]();
      let rangeRows: IterableIterator<Pending & { pending: bigint }> | undefined;
      let pendingChanges = new Map<string, { session: string; minute: bigint }>();
      try {
        let complete = false;
        for (let n = 0; n < 64; n++) {
          const next = pendingRows.next();
          if (next.done) { complete = true; break; }
          candidates++;
          changedMinute(next.value.session, next.value.minute, pendingChanges);
          if (++steps >= 64) await rest();
        }
        if (!complete) {
          const range = s.db.prepare(queries.pendingRange);
          range.setReadBigInts(true);
          const rangeArgs: (string | bigint)[] = [start, end];
          if (viewer !== null) rangeArgs.push("W" + viewer.workspace);
          rangeRows = (range.iterate(...rangeArgs) as IterableIterator<Pending & { pending: bigint }>)[Symbol.iterator]();
          const rangeChanges = new Map<string, { session: string; minute: bigint }>();
          for (;;) {
            const inRange = rangeRows.next();
            if (inRange.done) { pendingChanges = rangeChanges; break; }
            candidates++;
            if (inRange.value.pending === 1n) changedMinute(inRange.value.session, inRange.value.minute, rangeChanges);
            if (++steps >= 64) await rest();
            const next = pendingRows.next();
            if (next.done) break;
            candidates++;
            changedMinute(next.value.session, next.value.minute, pendingChanges);
            if (++steps >= 64) await rest();
          }
        }
      } finally {
        pendingRows.return?.();
        rangeRows?.return?.();
      }
      for (const [id, change] of pendingChanges) dirty.set(id, change);
    }
    const selectedMs = Math.round(performance.now() - started);
    for (const [id, hour] of hours!) if (whole.has(hour.session) || dirty.has(id)) {
      cells -= hour.groups.size;
      bytes -= hour.bytes;
      hours!.delete(id);
    }
    for (const session of whole) if (!(await readSession(session, start, end))) { cache!.drop(s.db, key); return null; }
    for (const { session, minute } of dirty.values()) if (!whole.has(session)) {
      if (!(await readSession(session, minute > start ? minute : start, minute + 60n < end ? minute + 60n : end))) {
        cache!.drop(s.db, key);
        return null;
      }
    }
    if (hours !== null) {
      const groups = combine(hours);
      // Formatting can fail on integer overflow. Do not publish an entry from a failed answer.
      const done = result(groups, selectedMs, true);
      cache!.put(s.db, key, { seq: last, hours, cells, bytes });
      return done;
    }
    cache!.drop(s.db, key);
    // The changed hour made this answer too large to cache. Reread it using the bounded path below, retaining the
    // work already done in the diagnostics and total duration.
  }

  const params: (string | bigint)[] = [start, end];
  if (viewer !== null) params.push("W" + viewer.workspace);
  const selected = s.db.prepare(queries.selected);
  const sessions = new Set<string>();
  for (const row of selected.iterate(...params) as Iterable<{ session: string }>) {
    candidates++;
    sessions.add(row.session);
    if (++steps >= 64) await rest();
  }
  const selectedMs = Math.round(performance.now() - started);
  const groups: Part[] = [];
  for (const session of sessions) {
    const ofSession = new Map<string, Part>();
    if (!(await readSession(session, start, end, ofSession))) { cache!.drop(s.db, key); return null; }
    groups.push(...ofSession.values());
  }
  const done = result(groups, selectedMs);
  if (hours !== null) cache!.put(s.db, key, { seq: last, hours, cells, bytes });
  else cache?.drop(s.db, key);
  return done;
}

export type BatchedUsage = NonNullable<Awaited<ReturnType<typeof usageGroupsBatched>>>;
