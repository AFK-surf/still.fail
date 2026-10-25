// Cold storage of archived sessions' files (the Rust station's hub.rs: archive_room, clean_rebuildable, pack_archive,
// archive_history_files, restore_archive, archive_has_jobs, archive_is_cold): once an archived session is idle, what a
// build makes again is removed from its own directory, and the rest of its workspace and the transcripts its runtime
// keeps in station storage are packed (archive.ts); they are restored before its runtime starts again, or when it is
// shown again. The hub calls it (ColdStorage) from the session's queue, so no turn starts halfway through.
import { existsSync, realpathSync, statSync } from "node:fs";
import { readdir, rm, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { log } from "../ops/log.ts";
import { realOutside } from "../ops/places.ts";
import { homesFirst, sessionPlaces, transcriptPaths } from "../read/transcript.ts";
import * as archive from "./archive.ts";
import { runtimeNamed } from "./config.ts";
import { measureRoom, roomOf, safeToRemove, within } from "./footprint.ts";
import type { ColdStorage, Hub } from "./hub.ts";

/// Links followed, never into a folder macOS protects (a session continued there, a job's directory: ops/places.ts).
const canonical = (path: string): string | null => realOutside(path);

export class ColdRooms implements ColdStorage {
  /// The hub it works for (made after it).
  private readonly hub: () => Hub;

  constructor(hub: () => Hub) {
    this.hub = hub;
  }

  private dataDir() {
    return this.hub().config().dataDir;
  }

  /// An archived session's own directory, while nothing needs it: not back in the lists or at work, and no other
  /// session or active job (running, or a service waiting to restart) using it.
  archiveRoom(key: string): string | null {
    const hub = this.hub();
    const row = hub.store.getSession(key);
    if (!row) return null;
    const dir = roomOf(this.dataDir(), row.workspace);
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
    const dir = this.archiveRoom(key);
    if (dir === null) return 0;
    let freed = 0;
    for (const [path, bytes] of (await measureRoom(dir)).rebuild) {
      // Restoring a chat updates the store before its next message reaches the actor queue.
      const row = this.hub().store.getSession(key);
      if (!(row && row.archivedAt !== null && !row.running) || this.hasJobs(key, dir)) break;
      if (!(await safeToRemove(path))) continue;
      try {
        await rm(path, { recursive: true });
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
    const id = row.runtimeSessionId;
    if (hub.store.runtimeSessions(key).length === 0) return [];
    if (
      packing &&
      id !== null &&
      hub.store.sessionsInUse().some((s) => s.key !== key && s.runtime === row.runtime && s.runtimeSessionId === id)
    )
      return [];
    const config = hub.config();
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) return [];
    const root = realpathSync(config.dataDir);
    const files: string[] = [];
    const homes = homesFirst(config.profiles, row.profile);
    // With those of the runtime sessions it ran in before (sessions/afresh.ts), each found as its history finds it.
    for (const each of hub.store.runtimeSessions(key)) {
      const path = transcriptPaths(runtime, config.dataDir, homes, [each], sessionPlaces(row)).paths[0];
      if (path === undefined) continue;
      const parent = realpathSync(dirname(path));
      if (!within(parent, root)) continue;
      files.push(join(parent, basename(path)));
      if (runtime === "claude") archive.jsonlFiles(join(parent, each), files);
    }
    return files;
  }

  isCold(key: string): boolean {
    const row = this.hub().store.getSession(key);
    const room = row ? roomOf(this.dataDir(), row.workspace) : null;
    if (room !== null && (existsSync(join(room, "cold")) || existsSync(archive.workspaceArchive(room)) || existsSync(join(room, "workspace-locks.json"))))
      return true;
    try {
      return this.historyFiles(key, false).some((path) => !existsSync(path) && existsSync(archive.packed(path)));
    } catch {
      return false;
    }
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
      if (existsSync(join(room, "cold"))) await unlink(join(room, "cold"));
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
    const room = due() ? this.archiveRoom(key) : null;
    if (room === null) return;
    await archive.withLock(room, async () => {
      if (!due() || !existsSync(join(room, "cold")) || !(await archive.holdsMore(room))) return;
      await archive.emptyWorkspace(room);
      log.info("hub", "workspace of a long-archived session emptied", { session: key });
    });
  }

  /// Whether an archived session's directory holds more than its chat's files.
  async holdsMore(key: string): Promise<boolean> {
    const row = this.hub().store.getSession(key);
    const room = row ? roomOf(this.dataDir(), row.workspace) : null;
    return room !== null && existsSync(join(room, "cold")) && (await archive.holdsMore(room));
  }

  async pack(key: string): Promise<void> {
    const room = this.archiveRoom(key);
    if (room === null) return;
    const ready = () => this.archiveRoom(key) !== null;
    await archive.withLock(room, async () => {
      if (!ready()) return;
      await this.cleanRebuildable(key);
      if (!ready()) return;
      await writeFile(join(room, "cold"), "workspace and history may be compressed\n");
      await archive.packWorkspaceIf(room, ready);
      if (!ready()) return;
      await this.packHistory(key, ready);
    });
  }

  /// Packs an archived session's transcripts in place (its room locked, `ready` while it may), then lets go of the
  /// Rust station's copy of them (`archive/transcripts/<key>.jsonl.zst`, which nothing reads) once they all are: the
  /// copy's size, 0 without one.
  private async packHistory(key: string, ready: () => boolean): Promise<number> {
    const files = this.historyFiles(key, true);
    for (const path of files) {
      await archive.packFileIf(path, () => ready() && this.historyFiles(key, true).length > 0);
    }
    if (files.length === 0 || !files.every((path) => !existsSync(path) && existsSync(archive.packed(path)))) return 0;
    const copy = legacyCopy(this.hub().store.archiveDir(), key);
    const size = statSync(copy, { throwIfNoEntry: false })?.size;
    if (size === undefined) return 0;
    await unlink(copy);
    return size;
  }

  /// What the Rust station's archiving left (2026-09 and early 10): each archived session's transcript copied into
  /// `archive/transcripts/`, its own left as it was, so both were on the disk (1.4 GB on ccvm). Each such session's
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
}

/// The Rust station's copy of an archived session's transcript.
const LEGACY = ".jsonl.zst";
const legacyCopy = (archiveDir: string, key: string) => join(archiveDir, "transcripts", `${key}${LEGACY}`);
