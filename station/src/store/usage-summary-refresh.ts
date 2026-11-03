// The session summaries written by an older station may need to be brought up to this station's format. The cursor
// makes that upgrade resumable; dirty sessions catch writes by a previous station during handover.
import type { DatabaseSync } from "node:sqlite";

const SCHEMA = `
CREATE TABLE usage_summary_refresh (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, after_key TEXT, done INTEGER NOT NULL);
-- FIFO: a session dirtied again after it is processed goes behind those already waiting.
CREATE TABLE usage_summary_dirty (session TEXT NOT NULL UNIQUE);

CREATE TRIGGER usage_summary_usage_before_add BEFORE INSERT ON usage BEGIN
  INSERT INTO usage_summary_dirty SELECT u.session FROM usage u WHERE u.id = NEW.id AND u.session <> NEW.session
    AND NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = u.session);
END;
CREATE TRIGGER usage_summary_usage_add AFTER INSERT ON usage BEGIN
  INSERT INTO usage_summary_dirty SELECT NEW.session WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = NEW.session);
END;
CREATE TRIGGER usage_summary_usage_change AFTER UPDATE ON usage BEGIN
  INSERT INTO usage_summary_dirty SELECT OLD.session WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = OLD.session);
  INSERT INTO usage_summary_dirty SELECT NEW.session WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = NEW.session);
END;
CREATE TRIGGER usage_summary_usage_drop AFTER DELETE ON usage BEGIN
  INSERT INTO usage_summary_dirty SELECT OLD.session WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = OLD.session);
END;
CREATE TRIGGER usage_summary_saved_add AFTER INSERT ON session_usage BEGIN
  INSERT INTO usage_summary_dirty SELECT NEW.session WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = NEW.session);
END;
CREATE TRIGGER usage_summary_saved_change AFTER UPDATE ON session_usage BEGIN
  INSERT INTO usage_summary_dirty SELECT NEW.session WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = NEW.session);
END;
CREATE TRIGGER usage_summary_saved_drop AFTER DELETE ON session_usage BEGIN
  INSERT INTO usage_summary_dirty SELECT OLD.session WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = OLD.session);
END;
CREATE TRIGGER usage_summary_conversation_change AFTER UPDATE OF runtime_session_id ON sessions
  WHEN OLD.runtime_session_id IS NOT NEW.runtime_session_id BEGIN
  INSERT INTO usage_summary_dirty SELECT NEW.key WHERE NOT EXISTS (SELECT 1 FROM usage_summary_dirty WHERE session = NEW.key);
END;
`;

/// Install empty bookkeeping and triggers without walking sessions or calls.
export function installUsageSummaryRefresh(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_refresh'").get() !== undefined;
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
