// Convert existing usage summaries to the year view in small transactions. The cursors and source-table triggers
// advance in the same database transaction, so a write is counted either by a trigger or when its row is visited.
import type { DatabaseSync } from "node:sqlite";

const qKey = (r: string) => `(${r}.session, ${r}.quarter, ${r}.runtime, ${r}.model)`;
const cKey = (r: string) => `(${r}.session, ${r}.minute, ${r}.thread, ${r}.person, ${r}.profile, ${r}.runtime, ${r}.model, ${r}.fast)`;
const qDone = (r: string) => `EXISTS (SELECT 1 FROM usage_history_transfer p WHERE p.id = 1 AND
  (p.phase > 0 OR (p.phase = 0 AND ${qKey(r)} <= (p.q_session, p.q_quarter, p.q_runtime, p.q_model))))`;
const cDone = (r: string) => `EXISTS (SELECT 1 FROM usage_history_transfer p WHERE p.id = 1 AND
  (p.phase > 1 OR (p.phase = 1 AND ${cKey(r)} <= (p.c_session, p.c_minute, p.c_thread, p.c_person, p.c_profile, p.c_runtime, p.c_model, p.c_fast))))`;
export const transferScope = (r: string) => `COALESCE((SELECT COALESCE(ws, '') FROM sessions WHERE key = ${r}.session),
  (SELECT scope FROM usage_history_orphans WHERE session = ${r}.session), '')`;
const compactQuarter = (r: string) => `(CASE WHEN ${r}.minute >= 0 THEN ${r}.minute / 15 ELSE -1 - ((-1 - ${r}.minute) / 15) END)`;
const compactTokens = (r: string) => `(${r}.input + ${r}.cache_read + ${r}.cache_write + ${r}.cache_write_long + ${r}.output)`;
const contribute = (r: string, period: string, calls: string, tokens: string, condition: string) => `
  INSERT INTO usage_history (scope, quarter, calls, tokens)
    SELECT ${transferScope(r)}, ${period}, ${calls}, ${tokens} WHERE ${condition}
    ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;`;
const qAdd = (r: string, sign: string) => contribute(r, `${r}.quarter`, `${sign}${r}.calls`, `${sign}${r}.tokens`, qDone(r));
const cAdd = (r: string, sign: string) => contribute(r, compactQuarter(r), `${sign}${r}.calls`, `${sign}${compactTokens(r)}`, cDone(r));

/// Called inside installation's write transaction, after compact usage has taken over the old writers.
export function installHistoryTransfer(db: DatabaseSync): void {
  db.exec(`
    CREATE TABLE usage_history_transfer (id INTEGER PRIMARY KEY CHECK (id = 1), phase INTEGER NOT NULL,
      q_session TEXT, q_quarter INTEGER, q_runtime TEXT, q_model TEXT,
      c_session TEXT, c_minute INTEGER, c_thread INTEGER, c_person TEXT, c_profile TEXT, c_runtime TEXT, c_model TEXT, c_fast INTEGER);
    INSERT INTO usage_history_transfer (id, phase) VALUES (1, 0);
    -- Remember the owner of a session deleted during conversion. Previously converted and later rows then stay together.
    CREATE TABLE usage_history_orphans (session TEXT PRIMARY KEY, scope TEXT NOT NULL) WITHOUT ROWID;
    CREATE INDEX usage_history_orphans_scope ON usage_history_orphans (scope, session);
    CREATE TRIGGER usage_history_transfer_owner BEFORE DELETE ON sessions
      WHEN EXISTS (SELECT 1 FROM usage_day_quarters WHERE session = OLD.key LIMIT 1)
        OR EXISTS (SELECT 1 FROM usage_compact WHERE session = OLD.key LIMIT 1) BEGIN
      INSERT INTO usage_history_orphans VALUES (OLD.key, COALESCE(OLD.ws, ''))
        ON CONFLICT (session) DO UPDATE SET scope = excluded.scope;
    END;
    CREATE TRIGGER usage_history_transfer_q_add AFTER INSERT ON usage_day_quarters BEGIN ${qAdd("NEW", "")} END;
    CREATE TRIGGER usage_history_transfer_q_change AFTER UPDATE OF session, quarter, runtime, model, calls, tokens ON usage_day_quarters BEGIN
      ${qAdd("OLD", "-")} ${qAdd("NEW", "")}
    END;
    CREATE TRIGGER usage_history_transfer_q_drop AFTER DELETE ON usage_day_quarters BEGIN ${qAdd("OLD", "-")} END;
    CREATE TRIGGER usage_history_transfer_c_add AFTER INSERT ON usage_compact BEGIN ${cAdd("NEW", "")} END;
    CREATE TRIGGER usage_history_transfer_c_change AFTER UPDATE OF session, minute, thread, person, profile, runtime, model, fast,
      calls, input, cache_read, cache_write, cache_write_long, output ON usage_compact BEGIN ${cAdd("OLD", "-")} ${cAdd("NEW", "")} END;
    CREATE TRIGGER usage_history_transfer_c_drop AFTER DELETE ON usage_compact BEGIN ${cAdd("OLD", "-")} END;
  `);
}

export const historyTransferPending = (db: DatabaseSync): boolean => db.prepare(
  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_history_transfer'",
).get() !== undefined;

type Progress = { phase: number; q_session: string | null; q_quarter: number; q_runtime: string; q_model: string;
  c_session: string | null; c_minute: number; c_thread: number; c_person: string; c_profile: string;
  c_runtime: string; c_model: string; c_fast: number };
type Quarter = { session: string; quarter: number; runtime: string; model: string; calls: number; tokens: number; scope: string };
type Compact = { session: string; minute: number; thread: number; person: string; profile: string; runtime: string; model: string;
  fast: number; quarter: number; calls: number; tokens: number; scope: string };

/// At most `batch` old summary rows are visited and written under one lock. `finish` installs the live usage triggers.
export function historyTransferStep(db: DatabaseSync, finish: () => void, batch = 64): boolean {
  if (!historyTransferPending(db)) return true;
  if (!Number.isSafeInteger(batch) || batch < 1) throw new RangeError("history conversion batch must be positive");
  batch = Math.min(batch, 64);
  db.exec("BEGIN IMMEDIATE");
  try {
    const p = db.prepare("SELECT * FROM usage_history_transfer WHERE id = 1").get() as Progress;
    const add = db.prepare(`INSERT INTO usage_history (scope, quarter, calls, tokens) VALUES (?, ?, ?, ?)
      ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`);
    if (p.phase === 0) {
      const after = p.q_session === null ? "" : `WHERE ${qKey("q")} > (?, ?, ?, ?)`;
      const args = p.q_session === null ? [batch] : [p.q_session, p.q_quarter, p.q_runtime, p.q_model, batch];
      const rows = db.prepare(`SELECT q.*, ${transferScope("q")} AS scope FROM usage_day_quarters q ${after}
        ORDER BY q.session, q.quarter, q.runtime, q.model LIMIT ?`).all(...args) as Quarter[];
      for (const row of rows) add.run(row.scope, row.quarter, row.calls, row.tokens);
      if (rows.length < batch) db.prepare("UPDATE usage_history_transfer SET phase = 1 WHERE id = 1").run();
      else {
        const last = rows[rows.length - 1]!;
        db.prepare("UPDATE usage_history_transfer SET q_session = ?, q_quarter = ?, q_runtime = ?, q_model = ? WHERE id = 1")
          .run(last.session, last.quarter, last.runtime, last.model);
      }
      db.exec("COMMIT");
      return false;
    }
    const after = p.c_session === null ? "" : `WHERE ${cKey("c")} > (?, ?, ?, ?, ?, ?, ?, ?)`;
    const args = p.c_session === null ? [batch] : [p.c_session, p.c_minute, p.c_thread, p.c_person, p.c_profile,
      p.c_runtime, p.c_model, p.c_fast, batch];
    const rows = db.prepare(`SELECT c.session, c.minute, c.thread, c.person, c.profile, c.runtime, c.model, c.fast,
      ${compactQuarter("c")} AS quarter, c.calls, ${compactTokens("c")} AS tokens, ${transferScope("c")} AS scope
      FROM usage_compact c ${after} ORDER BY c.session, c.minute, c.thread, c.person, c.profile, c.runtime, c.model, c.fast LIMIT ?`)
      .all(...args) as Compact[];
    for (const row of rows) add.run(row.scope, row.quarter, row.calls, row.tokens);
    if (rows.length < batch) {
      db.exec(`DROP TRIGGER usage_history_transfer_q_add; DROP TRIGGER usage_history_transfer_q_change;
        DROP TRIGGER usage_history_transfer_q_drop; DROP TRIGGER usage_history_transfer_c_add;
        DROP TRIGGER usage_history_transfer_c_change; DROP TRIGGER usage_history_transfer_c_drop;
        DROP TRIGGER usage_history_transfer_owner; DROP TABLE usage_history_transfer`);
      finish();
      db.exec("COMMIT");
      return true;
    }
    const last = rows[rows.length - 1]!;
    db.prepare(`UPDATE usage_history_transfer SET c_session = ?, c_minute = ?, c_thread = ?, c_person = ?, c_profile = ?,
      c_runtime = ?, c_model = ?, c_fast = ? WHERE id = 1`).run(last.session, last.minute, last.thread, last.person,
      last.profile, last.runtime, last.model, last.fast);
    db.exec("COMMIT");
    return false;
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
