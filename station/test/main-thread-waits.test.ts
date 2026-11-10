// What the station's main thread waits on through a day's work, counted: its synchronous calls of node:fs, the processes
// it waits on (node:child_process's *Sync) and its statements (store/timed.ts). Each takes as long as the disk, the
// machine and other processes make it take (a statement of 9 µs took 300 ms on a station short of memory, 2026-11-06):
// nothing of it may be added where it is not counted here. Counts, never times. A scenario's statements are what it
// takes now (STATEMENTS): a change may lower them, never raise them; its files and processes, where they are fixed at
// their cause, none.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { Jobs } from "../src/jobs/jobs.ts";
import { Remote, written } from "../src/jobs/remote.ts";
import { platform } from "../src/platform/index.ts";
import { Store } from "../src/store/store.ts";
import { timeFiles, timeProcesses } from "../src/ops/file-waits.ts";
import { WAITED_MS } from "../src/ops/waits.ts";
import { takeQueries } from "../src/store/timed.ts";
import { LENGTHS_GATHER_MS, sessionKey } from "../src/sessions/hub.ts";
import { Rig, message, reply, settle, testClock } from "./hub-fakes.ts";

type Counted = { files: number; processes: number; statements: number };

// Each call takes WAITED_MS by this clock: every one is put down with who made it.
let at = 0;
const each = () => (at += WAITED_MS);
const files = timeFiles(each);
const processes = timeProcesses(each);
after(() => {
  files.stop();
  processes.stop();
});

/// What `work` made the main thread wait on.
async function counted(work: () => Promise<unknown>): Promise<Counted> {
  files.take();
  processes.take();
  takeQueries();
  await work();
  const f = files.take();
  const p = processes.take();
  if (process.env.SHOW_WAITS) console.log([...f.by.keys(), ...p.by.keys()].join("\n"));
  return { files: f.calls, processes: p.calls, statements: takeQueries().calls };
}

/// The statements each scenario takes now: lower one where a change lowers it.
const STATEMENTS = {
  transcriptGrowing: 0,
  lengthsWritten: 4,
  turn: 97,
  toolCall: 4,
  usageRecord: 6,
  remoteToolCall: 1,
} as const;

test("a transcript growing: read and told, its length gathered, written with the others' once LENGTHS_GATHER_MS is up", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  try {
    // Each one's first length is written at once (its summary says it from then on).
    r.hub.live.lengths!("s0", 0);
    r.hub.live.lengths!("s1", 0);
    const grew = await counted(async () => {
      for (let n = 1; n <= 50; n++) r.hub.live.lengths!(`s${n % 2}`, n);
      await settle();
    });
    assert.deepEqual(grew, { files: 0, processes: 0, statements: STATEMENTS.transcriptGrowing });
    const writtenOnce = await counted(async () => {
      await time.adjust(LENGTHS_GATHER_MS);
      await settle();
    });
    // BEGIN, the two sessions' upserts, COMMIT.
    assert.deepEqual(writtenOnce, { files: 0, processes: 0, statements: STATEMENTS.lengthsWritten });
    assert.deepEqual(r.store.db.prepare("SELECT session, n FROM transcript_lengths ORDER BY session").all().map((row) => ({ ...row })), [{ session: "s0", n: 50 }, { session: "s1", n: 49 }]);
  } finally {
    await r.close();
  }
});

test("a turn, a tool call and a usage record: no file, no process, their statements", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  // Transcripts are found off the main thread, as the station has them found (agents.ts: the live locator).
  r.hub.live.locateAsync = async () => null;
  try {
    const m = message();
    await r.accept(m);
    await settle();
    const key = sessionKey("cl", "C1", m.threadTs);
    const to = `C1/${m.threadTs}`;
    await r.call(key, "chat_post", { to, text: "looking", kind: "all_done", done: "answered" });
    r.claude.last().complete();
    await settle();
    // The next turn of a session at work: a person's message, the agent's post, its end.
    const turn = await counted(async () => {
      await r.accept(reply(m, `${Number(m.ts) + 1}`, "<@UBOT> and this?", { addressed: true }));
      await settle();
      await r.call(key, "chat_post", { to, text: "this too", kind: "all_done", done: "answered this too" });
      r.claude.last().complete();
      await settle();
    });
    assert.deepEqual(turn, { files: 0, processes: 0, statements: STATEMENTS.turn });
    const toolCall = await counted(() => r.call(key, "chat_history", { to }));
    assert.deepEqual(toolCall, { files: 0, processes: 0, statements: STATEMENTS.toolCall });
    const usageRecord = await counted(async () => {
      r.store.recordUsage("/t.jsonl", { session: key, offset: 100, model: "opus" }, "claude", [[
        { id: "call-1", at: r.store.now(), model: "opus", subagent: false, fast: false, input: 10, cacheRead: 100, cacheWrite: 5, cacheWriteLong: 0, output: 20, calls: 1, context: 115, window: 200_000 },
        { turn: null, person: null, thread: null, profile: "cc" },
      ]]);
    });
    assert.deepEqual(usageRecord, { files: 0, processes: 0, statements: STATEMENTS.usageRecord });
  } finally {
    await r.close();
  }
});

test("a remote tool call: its records written off the thread, no file, no process", async () => {
  const dir = mkdtempSync(join(tmpdir(), "main-thread-waits-"));
  const store = Store.open(":memory:");
  const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
  const remote = new Remote({ data: dir, store, jobs, notify: () => {} });
  try {
    mkdirSync(join(dir, "mesh"), { recursive: true });
    writeFileSync(join(dir, "mesh", "cloud.json"), JSON.stringify({ workspace: "ws", station: "A" }));
    // The station's cloud.json as it keeps it in memory (followRoster).
    remote.place = () => ({ workspace: "ws", station: "A" });
    store.insertSession({ key: "s1", connect: "ds", runtime: "claude", profile: "cc", workspace: dir, token: "t1", createdBy: "ann", createdAt: store.now(), lastActiveAt: store.now() });
    remote.attach(async (station, _workspace, request) => station === "" ? { stations: [{ id: "B", name: "B" }] } : { key: request.key, prepared: true });
    const call = (key: string) => remote.tool("station_task", "s1", { station: "B", key, action: "prepare", command: "true" });
    await call("first");
    const toolCall = await counted(async () => {
      await call("second");
      await written(remote.usedPath("s1"));
    });
    assert.deepEqual(toolCall, { files: 0, processes: 0, statements: STATEMENTS.remoteToolCall });
  } finally {
    await remote.close();
    await jobs.shutdown();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a station's start follows its jobs again, and the memory watch reads the memory, waiting on no process", async () => {
  const dir = mkdtempSync(join(tmpdir(), "main-thread-waits-"));
  const store = Store.open(":memory:");
  const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
  try {
    // A group an earlier station recorded: this process, started at another time (not that group).
    store.recordProcess(process.pid, 1, "job", "left");
    const started = await counted(() => jobs.relaunch());
    assert.equal(started.processes, 0);
    assert.equal(store.listProcesses().length, 0, "not ours: forgotten");
    const pressure = await counted(() => platform.memoryPressure());
    assert.deepEqual(pressure, { files: 0, processes: 0, statements: 0 });
  } finally {
    await jobs.shutdown();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
