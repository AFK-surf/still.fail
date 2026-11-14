// A lost station's conversations taken back (replica/AGENTS.md): a copy of them (a generation of batches and its files,
// brought into <data>/restore/ from a station that holds it) folded into what it says
// now, and put into this station's database before its store opens: the same thread ids, entry numbers and session
// keys, the paths in its rows moved from the lost station's data directory to this one's, its files put where the rows
// say. Only into a station that has no chats of its own yet; the station then says it was that one (`formerly`).
import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { Worker } from "node:worker_threads";
import { dirname, join, sep } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { type Head, type Rec, type Row, Folded, OWN_LOG, RESTORE_ORDER, THREAD_COLUMNS, asHead, attachedPaths, bumpedTs, decodeBatch } from "./format.ts";
import { headFile } from "./export.ts";
import { STILLFAIL_SURFACE } from "../store/rows.ts";

/// Where a restore brings a copy before it is put in: `<data>/restore/`, its generation's batches and files as a
/// place keeps them, and `ready.json` once all of it is there.
export const restoreDir = (data: string) => join(data, "restore");
export const readyFile = (data: string) => join(restoreDir(data), "ready.json");
/// What a restore brought, once all of it is there: whose copy (`origin`, in `workspace`), which generation, and where it
/// was taken from (said to whoever looks at the station meanwhile).
/// `merge`: the copy of a station retired into this one (retire.ts), put in beside this station's own chats;
/// `connects`: how the ids of that station's connects go here (retire.ts `connectsThere`); `ws`: what its sessions'
/// `ws` is here (null: this station's home workspace), whatever it was there.
export type Ready = { origin: string; workspace: string; gen: string; name: string; from: string; merge?: boolean; connects?: Record<string, string>; ws?: string | null };

/// The generation brought, as `<restore>/copy/` holds it: `head.json`, `log/`, `files/`.
export const copyDir = (data: string) => join(restoreDir(data), "copy");

/// A generation folded: its head, and what its batches say now. Throws where a batch the head names is not there.
export function readCopy(dir: string): { head: Head; folded: Folded } {
  const head = asHead(JSON.parse(readFileSync(headFile(dir), "utf8"))); // sync: in the restore's own thread (restore-worker.ts)
  if (head === null) throw new Error("no copy here, or one of a newer station's");
  const folded = new Folded();
  for (const b of head.batches) for (const line of decodeBatch(readFileSync(join(dir, "log", b))).lines) folded.apply(line); // sync: in the restore's own thread (restore-worker.ts)
  return { head, folded };
}

/// `path` as it is on this station: under `to` where it was under `from`.
export function moved(path: string, from: string, to: string): string {
  if (from === "" || from === to) return path;
  const f = from.endsWith(sep) ? from.slice(0, -1) : from;
  if (path === f) return to;
  return path.startsWith(f + sep) || path.startsWith(`${f}/`) ? join(to, path.slice(f.length + 1)) : path;
}

/// A row as this station keeps it: its paths moved, a session at rest.
function shaped(table: string, row: Row, from: string, to: string): Row {
  const out = { ...row };
  if (table === "sessions") {
    if (typeof out.workspace === "string") out.workspace = moved(out.workspace, from, to);
    if (typeof out.cwd === "string") out.cwd = moved(out.cwd, from, to);
    out.running = 0;
  }
  if ((table === "entries" || table === "letters") && typeof out.attachments === "string" && out.attachments !== "") {
    try {
      const list = JSON.parse(out.attachments);
      if (Array.isArray(list)) out.attachments = JSON.stringify(list.map((a) => (a !== null && typeof a === "object" && typeof a.path === "string" ? { ...a, path: moved(a.path, from, to) } : a)));
    } catch {}
  }
  return out;
}

/// What was put in: rows by table, and files placed (or missing: not in the copy).
export type Built = { rows: Record<string, number>; files: number; missing: number };

/// What a restore put in, kept in the database it put it in with its rows (one transaction): a restore stopped after
/// it and run again does not put it in twice, nor refuse it as chats of the station's own.
const RESTORED = "CREATE TABLE IF NOT EXISTS replica_restored (origin TEXT NOT NULL, gen TEXT NOT NULL, at INTEGER NOT NULL, rows TEXT NOT NULL, PRIMARY KEY (origin, gen))";

/// Puts what the generation in `dir` says into the database at `db` (its schema there already: made by the store as
/// the station first started): its batches folded on disk, then each row that is left put in once (`Folded`): nothing
/// of it in memory grows with the copy. Then its files where its rows say, from `files` (`<hash>` each). Refused where the station has chats of its own,
/// unless `merge` (a station retired into this one): then each thread is given an id here (one followed by both, the
/// same surface, channel and ts of a platform's, is the one here: its log here stays as it is, the other's sessions join
/// it; still.fail's own chats are each station's, so one whose ts is taken here is given the next free one), what names
/// a thread names it by that id, and a row of a key here already is left as it is; each session's `ws` is `ws` where it
/// is said. `dataDir`: this station's.
export function build(db: string, dir: string, files: string, dataDir: string, now = 0, merge = false, connects: Record<string, string> = {}, ws?: string | null): Built {
  const head = asHead(JSON.parse(readFileSync(headFile(dir), "utf8"))); // sync: in the restore's own thread (restore-worker.ts)
  if (head === null) throw new Error("no copy here, or one of a newer station's");
  const d = new DatabaseSync(db, { timeout: 30_000 });
  const rows: Record<string, number> = {};
  try {
    d.exec(RESTORED);
    const done = d.prepare("SELECT rows FROM replica_restored WHERE origin = ? AND gen = ?").get(head.origin, head.gen) as { rows: string } | undefined;
    if (done === undefined) {
      d.exec("BEGIN IMMEDIATE");
      try {
        const has = (t: string) => d.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(t) !== undefined;
        if (!has("threads") || !has("sessions")) throw new Error("this station's database is not made yet");
        const empty = d.prepare("SELECT 1 FROM threads LIMIT 1").get() === undefined && d.prepare("SELECT 1 FROM sessions LIMIT 1").get() === undefined;
        if (!empty && !merge) throw new NotEmpty();
        // (merged: the ids the copy's threads have here, those followed here already, the rows put in by table)
        const merging = !empty;
        const ids = new Map<number, number>();
        const followed = new Set<number>();
        const put: Record<string, number> = {};
        const columns = new Map<string, Set<string>>();
        const columnsOf = (table: string) => {
          let c = columns.get(table);
          if (c === undefined) columns.set(table, (c = new Set((d.prepare(`SELECT name FROM pragma_table_info('${table}')`).all() as { name: string }[]).map((x) => x.name))));
          return c;
        };
        const statements = new Map<string, ReturnType<DatabaseSync["prepare"]>>();
        const st = (sql: string) => {
          let x = statements.get(sql);
          if (x === undefined) statements.set(sql, (x = d.prepare(sql)));
          return x;
        };
        d.exec("CREATE TEMP TABLE restore_files (path TEXT PRIMARY KEY, hash TEXT NOT NULL) WITHOUT ROWID");
        // Folded first, on disk (what was said again, deleted after, or a pass said twice: each key's last row, nothing
        // of what went), then each row put in once, table by table in RESTORE_ORDER, in the order it was last said: the
        // store's triggers see what a station that made them saw, whichever batches the copy is.
        const work = `${db}.restore-fold`;
        rmSync(work, { force: true }); // sync: in the restore's own thread (restore-worker.ts)
        const folded = new Folded(work);
        try {
          for (const b of head.batches) for (const line of decodeBatch(readFileSync(join(dir, "log", b))).lines) folded.apply(line); // sync: in the restore's own thread (restore-worker.ts)
          for (const line of folded.records()) {
            const rec = JSON.parse(line) as Rec;
            if ("r" in rec) {
              if (!has(rec.r)) continue;
              const r = shaped(rec.r, rec.row, head.dataDir, dataDir);
              // (a connect of the station retired here named as it is here)
              if ((rec.r === "sessions" || rec.r === "thread_sessions") && typeof r.connect === "string" && connects[r.connect] !== undefined) r.connect = connects[r.connect]!;
              // (its workspace as it is said here)
              if (rec.r === "sessions" && merge && ws !== undefined) r.ws = ws;
              // (a column of a newer station's that this one does not have is left out; one this one has and the copy
              // does not say takes its default)
              const have = columnsOf(rec.r);
              if (merging) {
                if (rec.r === "threads") {
                  const was = Number(r.id);
                  const here = st("SELECT id FROM threads WHERE surface = ? AND channel = ? AND thread_ts = ?").get(r.surface as never, r.channel as never, r.thread_ts as never) as { id: number } | undefined;
                  if (here !== undefined) {
                    if (r.surface !== STILLFAIL_SURFACE) {
                      ids.set(was, here.id);
                      followed.add(was);
                      continue;
                    }
                    let ts = String(r.thread_ts);
                    do ts = bumpedTs(ts);
                    while (st("SELECT 1 FROM threads WHERE surface = ? AND channel = ? AND thread_ts = ?").get(r.surface as never, r.channel as never, ts) !== undefined);
                    r.thread_ts = ts;
                  }
                  delete r.id;
                }
                const column = THREAD_COLUMNS[rec.r];
                if (column !== undefined && typeof r[column] === "number") {
                  const was = r[column] as number;
                  const id = ids.get(was);
                  if (rec.r === "turns") {
                    // (what a turn was about, by a thread's own log: kept only where that log came with it)
                    if (id === undefined || followed.has(was)) {
                      r.about_thread = null;
                      r.about_n = null;
                    } else r.about_thread = id;
                  } else {
                    if (id === undefined || (OWN_LOG.has(rec.r) && followed.has(was))) continue;
                    r[column] = id;
                  }
                }
              }
              const cols = Object.keys(r).filter((c) => have.has(c));
              const done = st(`INSERT${merging ? " OR IGNORE" : ""} INTO ${rec.r} (${cols.join(", ")}) VALUES (${cols.map(() => "?").join(", ")})`).run(...cols.map((c) => r[c] as never));
              if (merging) {
                put[rec.r] = (put[rec.r] ?? 0) + Number(done.changes);
                if (rec.r === "threads") ids.set(Number(rec.row.id), Number(done.lastInsertRowid));
              }
            } else if ("file" in rec) {
              st("INSERT OR REPLACE INTO restore_files (path, hash) VALUES (?, ?)").run(moved(rec.path, head.dataDir, dataDir), rec.file);
            }
          }
        } finally {
          folded.close();
          rmSync(work, { force: true }); // sync: in the restore's own thread (restore-worker.ts)
        }
        for (const table of RESTORE_ORDER) if (has(table)) rows[table] = merging ? (put[table] ?? 0) : (d.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
        d.prepare("INSERT INTO replica_restored (origin, gen, at, rows) VALUES (?, ?, ?, ?)").run(head.origin, head.gen, now, JSON.stringify(rows));
        // (where the files go stays beside the rows until they are placed)
        d.exec("CREATE TABLE IF NOT EXISTS replica_restore_files (path TEXT PRIMARY KEY, hash TEXT NOT NULL) WITHOUT ROWID; INSERT OR REPLACE INTO replica_restore_files SELECT path, hash FROM temp.restore_files;");
        d.exec("COMMIT");
      } catch (e) {
        d.exec("ROLLBACK");
        throw e;
      }
    } else Object.assign(rows, JSON.parse(done.rows));
    // The files the rows still name, where they say, a page of rows at a time (placed already: left as they are). One
    // that cannot be placed (the disk full, a folder that cannot be made) leaves what was brought, and where the files
    // go, for the next start to place the rest (`FilesPending`).
    let placed = 0;
    let missing = 0;
    const named = (d.prepare("SELECT COUNT(*) AS n FROM replica_restore_files").get() as { n: number }).n;
    try {
      const where = d.prepare("SELECT hash FROM replica_restore_files WHERE path = ?");
      for (const table of ["entries", "letters"]) {
        for (let after = 0; ; ) {
          const page = d.prepare(`SELECT rowid AS r, attachments FROM ${table} WHERE rowid > ? AND attachments IS NOT NULL AND attachments <> '[]' ORDER BY rowid LIMIT 500`).all(after) as { r: number; attachments: string }[];
          for (const p of page) {
            for (const path of attachedPaths({ attachments: p.attachments })) {
              const f = where.get(path) as { hash: string } | undefined;
              if (f === undefined) continue;
              // (placed by a start before this one)
              if (existsSync(path)) { // sync: in the restore's own thread (restore-worker.ts)
                placed++;
                continue;
              }
              const from = join(files, f.hash);
              if (!existsSync(from)) { // sync: in the restore's own thread (restore-worker.ts)
                missing++;
                continue;
              }
              mkdirSync(dirname(path), { recursive: true }); // sync: in the restore's own thread (restore-worker.ts)
              copyFileSync(from, `${path}.restoring`); // sync: in the restore's own thread (restore-worker.ts)
              renameSync(`${path}.restoring`, path); // sync: in the restore's own thread (restore-worker.ts)
              placed++;
            }
          }
          if (page.length < 500) break;
          after = page[page.length - 1]!.r;
        }
      }
    } catch (e) {
      throw new FilesPending(e as Error, Math.max(0, named - placed - missing));
    }
    d.exec("DELETE FROM replica_restore_files");
    return { rows, files: placed, missing };
  } finally {
    d.close();
  }
}

/// What came of a restore, as the settings say it after the restart (copies.ts `overview`): `error` its words for the
/// log, `reason` the settings' (the station got a chat of its own first, the disk full, or something else); `pending`:
/// its chats are in and their files not all placed yet (`left` of them), the next start placing them.
export type Outcome = { origin: string; name: string; from: string; at: number; rows: Record<string, number>; files: number; missing: number; error: string | null; reason: "notEmpty" | "full" | "error" | null; pending: boolean; left: number };

/// The rows of a restore are in and its files not all placed: what was brought is kept for the next start to place
/// them.
export class FilesPending extends Error {
  /// The files still to be placed.
  readonly left: number;
  constructor(cause: Error, left: number) {
    super(`the chats are in; ${left} of their files not placed yet: ${cause.message}`, { cause });
    this.left = left;
  }
}

/// A copy is taken back only into a station with no chat of its own.
export class NotEmpty extends Error {
  constructor() {
    super("this station has chats of its own: a copy is taken back only into a new one");
  }
}
export const outcomeFile = (data: string) => join(data, "replica", "restored.json");

/// The restore brought to this station before, put in as its store is about to open (main.ts, through Paths
/// `beforeStore`; in a thread of its own, `takeBackSoon`), each step safe to run again where it stopped: its rows (one
/// transaction, which says it was done), its files (those placed already left), that the station took the lost one's
/// place (`formerly`), what came of it (`restored.json`); then what it brought is let go. One that cannot be put in
/// (the station got a chat of its own meanwhile) is let go too, saying why; one whose files could not all be placed is
/// kept, and the next start places them. What it was is said back (null: none waited).
export function takeBack(data: string, db: string, now = 0): Ready | null {
  let ready: Ready;
  try {
    ready = JSON.parse(readFileSync(readyFile(data), "utf8")) as Ready; // sync: in the restore's own thread (restore-worker.ts)
  } catch {
    return null;
  }
  const dir = copyDir(data);
  const outcome: Outcome = { origin: ready.origin, name: ready.name, from: ready.from, at: now, rows: {}, files: 0, missing: 0, error: null, reason: null, pending: false, left: 0 };
  try {
    const built = build(db, join(dir, ready.gen), join(dir, "files"), data, now, ready.merge === true, ready.connects ?? {}, ready.ws);
    addFormerly(data, ready.origin);
    Object.assign(outcome, { rows: built.rows, files: built.files, missing: built.missing });
  } catch (e) {
    outcome.error = (e as Error).message;
    outcome.reason = e instanceof NotEmpty ? "notEmpty" : /ENOSPC|disk is full/i.test(outcome.error) ? "full" : "error";
    if (e instanceof FilesPending) {
      // (the chats are in: the station took the lost one's place; what was brought stays, for the next start)
      addFormerly(data, ready.origin);
      outcome.pending = true;
      outcome.left = e.left;
    }
  }
  mkdirSync(dirname(outcomeFile(data)), { recursive: true }); // sync: in the restore's own thread (restore-worker.ts)
  writeFileSync(`${outcomeFile(data)}.tmp`, JSON.stringify(outcome)); // sync: in the restore's own thread (restore-worker.ts)
  renameSync(`${outcomeFile(data)}.tmp`, outcomeFile(data)); // sync: in the restore's own thread (restore-worker.ts)
  // (let go once its files are placed, or where its rows never went in)
  if (!outcome.pending) rmSync(restoreDir(data), { recursive: true, force: true }); // sync: in the restore's own thread (restore-worker.ts)
  return ready;
}

/// That this station took `origin`'s place (copies.ts `formerlyOf` reads it).
export function addFormerly(data: string, origin: string): void {
  const file = join(data, "replica", "formerly.json");
  let list: string[] = [];
  try {
    list = JSON.parse(readFileSync(file, "utf8")); // sync: in the restore's own thread (restore-worker.ts)
  } catch {}
  if (!list.includes(origin)) list.push(origin);
  mkdirSync(dirname(file), { recursive: true }); // sync: in the restore's own thread (restore-worker.ts)
  writeFileSync(`${file}.tmp`, JSON.stringify(list)); // sync: in the restore's own thread (restore-worker.ts)
  renameSync(`${file}.tmp`, file); // sync: in the restore's own thread (restore-worker.ts)
}

/// `takeBack` off the main thread, where a restore waits (null: none did): by the MoonBit program (station/mb's
/// src/replica, `--builder replica-restore`) where it is built, else in a worker thread.
export async function takeBackSoon(data: string, db: string, now: number, given?: string | null): Promise<Ready | null> {
  if (!existsSync(readyFile(data))) return null; // sync: before the station serves (its store not open yet)
  // (imported here: the restore's own thread, which imports this file, keeps its heap to what it does)
  const { MbProcess, mbReaderBinary } = await import("../read/mb-reader.ts");
  const binary = given === undefined ? mbReaderBinary() : given;
  if (binary !== null) {
    return new Promise((resolve, reject) => {
      const p = new MbProcess(binary, ["--builder", "replica-restore", "--db", db, "--data", data, "--now", String(now), "--sep", sep]);
      let said = false;
      p.once("message", (m: { ready?: Ready | null; error?: string }) => {
        said = true;
        if (m.error !== undefined) reject(new Error(m.error));
        else resolve(m.ready ?? null);
      });
      p.once("error", reject);
      p.once("exit", (code: number) => { if (!said) reject(new Error(`the restore ended saying nothing (${code})`)); });
    });
  }
  const file = new URL(import.meta.url.endsWith(".ts") ? "./restore-worker.ts" : "./replica/restore-worker.js", import.meta.url);
  return new Promise((resolve, reject) => {
    const w = new Worker(file, { workerData: { data, db, now } });
    w.once("message", (m: { ready?: Ready | null; error?: string }) => (m.error !== undefined ? reject(new Error(m.error)) : resolve(m.ready ?? null)));
    w.once("error", reject);
  });
}
