// The database as the station's main thread asks it, timed. The main thread answers every device and every agent: a
// query of seconds holds them all (on a machine short of memory, one that reads the pages of a table from the disk took
// half a minute, 2026-10-25). A statement run, all of its rows, or an exec, that took SLOW_MS or more is said in the log
// with its SQL alone: never what it was given, which may be someone's words.
import { performance } from "node:perf_hooks";
import type { DatabaseSync, StatementSync } from "node:sqlite";
import { isMainThread } from "node:worker_threads";
import { log } from "../ops/log.ts";

/// A statement on the main thread taking this long is said.
export const SLOW_MS = 200;

/// Its SQL on one line, cut where it gets long.
export function shortSql(sql: string): string {
  const one = sql.replace(/\s+/g, " ").trim();
  return one.length > 300 ? `${one.slice(0, 300)}…` : one;
}

/// Says a statement that took `ms` (null rows: one that answers none, or one).
export type Said = (sql: string, ms: number, rows: number | null) => void;

const inLog: Said = (sql, ms, rows) => log.warn("store", "a slow query on the main thread", { ms: Math.round(ms), ...(rows !== null ? { rows } : {}), sql: shortSql(sql) });

/// `db` with its statements' runs and execs timed (by `now`, ms), those of SLOW_MS or more told to `said`; as it is off
/// the main thread (the readers': theirs hold no device), unless `said` is given.
export function timed(db: DatabaseSync, said: Said | null = isMainThread ? inLog : null, now: () => number = () => performance.now()): DatabaseSync {
  if (said === null) return db;
  const time = <T>(sql: () => string, run: () => T): T => {
    const at = now();
    const answer = run();
    const ms = now() - at;
    if (ms >= SLOW_MS) said(sql(), ms, Array.isArray(answer) ? answer.length : null);
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
