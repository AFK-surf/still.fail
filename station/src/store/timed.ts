// The database as the station's main thread asks it, timed. The main thread answers every device and every agent: a
// query of seconds holds them all (on a machine short of memory, one that reads the pages of a table from the disk took
// half a minute, 2026-10-25). A statement run, all of its rows, or an exec, that took SLOW_MS or more is said in the log
// with its SQL and who asked it: never what it was given, which may be someone's words.
import { performance } from "node:perf_hooks";
import type { DatabaseSync, StatementSync } from "node:sqlite";
import { isMainThread } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { askedBy, noWaits, waited, type Waits } from "../ops/waits.ts";

/// A statement on the main thread taking this long is said.
export const SLOW_MS = 200;

/// Its SQL on one line, cut where it gets long.
export function shortSql(sql: string): string {
  const one = sql.replace(/\s+/g, " ").trim();
  return one.length > 300 ? `${one.slice(0, 300)}…` : one;
}

/// Says a statement that took `ms` (null rows: one that answers none, or one), and who asked it (`askedBy`).
export type Said = (sql: string, ms: number, rows: number | null, by: string) => void;

const inLog: Said = (sql, ms, rows, by) =>
  log.warn("store", "a slow query on the main thread", { ms: Math.round(ms), ...(rows !== null ? { rows } : {}), by, sql: shortSql(sql) });

/// What the main thread's statements took since `takeQueries` was last asked: many of a few milliseconds each, none
/// slow, hold it as long as one that is (a page read from the disk at each, on a machine short of memory).
let queried = noWaits();

export function takeQueries(): Waits {
  const taken = queried;
  queried = noWaits();
  return taken;
}

/// `db` with its statements' runs and execs timed (by `now`, ms), those of SLOW_MS or more told to `said`, and each put
/// down for `takeQueries`; as it is off the main thread (the readers': theirs hold no device), unless `said` is given.
export function timed(db: DatabaseSync, said: Said | null = isMainThread ? inLog : null, now: () => number = () => performance.now()): DatabaseSync {
  if (said === null) return db;
  const time = <T>(sql: () => string, run: () => T): T => {
    const at = now();
    const answer = run();
    const ms = now() - at;
    let by: string | null = null;
    const who = () => {
      if (by !== null) return by;
      const where: { stack?: string } = {};
      Error.captureStackTrace(where, time);
      return (by = askedBy(where.stack));
    };
    waited(queried, ms, who);
    if (ms >= SLOW_MS) said(sql(), ms, Array.isArray(answer) ? answer.length : null, who());
    return answer;
  };
  const statement = (s: StatementSync): StatementSync =>
    new Proxy(s, {
      get(target, key) {
        const v = Reflect.get(target, key, target);
        if (typeof v !== "function") return v;
        if (key === "all" || key === "get" || key === "run") return (...args: unknown[]) => time(() => target.sourceSQL, () => v.apply(target, args));
        return v.bind(target);
      },
    });
  return new Proxy(db, {
    get(target, key) {
      const v = Reflect.get(target, key, target);
      if (typeof v !== "function") return v;
      if (key === "prepare") return (...args: Parameters<DatabaseSync["prepare"]>) => statement(target.prepare(...args));
      if (key === "exec") return (sql: string) => time(() => sql, () => target.exec(sql));
      return v.bind(target);
    },
  });
}
