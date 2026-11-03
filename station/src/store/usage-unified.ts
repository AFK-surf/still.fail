// The detailed buckets hold exact minutes. Keep the compact daily quarters as a projection of them, and stop writing
// the duplicate legacy quarter and minute summaries once the previous process has exited.
import type { DatabaseSync } from "node:sqlite";
import { usageDetailGeneration, usageDetailReady } from "./usage-detail.ts";

export function retireDuplicateUsage(db: DatabaseSync): boolean {
  const retired = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_history_from_detail'").get() !== undefined;
  const ready = () => usageDetailGeneration(db) === "legacy" && usageDetailReady(db, null, "legacy")
    && (db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number } | undefined)?.done === 1;
  if (retired()) return true;
  // Neither a partially built detail index nor partial old quarters can represent a complete history.
  if (!ready()) return false;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!retired() && ready()) {
      db.exec(`DROP TRIGGER IF EXISTS usage_quarters_add; DROP TRIGGER IF EXISTS usage_quarters_drop; DROP TRIGGER IF EXISTS usage_quarters_grow;
        DROP TRIGGER IF EXISTS usage_minute_add; DROP TRIGGER IF EXISTS usage_minute_drop; DROP TRIGGER IF EXISTS usage_minute_grow;
        CREATE TRIGGER usage_daily_detail_add AFTER INSERT ON usage_detail WHEN NEW.level = 0 BEGIN
          INSERT INTO usage_day_quarters VALUES (NEW.session, NEW.bucket, NEW.runtime, NEW.model, NEW.calls,
            NEW.input + NEW.cache_read + NEW.cache_write + NEW.cache_write_long + NEW.output)
            ON CONFLICT (session, quarter, runtime, model) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens;
        END;
        CREATE TRIGGER usage_daily_detail_drop AFTER DELETE ON usage_detail WHEN OLD.level = 0 BEGIN
          UPDATE usage_day_quarters SET calls = calls - OLD.calls,
            tokens = tokens - OLD.input - OLD.cache_read - OLD.cache_write - OLD.cache_write_long - OLD.output
            WHERE session = OLD.session AND quarter = OLD.bucket AND runtime = OLD.runtime AND model = OLD.model;
          DELETE FROM usage_day_quarters WHERE session = OLD.session AND quarter = OLD.bucket AND runtime = OLD.runtime AND model = OLD.model
            AND calls = 0 AND tokens = 0;
        END;
        CREATE TRIGGER usage_daily_detail_change AFTER UPDATE OF calls, input, cache_read, cache_write, cache_write_long, output ON usage_detail
          WHEN NEW.level = 0 BEGIN
          UPDATE usage_day_quarters SET calls = calls + NEW.calls - OLD.calls,
            tokens = tokens + NEW.input - OLD.input + NEW.cache_read - OLD.cache_read + NEW.cache_write - OLD.cache_write
              + NEW.cache_write_long - OLD.cache_write_long + NEW.output - OLD.output
            WHERE session = NEW.session AND quarter = NEW.bucket AND runtime = NEW.runtime AND model = NEW.model;
        END;
        CREATE TABLE usage_history_from_detail (id INTEGER PRIMARY KEY CHECK (id = 1));
        INSERT INTO usage_history_from_detail VALUES (1);`);
    }
    db.exec("COMMIT");
    return retired();
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
