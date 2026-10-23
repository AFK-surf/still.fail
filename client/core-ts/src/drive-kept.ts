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
// An image sent up from this device is kept too, as it went (`sent`, composer.ts): by its station and the name the
// station keeps it under, its chat shows it and opens it from here, not read back from the station it went to; the
// least lately read go past SENT_MAX, and it is counted and let go with the drives' files.
import { Effect } from "effect";
import type { Host, Sql } from "./host.ts";

export type KeepKind = "file" | "played" | "chat" | "sent";

/// Files read whole or from their start: the least lately read go past this (DriveCache.kt FILES_MAX).
export const FILES_MAX = 512 * 1024 * 1024;
/// Videos and songs, by the ranges played (DriveCache.kt PLAYED_MAX).
export const PLAYED_MAX = 1536 * 1024 * 1024;
/// Images sent up from here: the least lately read go past this.
export const SENT_MAX = 256 * 1024 * 1024;
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

  constructor(host: Host, most: Record<KeepKind, number> = { file: FILES_MAX, played: PLAYED_MAX, chat: Number.POSITIVE_INFINITY, sent: SENT_MAX }) {
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
        );`);
        return (this.#sql = opened.success);
      } catch {
        return (this.#sql = null);
      }
    });
  }

  #kept(sql: Sql, id: string): Kept | null {
    const r = sql.all("SELECT kind, mtime, size, type, used FROM kept WHERE id = ?", [id])[0];
    if (r === undefined) return null;
    return { kind: r[0] === "played" || r[0] === "chat" || r[0] === "sent" ? r[0] : "file", mtime: Number(r[1]), size: Number(r[2]), type: String(r[3] ?? ""), used: Number(r[4]) };
  }

  /// A file and its parts let go: their rows at once, their bytes after.
  #drop(sql: Sql, id: string): Effect.Effect<void> {
    const keys = sql.all("SELECT key FROM part WHERE id = ?", [id]).map((r) => String(r[0]));
    sql.run("DELETE FROM part WHERE id = ?", [id]);
    sql.run("DELETE FROM kept WHERE id = ?", [id]);
    return this.#forget(keys);
  }

  #forget(keys: string[]): Effect.Effect<void> {
    return Effect.forEach(keys, (key) => Effect.ignore(this.#host.storageDelete(key)), { discard: true });
  }

  /// Bytes `offset` to `offset + length` of the file `id` as it was (`mtime`, `size`), with its type, if they are kept
  /// (and it is written down as read now); else null. What was kept of it as it was before it changed goes.
  read(id: string, mtime: number, size: number, offset: number, length: number): Effect.Effect<{ type: string; bytes: Uint8Array } | null> {
    return Effect.gen({ self: this }, function* () {
      const sql = yield* this.#db();
      if (sql === null) return null;
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
        if (best === null) return null;
        const bytes = yield* Effect.orElseSucceed(this.#host.storageGet(best.key), () => null);
        if (bytes === null || bytes.length !== best.length) {
          // Gone from under it (the storage cleared by the system, or the part never written whole).
          sql.run("DELETE FROM part WHERE id = ? AND at = ? AND length = ?", [id, best.at, best.length]);
          return null;
        }
        const to = Math.min(end, best.at + best.length);
        out.set(bytes.subarray(at - best.at, to - best.at), at - offset);
        at = to;
      }
      const now = this.#host.nowMs();
      if (now - kept.used >= USED_EVERY_MS) sql.run("UPDATE kept SET used = ? WHERE id = ?", [now, id]);
      return { type: kept.type, bytes: out };
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

  /// What is kept of the file `id` let go (found changed on the station), unless a part of it is being written.
  forget(id: string): Effect.Effect<void> {
    return Effect.flatMap(this.#db(), (sql) => (sql === null || this.#writing.has(id) ? Effect.void : this.#drop(sql, id)));
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
      for (const r of sql.all("SELECT id FROM kept WHERE kind != 'chat'")) {
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
