// What the station's main thread waits on through a day's work, counted: its synchronous calls of node:fs, the processes
// it waits on (node:child_process's *Sync) and its statements (store/timed.ts). Each takes as long as the disk, the
// machine and other processes make it take (a statement of 9 µs took 300 ms on a station short of memory, 2026-11-06):
// nothing of it may be added where it is not counted here. Counts, never times. A scenario's statements are what it
// takes now (STATEMENTS): a change may lower them, never raise them; its files and processes, where they are fixed at
// their cause, none.
import assert from "node:assert/strict";
import { appendFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
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
import { claudeOAuthToken } from "../src/accounts/oauth.ts";
import { findRunner } from "../src/agents/process.ts";
import { install } from "../src/helper/app.ts";
import { WorkspaceWatch } from "../src/jobs/workspace-size.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { LogExport } from "../src/ops/log-export.ts";
import { linkSkills } from "../src/sessions/actor.ts";
import { ColdRooms } from "../src/sessions/cold.ts";
import { fingerprint, profileFilesRead } from "../src/sessions/decision.ts";
import { LiveHub } from "../src/sessions/live.ts";
import { sessionSeen } from "../src/api/seen.ts";
import { autoArchive } from "../src/sessions/lifecycle.ts";
import { iso } from "../src/read/transcript.ts";
import { UsageCounter, claudeProject } from "../src/usage/counter.ts";
import { usageTurns } from "../src/store/usage.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { archiveLookOf } from "../src/store/store.ts";
import { DatabaseSync } from "node:sqlite";

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
  // SHOW_SQL: each statement seen as slow, so that the log says its SQL and who asked (a look at what a count is).
  const real = performance.now;
  let clock = real.call(performance);
  if (process.env.SHOW_SQL) performance.now = () => (clock += 1000);
  try {
    await work();
  } finally {
    performance.now = real;
  }
  const f = files.take();
  const p = processes.take();
  const q = takeQueries();
  if (process.env.SHOW_WAITS) console.log([...f.by.keys(), ...p.by.keys(), ...q.by.keys()].join("\n"));
  return { files: f.calls, processes: p.calls, statements: q.calls };
}

/// The statements each scenario takes now: lower one where a change lowers it.
const STATEMENTS = {
  transcriptGrowing: 0,
  lengthsWritten: 4,
  // 98 until #5188 (6810813bf): a session whose model no account enables is kept on its account before each turn, so the
  // pool is not asked to pick and no longer reads each running session's row (hub.ts `running`, `getSession`).
  // 97 until sessions stopped running in sandboxes: a turn no longer reads its session's row to copy its files there.
  turn: 96,
  toolCall: 4,
  // A call recorded with compact usage installed, as a station has it: BEGIN, whether it was recorded before, its
  // session's context as kept, the call, its context, its file's position, COMMIT. (12 before: sqlite_master asked twice,
  // the context read three times and its pointer written again unchanged.)
  usageRecord: 7,
  remoteToolCall: 1,
  // task.files asks whether the task's job is running: the job by its primary key (store.getJob).
  remoteTask: 1,
  // The session's row by its primary key, for its workspace (store.getSession).
  coldAsked: 1,
  // 50 before: each told change asked a session's row for its workspace.
  seenTold: 0,
  // 20 before: each tool call asked the session of its token.
  tokenResolved: 0,
  // The counter's cursor, the sessions in one statement, their runtime sources (one each), and one transaction: BEGIN,
  // for each call as a usage record is (5), COMMIT; the turns are a reader's. (Before: a transaction for each transcript,
  // each session's row read again for its sources, the turns of each part (5 statements) here, and a usage record's 11.)
  usageRead: 16,
  // 53 before (3 sessions archived, one at work): every session shown and chat of its own, and of each idle one its
  // bindings, pin, chats, row, jobs, keeps and work, read here. Now the look is a reader's; here only the archiving of each
  // session it archives: BEGIN, its row and its chat out of the lists, COMMIT, its chats and row for what is told, its
  // last turn as its process is let go (7 each).
  autoArchiveLook: 21,
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
    // Compact usage installed, as the usage module installs it as the station starts (usage/module.ts).
    installCompactUsage(r.store.db, () => r.store.now());
    // A call of its recorded already: its context kept, as a session at work has it.
    r.store.recordUsage("/t.jsonl", { session: key, offset: 50, model: "opus" }, "claude", [[
      { id: "call-0", at: r.store.now(), model: "opus", subagent: false, fast: false, input: 10, cacheRead: 100, cacheWrite: 5, cacheWriteLong: 0, output: 20, calls: 1, context: 110, window: 200_000 },
      { turn: null, person: null, thread: null, profile: "cc" },
    ]]);
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

/// A directory of its own for a scenario, removed after it.
const scratch = () => mkdtempSync(join(tmpdir(), "main-thread-waits-"));

test("a followed transcript growing is read and told off the main thread, its file looked at nowhere on it", async () => {
  const dir = scratch();
  const time = testClock();
  const path = join(dir, "t.jsonl");
  const said = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-11-10T00:00:00Z", message: { id, content: [{ type: "text", text }] } })}\n`;
  writeFileSync(path, said("one", "m1"));
  const live = new LiveHub(() => ({ runtime: "claude", paths: [path] }), time.clock);
  // Where the station finds transcripts: off the main thread (agents.ts: the live locator).
  live.locateAsync = async () => ({ runtime: "claude", paths: [path], current: true });
  const told: string[] = [];
  live.heldTold = (_key, m) => void (m.type === "timeline" && told.push(...m.entries.map((e) => e.text ?? "")));
  try {
    live.running("s", true);
    await live.idle();
    const grew = await counted(async () => {
      appendFileSync(path, said("two", "m2")); // (the agent's write, not the station's)
      files.take();
      await time.adjust(100);
      await settle();
      await live.idle();
      await live.turnEnded("s");
      await live.idle();
    });
    assert.ok(told.includes("two"), told.join());
    assert.deepEqual(grew, { files: 0, processes: 0, statements: 0 });
  } finally {
    live.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("what the station keeps of its files in memory is read off the main thread: the log's batches, its runners, a login, a profile's files, the helper's copy, a workspace's limits, a session's memory and skills", async () => {
  const dir = scratch();
  try {
    // The log's batches: config.json watched, the station's id held (main.ts).
    const config = new ConfigFile(dir);
    config.watch();
    const logs = new LogExport();
    logs.configure({ enabled: () => config.raw()?.telemetry?.logs !== false, station: () => "station", version: () => "v" });
    logs.sendWith(async () => {});
    // A login's token, the refresh not due.
    const home = join(dir, "claude");
    mkdirSync(home);
    writeFileSync(join(home, ".credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "token", expiresAt: Date.now() + 86_400_000 } }));
    // A Codex profile's files.
    const codex = join(dir, "codex");
    mkdirSync(codex);
    writeFileSync(join(codex, "config.toml"), 'model_provider = "openai"\n');
    const profile = { id: "cx", name: "cx", runtime: "codex", runtimes: ["codex"], home: codex, models: [], named: [], env: {}, backgroundOnMessage: true } as any;
    await profileFilesRead(profile);
    // The helper's copy of the release's app, the same as it.
    const app = join(dir, "app", "still.fail Helper.app");
    for (const f of ["Contents/MacOS/stillfail-helper", "Contents/Info.plist", "Contents/_CodeSignature/CodeResources"]) {
      mkdirSync(dirname(join(app, f)), { recursive: true });
      writeFileSync(join(app, f), f);
    }
    await install(app, join(dir, "helper"));
    // A workspace's limits, read as it starts.
    const watch = new WorkspaceWatch({ data: dir, readings: async () => [], working: () => false, notify: () => {} });
    await watch.ready();
    // A session's agent home: its memory and a skill.
    const agent = join(dir, "agent");
    mkdirSync(join(agent, "skills", "one"), { recursive: true });
    writeFileSync(join(agent, "MEMORY.md"), "# lessons\n");
    writeFileSync(join(agent, "skills", "one", "SKILL.md"), "one");
    const row = { key: "s", workspace: join(dir, "workspace"), cwd: null };
    mkdirSync(row.workspace);
    const kept = await counted(async () => {
      logs.add({ ms: 0, level: "INFO", at: "station", message: "a line", fields: {} });
      await logs.flush();
      await claudeOAuthToken({}, home, null, "http://127.0.0.1:9/token");
      await findRunner(dir, "claude-s");
      fingerprint(profile);
      await install(app, join(dir, "helper"));
      await watch.setLimit("s", "", 20);
      watch.limit("s", "");
      assert.equal(await linkSkills(row, { memoryPath: () => join(agent, "MEMORY.md") }), "# lessons");
    });
    assert.deepEqual(kept, { files: 0, processes: 0, statements: 0 });
    await logs.shutdown();
    config.unwatch();
    await watch.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a task on this station for another's chat: prepared and its files listed off the main thread", async () => {
  const dir = scratch();
  const store = Store.open(":memory:");
  const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
  const remote = new Remote({ data: dir, store, jobs, notify: () => {} });
  try {
    // The session's room made, at its first task (its directory, once a minute).
    await remote.handle("ws", "peer", { method: "task.prepare", session: "s", key: "first", spec: { command: "true" } });
    const task = await counted(async () => {
      await remote.handle("ws", "peer", { method: "task.prepare", session: "s", key: "second", spec: { command: "true" } });
      await remote.handle("ws", "peer", { method: "task.files", session: "s", key: "second", paths: ["missing.txt"] });
      await remote.handle("ws", "peer", { method: "task.mirrors", session: "s" });
    });
    assert.deepEqual(task, { files: 0, processes: 0, statements: STATEMENTS.remoteTask });
  } finally {
    await remote.close();
    await jobs.shutdown();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("an archived session's directory and transcripts are asked of as it opens, off the main thread", async () => {
  const r = new Rig();
  r.hub.live.locateAsync = async () => ({ runtime: "claude", paths: [join(r.dir, "nowhere.jsonl")], current: true });
  // The session at work is followed as it starts (live.ts `running`), off the main thread: its transcript's first length
  // is written once its reader says it, whenever that is (on CI's Linux, inside what is counted below). Counted after it.
  const note = r.hub.live.lengths!;
  const followed = new Promise<void>((noted) => (r.hub.live.lengths = (key, n) => (note(key, n), noted())));
  try {
    const m = message();
    await r.accept(m);
    await followed;
    await settle();
    const key = sessionKey("cl", "C1", m.threadTs);
    const cold = new ColdRooms(() => r.hub);
    const asked = await counted(async () => assert.equal(await cold.isCold(key), false));
    assert.deepEqual(asked, { files: 0, processes: 0, statements: STATEMENTS.coldAsked });
  } finally {
    await r.close();
  }
});

test("the changes told to each viewer ask each session's workspace of memory, and each tool call its token", async () => {
  const r = new Rig();
  try {
    const m = message();
    await r.accept(m);
    await settle();
    const key = sessionKey("cl", "C1", m.threadTs);
    const token = r.store.getSession(key)!.token;
    const viewer = { workspace: "", home: true };
    // Asked once as the session is first told.
    sessionSeen(r.store, viewer, key);
    r.store.sessionKeyByToken(token);
    const told = await counted(async () => {
      for (let i = 0; i < 50; i++) assert.equal(sessionSeen(r.store, viewer, key), true);
    });
    assert.deepEqual(told, { files: 0, processes: 0, statements: STATEMENTS.seenTold });
    const resolved = await counted(async () => {
      for (let i = 0; i < 20; i++) assert.equal(r.store.sessionKeyByToken(token), key);
    });
    assert.deepEqual(resolved, { files: 0, processes: 0, statements: STATEMENTS.tokenResolved });
  } finally {
    await r.close();
  }
});

test("the usage counter writes what it read of two sessions' transcripts in one transaction", async () => {
  const dir = scratch();
  const time = testClock();
  await time.adjust(Date.parse("2026-11-10T08:00:00Z"));
  const store = Store.open(join(dir, "stillfail.db"), null, time.clock);
  // The turns its calls were made in, a reader's (its own connection, as the station's readers have).
  const reader = new DatabaseSync(join(dir, "stillfail.db"), { readOnly: true });
  const counter = new UsageCounter({ store, config: () => ({ dataDir: dir, profiles: [{ home: join(dir, "homes/cc") }] }), clock: time.clock,
    turns: async (session, from, until) => usageTurns(reader, session, from, until) });
  try {
    installCompactUsage(store.db, () => store.now());
    const now = store.now();
    const call = (id: string, at: number) => `${JSON.stringify({ type: "assistant", timestamp: iso(at), isSidechain: false, message: { id, model: "claude-opus-5-5", usage: { input_tokens: 10, output_tokens: 2 } } })}\n`;
    const paths: string[] = [];
    for (const key of ["a", "b"]) {
      const workspace = join(dir, key);
      store.insertSession({ key, connect: "ember", createdBy: "x", runtime: "claude", profile: "cc", workspace, token: `t-${key}`, createdAt: now - 60_000, lastActiveAt: now - 60_000 });
      store.startTurn(`turn-${key}`, key, "input");
      const path = join(dir, "transcripts/claude", claudeProject(workspace), "r.jsonl");
      mkdirSync(dirname(path), { recursive: true });
      appendFileSync(path, call(`${key}-1`, now + 1));
      paths.push(path);
    }
    await counter.read();
    // A call more in each, read as they come (live.ts asks).
    for (const [i, path] of paths.entries()) appendFileSync(path, call(`more-${i}`, now + 2));
    const read = await counted(async () => assert.equal(await counter.read(new Set(["a", "b"])), 2));
    assert.deepEqual(read, { files: 0, processes: 0, statements: STATEMENTS.usageRead });
  } finally {
    await counter.stop();
    reader.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the auto-archive's look is a reader's: here only the sessions it archives cost anything", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  try {
    const keys: string[] = [];
    for (let i = 0; i < 4; i++) {
      const m = message();
      await r.accept(m);
      await settle();
      const key = sessionKey("cl", "C1", m.threadTs);
      // The last at work still (its turn not ended): it stays.
      if (i < 3) {
        await r.call(key, "chat_state", { kind: "all_done", done: "答完了它问的事" });
        r.claude.last().complete();
      }
      await settle();
      keys.push(key);
    }
    await time.adjust(r.hub.config().autoArchiveMs + 60_000);
    // What a reader read for the look (read/ops-sessions.ts `archiveLook`), as the station has it carried over.
    const { autoArchiveMs, slackArchiveMs } = r.hub.config();
    const read = JSON.parse(JSON.stringify(archiveLookOf(r.store.db, r.hub.now(), autoArchiveMs, slackArchiveMs)));
    const look = await counted(async () => {
      autoArchive(r.hub, r.hub.now(), undefined, undefined, undefined, undefined, undefined, read);
    });
    assert.deepEqual(keys.map((key) => r.store.getSession(key)?.archivedAt !== null), [true, true, true, false], "the three done, not the one at work");
    // For each session archived, its archiving; nothing for the one that stays, nor for the look itself.
    assert.deepEqual(look, { files: 0, processes: 0, statements: STATEMENTS.autoArchiveLook });
  } finally {
    await r.close();
  }
});
