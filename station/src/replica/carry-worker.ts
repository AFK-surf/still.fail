// What of a workspace's chats goes along beside their copy as a station is retired from it (retire.ts; replica/AGENTS.md):
// their agents' transcripts and each session's own directory (its room: the workspace, and an archived one's packed
// workspace beside it), gathered on the station retired and put in place on the one its chats go to. Nothing in it is
// changed on the way: each file is taken by its bytes (by their hash, as a copy's files are) and put at the same place
// under the other station's data directory. A checkout's own repository (`.git` a directory) goes as its files; a linked
// worktree's is git's to make again there (retire.ts `rebuildGits`), from what this says of it. What a build or an
// install makes again (footprint.ts `rebuildable`), and what git ignores, stays behind. Only what is under the data
// directory's `sessions/` and `transcripts*/` goes, or is put. Run in a thread of its own (retire.ts `gatherSoon`,
// `placeSoon`), or a test's.
//
// A station has a million files under `sessions/`: none of it is one object. Each session's files are a list of their
// own on disk (a line each), and what goes along is an index of the lists (`CarryIndex`); the main thread reads the
// index and streams the lists, and what goes between the two stations is a list's piece at a time (retire.ts).
import { execFileSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { chmodSync, closeSync, constants, copyFileSync, existsSync, lstatSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, readlinkSync, realpathSync, renameSync, rmSync, symlinkSync, utimesSync, writeFileSync, writeSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { rebuildable, roomOf } from "../sessions/footprint.ts";
import { runtimeKind } from "../agents/runtime.ts";
import { sessionPlaces, storage, transcriptSources } from "../read/transcript.ts";
import { moved } from "./restore.ts";

/// A file that goes along, a line of its session's list: where it is (under the station's data directory), its bytes'
/// hash, how big, its mode and time; a symbolic link its target instead (nothing to send).
export type CarriedFile = { path: string; hash: string; size: number; mode: number; mtimeMs: number } | { path: string; link: string };
/// A linked git worktree of a working directory (its `.git` a file naming its repository elsewhere): where it is, the
/// remote it came from, its branch (null: detached), its commit, and its commits no remote has (a bundle's hash; null:
/// none).
export type CarriedGit = { dir: string; remote: string; branch: string | null; head: string; bundle: string | null };
/// A session whose things go along: its key, its working directory, its room (null: not in the station's layout, so
/// nothing of its directory goes); its list (the hash of its file, the name it is sent by), how many files and bytes
/// it names; `at`: where the list is on the station it was gathered on.
export type CarriedSession = { key: string; workspace: string; room: string | null; list: string; files: number; bytes: number; at: string };
/// A job or service a session had running, which stays behind (its agent is told: retire.ts).
export type CarriedJob = { session: string; name: string; command: string };
/// What goes along with a workspace's chats, all but the files: `dataDir` the retired station's; each session and its
/// list; the linked worktrees; the sessions whose directory is not the station's own (a person's project), which stays;
/// the jobs that stay behind; where each worktree's bundle is on the station gathered on.
export type CarryIndex = { v: 2; dataDir: string; sessions: CarriedSession[]; gits: CarriedGit[]; skipped: string[]; jobs: CarriedJob[]; bundles: Record<string, string>; files: number; bytes: number };
/// What a gathering answers (the rest is on disk): where its index is, and how much it names.
export type Gathered = { index: string; files: number; bytes: number; gits: number; skipped: number };

/// A session of the workspace as the gathering reads it.
type SessionAt = { key: string; workspace: string; cwd: string | null; runtime: string; profile: string; runtime_session_id: string | null; archived_at: number | null };

const within = (path: string, dir: string) => path === dir || path.startsWith(dir.endsWith(sep) ? dir : dir + sep);

/// Whether `path` is one that goes along, or is put: under `dataDir`'s `sessions/` or a `transcripts*/` of it.
export function carriedPlace(dataDir: string, path: string): boolean {
  const rel = relative(dataDir, path);
  if (rel === "" || rel.startsWith("..") || isAbsolute(rel)) return false;
  const parts = rel.split(sep);
  return parts.length > 1 && (parts[0] === "sessions" || parts[0]!.startsWith("transcripts"));
}

/// A file's hash, read a piece at a time (a room's packed workspace is gigabytes).
export function hashFile(path: string): string {
  const h = createHash("sha256");
  const fd = openSync(path, "r"); // sync: in the gathering's or placing's own thread
  const buf = Buffer.allocUnsafe(1 << 20);
  try {
    for (;;) {
      const n = readSync(fd, buf, 0, buf.length, null); // sync: in the gathering's or placing's own thread
      if (n === 0) break;
      h.update(buf.subarray(0, n));
    }
  } finally {
    closeSync(fd); // sync: in the gathering's or placing's own thread
  }
  return h.digest("hex");
}

/// The lines of a file, read a piece at a time.
export function* linesOf(path: string): Generator<string> {
  const fd = openSync(path, "r"); // sync: in the gathering's or placing's own thread
  const buf = Buffer.allocUnsafe(1 << 20);
  let rest = Buffer.alloc(0);
  try {
    for (;;) {
      const n = readSync(fd, buf, 0, buf.length, null); // sync: in the gathering's or placing's own thread
      if (n === 0) break;
      let chunk = Buffer.concat([rest, buf.subarray(0, n)]);
      for (let at = chunk.indexOf(10); at >= 0; at = chunk.indexOf(10)) {
        if (at > 0) yield chunk.subarray(0, at).toString("utf8");
        chunk = chunk.subarray(at + 1);
      }
      rest = Buffer.from(chunk);
    }
    if (rest.length > 0) yield rest.toString("utf8");
  } finally {
    closeSync(fd); // sync: in the gathering's or placing's own thread
  }
}

/// A session's list, written a line at a time, its hash taken as it goes.
class ListFile {
  readonly #fd: number;
  readonly #hash = createHash("sha256");
  readonly tmp: string;
  files = 0;
  bytes = 0;
  readonly path: string;
  constructor(path: string) {
    this.path = path;
    this.tmp = `${path}.writing`;
    this.#fd = openSync(this.tmp, "w"); // sync: in the gathering's own thread (gatherSoon)
  }
  add(f: CarriedFile): void {
    const line = `${JSON.stringify(f)}\n`;
    this.#hash.update(line);
    writeSync(this.#fd, line); // sync: in the gathering's own thread (gatherSoon)
    if ("hash" in f) {
      this.files++;
      this.bytes += f.size;
    }
  }
  close(): string {
    closeSync(this.#fd); // sync: in the gathering's own thread (gatherSoon)
    renameSync(this.tmp, this.path); // sync: in the gathering's own thread (gatherSoon)
    return this.#hash.digest("hex");
  }
}

const GIT_ENV = { ...process.env, GIT_TERMINAL_PROMPT: "0", GIT_SSH_COMMAND: "ssh -o BatchMode=yes" };
/// How long a fetch of a checkout's remote may take as it is gathered.
const FETCH_MS = 120_000;

const git = (dir: string, args: string[], timeout?: number): string | null => {
  try {
    return execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], env: GIT_ENV, maxBuffer: 256 * 1024 * 1024, timeout }).trim(); // sync: in the gathering's own thread (gatherSoon)
  } catch {
    return null;
  }
};

/// The sessions of a workspace whose things go along, as both the gathering and the preview read them (`home`: the
/// station's home workspace, whose sessions say none).
const sessionsIn = (home: boolean) => `SELECT key, workspace, cwd, runtime, profile, runtime_session_id, archived_at FROM sessions WHERE ${home ? "(ws = ? OR ws IS NULL)" : "ws = ?"} ORDER BY key`;

/// A session's room under `dataDir` as its files go along (footprint.ts `roomOf`, said under `dataDir` as given,
/// `realData` its real path), null where its directory is not the station's own (it stays, `skipped`).
function roomFor(dataDir: string, realData: string, workspace: string): string | null {
  const real = roomOf(dataDir, workspace);
  return real === null || !within(real, realData) ? null : join(dataDir, relative(realData, real));
}

/// What a retirement of `ws` would take of its sessions here, as the app shows it first (retire.ts `preview`): how many
/// chats, archived or not, and how many have a directory that is not the station's own (the gathering's `skipped`),
/// found as the gathering finds it, no directory walked.
export function preview(dataDir: string, db: string, ws: string, home: boolean): { chats: number; archived: number; outside: number } {
  const d = new DatabaseSync(db, { readOnly: true, timeout: 30_000 });
  let realData = dataDir;
  try {
    realData = realpathSync(dataDir); // sync: in the preview's own thread (previewSoon)
  } catch {}
  let chats = 0;
  let archived = 0;
  let outside = 0;
  try {
    for (const s of d.prepare(sessionsIn(home)).iterate(ws) as Iterable<SessionAt>) {
      if (s.archived_at === null) chats++;
      else archived++;
      if (roomFor(dataDir, realData, s.workspace) === null) outside++;
    }
  } finally {
    d.close();
  }
  return { chats, archived, outside };
}

/// Where a gathering keeps its index and its lists, in `scratch`.
export const indexFile = (scratch: string) => join(scratch, "index.json");
const listFile = (scratch: string, key: string) => join(scratch, "lists", `${createHash("sha256").update(key).digest("hex").slice(0, 32)}.jsonl`);

/// What goes along with the chats of `ws` on the station whose data directory is `dataDir`: their transcripts and each
/// one's room, a git checkout in it as git lists its files (tracked and not ignored) with its repository, a linked
/// worktree's commits no remote has in a bundle; written in `scratch` (a list a session, the index of them). A file of
/// the gathering before that has the same size and time is not read again (its hash from that session's list then).
export function gather(dataDir: string, db: string, ws: string, home: boolean, scratch: string): Gathered {
  const d = new DatabaseSync(db, { readOnly: true, timeout: 30_000 });
  const gits: CarriedGit[] = [];
  const sessions: CarriedSession[] = [];
  const skipped: string[] = [];
  const bundles: Record<string, string> = {};
  const fetched = new Set<string>();
  mkdirSync(join(scratch, "lists"), { recursive: true }); // sync: in the gathering's own thread (gatherSoon)
  let files = 0;
  let bytes = 0;
  // (per session: what its list said before, and what is in its list now)
  let before = new Map<string, { size: number; mtimeMs: number; hash: string }>();
  let seen = new Set<string>();
  let list: ListFile | null = null;
  const add = (path: string) => {
    if (seen.has(path) || !carriedPlace(dataDir, path) || list === null) return;
    seen.add(path);
    let st;
    try {
      st = lstatSync(path); // sync: in the gathering's own thread (gatherSoon)
    } catch {
      return;
    }
    if (st.isSymbolicLink()) {
      list.add({ path, link: readlinkSync(path) }); // sync: in the gathering's own thread (gatherSoon)
      return;
    }
    if (!st.isFile()) return;
    const was = before.get(path);
    let hash: string;
    try {
      hash = was !== undefined && was.size === st.size && was.mtimeMs === st.mtimeMs ? was.hash : hashFile(path);
    } catch {
      return;
    }
    list.add({ path, hash, size: st.size, mode: st.mode & 0o777, mtimeMs: st.mtimeMs });
  };
  /// Every file under `dir` as it is (a checkout's own repository).
  const whole = (dir: string) => {
    let names: string[];
    try {
      names = readdirSync(dir); // sync: in the gathering's own thread (gatherSoon)
    } catch {
      return;
    }
    for (const name of names.sort()) {
      const path = join(dir, name);
      let st;
      try {
        st = lstatSync(path); // sync: in the gathering's own thread (gatherSoon)
      } catch {
        continue;
      }
      if (st.isDirectory()) whole(path);
      else add(path);
    }
  };
  /// Every file under `dir`, but what a build makes again; a git checkout in it as `checkout` takes it.
  const tree = (dir: string) => {
    let names: string[];
    try {
      names = readdirSync(dir); // sync: in the gathering's own thread (gatherSoon)
    } catch {
      return;
    }
    if (names.includes(".git") && checkout(dir)) return;
    for (const name of names.sort()) {
      const path = join(dir, name);
      let st;
      try {
        st = lstatSync(path); // sync: in the gathering's own thread (gatherSoon)
      } catch {
        continue;
      }
      if (st.isDirectory()) {
        if (name === ".git" || !rebuildable(path)) tree(path);
      } else add(path);
    }
  };
  /// A git checkout at `dir`, taken: its files as git lists them (tracked, and untracked but not ignored), a directory
  /// it lists (a repository in it, a submodule) gone into; its `.git` as its files where it is the checkout's own
  /// repository or a submodule's (a relative `gitdir:`), made again from its remote where it is a linked worktree (an
  /// absolute one). False where git does not read it: its files then go as any others do, `.git` with them.
  const checkout = (dir: string): boolean => {
    const dotgit = join(dir, ".git");
    let st;
    try {
      st = lstatSync(dotgit); // sync: in the gathering's own thread (gatherSoon)
    } catch {
      return false;
    }
    const listed = git(dir, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"]);
    if (listed === null) return false;
    // (what a build or an install makes again stays behind here too, where git does not ignore it)
    const made = new Map<string, boolean>();
    const rebuilt = (f: string): boolean => {
      const parts = f.split("/");
      for (let i = 1; i < parts.length; i++) {
        const at = parts.slice(0, i).join("/");
        let r = made.get(at);
        if (r === undefined) made.set(at, (r = rebuildable(join(dir, at))));
        if (r) return true;
      }
      return false;
    };
    const entries = [...new Set(listed.split("\0").map((f) => f.replace(/\/+$/, "")).filter((f) => f !== "" && !rebuilt(f)))];
    const take = () => {
      for (const f of entries) {
        const path = join(dir, f);
        let s;
        try {
          s = lstatSync(path); // sync: in the gathering's own thread (gatherSoon)
        } catch {
          continue;
        }
        if (s.isDirectory()) {
          if (!rebuildable(path)) tree(path);
        } else add(path);
      }
    };
    if (st.isDirectory()) {
      whole(dotgit);
      take();
      return true;
    }
    if (!st.isFile()) return false;
    let said = "";
    try {
      said = readFileSync(dotgit, "utf8").trim(); // sync: in the gathering's own thread (gatherSoon)
    } catch {}
    const gitdir = said.startsWith("gitdir:") ? said.slice("gitdir:".length).trim() : null;
    const worktree = gitdir !== null && isAbsolute(gitdir) ? linked(dir) : null;
    if (worktree === null) add(dotgit);
    else gits.push(worktree);
    take();
    return true;
  };
  /// A linked worktree at `dir`, as it is made again elsewhere: its remote (fetched first, pruned, so a branch deleted
  /// there is not taken as still there), branch, commit, and its commits no remote has in a bundle. Null without a
  /// remote or a commit.
  const linked = (dir: string): CarriedGit | null => {
    const remote = git(dir, ["remote", "get-url", "origin"]);
    const head = git(dir, ["rev-parse", "--verify", "-q", "HEAD"]);
    if (remote === null || remote === "" || head === null || head === "") return null;
    const common = git(dir, ["rev-parse", "--git-common-dir"]);
    const repo = common === null ? dir : resolve(dir, common);
    if (!fetched.has(repo)) {
      fetched.add(repo);
      git(dir, ["fetch", "-q", "--prune", "origin"], FETCH_MS);
    }
    const branch = git(dir, ["symbolic-ref", "--short", "-q", "HEAD"]);
    const bundle = join(scratch, `${gits.length}.bundle`);
    rmSync(bundle, { force: true }); // sync: in the gathering's own thread (gatherSoon)
    // (git refuses a bundle of nothing: every commit of it is on a remote already)
    let hash: string | null = null;
    if (git(dir, ["bundle", "create", "-q", bundle, "HEAD", "--not", "--remotes"]) !== null && existsSync(bundle)) { // sync: in the gathering's own thread (gatherSoon)
      hash = hashFile(bundle);
      bundles[hash] = bundle;
      bytes += lstatSync(bundle).size; // sync: in the gathering's own thread (gatherSoon)
    }
    return { dir, remote, branch: branch === null || branch === "" ? null : branch, head, bundle: hash };
  };
  let realData = dataDir;
  try {
    realData = realpathSync(dataDir); // sync: in the gathering's own thread (gatherSoon)
  } catch {}
  try {
    const rows = d.prepare(sessionsIn(home)).all(ws) as SessionAt[];
    const runs = d.prepare("SELECT id, profile, runtime FROM runtime_sessions WHERE session_key = ? ORDER BY at");
    for (const s of rows) {
      const at = listFile(scratch, s.key);
      // (the hashes the list before said, by path: this session's alone)
      before = new Map();
      if (existsSync(at)) for (const line of linesOf(at)) { // sync: in the gathering's own thread (gatherSoon)
        try {
          const f = JSON.parse(line) as CarriedFile;
          if ("hash" in f) before.set(f.path, { size: f.size, mtimeMs: f.mtimeMs, hash: f.hash });
        } catch {}
      }
      seen = new Set();
      list = new ListFile(at);
      // Its transcripts: each runtime session's, where the station keeps them (its shared place), and a Claude one's
      // subagents beside it.
      const ids = (runs.all(s.key) as { id: string; profile: string | null; runtime: string | null }[]).map((r) => ({ id: r.id, profile: r.profile, runtime: r.runtime ?? s.runtime }));
      if (s.runtime_session_id !== null && !ids.some((r) => r.id === s.runtime_session_id)) ids.push({ id: s.runtime_session_id, profile: s.profile, runtime: s.runtime });
      const found = transcriptSources(dataDir, [], ids.filter((r) => runtimeKind(r.runtime) !== null), sessionPlaces(s));
      for (const t of found.paths) {
        add(storage(t.path));
        if (t.runtime === "claude") {
          const id = t.path.slice(t.path.lastIndexOf(sep) + 1).replace(/\.jsonl$/, "");
          whole(join(dirname(t.path), id));
        }
      }
      // Its room, whole (an archived one's workspace packed in it): one that is not the station's goes nowhere.
      const room = roomFor(dataDir, realData, s.workspace);
      if (room === null) skipped.push(s.key);
      else {
        let names: string[] = [];
        try {
          names = readdirSync(room); // sync: in the gathering's own thread (gatherSoon)
        } catch {}
        for (const name of names.sort()) {
          // (its lock, and what is being written as it is looked at, stay)
          if (name === "archive.lock" || name.endsWith(".writing")) continue;
          const path = join(room, name);
          let st;
          try {
            st = lstatSync(path); // sync: in the gathering's own thread (gatherSoon)
          } catch {
            continue;
          }
          if (st.isDirectory()) {
            if (!rebuildable(path)) tree(path);
          } else add(path);
        }
      }
      const done = list;
      list = null;
      const hash = done.close();
      sessions.push({ key: s.key, workspace: s.workspace, room, list: hash, files: done.files, bytes: done.bytes, at });
      files += done.files;
      bytes += done.bytes;
    }
  } finally {
    d.close();
  }
  const index: CarryIndex = { v: 2, dataDir, sessions, gits, skipped, jobs: [], bundles, files, bytes };
  const path = indexFile(scratch);
  writeFileSync(`${path}.tmp`, JSON.stringify(index)); // sync: in the gathering's own thread (gatherSoon)
  renameSync(`${path}.tmp`, path); // sync: in the gathering's own thread (gatherSoon)
  return { index: path, files, bytes, gits: gits.length, skipped: skipped.length };
}

/// What the index at `indexPath` says put under this station's data directory `dataDir`, each session's list and each
/// file's bytes read from `from` (`<hash>` each, copied: a clone where the disk makes one): where the retired station
/// had it, moved to here. One there already with the same size and time, or the same bytes, is left as it is, another
/// put in its place. A link to the retired station's data directory names this one's. What of it could not be put (its
/// bytes not brought) is counted.
export function place(dataDir: string, indexPath: string, from: string): { placed: number; missing: number; kept: number } {
  const index = JSON.parse(readFileSync(indexPath, "utf8")) as CarryIndex; // sync: in the placing's own thread (placeSoon)
  let placed = 0;
  let missing = 0;
  let kept = 0;
  const root = resolve(dataDir);
  for (const s of index.sessions) {
    const list = join(from, s.list);
    if (!existsSync(list)) { // sync: in the placing's own thread (placeSoon)
      missing += s.files;
      continue;
    }
    for (const line of linesOf(list)) {
      let f: CarriedFile;
      try {
        f = JSON.parse(line) as CarriedFile;
      } catch {
        continue;
      }
      // (resolved first: a path the other station said is put under this one's sessions or transcripts, or nowhere)
      const path = resolve(moved(f.path, index.dataDir, dataDir));
      if (!carriedPlace(root, path)) continue;
      let there = null;
      try {
        there = lstatSync(path); // sync: in the placing's own thread (placeSoon)
      } catch {}
      if ("link" in f) {
        const target = isAbsolute(f.link) ? moved(f.link, index.dataDir, dataDir) : f.link;
        if (there !== null) {
          if (there.isSymbolicLink() && readlinkSync(path) === target) { // sync: in the placing's own thread (placeSoon)
            kept++;
            continue;
          }
          rmSync(path, { recursive: true, force: true }); // sync: in the placing's own thread (placeSoon)
        }
        mkdirSync(dirname(path), { recursive: true }); // sync: in the placing's own thread (placeSoon)
        symlinkSync(target, path); // sync: in the placing's own thread (placeSoon)
        placed++;
        continue;
      }
      if (there !== null && there.isFile() && there.size === f.size && (Math.trunc(there.mtimeMs) === Math.trunc(f.mtimeMs) || hashFile(path) === f.hash)) {
        kept++;
        continue;
      }
      const blob = join(from, f.hash);
      if (!existsSync(blob)) { // sync: in the placing's own thread (placeSoon)
        missing++;
        continue;
      }
      mkdirSync(dirname(path), { recursive: true }); // sync: in the placing's own thread (placeSoon)
      const tmp = `${path}.${randomBytes(4).toString("hex")}.carrying`;
      copyFileSync(blob, tmp, constants.COPYFILE_FICLONE); // sync: in the placing's own thread (placeSoon)
      chmodSync(tmp, f.mode); // sync: in the placing's own thread (placeSoon)
      utimesSync(tmp, f.mtimeMs / 1000, f.mtimeMs / 1000); // sync: in the placing's own thread (placeSoon)
      if (there !== null) rmSync(path, { recursive: true, force: true }); // sync: in the placing's own thread (placeSoon)
      renameSync(tmp, path); // sync: in the placing's own thread (placeSoon)
      placed++;
    }
  }
  return { placed, missing, kept };
}

if (!isMainThread && workerData?.carry !== undefined) {
  const a = workerData.carry;
  try {
    const answer = a.op === "gather" ? gather(a.dataDir, a.db, a.ws, a.home, a.scratch) : a.op === "preview" ? preview(a.dataDir, a.db, a.ws, a.home) : place(a.dataDir, a.index, a.from);
    parentPort!.postMessage({ answer });
  } catch (e) {
    parentPort!.postMessage({ error: (e as Error).message });
  }
}
