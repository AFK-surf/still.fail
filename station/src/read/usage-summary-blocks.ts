import type { DatabaseSync } from "node:sqlite";
import { Refused } from "../api/request.ts";
import type { InWorkspace } from "../store/rows.ts";
import { hasUsageSummaryBlocks, usageSummaryBlocksReady, USAGE_SUMMARY_PENDING } from "../store/usage-summary-blocks.ts";

export type SummaryPart = { day: string | null; session: string; thread: bigint; person: string; profile: string;
  runtime: string; model: string; fast: bigint; calls: bigint; input: bigint; cache_read: bigint;
  cache_write: bigint; cache_write_long: bigint; output: bigint };
type Block = Omit<SummaryPart, "day"> & { parts: bigint };
type Dirty = { session: string; minute: bigint; thread: bigint; person: string; profile: string; runtime: string; model: string; fast: bigint };
type Snapshot = Dirty & Block & { scope: string };
type Group = { row: SummaryPart; parts: bigint };
type Stage = "pending" | "selected" | "owner" | "buckets";
type Timed = <T>(stage: Stage, f: () => T) => T;
const values = ["calls", "input", "cache_read", "cache_write", "cache_write_long", "output"] as const;
const dimensions = "session, thread, person, profile, runtime, model, fast";
const amounts = values.join(", ");
const key = ["session", "minute", "thread", "person", "profile", "runtime", "model", "fast"] as const;
const keyArgs = (row: Dirty): (string | bigint)[] => key.map((name) => row[name]);
const keyId = (row: Dirty) => JSON.stringify(keyArgs(row).map((value) => typeof value === "bigint" ? value.toString() : value));
const max = 9223372036854775807n;
const floorDiv = (n: bigint, d: bigint) => n >= 0n ? n / d : -1n - ((-1n - n) / d);
const ceilMultiple = (n: bigint, d: bigint) => (floorDiv(n, d) + 1n) * d;

/// The same indexed queries are exposed to the query-plan tests.
export function usageSummaryBlockQueries(scoped: boolean, size: 1 | 15 | 60) {
  const source = size === 1 ? "usage_summary_blocks_shadow" : "usage_summary_blocks";
  const index = !scoped ? `${source}_time` : size === 1 ? `${source}_scope_time` : undefined;
  const period = size === 1 ? "minute" : "bucket";
  const scope = scoped ? "scope = ?3 AND " : "";
  const level = size === 1 ? "" : `level = ${size} AND `;
  return {
    selected: `SELECT ${dimensions}, ${size === 1 ? "1" : "parts"} AS parts, ${amounts}
      FROM ${source}${index === undefined ? "" : ` INDEXED BY ${index}`} WHERE ${scope}${level}${period} >= ?1 AND ${period} < ?2`,
    next: scoped
      ? "SELECT bucket FROM usage_summary_blocks WHERE scope = ?3 AND level = 60 AND bucket >= ?1 AND bucket < ?2 ORDER BY bucket LIMIT 1"
      : "SELECT bucket FROM usage_summary_blocks INDEXED BY usage_summary_blocks_time WHERE level = 60 AND bucket >= ?1 AND bucket < ?2 ORDER BY bucket LIMIT 1",
    last: scoped
      ? "SELECT bucket FROM usage_summary_blocks WHERE scope = ? AND level = 60 ORDER BY bucket DESC LIMIT 1"
      : "SELECT bucket FROM usage_summary_blocks INDEXED BY usage_summary_blocks_time WHERE level = 60 ORDER BY bucket DESC LIMIT 1",
  };
}

export function usageSummaryBlockPendingQuery(side: "time" | "old" | "new"): string {
  const predicate = side === "time" ? "minute >= ?1 AND minute < ?2" : `${side}_scope = ?3 AND minute >= ?1 AND minute < ?2`;
  return `SELECT ${key.join(", ")} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_${side} WHERE ${predicate} LIMIT 65`;
}

export function usageSummaryBlockOverlayQuery(current: boolean): string {
  const where = key.map((name) => `${name} = ?`).join(" AND ");
  const source = current ? "usage_compact" : "usage_summary_blocks_shadow";
  return `SELECT ${key.join(", ")}, scope, ${amounts}, 1 AS parts FROM ${source} WHERE ${where}${current ? " AND records > 0" : ""}`;
}

/// Read at most an hour's edge minutes plus the quarter/hour groups in each requested day. A small set of changed
/// buckets is overlaid; larger changes and initial conversion are prepared outside the requesting reader.
export async function usageGroupsFromBlocks(db: DatabaseSync, from: bigint, to: bigint, offset: bigint, viewer: InWorkspace | null,
  timed: Timed, tick: () => Promise<void>, prepared?: boolean): Promise<{ groups: SummaryPart[]; parts: number; candidates: number } | null> {
  if (offset < -1440n || offset > 1440n || from % 60_000n !== 0n || (to !== max && to % 60_000n !== 0n)) return null;
  if (from >= to) return { groups: [], parts: 0, candidates: 0 };
  const installed = timed("pending", () => hasUsageSummaryBlocks(db));
  if (!installed) {
    if (prepared !== undefined) throw new Refused(503, USAGE_SUMMARY_PENDING);
    return null;
  }
  const scopes = viewer === null ? [null] : viewer.home === false ? [`W${viewer.workspace}`] : [`W${viewer.workspace}`, "H"];
  if (!prepared && !scopes.every((scope) => timed("pending", () => usageSummaryBlocksReady(db, scope ?? undefined)))) {
    throw new Refused(503, USAGE_SUMMARY_PENDING);
  }
  const start = from / 60_000n;
  let end = to === max ? max : to / 60_000n;
  const changed = new Map<string, Dirty>();
  for (const scope of scopes) {
    for (const side of scope === null ? ["time"] as const : ["old", "new"] as const) {
      const stmt = timed("pending", () => db.prepare(usageSummaryBlockPendingQuery(side)));
      stmt.setReadBigInts(true);
      const pending = timed("pending", () => stmt.all(...(scope === null ? [start, end] : [start, end, scope]))) as Dirty[];
      for (const row of pending) changed.set(keyId(row), row);
      if (pending.length > 64 || changed.size > 64) throw new Refused(503, USAGE_SUMMARY_PENDING);
    }
  }
  if (start >= end) return { groups: [], parts: 0, candidates: 0 };
  if (end === max) {
    let last: bigint | null = null;
    for (const scope of scopes) {
      const sql = usageSummaryBlockQueries(scope !== null, 60).last;
      const stmt = timed("selected", () => db.prepare(sql));
      stmt.setReadBigInts(true);
      const row = timed("selected", () => scope === null ? stmt.get() : stmt.get(scope)) as { bucket: bigint } | undefined;
      if (row !== undefined && (last === null || row.bucket > last)) last = row.bucket;
    }
    // A newly written bucket may be newer than every accounted block.
    for (const row of changed.values()) {
      const bucket = floorDiv(row.minute, 60n);
      if (last === null || bucket > last) last = bucket;
    }
    if (last === null) return { groups: [], parts: 0, candidates: 0 };
    end = (last + 1n) * 60n;
    if (start >= end) return { groups: [], parts: 0, candidates: 0 };
  }
  // SQLite groups all timestamps outside its date format under NULL. Keep that rare case on the exact original path.
  if (start + offset < -1036120320n || end + offset > 4223371680n) return null;
  const selected = new Map<string, Group>();
  const visible = new Map<string, boolean>();
  let parts = 0, candidates = 0;
  const owner = viewer === null ? null : timed("owner", () => db.prepare("SELECT ws FROM usage_minute_scope WHERE session = ?"));
  const sees = (session: string) => {
    if (viewer === null) return true;
    let found = visible.get(session);
    if (found === undefined) {
      const row = timed("owner", () => owner!.get(session)) as { ws: string | null } | undefined;
      found = row !== undefined && (row.ws === viewer.workspace || (viewer.home !== false && row.ws === null));
      visible.set(session, found);
    }
    return found;
  };
  const statements = new Map<string, ReturnType<DatabaseSync["prepare"]>>();
  const statement = (scope: string | null, size: bigint) => {
    const id = `${scope === null ? "all" : "scope"}:${size}`;
    let found = statements.get(id);
    if (found !== undefined) return found;
    found = timed("buckets", () => db.prepare(usageSummaryBlockQueries(scope !== null, Number(size) as 1 | 15 | 60).selected));
    found.setReadBigInts(true);
    statements.set(id, found);
    return found;
  };
  const nextHour = new Map<string | null, ReturnType<DatabaseSync["prepare"]>>();
  const nextDayWithUsage = (fromMinute: bigint): bigint | null => {
    let next: bigint | null = null;
    for (const scope of scopes) {
      let stmt = nextHour.get(scope);
      if (stmt === undefined) {
        const sql = usageSummaryBlockQueries(scope !== null, 60).next;
        stmt = timed("selected", () => db.prepare(sql));
        stmt.setReadBigInts(true);
        nextHour.set(scope, stmt);
      }
      const first = floorDiv(fromMinute, 60n), after = floorDiv(end - 1n, 60n) + 1n;
      const row = timed("selected", () => stmt!.get(...(scope === null ? [first, after] : [first, after, scope]))) as { bucket: bigint } | undefined;
      if (row !== undefined) {
        const candidate = row.bucket * 60n < fromMinute ? fromMinute : row.bucket * 60n;
        if (next === null || candidate < next) next = candidate;
      }
    }
    for (const row of changed.values()) if (row.minute >= fromMinute && row.minute < end && (next === null || row.minute < next)) next = row.minute;
    return next;
  };
  const add = (day: string, row: Block, sign = 1n) => {
    const id = JSON.stringify([day, row.session, row.thread.toString(), row.person, row.profile, row.runtime, row.model, row.fast.toString()]);
    const held = selected.get(id);
    if (held === undefined) {
      const copy = { ...row, day };
      for (const name of values) copy[name] *= sign;
      selected.set(id, { row: copy, parts: sign * row.parts });
      return;
    }
    held.parts += sign * row.parts;
    for (const name of values) held.row[name] += sign * row[name];
  };
  const read = async (day: string, first: bigint, last: bigint, size: bigint) => {
    for (const scope of scopes) {
      const stmt = statement(scope, size);
      const args = scope === null ? [first / size, last / size] : [first / size, last / size, scope];
      const iterator = timed("buckets", () => stmt.iterate(...args))[Symbol.iterator]() as IterableIterator<Block>;
      let finished = false;
      try {
        for (;;) {
          const next = timed("buckets", () => iterator.next());
          if (next.done) { finished = true; break; }
          candidates++;
          if (sees(next.value.session)) { parts++; add(day, next.value); }
          await tick();
        }
      } finally { if (!finished && iterator.return) timed("buckets", () => iterator.return!()); }
    }
  };
  for (let at = start; at < end;) {
    const next = nextDayWithUsage(at);
    if (next === null) break;
    at = next;
    const localDay = floorDiv(at + offset, 1440n) * 1440n;
    const dayEnd = localDay + 1440n - offset < end ? localDay + 1440n - offset : end;
    const day = new Date(Number(localDay * 60_000n)).toISOString().slice(0, 10);
    while (at < dayEnd) {
      let size = 1n, stop = dayEnd;
      if (at % 60n === 0n && dayEnd - at >= 60n) { size = 60n; stop = at + ((dayEnd - at) / 60n) * 60n; }
      else if (at % 15n === 0n && dayEnd - at >= 15n) {
        size = 15n;
        const next = ceilMultiple(at, 60n);
        stop = next < dayEnd ? next : at + ((dayEnd - at) / 15n) * 15n;
      } else {
        const next = ceilMultiple(at, 15n);
        if (next < stop) stop = next;
      }
      await read(day, at, stop, size);
      at = stop;
    }
  }
  const old = timed("pending", () => db.prepare(usageSummaryBlockOverlayQuery(false)));
  const now = timed("pending", () => db.prepare(usageSummaryBlockOverlayQuery(true)));
  old.setReadBigInts(true);
  now.setReadBigInts(true);
  const allowed = (scope: string) => viewer === null || scopes.some((candidate) => candidate === scope);
  for (const change of changed.values()) {
    if (change.minute < start || change.minute >= end || !sees(change.session)) continue;
    const args = keyArgs(change);
    const before = timed("pending", () => old.get(...args)) as Snapshot | undefined;
    const after = timed("pending", () => now.get(...args)) as Snapshot | undefined;
    const day = new Date(Number(floorDiv(change.minute + offset, 1440n) * 86_400_000n)).toISOString().slice(0, 10);
    if (before !== undefined && allowed(before.scope)) { add(day, before, -1n); parts++; }
    if (after !== undefined && allowed(after.scope)) { add(day, after); parts++; }
    candidates++;
    await tick();
  }
  return { groups: [...selected.values()].filter((g) => g.parts > 0n).map((g) => g.row), parts, candidates };
}
