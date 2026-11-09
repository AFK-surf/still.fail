import type { DatabaseSync } from "node:sqlite";

// A station from before sidebar said-state kept these columns and this writer, but had no message index.
export function withoutSaidState(old: DatabaseSync): void {
  old.exec(`DROP TRIGGER said_state_before_insert; DROP TRIGGER said_state_before_update;
    DROP TRIGGER said_state_before_delete; DROP TRIGGER thread_state_add; DROP TABLE said_state_guard;
    ALTER TABLE thread_state DROP COLUMN said_other_n; ALTER TABLE thread_state DROP COLUMN said_other_known;
    CREATE TRIGGER thread_state_add AFTER INSERT ON entries BEGIN
      INSERT INTO thread_state VALUES (NEW.thread,NEW.n,
        CASE WHEN NEW.kind='message' AND NEW.letter IS NULL THEN NEW.n END,
        CASE WHEN NEW.kind='message' AND NEW.author_kind='person' THEN NEW.n END,
        CASE WHEN NEW.kind='message' AND NEW.letter IS NOT NULL THEN 1 ELSE 0 END)
      ON CONFLICT(thread) DO UPDATE SET last_n=MAX(last_n,excluded.last_n),
        said_n=CASE WHEN excluded.said_n IS NULL THEN said_n WHEN said_n IS NULL THEN excluded.said_n ELSE MAX(said_n,excluded.said_n) END,
        person_n=CASE WHEN excluded.person_n IS NULL THEN person_n WHEN person_n IS NULL THEN excluded.person_n ELSE MIN(person_n,excluded.person_n) END,
        letters=letters+excluded.letters;
      INSERT INTO thread_people SELECT NEW.thread,NEW.author,NEW.n WHERE NEW.kind='message' AND NEW.author_kind='person'
        ON CONFLICT(thread,author) DO UPDATE SET first_n=MIN(first_n,excluded.first_n);
    END;
    DROP INDEX entries_said;`);
}
