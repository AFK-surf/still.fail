// Exact local-day usage without rereading calls at a midnight inside a quarter. Old calls are filled a session at a time,
// in bounded transactions; new calls and changes are kept by database triggers, including those from older stations.
import type { DatabaseSync } from "node:sqlite";

const MINUTE = (name: string) => `(CASE WHEN ${name}.at >= 0 THEN ${name}.at / 60000 ELSE -1 - ((-1 - ${name}.at) / 60000) END)`;
const QUARTER = (name: string) => `(CASE WHEN ${name}.at >= 0 THEN ${name}.at / 900000 ELSE -1 - ((-1 - ${name}.at) / 900000) END)`;
const TOKENS = (name: string) => `(${name}.input + ${name}.cache_read + ${name}.cache_write + ${name}.cache_write_long + ${name}.output)`;
const KEY = (name: string) => `session = ${name}.session AND minute = ${MINUTE(name)} AND runtime = ${name}.runtime AND model = COALESCE(${name}.model, '')`;
const QUARTER_KEY = (name: string) => `session = ${name}.session AND quarter = ${QUARTER(name)} AND runtime = ${name}.runtime AND model = COALESCE(${name}.model, '')`;

// A row was added to the summary if it was already passed by the cursor, was inserted beyond the saved end, or was
// written after installation while it was inside the still-unfilled range (the marker). A row with no state is old.
const INDEXED = (name: string) => `EXISTS (
  SELECT 1 FROM usage_minute_sessions st WHERE st.session = ${name}.session AND (
    st.done = 1 OR (st.after_at IS NOT NULL AND (${name}.at, ${name}.rowid) <= (st.after_at, st.after_rowid))
    OR (st.end_at IS NOT NULL AND (${name}.at, ${name}.rowid) > (st.end_at, st.end_rowid))
    OR EXISTS (SELECT 1 FROM usage_minute_seen seen WHERE seen.id = ${name}.id)))`;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS usage_minute (
  session TEXT NOT NULL, minute INTEGER NOT NULL, runtime TEXT NOT NULL, model TEXT NOT NULL,
  calls INTEGER NOT NULL, tokens INTEGER NOT NULL,
  PRIMARY KEY (session, minute, runtime, model)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS usage_day_quarters (
  session TEXT NOT NULL, quarter INTEGER NOT NULL, runtime TEXT NOT NULL, model TEXT NOT NULL,
  calls INTEGER NOT NULL, tokens INTEGER NOT NULL,
  PRIMARY KEY (session, quarter, runtime, model)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS usage_minute_scope (session TEXT PRIMARY KEY, ws TEXT, done INTEGER NOT NULL) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS usage_minute_scope_ws ON usage_minute_scope (ws, done, session);
CREATE TABLE IF NOT EXISTS usage_minute_sessions (
  session TEXT PRIMARY KEY, after_at INTEGER, after_rowid INTEGER, end_at INTEGER, end_rowid INTEGER, done INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS usage_minute_seen (id TEXT PRIMARY KEY) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS usage_minute_all (id INTEGER PRIMARY KEY CHECK (id = 1), after_session TEXT, done INTEGER NOT NULL);
INSERT OR IGNORE INTO usage_minute_all VALUES (1, NULL, NOT EXISTS (SELECT 1 FROM usage LIMIT 1));

CREATE TRIGGER IF NOT EXISTS usage_minute_session_add AFTER INSERT ON sessions BEGIN
  INSERT OR IGNORE INTO usage_minute_sessions
    SELECT NEW.key, NULL, NULL,
      (SELECT at FROM usage WHERE session = NEW.key ORDER BY at DESC, rowid DESC LIMIT 1),
      (SELECT rowid FROM usage WHERE session = NEW.key ORDER BY at DESC, rowid DESC LIMIT 1),
      NOT EXISTS (SELECT 1 FROM usage WHERE session = NEW.key LIMIT 1);
  INSERT INTO usage_minute_scope (session, ws, done)
    SELECT NEW.key, NEW.ws, (SELECT done FROM usage_minute_sessions WHERE session = NEW.key)
    WHERE EXISTS (SELECT 1 FROM usage WHERE session = NEW.key LIMIT 1)
    ON CONFLICT (session) DO UPDATE SET ws = excluded.ws, done = excluded.done;
END;
CREATE TRIGGER IF NOT EXISTS usage_minute_session_move AFTER UPDATE OF ws ON sessions BEGIN
  INSERT OR IGNORE INTO usage_minute_sessions
    SELECT NEW.key, NULL, NULL,
      (SELECT at FROM usage WHERE session = NEW.key ORDER BY at DESC, rowid DESC LIMIT 1),
      (SELECT rowid FROM usage WHERE session = NEW.key ORDER BY at DESC, rowid DESC LIMIT 1),
      NOT EXISTS (SELECT 1 FROM usage WHERE session = NEW.key LIMIT 1);
  INSERT INTO usage_minute_scope (session, ws, done)
    SELECT NEW.key, NEW.ws, (SELECT done FROM usage_minute_sessions WHERE session = NEW.key)
    WHERE EXISTS (SELECT 1 FROM usage WHERE session = NEW.key LIMIT 1)
    ON CONFLICT (session) DO UPDATE SET ws = excluded.ws, done = excluded.done;
END;
CREATE TRIGGER IF NOT EXISTS usage_minute_session_drop AFTER DELETE ON sessions BEGIN
  UPDATE usage_minute_scope SET ws = NULL WHERE session = OLD.key;
END;
CREATE TRIGGER IF NOT EXISTS usage_minute_add AFTER INSERT ON usage BEGIN
  INSERT OR IGNORE INTO usage_minute_sessions
    SELECT NEW.session, NULL, NULL,
      (SELECT at FROM usage WHERE session = NEW.session ORDER BY at DESC, rowid DESC LIMIT 1),
      (SELECT rowid FROM usage WHERE session = NEW.session ORDER BY at DESC, rowid DESC LIMIT 1),
      NOT EXISTS (SELECT 1 FROM usage WHERE session = NEW.session AND id <> NEW.id LIMIT 1);
  INSERT OR IGNORE INTO usage_minute_seen
    SELECT NEW.id FROM usage_minute_sessions st WHERE st.session = NEW.session AND st.done = 0
      AND (st.after_at IS NULL OR (NEW.at, NEW.rowid) > (st.after_at, st.after_rowid))
      AND (NEW.at, NEW.rowid) <= (st.end_at, st.end_rowid);
  INSERT INTO usage_minute_scope (session, ws, done)
    VALUES (NEW.session, (SELECT ws FROM sessions WHERE key = NEW.session), (SELECT done FROM usage_minute_sessions WHERE session = NEW.session))
    ON CONFLICT (session) DO UPDATE SET ws = excluded.ws, done = excluded.done;
  INSERT INTO usage_minute VALUES (NEW.session, ${MINUTE("NEW")}, NEW.runtime, COALESCE(NEW.model, ''), NEW.calls, ${TOKENS("NEW")})
    ON CONFLICT (session, minute, runtime, model) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;
  INSERT INTO usage_day_quarters VALUES (NEW.session, ${QUARTER("NEW")}, NEW.runtime, COALESCE(NEW.model, ''), NEW.calls, ${TOKENS("NEW")})
    ON CONFLICT (session, quarter, runtime, model) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;
END;
CREATE TRIGGER IF NOT EXISTS usage_minute_drop AFTER DELETE ON usage BEGIN
  UPDATE usage_minute SET calls = calls - OLD.calls, tokens = tokens - ${TOKENS("OLD")} WHERE ${KEY("OLD")} AND ${INDEXED("OLD")};
  DELETE FROM usage_minute WHERE ${KEY("OLD")} AND calls = 0 AND tokens = 0 AND ${INDEXED("OLD")};
  UPDATE usage_day_quarters SET calls = calls - OLD.calls, tokens = tokens - ${TOKENS("OLD")} WHERE ${QUARTER_KEY("OLD")} AND ${INDEXED("OLD")};
  DELETE FROM usage_day_quarters WHERE ${QUARTER_KEY("OLD")} AND calls = 0 AND tokens = 0 AND ${INDEXED("OLD")};
  DELETE FROM usage_minute_seen WHERE id = OLD.id;
  DELETE FROM usage_minute_scope WHERE session = OLD.session
    AND NOT EXISTS (SELECT 1 FROM usage_minute WHERE session = OLD.session LIMIT 1)
    AND EXISTS (SELECT 1 FROM usage_minute_sessions WHERE session = OLD.session AND done = 1);
END;
CREATE TRIGGER IF NOT EXISTS usage_minute_grow AFTER UPDATE OF output ON usage WHEN NEW.output <> OLD.output BEGIN
  UPDATE usage_minute SET tokens = tokens + NEW.output - OLD.output WHERE ${KEY("OLD")} AND ${INDEXED("OLD")};
  UPDATE usage_day_quarters SET tokens = tokens + NEW.output - OLD.output WHERE ${QUARTER_KEY("OLD")} AND ${INDEXED("OLD")};
END;
`;

/// Install only empty structures and triggers. Capturing old session endpoints and filling their calls happens later.
export function installUsageMinutes(db: DatabaseSync): void {
  if (db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_history_from_detail'").get()) return;
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_minute_all'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(SCHEMA);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

type State = { after_at: number | null; after_rowid: number | null; end_at: number | null; end_rowid: number | null; done: number };
type Source = { id: string; at: number; rowid: number };
export type Backfill = { done: boolean; processed: number };
export const MINUTE_SAME_TIME = `SELECT id, at, rowid FROM usage INDEXED BY usage_session
  WHERE session = ?1 AND at = ?2 AND rowid > ?3 ORDER BY rowid LIMIT ?4`;
export const MINUTE_SAME_END = `SELECT id, at, rowid FROM usage INDEXED BY usage_session
  WHERE session = ?1 AND at = ?2 AND rowid > ?3 AND rowid <= ?4 ORDER BY rowid LIMIT ?5`;
export const MINUTE_LAST_TIME = `SELECT id, at, rowid FROM usage INDEXED BY usage_session
  WHERE session = ?1 AND at = ?2 AND rowid <= ?3 ORDER BY rowid LIMIT ?4`;
export const PENDING_MINUTE_SESSION = `SELECT sc.session FROM usage_minute_scope sc INDEXED BY usage_minute_scope_ws
  WHERE sc.ws = ?1 AND sc.done = 0 LIMIT 1`;

/// Fill at most `limit` old calls of one session. A marker distinguishes newly written rows inside the saved range.
export function backfillUsageMinutes(db: DatabaseSync, session: string, limit = 32): Backfill {
  db.exec("BEGIN IMMEDIATE");
  try {
    db.prepare(`INSERT OR IGNORE INTO usage_minute_sessions
      SELECT ?1, NULL, NULL,
        (SELECT at FROM usage WHERE session = ?1 ORDER BY at DESC, rowid DESC LIMIT 1),
        (SELECT rowid FROM usage WHERE session = ?1 ORDER BY at DESC, rowid DESC LIMIT 1),
        NOT EXISTS (SELECT 1 FROM usage WHERE session = ?1 LIMIT 1)`).run(session);
    const state = db.prepare("SELECT after_at, after_rowid, end_at, end_rowid, done FROM usage_minute_sessions WHERE session = ?").get(session) as State;
    if (state.done) {
      db.exec("COMMIT");
      return { done: true, processed: 0 };
    }
    db.prepare(`INSERT INTO usage_minute_scope (session, ws, done)
      VALUES (?1, (SELECT ws FROM sessions WHERE key = ?1), 0) ON CONFLICT (session) DO UPDATE SET ws = excluded.ws, done = 0`).run(session);
    // Split the cursor's timestamp and the end timestamp from the interval between them. With many calls at exactly
    // one time, a tuple comparison can otherwise revisit all the earlier rowids on every batch.
    const rows: Source[] = [];
    const end = state.end_at!;
    if (state.after_at !== null) {
      const same = state.after_at === end
        ? db.prepare(MINUTE_SAME_END).all(session, state.after_at, state.after_rowid, state.end_rowid, limit)
        : db.prepare(MINUTE_SAME_TIME).all(session, state.after_at, state.after_rowid, limit);
      rows.push(...same as Source[]);
    }
    if (rows.length < limit && (state.after_at === null || state.after_at < end)) {
      const middle = state.after_at === null
        ? db.prepare(`SELECT id, at, rowid FROM usage INDEXED BY usage_session WHERE session = ?1 AND at < ?2 ORDER BY at, rowid LIMIT ?3`)
          .all(session, end, limit - rows.length)
        : db.prepare(`SELECT id, at, rowid FROM usage INDEXED BY usage_session WHERE session = ?1 AND at > ?2 AND at < ?3 ORDER BY at, rowid LIMIT ?4`)
          .all(session, state.after_at, end, limit - rows.length);
      rows.push(...middle as Source[]);
      if (rows.length < limit) rows.push(...db.prepare(MINUTE_LAST_TIME).all(session, end, state.end_rowid, limit - rows.length) as Source[]);
    }
    const unmark = db.prepare("DELETE FROM usage_minute_seen WHERE id = ?");
    const add = db.prepare(`INSERT INTO usage_minute
      SELECT u.session, ${MINUTE("u")}, u.runtime, COALESCE(u.model, ''), u.calls, ${TOKENS("u")} FROM usage u WHERE u.id = ?
      ON CONFLICT (session, minute, runtime, model) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`);
    const addQuarter = db.prepare(`INSERT INTO usage_day_quarters
      SELECT u.session, ${QUARTER("u")}, u.runtime, COALESCE(u.model, ''), u.calls, ${TOKENS("u")} FROM usage u WHERE u.id = ?
      ON CONFLICT (session, quarter, runtime, model) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`);
    for (const row of rows) if (unmark.run(row.id).changes === 0) {
      add.run(row.id);
      addQuarter.run(row.id);
    }
    const last = rows.at(-1);
    const done = rows.length < limit;
    db.prepare("UPDATE usage_minute_sessions SET after_at = ?, after_rowid = ?, done = ? WHERE session = ?")
      .run(last?.at ?? state.after_at, last?.rowid ?? state.after_rowid, done ? 1 : 0, session);
    if (done) db.prepare("UPDATE usage_minute_scope SET done = 1 WHERE session = ?").run(session);
    if (done) db.prepare("DELETE FROM usage_minute_scope WHERE session = ? AND NOT EXISTS (SELECT 1 FROM usage_minute WHERE session = ? LIMIT 1)").run(session, session);
    db.exec("COMMIT");
    return { done, processed: rows.length };
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

/// Discover one session and fill one bounded batch. The cursor survives a restart and new writes are already indexed.
export function backfillNextUsageSession(db: DatabaseSync, limit = 32): Backfill {
  const state = db.prepare("SELECT after_session, done FROM usage_minute_all WHERE id = 1").get() as { after_session: string | null; done: number };
  if (state.done) return { done: true, processed: 0 };
  const next = (state.after_session === null
    ? db.prepare("SELECT session FROM usage INDEXED BY usage_session ORDER BY session LIMIT 1").get()
    : db.prepare("SELECT session FROM usage INDEXED BY usage_session WHERE session > ? ORDER BY session LIMIT 1").get(state.after_session)) as { session: string } | undefined;
  if (!next) {
    db.prepare("UPDATE usage_minute_all SET done = 1 WHERE id = 1 AND after_session IS ?").run(state.after_session);
    return { done: (db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number }).done === 1, processed: 0 };
  }
  const step = backfillUsageMinutes(db, next.session, limit);
  if (step.done) db.prepare("UPDATE usage_minute_all SET after_session = ? WHERE id = 1 AND after_session IS ? AND done = 0").run(next.session, state.after_session);
  return { done: false, processed: step.processed };
}
