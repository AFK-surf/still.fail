// The decided uses of secrets: maintained as requests change and filled from old requests in bounded transactions.
// Building an index directly over vault_requests would make the first station start read and sort its whole history.
import type { DatabaseSync } from "node:sqlite";
import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { backfillPendingPreparation, pendingPreparationComplete } from "./pending-index.ts";
import { initializeReboxIndex } from "./rebox-index.ts";
import { installSchema } from "./schema-install.ts";
import { mbReaderBinary } from "../read/mb-reader.ts";
import { MbUseReader } from "./use-reader-mb.ts";

// JSON paths use the first duplicate key and truncate keys at NUL; JavaScript does neither. A lone UTF-16
// surrogate also cannot round-trip through SQLite TEXT. Only these exceptional bodies need JavaScript indexing.
const ambiguousUse = (body: string) => `CASE WHEN json_valid(${body}) THEN
  (instr(${body}, '\\ud') > 0 OR instr(${body}, '\\uD') > 0 OR
    (instr(${body}, '\\u0000') > 0 AND EXISTS (SELECT 1 FROM json_each(${body}) WHERE instr(key, char(0)) > 0)) OR
    EXISTS (SELECT 1 FROM json_each(${body}) WHERE key IN ('vault','owner','save','at') GROUP BY key HAVING count(*) > 1))
  ELSE 0 END`;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_use_lookup (
  ws TEXT NOT NULL, id TEXT NOT NULL, vault TEXT, owner TEXT, at INTEGER,
  PRIMARY KEY (ws, id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS vault_use_lookup_vault ON vault_use_lookup (ws, vault, at DESC, id DESC);
CREATE INDEX IF NOT EXISTS vault_use_lookup_owner ON vault_use_lookup (ws, vault, owner, at DESC, id DESC);
CREATE TABLE IF NOT EXISTS vault_use_backfill (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS vault_use_backfill_all (
  id INTEGER PRIMARY KEY CHECK (id = 1), after_ws TEXT, done INTEGER NOT NULL
);
-- Exceptional requests are indexed from JSON.parse by the reader, in bounded batches. BLOB keys preserve the exact
-- JavaScript UTF-16 code units, including isolated surrogates. Old Station writers only have to mark a row dirty.
CREATE TABLE IF NOT EXISTS vault_use_ambiguous_v2 (
  ws TEXT NOT NULL, id TEXT NOT NULL, dirty INTEGER NOT NULL, is_use INTEGER NOT NULL,
  vault BLOB, owner BLOB, at INTEGER, PRIMARY KEY (ws, id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS vault_use_ambiguous_dirty_v2 ON vault_use_ambiguous_v2 (ws, dirty, id);
CREATE INDEX IF NOT EXISTS vault_use_ambiguous_vault_v2 ON vault_use_ambiguous_v2 (ws, vault, at DESC, id DESC)
  WHERE dirty = 0 AND is_use = 1;
CREATE INDEX IF NOT EXISTS vault_use_ambiguous_owner_v2 ON vault_use_ambiguous_v2 (ws, vault, owner, at DESC, id DESC)
  WHERE dirty = 0 AND is_use = 1;
CREATE TABLE IF NOT EXISTS vault_use_ambiguous_audit_v2 (
  ws TEXT PRIMARY KEY, after_id TEXT, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TRIGGER IF NOT EXISTS vault_use_lookup_add AFTER INSERT ON vault_requests BEGIN
  DELETE FROM vault_use_lookup WHERE ws = NEW.ws AND id = NEW.id;
  INSERT OR REPLACE INTO vault_use_lookup
    SELECT NEW.ws, NEW.id, json_extract(NEW.body, '$.vault'), json_extract(NEW.body, '$.owner'), json_extract(NEW.body, '$.at')
    WHERE NEW.status IN ('granted', 'denied') AND json_extract(NEW.body, '$.save') IS NULL;
END;
CREATE TRIGGER IF NOT EXISTS vault_use_lookup_change AFTER UPDATE ON vault_requests BEGIN
  DELETE FROM vault_use_lookup WHERE ws = OLD.ws AND id = OLD.id;
  INSERT OR REPLACE INTO vault_use_lookup
    SELECT NEW.ws, NEW.id, json_extract(NEW.body, '$.vault'), json_extract(NEW.body, '$.owner'), json_extract(NEW.body, '$.at')
    WHERE NEW.status IN ('granted', 'denied') AND json_extract(NEW.body, '$.save') IS NULL;
END;
CREATE TRIGGER IF NOT EXISTS vault_use_lookup_drop AFTER DELETE ON vault_requests BEGIN
  DELETE FROM vault_use_lookup WHERE ws = OLD.ws AND id = OLD.id;
END;
CREATE TRIGGER IF NOT EXISTS vault_use_ambiguous_add_v2 AFTER INSERT ON vault_requests BEGIN
  DELETE FROM vault_use_ambiguous_v2 WHERE ws = NEW.ws AND id = NEW.id;
  INSERT OR IGNORE INTO vault_use_ambiguous_v2 (ws,id,dirty,is_use)
    SELECT NEW.ws, NEW.id, 1, 0 WHERE NEW.status IN ('granted','denied') AND (${ambiguousUse("NEW.body")}) = 1;
END;
CREATE TRIGGER IF NOT EXISTS vault_use_ambiguous_change_v2 AFTER UPDATE ON vault_requests
  WHEN OLD.ws IS NOT NEW.ws OR OLD.id IS NOT NEW.id OR OLD.status IS NOT NEW.status OR OLD.body IS NOT NEW.body BEGIN
  DELETE FROM vault_use_ambiguous_v2 WHERE ws = OLD.ws AND id = OLD.id;
  DELETE FROM vault_use_ambiguous_v2 WHERE ws = NEW.ws AND id = NEW.id;
  INSERT OR IGNORE INTO vault_use_ambiguous_v2 (ws,id,dirty,is_use)
    SELECT NEW.ws, NEW.id, 1, 0 WHERE NEW.status IN ('granted','denied') AND (${ambiguousUse("NEW.body")}) = 1;
END;
CREATE TRIGGER IF NOT EXISTS vault_use_ambiguous_drop_v2 AFTER DELETE ON vault_requests BEGIN
  DELETE FROM vault_use_ambiguous_v2 WHERE ws = OLD.ws AND id = OLD.id;
END;
INSERT OR IGNORE INTO vault_use_backfill_all (id, after_ws, done) VALUES (1, NULL, 0);
`;

/// Both statements read only their page in time order, then fetch its request bodies by primary key.
export const VAULT_USES = `SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_vault
  JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
  WHERE u.ws = ?1 AND u.vault = ?2 ORDER BY u.at DESC, u.id DESC LIMIT ?3`;
export const PLAIN_USES = `SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_owner
  JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
  WHERE u.ws = ?1 AND u.vault = ?2 AND u.owner = ?3 ORDER BY u.at DESC, u.id DESC LIMIT ?4`;
// Merge each indexed page in SQLite so the limit and tie order apply across normal and corrected requests.
export const VAULT_USES_AMBIGUOUS = `SELECT r.body AS body, u.at AS at, u.id AS id FROM vault_use_lookup u INDEXED BY vault_use_lookup_vault
    JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
    WHERE ?4 AND u.ws = ?1 AND u.vault = ?2 AND NOT EXISTS
      (SELECT 1 FROM vault_use_ambiguous_v2 a WHERE a.ws = u.ws AND a.id = u.id)
  UNION ALL
  SELECT r.body, a.at, a.id FROM vault_use_ambiguous_v2 a INDEXED BY vault_use_ambiguous_vault_v2
    JOIN vault_requests r ON r.ws = a.ws AND r.id = a.id
    WHERE a.ws = ?1 AND a.vault = ?3 AND a.dirty = 0 AND a.is_use = 1
ORDER BY at DESC, id DESC LIMIT ?5`;
export const PLAIN_USES_AMBIGUOUS = `SELECT r.body AS body, u.at AS at, u.id AS id FROM vault_use_lookup u INDEXED BY vault_use_lookup_owner
    JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
    WHERE ?6 AND u.ws = ?1 AND u.vault = ?2 AND u.owner = ?3 AND NOT EXISTS
      (SELECT 1 FROM vault_use_ambiguous_v2 a WHERE a.ws = u.ws AND a.id = u.id)
  UNION ALL
  SELECT r.body, a.at, a.id FROM vault_use_ambiguous_v2 a INDEXED BY vault_use_ambiguous_owner_v2
    JOIN vault_requests r ON r.ws = a.ws AND r.id = a.id
    WHERE a.ws = ?1 AND a.vault = ?4 AND a.owner = ?5 AND a.dirty = 0 AND a.is_use = 1
ORDER BY at DESC, id DESC LIMIT ?7`;
export const USE_BACKFILL_AFTER = "SELECT id FROM vault_requests WHERE ws = ? AND id > ? ORDER BY id LIMIT ?";

export type UseRead = { id: number; ws: string; vault: string; owner: string | null; limit: number };
export type PendingPrepare = { kind: "pending"; id: number; ws: string; members: boolean; audit: boolean };
export type UseAnswer = { id: number; bodies?: string[]; ready?: true; error?: string };

export function initializeUseIndex(db: DatabaseSync): void {
  installSchema(db, "vault_use_schema", SCHEMA, ["SELECT 1 FROM vault_use_backfill_all WHERE id = 1"]);
}

export function readUses(db: DatabaseSync, q: UseRead, knownAmbiguous?: boolean): string[] {
  const ambiguous = knownAmbiguous ?? (db.prepare("SELECT 1 FROM vault_use_ambiguous_v2 WHERE ws = ? LIMIT 1").get(q.ws) !== undefined);
  const normalIdentity = q.vault.isWellFormed() && (q.owner === null || q.owner.isWellFormed());
  if (!ambiguous && !normalIdentity) return [];
  let rows: { body: string }[];
  if (!ambiguous) {
    rows = (q.owner === null ? db.prepare(VAULT_USES).all(q.ws, q.vault, q.limit)
      : db.prepare(PLAIN_USES).all(q.ws, q.vault, q.owner, q.limit)) as { body: string }[];
  } else {
    const page = db.prepare(q.owner === null ? VAULT_USES_AMBIGUOUS : PLAIN_USES_AMBIGUOUS);
    // The ordered merge returns its sort keys as well as the body. A legacy timestamp may exceed JavaScript's safe
    // integer range; keep it as a bigint even though callers only consume the body.
    page.setReadBigInts(true);
    rows = (q.owner === null ? page.all(q.ws, q.vault, Buffer.from(q.vault, "utf16le"), normalIdentity ? 1 : 0, q.limit)
      : page.all(q.ws, q.vault, q.owner, Buffer.from(q.vault, "utf16le"), Buffer.from(q.owner, "utf16le"),
        normalIdentity ? 1 : 0, q.limit)) as { body: string }[];
  }
  return rows.map((r) => r.body);
}

/// Readiness, dirty markers and the page share one snapshot with other connections' writes.
export function tryReadUses(db: DatabaseSync, q: UseRead): string[] | null {
  db.exec("SAVEPOINT vault_use_page");
  try {
    const state = usePreparationState(db, q.ws);
    if (!state || state.done !== 1 || state.audited !== 1 || state.dirty !== 0) return null;
    return readUses(db, q, state.ambiguous !== 0);
  } finally { db.exec("RELEASE vault_use_page"); }
}

/// Whether a workspace's earlier requests have been filled. Writes after that are kept by the triggers.
export function useIndexComplete(db: DatabaseSync, ws: string): boolean {
  return (db.prepare("SELECT done FROM vault_use_backfill WHERE ws = ?").get(ws) as { done: number } | undefined)?.done === 1;
}

function useAuditComplete(db: DatabaseSync, ws: string): boolean {
  return (db.prepare("SELECT done FROM vault_use_ambiguous_audit_v2 WHERE ws = ?").get(ws) as { done: number } | undefined)?.done === 1;
}

function usePreparationState(db: DatabaseSync, ws: string): { done: number; audited: number | null; dirty: number; ambiguous: number } | undefined {
  return db.prepare(`SELECT b.done, a.done AS audited,
      EXISTS (SELECT 1 FROM vault_use_ambiguous_v2 WHERE ws = b.ws AND dirty = 1 LIMIT 1) AS dirty,
      EXISTS (SELECT 1 FROM vault_use_ambiguous_v2 WHERE ws = b.ws LIMIT 1) AS ambiguous
    FROM vault_use_backfill b LEFT JOIN vault_use_ambiguous_audit_v2 a ON a.ws = b.ws WHERE b.ws = ?`).get(ws) as
    { done: number; audited: number | null; dirty: number; ambiguous: number } | undefined;
}

function usePreparationReady(db: DatabaseSync, ws: string): boolean {
  const state = usePreparationState(db, ws);
  return state?.done === 1 && state.audited === 1 && state.dirty === 0;
}

function auditUseRows(db: DatabaseSync, ws: string, rows: { id: string }[]): void {
  const mark = db.prepare(`INSERT OR IGNORE INTO vault_use_ambiguous_v2 (ws,id,dirty,is_use)
    SELECT ws, id, 1, 0 FROM vault_requests WHERE ws = ? AND id = ? AND status IN ('granted','denied')
      AND (${ambiguousUse("body")}) = 1`);
  for (const row of rows) mark.run(ws, row.id);
}

/// Upgrade a completed old index without locking the whole request history at once.
export function backfillUseAudit(db: DatabaseSync, ws: string, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare("INSERT OR IGNORE INTO vault_use_ambiguous_audit_v2 (ws,after_id,done) VALUES (?,NULL,0)").run(ws);
    const audit = db.prepare("SELECT after_id,done FROM vault_use_ambiguous_audit_v2 WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    if (audit.done) { db.exec("COMMIT"); return true; }
    const rows = (audit.after_id === null
      ? db.prepare("SELECT id FROM vault_requests WHERE ws = ? ORDER BY id LIMIT ?").all(ws, limit)
      : db.prepare(USE_BACKFILL_AFTER).all(ws, audit.after_id, limit)) as { id: string }[];
    auditUseRows(db, ws, rows);
    const done = rows.length < limit;
    db.prepare("UPDATE vault_use_ambiguous_audit_v2 SET after_id = ?, done = ? WHERE ws = ?")
      .run(rows.at(-1)?.id ?? audit.after_id, done ? 1 : 0, ws);
    db.exec("COMMIT");
    return done;
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

// SQLite's json_extract represents JSON arrays and objects as text, booleans as integers and missing values as NULL.
function useTime(value: unknown): string | number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "boolean") return value ? 1 : 0;
  if (typeof value === "number" || typeof value === "string") return value;
  return JSON.stringify(value) ?? null;
}

/// Resolve at most `limit` dirty exceptional bodies. Trigger and repair writes serialize on the same database lock.
export function repairAmbiguousUses(db: DatabaseSync, ws: string, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    const rows = db.prepare(`SELECT a.id, r.body, r.status FROM vault_use_ambiguous_v2 a
      LEFT JOIN vault_requests r ON r.ws = a.ws AND r.id = a.id
      WHERE a.ws = ? AND a.dirty = 1 ORDER BY a.id LIMIT ?`).all(ws, limit) as { id: string; body: string | null; status: string | null }[];
    const drop = db.prepare("DELETE FROM vault_use_ambiguous_v2 WHERE ws = ? AND id = ?");
    const set = db.prepare("UPDATE vault_use_ambiguous_v2 SET dirty = 0, is_use = ?, vault = ?, owner = ?, at = ? WHERE ws = ? AND id = ?");
    for (const row of rows) {
      if (row.body === null || (row.status !== "granted" && row.status !== "denied")) { drop.run(ws, row.id); continue; }
      const request = JSON.parse(row.body) as { vault?: unknown; owner?: unknown; save?: unknown; at?: unknown } | null;
      const vault = request && typeof request.vault === "string" ? Buffer.from(request.vault, "utf16le") : null;
      const owner = request && typeof request.owner === "string" ? Buffer.from(request.owner, "utf16le") : null;
      set.run(vault !== null && request?.save == null ? 1 : 0, vault, owner, useTime(request?.at), ws, row.id);
    }
    db.exec("COMMIT");
    return rows.length < limit;
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// One bounded step toward a complete use page; a changed anomalous request is repaired before the next page.
export function backfillUsePreparation(db: DatabaseSync, ws: string): boolean {
  if (!useIndexComplete(db, ws)) return backfillUseIndex(db, ws) && usePreparationReady(db, ws);
  if (!useAuditComplete(db, ws)) return backfillUseAudit(db, ws) && usePreparationReady(db, ws);
  return repairAmbiguousUses(db, ws) && usePreparationReady(db, ws);
}

/// One resumable transaction, considering at most `limit` old requests of this workspace, including requests that are
/// not uses. New and changed requests are already maintained by triggers, including changes behind the saved cursor.
export function backfillUseIndex(db: DatabaseSync, ws: string, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare("INSERT OR IGNORE INTO vault_use_backfill (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    db.prepare("INSERT OR IGNORE INTO vault_use_ambiguous_audit_v2 (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    const state = db.prepare("SELECT after_id, done FROM vault_use_backfill WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    const audit = db.prepare("SELECT after_id, done FROM vault_use_ambiguous_audit_v2 WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
    if (state.done) {
      db.exec("COMMIT");
      return true;
    }
    const rows = (state.after_id === null
      ? db.prepare("SELECT id FROM vault_requests WHERE ws = ? ORDER BY id LIMIT ?").all(ws, limit)
      : db.prepare(USE_BACKFILL_AFTER).all(ws, state.after_id, limit)) as { id: string }[];
    const add = db.prepare(`INSERT OR IGNORE INTO vault_use_lookup
      SELECT ws, id, json_extract(body, '$.vault'), json_extract(body, '$.owner'), json_extract(body, '$.at') FROM vault_requests
      WHERE ws = ? AND id = ? AND status IN ('granted', 'denied') AND json_extract(body, '$.save') IS NULL`);
    for (const row of rows) add.run(ws, row.id);
    const last = rows.at(-1);
    const done = rows.length < limit;
    if (!audit.done && audit.after_id === state.after_id) {
      auditUseRows(db, ws, rows);
      db.prepare("UPDATE vault_use_ambiguous_audit_v2 SET after_id = ?, done = ? WHERE ws = ?")
        .run(last?.id ?? audit.after_id, done ? 1 : 0, ws);
    }
    db.prepare("UPDATE vault_use_backfill SET after_id = ?, done = ? WHERE ws = ?")
      .run(last?.id ?? state.after_id, done ? 1 : 0, ws);
    db.exec("COMMIT");
    return done;
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// In the background, discover one workspace at a time through the requests' primary key and fill one batch. Reads
/// can preempt this work with their own workspace; the saved per-workspace cursor also lets another process resume it.
export function backfillNextWorkspace(db: DatabaseSync): boolean {
  const state = db.prepare("SELECT after_ws, done FROM vault_use_backfill_all WHERE id = 1").get() as { after_ws: string | null; done: number };
  if (state.done) return true;
  const next = (state.after_ws === null
    ? db.prepare("SELECT ws FROM vault_requests ORDER BY ws LIMIT 1").get()
    : db.prepare("SELECT ws FROM vault_requests WHERE ws > ? ORDER BY ws LIMIT 1").get(state.after_ws)) as { ws: string } | undefined;
  if (!next) {
    db.prepare("UPDATE vault_use_backfill_all SET done = 1 WHERE id = 1 AND after_ws IS ?").run(state.after_ws);
    return (db.prepare("SELECT done FROM vault_use_backfill_all WHERE id = 1").get() as { done: number }).done === 1;
  }
  if (usePreparationReady(db, next.ws) || backfillUsePreparation(db, next.ws)) {
    db.prepare("UPDATE vault_use_backfill_all SET after_ws = ? WHERE id = 1 AND after_ws IS ? AND done = 0").run(next.ws, state.after_ws);
  }
  return false;
}

/// A separate connection and worker keep both the backfill and reads away from the station's request thread. In-memory
/// stores (tests) use the same bounded algorithm on their own connection; they cannot be opened by another worker.
export class UseIndex {
  readonly #db: DatabaseSync;
  readonly #path: string | null;
  readonly #previousGone: Promise<void> | null;
  readonly #priority: SharedArrayBuffer | undefined;
  #worker: Worker | MbUseReader | null = null;
  #closed = false;
  #stopped!: () => void;
  readonly #whenStopped = new Promise<void>((resolve) => { this.#stopped = resolve; });
  #next = 0;
  #waiting = new Map<number, { resolve: (answer: UseAnswer) => void; reject: (error: Error) => void }>();

  constructor(db: DatabaseSync, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}) {
    this.#db = db;
    this.#previousGone = options.previousGone ?? null;
    this.#priority = options.priority;
    initializeUseIndex(db);
    initializeReboxIndex(db);
    this.#path = db.location();
    if (this.#path !== null) {
      if (this.#previousGone === null) this.#start();
      else void this.#previousGone.then(() => { if (!this.#closed) this.#start(); }).catch((error) => {
        log.error("vault", "the use reader could not start", { error: (error as Error).message });
      });
    }
  }

  #start(): Worker | MbUseReader {
    if (this.#worker !== null) return this.#worker;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./use-index-worker.ts" : "./vault/use-index-worker.js", import.meta.url);
    // (by the MoonBit program, station/mb's src/vaultuses, where it is there; else by the worker)
    const mb = mbReaderBinary();
    const worker = mb !== null ? new MbUseReader(mb, this.#path!, this.#priority)
      : new Worker(file, { workerData: { path: this.#path, priority: this.#priority } });
    const owner = worker.threadId;
    worker.once("exit", () => releaseStoppedBackfill(this.#priority, owner));
    this.#worker = worker;
    worker.unref();
    worker.on("message", (answer: UseAnswer | { foreground: true }) => {
      if ("foreground" in answer) return;
      const waiting = this.#waiting.get(answer.id);
      if (!waiting) return;
      this.#waiting.delete(answer.id);
      if (answer.error !== undefined) waiting.reject(new Error(answer.error));
      else if (answer.bodies !== undefined || answer.ready === true) waiting.resolve(answer);
      else waiting.reject(new Error("the vault use reader sent no result"));
    });
    let failure: Error | null = null;
    worker.on("error", (error) => {
      failure = error;
      log.error("vault", "the use reader stopped", { error: error.message });
    });
    worker.on("exit", (code) => {
      if (this.#worker === worker) this.#worker = null;
      for (const waiting of this.#waiting.values()) waiting.reject(failure ?? new Error(`the vault use reader stopped (exit ${code})`));
      this.#waiting.clear();
    });
    return worker;
  }

  async read(ws: string, vault: string, owner: string | null, limit: number): Promise<string[]> {
    const q = { id: ++this.#next, ws, vault, owner, limit };
    if (this.#path === null) {
      for (;;) {
        if (this.#closed) throw new Error("station stopping");
        const bodies = tryReadUses(this.#db, q);
        if (bodies !== null) return bodies;
        backfillUsePreparation(this.#db, ws);
        await new Promise<void>((resolve) => setImmediate(resolve));
      }
    }
    const answer = await this.#ask(q);
    if (answer.bodies === undefined) throw new Error("the vault use reader sent no page");
    return answer.bodies;
  }

  /// Prepare one workspace's pending lookup in bounded transactions on the same worker as use-history preparation.
  async preparePending(ws: string, members: boolean, audit = false): Promise<void> {
    if (this.#closed) throw new Error("station stopping");
    if (pendingPreparationComplete(this.#db, ws, members, audit)) return;
    if (this.#path === null) {
      for (;;) {
        if (this.#closed) throw new Error("station stopping");
        if (pendingPreparationComplete(this.#db, ws, members, audit) || backfillPendingPreparation(this.#db, ws, members, audit)) return;
        await new Promise<void>((resolve) => setImmediate(resolve));
      }
    }
    const answer = await this.#ask({ kind: "pending", id: ++this.#next, ws, members, audit });
    if (answer.ready !== true) throw new Error("the vault reader did not prepare pending requests");
  }

  async #ask(q: UseRead | PendingPrepare): Promise<UseAnswer> {
    if (this.#previousGone !== null) await Promise.race([this.#previousGone, this.#whenStopped]);
    if (this.#closed) throw new Error("station stopping");
    return new Promise((resolve, reject) => {
      try {
        const worker = this.#start();
        this.#waiting.set(q.id, { resolve, reject });
        worker.postMessage(q);
      } catch (e) {
        this.#waiting.delete(q.id);
        reject(e);
      }
    });
  }

  async close(): Promise<void> {
    this.#closed = true;
    this.#stopped();
    if (this.#worker !== null) await this.#worker.terminate();
  }
}
