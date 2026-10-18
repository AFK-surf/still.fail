// The station's search index (docs/search.md): `<data>/search.db`, a database of its own beside stillfail.db, so it can
// be dropped and built again at any time and nothing else reads it. Each thing found is a document: its kind, whom it is
// for (the workspace it is in, and a scope a viewer must have), what it is called, what it says, when, and what opens
// it. A document belongs to a source (a thread, a session's transcript, the skills of a workspace…), which is indexed as
// a whole and marked with the version indexed (`marks`), so what changed is indexed again and nothing else.
//
// The words are found by FTS5's trigram tokenizer (any part of a word, any script, case aside), with no positions kept
// (`detail=none`: a fifth of the size): the documents that have every three characters of a word are found by the
// index, and the word looked for in their text. A term of fewer than three characters (most Chinese words) has no
// trigram, and is looked for in the text itself.
import { DatabaseSync, type StatementSync } from "node:sqlite";

export type Doc = {
  /// Unique among all documents: its kind's and its own (`m:<thread>:<n>`, `h:<session>:<i>`…).
  key: string;
  kind: string;
  /// The source it is indexed with, and removed with.
  source: string;
  /// The workspace it is in: null the station's home one, `*` every workspace's members.
  ws: string | null;
  /// What else a viewer must have (`write`: a member who may write); null: none.
  scope?: string | null;
  title: string;
  body: string;
  at: number | null;
  /// What opens it, as the clients and agents are told (JSON).
  ref: Record<string, unknown>;
};

/// Whom a search is for: their workspace, whether it is the station's home one, and the scopes they have.
export type Asker = { workspace: string; home: boolean; scopes: string[] };

export type Hit = { kind: string; key: string; title: string; text: string; at: number | null } & Record<string, unknown>;
export type Group = { kind: string; hits: Hit[]; more: boolean };

/// What a body may hold at most (a long file's or message's first part).
export const BODY_MAX = 20_000;
/// How much of a body a hit says: around where the words are.
const BEFORE = 80;
const AFTER = 240;

/// The shape of the index: one of another is dropped and built again (PRAGMA user_version; 0 before it was kept).
const VERSION = 2;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS docs (
  id INTEGER PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL,
  source TEXT NOT NULL,
  ws TEXT,
  scope TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  at INTEGER,
  ref TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS docs_source ON docs (source);
CREATE INDEX IF NOT EXISTS docs_kind_at ON docs (kind, at DESC);
CREATE TABLE IF NOT EXISTS marks (source TEXT PRIMARY KEY, version TEXT NOT NULL);
`;

const FTS = `
CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(title, body, content='docs', content_rowid='id', tokenize='trigram', detail=none);
CREATE TRIGGER IF NOT EXISTS docs_ai AFTER INSERT ON docs BEGIN
  INSERT INTO docs_fts (rowid, title, body) VALUES (new.id, new.title, new.body);
END;
CREATE TRIGGER IF NOT EXISTS docs_ad AFTER DELETE ON docs BEGIN
  INSERT INTO docs_fts (docs_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
END;
CREATE TRIGGER IF NOT EXISTS docs_au AFTER UPDATE OF title, body ON docs BEGIN
  INSERT INTO docs_fts (docs_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
  INSERT INTO docs_fts (rowid, title, body) VALUES (new.id, new.title, new.body);
END;
`;

/// The words of a query: split at white space, each once, case aside; at most eight.
export function terms(query: string): string[] {
  const out: string[] = [];
  for (const t of query.trim().split(/\s+/u)) {
    const w = t.toLowerCase();
    if (w !== "" && !out.includes(w)) out.push(w);
  }
  return out.slice(0, 8);
}

const chars = (s: string) => Array.from(s).length;
/// A term as FTS5 reads a token: in double quotes, its own doubled.
const quoted = (t: string) => `"${t.replaceAll('"', '""')}"`;
/// A word's every three characters, each once: what the index has of it (it keeps no positions to find it whole by).
export function trigrams(word: string): string[] {
  const c = Array.from(word);
  const out = new Set<string>();
  for (let i = 0; i + 3 <= c.length; i++) out.add(c.slice(i, i + 3).join(""));
  return [...out];
}

/// Whether a word's letters other than ASCII's have no case (Chinese, digits…): lower() finds it as it is.
const plainCase = (w: string) => Array.from(w).every((c) => c <= "\x7f" || c.toUpperCase() === c.toLowerCase());

/// Where a body has the first of the words, and that part of it on one line: `…` where it is cut.
export function excerpt(body: string, words: string[]): string {
  const flat = body.replace(/\s+/gu, " ").trim();
  const lower = flat.toLowerCase();
  let at = -1;
  for (const w of words) {
    const i = lower.indexOf(w);
    if (i >= 0 && (at < 0 || i < at)) at = i;
  }
  if (at < 0) at = 0;
  const from = Math.max(0, at - BEFORE);
  const to = Math.min(flat.length, at + AFTER);
  return `${from > 0 ? "…" : ""}${flat.slice(from, to)}${to < flat.length ? "…" : ""}`;
}

export class SearchIndex {
  readonly db: DatabaseSync;
  /// Whether FTS5 is there (a Node without it looks through the text, slower).
  readonly fts: boolean;
  #stmts = new Map<string, StatementSync>();

  constructor(path: string) {
    this.db = new DatabaseSync(path, { timeout: 5000 });
    // The log given back once written in (a large source's replacing grows it to tens of MB).
    this.db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA journal_size_limit=8388608;");
    const version = (this.db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
    if (version !== VERSION) {
      // Another shape: what there was dropped (its space given back), built again from the store.
      this.db.exec("DROP TABLE IF EXISTS docs_fts; DROP TABLE IF EXISTS docs; DROP TABLE IF EXISTS marks;");
      this.db.exec("VACUUM");
      this.db.exec(`PRAGMA user_version=${VERSION}`);
    }
    this.db.exec(SCHEMA);
    let fts = true;
    try {
      this.db.exec(FTS);
    } catch {
      fts = false;
    }
    this.fts = fts;
  }

  close(): void {
    this.db.close();
  }

  #stmt(sql: string): StatementSync {
    let s = this.#stmts.get(sql);
    if (!s) {
      s = this.db.prepare(sql);
      this.#stmts.set(sql, s);
    }
    return s;
  }

  /// Done together, or not at all.
  tx<T>(work: () => T): T {
    this.db.exec("BEGIN");
    try {
      const out = work();
      this.db.exec("COMMIT");
      return out;
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }

  mark(source: string): string | null {
    const r = this.#stmt("SELECT version FROM marks WHERE source = ?").get(source) as { version: string } | undefined;
    return r?.version ?? null;
  }

  setMark(source: string, version: string): void {
    this.#stmt("INSERT INTO marks (source, version) VALUES (?, ?) ON CONFLICT (source) DO UPDATE SET version = excluded.version").run(source, version);
  }

  /// The sources marked whose names start with `prefix` (`t:` the threads…).
  marked(prefix: string): string[] {
    return (this.#stmt("SELECT source FROM marks WHERE source >= ? AND source < ?").all(prefix, `${prefix}￿`) as { source: string }[]).map((r) => r.source);
  }

  put(doc: Doc): void {
    const body = doc.body.length > BODY_MAX ? doc.body.slice(0, BODY_MAX) : doc.body;
    this.#stmt(
      `INSERT INTO docs (key, kind, source, ws, scope, title, body, at, ref) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (key) DO UPDATE SET kind = excluded.kind, source = excluded.source, ws = excluded.ws, scope = excluded.scope,
         title = excluded.title, body = excluded.body, at = excluded.at, ref = excluded.ref`,
    ).run(doc.key, doc.kind, doc.source, doc.ws, doc.scope ?? null, doc.title, body, doc.at, JSON.stringify(doc.ref));
  }

  has(key: string): boolean {
    return this.#stmt("SELECT 1 FROM docs WHERE key = ?").get(key) !== undefined;
  }

  /// A document's body as indexed (an edit's message indexed again keeps the rest of it).
  get(key: string): Doc | null {
    const r = this.#stmt("SELECT * FROM docs WHERE key = ?").get(key) as Record<string, any> | undefined;
    return r ? { key: r.key, kind: r.kind, source: r.source, ws: r.ws, scope: r.scope, title: r.title, body: r.body, at: r.at, ref: JSON.parse(r.ref) } : null;
  }

  remove(key: string): void {
    this.#stmt("DELETE FROM docs WHERE key = ?").run(key);
  }

  /// A source's documents, and its mark, gone.
  drop(source: string): void {
    this.#stmt("DELETE FROM docs WHERE source = ?").run(source);
    this.#stmt("DELETE FROM marks WHERE source = ?").run(source);
  }

  /// A source indexed anew: its documents replaced by these, marked with `version`.
  replace(source: string, version: string, docs: Doc[]): void {
    this.tx(() => {
      this.#stmt("DELETE FROM docs WHERE source = ?").run(source);
      for (const d of docs) this.put({ ...d, source });
      this.setMark(source, version);
    });
  }

  /// How many documents of each kind there are.
  counts(): Record<string, number> {
    const out: Record<string, number> = {};
    for (const r of this.#stmt("SELECT kind, count(*) AS n FROM docs GROUP BY kind").all() as { kind: string; n: number }[]) out[r.kind] = r.n;
    return out;
  }

  /**
   * What `query` finds for `asker`, by kind (those of `kinds`, all without), at most `limit` of each: those whose title
   * has the first word first, then the newest. Every word must be in its title or body: the index finds those with
   * each three characters of the longer ones, the text has the words.
   */
  search(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number } = {}): Group[] {
    const words = terms(query);
    if (words.length === 0) return [];
    const limit = Math.max(1, Math.min(options.limit ?? 8, 200));
    const offset = Math.max(0, options.offset ?? 0);
    const long = this.fts ? words.filter((w) => chars(w) >= 3) : [];
    // Looked for in the text: SQLite's lower() knows no case but ASCII's, so a longer word with other cased letters
    // (é, Ж) is left to the index, which does (its three characters found apart are let through).
    const within = words.filter((w) => !long.includes(w) || plainCase(w));
    const scopes = asker.scopes.map(() => "?").join(", ");
    const seen = `(d.ws = '*' OR d.ws = ? OR (d.ws IS NULL AND ? = 1)) AND (d.scope IS NULL${scopes ? ` OR d.scope IN (${scopes})` : ""})`;
    const contains = within.map(() => " AND instr(lower(d.title || char(10) || d.body), ?) > 0").join("");
    const only = options.kinds && options.kinds.length > 0 ? ` AND d.kind IN (${options.kinds.map(() => "?").join(", ")})` : "";
    // The index first (CROSS JOIN keeps the planner from reading every document of a kind and asking the index of each),
    // then each kind's first ones in one pass.
    const from = long.length > 0 ? "docs_fts CROSS JOIN docs d ON d.id = docs_fts.rowid WHERE docs_fts MATCH ? AND" : "docs d WHERE";
    const sql = `SELECT * FROM (
        SELECT d.*, row_number() OVER (PARTITION BY d.kind ORDER BY instr(lower(d.title), ?) > 0 DESC, d.at IS NULL, d.at DESC, d.id DESC) AS rank
        FROM ${from} ${seen}${contains}${only}
      ) WHERE rank > ? AND rank <= ? ORDER BY kind, rank`;
    const args: (string | number)[] = [words[0]!];
    if (long.length > 0) args.push(long.flatMap(trigrams).map(quoted).join(" "));
    args.push(asker.workspace, asker.home ? 1 : 0, ...asker.scopes, ...within, ...(options.kinds ?? []), offset, offset + limit + 1);
    const byKind = new Map<string, Record<string, any>[]>();
    for (const r of this.#stmt(sql).all(...args) as Record<string, any>[]) {
      const list = byKind.get(r.kind) ?? [];
      list.push(r);
      byKind.set(r.kind, list);
    }
    const out: Group[] = [];
    for (const [kind, rows] of byKind) {
      out.push({
        kind,
        more: rows.length > limit,
        hits: rows.slice(0, limit).map((r) => ({ ...JSON.parse(r.ref), kind: r.kind, key: r.key, title: r.title, text: excerpt(r.body, words), at: r.at })),
      });
    }
    return out;
  }
}
