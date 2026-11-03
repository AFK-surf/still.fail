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
type Block = { session: string; minute: bigint; groups: Map<string, Part>; bytes: number };
type Total = { row: Part; refs: number; bytes: number };
type Cached = { seq: bigint; blocks: Map<string, Block>; totals: Map<string, Total>; width: bigint; cells: number; bytes: number };
type CacheStatus = "disabled" | "miss" | "expired" | "reused" | "oversized";
type SqlStage = "journal" | "changes" | "pending" | "selected" | "owner" | "buckets";
export type UsageSqlTimings = Record<SqlStage, number> & { slowMs: number; slowOp: string };
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
const blockKey = (session: string, minute: bigint) => JSON.stringify([session, minute.toString()]);
const totalKey = (session: string, group: string) => JSON.stringify([session, group]);
const floorDiv = (n: bigint, d: bigint) => n >= 0n ? n / d : -1n - ((-1n - n) / d);
const blockOf = (minute: bigint, offset: bigint, width: bigint) => floorDiv(minute + offset, width) * width - offset;

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

/// An aligned compact summary, read in bounded steps on the caller's snapshot. Cached blocks are only reused when
/// the journal still covers every subsequent change; otherwise this takes the ordinary full indexed path.
export async function usageGroupsBatched(s: Store, from: bigint, to: bigint, utcOffsetMin: bigint, viewer: InWorkspace | null = null,
  pause: (ms: number) => Promise<void> = (ms) => ms > 0 ? wall.sleep(ms) : new Promise((resolve) => setImmediate(resolve)),
  cache?: UsageSummaryCache, kind: "summary" | "history" = "summary"): Promise<{
    groups: UsageGroup[]; diagnostics: { parts: number; candidates: number; selectedMs: number; selectedRestMs: number;
      selectedCpuMs?: number; cpuMs?: number; rests: number; restMs: number; cache: CacheStatus; sql: UsageSqlTimings }; ms: number;
  } | null> {
  const max = 9223372036854775807n;
  if (!hasCompactUsage(s.db) || (from < to && (from % 60_000n !== 0n || (to !== max && to % 60_000n !== 0n)))) return null;
  if (!compactScopeReady(s.db, viewer)) throw new Refused(503, "usage statistics are moving between workspaces");
  const start = from >= to ? 0n : floorDiv(from, 60_000n);
  const end = from >= to ? 0n : to === max ? max : floorDiv(to, 60_000n);
  const queries = batchedUsageQueries(viewer);
  const started = performance.now();
  // A wall-clock delay in a reader can be SQLite/CPU work, scheduling or our own deliberate rests. The thread's CPU
  // time distinguishes those without inspecting another process or measuring the user's data.
  let cpuStart: NodeJS.CpuUsage | undefined;
  try { cpuStart = process.threadCpuUsage(); } catch { /* Some runtimes cannot report per-thread CPU. */ }
  const cpuMs = (): number | undefined => {
    if (cpuStart === undefined) return undefined;
    try { const cpu = process.threadCpuUsage(cpuStart); return Math.round((cpu.user + cpu.system) / 1000); }
    catch { return undefined; }
  };
  let batchAt = started, steps = 0, rests = 0, restMs = 0, candidates = 0, parts = 0;
  let selectedRestMs = 0, selectedCpuMs: number | undefined;
  const sql: UsageSqlTimings = { journal: 0, changes: 0, pending: 0, selected: 0, owner: 0, buckets: 0, slowMs: 0, slowOp: "none" };
  const timeSql = <T>(stage: SqlStage, f: () => T): T => {
    const at = performance.now();
    try { return f(); }
    finally {
      const ms = performance.now() - at;
      sql[stage] += ms;
      if (ms > sql.slowMs) { sql.slowMs = ms; sql.slowOp = stage; }
    }
  };
  function* sqlRows<T>(stage: SqlStage, rows: Iterable<T>): Iterable<T> {
    const iter = rows[Symbol.iterator]();
    let done = false;
    try {
      for (;;) {
        const row = timeSql(stage, () => iter.next());
        if (row.done) { done = true; return; }
        yield row.value;
      }
    } finally { if (!done && iter.return) timeSql(stage, () => iter.return!()); }
  }
  const rest = async () => {
    const ms = Math.min(100, Math.floor(performance.now() - batchAt));
    const pausedAt = performance.now();
    await pause(ms);
    restMs += performance.now() - pausedAt;
    rests++;
    steps = 0;
    batchAt = performance.now();
  };
  const result = (groups: Part[], selectedMs: number, cache: CacheStatus) => ({ groups: answer(groups),
    diagnostics: { parts, candidates, selectedMs, selectedRestMs, selectedCpuMs, cpuMs: cpuMs(), rests,
      restMs: Math.round(restMs), cache, sql: { journal: Math.round(sql.journal), changes: Math.round(sql.changes),
        pending: Math.round(sql.pending), selected: Math.round(sql.selected), owner: Math.round(sql.owner),
        buckets: Math.round(sql.buckets), slowMs: Math.round(sql.slowMs), slowOp: sql.slowMs < 0.5 ? "none" : sql.slowOp } }, ms: Math.round(performance.now() - started) });
  const key = JSON.stringify([kind, from.toString(), to.toString(), utcOffsetMin.toString(), viewer?.workspace ?? null,
    viewer === null ? null : viewer.home !== false]);
  const journal = cache !== undefined && timeSql("journal", () => s.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_changes'").get()) !== undefined;
  if (kind === "history" && !journal) return null;
  let first = 0n, last = 0n;
  if (journal) {
    const bounds = timeSql("journal", () => s.db.prepare("SELECT (SELECT seq FROM usage_summary_changes ORDER BY seq LIMIT 1) AS first, " +
      "(SELECT seq FROM usage_summary_changes ORDER BY seq DESC LIMIT 1) AS last"));
    bounds.setReadBigInts(true);
    const row = timeSql("journal", () => bounds.get()) as { first: bigint | null; last: bigint | null };
    first = row.first ?? 0n;
    last = row.last ?? 0n;
  }
  const prior = journal ? cache!.get(s.db, key) : undefined;
  const usable = prior !== undefined && prior.seq <= last && (first === 0n ? prior.seq === last : prior.seq >= first - 1n);
  const cacheStatus: CacheStatus = !journal ? "disabled" : prior === undefined ? "miss" : usable ? "reused" : "expired";

  // A cache is updated only after the complete read succeeds. Unchanged block maps remain immutable and can be shared
  // with the preceding snapshot while new ones are built.
  let blocks: Map<string, Block> | null = journal ? new Map(usable ? prior.blocks : []) : null;
  let totals: Map<string, Total> = new Map(usable ? prior.totals : []);
  let copied = new Set<string>();
  let width = usable ? prior.width : 1n;
  let building = !usable;
  let cells = usable ? prior.cells : 0;
  let bytes = usable ? prior.bytes : 0;
  // The totals for a snapshot share rows with the previous cache until a changed block actually touches them.
  const writable = (key: string, total: Total): Total => {
    if (copied.has(key)) return total;
    const copy = { ...total, row: { ...total.row } };
    totals.set(key, copy);
    copied.add(key);
    return copy;
  };
  const addTotal = (group: string, row: Part, newBlockGroup: boolean) => {
    const key = totalKey(row.session, group);
    let total = totals.get(key);
    if (!total) {
      const size = 256 + 2 * (key.length + row.session.length + (row.day?.length ?? 0) + row.person.length
        + row.profile.length + row.runtime.length + row.model.length);
      total = { row: { ...row }, refs: 1, bytes: size };
      totals.set(key, total);
      copied.add(key);
      bytes += size;
      return;
    }
    total = writable(key, total);
    for (const name of names) total.row[name] += row[name];
    if (newBlockGroup) total.refs++;
  };
  const remove = (key: string, block: Block) => {
    cells -= block.groups.size;
    bytes -= block.bytes;
    blocks!.delete(key);
    for (const [group, row] of block.groups) {
      const id = totalKey(row.session, group);
      let total = totals.get(id)!;
      if (total.refs === 1) {
        totals.delete(id);
        copied.delete(id);
        bytes -= total.bytes;
      } else {
        total = writable(id, total);
        total.refs--;
        for (const name of names) total.row[name] -= row[name];
      }
    }
  };
  const put = (session: string, minute: bigint, row: Part) => {
    const block = blockOf(minute, utcOffsetMin, width);
    const key = blockKey(session, block);
    let held = blocks!.get(key);
    if (!held) {
      held = { session, minute: block, groups: new Map(), bytes: 288 + key.length * 2 };
      blocks!.set(key, held);
      bytes += held.bytes;
    }
    const group = groupKey(row);
    const newBlockGroup = add(held.groups, group, row);
    addTotal(group, row, newBlockGroup);
    if (newBlockGroup) {
      cells++;
      // Count the key, retained strings, bigint fields and object overhead conservatively. Long names cannot make
      // an otherwise small number of groups retain an unbounded share of a reader's 128 MB heap.
      const size = 416 + 2 * (group.length + row.session.length + (row.day?.length ?? 0) + row.person.length
        + row.profile.length + row.runtime.length + row.model.length);
      held.bytes += size;
      bytes += size;
    }
  };
  const putBucket = (row: Bucket) => {
    if (blocks === null) return;
    put(row.session, row.minute, row);
    while (blocks !== null && (cells > MAX_CELLS || bytes > MAX_BYTES)) {
      // A refresh has already chosen its dirty blocks at the old width. If it no longer fits, start a full read below
      // rather than mix widths inside that snapshot. Initial reads can coarsen without reading the same minute twice.
      const wider = !building ? null : width === 1n ? 5n : width === 5n ? 15n : width === 15n ? 60n : null;
      if (wider === null) { blocks = null; totals.clear(); copied.clear(); break; }
      const old: Map<string, Block> = blocks;
      width = wider;
      blocks = new Map();
      totals = new Map();
      copied = new Set();
      cells = 0;
      bytes = 0;
      for (const block of old.values()) for (const part of block.groups.values()) put(block.session, block.minute, part);
    }
  };
  let bucket: ReturnType<DatabaseSync["prepare"]> | undefined;
  const visible = viewer === null ? null : timeSql("owner", () => s.db.prepare(queries.owner));
  const readSession = async (session: string, low: bigint, high: bigint, groups?: Map<string, Part>) => {
    const found = visible === null ? undefined : timeSql("owner", () => visible.get(session)) as { ws: string | null } | undefined;
    const seen = viewer === null || (found !== undefined && (found.ws === viewer.workspace || (viewer.home !== false && found.ws === null)));
    if (++steps >= 64) await rest();
    if (!seen || low >= high) return true;
    if (bucket === undefined) { bucket = timeSql("buckets", () => s.db.prepare(queries.buckets)); bucket.setReadBigInts(true); }
    const args: (string | bigint)[] = [utcOffsetMin, session, low, high];
    if (viewer !== null) args.push("W" + viewer.workspace);
    for (const bucketRow of sqlRows("buckets", timeSql("buckets", () => bucket!.iterate(...args)) as Iterable<Bucket>)) {
      // History groups only by day, session, runtime and model. Do not retain a row for every person or thread.
      const row = kind === "history" ? { ...bucketRow, thread: 0n, person: "", profile: "", fast: 0n } : bucketRow;
      parts++;
      if (groups) add(groups, groupKey(row), row);
      putBucket(row);
      // A very large history can have far more details than its answer. Leave it to the existing SQL aggregate.
      if (kind === "history" && blocks === null) return false;
      if (++steps >= 64) await rest();
    }
    return true;
  };

  if (usable) {
    const scope = viewer === null ? "" : viewer.home === false ? " AND scope = ?3" : " AND scope IN (?3, 'H')";
    const changes = timeSql("changes", () => s.db.prepare("SELECT session, minute FROM usage_summary_changes WHERE seq > ?1 AND seq <= ?2" + scope));
    changes.setReadBigInts(true);
    const args: (string | bigint)[] = [prior.seq, last];
    if (viewer !== null) args.push("W" + viewer.workspace);
    const whole = new Set<string>();
    const dirty = new Map<string, { session: string; minute: bigint }>();
    const changedMinute = (session: string, minute: bigint, target = dirty) => {
      if (minute < start || minute >= end) return;
      const block = blockOf(minute, utcOffsetMin, width);
      target.set(blockKey(session, block), { session, minute: block });
    };
    for (const row of sqlRows("changes", timeSql("changes", () => changes.iterate(...args)) as Iterable<{ session: string; minute: bigint | null }>)) {
      if (row.minute === null) whole.add(row.session);
      else changedMinute(row.session, row.minute);
      if (++steps >= 128) await rest();
    }
    // Repeated writes to a pending bucket are coalesced until the totals worker accounts it. A pending bucket may
    // have changed since this snapshot, so refresh its block; accounting it records a change before it disappears.
    const pendingArgs = viewer === null ? [] : ["W" + viewer.workspace];
    if (timeSql("pending", () => s.db.prepare(queries.anyPending).get(...pendingArgs))) {
      // Usually only a few buckets are pending. If there are many, compare that index with the requested time
      // range and stop as soon as either is exhausted: a narrow request must not walk another year's pending work,
      // and a wide request must not walk every minute merely to find a handful of pending buckets.
      type Pending = { session: string; minute: bigint };
      const pending = timeSql("pending", () => s.db.prepare(queries.pending));
      pending.setReadBigInts(true);
      const pendingRows = (timeSql("pending", () => pending.iterate(...pendingArgs)) as IterableIterator<Pending>)[Symbol.iterator]();
      let rangeRows: IterableIterator<Pending & { pending: bigint }> | undefined;
      let pendingChanges = new Map<string, { session: string; minute: bigint }>();
      try {
        let complete = false;
        for (let n = 0; n < 64; n++) {
          const next = timeSql("pending", () => pendingRows.next());
          if (next.done) { complete = true; break; }
          candidates++;
          changedMinute(next.value.session, next.value.minute, pendingChanges);
          if (++steps >= 64) await rest();
        }
        if (!complete) {
          const range = timeSql("pending", () => s.db.prepare(queries.pendingRange));
          range.setReadBigInts(true);
          const rangeArgs: (string | bigint)[] = [start, end];
          if (viewer !== null) rangeArgs.push("W" + viewer.workspace);
          rangeRows = (timeSql("pending", () => range.iterate(...rangeArgs)) as IterableIterator<Pending & { pending: bigint }>)[Symbol.iterator]();
          const rangeChanges = new Map<string, { session: string; minute: bigint }>();
          for (;;) {
            const inRange = timeSql("pending", () => rangeRows!.next());
            if (inRange.done) { pendingChanges = rangeChanges; break; }
            candidates++;
            if (inRange.value.pending === 1n) changedMinute(inRange.value.session, inRange.value.minute, rangeChanges);
            if (++steps >= 64) await rest();
            const next = timeSql("pending", () => pendingRows.next());
            if (next.done) break;
            candidates++;
            changedMinute(next.value.session, next.value.minute, pendingChanges);
            if (++steps >= 64) await rest();
          }
        }
      } finally {
        if (pendingRows.return) timeSql("pending", () => pendingRows.return!());
        if (rangeRows?.return) timeSql("pending", () => rangeRows!.return!());
      }
      for (const [id, change] of pendingChanges) dirty.set(id, change);
    }
    const selectedMs = Math.round(performance.now() - started);
    selectedRestMs = Math.round(restMs);
    selectedCpuMs = cpuMs();
    if (whole.size) for (const [id, block] of blocks!) if (whole.has(block.session)) remove(id, block);
    for (const id of dirty.keys()) {
      const block = blocks!.get(id);
      if (block) remove(id, block);
    }
    for (const session of whole) {
      if (!(await readSession(session, start, end))) { cache!.drop(s.db, key); return null; }
      if (blocks === null) break;
    }
    // Adjacent changed blocks of the same session can share both the ownership check and one indexed range read.
    // A gap still stays unread, so a single changed minute does not pull in the rest of its hour.
    const changed = [...dirty.values()].filter((block) => !whole.has(block.session)).sort((a, b) =>
      a.session === b.session ? (a.minute < b.minute ? -1 : a.minute > b.minute ? 1 : 0) : a.session < b.session ? -1 : 1);
    for (let i = 0; blocks !== null && i < changed.length;) {
      const { session, minute } = changed[i++]!;
      let high = minute + width;
      while (i < changed.length && changed[i]!.session === session && changed[i]!.minute <= high) {
        high = changed[i++]!.minute + width;
      }
      if (!(await readSession(session, minute > start ? minute : start, high < end ? high : end))) {
        cache!.drop(s.db, key);
        return null;
      }
    }
    if (blocks !== null) {
      const groups = [...totals.values()].map((total) => total.row);
      // Formatting can fail on integer overflow. Do not publish an entry from a failed answer.
      const done = result(groups, selectedMs, "reused");
      cache!.put(s.db, key, { seq: last, blocks, totals, width, cells, bytes });
      return done;
    }
    cache!.drop(s.db, key);
    // The changed block made this answer too large to cache. Reread it using the bounded path below, retaining the
    // work already done in the diagnostics and total duration.
    blocks = new Map();
    totals = new Map();
    copied = new Set();
    width = 1n;
    cells = 0;
    bytes = 0;
    building = true;
  }

  const params: (string | bigint)[] = [start, end];
  if (viewer !== null) params.push("W" + viewer.workspace);
  const selected = timeSql("selected", () => s.db.prepare(queries.selected));
  const sessions = new Set<string>();
  for (const row of sqlRows("selected", timeSql("selected", () => selected.iterate(...params)) as Iterable<{ session: string }>)) {
    candidates++;
    sessions.add(row.session);
    if (++steps >= 64) await rest();
  }
  const selectedMs = Math.round(performance.now() - started);
  selectedRestMs = Math.round(restMs);
  selectedCpuMs = cpuMs();
  const groups: Part[] = [];
  for (const session of sessions) {
    const ofSession = new Map<string, Part>();
    if (!(await readSession(session, start, end, ofSession))) { cache!.drop(s.db, key); return null; }
    groups.push(...ofSession.values());
  }
  const done = result(groups, selectedMs, journal && blocks === null ? "oversized" : cacheStatus);
  if (blocks !== null) cache!.put(s.db, key, { seq: last, blocks, totals, width, cells, bytes });
  else cache?.drop(s.db, key);
  return done;
}

export type BatchedUsage = NonNullable<Awaited<ReturnType<typeof usageGroupsBatched>>>;
