// What a copy of a station's conversations is made of (replica/AGENTS.md): batches, each the rows that changed since the
// one before it, numbered on in a generation of them, and the head that says which batches and files make the copy now.
// Only a restorer reads inside them; the stations that keep a copy keep them as files.
//
//   <gen>/log/<from>-<to>-<sum>.ndjson.zst   a batch: zstd of JSON lines, the first its header, written whole or not at
//                                      all; `sum` the start of its bytes' hash, so two batches of the same numbers (one a
//                                      station rolled back wrote again) are never taken for each other
//   <gen>/files/<sha256>               an attached file, by the hash of what it holds
//   <gen>/head.json                    written last: the batches and files of the copy, and what it is of
//
// A record says a row as it is now (`r`: its table, `row`: its columns by name, as the origin's schema has them), a row
// that is gone (`del`: its table and key), a session or thread deleted with everything of it (`gone`), or an attached
// file (`file`: its hash, size and where it was). A later record of a key stands for an earlier one; folding them
// (`Folded`) is what both a restore and the folding of small batches into one do.
import { createHash } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { zstdCompressSync, zstdDecompressSync } from "node:zlib";

/// The batches' format: a restorer takes those of its own version or before.
export const VERSION = 1;

export type Row = Record<string, unknown>;
export type Rec =
  | { r: string; row: Row }
  | { del: string; key: Row }
  | { gone: "session"; key: string }
  | { gone: "thread"; id: number }
  | { file: string; size: number; path: string };

export type Header = { v: number; gen: string; from: number; to: number; made: number };

/// The head of a generation of batches (`head.json`): which batches and files the copy is now, whose it is (`origin`,
/// in `workspace`; what it was called, `name`; where its data was, `dataDir`, which the paths in its rows begin with),
/// how far it goes (`to`), when that was (`made`), how much it holds (`chats`, `messages`; `bytes` of batches and
/// files), and the runs of its exporter that wrote it, each from the batch it began at (`runs`, the last RUNS_KEPT): a
/// place that holds a run this station's own head does not know holds what this station lost (it was rolled back).
export type Head = {
  v: number;
  origin: string;
  workspace: string;
  gen: string;
  name: string;
  dataDir: string;
  made: number;
  to: number;
  batches: string[];
  files: Record<string, number>;
  chats: number;
  messages: number;
  bytes: number;
  runs: { run: string; from: number }[];
};

/// The tables a copy holds, each by its key's columns: what a restored chat is (its threads, their entries and letters,
/// their sessions and turns, and each viewer's marks of them).
export const TABLES: Record<string, readonly string[]> = {
  threads: ["id"],
  sessions: ["key"],
  thread_sessions: ["thread", "session"],
  entries: ["thread", "n"],
  letters: ["thread", "n"],
  turns: ["id"],
  runtime_sessions: ["session_key", "id"],
  closed_cards: ["thread", "n"],
  reads: ["viewer", "thread"],
  hidden_chats: ["viewer", "thread"],
  muted_chats: ["viewer", "thread"],
  kept_chats: ["viewer", "thread"],
  dismissed: ["viewer", "thread", "n"],
  pins: ["viewer", "session"],
  opened_chats: ["child_station", "child"],
};

/// The order a restore puts them in: what a row points at before it.
export const RESTORE_ORDER = ["threads", "sessions", "thread_sessions", "entries", "letters", "turns", "runtime_sessions", "closed_cards", "reads", "hidden_chats", "muted_chats", "kept_chats", "dismissed", "pins", "opened_chats"];

/// The column of a table that names the thread or the session a row is of: what goes with a thread or a session gone.
const THREAD_OF: Record<string, string> = { threads: "id", thread_sessions: "thread", entries: "thread", letters: "thread", closed_cards: "thread", reads: "thread", hidden_chats: "thread", muted_chats: "thread", kept_chats: "thread", dismissed: "thread" };
/// Where a copy is put into a station with chats of its own (a station retired into it, restore.ts `build`'s `merge`):
/// the columns that name a thread by its id here, given the id it gets there; and the tables numbered by a thread's
/// own log (`n`, a viewer's read to it too), whose rows go only with a thread new there (one followed by both is the one
/// there, its log as it is).
export const THREAD_COLUMNS: Record<string, string> = { thread_sessions: "thread", entries: "thread", letters: "thread", closed_cards: "thread", reads: "thread", hidden_chats: "thread", muted_chats: "thread", kept_chats: "thread", dismissed: "thread", turns: "about_thread" };
export const OWN_LOG = new Set(["entries", "letters", "closed_cards", "dismissed", "reads"]);

/// A thread's ts a step on (a still.fail chat's, which each station mints itself, met there by another's: restore.ts
/// `build`'s `merge`): its last digits counted up by one (`9` to `10` as a number is), a `1` put after it where it
/// ends in none.
export function bumpedTs(ts: string): string {
  let i = ts.length;
  while (i > 0 && ts.charCodeAt(i - 1) >= 48 && ts.charCodeAt(i - 1) <= 57) i--;
  if (i === ts.length) return `${ts}1`;
  const digits = ts.slice(i).split("");
  let j = digits.length - 1;
  while (j >= 0 && digits[j] === "9") digits[j--] = "0";
  if (j < 0) digits.unshift("1");
  else digits[j] = String.fromCharCode(digits[j]!.charCodeAt(0) + 1);
  return ts.slice(0, i) + digits.join("");
}
const SESSION_OF: Record<string, string> = { sessions: "key", thread_sessions: "session", turns: "session_key", runtime_sessions: "session_key", pins: "session", opened_chats: "child" };

export const WORKSPACE = /^[0-9A-Za-z_-]{1,64}$/;
export const STATION = /^[0-9a-f]{64}$/;
export const GEN = /^[0-9a-z]{1,16}-[0-9a-f]{8}$/;
export const HASH = /^[0-9a-f]{64}$/;
export const BATCH = /^(\d{10})-(\d{10})-[0-9a-f]{8}\.ndjson\.zst$/;

const pad = (n: number) => String(n).padStart(10, "0");
export const batchName = (from: number, to: number, bytes: Buffer) => `${pad(from)}-${pad(to)}-${createHash("sha256").update(bytes).digest("hex").slice(0, 8)}.ndjson.zst`;
export function batchSpan(name: string): { from: number; to: number } | null {
  const m = BATCH.exec(name);
  return m === null ? null : { from: Number(m[1]), to: Number(m[2]) };
}

/// A new generation's name: when it began (base 36, so names sort by it) and a random part.
export const genName = (now: number, random: string) => `${Math.max(0, Math.floor(now)).toString(36)}-${random.slice(0, 8)}`;
export const genMade = (gen: string) => parseInt(gen.split("-")[0]!, 36);

/// The key of a row of `table`, as text: what a later record of it is matched by.
export function keyOf(table: string, row: Row): string {
  const cols = TABLES[table];
  if (cols === undefined) throw new Error(`no such table in a copy: ${table}`);
  return JSON.stringify(cols.map((c) => row[c] ?? null));
}

/// A batch's bytes: its header, then its records, a line each (records already as their lines, `lines`, go as they are:
/// a Buffer a line with its newline, as `runsOf` gives them, kept outside the heap).
export function encodeBatch(header: Header, records: readonly Rec[], lines: Iterable<string | Buffer> = []): Buffer {
  const parts: Buffer[] = [Buffer.from(JSON.stringify(header) + "\n", "utf8")];
  for (const l of lines) parts.push(typeof l === "string" ? Buffer.from(l + "\n", "utf8") : l);
  for (const r of records) parts.push(Buffer.from(JSON.stringify(r) + "\n", "utf8"));
  return zstdCompressSync(Buffer.concat(parts)); // sync: only the export's and the restore's own threads code batches (export.ts, restore.ts)
}

/// A batch read: its header, and its records' lines one at a time (a folded generation is all of a station's chats:
/// never all its records parsed at once).
export function decodeBatch(bytes: Buffer): { header: Header; lines: Iterable<string> } {
  const text = zstdDecompressSync(bytes); // sync: only the export's and the restore's own threads code batches (export.ts, restore.ts)
  const first = text.indexOf(10);
  const header = JSON.parse(text.toString("utf8", 0, first < 0 ? text.length : first)) as Header;
  if (header === null || typeof header !== "object" || typeof header.v !== "number") throw new Error("not a batch");
  if (header.v > VERSION) throw new Error(`a batch of format ${header.v}, newer than this station's ${VERSION}`);
  return {
    header,
    lines: (function* () {
      for (let at = first < 0 ? text.length : first + 1; at < text.length; ) {
        let end = text.indexOf(10, at);
        if (end < 0) end = text.length;
        if (end > at) yield text.toString("utf8", at, end);
        at = end + 1;
      }
    })(),
  };
}

/// Every record of a batch, parsed.
export function recordsOf(bytes: Buffer): Rec[] {
  return [...decodeBatch(bytes).lines].map((l) => JSON.parse(l) as Rec);
}

/// A head read back, or null where it is none (or of a format newer than this).
export function asHead(v: unknown): Head | null {
  const h = v as Head;
  if (h === null || typeof h !== "object" || typeof h.v !== "number" || h.v > VERSION) return null;
  if (typeof h.origin !== "string" || typeof h.workspace !== "string" || typeof h.gen !== "string" || !GEN.test(h.gen)) return null;
  if (!Number.isSafeInteger(h.to) || !Array.isArray(h.batches) || h.batches.some((b) => typeof b !== "string" || !BATCH.test(b))) return null;
  if (h.files === null || typeof h.files !== "object" || Object.keys(h.files).some((k) => !HASH.test(k))) return null;
  if (!Array.isArray(h.runs)) return null;
  return h;
}

/// The paths of the files a row's attachments name (entries' and letters' `attachments`, JSON: [{path, …}]).
export function attachedPaths(row: Row): string[] {
  const a = row.attachments;
  if (typeof a !== "string" || a === "" || a === "[]") return [];
  try {
    const list = JSON.parse(a);
    return Array.isArray(list) ? list.flatMap((x) => (x !== null && typeof x === "object" && typeof x.path === "string" && x.path !== "" ? [x.path as string] : [])) : [];
  } catch {
    return [];
  }
}

/// How much of records a batch holds at most, before it is compressed: a pass and a fold write several past it.
export const BATCH_BYTES = 8 << 20;

/// Record lines cut into runs of at most BATCH_BYTES (one line longer than that is a run of its own), each line a
/// Buffer with its newline as it comes: a run waits outside the heap, its strings let go one at a time.
export function* runsOf(lines: Iterable<string | Buffer>, most = BATCH_BYTES): Iterable<Buffer[]> {
  let run: Buffer[] = [];
  let size = 0;
  for (const line of lines) {
    const b = typeof line === "string" ? Buffer.from(line + "\n", "utf8") : line;
    if (run.length > 0 && size + b.length > most) {
      yield run;
      run = [];
      size = 0;
    }
    run.push(b);
    size += b.length;
  }
  if (run.length > 0) yield run;
}

const FOLD = `
CREATE TABLE IF NOT EXISTS rows (tbl INTEGER NOT NULL, k TEXT NOT NULL, seq INTEGER NOT NULL, line TEXT NOT NULL, thread INTEGER, session TEXT, message INTEGER NOT NULL, PRIMARY KEY (tbl, k)) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS rows_order ON rows (tbl, seq);
CREATE INDEX IF NOT EXISTS rows_thread ON rows (thread) WHERE thread IS NOT NULL;
CREATE INDEX IF NOT EXISTS rows_session ON rows (session) WHERE session IS NOT NULL;
CREATE TABLE IF NOT EXISTS attached (tbl INTEGER NOT NULL, k TEXT NOT NULL, path TEXT NOT NULL, PRIMARY KEY (tbl, k, path)) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS attached_path ON attached (path);
CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, seq INTEGER NOT NULL, hash TEXT NOT NULL, size INTEGER NOT NULL) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS files_order ON files (seq);
CREATE TABLE IF NOT EXISTS dels (tk TEXT PRIMARY KEY, seq INTEGER NOT NULL, line TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS gone (line TEXT PRIMARY KEY, seq INTEGER NOT NULL) WITHOUT ROWID;
`;

/// Records folded into what they say now: each key's last row, nothing of what was deleted, and the files the rows left
/// still name. Kept in a database of its own on disk (`path`; ":memory:" for a small one, a test's), each row as its
/// record's line with what a deletion goes by: a whole station's copy is folded in memory that does not grow with it.
export class Folded {
  readonly #db: DatabaseSync;
  #seq = 0;
  readonly #q = new Map<string, ReturnType<DatabaseSync["prepare"]>>();

  constructor(path = ":memory:") {
    this.#db = new DatabaseSync(path);
    this.#db.exec("PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; PRAGMA cache_size = -8192; PRAGMA temp_store = FILE;");
    this.#db.exec(FOLD);
    this.#db.exec("BEGIN");
  }

  #s(sql: string) {
    let s = this.#q.get(sql);
    if (s === undefined) this.#q.set(sql, (s = this.#db.prepare(sql)));
    return s;
  }

  close(): void {
    try {
      this.#db.exec("COMMIT");
    } catch {}
    this.#db.close();
  }

  /// A record, as its line (or parsed).
  apply(line: string | Rec): void {
    const rec = typeof line === "string" ? (JSON.parse(line) as Rec) : line;
    const text = typeof line === "string" ? line : JSON.stringify(rec);
    const seq = ++this.#seq;
    if ("r" in rec) {
      const tbl = RESTORE_ORDER.indexOf(rec.r);
      if (tbl < 0) return;
      const key = keyOf(rec.r, rec.row);
      const column = SESSION_OF[rec.r];
      const thread = THREAD_OF[rec.r] === undefined ? null : (rec.row[THREAD_OF[rec.r]!] as number);
      const session = column === undefined || (rec.r === "opened_chats" && rec.row.child_station !== "") ? null : (rec.row[column] as string);
      this.#s("INSERT INTO rows (tbl, k, seq, line, thread, session, message) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (tbl, k) DO UPDATE SET seq = excluded.seq, line = excluded.line, thread = excluded.thread, session = excluded.session, message = excluded.message")
        .run(tbl, key, seq, text, thread, session, rec.r === "entries" && rec.row.kind === "message" ? 1 : 0);
      this.#s("DELETE FROM attached WHERE tbl = ? AND k = ?").run(tbl, key);
      if (rec.r === "entries" || rec.r === "letters") for (const path of attachedPaths(rec.row)) this.#s("INSERT OR IGNORE INTO attached (tbl, k, path) VALUES (?, ?, ?)").run(tbl, key, path);
      this.#s("DELETE FROM dels WHERE tk = ?").run(`${rec.r}|${key}`);
    } else if ("del" in rec) {
      const tbl = RESTORE_ORDER.indexOf(rec.del);
      if (tbl < 0) return;
      const key = keyOf(rec.del, rec.key);
      this.#s("DELETE FROM rows WHERE tbl = ? AND k = ?").run(tbl, key);
      this.#s("DELETE FROM attached WHERE tbl = ? AND k = ?").run(tbl, key);
      this.#s("INSERT INTO dels (tk, seq, line) VALUES (?, ?, ?) ON CONFLICT (tk) DO UPDATE SET seq = excluded.seq, line = excluded.line").run(`${rec.del}|${key}`, seq, text);
    } else if ("gone" in rec) {
      const [column, value, tables] = rec.gone === "session" ? ["session", rec.key, Object.keys(SESSION_OF)] : ["thread", rec.id, Object.keys(THREAD_OF)];
      const tbls = tables.map((t) => RESTORE_ORDER.indexOf(t));
      for (const r of this.#s(`SELECT tbl, k FROM rows WHERE ${column} = ?`).all(value as never) as { tbl: number; k: string }[]) {
        if (!tbls.includes(r.tbl)) continue;
        this.#s("DELETE FROM rows WHERE tbl = ? AND k = ?").run(r.tbl, r.k);
        this.#s("DELETE FROM attached WHERE tbl = ? AND k = ?").run(r.tbl, r.k);
      }
      this.#s("INSERT INTO gone (line, seq) VALUES (?, ?) ON CONFLICT (line) DO UPDATE SET seq = excluded.seq").run(text, seq);
    } else if ("file" in rec) {
      this.#s("INSERT INTO files (path, seq, hash, size) VALUES (?, ?, ?, ?) ON CONFLICT (path) DO UPDATE SET seq = excluded.seq, hash = excluded.hash, size = excluded.size").run(rec.path, seq, rec.file, rec.size);
    }
  }

  /// A table's rows now, parsed, in the order they were said (a test's, one table at a time).
  *rowsOf(table: string): Iterable<Row> {
    for (const r of this.#s("SELECT line FROM rows WHERE tbl = ? ORDER BY seq").iterate(RESTORE_ORDER.indexOf(table)) as Iterable<{ line: string }>) {
      yield (JSON.parse(r.line) as { row: Row }).row;
    }
  }

  table(table: string): Row[] {
    return [...this.rowsOf(table)];
  }

  size(table: string): number {
    return (this.#s("SELECT COUNT(*) AS n FROM rows WHERE tbl = ?").get(RESTORE_ORDER.indexOf(table)) as { n: number }).n;
  }

  /// The files the rows still name, by where they were.
  *namedFiles(): Iterable<{ path: string; hash: string; size: number }> {
    yield* this.#s("SELECT f.path, f.hash, f.size FROM files f WHERE EXISTS (SELECT 1 FROM attached a WHERE a.path = f.path) ORDER BY f.seq").iterate() as Iterable<{ path: string; hash: string; size: number }>;
  }

  named(): Map<string, { hash: string; size: number }> {
    return new Map([...this.namedFiles()].map((f) => [f.path, { hash: f.hash, size: f.size }]));
  }

  /// What it says now, as record lines, one at a time: every row, then the files still named.
  *records(): Iterable<string> {
    for (const r of this.#s("SELECT line FROM rows ORDER BY tbl, seq").iterate() as Iterable<{ line: string }>) yield r.line;
    for (const f of this.namedFiles()) yield JSON.stringify({ file: f.hash, size: f.size, path: f.path });
  }

  /// What it says, as record lines, where batches before it are not folded with it: what was deleted first (sessions
  /// and threads, then rows), so that it still deletes what they said, then every row and every file.
  *partial(): Iterable<string> {
    for (const g of this.#s("SELECT line FROM gone ORDER BY seq").iterate() as Iterable<{ line: string }>) yield g.line;
    for (const d of this.#s("SELECT line FROM dels ORDER BY seq").iterate() as Iterable<{ line: string }>) yield d.line;
    for (const r of this.#s("SELECT line FROM rows ORDER BY tbl, seq").iterate() as Iterable<{ line: string }>) yield r.line;
    for (const f of this.#s("SELECT path, hash, size FROM files ORDER BY seq").iterate() as Iterable<{ path: string; hash: string; size: number }>) {
      yield JSON.stringify({ file: f.hash, size: f.size, path: f.path });
    }
  }

  /// How many chats and messages it holds.
  counts(): { chats: number; messages: number } {
    return { chats: this.size("threads"), messages: (this.#s("SELECT COUNT(*) AS n FROM rows WHERE message = 1").get() as { n: number }).n };
  }
}
