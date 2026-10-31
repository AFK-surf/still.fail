// Files of a station's drive kept on this device once read, for an app that asks it (`drive.read` with `keep`, as
// Android's DriveCache.kt keeps them on the phone): read again, what is kept is answered, not asked of the station
// again. A file is kept by where it is (station, root, path) and as it was (its mtime and size, as its folder says);
// changed on the station, what was kept of it goes and it is read anew. Each part is kept as it was read: its bytes
// in the host's storage (one key each, `drive-kept-…`), what they are in a database of their own (`drive-kept`).
// `file`: a file read whole or from its start (a text read, a picture, a PDF, a file handed to another app or saved);
// `played`: a video or song, by the ranges played. Past a kind's bound the least lately read of it go, never the one
// just read nor one being written (FILES_MAX, PLAYED_MAX). What is kept is counted with the rest the device keeps
// (`cache.usage`'s `drive`) and let go all at once (`drive.kept.clear`).
// A chat's files are kept here too, as Android keeps those its viewers open (ChatFiles.kt toDisk, onDisk: a video, a
// song, a PDF, a big file; `station.file`, `station.file.part` with `keep`): `chat`, by the station, the session and
// the name (a file sent never changes), its size as the message says; none let go by itself, but by the person, a
// file at a time (`cache.file.clear`), a chat's with it (`cache.clear`), and listed with its chat (`cache.usage`).
// A file sent up from this device is kept too, as it went (`sent`, composer.ts), whatever it is: by its station and
// the name the station keeps it under, its chat shows it, opens it and plays it from here, not read back from the
// station it went to; the least lately read go past SENT_MAX, and it is counted and let go with the drives' files.
// A file going up with a message (`outbox`, composer.ts) is kept too as it goes, with what it is and, once up, what
// its station said of it (`noteUpload`): a message whose file had not gone, or whose own sending had not come, when the
// app ended goes on from here as it starts again, not failed for a source the app no longer has. It goes as its message
// is sent or discarded (`dropUpload`), and one left behind a week (a message gone some other way) as the core starts;
// never let go by `clear` while its message waits.
// Where a chat's file was opened (`origin`: its chat, the file as its message has it) is written down beside it while
// any of it is kept, so what lists it (fill.ts, views/downloads.ts) leads back there.
// A chat's file a person asked to load (加载, `wanted`) is written down too, whatever of it is kept yet (none at
// first): fill.ts brings it before everything else, and goes on with it as the core starts again, until all of it is
// kept or the person stops it.
// The downloads asked of this device and not yet saved are written down here too (views/downloads.ts), beside the
// files they bring: one stopped by the app's end goes on as it starts again. A chat's file saved where the person
// keeps files, where the app can read it back (Host.savedRead), is that file's copy on the device: what was kept of it
// goes, and it is read from where it was saved (`saved`) until it is no longer there (moved, deleted, changed), then
// read and kept as any other again.
import { Effect } from "effect";
import type { Host, Sql } from "./host.ts";

export type KeepKind = "file" | "played" | "chat" | "sent" | "outbox";

/// Files read whole or from their start: the least lately read go past this (DriveCache.kt FILES_MAX).
export const FILES_MAX = 512 * 1024 * 1024;
/// Videos and songs, by the ranges played (DriveCache.kt PLAYED_MAX).
export const PLAYED_MAX = 1536 * 1024 * 1024;
/// Files sent up from here: the least lately read go past this (a phone's video alone can be a few hundred MB).
export const SENT_MAX = 1024 * 1024 * 1024;
/// How long a file going up with a message is kept for it at most: one left behind (its message gone some other way).
export const OUTBOX_KEPT_MS = 7 * 24 * 3600_000;
/// How seldom a file's last reading is written down: a video read a part a second is not a write a second.
const USED_EVERY_MS = 60_000;

/// What a file is kept as, by `keptId`.
type Kept = { kind: KeepKind; mtime: number; size: number; type: string; used: number };
/// A part of it: from `at`, `length` bytes, kept under `key`.
type Part = { at: number; length: number; key: string };

/// A file's own name among those kept: where it is.
export function keptId(station: string, root: string, path: string): string {
  return `${station}\n${root}\n${path}`;
}

/// A chat's file's own name among those kept: its station, its session, its name (`chat` first: no station's is so).
export function chatKeptId(station: string, key: string, name: string): string {
  return `chat\n${station}\n${key}\n${name}`;
}

/// A file sent up from here, among those kept: its station, and the name the station keeps it under (unique there, and
/// kept as it moves the file into the chat's uploads), whichever chat it is in (`sent` first: no station's is so).
export function sentKeptId(station: string, name: string): string {
  return `sent\n${station}\n${name}`;
}

/// A file going up with a message, among those kept: its upload's id (`outbox` first: no station's is so).
export function outboxKeptId(id: string): string {
  return `outbox\n${id}`;
}

/// A file kept in part (`unfinished`): what it is kept as, `have` bytes of it, the first of it not kept (`at`,
/// `length` bytes on from there); whether a person asked to load it (`wanted`).
export type Unfinished = { id: string; kind: KeepKind; mtime: number; size: number; have: number; at: number; length: number; wanted: boolean };

/// A chat's file kept: where it is, its size, the bytes kept of it (fewer: a part of it read), when it was last read.
export type ChatKept = { station: string; key: string; name: string; size: number; bytes: number; used: number };

export class DriveKept {
  readonly #host: Host;
  /// How much of each kind is kept at most.
  readonly #most: Record<KeepKind, number>;
  /// undefined: not opened yet; null: nothing to keep it in (a host without databases, or one that would not open).
  #sql: Sql | null | undefined = undefined;
  /// Files a part of which is being written, how many: not let go meanwhile.
  readonly #writing = new Map<string, number>();

  constructor(host: Host, most: Record<KeepKind, number> = { file: FILES_MAX, played: PLAYED_MAX, chat: Number.POSITIVE_INFINITY, sent: SENT_MAX, outbox: Number.POSITIVE_INFINITY }) {
    this.#host = host;
    this.#most = most;
  }

  #db(): Effect.Effect<Sql | null> {
    if (this.#sql !== undefined) return Effect.succeed(this.#sql);
    const open = this.#host.openDb;
    if (open === undefined) return Effect.succeed((this.#sql = null));
    return Effect.map(Effect.result(open.call(this.#host, "drive-kept")), (opened) => {
      if (this.#sql !== undefined) return this.#sql;
      if (opened._tag === "Failure") return (this.#sql = null);
      try {
        opened.success.exec(`CREATE TABLE IF NOT EXISTS kept (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL, mtime INTEGER NOT NULL, size INTEGER NOT NULL, type TEXT NOT NULL,
          used INTEGER NOT NULL
        ); CREATE TABLE IF NOT EXISTS part (
          id TEXT NOT NULL, at INTEGER NOT NULL, length INTEGER NOT NULL, key TEXT NOT NULL, PRIMARY KEY (id, at, length)
        ); CREATE TABLE IF NOT EXISTS download (id TEXT PRIMARY KEY, json TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS saved (id TEXT PRIMARY KEY, at TEXT NOT NULL, size INTEGER NOT NULL, type TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS upload (id TEXT PRIMARY KEY, json TEXT NOT NULL, at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS origin (id TEXT PRIMARY KEY, json TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS wanted (id TEXT PRIMARY KEY, kind TEXT NOT NULL, size INTEGER NOT NULL);`);
        return (this.#sql = opened.success);
      } catch {
        return (this.#sql = null);
      }
    });
  }

  #kept(sql: Sql, id: string): Kept | null {
    const r = sql.all("SELECT kind, mtime, size, type, used FROM kept WHERE id = ?", [id])[0];
    if (r === undefined) return null;
    return { kind: r[0] === "played" || r[0] === "chat" || r[0] === "sent" || r[0] === "outbox" ? r[0] : "file", mtime: Number(r[1]), size: Number(r[2]), type: String(r[3] ?? ""), used: Number(r[4]) };
  }

  /// A file and its parts let go: their rows at once, their bytes after.
  #drop(sql: Sql, id: string): Effect.Effect<void> {
    const keys = sql.all("SELECT key FROM part WHERE id = ?", [id]).map((r) => String(r[0]));
    sql.run("DELETE FROM part WHERE id = ?", [id]);
    sql.run("DELETE FROM kept WHERE id = ?", [id]);
    sql.run("DELETE FROM origin WHERE id = ?", [id]);
    sql.run("DELETE FROM wanted WHERE id = ?", [id]);
    return this.#forget(keys);
  }

  #forget(keys: string[]): Effect.Effect<void> {
    return Effect.forEach(keys, (key) => Effect.ignore(this.#host.storageDelete(key), { log: "Unhandled", message: "drive upload removed" }), { discard: true });
  }

  /// Bytes `offset` to `offset + length` of the file `id` as it was (`mtime`, `size`), with its type, if they are kept
  /// (and it is written down as read now); else null. What was kept of it as it was before it changed goes.
  read(id: string, mtime: number, size: number, offset: number, length: number): Effect.Effect<{ type: string; bytes: Uint8Array } | null> {
    return Effect.map(this.from(id, mtime, size, offset, length), (got) => (got !== null && got.bytes.length === Math.max(0, Math.min(offset + length, size) - offset) ? got : null));
  }

  /// Bytes from `offset` (`length` at most) of the file `id` as it was (`mtime`, `size`), as far as they are kept on from
  /// there, with its type: all of them, fewer (those up to the first byte not kept), or null when none from `offset` is.
  /// What was kept of it as it was before it changed goes.
  from(id: string, mtime: number, size: number, offset: number, length: number): Effect.Effect<{ type: string; bytes: Uint8Array } | null> {
    return Effect.gen({ self: this }, function* () {
      const sql = yield* this.#db();
      if (sql === null) return null;
      const saved = yield* this.#savedRead(sql, id, size, offset, length);
      if (saved !== null) return saved;
      const kept = this.#kept(sql, id);
      if (kept === null) return null;
      if (kept.mtime !== mtime || kept.size !== size) {
        if (!this.#writing.has(id)) yield* this.#drop(sql, id);
        return null;
      }
      const end = Math.min(offset + length, size);
      const out = new Uint8Array(Math.max(0, end - offset));
      // The parts that hold it from its start on: at each byte not yet had, of those begun by then the one that
      // reaches furthest.
      const parts: Part[] = sql
        .all("SELECT at, length, key FROM part WHERE id = ? AND at < ? AND at + length > ? ORDER BY at", [id, end, offset])
        .map((r) => ({ at: Number(r[0]), length: Number(r[1]), key: String(r[2]) }));
      let at = offset;
      while (at < end) {
        let best: Part | null = null;
        for (const p of parts) if (p.at <= at && p.at + p.length > at && (best === null || p.at + p.length > best.at + best.length)) best = p;
        if (best === null) break;
        const bytes = yield* Effect.orElseSucceed(this.#host.storageGet(best.key), () => null);
        if (bytes === null || bytes.length !== best.length) {
          // Gone from under it (the storage cleared by the system, or the part never written whole).
          sql.run("DELETE FROM part WHERE id = ? AND at = ? AND length = ?", [id, best.at, best.length]);
          break;
        }
        const to = Math.min(end, best.at + best.length);
        out.set(bytes.subarray(at - best.at, to - best.at), at - offset);
        at = to;
      }
      if (at === offset && end > offset) return null;
      const now = this.#host.nowMs();
      if (now - kept.used >= USED_EVERY_MS) sql.run("UPDATE kept SET used = ? WHERE id = ?", [now, id]);
      return { type: kept.type, bytes: at === end ? out : out.subarray(0, at - offset) };
    });
  }

  /// How far on from `at` (to `end` at most) the file `id` (as it was: `mtime`, `size`) is kept without a break, as its
  /// parts say (their bytes not read): `at` when the byte there is not kept.
  keptUntil(id: string, mtime: number, size: number, at: number, end: number): Effect.Effect<number> {
    return Effect.map(this.#db(), (sql) => {
      const kept = sql === null ? null : this.#kept(sql, id);
      if (sql === null || kept === null || kept.mtime !== mtime || kept.size !== size) return at;
      let to = at;
      for (const r of sql.all("SELECT at, length FROM part WHERE id = ? AND at + length > ? AND at < ? ORDER BY at", [id, at, end])) {
        const [from, length] = [Number(r[0]), Number(r[1])];
        if (from > to) break;
        to = Math.max(to, from + length);
      }
      return Math.min(to, end);
    });
  }

  /// Where the next part kept of the file `id` (as it was: `mtime`, `size`) begins after `at` and before `end`; `end`
  /// when none does. From `at` (a byte not kept) to there is what is not kept: what alone is asked of the station.
  nextKept(id: string, mtime: number, size: number, at: number, end: number): Effect.Effect<number> {
    return Effect.map(this.#db(), (sql) => {
      const kept = sql === null ? null : this.#kept(sql, id);
      if (sql === null || kept === null || kept.mtime !== mtime || kept.size !== size) return end;
      const r = sql.all("SELECT min(at) FROM part WHERE id = ? AND at > ? AND at < ?", [id, at, end])[0];
      return r === undefined || r[0] === null || r[0] === undefined ? end : Number(r[0]);
    });
  }

  /// Bytes `offset` to `offset + length` of the file `id` kept as it was once and for all (a sent one: its size is what
  /// was kept), with its type and whole size, if they are all kept; else null.
  held(id: string, offset = 0, length = Number.POSITIVE_INFINITY): Effect.Effect<{ type: string; size: number; bytes: Uint8Array } | null> {
    return Effect.flatMap(this.#db(), (sql) => {
      const kept = sql === null ? null : this.#kept(sql, id);
      if (kept === null) return Effect.succeed(null);
      return Effect.map(this.read(id, kept.mtime, kept.size, offset, length), (got) => (got === null ? null : { ...got, size: kept.size }));
    });
  }

  /// Keeps a part of the file `id` read from `offset`, as the station said the file is (`mtime`, `size`, `type`); then
  /// lets the least lately read of its kind go while they are past its bound. What was kept of it as it was before
  /// goes; a part kept already is not again.
  keep(id: string, kind: KeepKind, mtime: number, size: number, type: string, offset: number, bytes: Uint8Array): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (bytes.length === 0) return;
      const sql = yield* this.#db();
      if (sql === null) return;
      const kept = this.#kept(sql, id);
      const now = this.#host.nowMs();
      if (kept !== null && (kept.mtime !== mtime || kept.size !== size)) {
        if (this.#writing.has(id)) return;
        yield* this.#drop(sql, id);
      }
      if (kept === null || kept.mtime !== mtime || kept.size !== size) {
        sql.run("INSERT INTO kept (id, kind, mtime, size, type, used) VALUES (?, ?, ?, ?, ?, ?)", [id, kind, mtime, size, type, now]);
      } else if (now - kept.used >= USED_EVERY_MS) sql.run("UPDATE kept SET used = ? WHERE id = ?", [now, id]);
      if (sql.all("SELECT 1 FROM part WHERE id = ? AND at = ? AND length = ?", [id, offset, bytes.length]).length > 0) return;
      const name = new Uint8Array(12);
      this.#host.randomBytes(name);
      const key = `drive-kept-${[...name].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
      // Its row first: what is in the storage is always what a row says (a part whose writing stopped is found short).
      sql.run("INSERT INTO part (id, at, length, key) VALUES (?, ?, ?, ?)", [id, offset, bytes.length, key]);
      this.#writing.set(id, (this.#writing.get(id) ?? 0) + 1);
      const wrote = yield* Effect.result(this.#host.storageSet(key, bytes));
      const left = (this.#writing.get(id) ?? 1) - 1;
      if (left > 0) this.#writing.set(id, left);
      else this.#writing.delete(id);
      if (wrote._tag === "Failure") {
        sql.run("DELETE FROM part WHERE key = ?", [key]);
        yield* this.#forget([key]);
        return;
      }
      yield* this.#trim(sql, kind, id);
    });
  }

  /// The least lately read of `kind` let go while they are past its bound: never `keep`, nor one being written.
  #trim(sql: Sql, kind: KeepKind, keep: string): Effect.Effect<void> {
    const most = this.#most[kind];
    const rows = sql.all("SELECT k.id, coalesce(sum(p.length), 0) FROM kept k LEFT JOIN part p ON p.id = k.id WHERE k.kind = ? GROUP BY k.id ORDER BY k.used DESC, k.id", [kind]);
    const drop: string[] = [];
    let total = 0;
    for (const r of rows) {
      const [id, n] = [String(r[0]), Number(r[1])];
      total += n;
      if (total <= most || id === keep || this.#writing.has(id)) continue;
      drop.push(id);
      total -= n;
    }
    return Effect.forEach(drop, (id) => this.#drop(sql, id), { discard: true });
  }

  /// Whether all of the file `id`, `size` long, is kept (its parts from its start to its end, one after another).
  whole(id: string, size: number): Effect.Effect<boolean> {
    return Effect.map(this.#db(), (sql) => {
      const kept = sql === null ? null : this.#kept(sql, id);
      if (sql === null || kept === null || kept.size !== size) return false;
      let end = 0;
      for (const r of sql.all("SELECT at, length FROM part WHERE id = ? ORDER BY at", [id])) {
        const [at, length] = [Number(r[0]), Number(r[1])];
        if (at > end) return false;
        end = Math.max(end, at + length);
      }
      return end >= size;
    });
  }

  /// The files of `kinds` a part of which is kept and not all (`have` bytes of it), read since `since` (ms), the most lately read first,
  /// each with where the first of it not kept is (`at`, `length` bytes on from there): those whose rest fits in what
  /// their kind keeps beside all else kept of it (bringing it would not push out another, nor then itself), and none
  /// being written now. Those a person asked to load (`want`) first, however long ago and however little of them is
  /// kept (none yet: all of it from its start).
  unfinished(kinds: readonly KeepKind[], since = 0): Effect.Effect<Unfinished[]> {
    return Effect.map(this.#db(), (sql) => {
      if (sql === null) return [];
      const found: (Unfinished & { used: number })[] = [];
      const wanted = new Map(sql.all("SELECT id, kind, size FROM wanted").map((r) => [String(r[0]), { kind: String(r[1]), size: Number(r[2]) }] as const));
      for (const kind of kinds) {
        const rows = sql.all("SELECT k.id, k.mtime, k.size, k.used FROM kept k WHERE k.kind = ?", [kind]);
        const parts = new Map<string, [number, number][]>();
        for (const r of sql.all("SELECT p.id, p.at, p.length FROM part p JOIN kept k ON k.id = p.id WHERE k.kind = ? ORDER BY p.id, p.at", [kind])) {
          const id = String(r[0]);
          let of = parts.get(id);
          if (of === undefined) parts.set(id, (of = []));
          of.push([Number(r[1]), Number(r[2])]);
        }
        let total = 0;
        for (const of of parts.values()) for (const [, length] of of) total += length;
        const seen = new Set<string>();
        for (const r of rows) {
          const [id, mtime, size, used] = [String(r[0]), Number(r[1]), Number(r[2]), Number(r[3])];
          seen.add(id);
          const want = wanted.has(id);
          const of = parts.get(id) ?? [];
          if ((of.length === 0 && !want) || (used < since && !want) || this.#writing.has(id)) continue;
          // the first byte not kept, and the first kept after it
          let end = 0;
          let gap: [number, number] | null = null;
          let have = 0;
          for (const [at, length] of of) {
            if (gap === null && at > end) gap = [end, at];
            have += Math.max(0, at + length - Math.max(at, end));
            end = Math.max(end, at + length);
          }
          if (gap === null && end < size) gap = [end, size];
          if (gap === null || (!want && total - have + size > this.#most[kind])) continue;
          found.push({ id, kind, mtime, size, have: Math.min(have, size), at: gap[0], length: gap[1] - gap[0], wanted: want, used });
        }
        // asked to load, none of it kept yet
        for (const [id, w] of wanted) {
          if (w.kind !== kind || seen.has(id) || this.#writing.has(id) || w.size <= 0) continue;
          found.push({ id, kind, mtime: 0, size: w.size, have: 0, at: 0, length: w.size, wanted: true, used: Number.POSITIVE_INFINITY });
        }
      }
      return found.sort((a, b) => Number(b.wanted) - Number(a.wanted) || b.used - a.used || (a.id < b.id ? -1 : 1)).map(({ used: _, ...f }) => f);
    });
  }

  /// The chat's file `id`, `size` long, asked to be loaded (加载): written down, brought before everything else
  /// (`unfinished`) until all of it is kept or it is no longer wanted.
  want(id: string, kind: KeepKind, size: number): Effect.Effect<void> {
    return Effect.map(this.#db(), (sql) => { sql?.run("INSERT OR REPLACE INTO wanted (id, kind, size) VALUES (?, ?, ?)", [id, kind, size]); });
  }

  /// The file `id` no longer asked to be loaded, nor brought as one opened and let go (where it was opened forgotten):
  /// what is kept of it stays kept, read from here as before.
  unwant(id: string): Effect.Effect<void> {
    return Effect.map(this.#db(), (sql) => {
      sql?.run("DELETE FROM wanted WHERE id = ?", [id]);
      sql?.run("DELETE FROM origin WHERE id = ?", [id]);
    });
  }

  /// Whether a person asked to load the file `id` and it is not all here yet.
  wanted(id: string): Effect.Effect<boolean> {
    return Effect.map(this.#db(), (sql) => sql !== null && sql.all("SELECT 1 FROM wanted WHERE id = ?", [id]).length > 0);
  }

  /// The file `id` all kept: no longer asked to be loaded (where it was opened stays, for what lists it).
  loaded(id: string): Effect.Effect<void> {
    return Effect.map(this.#db(), (sql) => { sql?.run("DELETE FROM wanted WHERE id = ?", [id]); });
  }

  /// What is kept of the file `id` let go (found changed on the station), unless a part of it is being written.
  forget(id: string): Effect.Effect<void> {
    return Effect.flatMap(this.#db(), (sql) => (sql === null || this.#writing.has(id) ? Effect.void : this.#drop(sql, id)));
  }

  /// The file `from`, kept whole at its `size`, kept on as `to` of `kind` instead (its bytes where they are, nothing
  /// read or written again), what was kept as `to` before let go; then the least lately read of `kind` past its bound.
  /// False, and nothing changes, when it is not whole or a part of it is being written.
  rename(from: string, to: string, kind: KeepKind, size: number): Effect.Effect<boolean> {
    return Effect.gen({ self: this }, function* () {
      const sql = yield* this.#db();
      if (sql === null || this.#writing.has(from) || this.#writing.has(to) || !(yield* this.whole(from, size))) return false;
      if (this.#kept(sql, to) !== null) yield* this.#drop(sql, to);
      sql.run("UPDATE kept SET id = ?, kind = ?, used = ? WHERE id = ?", [to, kind, this.#host.nowMs(), from]);
      sql.run("UPDATE part SET id = ? WHERE id = ?", [to, from]);
      sql.run("DELETE FROM origin WHERE id = ?", [from]);
      yield* this.#trim(sql, kind, to);
      return true;
    });
  }

  /// Whether anything of the file `id` is kept (or it was saved where it can be read back).
  has(id: string): Effect.Effect<boolean> {
    return Effect.map(this.#db(), (sql) => sql !== null && (this.#kept(sql, id) !== null || sql.all("SELECT 1 FROM saved WHERE id = ?", [id]).length > 0));
  }

  /// Bytes `offset` to `offset + length` of the file `id` read from where it was saved, when it was (at its `size`) and
  /// they are all still there; else null, and once it is found gone or changed it is no longer taken as saved.
  #savedRead(sql: Sql, id: string, size: number, offset: number, length: number): Effect.Effect<{ type: string; bytes: Uint8Array } | null> {
    const r = sql.all("SELECT at, size, type FROM saved WHERE id = ?", [id])[0];
    const read = this.#host.savedRead;
    if (r === undefined || read === undefined) return Effect.succeed(null);
    const [at, was, type] = [String(r[0]), Number(r[1]), String(r[2])];
    const end = Math.min(offset + length, size);
    const gone = () => { sql.run("DELETE FROM saved WHERE id = ?", [id]); return null; };
    if (was !== size) return Effect.sync(gone);
    return Effect.map(Effect.orElseSucceed(read.call(this.#host, at, offset, end), () => null), (bytes) =>
      bytes !== null && bytes.length === Math.max(0, end - offset) ? { type, bytes } : gone());
  }

  /// The chat's file `id` saved where the person keeps files (`at`, as the system named it), its whole `size`: when it
  /// can be read back there (its last byte read), that is its copy on the device and what was kept of it goes (true);
  /// else nothing changes (false).
  saved(id: string, at: string, size: number): Effect.Effect<boolean> {
    return Effect.gen({ self: this }, function* () {
      const sql = yield* this.#db();
      const read = this.#host.savedRead;
      if (sql === null || read === undefined || at === "" || size <= 0) return false;
      const last = yield* Effect.orElseSucceed(read.call(this.#host, at, size - 1, size), () => null);
      if (last === null || last.length !== 1) return false;
      const type = this.#kept(sql, id)?.type ?? "";
      sql.run("INSERT OR REPLACE INTO saved (id, at, size, type) VALUES (?, ?, ?, ?)", [id, at, size, type]);
      if (!this.#writing.has(id)) yield* this.#drop(sql, id);
      return true;
    });
  }

  /// Where the file `id` was opened (KeptFrom, as its viewer said it), written down while any of it is kept.
  noteFrom(id: string, from: unknown): Effect.Effect<void> {
    return Effect.map(this.#db(), (sql) => { sql?.run("INSERT OR REPLACE INTO origin (id, json) VALUES (?, ?)", [id, JSON.stringify(from)]); });
  }

  /// Where each of the files `ids` was opened, those written down.
  fromOf(ids: readonly string[]): Effect.Effect<Map<string, unknown>> {
    return Effect.map(this.#db(), (sql) => {
      const out = new Map<string, unknown>();
      if (sql === null) return out;
      for (const id of ids) {
        const r = sql.all("SELECT json FROM origin WHERE id = ?", [id])[0];
        if (r === undefined) continue;
        try {
          out.set(id, JSON.parse(String(r[0])));
        } catch {
          // (not one this core can read: left out)
        }
      }
      return out;
    });
  }

  /// The downloads written down (views/downloads.ts), each as it was written: the oldest first.
  downloads(): Effect.Effect<unknown[]> {
    return Effect.map(this.#db(), (sql) => {
      if (sql === null) return [];
      const out: unknown[] = [];
      for (const r of sql.all("SELECT json FROM download ORDER BY rowid")) {
        try {
          out.push(JSON.parse(String(r[0])));
        } catch {
          // (not one this core can read: left out)
        }
      }
      return out;
    });
  }

  /// A download written down (again), by its id.
  noteDownload(id: string, value: unknown): Effect.Effect<void> {
    return Effect.map(this.#db(), (sql) => { sql?.run("INSERT OR REPLACE INTO download (id, json) VALUES (?, ?)", [id, JSON.stringify(value)]); });
  }

  /// A download no longer written down (saved, or called off).
  dropDownload(id: string): Effect.Effect<void> {
    return Effect.map(this.#db(), (sql) => { sql?.run("DELETE FROM download WHERE id = ?", [id]); });
  }

  /// A file going up with a message written down (again) by its upload's id: what it is, and once up what its station
  /// said of it.
  noteUpload(id: string, value: unknown): Effect.Effect<void> {
    return Effect.map(this.#db(), (sql) => { sql?.run("INSERT OR REPLACE INTO upload (id, json, at) VALUES (?, ?, ?)", [id, JSON.stringify(value), this.#host.nowMs()]); });
  }

  /// What is written down of the file going up as upload `id`, or null.
  uploadNoted(id: string): Effect.Effect<unknown> {
    return Effect.map(this.#db(), (sql) => {
      const r = sql?.all("SELECT json FROM upload WHERE id = ?", [id])[0];
      if (r === undefined) return null;
      try {
        return JSON.parse(String(r[0]));
      } catch {
        return null;
      }
    });
  }

  /// The file going up as upload `id` no longer kept: written down or its bytes (its message sent or discarded).
  dropUpload(id: string): Effect.Effect<void> {
    return Effect.flatMap(this.#db(), (sql) => {
      sql?.run("DELETE FROM upload WHERE id = ?", [id]);
      return this.forget(outboxKeptId(id));
    });
  }

  /// The files going up with messages left behind longer than OUTBOX_KEPT_MS let go (as the core starts).
  dropOldUploads(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const sql = yield* this.#db();
      if (sql === null) return;
      const old = sql.all("SELECT id FROM upload WHERE at < ?", [this.#host.nowMs() - OUTBOX_KEPT_MS]).map((r) => String(r[0]));
      for (const id of old) yield* this.dropUpload(id);
      // (bytes whose note is gone: their writing stopped as the app ended)
      for (const r of sql.all("SELECT k.id FROM kept k WHERE k.kind = 'outbox' AND NOT EXISTS (SELECT 1 FROM upload u WHERE 'outbox' || char(10) || u.id = k.id)")) {
        yield* this.forget(String(r[0]));
      }
    });
  }

  /// The bytes kept of the drives' files and of those sent from here (not the chats').
  usage(): Effect.Effect<number> {
    return Effect.map(this.#db(), (sql) =>
      sql === null ? 0 : Number(sql.all("SELECT coalesce(sum(p.length), 0) FROM part p JOIN kept k ON k.id = p.id WHERE k.kind != 'chat'")[0]?.[0] ?? 0),
    );
  }

  /// The drives' files kept and those sent from here let go (read from the stations again when opened), but what is
  /// being written.
  clear(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const sql = yield* this.#db();
      if (sql === null) return;
      for (const r of sql.all("SELECT id FROM kept WHERE kind != 'chat' AND kind != 'outbox'")) {
        const id = String(r[0]);
        if (!this.#writing.has(id)) yield* this.#drop(sql, id);
      }
    });
  }

  /// The chats' files kept, the most lately read first.
  chatFiles(): Effect.Effect<ChatKept[]> {
    return Effect.map(this.#db(), (sql) => {
      if (sql === null) return [];
      const rows = sql.all("SELECT k.id, k.size, k.used, coalesce(sum(p.length), 0) FROM kept k LEFT JOIN part p ON p.id = k.id WHERE k.kind = 'chat' GROUP BY k.id ORDER BY k.used DESC, k.id");
      const out: ChatKept[] = [];
      for (const r of rows) {
        const [, station, key, ...name] = String(r[0]).split("\n");
        if (station === undefined || key === undefined || name.length === 0) continue;
        out.push({ station, key, name: name.join("\n"), size: Number(r[1]), bytes: Number(r[3]), used: Number(r[2]) });
      }
      return out;
    });
  }

  /// The files kept of a station's sessions `keys` let go (a chat's, as its messages are), but what is being written.
  forgetChat(station: string, keys: readonly string[]): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const files = yield* this.chatFiles();
      for (const f of files) if (f.station === station && keys.includes(f.key)) yield* this.forget(chatKeptId(f.station, f.key, f.name));
    });
  }
}
