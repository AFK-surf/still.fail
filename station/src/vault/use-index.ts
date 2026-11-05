// The decided uses of secrets: maintained as requests change and filled from old requests in bounded transactions.
// Building an index directly over vault_requests would make the first station start read and sort its whole history.
import type { DatabaseSync } from "node:sqlite";
import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { backfillPendingPreparation, pendingPreparationComplete } from "./pending-index.ts";

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
INSERT OR IGNORE INTO vault_use_backfill_all (id, after_ws, done) VALUES (1, NULL, 0);
`;

/// Both statements read only their page in time order, then fetch its request bodies by primary key.
export const VAULT_USES = `SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_vault
  JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
  WHERE u.ws = ?1 AND u.vault = ?2 ORDER BY u.at DESC, u.id DESC LIMIT ?3`;
export const PLAIN_USES = `SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_owner
  JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
  WHERE u.ws = ?1 AND u.vault = ?2 AND u.owner = ?3 ORDER BY u.at DESC, u.id DESC LIMIT ?4`;
export const USE_BACKFILL_AFTER = "SELECT id FROM vault_requests WHERE ws = ? AND id > ? ORDER BY id LIMIT ?";

export type UseRead = { id: number; ws: string; vault: string; owner: string | null; limit: number };
export type PendingPrepare = { kind: "pending"; id: number; ws: string };
export type UseAnswer = { id: number; bodies?: string[]; ready?: true; error?: string };

export function initializeUseIndex(db: DatabaseSync): void {
  db.exec(SCHEMA);
}

export function readUses(db: DatabaseSync, q: UseRead): string[] {
  const rows = (q.owner === null
    ? db.prepare(VAULT_USES).all(q.ws, q.vault, q.limit)
    : db.prepare(PLAIN_USES).all(q.ws, q.vault, q.owner, q.limit)) as { body: string }[];
  return rows.map((r) => r.body);
}

/// Whether a workspace's earlier requests have been filled. Writes after that are kept by the triggers.
export function useIndexComplete(db: DatabaseSync, ws: string): boolean {
  return (db.prepare("SELECT done FROM vault_use_backfill WHERE ws = ?").get(ws) as { done: number } | undefined)?.done === 1;
}

/// One resumable transaction, considering at most `limit` old requests of this workspace, including requests that are
/// not uses. New and changed requests are already maintained by triggers, including changes behind the saved cursor.
export function backfillUseIndex(db: DatabaseSync, ws: string, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare("INSERT OR IGNORE INTO vault_use_backfill (ws, after_id, done) VALUES (?, NULL, 0)").run(ws);
    const state = db.prepare("SELECT after_id, done FROM vault_use_backfill WHERE ws = ?").get(ws) as { after_id: string | null; done: number };
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
  if (useIndexComplete(db, next.ws) || backfillUseIndex(db, next.ws)) {
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
  #worker: Worker | null = null;
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
    this.#path = db.location();
    if (this.#path !== null) {
      if (this.#previousGone === null) this.#start();
      else void this.#previousGone.then(() => { if (!this.#closed) this.#start(); }).catch((error) => {
        log.error("vault", "the use reader could not start", { error: (error as Error).message });
      });
    }
  }

  #start(): Worker {
    if (this.#worker !== null) return this.#worker;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./use-index-worker.ts" : "./vault/use-index-worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { path: this.#path, priority: this.#priority } });
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
      while (!useIndexComplete(this.#db, ws) && !backfillUseIndex(this.#db, ws)) await new Promise<void>((resolve) => setImmediate(resolve));
      return readUses(this.#db, q);
    }
    const answer = await this.#ask(q);
    if (answer.bodies === undefined) throw new Error("the vault use reader sent no page");
    return answer.bodies;
  }

  /// Prepare one workspace's pending lookup in bounded transactions on the same worker as use-history preparation.
  async preparePending(ws: string): Promise<void> {
    if (pendingPreparationComplete(this.#db, ws)) return;
    if (this.#path === null) {
      while (!pendingPreparationComplete(this.#db, ws) && !backfillPendingPreparation(this.#db, ws)) await new Promise<void>((resolve) => setImmediate(resolve));
      return;
    }
    const answer = await this.#ask({ kind: "pending", id: ++this.#next, ws });
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
