// Cold storage of archived sessions' files (the Rust station's hub.rs: archive_room, clean_rebuildable, pack_archive,
// archive_history_files, restore_archive, archive_has_jobs, archive_is_cold): once an archived session is idle, what a
// build makes again is removed from its own directory, and the rest of its workspace and the transcripts its runtime
// keeps in station storage are packed (archive.ts); they are restored before its runtime starts again, or when it is
// shown again. The hub calls it (ColdStorage) from the session's queue, so no turn starts halfway through.
import { existsSync, realpathSync, statSync } from "node:fs";
import { access, readdir, realpath, stat, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { wall } from "../ops/fibers.ts";
import { realOutside } from "../ops/places.ts";
import { homesFirst, sessionPlaces, transcriptPaths } from "../read/transcript.ts";
import * as archive from "./archive.ts";
import { runtimeNamed } from "./config.ts";
import { measureRoom, roomOf, roomOfSoon, safeToRemove, within } from "./footprint.ts";
import type { ColdStorage, Hub } from "./hub.ts";

/// Links followed, never into a folder macOS protects (a session continued there, a job's directory: ops/places.ts).
/// Each path is kept for 15 minutes so repeated archive rounds do not follow the same folders on the station's thread.
const followed = new Map<string, { at: number; real: string | null }>();
const FOLLOWED_MS = 15 * 60_000;
const canonical = (path: string): string | null => {
  const now = wall.now();
  const kept = followed.get(path);
  if (kept !== undefined && now - kept.at < FOLLOWED_MS) return kept.real;
  const real = realOutside(path);
  followed.set(path, { at: now, real });
  if (followed.size > 1024) followed.delete(followed.keys().next().value!);
  return real;
};

/// Each session's own directory as last found (`roomOfSoon`, off the thread), for FOLLOWED_MS: `archiveRoom` is asked
/// again before each step of packing one, and followed its paths on the station's thread at every ask.
const rooms = new Map<string, { at: number; room: string | null }>();
const keptRoom = (dataDir: string, workspace: string): string | null => {
  const kept = rooms.get(workspace);
  if (kept !== undefined && wall.now() - kept.at < FOLLOWED_MS) return kept.room;
  return roomOf(dataDir, workspace);
};
async function findRoom(dataDir: string, workspace: string): Promise<void> {
  rooms.set(workspace, { at: wall.now(), room: await roomOfSoon(dataDir, workspace) });
  if (rooms.size > 1024) rooms.delete(rooms.keys().next().value!);
}

/// Whether `path` is there, asked off the station's thread.
const there = (path: string): Promise<boolean> => access(path).then(() => true, () => false);

export class ColdRooms implements ColdStorage {
  /// The hub it works for (made after it).
  private readonly hub: () => Hub;

  constructor(hub: () => Hub) {
    this.hub = hub;
  }

  private dataDir() {
    return this.hub().config().dataDir;
  }

  /// Its session's own directory found off the thread, for `archiveRoom` to ask again and again.
  private async findRoom(key: string): Promise<void> {
    const row = this.hub().store.getSession(key);
    if (row) await findRoom(this.dataDir(), row.workspace);
  }

  /// An archived session's own directory, while nothing needs it: not back in the lists or at work, and no other
  /// session or active job (running, or a service waiting to restart) using it.
  archiveRoom(key: string): string | null {
    const hub = this.hub();
    const row = hub.store.getSession(key);
    if (!row) return null;
    const dir = keptRoom(this.dataDir(), row.workspace);
    if (dir === null || row.archivedAt === null || row.running || hub.processState(key) === "running") return null;
    // The sessions in use alone (by their indexes): this is asked again and again as a session is packed.
    const shared = hub.store
      .sessionsInUse()
      .some(
        (s) =>
          s.key !== key &&
          [s.workspace, s.cwd ?? s.workspace].some((path) => {
            const cwd = canonical(path);
            return cwd !== null && within(cwd, dir);
          }),
      );
    if (shared || this.hasJobs(key, dir)) return null;
    return dir;
  }

  private hasJobs(key: string, dir: string): boolean {
    let jobs;
    try {
      // Those active (running, or a service waiting to start again), by their index: not every job ever run.
      jobs = this.hub().store.jobsUp();
    } catch {
      return true;
    }
    return jobs.some((job) => {
      const cwd = canonical(job.cwd);
      return job.sessionKey === key || (cwd !== null && within(cwd, dir));
    });
  }

  /// Removes what a build or an install makes again (node_modules, a Cargo target, …; footprint.ts `rebuildable`) from
  /// an archived session's own directory: it may come back, and is built again then. Left as it is while the session is
  /// back in the lists or at work, or a session/job still uses its directory. Returns removed allocated file bytes.
  async cleanRebuildable(key: string): Promise<number> {
    await this.findRoom(key);
    const dir = this.archiveRoom(key);
    if (dir === null) return 0;
    let freed = 0;
    for (const [path, bytes] of (await measureRoom(dir)).rebuild) {
      // Restoring a chat updates the store before its next message reaches the actor queue.
      const row = this.hub().store.getSession(key);
      if (!(row && row.archivedAt !== null && !row.running) || this.hasJobs(key, dir)) break;
      if (!(await safeToRemove(path))) continue;
      try {
        await archive.removeTree(path);
        freed += bytes;
      } catch (error) {
        log.warn("hub", "not removed", { path, error: (error as Error).message });
      }
    }
    if (freed > 0) log.info("hub", "rebuildable files of an archived session cleaned", { session: key, freed });
    return freed;
  }

  /// Runtime-owned files outside station storage are never removed. A shared runtime session is left hot while another
  /// chat can still use it. The main transcript and Claude's subagent files are compressed together.
  historyFiles(key: string, packing: boolean): string[] {
    const hub = this.hub();
    const row = hub.store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const sources = hub.store.runtimeSessionSources(key);
    if (sources.length === 0) return [];
    if (packing && sources.some((source) => hub.store.transcriptInUse(source.runtime, source.id, key)))
      return [];
    const config = hub.config();
    const root = realpathSync(config.dataDir);
    const files: string[] = [];
    // With those of the runtime sessions it ran in before (sessions/afresh.ts), each found as its history finds it.
    for (const each of sources) {
      const segmentRuntime = runtimeNamed(each.runtime);
      if (!segmentRuntime) continue;
      const path = transcriptPaths(segmentRuntime, config.dataDir, homesFirst(config.profiles, each.profile), [each.id], sessionPlaces(row)).paths[0];
      if (path === undefined) continue;
      const parent = realpathSync(dirname(path));
      if (!within(parent, root)) continue;
      files.push(join(parent, basename(path)));
      if (segmentRuntime === "claude") archive.jsonlFiles(join(parent, each.id), files);
    }
    return files;
  }

  /// Whether an archived session's directory or transcripts are put away: asked before each of its processes opens, so
  /// off the station's thread, its transcripts found where the live view finds them (live.ts `locateAsync`, a worker's).
  async isCold(key: string): Promise<boolean> {
    const hub = this.hub();
    const row = hub.store.getSession(key);
    const room = row ? await roomOfSoon(this.dataDir(), row.workspace) : null;
    if (room !== null && ((await there(join(room, "cold"))) || (await there(archive.workspaceArchive(room))) || (await there(join(room, "workspace-locks.json")))))
      return true;
    let paths: string[];
    try {
      const locate = hub.live.locateAsync;
      paths = locate !== null
        ? ((await locate(key, new AbortController().signal))?.paths ?? []).map((p) => (typeof p === "string" ? p : p.path))
        : this.historyFiles(key, false);
    } catch {
      return false;
    }
    for (const path of paths) if (!(await there(path)) && (await there(archive.packed(path)))) return true;
    return false;
  }

  async restore(key: string): Promise<void> {
    const row = this.hub().store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const room = roomOf(this.dataDir(), row.workspace);
    if (room === null) return;
    await archive.withLock(room, async () => {
      await archive.restoreWorkspace(room);
      // Restoration must work even after the store has already brought this chat back.
      for (const path of this.historyFiles(key, false)) await archive.restoreFile(path);
      await unlink(join(room, "cold")).catch(() => undefined);
    });
  }

  /// Archived long enough (expireArchived, lifecycle.ts): its workspace keeps only the files sent in its chat
  /// (archive.ts `emptyWorkspace`); its history and transcripts stay. Left as it is while it is shown again or at work,
  /// or something else still uses its directory; one restored (no `cold` mark) is no longer archived.
  /// `before`: only if it was archived by then (one shown and archived again since is archived anew).
  async expire(key: string, before: number): Promise<void> {
    const due = () => {
      const at = this.hub().store.getSession(key)?.archivedAt ?? null;
      return at !== null && at <= before && this.archiveRoom(key) !== null;
    };
    await this.findRoom(key);
    const room = due() ? this.archiveRoom(key) : null;
    if (room === null) return;
    await archive.withLock(room, async () => {
      if (!due() || !(await there(join(room, "cold"))) || !(await archive.holdsMore(room))) return;
      await archive.emptyWorkspace(room);
      log.info("hub", "workspace of a long-archived session emptied", { session: key });
    });
  }

  /// Whether an archived session's directory holds more than its chat's files. Asked of every archived session in turn
  /// (lifecycle.ts expireArchived, relieveArchived): its paths followed off the main thread, where on a station short of
  /// memory (2026-11-02) they held every device for seconds at a time, 47 s in six hours.
  async holdsMore(key: string): Promise<boolean> {
    const row = this.hub().store.getSession(key);
    const room = row ? await roomOfSoon(this.dataDir(), row.workspace) : null;
    return room !== null && (await access(join(room, "cold")).then(() => true, () => false)) && (await archive.holdsMore(room));
  }

  async pack(key: string): Promise<void> {
    await this.findRoom(key);
    const room = this.archiveRoom(key);
    if (room === null) return;
    const ready = () => this.archiveRoom(key) !== null;
    await archive.withLock(room, async () => {
      if (!ready()) return;
      await this.stopStrays(key, join(room, "workspace"));
      if (!ready()) return;
      await this.cleanRebuildable(key);
      if (!ready()) return;
      await writeFile(join(room, "cold"), "workspace and history may be compressed\n");
      await archive.packWorkspaceIf(room, ready);
      if (!ready()) return;
      await this.packHistory(key, ready);
    });
  }

  /// What still runs in an archived session's workspace, its agent's and its jobs' processes gone: what they left
  /// behind running on its own (an adb server its `adb` started, a daemon), stopped even after the workspace is removed.
  private async stopStrays(key: string, workspace: string): Promise<void> {
    if (platform.os === "windows") return;
    let pids: number[];
    try {
      const { stdout } = await promisify(execFile)("ps", ["-U", String(process.getuid?.() ?? ""), "-o", "pid="]);
      pids = stdout.split("\n").map((l) => Number(l.trim())).filter((p) => Number.isSafeInteger(p) && p > 1 && p !== process.pid);
    } catch {
      return;
    }
    const real = await realpath(workspace).catch(() => workspace);
    let stopped = 0;
    for (const [pid, cwd] of await platform.cwds(pids).catch(() => new Map<number, string>())) {
      if (cwd !== real && cwd !== workspace && !within(cwd, real) && !within(cwd, workspace)) continue;
      try {
        process.kill(pid, "SIGTERM");
        stopped++;
      } catch {}
    }
    if (stopped > 0) log.info("hub", "what was left running in an archived session's workspace stopped", { session: key, n: stopped });
  }

  /// Packs an archived session's transcripts in place (its room locked, `ready` while it may), then lets go of the
  /// Rust station's copy of them (`archive/transcripts/<key>.jsonl.zst`, which nothing reads) once they all are: the
  /// copy's size, 0 without one.
  private async packHistory(key: string, ready: () => boolean): Promise<number> {
    const files = this.historyFiles(key, true);
    for (const path of files) {
      await archive.packFileIf(path, () => ready() && this.historyFiles(key, true).length > 0);
    }
    if (files.length === 0) return 0;
    for (const path of files) if ((await there(path)) || !(await there(archive.packed(path)))) return 0;
    const copy = legacyCopy(this.hub().store.archiveDir(), key);
    const size = await stat(copy).then((s) => s.size, () => undefined);
    if (size === undefined) return 0;
    await unlink(copy);
    return size;
  }

  /// What the Rust station's archiving left (2026-09 and early 10): each archived session's transcript copied into
  /// `archive/transcripts/`, its own left as it was, so both were on the disk (1.4 GB on a station). Each such session's
  /// transcripts are packed now as archiving packs them, and the copy let go; nothing makes copies any more, so this
  /// comes to an end. Its workspace is left as it is: only the transcripts are touched. A copy whose session is back
  /// in the lists or at work stays until its session is archived again.
  async finishLegacyCopies(): Promise<void> {
    const dir = join(this.hub().store.archiveDir(), "transcripts");
    let names: string[];
    try {
      names = await readdir(dir);
    } catch {
      return;
    }
    let freed = 0;
    let done = 0;
    for (const name of names) {
      if (!name.endsWith(LEGACY)) continue;
      const key = name.slice(0, -LEGACY.length);
      await this.findRoom(key);
      const room = this.archiveRoom(key);
      if (room === null) continue;
      const ready = () => this.archiveRoom(key) !== null;
      try {
        await archive.withLock(room, async () => {
          if (!ready()) return;
          const size = await this.packHistory(key, ready);
          freed += size;
          if (size > 0) done++;
        });
      } catch (error) {
        log.warn("hub", "an archived session's transcripts not packed", { session: key, error: (error as Error).message });
      }
    }
    if (done > 0) log.info("hub", "the Rust station's transcript copies let go, the transcripts packed", { sessions: done, freed });
  }

  /// Transcripts put away before they were in segments (read/packed.ts), each read whole for every page of its history
  /// (150 MB for one): put away again in segments, one after another. Once every one is, said so on disk (SEGMENTED),
  /// and none looked for again: each station start went through every archived session's
  /// transcripts again, finding them on the station's thread (a Codex one by its sessions' tree), 1.2 s held at a time
  /// on a station short of memory (2026-11-03), every 10 min that evening.
  async segmentHistories(): Promise<void> {
    const said = join(this.dataDir(), SEGMENTED);
    if (await access(said).then(() => true, () => false)) return;
    let done = 0;
    let failed = false;
    const store = this.hub().store;
    // Do not load every session before yielding. The upper bound also keeps newly archived sessions from extending
    // this sweep; archives made now are already put away in segments.
    const through = store.lastArchivedSession();
    let after: typeof through = null;
    while (through !== null) {
      const page = store.archivedSessions(after, through);
      if (page.length === 0) break;
      for (const row of page) {
        let files: string[] = [];
        try {
          files = this.historyFiles(row.key, false);
        } catch {}
        for (const path of files) {
          try {
            if (await archive.segmentFile(path)) done++;
          } catch (error) {
            failed = true;
            log.warn("hub", "a put-away transcript not put in segments", { session: row.key, error: (error as Error).message });
          }
        }
        // Between sessions, including one whose files could not be found, the station's other work.
        await new Promise<void>((resolve) => setImmediate(resolve));
      }
      after = page[page.length - 1]!;
    }
    if (done > 0) log.info("hub", "put-away transcripts put in segments", { n: done });
    if (!failed) await writeFile(said, "").catch(() => undefined);
  }
}

/// Said in the station's data once every transcript put away is in segments (`segmentHistories`).
const SEGMENTED = "transcripts-segmented";

/// The Rust station's copy of an archived session's transcript.
const LEGACY = ".jsonl.zst";
const legacyCopy = (archiveDir: string, key: string) => join(archiveDir, "transcripts", `${key}${LEGACY}`);
