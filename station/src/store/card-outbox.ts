import type { DatabaseSync } from "node:sqlite";

export type CardOutcomeField = "adb" | "rig" | "signin" | "vault";
export type CardOutcome = {
  id: string;
  thread: number;
  ts: string;
  agent: string;
  field: CardOutcomeField;
  close: boolean;
  outcome: Record<string, unknown>;
};
export type CardOutcomeSaver = { save(item: Omit<CardOutcome, "id">, save: () => void): string };

export type CardEditPage = { kind: "found"; card: string } | { kind: "next"; before: string } | { kind: "end" };
export type CardMessagePage = { kind: "found"; n: string } | { kind: "next"; before: string } | { kind: "end" };
/// A live guard acquired before paging. It is only an in-process capability, never stored in the queue.
export type CardEditScan = { thread: number; ts: string; agent: string; target: string; token: string; schema: number };
const installed = new WeakMap<DatabaseSync, number>();

/// Find an old message's last target entry in small pages without preparing the entire database. A guard spanning the
/// pages is checked before the result is used; the cursor and result stay SQLite integers encoded as strings.
export function cardMessagePage(db: DatabaseSync, thread: number, target: string, before: string | null): CardMessagePage {
  const range = before === null ? "" : " AND n<CAST(?3 AS INTEGER)";
  const row = db.prepare(`WITH page AS MATERIALIZED (
      SELECT n,target FROM entries WHERE thread=?1${range} ORDER BY n DESC LIMIT 512
    ) SELECT (SELECT CAST(n AS TEXT) FROM page WHERE target=CAST(?2 AS INTEGER) ORDER BY n DESC LIMIT 1) AS edit,
      CAST(MIN(n) AS TEXT) AS before,COUNT(*) AS count FROM page`)
    .get(...(before === null ? [thread, target] : [thread, target, before])) as
      { edit: string | null; before: string | null; count: number };
  if (row.edit !== null) return { kind: "found", n: row.edit };
  return row.count < 512 ? { kind: "end" } : { kind: "next", before: row.before! };
}

/// One bounded page of possible card edits, newest first. The caller holds a snapshot and must validate that the
/// target did not change across pages before applying the result. Cursors remain SQLite integers as strings.
export function cardEditPage(db: DatabaseSync, thread: number, target: string, before: string | null): CardEditPage {
  const indexed = db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_cards'").get() !== undefined;
  const from = indexed ? "entries INDEXED BY entries_cards" : "entries";
  const range = before === null ? "" : " AND n<CAST(?3 AS INTEGER)";
  const rows = db.prepare(`SELECT CAST(n AS TEXT) AS position,
      CASE WHEN kind='edit' AND target=CAST(?2 AS INTEGER) THEN card ELSE NULL END AS card
    FROM (SELECT n,kind,target,card FROM ${from} WHERE thread=?1${indexed ? " AND card IS NOT NULL" : ""}${range}
      ORDER BY n DESC LIMIT 64) ORDER BY n DESC`)
    .all(...(before === null ? [thread, target] : [thread, target, before])) as { position: string; card: string | null }[];
  const found = rows.find((row) => row.card !== null);
  if (found) return { kind: "found", card: found.card! };
  return rows.length < 64 ? { kind: "end" } : { kind: "next", before: rows.at(-1)!.position };
}

/// The queue's table, under `name`.
const outboxTable = (name: string) => `CREATE TABLE IF NOT EXISTS ${name}(thread INTEGER NOT NULL,ts TEXT NOT NULL,id INTEGER NOT NULL,
        agent TEXT NOT NULL,field TEXT NOT NULL CHECK(field IN ('adb','rig','signin','vault')),
        close_card INTEGER NOT NULL CHECK(close_card IN (0,1)),outcome TEXT NOT NULL,
        PRIMARY KEY(thread,ts,id)) WITHOUT ROWID`;

/// A queue made before a rig's card had an outcome (2026-11-10) names the fields it takes in a CHECK, which SQLite
/// does not alter: made again with one more, the outcomes waiting in it kept (a few rows at most: it is emptied as
/// they are applied), the first time a rig's outcome is queued. A caller's savepoint holds it.
function takeRigOutcomes(db: DatabaseSync): void {
  const sql = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='card_outbox'").get()?.sql;
  if (typeof sql !== "string" || sql.includes("'rig'")) return;
  db.exec(`${outboxTable("card_outbox_wider")};
    INSERT INTO card_outbox_wider SELECT thread,ts,id,agent,field,close_card,outcome FROM card_outbox;
    DROP TABLE card_outbox;
    ALTER TABLE card_outbox_wider RENAME TO card_outbox;`);
}

/// Install only constant-size metadata. Existing messages and requests are not scanned.
export function installCardOutbox(db: DatabaseSync): void {
  if (hasCardOutbox(db)) return;
  db.exec("SAVEPOINT card_outbox_install");
  try {
    // Another connection may have installed it before this savepoint acquired its write transaction.
    if (hasCardOutbox(db)) { db.exec("RELEASE card_outbox_install"); return; }
    db.exec(`CREATE TABLE IF NOT EXISTS card_outbox_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
        next_id INTEGER NOT NULL) WITHOUT ROWID;
      INSERT OR IGNORE INTO card_outbox_meta VALUES(1,1,0);`);
    if (db.prepare("SELECT version FROM card_outbox_meta WHERE id=1").get()?.version !== 1)
      throw new Error("card outcome outbox has an unsupported version");
    db.exec(`${outboxTable("card_outbox")};
      CREATE TABLE IF NOT EXISTS card_outbox_head(id INTEGER PRIMARY KEY,thread INTEGER NOT NULL,ts TEXT NOT NULL);`);
    db.exec("RELEASE card_outbox_install");
    hasCardOutbox(db);
  } catch (error) {
    try { db.exec("ROLLBACK TO card_outbox_install; RELEASE card_outbox_install"); } catch {}
    throw error;
  }
}

/// A store from before the queue has no work; an unknown queue version must not be consumed.
export function hasCardOutbox(db: DatabaseSync): boolean {
  const schema = Number(db.prepare("PRAGMA schema_version").get()!.schema_version);
  if (installed.get(db) === schema) {
    // A version change is a row update and does not change SQLite's schema cookie.
    if (db.prepare("SELECT version FROM card_outbox_meta WHERE id=1").get()?.version !== 1)
      throw new Error("card outcome outbox has an unsupported version");
    return true;
  }
  if (!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='card_outbox_meta'").get()) return false;
  if (db.prepare("SELECT version FROM card_outbox_meta WHERE id=1").get()?.version !== 1)
    throw new Error("card outcome outbox has an unsupported version");
  if (db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name IN ('card_outbox','card_outbox_head')").get()?.n !== 2)
    throw new Error("card outcome outbox tables are missing");
  // A savepoint may still be rolled back by its caller. Its schema cookie can later be reused by unrelated DDL,
  // so cache only schema that has actually committed.
  if (!db.isTransaction) installed.set(db, schema);
  return true;
}

/// Called in the transaction that saves the request's status, so a crash cannot separate it from its card result.
export function enqueueCardOutcome(db: DatabaseSync, item: Omit<CardOutcome, "id">): string {
  if (!db.isTransaction) throw new Error("card outcome must be queued with its request in a transaction");
  const outcome = JSON.stringify(item.outcome);
  if (outcome === undefined) throw new Error("card outcome must be serializable");
  const next = db.prepare(`UPDATE card_outbox_meta SET next_id=next_id+1
    WHERE id=1 AND next_id<9223372036854775807 RETURNING CAST(next_id AS TEXT) AS id`).get();
  if (!next) throw new Error("card outcome sequence is exhausted");
  const id = String(next.id);
  db.prepare(`INSERT INTO card_outbox_head(id,thread,ts) SELECT CAST(? AS INTEGER),?,?
    WHERE NOT EXISTS (SELECT 1 FROM card_outbox WHERE thread=? AND ts=? LIMIT 1)`)
    .run(id, item.thread, item.ts, item.thread, item.ts);
  db.prepare("INSERT INTO card_outbox(thread,ts,id,agent,field,close_card,outcome) VALUES(?,?,CAST(? AS INTEGER),?,?,?,?)")
    .run(item.thread, item.ts, id, item.agent, item.field, item.close ? 1 : 0, outcome);
  return id;
}

/// A request save and its queued outcome succeed or fail as one operation, including inside an existing transaction.
export function saveWithCardOutcome(db: DatabaseSync, item: Omit<CardOutcome, "id">, save: () => void): string {
  db.exec("SAVEPOINT card_outbox_save");
  try {
    if (!hasCardOutbox(db)) installCardOutbox(db);
    if (item.field === "rig") takeRigOutcomes(db);
    save();
    const id = enqueueCardOutcome(db, item);
    db.exec("RELEASE card_outbox_save");
    return id;
  } catch (error) {
    try { db.exec("ROLLBACK TO card_outbox_save; RELEASE card_outbox_save"); } catch {}
    throw error;
  }
}

/// One oldest result per card. A cursor lets another card advance when one waits on old history.
export function cardOutcomeHeads(db: DatabaseSync, after: string, limit = 64): CardOutcome[] {
  if (!Number.isInteger(limit) || limit < 1 || limit > 64) throw new Error("card outcome page must contain 1 to 64 cards");
  const rows = db.prepare(`SELECT CAST(q.id AS TEXT) AS id,q.thread,q.ts,q.agent,q.field,q.close_card,q.outcome
    FROM card_outbox_head h CROSS JOIN card_outbox q ON q.thread=h.thread AND q.ts=h.ts AND q.id=h.id
    WHERE h.id>CAST(? AS INTEGER) ORDER BY h.id LIMIT ?`).all(after, limit) as
      { id: string; thread: number; ts: string; agent: string; field: CardOutcomeField; close_card: number; outcome: string }[];
  return rows.map(({ close_card, ...row }) => ({ ...row, close: close_card === 1, outcome: JSON.parse(row.outcome) as Record<string, unknown> }));
}

/// Remove the observed head in the same transaction as its message edit. A competing consumer cannot remove its successor.
export function completeCardOutcome(db: DatabaseSync, item: Pick<CardOutcome, "id" | "thread" | "ts">): boolean {
  if (!db.isTransaction) throw new Error("card outcome must be completed with its message edit in a transaction");
  const removed = db.prepare("DELETE FROM card_outbox_head WHERE thread=? AND ts=? AND id=CAST(? AS INTEGER)")
    .run(item.thread, item.ts, item.id).changes;
  if (!removed) return false;
  db.prepare("DELETE FROM card_outbox WHERE thread=? AND ts=? AND id=CAST(? AS INTEGER)").run(item.thread, item.ts, item.id);
  db.prepare(`INSERT INTO card_outbox_head(id,thread,ts)
    SELECT id,thread,ts FROM card_outbox WHERE thread=? AND ts=? ORDER BY id LIMIT 1`).run(item.thread, item.ts);
  return true;
}
