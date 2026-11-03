// Counts for the usage history: one contribution per visible chat, rather than a walk over chats and cards each time.
// Old rows are added in bounded background batches. Triggers include writes from an older station during the fill.
import type { DatabaseSync } from "node:sqlite";
import type { InWorkspace } from "./rows.ts";

const place = (row: string) => `CASE WHEN instr(${row}.surface, ':') = 0 THEN ${row}.surface
  ELSE substr(${row}.surface, 1, instr(${row}.surface, ':') - 1) END`;

// A card or membership can arrive before its old thread has been visited, or after a thread has gone. A placeholder
// contributes its cards to the unscoped total and becomes a normal chat if the thread appears later.
// Use an existence check instead of OR IGNORE: SQLite applies an outer INSERT OR REPLACE's conflict policy inside
// triggers, which would otherwise replace an existing summary and lose its accumulated cards.
const ensure = (thread: string) => `INSERT INTO usage_chat_stats
  SELECT ${thread}, CASE WHEN t.id IS NULL THEN '' ELSE ${place("t")} END, t.id IS NOT NULL,
    t.id IS NOT NULL AND t.hidden_at IS NOT NULL, 0, 0
  FROM (SELECT 1) LEFT JOIN threads t ON t.id = ${thread}
  WHERE NOT EXISTS (SELECT 1 FROM usage_chat_stats WHERE thread = ${thread});`;

// Scope 0 is every chat, 1 the home contribution (null-workspace members and orphan chats), 2 one workspace, and 3
// the overlap of that workspace and home. A home viewer adds 1 and 2 and subtracts 3, so a shared chat counts once.
const refresh = (thread: string, when = "1") => `
  DELETE FROM usage_chat_scopes WHERE thread = ${thread} AND (${when});
  INSERT OR IGNORE INTO usage_chat_scopes SELECT thread, 0, '' FROM usage_chat_stats WHERE thread = ${thread} AND (${when});
  INSERT OR IGNORE INTO usage_chat_scopes SELECT thread, 1, '' FROM usage_chat_stats s WHERE s.thread = ${thread} AND s.live = 1 AND (${when})
    AND (NOT EXISTS (SELECT 1 FROM usage_chat_members m WHERE m.thread = s.thread)
      OR EXISTS (SELECT 1 FROM usage_chat_members m WHERE m.thread = s.thread AND m.present = 1 AND m.ws IS NULL));
  INSERT OR IGNORE INTO usage_chat_scopes SELECT m.thread, 2, m.ws FROM usage_chat_members m
    WHERE m.thread = ${thread} AND m.present = 1 AND m.ws IS NOT NULL AND (${when})
      AND EXISTS (SELECT 1 FROM usage_chat_stats s WHERE s.thread = m.thread AND s.live = 1) GROUP BY m.thread, m.ws;
  INSERT OR IGNORE INTO usage_chat_scopes SELECT m.thread, 3, m.ws FROM usage_chat_members m
    WHERE m.thread = ${thread} AND m.present = 1 AND m.ws IS NOT NULL AND (${when})
      AND EXISTS (SELECT 1 FROM usage_chat_scopes s WHERE s.thread = m.thread AND s.kind = 1 AND s.ws = '') GROUP BY m.thread, m.ws;`;

// Joining another session should only change its own workspace's contribution. Home visibility can also change when
// the first/last home member comes or goes; only then must the overlap of the affected shared chat be updated.
const isHome = (thread: string) => `EXISTS (SELECT 1 FROM usage_chat_stats s WHERE s.thread = ${thread} AND s.live = 1)
  AND (NOT EXISTS (SELECT 1 FROM usage_chat_members m WHERE m.thread = ${thread}) OR EXISTS
    (SELECT 1 FROM usage_chat_members m WHERE m.thread = ${thread} AND m.present = 1 AND m.ws IS NULL))`;
const homeScope = (thread: string) => `EXISTS (SELECT 1 FROM usage_chat_scopes WHERE thread = ${thread} AND kind = 1 AND ws = '')`;
const refreshHome = (thread: string) => `
  DELETE FROM usage_chat_scopes WHERE thread = ${thread} AND kind = 3
    AND ${homeScope(thread)} AND NOT (${isHome(thread)});
  DELETE FROM usage_chat_scopes WHERE thread = ${thread} AND kind = 1 AND ws = '' AND NOT (${isHome(thread)});
  INSERT OR IGNORE INTO usage_chat_scopes SELECT thread, 3, ws FROM usage_chat_scopes
    WHERE thread = ${thread} AND kind = 2 AND (${isHome(thread)}) AND NOT (${homeScope(thread)});
  INSERT OR IGNORE INTO usage_chat_scopes SELECT thread, 1, '' FROM usage_chat_stats
    WHERE thread = ${thread} AND (${isHome(thread)});`;
const addMemberScope = (row: string) => `
  INSERT INTO usage_chat_scopes SELECT s.thread, 2, ${row}.ws FROM usage_chat_stats s
    WHERE s.thread = ${row}.thread AND s.live = 1 AND ${row}.present = 1 AND ${row}.ws IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM usage_chat_scopes x WHERE x.thread = s.thread AND x.kind = 2 AND x.ws = ${row}.ws);
  INSERT INTO usage_chat_scopes SELECT s.thread, 3, ${row}.ws FROM usage_chat_stats s
    WHERE s.thread = ${row}.thread AND s.live = 1 AND ${row}.present = 1 AND ${row}.ws IS NOT NULL
      AND ${homeScope(`${row}.thread`)}
      AND NOT EXISTS (SELECT 1 FROM usage_chat_scopes x WHERE x.thread = s.thread AND x.kind = 3 AND x.ws = ${row}.ws);`;
const removeMemberScope = (row: string) => `
  DELETE FROM usage_chat_scopes WHERE thread = ${row}.thread AND kind IN (2, 3) AND ws = ${row}.ws
    AND ${row}.present = 1 AND ${row}.ws IS NOT NULL AND NOT EXISTS
      (SELECT 1 FROM usage_chat_members m WHERE m.thread = ${row}.thread AND m.present = 1 AND m.ws = ${row}.ws);`;

const keepMember = (row: string) => `
  ${ensure(`${row}.thread`)}
  INSERT INTO usage_chat_members VALUES (${row}.thread, ${row}.session,
    (SELECT ws FROM sessions WHERE key = ${row}.session), EXISTS (SELECT 1 FROM sessions WHERE key = ${row}.session))
  ON CONFLICT (thread, session) DO UPDATE SET ws = excluded.ws, present = excluded.present;`;
const picked = (row: string) => `(${row}.said != 0 OR EXISTS (SELECT 1 FROM closed_cards x
  WHERE x.thread = ${row}.thread AND x.n = ${row}.n AND x.viewer != ${row}.author))`;
const keepCard = (row: string) => `
  ${ensure(`${row}.thread`)}
  INSERT INTO usage_chat_cards VALUES (${row}.thread, ${row}.n, ${picked(row)})
  ON CONFLICT (thread, n) DO UPDATE SET picked = excluded.picked;`;
const recheckCard = (row: string) => `UPDATE usage_chat_cards SET picked = COALESCE((
  SELECT ${picked("c")} FROM card_outcomes c WHERE c.thread = ${row}.thread AND c.n = ${row}.n), 0)
  WHERE thread = ${row}.thread AND n = ${row}.n;`;
const dirtySession = (session: string, workspace: string, when = "1") => `
  INSERT INTO usage_chat_dirty SELECT ${session}, NULL
    WHERE (${when}) AND EXISTS (SELECT 1 FROM usage_chat_members WHERE session = ${session})
  ON CONFLICT (session) DO UPDATE SET thread_after = NULL;
  INSERT OR IGNORE INTO usage_chat_dirty_scope
    SELECT ${session}, CASE WHEN ${workspace} IS NULL THEN 1 ELSE 2 END, COALESCE(${workspace}, '')
    WHERE (${when}) AND EXISTS (SELECT 1 FROM usage_chat_dirty WHERE session = ${session});`;
// An older writer can replace a session without firing a delete trigger. Its indexed memberships still remember the
// previous workspace, so that workspace must wait too; earlier unfinished moves have already recorded their scopes.
const dirtyPrevious = (session: string) => `INSERT OR IGNORE INTO usage_chat_dirty_scope
  SELECT ${session}, CASE WHEN ws IS NULL THEN 1 ELSE 2 END, COALESCE(ws, '')
  FROM usage_chat_members INDEXED BY usage_chat_members_session_present
  WHERE session = ${session} AND present = 1 ORDER BY thread LIMIT 1;`;

const SCHEMA = `
CREATE TABLE usage_chat_stats (thread INTEGER PRIMARY KEY, place TEXT NOT NULL, live INTEGER NOT NULL,
  archived INTEGER NOT NULL, cards INTEGER NOT NULL, picked INTEGER NOT NULL);
CREATE TABLE usage_chat_members (thread INTEGER NOT NULL, session TEXT NOT NULL, ws TEXT, present INTEGER NOT NULL,
  PRIMARY KEY (thread, session)) WITHOUT ROWID;
CREATE INDEX usage_chat_members_session ON usage_chat_members (session, thread);
CREATE INDEX usage_chat_members_session_present ON usage_chat_members (session, present, thread);
CREATE INDEX usage_chat_members_workspace ON usage_chat_members (thread, present, ws);
CREATE TABLE usage_chat_cards (thread INTEGER NOT NULL, n INTEGER NOT NULL, picked INTEGER NOT NULL,
  PRIMARY KEY (thread, n)) WITHOUT ROWID;
CREATE TABLE usage_chat_dirty (session TEXT PRIMARY KEY, thread_after INTEGER) WITHOUT ROWID;
CREATE TABLE usage_chat_dirty_scope (session TEXT NOT NULL, kind INTEGER NOT NULL, ws TEXT NOT NULL,
  PRIMARY KEY (session, kind, ws)) WITHOUT ROWID;
CREATE INDEX usage_chat_dirty_scope_workspace ON usage_chat_dirty_scope (kind, ws, session);
CREATE TABLE usage_chat_scopes (thread INTEGER NOT NULL, kind INTEGER NOT NULL, ws TEXT NOT NULL,
  PRIMARY KEY (thread, kind, ws)) WITHOUT ROWID;
CREATE TABLE usage_chat_totals (kind INTEGER NOT NULL, ws TEXT NOT NULL, place TEXT NOT NULL,
  chats INTEGER NOT NULL, archived INTEGER NOT NULL, cards INTEGER NOT NULL, picked INTEGER NOT NULL,
  PRIMARY KEY (kind, ws, place)) WITHOUT ROWID;
CREATE TABLE usage_chat_progress (id INTEGER PRIMARY KEY CHECK (id = 1), stage INTEGER NOT NULL,
  thread_after INTEGER, thread_end INTEGER, member_after INTEGER, member_end INTEGER,
  card_thread INTEGER, card_n INTEGER, card_end_thread INTEGER, card_end_n INTEGER, done INTEGER NOT NULL);
INSERT INTO usage_chat_progress
  SELECT 1, 0, NULL, (SELECT MAX(id) FROM threads), NULL, (SELECT MAX(rowid) FROM thread_sessions), NULL, NULL,
    (SELECT thread FROM card_outcomes ORDER BY thread DESC, n DESC LIMIT 1),
    (SELECT n FROM card_outcomes ORDER BY thread DESC, n DESC LIMIT 1),
    NOT EXISTS (SELECT 1 FROM threads LIMIT 1) AND NOT EXISTS (SELECT 1 FROM thread_sessions LIMIT 1)
      AND NOT EXISTS (SELECT 1 FROM card_outcomes LIMIT 1);

CREATE TRIGGER usage_chat_scope_add AFTER INSERT ON usage_chat_scopes BEGIN
  INSERT INTO usage_chat_totals SELECT NEW.kind, NEW.ws, s.place, s.live, s.live * s.archived, s.cards, s.picked
    FROM usage_chat_stats s WHERE s.thread = NEW.thread
  ON CONFLICT (kind, ws, place) DO UPDATE SET chats = chats + excluded.chats, archived = archived + excluded.archived,
    cards = cards + excluded.cards, picked = picked + excluded.picked;
END;
CREATE TRIGGER usage_chat_scope_drop AFTER DELETE ON usage_chat_scopes BEGIN
  UPDATE usage_chat_totals SET
    chats = chats - (SELECT live FROM usage_chat_stats WHERE thread = OLD.thread),
    archived = archived - (SELECT live * archived FROM usage_chat_stats WHERE thread = OLD.thread),
    cards = cards - (SELECT cards FROM usage_chat_stats WHERE thread = OLD.thread),
    picked = picked - (SELECT picked FROM usage_chat_stats WHERE thread = OLD.thread)
    WHERE kind = OLD.kind AND ws = OLD.ws AND place = (SELECT place FROM usage_chat_stats WHERE thread = OLD.thread);
  DELETE FROM usage_chat_totals WHERE kind = OLD.kind AND ws = OLD.ws
    AND place = (SELECT place FROM usage_chat_stats WHERE thread = OLD.thread)
    AND chats = 0 AND archived = 0 AND cards = 0 AND picked = 0;
END;
CREATE TRIGGER usage_chat_stats_add AFTER INSERT ON usage_chat_stats BEGIN ${refresh("NEW.thread")} END;
CREATE TRIGGER usage_chat_stats_before BEFORE UPDATE ON usage_chat_stats
  WHEN OLD.place IS NOT NEW.place OR OLD.live IS NOT NEW.live OR OLD.archived IS NOT NEW.archived
    OR OLD.cards IS NOT NEW.cards OR OLD.picked IS NOT NEW.picked BEGIN
  UPDATE usage_chat_totals SET chats = chats - OLD.live, archived = archived - OLD.live * OLD.archived,
    cards = cards - OLD.cards, picked = picked - OLD.picked WHERE place = OLD.place AND (kind, ws) IN
      (SELECT kind, ws FROM usage_chat_scopes WHERE thread = OLD.thread);
  DELETE FROM usage_chat_totals WHERE place = OLD.place AND (kind, ws) IN
    (SELECT kind, ws FROM usage_chat_scopes WHERE thread = OLD.thread)
    AND chats = 0 AND archived = 0 AND cards = 0 AND picked = 0;
END;
CREATE TRIGGER usage_chat_stats_after AFTER UPDATE ON usage_chat_stats
  WHEN OLD.place IS NOT NEW.place OR OLD.live IS NOT NEW.live OR OLD.archived IS NOT NEW.archived
    OR OLD.cards IS NOT NEW.cards OR OLD.picked IS NOT NEW.picked BEGIN
  INSERT INTO usage_chat_totals SELECT s.kind, s.ws, NEW.place, NEW.live, NEW.live * NEW.archived, NEW.cards, NEW.picked
    FROM usage_chat_scopes s WHERE s.thread = NEW.thread
  ON CONFLICT (kind, ws, place) DO UPDATE SET chats = chats + excluded.chats, archived = archived + excluded.archived,
    cards = cards + excluded.cards, picked = picked + excluded.picked;
  ${refresh("NEW.thread", "OLD.live IS NOT NEW.live")}
END;
CREATE TRIGGER usage_chat_stats_drop BEFORE DELETE ON usage_chat_stats BEGIN
  DELETE FROM usage_chat_scopes WHERE thread = OLD.thread;
END;

CREATE TRIGGER usage_chat_thread_add AFTER INSERT ON threads BEGIN
  INSERT INTO usage_chat_stats VALUES (NEW.id, ${place("NEW")}, 1, NEW.hidden_at IS NOT NULL, 0, 0)
  ON CONFLICT (thread) DO UPDATE SET place = excluded.place, live = 1, archived = excluded.archived;
END;
CREATE TRIGGER usage_chat_thread_change AFTER UPDATE OF surface, hidden_at ON threads BEGIN
  INSERT INTO usage_chat_stats VALUES (NEW.id, ${place("NEW")}, 1, NEW.hidden_at IS NOT NULL, 0, 0)
  ON CONFLICT (thread) DO UPDATE SET place = excluded.place, live = 1, archived = excluded.archived;
END;
CREATE TRIGGER usage_chat_thread_drop AFTER DELETE ON threads BEGIN
  UPDATE usage_chat_stats SET place = '', live = 0, archived = 0 WHERE thread = OLD.id;
  DELETE FROM usage_chat_stats WHERE thread = OLD.id AND cards = 0
    AND NOT EXISTS (SELECT 1 FROM usage_chat_members WHERE thread = OLD.id);
END;

CREATE TRIGGER usage_chat_member_add AFTER INSERT ON usage_chat_members BEGIN
  ${addMemberScope("NEW")}
END;
CREATE TRIGGER usage_chat_member_change AFTER UPDATE ON usage_chat_members
  WHEN OLD.ws IS NOT NEW.ws OR OLD.present IS NOT NEW.present BEGIN
  ${removeMemberScope("OLD")}
  ${addMemberScope("NEW")}
END;
CREATE TRIGGER usage_chat_member_drop AFTER DELETE ON usage_chat_members BEGIN
  ${removeMemberScope("OLD")}
  DELETE FROM usage_chat_stats WHERE thread = OLD.thread AND live = 0 AND cards = 0
    AND NOT EXISTS (SELECT 1 FROM usage_chat_members WHERE thread = OLD.thread);
END;
CREATE TRIGGER usage_chat_member_home_add AFTER INSERT ON usage_chat_members
  WHEN (${isHome("NEW.thread")}) != (${homeScope("NEW.thread")}) BEGIN ${refreshHome("NEW.thread")} END;
CREATE TRIGGER usage_chat_member_home_change AFTER UPDATE ON usage_chat_members
  WHEN (OLD.ws IS NOT NEW.ws OR OLD.present IS NOT NEW.present)
    AND (${isHome("NEW.thread")}) != (${homeScope("NEW.thread")}) BEGIN ${refreshHome("NEW.thread")} END;
CREATE TRIGGER usage_chat_member_home_drop AFTER DELETE ON usage_chat_members
  WHEN (${isHome("OLD.thread")}) != (${homeScope("OLD.thread")}) BEGIN ${refreshHome("OLD.thread")} END;
CREATE TRIGGER usage_chat_membership_add AFTER INSERT ON thread_sessions BEGIN ${keepMember("NEW")} END;
CREATE TRIGGER usage_chat_membership_change AFTER UPDATE ON thread_sessions BEGIN
  DELETE FROM usage_chat_members WHERE thread = OLD.thread AND session = OLD.session
    AND (OLD.thread IS NOT NEW.thread OR OLD.session IS NOT NEW.session);
  ${keepMember("NEW")}
END;
CREATE TRIGGER usage_chat_membership_drop AFTER DELETE ON thread_sessions BEGIN
  DELETE FROM usage_chat_members WHERE thread = OLD.thread AND session = OLD.session;
END;
-- REPLACE may also evict another session through the unique token, without firing its DELETE trigger.
CREATE TRIGGER usage_chat_session_token_add BEFORE INSERT ON sessions
  WHEN EXISTS (SELECT 1 FROM sessions WHERE token = NEW.token AND key <> NEW.key) BEGIN
  ${dirtySession("(SELECT key FROM sessions WHERE token = NEW.token)", "(SELECT ws FROM sessions WHERE token = NEW.token)")}
END;
CREATE TRIGGER usage_chat_session_token_change BEFORE UPDATE OF token ON sessions
  WHEN OLD.token IS NOT NEW.token AND EXISTS (SELECT 1 FROM sessions WHERE token = NEW.token AND key <> NEW.key) BEGIN
  ${dirtySession("(SELECT key FROM sessions WHERE token = NEW.token)", "(SELECT ws FROM sessions WHERE token = NEW.token)")}
END;
CREATE TRIGGER usage_chat_session_add AFTER INSERT ON sessions BEGIN
  ${dirtyPrevious("NEW.key")}
  ${dirtySession("NEW.key", "NEW.ws")}
END;
CREATE TRIGGER usage_chat_session_change AFTER UPDATE OF key, ws ON sessions
  WHEN OLD.key IS NOT NEW.key OR OLD.ws IS NOT NEW.ws BEGIN
  ${dirtySession("OLD.key", "OLD.ws")}
  ${dirtySession("NEW.key", "NEW.ws")}
END;
CREATE TRIGGER usage_chat_session_drop AFTER DELETE ON sessions BEGIN
  ${dirtySession("OLD.key", "OLD.ws")}
END;

CREATE TRIGGER usage_chat_card_add AFTER INSERT ON usage_chat_cards BEGIN
  UPDATE usage_chat_stats SET cards = cards + 1, picked = picked + NEW.picked WHERE thread = NEW.thread;
END;
CREATE TRIGGER usage_chat_card_change AFTER UPDATE OF picked ON usage_chat_cards WHEN OLD.picked IS NOT NEW.picked BEGIN
  UPDATE usage_chat_stats SET picked = picked + NEW.picked - OLD.picked WHERE thread = NEW.thread;
END;
CREATE TRIGGER usage_chat_card_drop AFTER DELETE ON usage_chat_cards BEGIN
  UPDATE usage_chat_stats SET cards = cards - 1, picked = picked - OLD.picked WHERE thread = OLD.thread;
  DELETE FROM usage_chat_stats WHERE thread = OLD.thread AND live = 0 AND cards = 0
    AND NOT EXISTS (SELECT 1 FROM usage_chat_members WHERE thread = OLD.thread);
END;
CREATE TRIGGER usage_chat_outcome_add AFTER INSERT ON card_outcomes BEGIN ${keepCard("NEW")} END;
CREATE TRIGGER usage_chat_outcome_change AFTER UPDATE ON card_outcomes BEGIN
  DELETE FROM usage_chat_cards WHERE thread = OLD.thread AND n = OLD.n AND (OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n);
  ${keepCard("NEW")}
END;
CREATE TRIGGER usage_chat_outcome_drop AFTER DELETE ON card_outcomes BEGIN
  DELETE FROM usage_chat_cards WHERE thread = OLD.thread AND n = OLD.n;
END;
CREATE TRIGGER usage_chat_closed_add AFTER INSERT ON closed_cards BEGIN ${recheckCard("NEW")} END;
CREATE TRIGGER usage_chat_closed_change AFTER UPDATE ON closed_cards BEGIN ${recheckCard("OLD")} ${recheckCard("NEW")} END;
CREATE TRIGGER usage_chat_closed_drop AFTER DELETE ON closed_cards BEGIN ${recheckCard("OLD")} END;
`;

/// Create only empty statistics and triggers; old histories are never scanned while the station opens.
export function installUsageChatStats(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_chat_progress'").get() !== undefined;
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

/// A moved session holds only its old and new workspaces. A home move also affects all home views.
export function usageChatStatsReady(db: DatabaseSync, viewer: InWorkspace | null): boolean {
  if ((db.prepare("SELECT done FROM usage_chat_progress WHERE id = 1").get() as { done: number } | undefined)?.done !== 1) return false;
  if (viewer === null) return db.prepare("SELECT 1 FROM usage_chat_dirty LIMIT 1").get() === undefined;
  if (db.prepare("SELECT 1 FROM usage_chat_dirty_scope WHERE kind = 2 AND ws = ? LIMIT 1").get(viewer.workspace)) return false;
  return viewer.home === false || db.prepare("SELECT 1 FROM usage_chat_dirty_scope WHERE kind = 1 AND ws = '' LIMIT 1").get() === undefined;
}

type Progress = { stage: number; thread_after: number | null; thread_end: number | null; member_after: number | null;
  member_end: number | null; card_thread: number | null; card_n: number | null; card_end_thread: number | null;
  card_end_n: number | null; done: number };

/// Copy at most `limit` old objects. The cursor and their contributions commit together; a concurrent write is already
/// represented by the triggers, so INSERT OR IGNORE never counts it a second time.
export function backfillUsageChatStats(db: DatabaseSync, limit = 32): { done: boolean; processed: number } {
  db.exec("BEGIN IMMEDIATE");
  try {
    const state = db.prepare("SELECT * FROM usage_chat_progress WHERE id = 1").get() as Progress;
    const dirty = db.prepare("SELECT session, thread_after FROM usage_chat_dirty ORDER BY session LIMIT 1").get() as
      { session: string; thread_after: number | null } | undefined;
    if (dirty) {
      const session = db.prepare("SELECT ws FROM sessions WHERE key = ?").get(dirty.session) as { ws: string | null } | undefined;
      const rows = (dirty.thread_after === null
        ? db.prepare("SELECT thread FROM usage_chat_members INDEXED BY usage_chat_members_session WHERE session = ? ORDER BY thread LIMIT ?").all(dirty.session, limit)
        : db.prepare("SELECT thread FROM usage_chat_members INDEXED BY usage_chat_members_session WHERE session = ? AND thread > ? ORDER BY thread LIMIT ?").all(dirty.session, dirty.thread_after, limit)) as { thread: number }[];
      const update = db.prepare("UPDATE usage_chat_members SET ws = ?, present = ? WHERE session = ? AND thread = ? AND (ws IS NOT ? OR present IS NOT ?)");
      const ws = session?.ws ?? null, present = session === undefined ? 0 : 1;
      for (const row of rows) update.run(ws, present, dirty.session, row.thread, ws, present);
      if (rows.length < limit) {
        db.prepare("DELETE FROM usage_chat_dirty_scope WHERE session = ?").run(dirty.session);
        db.prepare("DELETE FROM usage_chat_dirty WHERE session = ?").run(dirty.session);
      } else db.prepare("UPDATE usage_chat_dirty SET thread_after = ? WHERE session = ?").run(rows.at(-1)!.thread, dirty.session);
      const done = state.done === 1 && db.prepare("SELECT 1 FROM usage_chat_dirty LIMIT 1").get() === undefined;
      db.exec("COMMIT");
      return { done, processed: rows.length };
    }
    if (state.done) { db.exec("COMMIT"); return { done: true, processed: 0 }; }
    let processed = 0;
    if (state.stage === 0) {
      const rows = (state.thread_end === null ? [] : state.thread_after === null
        ? db.prepare("SELECT id, surface, hidden_at FROM threads WHERE id <= ? ORDER BY id LIMIT ?").all(state.thread_end, limit)
        : db.prepare("SELECT id, surface, hidden_at FROM threads WHERE id > ? AND id <= ? ORDER BY id LIMIT ?").all(state.thread_after, state.thread_end, limit)) as
        { id: number; surface: string; hidden_at: number | null }[];
      const insert = db.prepare("INSERT OR IGNORE INTO usage_chat_stats VALUES (?, ?, 1, ?, 0, 0)");
      for (const row of rows) insert.run(row.id, row.surface.split(":")[0] ?? row.surface, row.hidden_at === null ? 0 : 1);
      processed = rows.length;
      db.prepare("UPDATE usage_chat_progress SET thread_after = ?, stage = ? WHERE id = 1")
        .run(rows.at(-1)?.id ?? state.thread_after, rows.length < limit ? 1 : 0);
    } else if (state.stage === 1) {
      const rows = (state.member_end === null ? [] : state.member_after === null
        ? db.prepare("SELECT rowid AS seq, thread, session FROM thread_sessions WHERE rowid <= ? ORDER BY rowid LIMIT ?").all(state.member_end, limit)
        : db.prepare("SELECT rowid AS seq, thread, session FROM thread_sessions WHERE rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?").all(state.member_after, state.member_end, limit)) as
        { seq: number; thread: number; session: string }[];
      const addThread = db.prepare(`INSERT OR IGNORE INTO usage_chat_stats
        SELECT ?1, CASE WHEN t.id IS NULL THEN '' ELSE ${place("t")} END, t.id IS NOT NULL,
          t.id IS NOT NULL AND t.hidden_at IS NOT NULL, 0, 0 FROM (SELECT 1) LEFT JOIN threads t ON t.id = ?1`);
      const insert = db.prepare(`INSERT OR IGNORE INTO usage_chat_members VALUES (?1, ?2,
        (SELECT ws FROM sessions WHERE key = ?2), EXISTS (SELECT 1 FROM sessions WHERE key = ?2))`);
      for (const row of rows) { addThread.run(row.thread); insert.run(row.thread, row.session); }
      processed = rows.length;
      db.prepare("UPDATE usage_chat_progress SET member_after = ?, stage = ? WHERE id = 1")
        .run(rows.at(-1)?.seq ?? state.member_after, rows.length < limit ? 2 : 1);
    } else {
      const rows = (state.card_end_thread === null ? [] : state.card_thread === null
        ? db.prepare(`SELECT thread, n FROM card_outcomes WHERE (thread, n) <= (?, ?) ORDER BY thread, n LIMIT ?`)
          .all(state.card_end_thread, state.card_end_n, limit)
        : db.prepare(`SELECT thread, n FROM card_outcomes WHERE (thread, n) > (?, ?) AND (thread, n) <= (?, ?) ORDER BY thread, n LIMIT ?`)
          .all(state.card_thread, state.card_n, state.card_end_thread, state.card_end_n, limit)) as { thread: number; n: number }[];
      const addThread = db.prepare(`INSERT OR IGNORE INTO usage_chat_stats
        SELECT ?1, CASE WHEN t.id IS NULL THEN '' ELSE ${place("t")} END, t.id IS NOT NULL,
          t.id IS NOT NULL AND t.hidden_at IS NOT NULL, 0, 0 FROM (SELECT 1) LEFT JOIN threads t ON t.id = ?1`);
      const insert = db.prepare(`INSERT OR IGNORE INTO usage_chat_cards
        SELECT c.thread, c.n, ${picked("c")} FROM card_outcomes c WHERE c.thread = ? AND c.n = ?`);
      for (const row of rows) { addThread.run(row.thread); insert.run(row.thread, row.n); }
      processed = rows.length;
      const last = rows.at(-1);
      db.prepare("UPDATE usage_chat_progress SET card_thread = ?, card_n = ?, done = ? WHERE id = 1")
        .run(last?.thread ?? state.card_thread, last?.n ?? state.card_n, rows.length < limit ? 1 : 0);
    }
    const done = (db.prepare("SELECT done FROM usage_chat_progress WHERE id = 1").get() as { done: number }).done === 1;
    db.exec("COMMIT");
    return { done, processed };
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}
