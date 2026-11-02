// The decided uses of secrets: maintained as requests change and filled from old requests in bounded transactions.
// Building an index directly over vault_requests would make the first station start read and sort its whole history.
import type { DatabaseSync } from "node:sqlite";
import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_use_lookup (
  ws TEXT NOT NULL, id TEXT NOT NULL, vault TEXT, owner TEXT, at INTEGER,
  PRIMARY KEY (ws, id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS vault_use_lookup_vault ON vault_use_lookup (ws, vault, at DESC, id DESC);
CREATE INDEX IF NOT EXISTS vault_use_lookup_owner ON vault_use_lookup (ws, vault, owner, at DESC, id DESC);
CREATE TABLE IF NOT EXISTS vault_use_backfill (
  id INTEGER PRIMARY KEY CHECK (id = 1), after_ws TEXT, after_id TEXT, done INTEGER NOT NULL
);
CREATE TRIGGER IF NOT EXISTS vault_use_lookup_add AFTER INSERT ON vault_requests BEGIN
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
-- The triggers are in place before this test: a request arriving after it is indexed by its own write.
INSERT OR IGNORE INTO vault_use_backfill (id, after_ws, after_id, done)
  SELECT 1, NULL, NULL, NOT EXISTS (SELECT 1 FROM vault_requests LIMIT 1);
`;

/// Both statements read only their page in time order, then fetch its request bodies by primary key.
export const VAULT_USES = `SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_vault
  JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
  WHERE u.ws = ?1 AND u.vault = ?2 ORDER BY u.at DESC, u.id DESC LIMIT ?3`;
export const PLAIN_USES = `SELECT r.body FROM vault_use_lookup u INDEXED BY vault_use_lookup_owner
  JOIN vault_requests r ON r.ws = u.ws AND r.id = u.id
  WHERE u.ws = ?1 AND u.vault = ?2 AND u.owner = ?3 ORDER BY u.at DESC, u.id DESC LIMIT ?4`;
export const USE_BACKFILL_AFTER = "SELECT ws, id FROM vault_requests WHERE (ws, id) > (?, ?) ORDER BY ws, id LIMIT ?";

export type UseRead = { id: number; ws: string; vault: string; owner: string | null; limit: number };
export type UseAnswer = { id: number; bodies?: string[]; error?: string };

export function initializeUseIndex(db: DatabaseSync): void {
  db.exec(SCHEMA);
}

export function readUses(db: DatabaseSync, q: UseRead): string[] {
  const rows = (q.owner === null
    ? db.prepare(VAULT_USES).all(q.ws, q.vault, q.limit)
    : db.prepare(PLAIN_USES).all(q.ws, q.vault, q.owner, q.limit)) as { body: string }[];
  return rows.map((r) => r.body);
}

/// One resumable transaction, considering at most `limit` old requests, including requests that are not uses.
/// New and changed requests are already maintained by triggers, including changes behind the saved cursor.
export function backfillUseIndex(db: DatabaseSync, limit = 32): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    const state = db.prepare("SELECT after_ws, after_id, done FROM vault_use_backfill WHERE id = 1").get() as { after_ws: string | null; after_id: string | null; done: number };
    if (state.done) {
      db.exec("COMMIT");
      return true;
    }
    const rows = (state.after_ws === null
      ? db.prepare("SELECT ws, id FROM vault_requests ORDER BY ws, id LIMIT ?").all(limit)
      : db.prepare(USE_BACKFILL_AFTER).all(state.after_ws, state.after_id, limit)) as { ws: string; id: string }[];
    const add = db.prepare(`INSERT OR IGNORE INTO vault_use_lookup
      SELECT ws, id, json_extract(body, '$.vault'), json_extract(body, '$.owner'), json_extract(body, '$.at') FROM vault_requests
      WHERE ws = ? AND id = ? AND status IN ('granted', 'denied') AND json_extract(body, '$.save') IS NULL`);
    for (const row of rows) add.run(row.ws, row.id);
    const last = rows.at(-1);
    const done = rows.length < limit;
    db.prepare("UPDATE vault_use_backfill SET after_ws = ?, after_id = ?, done = ? WHERE id = 1")
      .run(last?.ws ?? state.after_ws, last?.id ?? state.after_id, done ? 1 : 0);
    db.exec("COMMIT");
    return done;
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// A separate connection and worker keep both the backfill and reads away from the station's request thread. In-memory
/// stores (tests) use the same bounded algorithm on their own connection; they cannot be opened by another worker.
export class UseIndex {
  readonly #db: DatabaseSync;
  readonly #path: string | null;
  #worker: Worker | null = null;
  #next = 0;
  #waiting = new Map<number, { resolve: (bodies: string[]) => void; reject: (error: Error) => void }>();

  constructor(db: DatabaseSync) {
    this.#db = db;
    initializeUseIndex(db);
    this.#path = db.location();
    if (this.#path !== null) this.#start();
  }

  #start(): Worker {
    if (this.#worker !== null) return this.#worker;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./use-index-worker.ts" : "./vault/use-index-worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { path: this.#path } });
    this.#worker = worker;
    worker.unref();
    worker.on("message", (answer: UseAnswer) => {
      const waiting = this.#waiting.get(answer.id);
      if (!waiting) return;
      this.#waiting.delete(answer.id);
      if (answer.error !== undefined) waiting.reject(new Error(answer.error));
      else if (answer.bodies !== undefined) waiting.resolve(answer.bodies);
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
      while (!backfillUseIndex(this.#db)) await new Promise<void>((resolve) => setImmediate(resolve));
      return readUses(this.#db, q);
    }
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
    if (this.#worker !== null) await this.#worker.terminate();
  }
}
