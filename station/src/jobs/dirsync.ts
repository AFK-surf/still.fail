// A local directory of a source session mirrored on another station for its remote tasks (station_task's `dir`,
// docs/station-peers.md "Directories"). Each start brings the mirror up to date before the command runs there:
//
// - Which files: in a Git work tree what `git ls-files -co --exclude-standard` names (tracked, and untracked but not
//   ignored), so node_modules, target and dist stay home; elsewhere every file but IGNORED. `.git` is not synced,
//   neither are submodules or nested repositories. A symbolic link goes as a link when what it names stays inside the
//   directory, and is left out (said in `skipped`) when it leads out.
// - Compared by content: a file's id is its Git blob id (sha1 of "blob <size>\0" and its bytes), free from the index
//   for a clean tracked file, hashed for the rest. The target keeps a manifest of what it wrote into the mirror (path →
//   id, mode and the stat it left), and answers with what is there now (a file a command changed is hashed again).
// - Sent: only contents the mirror has nowhere, as pieces packed into zstd-compressed requests (`sync.put`), each
//   within the transport's 1 MiB message; then the plan (`sync.commit`), in pages as well.
// - Written: a changed file goes to a temporary file renamed over it, with its exec bit; a file that left the set is
//   removed; nothing else in the mirror (build output, node_modules, files a task made) is touched, and an unchanged
//   file keeps its mtime, so incremental builds there see exactly what changed.
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync, closeSync, copyFileSync, createReadStream, existsSync, lstatSync, mkdirSync, openSync, readFileSync, readlinkSync,
  renameSync, rmSync, rmdirSync, statSync, symlinkSync, writeFileSync, writeSync,
} from "node:fs";
import { lstat, open, readdir, readlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import { zstdCompress, zstdDecompress } from "node:zlib";
import { filePath } from "./remote.ts";

type Json = any;

export const FILE = "100644";
export const EXEC = "100755";
export const LINK = "120000";
/// Directories a walk outside Git leaves out, wherever they are: version control, dependencies and build output.
export const IGNORED = new Set([".git", ".hg", ".svn", ".jj", "node_modules", "target", "dist", "build", ".gradle", ".next", ".turbo", ".cache", "__pycache__", ".venv"]);
const IGNORED_FILES = new Set([".DS_Store"]);
/// At most this many files in a directory synced.
export const MAX_FILES = 200_000;
const MAX_FILE = 1024 * 1024 * 1024;
/// A file goes in pieces of at most this much.
const PIECE = 512 * 1024;
/// A request's packed data at most (base64 of the compressed pieces), and its pieces at most: with the rest of the
/// request it stays within the transport's message (1 MiB, mesh/peer.ts).
const BODY = 720 * 1024;
const PIECES = 2000;
/// A request's pieces unpacked at most.
export const RAW = 16 * 1024 * 1024;
/// A page of a manifest or a plan, as JSON, at most about this much.
const PAGE = 512 * 1024;

const pack = promisify(zstdCompress);
const unpack = promisify(zstdDecompress);
const run = promisify(execFile);

/// A file's content id as Git has it.
export function blobId(content: Buffer): string {
  return createHash("sha1").update(`blob ${content.length}\0`).update(content).digest("hex");
}

/// The blob id of a file `size` bytes long, read as a stream.
async function fileId(path: string, size: number): Promise<string> {
  const hash = createHash("sha1").update(`blob ${size}\0`);
  let read = 0;
  for await (const chunk of createReadStream(path)) {
    hash.update(chunk as Buffer);
    read += (chunk as Buffer).length;
  }
  if (read !== size) throw new Error(`${path} changed while it was read`);
  return hash.digest("hex");
}

/// Whether a link at `path` (relative, / between parts) naming `target` stays inside the directory.
export function linkInside(path: string, target: string): boolean {
  if (target === "" || target.startsWith("/") || target.startsWith("\\") || /^[A-Za-z]:/.test(target)) return false;
  const parts = path.split("/").slice(0, -1);
  for (const part of target.split(/[\\/]/)) {
    if (part === "" || part === ".") continue;
    if (part === "..") {
      if (parts.length === 0) return false;
      parts.pop();
    } else parts.push(part);
  }
  return true;
}

const modeOf = (mode: number) => (mode & 0o111 ? EXEC : FILE);

// ── the source: what the directory has ──

export type Local = { path: string; hash: string; mode: string; size: number };
export type Listing = { files: Local[]; git: boolean; prefix: string; skipped: { path: string; why: string }[] };

async function git(dir: string, args: string[]): Promise<string> {
  const { stdout } = await run("git", ["-C", dir, ...args], { maxBuffer: 1 << 30, env: { ...process.env, GIT_OPTIONAL_LOCKS: "0" } });
  return stdout;
}

const entries = (out: string) => out.split("\0").filter((s) => s !== "");

/// A file of the directory as it is on disk; null when it is not there (or a directory), a reason when it is left out.
async function onDisk(dir: string, path: string): Promise<Local | string | null> {
  const abs = join(dir, ...path.split("/"));
  let st;
  try {
    st = await lstat(abs);
  } catch {
    return null;
  }
  if (st.isSymbolicLink()) {
    const target = await readlink(abs);
    if (!linkInside(path, target)) return "symbolic link leading out of the directory";
    const content = Buffer.from(target);
    return { path, hash: blobId(content), mode: LINK, size: content.length };
  }
  if (st.isDirectory()) return null;
  if (!st.isFile()) return "not a regular file";
  if (st.size > MAX_FILE) return "larger than 1 GiB";
  return { path, hash: await fileId(abs, st.size), mode: modeOf(st.mode), size: st.size };
}

/// `todo` done 8 at a time.
async function pool<T>(items: T[], f: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(8, items.length) }, async () => {
    while (next < items.length) await f(items[next++]!);
  }));
}

/// What of `dir` is synced: Git's files in a work tree, a walk without IGNORED elsewhere.
export async function listLocal(dir: string): Promise<Listing> {
  if (!statSync(dir).isDirectory()) throw new Error(`${dir} is not a directory`);
  let tree: string[] | null = null;
  try {
    tree = (await git(dir, ["rev-parse", "--is-inside-work-tree", "--show-prefix"])).split("\n");
    // A directory its work tree ignores (a build directory) has no files Git names: walked.
    if (tree[0] === "true" && tree[1] !== "") {
      const ignored = await git(dir, ["check-ignore", "-q", "."]).then(() => true, () => false);
      if (ignored) tree = null;
    }
  } catch {}
  const files: Local[] = [];
  const skipped: { path: string; why: string }[] = [];
  const take = (got: Local | string | null, path: string) => {
    if (typeof got === "string") skipped.push({ path, why: got });
    else if (got !== null) files.push(got);
  };
  const more = () => {
    if (files.length > MAX_FILES) throw new Error(`${dir} has more than ${MAX_FILES} files to sync`);
  };
  if (tree !== null && tree[0] === "true") {
    const prefix = tree[1] ?? "";
    const modified = new Set(entries(await git(dir, ["ls-files", "-z", "-m"])));
    const seen = new Set<string>();
    const hash: string[] = [];
    for (const line of entries(await git(dir, ["ls-files", "-z", "-s"]))) {
      const tab = line.indexOf("\t");
      const [mode, id, stage] = line.slice(0, tab).split(" ");
      const path = line.slice(tab + 1);
      if (seen.has(path)) continue;
      seen.add(path);
      if (mode === "160000") {
        skipped.push({ path, why: "submodule" });
        continue;
      }
      // A clean tracked file is what the index says; a changed one (or one in a conflict) is hashed.
      if (modified.has(path) || stage !== "0" || (mode !== FILE && mode !== EXEC && mode !== LINK)) {
        hash.push(path);
        continue;
      }
      if (mode === LINK) {
        hash.push(path);
        continue;
      }
      let size = 0;
      try {
        const st = lstatSync(join(dir, ...path.split("/")));
        if (!st.isFile()) {
          hash.push(path);
          continue;
        }
        size = st.size;
      } catch {
        continue;
      }
      files.push({ path, hash: id!, mode: mode!, size });
      more();
    }
    for (const path of entries(await git(dir, ["ls-files", "-z", "-o", "--exclude-standard"]))) {
      if (path.endsWith("/")) skipped.push({ path: path.slice(0, -1), why: "nested repository" });
      else hash.push(path);
    }
    if (files.length + hash.length > MAX_FILES) throw new Error(`${dir} has more than ${MAX_FILES} files to sync`);
    await pool(hash, async (path) => take(await onDisk(dir, path), path));
    return { files: files.sort(byPath), git: true, prefix, skipped };
  }
  const found: string[] = [];
  const visit = async (rel: string) => {
    for (const e of await readdir(rel === "" ? dir : join(dir, ...rel.split("/")), { withFileTypes: true })) {
      const path = rel === "" ? e.name : `${rel}/${e.name}`;
      if (e.isDirectory()) {
        if (!IGNORED.has(e.name)) await visit(path);
      } else if (!IGNORED_FILES.has(e.name)) {
        found.push(path);
        if (found.length > MAX_FILES) throw new Error(`${dir} has more than ${MAX_FILES} files to sync`);
      }
    }
  };
  await visit("");
  await pool(found, async (path) => take(await onDisk(dir, path), path));
  return { files: files.sort(byPath), git: false, prefix: "", skipped };
}

const byPath = (a: { path: string }, b: { path: string }) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0);

// ── the source: bringing a mirror up to date ──

/// A sync request to the target, for the task being started (`sync.<method>`, its session and key added).
export type Ask = (method: string, more: Json) => Promise<Json>;

export type Synced = {
  files: number;
  git: boolean;
  /// Contents the mirror had nowhere, sent: how many, their bytes, and the bytes that went (compressed).
  sent: { files: number; bytes: number; packed: number; requests: number };
  written: number;
  removed: number;
  /// What was left out (the first 50), and how many.
  skipped: { path: string; why: string }[];
  skippedCount: number;
  /// The directory's place in its Git work tree ("" outside one).
  prefix: string;
  ms: number;
};

/// Pages of `items`, each about PAGE as JSON at most.
function pages<T>(items: T[]): T[][] {
  const out: T[][] = [[]];
  let size = 0;
  for (const item of items) {
    const n = JSON.stringify(item).length + 1;
    if (size + n > PAGE && out.at(-1)!.length > 0) {
      out.push([]);
      size = 0;
    }
    out.at(-1)!.push(item);
    size += n;
  }
  return out;
}

/// Brings the target's mirror up to date with `dir`; null when the task started already (nothing synced: a start
/// asked again returns the job that started).
export async function syncDir(ask: Ask, dir: string, now: () => number = Date.now): Promise<Synced | null> {
  const t0 = now();
  const begun = await ask("sync.begin", {});
  if (begun?.started === true) return null;
  const id = String(begun?.id ?? "");
  const listing = await listLocal(dir);
  const there = new Map<string, [string, string]>();
  for (let after: number | null = 0; after !== null; ) {
    const page: Json = await ask("sync.manifest", { id, after });
    for (const [path, hash, mode] of page.entries as [string, string, string][]) there.set(path, [hash, mode]);
    after = typeof page.next === "number" ? page.next : null;
  }
  const have = new Set([...there.values()].map(([hash]) => hash));
  const set: [string, string, string][] = [];
  const need = new Map<string, Local>();
  for (const f of listing.files) {
    const t = there.get(f.path);
    if (t && t[0] === f.hash && t[1] === f.mode) continue;
    set.push([f.path, f.hash, f.mode]);
    if (!have.has(f.hash) && !need.has(f.hash)) need.set(f.hash, f);
  }
  const local = new Set(listing.files.map((f) => f.path));
  const remove = [...there.keys()].filter((p) => !local.has(p));
  const sent = await sendBlobs(ask, id, dir, [...need.values()]);
  const plan = [...set.map((s) => ({ s })), ...remove.map((r) => ({ r }))];
  const parts = pages(plan);
  let answer: Json = null;
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i]!;
    answer = await ask("sync.commit", {
      id,
      set: part.flatMap((p) => ("s" in p ? [p.s] : [])),
      remove: part.flatMap((p) => ("r" in p ? [p.r] : [])),
      final: i === parts.length - 1,
    });
  }
  return {
    files: listing.files.length,
    git: listing.git,
    sent,
    written: Number(answer?.written ?? 0),
    removed: Number(answer?.removed ?? 0),
    skipped: listing.skipped.slice(0, 50),
    skippedCount: listing.skipped.length,
    prefix: listing.prefix,
    ms: now() - t0,
  };
}

type Piece = { hash: string; size: number; offset: number; data: Buffer };

/// Sends the contents in `need` in packed requests, each within BODY; checks each file is still what was hashed.
async function sendBlobs(ask: Ask, id: string, dir: string, need: Local[]): Promise<Synced["sent"]> {
  const sent = { files: need.length, bytes: 0, packed: 0, requests: 0 };
  // How much a request's pieces shrink, from the last one (assumed not at all at first).
  let ratio = 1;
  let batch: Piece[] = [];
  let raw = 0;
  const flush = async (pieces: Piece[]): Promise<void> => {
    if (pieces.length === 0) return;
    const plain = Buffer.concat(pieces.map((p) => p.data));
    const packed = await pack(plain);
    const data = packed.toString("base64");
    if (data.length > BODY && pieces.length > 1) {
      const half = Math.ceil(pieces.length / 2);
      await flush(pieces.slice(0, half));
      await flush(pieces.slice(half));
      return;
    }
    ratio = Math.max(0.02, packed.length / Math.max(1, plain.length));
    await ask("sync.put", { id, blobs: pieces.map((p) => [p.hash, p.size, p.offset, p.data.length]), data });
    sent.requests++;
    sent.packed += packed.length;
  };
  const add = async (piece: Piece) => {
    const budget = Math.min(RAW, (BODY * 0.7) / ratio);
    if (batch.length > 0 && (raw + piece.data.length > budget || batch.length >= PIECES)) {
      const pieces = batch;
      batch = [];
      raw = 0;
      await flush(pieces);
    }
    batch.push(piece);
    raw += piece.data.length;
    sent.bytes += piece.data.length;
  };
  for (const f of need) {
    const abs = join(dir, ...f.path.split("/"));
    const changed = () => new Error(`${f.path} changed while syncing; start again`);
    if (f.mode === LINK) {
      const content = Buffer.from(await readlink(abs).catch(() => ""));
      if (blobId(content) !== f.hash) throw changed();
      await add({ hash: f.hash, size: content.length, offset: 0, data: content });
      continue;
    }
    const file = await open(abs, "r").catch(() => null);
    if (file === null) throw changed();
    try {
      const hash = createHash("sha1").update(`blob ${f.size}\0`);
      let offset = 0;
      do {
        const data = Buffer.alloc(Math.min(PIECE, f.size - offset));
        const { bytesRead } = await file.read(data, 0, data.length, offset);
        if (bytesRead !== data.length) throw changed();
        hash.update(data);
        if (offset + data.length === f.size && hash.digest("hex") !== f.hash) throw changed();
        await add({ hash: f.hash, size: f.size, offset, data });
        offset += data.length;
      } while (offset < f.size);
    } finally {
      await file.close();
    }
  }
  await flush(batch);
  return sent;
}

// ── the target: the mirror ──

/// A file the mirror has: its id, mode, and the size, mtime and inode it was left with.
export type Entry = [hash: string, mode: string, size: number, mtime: number, ino: number];
export type Manifest = { dir: string; name: string; version: number; files: Record<string, Entry> };

export function readManifest(path: string): Manifest | null {
  try {
    const m = JSON.parse(readFileSync(path, "utf8"));
    if (m !== null && typeof m === "object" && typeof m.files === "object" && m.files !== null) return m;
  } catch {}
  return null;
}

const entryOf = (hash: string, mode: string, path: string): Entry => {
  const st = lstatSync(path);
  return [hash, mode, st.size, st.mtimeMs, st.ino];
};

/// What the mirror has of the files it was given, now: one a command changed is hashed again, one it removed (or made
/// something else) is no longer there.
export async function actual(mirror: string, files: Record<string, Entry>): Promise<Record<string, Entry>> {
  const out: Record<string, Entry> = {};
  for (const [path, e] of Object.entries(files)) {
    const abs = join(mirror, ...path.split("/"));
    let st;
    try {
      st = lstatSync(abs);
    } catch {
      continue;
    }
    const same = st.size === e[2] && st.mtimeMs === e[3] && st.ino === e[4];
    if (st.isSymbolicLink()) {
      out[path] = e[1] === LINK && same ? e : [blobId(Buffer.from(readlinkSync(abs))), LINK, st.size, st.mtimeMs, st.ino];
    } else if (st.isFile()) {
      const mode = modeOf(st.mode);
      out[path] = e[1] === mode && same ? e : [await fileId(abs, st.size), mode, st.size, st.mtimeMs, st.ino];
    }
  }
  return out;
}

/// Pieces sent (`index`: id, size, offset, length) unpacked into `blobs`: each content in its own file, complete when
/// its last piece came and its id checked. A piece that came already (a request asked again) is skipped.
export async function putBlobs(blobs: string, index: Json, packed: Buffer): Promise<number> {
  if (!Array.isArray(index) || index.length > PIECES) throw new Error("bad pieces");
  let total = 0;
  for (const p of index) {
    if (!Array.isArray(p) || typeof p[0] !== "string" || !/^[0-9a-f]{40}$/.test(p[0]) || ![p[1], p[2], p[3]].every((n) => Number.isInteger(n) && n >= 0)) {
      throw new Error("bad piece");
    }
    if (p[1] > MAX_FILE || p[2] + p[3] > p[1]) throw new Error("bad piece");
    total += p[3];
  }
  if (total > RAW) throw new Error("too much in one request");
  const data = await unpack(packed, { maxOutputLength: RAW });
  if (data.length !== total) throw new Error("pieces do not match their data");
  mkdirSync(blobs, { recursive: true });
  let at = 0;
  for (const [hash, size, offset, length] of index as [string, number, number, number][]) {
    const piece = data.subarray(at, at + length);
    at += length;
    const done = join(blobs, hash);
    if (existsSync(done)) continue;
    const part = `${done}.part`;
    let has = 0;
    try {
      has = statSync(part).size;
    } catch {}
    if (offset + length <= has && !(offset === 0 && has === 0)) continue;
    if (offset !== has) throw new Error("a content's pieces came out of order");
    const fd = openSync(part, offset === 0 ? "w" : "a");
    try {
      for (let w = 0; w < piece.length; ) w += writeSync(fd, piece, w, piece.length - w);
    } finally {
      closeSync(fd);
    }
    if (offset + length === size) {
      if ((await fileId(part, size)) !== hash) {
        rmSync(part, { force: true });
        throw new Error("a content sent does not match its id");
      }
      renameSync(part, done);
    }
  }
  return index.length;
}

/// Checks a plan's entries as they come: [path, id, mode] to have, paths to remove.
export function planPart(request: Json): { set: [string, string, string][]; remove: string[] } {
  const set = request?.set ?? [];
  const remove = request?.remove ?? [];
  if (!Array.isArray(set) || !Array.isArray(remove)) throw new Error("bad plan");
  for (const s of set) {
    if (!Array.isArray(s) || typeof s[0] !== "string" || typeof s[1] !== "string" || !/^[0-9a-f]{40}$/.test(s[1]) || ![FILE, EXEC, LINK].includes(s[2])) {
      throw new Error("bad plan");
    }
  }
  if (!remove.every((r: unknown) => typeof r === "string")) throw new Error("bad plan");
  return { set, remove };
}

/// Removes the empty directories from `path`'s up to the mirror's.
function prune(mirror: string, path: string) {
  for (let d = dirname(path); d.length > mirror.length && d.startsWith(mirror); d = dirname(d)) {
    try {
      rmdirSync(d);
    } catch {
      return;
    }
  }
}

/// Carries out a plan in the mirror (`name` in `work`): every new content made beside it first (in `scratch`, from `blobs` or from a file
/// of the mirror with the same id), then the files that left removed, then the new ones renamed into place. `files`
/// (what the mirror has, `actual`) is updated as it goes, also when it stops on an error part way.
export function apply(
  work: string,
  name: string,
  scratch: string,
  blobs: string,
  files: Record<string, Entry>,
  plan: { set: [string, string, string][]; remove: string[] },
): { written: number; removed: number } {
  const mirror = filePath(work, name, true);
  mkdirSync(mirror, { recursive: true });
  mkdirSync(scratch, { recursive: true });
  const byHash = new Map<string, string>();
  for (const [path, e] of Object.entries(files)) byHash.set(e[0], path);
  const uses = new Map<string, number>();
  for (const [, hash] of plan.set) uses.set(hash, (uses.get(hash) ?? 0) + 1);
  type Ready = { path: string; hash: string; mode: string; temp: string | null };
  const ready: Ready[] = [];
  plan.set.forEach(([path, hash, mode], i) => {
    const now = files[path];
    if (now && now[0] === hash && (now[1] === LINK) === (mode === LINK)) {
      // The same content: a mode to set, if any.
      ready.push({ path, hash, mode, temp: null });
      return;
    }
    const temp = join(scratch, String(i));
    rmSync(temp, { force: true });
    const blob = join(blobs, hash);
    const from = existsSync(blob) ? null : byHash.get(hash);
    if (!existsSync(blob) && from === undefined) throw new Error(`the content of ${path} was not sent`);
    if (mode === LINK) {
      const target = from === undefined || from === null ? readFileSync(blob, "utf8") : readlinkSync(join(mirror, ...from.split("/")));
      if (!linkInside(path, target)) throw new Error(`${path} is a symbolic link leading out of the directory`);
      symlinkSync(target, temp);
    } else {
      const left = (uses.get(hash) ?? 1) - 1;
      uses.set(hash, left);
      if (from === null || from === undefined) {
        if (left === 0) renameSync(blob, temp);
        else copyFileSync(blob, temp);
      } else copyFileSync(join(mirror, ...from.split("/")), temp);
      chmodSync(temp, mode === EXEC ? 0o755 : 0o644);
    }
    ready.push({ path, hash, mode, temp });
  });
  let removed = 0;
  for (const path of plan.remove) {
    if (!(path in files)) continue;
    let abs: string;
    try {
      abs = filePath(mirror, path, false);
    } catch {
      delete files[path];
      continue;
    }
    try {
      const st = lstatSync(abs);
      if (st.isFile() || st.isSymbolicLink()) rmSync(abs, { force: true });
    } catch {}
    delete files[path];
    removed++;
    prune(mirror, abs);
  }
  let written = 0;
  for (const r of ready) {
    let abs: string;
    try {
      abs = filePath(mirror, r.path, true);
    } catch (error) {
      throw new Error(`cannot write ${r.path} on the target: ${(error as Error).message}`);
    }
    if (r.temp === null) {
      if (r.mode !== LINK && files[r.path]![1] !== r.mode) chmodSync(abs, r.mode === EXEC ? 0o755 : 0o644);
      files[r.path] = entryOf(r.hash, r.mode, abs);
      continue;
    }
    try {
      const st = lstatSync(abs);
      if (st.isDirectory()) rmdirSync(abs);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw new Error(`cannot write ${r.path} on the target: a directory is there`);
    }
    renameSync(r.temp, abs);
    files[r.path] = entryOf(r.hash, r.mode, abs);
    written++;
  }
  return { written, removed };
}

/// The manifest's entries as pages give them: [path, id, mode], by path.
export function listed(files: Record<string, Entry>): [string, string, string][] {
  return Object.keys(files)
    .sort()
    .map((p) => [p, files[p]![0], files[p]![1]]);
}

/// A page of `all` from `after`: as many as about PAGE of JSON, and where the next starts (null at the end).
export function page<T>(all: T[], after: number): { entries: T[]; next: number | null } {
  const entries: T[] = [];
  let size = 0;
  let i = after;
  for (; i < all.length; i++) {
    const n = JSON.stringify(all[i]).length + 1;
    if (size + n > PAGE && entries.length > 0) break;
    entries.push(all[i]!);
    size += n;
  }
  return { entries, next: i < all.length ? i : null };
}

export function writeManifest(path: string, m: Manifest): void {
  const temp = `${path}.${process.pid}.tmp`;
  writeFileSync(temp, JSON.stringify(m));
  renameSync(temp, path);
}

// ── the source: what a task changed in the mirror, as a patch ──

/// A patch from what the mirror had (`old` ids, taken from `dir` or its Git objects) to what a command left there
/// (`after`, null for a file it removed); null when git is not there. Paths as `git apply` takes them in `dir`
/// (`prefix`: dir's place in its work tree). `missing`: files whose old content was not found (left out of the patch).
export async function patchOf(
  dir: string,
  prefix: string,
  scratch: string,
  changes: { path: string; old: string; mode: string; after: Buffer | null; afterMode: string | null }[],
): Promise<{ patch: string; missing: string[] } | null> {
  try {
    await run("git", ["--version"]);
  } catch {
    return null;
  }
  const missing: string[] = [];
  mkdirSync(scratch, { recursive: true });
  try {
    const g = (args: string[]) => run("git", ["-C", scratch, "-c", "core.autocrlf=false", "-c", "core.symlinks=true", "-c", "core.filemode=true", ...args], { maxBuffer: 1 << 30 });
    await g(["init", "-q"]);
    const put = (path: string, content: Buffer, mode: string) => {
      const abs = join(scratch, ...path.split("/"));
      mkdirSync(dirname(abs), { recursive: true });
      rmSync(abs, { force: true });
      if (mode === LINK) symlinkSync(content.toString(), abs);
      else {
        writeFileSync(abs, content);
        chmodSync(abs, mode === EXEC ? 0o755 : 0o644);
      }
    };
    const kept = [];
    for (const c of changes) {
      let before: Buffer | null = null;
      const abs = join(dir, ...c.path.split("/"));
      try {
        const st = lstatSync(abs);
        const local = st.isSymbolicLink() ? Buffer.from(readlinkSync(abs)) : st.isFile() ? readFileSync(abs) : null;
        if (local !== null && blobId(local) === c.old) before = local;
      } catch {}
      if (before === null) {
        try {
          const { stdout } = await run("git", ["-C", dir, "cat-file", "blob", c.old], { encoding: "buffer", maxBuffer: 1 << 30 });
          before = stdout as unknown as Buffer;
        } catch {}
      }
      if (before === null) {
        missing.push(c.path);
        continue;
      }
      put(c.path, before, c.mode);
      kept.push(c);
    }
    await g(["add", "-A"]);
    for (const c of kept) {
      if (c.after === null) rmSync(join(scratch, ...c.path.split("/")), { force: true });
      else put(c.path, c.after, c.afterMode ?? c.mode);
    }
    const { stdout } = await g(["diff", "--binary", `--src-prefix=a/${prefix}`, `--dst-prefix=b/${prefix}`]);
    return { patch: stdout, missing };
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}
