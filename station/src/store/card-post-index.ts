import type { DatabaseSync } from "node:sqlite";

// Only the original post's card/options make it a question. Edits may carry the same fields but are not new questions.
// Requested old threads are prepared in slices; triggers keep each prepared or partly prepared thread current, even
// when the writer is an older station. The entries table remains the source of truth.
const VERSION = 1;
export const CARD_POST_BEFORE = "SELECT MAX(n) AS n FROM card_posts WHERE thread=? AND n<?";
export const CARD_POST_NEXT = "SELECT n FROM card_posts WHERE thread=? AND n>=? ORDER BY n LIMIT 1";
export const CARD_POST_AFTER = "SELECT 1 FROM card_posts WHERE thread=? AND n>? LIMIT 1";

const candidate = "NEW.kind='message' AND (NEW.card IS NOT NULL OR NEW.options IS NOT NULL)";
// REPLACE may silently remove a row without firing its DELETE trigger, including a row in a different thread by rowid.
// Stage every potentially displaced post and re-read it after the write. In a BEFORE INSERT an automatic rowid may be
// -1; staging that real row too is harmless because reconciliation sees whether it survived.
const conflicts = `SELECT e.thread,e.n FROM entries e WHERE e.thread=NEW.thread AND e.n=NEW.n
  UNION SELECT e.thread,e.n FROM entries e WHERE NEW.ts IS NOT NULL AND e.thread=NEW.thread AND e.ts=NEW.ts
  UNION SELECT e.thread,e.n FROM entries e WHERE e.rowid=NEW.rowid`;
const displaced = `EXISTS (SELECT 1 FROM card_posts p WHERE p.thread=NEW.thread AND p.n=NEW.n)
  OR EXISTS (SELECT 1 FROM entries e JOIN card_posts p ON p.thread=e.thread AND p.n=e.n WHERE e.rowid=NEW.rowid)
  OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e JOIN card_posts p ON p.thread=e.thread AND p.n=e.n
    WHERE e.thread=NEW.thread AND e.ts=NEW.ts))`;
const needsInsert = `(${displaced}) OR EXISTS (SELECT 1 FROM card_post_changed)`;
const needsUpdate = `(${needsInsert}) OR (${candidate} AND EXISTS (SELECT 1 FROM card_post_scopes WHERE thread=NEW.thread))
  OR EXISTS (SELECT 1 FROM card_posts WHERE thread=OLD.thread AND n=OLD.n)`;
const stage = (update: boolean) => `DELETE FROM card_post_changed;
  INSERT INTO card_post_changed(thread,n)
  SELECT k.thread,k.n FROM (SELECT NEW.thread AS thread,NEW.n AS n UNION ${conflicts}
    ${update ? "UNION SELECT OLD.thread,OLD.n" : ""}) k
  WHERE EXISTS (SELECT 1 FROM card_post_scopes s WHERE s.thread=k.thread);`;
// The changed set is tiny. Without CROSS JOIN SQLite may choose to scan every entry on every card write.
export const CARD_POST_ADD_CHANGED = `INSERT INTO card_posts(thread,n)
  SELECT e.thread,e.n FROM card_post_changed c CROSS JOIN entries e ON e.thread=c.thread AND e.n=c.n
  WHERE e.kind='message' AND (e.card IS NOT NULL OR e.options IS NOT NULL)`;
const reconcile = `DELETE FROM card_posts WHERE (thread,n) IN (SELECT thread,n FROM card_post_changed);
  ${CARD_POST_ADD_CHANGED}; DELETE FROM card_post_changed;`;

export function installCardPosts(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='card_post_meta'").get() !== undefined;
  if (installed()) { checkCardPosts(db); return; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE card_post_meta (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO card_post_meta VALUES(1,${VERSION});
      CREATE TABLE card_post_scopes (thread INTEGER PRIMARY KEY, last_n INTEGER, end_n INTEGER, phase INTEGER NOT NULL) WITHOUT ROWID;
      CREATE TABLE card_posts (thread INTEGER NOT NULL,n INTEGER NOT NULL,PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TABLE card_post_changed (thread INTEGER NOT NULL,n INTEGER NOT NULL,PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TRIGGER card_post_new_thread AFTER INSERT ON threads
      WHEN NOT EXISTS (SELECT 1 FROM entries WHERE thread=NEW.id LIMIT 1) BEGIN
        INSERT INTO card_post_scopes(thread,last_n,end_n,phase) VALUES(NEW.id,NULL,NULL,2)
        ON CONFLICT(thread) DO NOTHING;
      END;
      CREATE TRIGGER card_post_before_insert BEFORE INSERT ON entries WHEN ${needsInsert} BEGIN ${stage(false)} END;
      CREATE TRIGGER card_post_insert AFTER INSERT ON entries WHEN EXISTS (SELECT 1 FROM card_post_changed) BEGIN ${reconcile} END;
      -- A new post with no displaced indexed row needs no staging. If the reconciliation trigger ran first, it may
      -- already have inserted this post; the existence check keeps either trigger order correct.
      CREATE TRIGGER card_post_fast_insert AFTER INSERT ON entries WHEN ${candidate}
        AND EXISTS (SELECT 1 FROM card_post_scopes WHERE thread=NEW.thread)
        AND NOT EXISTS (SELECT 1 FROM card_post_changed) BEGIN
        INSERT INTO card_posts(thread,n) SELECT NEW.thread,NEW.n
          WHERE NOT EXISTS (SELECT 1 FROM card_posts WHERE thread=NEW.thread AND n=NEW.n);
      END;
      CREATE TRIGGER card_post_before_update BEFORE UPDATE OF rowid,_rowid_,oid,thread,n,kind,ts,card,options ON entries
      WHEN ${needsUpdate} BEGIN ${stage(true)} END;
      CREATE TRIGGER card_post_update AFTER UPDATE OF rowid,_rowid_,oid,thread,n,kind,ts,card,options ON entries
      WHEN EXISTS (SELECT 1 FROM card_post_changed) BEGIN ${reconcile} END;
      CREATE TRIGGER card_post_delete AFTER DELETE ON entries
      WHEN OLD.kind='message' AND (OLD.card IS NOT NULL OR OLD.options IS NOT NULL) BEGIN
        DELETE FROM card_posts WHERE thread=OLD.thread AND n=OLD.n;
      END;
      CREATE TRIGGER card_post_drop_thread AFTER DELETE ON threads
      WHEN NOT EXISTS (SELECT 1 FROM entries WHERE thread=OLD.id) BEGIN
        DELETE FROM card_post_scopes WHERE thread=OLD.id;
      END;
    `);
    else checkCardPosts(db);
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function checkCardPosts(db: DatabaseSync): void {
  const meta = db.prepare("SELECT version FROM card_post_meta WHERE id=1").get() as { version: number } | undefined;
  if (!meta || meta.version !== VERSION) throw new Error(`card post index version ${meta?.version ?? "missing"} is incompatible with ${VERSION}`);
}

type Scope = { last_n: string | null; end_n: string | null; phase: number };
const scopeOf = (db: DatabaseSync, thread: number): Scope | undefined => db.prepare(
  "SELECT CAST(last_n AS TEXT) AS last_n,CAST(end_n AS TEXT) AS end_n,phase FROM card_post_scopes WHERE thread=?",
).get(thread) as Scope | undefined;

export function cardPostsReady(db: DatabaseSync, thread: number): boolean {
  checkCardPosts(db);
  return scopeOf(db, thread)?.phase === 2;
}

// Keep the index's numeric ordering before casting the cursor for JavaScript. LIMIT applies before inspecting kind,
// since the legacy card indexes also contain edits. Missing legacy indexes fall back to bounded primary-key pages.
const positions = (column: "card" | "options" | null, after: boolean): string => {
  const index = column === null ? "" : ` INDEXED BY entries_${column === "card" ? "cards" : "options"}`;
  const predicate = column === null ? "" : ` AND ${column} IS NOT NULL`;
  const range = after ? "n>CAST(?2 AS INTEGER) AND n<=CAST(?3 AS INTEGER)" : "n<=CAST(?2 AS INTEGER)";
  return `SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM entries${index} WHERE thread=?1 AND ${range}${predicate}
    ORDER BY n LIMIT ${after ? "?4" : "?3"})`;
};

export function cardPostsStep(db: DatabaseSync, thread: number, limit = 128): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 128) throw new RangeError("card post batch must be between 1 and 128");
  if (cardPostsReady(db, thread)) return { done: true, visited: 0 };
  if (!scopeOf(db, thread)) {
    db.exec("BEGIN IMMEDIATE");
    try {
      db.prepare(`INSERT INTO card_post_scopes(thread,last_n,end_n,phase)
        SELECT ?1,NULL,(SELECT n FROM entries WHERE thread=?1 ORDER BY n DESC LIMIT 1),0
        WHERE NOT EXISTS (SELECT 1 FROM card_post_scopes WHERE thread=?1)`).run(thread);
      db.exec("COMMIT");
    } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
  }
  const before = scopeOf(db, thread)!;
  if (before.phase === 2) return { done: true, visited: 0 };
  const indexes = db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='index' AND name IN ('entries_cards','entries_options')").get() as { n: number };
  // If an old index disappeared between batches, restart from the beginning of the primary-key walk: the earlier
  // card-only batches cannot establish that they visited every options-only post.
  if (indexes.n !== 2 && before.phase !== 3) {
    db.exec("BEGIN IMMEDIATE");
    try {
      const now = scopeOf(db, thread);
      if (now && now.last_n === before.last_n && now.end_n === before.end_n && now.phase === before.phase)
        db.prepare("UPDATE card_post_scopes SET last_n=NULL,phase=3 WHERE thread=?").run(thread);
      db.exec("COMMIT");
      return { done: now?.phase === 2, visited: 0 };
    } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
  }
  const column = before.phase === 3 ? null : (before.phase === 0 ? "card" : "options");
  const statement = db.prepare(positions(column, before.last_n !== null));
  const rows = (before.last_n === null ? statement.all(thread, before.end_n, limit)
    : statement.all(thread, before.last_n, before.end_n, limit)) as { n: string }[];
  db.exec("BEGIN IMMEDIATE");
  try {
    const now = scopeOf(db, thread);
    if (!now || now.last_n !== before.last_n || now.end_n !== before.end_n || now.phase !== before.phase) {
      db.exec("COMMIT"); return { done: now?.phase === 2, visited: 0 };
    }
    const add = db.prepare(`INSERT INTO card_posts(thread,n)
      SELECT e.thread,e.n FROM entries e WHERE e.thread=?1 AND e.n=CAST(?2 AS INTEGER)
        AND e.kind='message' AND (e.card IS NOT NULL OR e.options IS NOT NULL)
        AND NOT EXISTS (SELECT 1 FROM card_posts p WHERE p.thread=e.thread AND p.n=e.n)`);
    for (const row of rows) add.run(thread, row.n);
    const endOfPhase = rows.length < limit;
    const phase = endOfPhase ? (column === null ? 2 : before.phase + 1) : before.phase;
    const last = endOfPhase ? null : rows.at(-1)!.n;
    db.prepare("UPDATE card_post_scopes SET last_n=CAST(? AS INTEGER),phase=? WHERE thread=?").run(last, phase, thread);
    db.exec("COMMIT");
    return { done: phase === 2, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
