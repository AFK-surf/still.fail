// A vault index's schema put in as the vault is made (the use, rebox, pending and members indexes), at every start.
// Put in by a savepoint begun outside a transaction (a deferred one), its first statements only read (what is there
// already) and the write its INSERT or a new trigger then needed was refused at once: SQLite calls no busy handler for
// a transaction that holds a read. A new station process started beside the one serving died "database is locked"
// whenever that one was writing (2026-11-14, the update not handed over). So what is there already is only read, and
// what is missing is put in with the write taken first (BEGIN IMMEDIATE, waiting its turn as busy_timeout says), or in
// the transaction the caller has open.
import type { DatabaseSync } from "node:sqlite";

const NAMED = /CREATE\s+(?:TABLE|INDEX|TRIGGER)\s+IF\s+NOT\s+EXISTS\s+(\w+)/gi;

/// A schema is only told installed by what it names, so it may hold nothing else: `CREATE TABLE|INDEX|TRIGGER IF NOT
/// EXISTS` and the `INSERT OR IGNORE INTO` of a table a query of `rows` looks in. Anything else (a `DROP … IF EXISTS` of
/// a trigger from before, an ALTER, an UPDATE, a CREATE without IF NOT EXISTS) would never run on a station that has the
/// rest: refused here, as the vault is made at start, saying which. Thrown the first time a schema is seen.
export class UnaccountedSchema extends Error {
  constructor(name: string, statement: string) {
    super(`the vault's schema ${name} holds a statement installSchema cannot tell is done: ${statement.slice(0, 80)} (vault/schema-install.ts)`);
  }
}

const accounted = new Map<string, true>();

function account(name: string, schema: string, rows: string[]): void {
  if (accounted.has(schema)) return;
  const statements = schema
    .replace(/--[^\n]*/g, "")
    .replace(/CREATE\s+TRIGGER\s+IF\s+NOT\s+EXISTS\s+\w+[\s\S]*?\bEND\s*;/gi, "")
    .split(";")
    .map((st) => st.trim().replace(/\s+/g, " "))
    .filter((st) => st !== "");
  for (const st of statements) {
    if (/^CREATE (TABLE|INDEX|UNIQUE INDEX) IF NOT EXISTS \w+/i.test(st)) continue;
    const insert = /^INSERT OR IGNORE INTO (\w+)/i.exec(st);
    if (insert !== null && rows.some((q) => new RegExp(`\\bFROM ${insert[1]}\\b`, "i").test(q))) continue;
    throw new UnaccountedSchema(name, st);
  }
  accounted.set(schema, true);
}

/// `schema`'s tables, indexes and triggers made where missing, and the rows `rows` look for (a query each, answering a
/// row when it is there) put in by it, all at once: nothing written where all of them are there.
export function installSchema(db: DatabaseSync, name: string, schema: string, rows: string[] = []): void {
  account(name, schema, rows);
  if (db.isTransaction) {
    db.exec(`SAVEPOINT ${name}`); // deferred: inside the caller's transaction
    try { db.exec(schema); db.exec(`RELEASE ${name}`); }
    catch (error) { db.exec(`ROLLBACK TO ${name}; RELEASE ${name}`); throw error; }
    return;
  }
  if (installed(db, schema, rows)) return;
  db.exec("BEGIN IMMEDIATE");
  try { db.exec(schema); db.exec("COMMIT"); }
  catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

function installed(db: DatabaseSync, schema: string, rows: string[]): boolean {
  const names = [...new Set([...schema.matchAll(NAMED)].map((m) => m[1]!))];
  const found = db.prepare(`SELECT count(*) AS n FROM sqlite_master WHERE name IN (${names.map(() => "?").join(",")})`).get(...names) as { n: number };
  if (Number(found.n) !== names.length) return false;
  return rows.every((sql) => db.prepare(sql).get() !== undefined);
}
