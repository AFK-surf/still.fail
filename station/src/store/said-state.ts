import { randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import { hasLegacySaid, legacySaidLatest, LEGACY_SAID_LATEST, LEGACY_SAID_SCAN } from "./legacy-said-build.ts";

export const SAID_LATEST = "SELECT n, author_kind, author FROM entries INDEXED BY entries_said WHERE thread = ?1 AND kind = 'message' AND letter IS NULL ORDER BY n DESC LIMIT 1";
export const SAID_STATE = `SELECT s.said_n, s.said_other_n, s.said_other_known,
    g.author AS guard_author, g.other_n AS guard_other_n, g.ready AS guard_ready
  FROM thread_state s LEFT JOIN said_state_guard g ON g.thread = s.thread WHERE s.thread = ?1
  UNION ALL SELECT NULL, NULL, NULL, g.author, g.other_n, g.ready FROM said_state_guard g
    WHERE g.thread = ?1 AND NOT EXISTS (SELECT 1 FROM thread_state s WHERE s.thread = ?1) LIMIT 1`;
export const SAID_SCAN = `SELECT n, author_kind, author FROM entries INDEXED BY entries_said
  WHERE thread = ?1 AND kind = 'message' AND letter IS NULL AND n < ?2 ORDER BY n DESC LIMIT ?3`;
export const SAID_BATCH_SIZE = 64;

type Latest = { n: number; author_kind: string; author: string };
type State = { said_n: number | null; said_other_n: number | null; said_other_known: number | null;
  guard_author: string | null; guard_other_n: number | null; guard_ready: number | null };

/// The guard can also hold a rare result for a thread whose old writer removed its thread_state row. It is invalidated
/// by the same triggers as a scan in progress, and remains valid across appends by that same person.
export function saidBoundary(state: State | undefined, latest: Latest): { known: boolean; other: number | null } {
  if (latest.author_kind !== "person") return { known: true, other: latest.n };
  if (state?.said_n === latest.n && state.said_other_known === 1) return { known: true, other: state.said_other_n };
  if (state?.guard_ready === 1 && state.guard_author === latest.author) return { known: true, other: state.guard_other_n };
  return { known: false, other: null };
}

export type SaidScan = { thread: number; author: string; token: string; before: number;
  found?: { other: number | null } };
type SaidStep = { done: boolean; visited: number; scan: SaidScan | null };

/// Read at most one small slice of a requested old chat. No lock is held between slices. A guard is invalidated by
/// writes that can change the result, so the last transaction can either publish this answer or safely start again.
export function saidScanStep(db: DatabaseSync, thread: number, scan: SaidScan | null, limit = SAID_BATCH_SIZE,
  mayWrite?: () => boolean): SaidStep {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > SAID_BATCH_SIZE) throw new RangeError("said scan batch must be between 1 and 64");
  if (scan !== null && scan.thread !== thread) throw new Error("said scan belongs to another chat");
  const legacy = hasLegacySaid(db);
  const latest = () => db.prepare(legacy ? LEGACY_SAID_LATEST : SAID_LATEST).get(thread) as Latest | undefined;
  const state = () => db.prepare(SAID_STATE).get(thread) as State | undefined;
  const done = (): SaidStep => ({ done: true, visited: 0, scan: null });
  if (scan === null) {
    const head = latest();
    if (head === undefined || saidBoundary(state(), head).known) return done();
    if (mayWrite && !mayWrite()) return { done: false, visited: 0, scan: null };
    db.exec("BEGIN IMMEDIATE");
    try {
      const current = latest();
      if (current === undefined || saidBoundary(state(), current).known) { db.exec("COMMIT"); return done(); }
      const token = randomBytes(16).toString("hex");
      db.prepare(`INSERT INTO said_state_guard(thread,token,author,other_n,ready) VALUES (?,?,?,NULL,0)
        ON CONFLICT(thread) DO UPDATE SET token=excluded.token,author=excluded.author,other_n=NULL,ready=0`)
        .run(thread, token, current.author);
      db.exec("COMMIT");
      return { done: false, visited: 0, scan: { thread, token, author: current.author, before: current.n } };
    } catch (error) {
      try { db.exec("ROLLBACK"); } catch {}
      throw error;
    }
  }
  const guard = db.prepare("SELECT token FROM said_state_guard WHERE thread=?").get(thread) as { token: string } | undefined;
  if (guard?.token !== scan.token) return { done: false, visited: 0, scan: null };
  let visited = 0;
  if (scan.found === undefined) {
    const rows = db.prepare(legacy ? LEGACY_SAID_SCAN : SAID_SCAN).all(thread, scan.before, limit) as Latest[];
    visited = rows.length;
    const other = rows.find((row) => row.author_kind !== "person" || row.author !== scan!.author);
    if (other !== undefined) scan.found = { other: other.n };
    else if (rows.length < limit) scan.found = { other: null };
    else scan.before = rows.at(-1)!.n;
  }
  if (scan.found === undefined || (mayWrite && !mayWrite())) return { done: false, visited, scan };
  db.exec("BEGIN IMMEDIATE");
  try {
    const currentGuard = db.prepare("SELECT token FROM said_state_guard WHERE thread=?").get(thread) as { token: string } | undefined;
    const current = latest();
    if (currentGuard?.token !== scan.token || (current !== undefined && (current.author_kind !== "person" || current.author !== scan.author))) {
      db.exec("COMMIT");
      return { done: false, visited, scan: null };
    }
    if (current === undefined) {
      db.prepare("DELETE FROM said_state_guard WHERE thread=? AND token=?").run(thread, scan.token);
    } else {
      const wrote = db.prepare("UPDATE thread_state SET said_other_n=?, said_other_known=1 WHERE thread=? AND said_n=?")
        .run(scan.found.other, thread, current.n).changes;
      if (wrote) db.prepare("DELETE FROM said_state_guard WHERE thread=? AND token=?").run(thread, scan.token);
      else db.prepare("UPDATE said_state_guard SET author=?, other_n=?, ready=1 WHERE thread=? AND token=?")
        .run(scan.author, scan.found.other, thread, scan.token);
    }
    db.exec("COMMIT");
    return { done: true, visited, scan: null };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}

// The sidebar needs the latest message not written by the latest person. Keep that boundary in the thread state page
// already changed by each append; a run of messages from the same person leaves the boundary alone.
const eligible = "NEW.kind = 'message' AND NEW.letter IS NULL";
const conflict = `(EXISTS (SELECT 1 FROM entries e WHERE e.thread = NEW.thread AND e.n = NEW.n)
  OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread = NEW.thread AND e.ts = NEW.ts)))`;
// REPLACE can also displace a row from a different thread by rowid without firing its DELETE triggers.
const rowidVictim = "SELECT thread FROM entries WHERE rowid=NEW.rowid AND kind='message' AND letter IS NULL";

// A trigger cannot wait for the old lookup's dirty keys to be folded. A source tail can prove the latest message
// without walking those keys; if it cannot, leave the boundary unknown for the existing reader/worker to resolve.
// Most appends only need the first row. A completed lookup with at most 64 pending keys is also bounded and can
// answer across a longer run of edits. Otherwise the lazy source probe reads at most 65 rows from this thread.
function legacyWriteHead(except?: string): string {
  const where = `thread=NEW.thread${except === undefined ? "" : ` AND n != ${except}`}`;
  const ordinary = "kind='message' AND letter IS NULL";
  const bounded = `(SELECT scanned FROM legacy_said_meta WHERE id=1)=1 AND NOT EXISTS (
    SELECT 1 FROM legacy_said_dirty WHERE ${where} LIMIT 1 OFFSET 64)`;
  const staged = `(SELECT n FROM (${legacySaidLatest(except).replaceAll("?1", "NEW.thread")}))`;
  return `WITH said_write_first AS MATERIALIZED (
    SELECT n,kind,letter FROM entries WHERE ${where} ORDER BY n DESC LIMIT 1
  ), said_write_probe AS MATERIALIZED (
    SELECT n,kind,letter FROM entries WHERE ${where} ORDER BY n DESC LIMIT 65
  ) SELECT
    CASE WHEN (SELECT n FROM said_write_first) IS NULL THEN NULL
      WHEN (SELECT ${ordinary} FROM said_write_first) THEN (SELECT n FROM said_write_first)
      WHEN ${bounded} THEN ${staged}
      ELSE (SELECT n FROM said_write_probe WHERE ${ordinary} ORDER BY n DESC LIMIT 1) END AS n,
    CASE WHEN (SELECT n FROM said_write_first) IS NULL THEN 1
      WHEN (SELECT ${ordinary} FROM said_write_first) THEN 1
      WHEN ${bounded} THEN 1
      WHEN EXISTS (SELECT 1 FROM said_write_probe WHERE ${ordinary}) THEN 1
      WHEN (SELECT COUNT(*) FROM said_write_probe)<65 THEN 1 ELSE 0 END AS known`;
}

function stateWriters(legacy: boolean): { addState: string; beforeInsert: string } {
  const source = legacy ? "legacy_said" : "entries INDEXED BY entries_said";
  const filter = legacy ? "" : " AND kind = 'message' AND letter IS NULL";
  const prior = `(SELECT n FROM ${source} WHERE thread = NEW.thread${filter} ORDER BY n DESC LIMIT 1)`;
  const other = legacy ? `(SELECT CASE WHEN p.known=1 AND p.n IS NULL THEN 0 ELSE 1 END
    FROM (${legacyWriteHead("NEW.n")}) p)`
    : `EXISTS (SELECT 1 FROM ${source} WHERE thread = NEW.thread${filter} AND n != NEW.n LIMIT 1)`;
  const same = `EXISTS (SELECT 1 FROM entries p WHERE p.thread = NEW.thread AND p.n = ${prior}
    AND p.author_kind = 'person' AND p.author = NEW.author)`;
  const appendSame = legacy ? `(${eligible} AND NEW.author_kind='person' AND COALESCE((
    SELECT p.known=1 AND p.n IS NOT NULL AND NEW.n>p.n AND EXISTS (
      SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.n=p.n
        AND e.author_kind='person' AND e.author=NEW.author)
    FROM (${legacyWriteHead()}) p),0))`
    : `(${eligible} AND NEW.author_kind = 'person' AND NEW.n > ${prior} AND ${same})`;
  // An upsert evaluates its proposed values even when it will update the existing row. Only a new state row needs
  // the other-message lookup; the update arm retains the existing boundary.
  const initialKnown = legacy
    ? `CASE WHEN EXISTS (SELECT 1 FROM thread_state WHERE thread=NEW.thread) THEN 0
        WHEN ${eligible} AND NOT ${other} THEN 1 ELSE 0 END`
    : `CASE WHEN ${eligible} AND NOT ${other} THEN 1 ELSE 0 END`;
  // A BEFORE INSERT trigger can itself insert another message. Compute the new boundary after the row lands, against
  // the current previous message and state; otherwise an outer insert can reuse the boundary of its nested insert.
  const previous = legacy ? legacyWriteHead("NEW.n") : `SELECT
    (SELECT n FROM entries INDEXED BY entries_said WHERE thread=NEW.thread AND n != NEW.n
      AND kind='message' AND letter IS NULL ORDER BY n DESC LIMIT 1) AS n,1 AS known`;
  const afterState = `(said_other_known,said_other_n) = (
    WITH previous AS MATERIALIZED (${previous}),
    previous_context AS MATERIALIZED (
      SELECT previous.n,previous.known,
        EXISTS (SELECT 1 FROM entries p WHERE p.thread=NEW.thread AND p.n=previous.n
          AND p.author_kind='person' AND p.author=NEW.author) AS same
      FROM previous
    )
    SELECT said_other_known,said_other_n WHERE NOT (${eligible})
    UNION ALL
    SELECT CASE
      WHEN p.known=0 THEN 0
      WHEN p.n IS NOT NULL AND NEW.n <= p.n THEN 0
      WHEN NEW.author_kind != 'person' OR p.n IS NULL OR NOT p.same THEN 1
      WHEN said_n = p.n THEN said_other_known ELSE 0 END,
    CASE
      WHEN p.known=0 THEN said_other_n
      WHEN p.n IS NOT NULL AND NEW.n <= p.n THEN said_other_n
      WHEN NEW.author_kind != 'person' OR p.n IS NULL THEN NULL
      WHEN NOT p.same THEN p.n
      WHEN said_n = p.n THEN said_other_n ELSE NULL END
    FROM previous_context p WHERE ${eligible}
  )`;
  const addState = `CREATE TRIGGER thread_state_add AFTER INSERT ON entries BEGIN
  -- said_after_insert_v2
  INSERT INTO thread_state (thread, last_n, said_n, person_n, letters, said_other_known)
    VALUES (NEW.thread, NEW.n,
      CASE WHEN NEW.kind = 'message' AND NEW.letter IS NULL THEN NEW.n END,
      CASE WHEN NEW.kind = 'message' AND NEW.author_kind = 'person' THEN NEW.n END,
      CASE WHEN NEW.kind = 'message' AND NEW.letter IS NOT NULL THEN 1 ELSE 0 END,
      ${initialKnown})
  ON CONFLICT (thread) DO UPDATE SET
    last_n = MAX(last_n, excluded.last_n),
    said_n = CASE WHEN excluded.said_n IS NULL THEN said_n WHEN said_n IS NULL THEN excluded.said_n ELSE MAX(said_n, excluded.said_n) END,
    person_n = CASE WHEN excluded.person_n IS NULL THEN person_n WHEN person_n IS NULL THEN excluded.person_n ELSE MIN(person_n, excluded.person_n) END,
    letters = letters + excluded.letters,
    ${afterState};
  INSERT INTO thread_people SELECT NEW.thread, NEW.author, NEW.n WHERE NEW.kind = 'message' AND NEW.author_kind = 'person'
  ON CONFLICT (thread, author) DO UPDATE SET first_n = MIN(first_n, excluded.first_n);
END;`;

  const beforeInsert = `CREATE TRIGGER said_state_before_insert BEFORE INSERT ON entries
  WHEN ${eligible} OR ${conflict} OR EXISTS (${rowidVictim}) BEGIN
  -- said_after_insert_v2
  -- A replacement can remove an entry without firing DELETE triggers. An old-history scan stays valid across an
  -- append by the same person, but any other eligible insertion can change the boundary it is looking for.
  DELETE FROM said_state_guard WHERE thread = NEW.thread
    AND (${conflict} OR (${eligible} AND NOT COALESCE(${appendSame}, 0)));
  UPDATE thread_state SET said_other_known=0 WHERE thread=NEW.thread AND ${conflict};
  DELETE FROM said_state_guard WHERE thread = (${rowidVictim});
  UPDATE thread_state SET said_other_known=0 WHERE thread = (${rowidVictim});
END;`;
  return { addState,beforeInsert };
}

const changed = "OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid OR OLD.kind IS NOT NEW.kind OR OLD.author_kind IS NOT NEW.author_kind OR OLD.author IS NOT NEW.author OR OLD.letter IS NOT NEW.letter OR OLD.ts IS NOT NEW.ts";
const invalidate = `
CREATE TRIGGER said_state_before_delete BEFORE DELETE ON entries BEGIN
  DELETE FROM said_state_guard WHERE thread = OLD.thread;
  UPDATE thread_state SET said_other_known = 0 WHERE thread = OLD.thread;
END;
CREATE TRIGGER said_state_before_update BEFORE UPDATE OF thread,n,rowid,_rowid_,oid,kind,author_kind,author,letter,ts ON entries
  WHEN ${changed} BEGIN
  -- said_rowid_v2
  DELETE FROM said_state_guard WHERE thread IN (OLD.thread, NEW.thread);
  UPDATE thread_state SET said_other_known = 0 WHERE thread IN (OLD.thread, NEW.thread);
  DELETE FROM said_state_guard WHERE thread = (${rowidVictim} AND OLD.rowid IS NOT NEW.rowid);
  UPDATE thread_state SET said_other_known=0 WHERE thread = (${rowidVictim} AND OLD.rowid IS NOT NEW.rowid);
END;`;

/// Add coverage without walking existing messages. Existing threads are unknown until requested; new appends maintain
/// what can be known from the immediately preceding message. No old usage or messages are rebuilt here.
export function installSaidState(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'said_state_guard'").get() !== undefined;
  const legacy = hasLegacySaid(db);
  const current = () => {
    const source = legacy ? "said_write_probe" : "entries_said";
    const trigger = db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name=?");
    const writes = ["said_state_before_insert", "thread_state_add"].every((name) => {
      const sql = (trigger.get(name) as { sql: string } | undefined)?.sql ?? "";
      return sql.includes(source) && sql.includes("said_after_insert_v2");
    });
    return writes && ((trigger.get("said_state_before_update") as { sql: string } | undefined)?.sql ?? "").includes("said_rowid_v2");
  };
  if (installed() && current()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    const { addState,beforeInsert } = stateWriters(legacy);
    if (!installed()) {
      db.exec(`ALTER TABLE thread_state ADD COLUMN said_other_n INTEGER;
        ALTER TABLE thread_state ADD COLUMN said_other_known INTEGER NOT NULL DEFAULT 0;
        CREATE TABLE said_state_guard(thread INTEGER PRIMARY KEY, token TEXT NOT NULL,
          author TEXT, other_n INTEGER, ready INTEGER NOT NULL DEFAULT 0) WITHOUT ROWID;
        DROP TRIGGER thread_state_add;
        ${addState}
        ${beforeInsert}
        ${invalidate}`);
    } else if (!current()) {
      db.exec(`DROP TRIGGER IF EXISTS thread_state_add; DROP TRIGGER IF EXISTS said_state_before_insert;
        DROP TRIGGER IF EXISTS said_state_before_delete; DROP TRIGGER IF EXISTS said_state_before_update;
        ${addState} ${beforeInsert} ${invalidate}`);
    }
    db.exec("COMMIT");
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}
