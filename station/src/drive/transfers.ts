// Files copied (or moved) into this station's drive (docs/drive.md "Copying between stations"): from a folder of its
// own, or from another station of the workspace, whose files this station reads over the station transport with what
// that station granted the member who asked (`grants.ts`). Each is a transfer of its own here, on the station the files
// go to, so it goes on whatever becomes of the page that started it: one at a time, in the order asked, each file put
// together beside where it goes as an upload is (drive.ts `upload`) and put there whole, the transfer kept on disk as it
// goes, so a station that restarts takes it up where it was. A move lets the originals go (to their machine's trash)
// once every file is in place.
//
// What is copied is walked first (`walk`): the folders and files under the names given, as the source finds them (the
// station's own data and, for a read-only member, what leads out of a pinned folder left out, as listings leave them
// out); links are not followed. A name already where it goes was answered before the transfer began (the page asks):
// replaced (the one there to the trash first), kept beside under a name of its own (`free`), or skipped.
import { randomUUID } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { platform } from "../platform/index.ts";
import { log } from "../ops/log.ts";
import { type Drive, DriveError, type Entry, MAX_READ } from "./drive.ts";

type Json = any;

/// One thing a transfer copies, relative to the folder its names are in (`/` between components): a folder made, or a
/// file of `size` (as the source found it when walking).
export type Item = { path: string; dir: boolean; size: number };
export type Conflict = "replace" | "keep" | "skip";
export type State = "queued" | "walking" | "copying" | "done" | "failed" | "cancelled";

/// Where the files come from: walked, read a part at a time, and let go of (a move) once all are in place.
export interface Source {
  readonly station: string | null;
  walk(names: string[]): Promise<{ items: Item[] }>;
  read(path: string, offset: number, length: number): Promise<{ bytes: Buffer; size: number; mtime: number }>;
  release(names: string[]): Promise<void>;
  /// The most one read gives.
  readonly part: number;
}

/// A transfer as it is kept and as the pages are told it.
export type Transfer = {
  id: string;
  by: string;
  /// The workspace it was asked in, and whether that is the station's own (its drive's pinned folders: driveOf).
  workspace: string;
  home: boolean;
  /// Whether the asker reaches every folder here (a member who may write).
  anywhere: boolean;
  move: boolean;
  /// Where the files are: another station's (its id and what it granted) or this one's (`station` null), the folder the
  /// names are in, and the names.
  from: { station: string | null; stationName?: string; grant?: string; root: string; path: string; names: string[] };
  to: { root: string; path: string };
  /// What each name already there was answered (names not in it are not there).
  conflicts: Record<string, Conflict>;
  state: State;
  /// What is copied, once walked; `done` of them in place, the next one `at` bytes in.
  items: Item[];
  done: number;
  at: number;
  /// Bytes in all, and copied.
  total: number;
  copied: number;
  /// The names as they are where they go (a name kept beside another: its own).
  placed: Record<string, string>;
  error?: string;
  createdAt: number;
  endedAt?: number;
};

/// Ended transfers are kept to be shown this long.
const KEPT_MS = 24 * 3600 * 1000;
/// At most this many things in one transfer.
export const MOST_ITEMS = 100_000;
/// Progress is written to disk at most this often while a file goes (every file's end is written).
const SAVE_EVERY_MS = 2000;

const key = (path: string) => platform.paths.key(path);
const join2 = (a: string, b: string) => (a === "" ? b : b === "" ? a : `${a}/${b}`);
const top = (path: string) => path.split("/")[0]!;

/// A name beside those taken, as Finder keeps both: `a 2.txt`, `a 3.txt`; a folder `b 2`.
export function free(name: string, dir: boolean, taken: (name: string) => boolean): string {
  const dot = dir ? -1 : name.lastIndexOf(".");
  const [stem, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
  for (let n = 2; ; n++) {
    const next = `${stem} ${n}${ext}`;
    if (!taken(next)) return next;
  }
}

/// A transfer as the pages are told it: without its list of what it copies.
export function shown(t: Transfer): Json {
  const { items, placed: _placed, ...rest } = t;
  const files = items.filter((i) => !i.dir).length;
  return { ...rest, count: items.length, files, ...(t.state === "copying" && items[t.done] ? { current: items[t.done]!.path } : {}) };
}

/// The folders and files under `names` of `path` in a drive, as the asker reaches them: folders before what is in them,
/// links left out (a listing follows them; a copy does not go where one leads), at most MOST_ITEMS.
export async function walkDrive(drive: Drive, root: string, path: string, names: string[], anywhere: boolean): Promise<Item[]> {
  const items: Item[] = [];
  const add = (item: Item) => {
    if (items.length >= MOST_ITEMS) throw new DriveError("too_large", `more than ${MOST_ITEMS} files and folders`);
    items.push(item);
  };
  const into = async (rel: string): Promise<void> => {
    const listed = await drive.list(root, join2(path, rel), anywhere);
    for (const e of listed.entries) await one(join2(rel, e.name), e);
  };
  const one = async (rel: string, e: Entry): Promise<void> => {
    if (e.dir) {
      add({ path: rel, dir: true, size: 0 });
      await into(rel);
    } else add({ path: rel, dir: false, size: e.size });
  };
  for (const name of names) {
    if (name === "" || name.includes("/") || name === "." || name === "..") throw new DriveError("invalid_request", "a name, not a path");
    const e = await drive.stat(root, join2(path, name), anywhere);
    // A link is listed as what it leads to; the walk does not go through one (`lstat` would say), so a folder's own
    // links are left out by `drive.list` already for a read-only member and followed for one who reaches everything:
    // the names given are taken as they are.
    await one(name, { ...e, name });
  }
  return items;
}

/// This station's own drive as a source, as the asker reaches it.
export function localSource(drive: Drive, root: string, path: string, anywhere: boolean): Source {
  return {
    station: null,
    part: MAX_READ,
    walk: async (names) => ({ items: await walkDrive(drive, root, path, names, anywhere) }),
    read: async (rel, offset, length) => {
      const got = await drive.read(root, join2(path, rel), offset, length, anywhere);
      return { bytes: got.bytes, size: got.total, mtime: got.mtime };
    },
    release: async (names) => {
      for (const name of names) await removeOrTrash(drive, root, join2(path, name), anywhere);
    },
  };
}

/// To the machine's trash; where none takes it, removed (the copy is in place: a move ends with one).
export async function removeOrTrash(drive: Drive, root: string, path: string, anywhere: boolean): Promise<void> {
  await drive.remove(root, path, anywhere).catch((e) => {
    if (e instanceof DriveError && e.code === "no_trash") return drive.remove(root, path, anywhere, true);
    throw e;
  });
}

export type TransfersDeps = {
  /// Where transfers are kept (one file each).
  dir: string;
  /// The drive as a transfer's asker has it (their workspace's pinned folders).
  driveFor: (t: Pick<Transfer, "workspace" | "home">) => Drive;
  /// Where another station's files are read from, with what it granted.
  remote: (t: Transfer) => Source;
  now: () => number;
  /// Told as one changes.
  changed: (t: Transfer) => void;
};

/// The transfers into this station, run one at a time in the order asked.
export class Transfers {
  readonly #deps: TransfersDeps;
  readonly #all = new Map<string, Transfer>();
  /// The one running, and what ends it early (cancelled): checked between parts.
  #running: string | null = null;
  #stop = new Set<string>();
  /// Told once nothing is left to run (`idle`).
  #waiting: (() => void)[] = [];
  #lastSave = 0;
  #closed = false;

  constructor(deps: TransfersDeps) {
    this.#deps = deps;
    mkdirSync(deps.dir, { recursive: true, mode: 0o700 });
    for (const name of readdirSync(deps.dir)) {
      if (!name.endsWith(".json")) continue;
      try {
        const t = JSON.parse(readFileSync(join(deps.dir, name), "utf8")) as Transfer;
        if (typeof t?.id !== "string") continue;
        if (t.endedAt !== undefined && deps.now() - t.endedAt > KEPT_MS) {
          rmSync(join(deps.dir, name), { force: true });
          continue;
        }
        this.#all.set(t.id, t);
      } catch (e) {
        log.warn("drive", "a kept transfer could not be read", { name, error: (e as Error).message });
      }
    }
    // What was under way when the station stopped goes on (a file from where it was).
    if ([...this.#all.values()].some((t) => !ended(t))) this.#kick();
  }

  /// The asker's transfers, newest first.
  list(by: string): Transfer[] {
    return [...this.#all.values()].filter((t) => t.by === by).sort((a, b) => b.createdAt - a.createdAt);
  }

  get(id: string): Transfer | undefined {
    return this.#all.get(id);
  }

  /// A transfer asked: kept, and run once those before it are.
  start(spec: Omit<Transfer, "id" | "state" | "items" | "done" | "at" | "total" | "copied" | "placed" | "createdAt">): Transfer {
    if (spec.from.names.length === 0) throw new DriveError("invalid_request", "nothing to copy");
    const t: Transfer = { ...spec, id: randomUUID().replaceAll("-", ""), state: "queued", items: [], done: 0, at: 0, total: 0, copied: 0, placed: {}, createdAt: this.#deps.now() };
    this.#save(t, true);
    this.#kick();
    return t;
  }

  /// Stopped (what is in place stays; the file under way is let go with its upload).
  cancel(by: string, id: string): Transfer {
    const t = this.#mine(by, id);
    if (ended(t)) return t;
    if (this.#running === id) this.#stop.add(id);
    this.#end(t, "cancelled");
    return t;
  }

  /// One that failed (its station away, say) taken up again where it was.
  retry(by: string, id: string): Transfer {
    const t = this.#mine(by, id);
    if (t.state !== "failed") return t;
    t.state = t.items.length > 0 ? "copying" : "queued";
    delete t.error;
    delete t.endedAt;
    this.#save(t, true);
    this.#kick();
    return t;
  }

  /// Settled when none is left to run.
  idle(): Promise<void> {
    return this.#running === null ? Promise.resolve() : new Promise((resolve) => this.#waiting.push(resolve));
  }

  close(): void {
    this.#closed = true;
    for (const resolve of this.#waiting.splice(0)) resolve();
  }

  #mine(by: string, id: string): Transfer {
    const t = this.#all.get(id);
    if (!t || t.by !== by) throw new DriveError("not_found", "no such transfer");
    return t;
  }

  #save(t: Transfer, tell: boolean): void {
    this.#all.set(t.id, t);
    const path = join(this.#deps.dir, `${t.id}.json`);
    try {
      writeFileSync(`${path}.tmp`, JSON.stringify(t), { mode: 0o600 });
      renameSync(`${path}.tmp`, path);
    } catch (e) {
      log.warn("drive", "a transfer was not kept", { id: t.id, error: (e as Error).message });
    }
    this.#lastSave = this.#deps.now();
    if (tell) this.#deps.changed(t);
  }

  #end(t: Transfer, state: "done" | "failed" | "cancelled", error?: string): void {
    t.state = state;
    if (error !== undefined) t.error = error;
    t.endedAt = this.#deps.now();
    this.#save(t, true);
  }

  /// The next one run, unless one runs.
  #kick(): void {
    if (this.#running !== null || this.#closed) return;
    const next = [...this.#all.values()].filter((t) => !ended(t) && t.state !== "failed").sort((a, b) => a.createdAt - b.createdAt)[0];
    if (!next) {
      for (const resolve of this.#waiting.splice(0)) resolve();
      return;
    }
    this.#running = next.id;
    void this.#run(next).finally(() => {
      this.#running = null;
      this.#stop.delete(next.id);
      this.#kick();
    });
  }

  async #run(t: Transfer): Promise<void> {
    const drive = this.#deps.driveFor(t);
    const source = t.from.station === null ? localSource(drive, t.from.root, t.from.path, t.anywhere) : this.#deps.remote(t);
    const stopped = () => this.#stop.has(t.id) || this.#closed;
    try {
      if (t.items.length === 0) {
        t.state = "walking";
        this.#save(t, true);
        const names = t.from.names.filter((n) => t.conflicts[n] !== "skip");
        const { items } = await source.walk(names);
        if (stopped()) return;
        await this.#place(t, drive, items);
        t.items = items;
        t.total = items.reduce((n, i) => n + i.size, 0);
        t.state = "copying";
        this.#save(t, true);
      }
      while (t.done < t.items.length) {
        if (stopped()) return;
        await this.#copy(t, drive, source, t.items[t.done]!, stopped);
        if (stopped()) return;
        t.done++;
        t.at = 0;
        this.#save(t, true);
      }
      if (t.move) await source.release(Object.keys(t.placed));
      this.#end(t, "done");
    } catch (e) {
      if (stopped()) return;
      const message = e instanceof Error ? e.message : String(e);
      log.warn("drive", "a transfer failed", { id: t.id, error: message });
      this.#end(t, "failed", message);
    }
  }

  /// Where each name goes: its own name, one kept beside (`keep`), or the one there let go first (`replace`).
  async #place(t: Transfer, drive: Drive, items: Item[]): Promise<void> {
    const listed = await drive.list(t.to.root, t.to.path, t.anywhere);
    const there = new Set(listed.entries.map((e) => key(e.name)));
    for (const name of t.from.names) {
      const answer = t.conflicts[name];
      if (answer === "skip") continue;
      const dir = items.find((i) => i.path === name)?.dir ?? false;
      if (there.has(key(name)) && answer === "keep") {
        t.placed[name] = free(name, dir, (n) => there.has(key(n)));
        there.add(key(t.placed[name]!));
        continue;
      }
      if (there.has(key(name)) && answer === "replace") await removeOrTrash(drive, t.to.root, join2(t.to.path, name), t.anywhere);
      else if (there.has(key(name))) throw new DriveError("exists", `${name}: there is already one by that name`);
      t.placed[name] = name;
    }
  }

  /// One folder made, or one file put together beside where it goes and put there whole.
  async #copy(t: Transfer, drive: Drive, source: Source, item: Item, stopped: () => boolean): Promise<void> {
    const name = top(item.path);
    const placed = t.placed[name] ?? name;
    const to = join2(t.to.path, placed + item.path.slice(name.length));
    if (item.dir) {
      await drive.mkdir(t.to.root, to, t.anywhere).catch((e) => {
        if (!(e instanceof DriveError && e.code === "exists")) throw e;
      });
      return;
    }
    const id = `${t.id.slice(0, 32)}-${t.done}`;
    let mtime: number | null = null;
    for (;;) {
      const got = await source.read(item.path, t.at, source.part);
      // Changed meanwhile: from its start again, at its size now.
      if (mtime !== null && got.mtime !== mtime) {
        t.copied -= t.at;
        t.at = 0;
        mtime = null;
        continue;
      }
      mtime = got.mtime;
      if (got.size !== item.size) {
        t.total += got.size - item.size;
        item.size = got.size;
      }
      const put = await drive.upload(t.to.root, to, id, t.at, got.size, got.bytes, false, t.anywhere).catch((e) => {
        // The station has less of it than this transfer thought (restarted before its last part was synced): from there.
        if (e instanceof DriveError && e.code === "upload_lost" && e.have !== undefined) return { have: e.have, entry: null, lost: true };
        throw e;
      });
      if ("lost" in put) {
        t.copied -= t.at - put.have;
        t.at = put.have;
        continue;
      }
      t.copied += put.have - t.at;
      t.at = put.have;
      if (put.entry !== null || t.at >= got.size) return;
      if (stopped()) return;
      if (this.#deps.now() - this.#lastSave >= SAVE_EVERY_MS) this.#save(t, true);
    }
  }
}

const ended = (t: Transfer) => t.state === "done" || t.state === "cancelled";
