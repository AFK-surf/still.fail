// The search index's thread (docs/search.md): keeps `<data>/search.db` as the station's data is, and answers what is
// looked for in it. It reads the station's store on a read-only connection of its own, as a reader does (read/store.ts),
// told by the station what changed (search/search.ts forwards the store's changes); and on its own, every while, looks
// over everything for what it was not told (a start after the station was away, memory written by an agent). The work
// is done a source at a time, the thread let through between them, so what is asked meanwhile is answered at once.
import { parentPort, workerData } from "node:worker_threads";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { openStore } from "../read/store.ts";
import { wall } from "../ops/fibers.ts";
import { homedir } from "node:os";
import { ownPaths } from "../ops/own.ts";
import { rootsOf } from "../drive/drive.ts";
import * as store from "../read/store.ts";
import { agentHomeOf } from "../read/memory.ts";
import { type Asker, SearchIndex } from "./index.ts";
import { READING, Readings, historyDocs, jobDocs, walkFiles, memoryDocs, memoryWorkspaces, profileDocs, profilesOf, sessionKeys, threadDocs, threadIds, type Indexed } from "./sources.ts";

export type Told =
  | { type: "thread"; id: number }
  | { type: "threadRemoved"; id: number }
  | { type: "session"; key: string }
  | { type: "sessionRemoved"; key: string }
  | { type: "job"; id: string }
  | { type: "sweep" }
  /// Answered once nothing told before it is left to do (transcripts waiting to settle aside).
  | { type: "flush"; id: number }
  | { type: "query"; id: number; query: string; asker: Asker; kinds?: string[]; limit?: number; offset?: number };

export type Answered = { id: number; groups?: unknown; building?: boolean; error?: string };

/// How long after a session changes its transcript is read (its last lines written, the turn's end settled).
const SETTLE_MS = 2_000;

const data = workerData.data as string;
const s = openStore(data);
const index = new SearchIndex(join(data, "search.db"));

const threads = new Set<number>();
/// Where the transcripts read lately were read to.
const readings = new Readings();
const jobs = new Set<string>();
/// Sessions whose transcript is to be read, and from when.
const histories = new Map<string, number>();
let sweeping = false;
/// The first look over everything since the start is not done yet: what is found may be missing some.
let building = true;
let pumping = false;
let timer: (() => void) | null = null;
/// The flushes asked for, answered once the work is done.
let flushes: number[] = [];

const config = (): any => {
  try {
    return JSON.parse(readFileSync(join(data, "config.json"), "utf8"));
  } catch {
    return {};
  }
};

/// A source indexed as `found` says: all of it replaced, or what is new put beside what was.
function apply(source: string, found: Indexed | null): void {
  if (found === null) {
    index.drop(source);
    return;
  }
  if (found.whole) {
    index.replace(source, found.version, found.docs);
    return;
  }
  if (found.docs.length === 0 && index.mark(source) === found.version) return;
  index.tx(() => {
    for (const d of found.docs) index.put(d);
    index.setMark(source, found.version);
  });
}

const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

/// A session's execution history indexed: marked as being read first, so one whose reading stops this thread (too
/// large for its heap) is found so when it starts again, and passed over until it changes (sources.ts `historyDocs`).
async function history(key: string, profiles: ReturnType<typeof profilesOf>): Promise<void> {
  const source = `h:${key}`;
  const had = index.mark(source);
  apply(source, await historyDocs(s, key, profiles, had, () => index.setMark(source, READING), readings));
}

/// Everything looked over: each thread, session and workspace indexed where it is not as it is now, and what is gone
/// let go.
async function sweep(): Promise<void> {
  const ids = threadIds(s);
  const live = new Set(ids.map((id) => `t:${id}`));
  for (const source of index.marked("t:")) if (!live.has(source)) index.drop(source);
  // The latest first: what was said lately is what is looked for most.
  for (const id of ids.sort((a, b) => b - a)) {
    threads.add(id);
  }
  await drainThreads();
  const raw = config();
  const profiles = profilesOf(raw, data);
  apply("p", profileDocs(profiles));
  const home = agentHomeOf(data);
  const spaces = [null, ...memoryWorkspaces(home)];
  const known = new Set(spaces.map((w) => `k:${w ?? ""}`));
  for (const source of index.marked("k:")) if (!known.has(source)) index.drop(source);
  for (const ws of spaces) {
    apply(`k:${ws ?? ""}`, memoryDocs(data, ws));
    await tick();
  }
  const keys = sessionKeys(s);
  const sessions = new Set(keys);
  for (const source of [...index.marked("h:"), ...index.marked("j:")]) if (!sessions.has(source.slice(2))) index.drop(source);
  for (const key of keys) {
    apply(`j:${key}`, jobDocs(s, key));
    await history(key, profiles);
    await tick();
  }
  // Last: the first walk of a home can take a while.
  await files(raw, profiles);
}

/// How often the machine's files are walked again where no system index has them (macOS asks Spotlight).
const FILES_EVERY_MS = 6 * 3600_000;

/// The machine's files indexed (not on macOS): the home's for members who may write, each workspace's pinned folders for
/// its members; walked again every FILES_EVERY_MS.
async function files(raw: any, profiles: ReturnType<typeof profilesOf>): Promise<void> {
  if (process.platform === "darwin") return;
  const last = Number(index.mark("fs") ?? 0);
  if (wall.now() - last < FILES_EVERY_MS) return;
  index.setMark("fs", String(wall.now()));
  const skip = ownPaths(data, join(data, "config.json"), profiles.map((p) => p.home));
  const spaces: (string | null)[] = [null, ...Object.keys(raw?.drive?.workspaces ?? {})];
  const tops: { top: string; ws: string | null; scope: string | null; source: string }[] = [{ top: homedir(), ws: "*", scope: "write", source: "fs:home" }];
  for (const ws of spaces) for (const root of rootsOf(raw, ws)) tops.push({ top: root, ws, scope: null, source: `fs:${ws ?? ""}:${root}` });
  const known = new Set(tops.map((t) => t.source));
  for (const source of index.marked("fs:")) if (!known.has(source)) index.drop(source);
  for (const t of tops) {
    index.drop(t.source);
    await walkFiles(t.top, {
      ws: t.ws, scope: t.scope, skip, source: t.source,
      each: async (docs) => {
        index.tx(() => {
          for (const d of docs) index.put(d);
        });
        await tick();
      },
    });
    index.setMark(t.source, String(wall.now()));
  }
}

async function drainThreads(): Promise<void> {
  while (threads.size > 0) {
    const id = threads.values().next().value as number;
    threads.delete(id);
    try {
      apply(`t:${id}`, threadDocs(s, id, index.mark(`t:${id}`)));
    } catch (error) {
      // A thread moved to the archive while it was read: indexed whole next time.
      index.setMark(`t:${id}`, "again");
      if (!(error instanceof Error && /no such|archive|ENOENT/.test(error.message))) throw error;
    }
    await tick();
  }
}

/// What there is to do, done: what was told first, then a sweep when asked for one.
async function pump(): Promise<void> {
  if (pumping) return;
  pumping = true;
  try {
    for (;;) {
      if (threads.size > 0) {
        await drainThreads();
        continue;
      }
      if (jobs.size > 0) {
        const key = jobs.values().next().value as string;
        jobs.delete(key);
        apply(`j:${key}`, jobDocs(s, key));
        await tick();
        continue;
      }
      const now = wall.now();
      const due = [...histories].find(([, at]) => at <= now);
      if (due) {
        histories.delete(due[0]);
        const profiles = profilesOf(config(), data);
        await history(due[0], profiles);
        await tick();
        continue;
      }
      if (sweeping) {
        sweeping = false;
        await sweep();
        building = false;
        continue;
      }
      break;
    }
  } catch (error) {
    parentPort!.postMessage({ id: -1, error: (error as Error).message } satisfies Answered);
  } finally {
    pumping = false;
  }
  for (const id of flushes) parentPort!.postMessage({ id, building } satisfies Answered);
  flushes = [];
  // Transcripts to read later: then.
  const next = Math.min(...histories.values());
  if (Number.isFinite(next)) {
    timer?.();
    timer = wall.after(next - wall.now(), () => void pump());
  }
}

parentPort!.on("message", (told: Told) => {
  switch (told.type) {
    case "query": {
      let answer: Answered;
      try {
        answer = { id: told.id, building, groups: index.search(told.query, told.asker, { kinds: told.kinds, limit: told.limit, offset: told.offset }) };
      } catch (error) {
        answer = { id: told.id, error: (error as Error).message };
      }
      parentPort!.postMessage(answer);
      return;
    }
    case "thread":
      threads.add(told.id);
      break;
    case "threadRemoved":
      index.drop(`t:${told.id}`);
      return;
    case "session": {
      jobs.add(told.key);
      histories.set(told.key, wall.now() + SETTLE_MS);
      // Its chats' titles are its own.
      for (const t of store.sessionThreads(s, told.key)) threads.add(t.id);
      break;
    }
    case "sessionRemoved":
      readings.forget(told.key);
      index.drop(`h:${told.key}`);
      index.drop(`j:${told.key}`);
      return;
    case "job": {
      const job = store.getJob(s, told.id);
      if (job) jobs.add(job.sessionKey);
      break;
    }
    case "sweep":
      sweeping = true;
      break;
    case "flush":
      flushes.push(told.id);
      break;
  }
  void pump();
});
