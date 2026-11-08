// A conservative index of the days in Comma's stored statistics. It is rebuilt in bounded batches, and every writer,
// including an older station during handover, marks changed rows for reclassification.
import type { DatabaseSync } from "node:sqlite";

type Json = any;

// Dirty rows and rows whose day is not a string are always checked by the original JavaScript predicate. A missing day
// or a removed row cannot satisfy it. String days use the first ten UTF-16 code units: fromDay is always ten ASCII units.
const STRING = 1, OMIT = 2, OTHER = 3, LARGE_STRING = 4, LARGE_OMIT = 5;
const BATCH_BYTES = 256 * 1024;
const MIN_OMITTED = 256;
const LARGE_BYTES = BATCH_BYTES / MIN_OMITTED;
// The compared ISO date contains only +, -, and digits. Code units outside that span can be folded to one ASCII byte
// on either side without changing their order relative to a date; padding is below every character in an ISO date.
const dayKey = (day: string) => Array.from({ length: 10 }, (_, i) => {
  const unit = i < day.length ? day.charCodeAt(i) : 0;
  return String.fromCharCode(unit < 43 ? 33 : unit > 57 ? 126 : unit);
}).join("");

function classify(json: Json, large: boolean): { kind: number; day: string } {
  try {
    const row = JSON.parse(json);
    const day = row.day;
    if (day === undefined) return { kind: large ? LARGE_OMIT : OMIT, day: "" };
    if (typeof day === "string") return { kind: large ? LARGE_STRING : STRING, day: dayKey(day) };
  } catch { /* The original reader must still see and report malformed JSON. */ }
  return { kind: OTHER, day: "" };
}

/// Create only empty structures. No old statistics are read here. Triggers are in the same transaction as the cursor.
export function installStatsAge(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'comma_stats_age_progress'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE comma_stats_age (id INTEGER PRIMARY KEY, kind INTEGER NOT NULL, day TEXT NOT NULL);
      CREATE INDEX comma_stats_age_day ON comma_stats_age (kind, day, id);
      CREATE TABLE comma_stats_age_progress (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, last INTEGER, done INTEGER NOT NULL);
      INSERT INTO comma_stats_age_progress SELECT 1, NULL, MAX(rowid), MAX(rowid) IS NULL FROM stats_index;

      -- An ignored conflicting insert still makes the existing row dirty; an implicit REPLACE can remove its old rowid
      -- without firing a DELETE trigger. Dirty orphan rows are removed by the batch reader.
      CREATE TRIGGER comma_stats_age_before_insert BEFORE INSERT ON stats_index BEGIN
        UPDATE comma_stats_age SET kind = 0, day = '' WHERE id IN
          (SELECT rowid FROM stats_index WHERE key = NEW.key OR rowid = NEW.rowid);
      END;
      CREATE TRIGGER comma_stats_age_insert AFTER INSERT ON stats_index BEGIN
        INSERT INTO comma_stats_age (id, kind, day) VALUES (NEW.rowid, 0, '')
          ON CONFLICT (id) DO UPDATE SET kind = 0, day = '';
      END;
      CREATE TRIGGER comma_stats_age_before_update BEFORE UPDATE OF rowid, _rowid_, oid, key, json ON stats_index BEGIN
        -- An ignored update leaves its old row in place; a REPLACE can implicitly remove another row without a
        -- DELETE trigger. Mark both for repair instead of removing the old entry before the update succeeds.
        UPDATE comma_stats_age SET kind = 0, day = '' WHERE id = OLD.rowid OR id IN
          (SELECT rowid FROM stats_index WHERE key = NEW.key OR rowid = NEW.rowid);
      END;
      CREATE TRIGGER comma_stats_age_update AFTER UPDATE OF rowid, _rowid_, oid, key, json ON stats_index BEGIN
        DELETE FROM comma_stats_age WHERE id = OLD.rowid AND OLD.rowid <> NEW.rowid;
        INSERT INTO comma_stats_age (id, kind, day) VALUES (NEW.rowid, 0, '')
          ON CONFLICT (id) DO UPDATE SET kind = 0, day = '';
      END;
      CREATE TRIGGER comma_stats_age_restore AFTER UPDATE OF removed ON stats_index
        WHEN OLD.removed <> 0 AND NEW.removed = 0 BEGIN
        INSERT INTO comma_stats_age (id, kind, day) VALUES (NEW.rowid, 0, '')
          ON CONFLICT (id) DO UPDATE SET kind = 0, day = '';
      END;
      CREATE TRIGGER comma_stats_age_delete AFTER DELETE ON stats_index BEGIN
        DELETE FROM comma_stats_age WHERE id = OLD.rowid;
      END;
    `);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Classify at most limit old or dirty rows and about BATCH_BYTES of JSON in one transaction, including orphaned rows
/// left by REPLACE. A single larger row still has to be read whole; no batch collects several such bodies.
export function statsAgeStep(db: DatabaseSync, limit = 64): { visited: number; done: boolean } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("statistics age batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const progress = db.prepare("SELECT cursor, last, done FROM comma_stats_age_progress WHERE id = 1");
    progress.setReadBigInts(true);
    const state = progress.get() as { cursor: bigint | null; last: bigint | null; done: bigint };
    const put = db.prepare(`INSERT INTO comma_stats_age (id, kind, day) VALUES (?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET kind = excluded.kind, day = excluded.day`);
    let visited = 0;
    let bytes = 0;
    const body = db.prepare("SELECT removed = 0 AS active, CASE WHEN removed = 0 THEN json ELSE NULL END AS json FROM stats_index WHERE rowid = ?");
    const add = (id: bigint) => {
      const row = body.get(id) as { active: number; json: Json };
      if (row.active === 0) { put.run(id, OMIT, ""); return; }
      const size = row.json instanceof Uint8Array ? row.json.byteLength : Buffer.byteLength(String(row.json));
      bytes += size;
      const found = classify(row.json, size >= LARGE_BYTES);
      put.run(id, found.kind, found.day);
    };
    if (state.done === 0n) {
      const query = db.prepare(state.cursor === null
        ? "SELECT rowid AS id FROM stats_index WHERE rowid <= ? ORDER BY rowid LIMIT ?"
        : "SELECT rowid AS id FROM stats_index WHERE rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?");
      query.setReadBigInts(true);
      const rows = (state.cursor === null ? query.all(state.last, limit) : query.all(state.cursor, state.last, limit)) as { id: bigint }[];
      for (const row of rows) {
        if (visited > 0 && bytes >= BATCH_BYTES) break;
        add(row.id);
        visited++;
      }
      db.prepare("UPDATE comma_stats_age_progress SET cursor = ?, done = ? WHERE id = 1")
        .run(rows[visited - 1]?.id ?? state.cursor, visited === rows.length && rows.length < limit ? 1 : 0);
    } else {
      const dirty = db.prepare(`SELECT a.id, s.rowid AS present FROM comma_stats_age a INDEXED BY comma_stats_age_day
        LEFT JOIN stats_index s ON s.rowid = a.id WHERE a.kind = 0 ORDER BY a.day, a.id LIMIT ?`);
      dirty.setReadBigInts(true);
      const rows = dirty.all(limit) as { id: bigint; present: bigint | null }[];
      const remove = db.prepare("DELETE FROM comma_stats_age WHERE id = ?");
      for (const row of rows) {
        if (visited > 0 && bytes >= BATCH_BYTES) break;
        if (row.present === null) remove.run(row.id);
        else add(row.id);
        visited++;
      }
    }
    const done = statsAgeReady(db, 0);
    db.exec("COMMIT");
    return { visited, done };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Can a reader use the index, with at most maxDirty rows that still need the original predicate?
export function statsAgeReady(db: DatabaseSync, maxDirty = 64): boolean {
  const progress = db.prepare("SELECT done FROM comma_stats_age_progress WHERE id = 1").get() as { done: number };
  if (progress.done !== 1) return false;
  return db.prepare("SELECT 1 FROM comma_stats_age INDEXED BY comma_stats_age_day WHERE kind = 0 LIMIT 1 OFFSET ?").get(maxDirty) === undefined;
}

// Candidates remain in their original rowid order, which keeps tombstone revision order unchanged. Cross joins force
// the day index to be searched first, even when statistics far outnumber the candidate days.
export const STATS_AGE_CANDIDATES = `SELECT id, key, json FROM (
  SELECT s.rowid AS id, CAST(s.key AS BLOB) AS key, s.json AS json
    FROM comma_stats_age a INDEXED BY comma_stats_age_day CROSS JOIN stats_index s ON s.rowid = a.id
    WHERE a.kind IN (0, 3) AND s.removed = 0
  UNION ALL
  SELECT s.rowid AS id, CAST(s.key AS BLOB) AS key, s.json AS json
    FROM comma_stats_age a INDEXED BY comma_stats_age_day CROSS JOIN stats_index s ON s.rowid = a.id
    WHERE a.kind IN (1, 4) AND a.day >= ? AND s.removed = 0
) ORDER BY id`;

export function statsAgeCandidates(db: DatabaseSync, fromDay: string): { key: Uint8Array; json: string }[] {
  const day = dayKey(fromDay);
  // With very little old history, the joins and sort can cost more than reading it. One large omitted body or 256
  // small ones make the index worthwhile. Both probes seek only into the day index and have a fixed result bound.
  const large = db.prepare(`SELECT 1 FROM comma_stats_age INDEXED BY comma_stats_age_day WHERE kind = 5
    UNION ALL SELECT 1 FROM comma_stats_age INDEXED BY comma_stats_age_day WHERE kind = 4 AND day < ? LIMIT 1`).get(day);
  const omitted = large ?? db.prepare(`SELECT 1 FROM comma_stats_age INDEXED BY comma_stats_age_day WHERE kind = 2
    UNION ALL SELECT 1 FROM comma_stats_age INDEXED BY comma_stats_age_day WHERE kind = 1 AND day < ? LIMIT 1 OFFSET ?`).get(day, MIN_OMITTED - 1);
  if (omitted === undefined) {
    return db.prepare("SELECT CAST(key AS BLOB) AS key, json FROM stats_index WHERE removed = 0").all() as { key: Uint8Array; json: string }[];
  }
  const query = db.prepare(STATS_AGE_CANDIDATES);
  query.setReadBigInts(true);
  return query.all(day) as { key: Uint8Array; json: string }[];
}
