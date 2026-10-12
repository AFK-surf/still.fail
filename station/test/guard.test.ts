// The guard (ops/guard.ts): which processes are the agents' commands, and what it does as the data disk fills and
// memory runs out.
import assert from "node:assert/strict";
import { test } from "node:test";
import { type GuardDeps, type RunningJob, type Runtime, Guard, commands, diskLimits } from "../src/ops/guard.ts";
import type { MemoryPressure, ProcessEntry } from "../src/platform/index.ts";

const GiB = 1024 ** 3;
const MB = 1024; // kB

const p = (pid: number, ppid: number, pgid: number, rssKb: number, command: string): ProcessEntry => ({ pid, ppid, pgid, rssKb, command });

// A claude runtime (10) with an MCP server (11) and a shell (20) running a build (21, 22); a codex app-server (30)
// with a shell (40); a job (pgid 50) whose shell started a browser (51); the station (1) and what is not the agents'.
const TABLE: ProcessEntry[] = [
  p(1, 0, 1, 200 * MB, "node"),
  p(9, 1, 9, 5 * MB, "/Users/a/.stillfail/app/station/stillfail-runner"),
  p(10, 9, 10, 300 * MB, "claude"),
  p(11, 10, 10, 50 * MB, "node"),
  p(20, 10, 20, 3 * MB, "/bin/zsh"),
  p(21, 20, 20, 900 * MB, "cargo"),
  p(22, 21, 20, 400 * MB, "rustc"),
  p(29, 1, 29, 5 * MB, "stillfail-runner"),
  p(30, 29, 30, 200 * MB, "codex"),
  p(40, 30, 40, 2 * MB, "-bash"),
  p(41, 40, 40, 100 * MB, "node"),
  p(50, 1, 50, 2 * MB, "/bin/sh"),
  p(51, 50, 50, 1200 * MB, "/Applications/Chromium.app/Contents/MacOS/Chromium"),
  p(60, 1, 60, 3000 * MB, "Xcode"),
];
const RUNTIMES: Runtime[] = [
  { pid: 10, session: "ember:c-a" },
  { pid: 30, session: null },
];
const JOBS: RunningJob[] = [{ id: "j1", pgid: 50, session: "ember:c-b", name: "preview" }];

test("the agents' commands are their runtimes' shells and their jobs, with all under them; not the runtimes, their MCP servers or anything else", () => {
  const found = commands(TABLE, RUNTIMES, JOBS);
  const by = (pid: number) => found.find((c) => c.pids.includes(pid));
  assert.deepEqual(found.map((c) => [...c.pids].sort((a, b) => a - b)), [[50, 51], [20, 21, 22], [40, 41]]);
  assert.deepEqual(by(21), { pids: by(21)!.pids, rssKb: 1303 * MB, session: "ember:c-a", what: "cargo", job: null });
  assert.equal(by(41)!.session, null);
  assert.equal(by(41)!.what, "node");
  assert.equal(by(51)!.what, 'job "preview"');
  for (const pid of [1, 9, 10, 11, 29, 30, 60]) assert.equal(by(pid), undefined, `process ${pid}`);
});

test("the limits are 8 and 2 GB, or shares of a small disk", () => {
  assert.deepEqual(diskLimits(1000 * GiB), { low: 8 * GiB, full: 2 * GiB });
  const small = diskLimits(40 * GiB);
  assert.deepEqual([small.low / GiB, Math.round((small.full / GiB) * 10) / 10], [4, 1.2]);
});

function fake(over: Partial<GuardDeps> = {}) {
  const said: [string, string][] = [];
  const signals: [number, string][] = [];
  const stopped: string[] = [];
  const state = { free: 100 * GiB, pressure: "normal" as MemoryPressure | null, now: 0, atWork: ["ember:c-a", "ember:c-z"] };
  const deps: GuardDeps = {
    disk: () => ({ free: state.free, total: 500 * GiB }),
    memoryPressure: async () => state.pressure,
    processes: async () => TABLE,
    runtimes: () => RUNTIMES,
    jobs: () => JOBS,
    sessionAt: async (pid) => (pid === 40 ? "ember:c-x" : null),
    atWork: () => state.atWork,
    signal: (pid, signal) => void signals.push([pid, signal]),
    stopJob: async (id) => void stopped.push(id),
    tell: (session, text) => void said.push([session, text]),
    now: () => state.now,
    sleep: async () => {},
    ...over,
  };
  return { guard: new Guard(deps), said, signals, stopped, state };
}

test("the disk running low: the agents at work are told once; nothing is paused", async () => {
  const { guard, said, signals, state } = fake();
  await guard.look();
  assert.equal(said.length, 0);
  state.free = 6 * GiB;
  await guard.look();
  await guard.look();
  assert.deepEqual(said.map(([s]) => s), ["ember:c-a", "ember:c-z"]);
  assert.match(said[0]![1], /6\.0 GB left/);
  assert.equal(signals.length, 0);
});

test("the disk all but full: the commands running are paused and their agents told; with room again they go on", async () => {
  const { guard, said, signals, state } = fake();
  state.free = 1 * GiB;
  await guard.look();
  const stopped = signals.filter(([, s]) => s === "SIGSTOP").map(([pid]) => pid).sort((a, b) => a - b);
  assert.deepEqual(stopped, [20, 21, 22, 40, 41, 50, 51]);
  // The runtime's own session and the job's are told what was paused; another at work, that others' are.
  assert.match(said.find(([s]) => s === "ember:c-a")![1], /paused \(not ended\).*cargo/);
  assert.match(said.find(([s]) => s === "ember:c-b")![1], /job "preview"/);
  assert.match(said.find(([s]) => s === "ember:c-z")![1], /Other agents' commands are paused until 4\.0 GB/);
  // Not at the line itself: only once twice the full room is free.
  said.length = 0;
  signals.length = 0;
  state.free = 3 * GiB;
  await guard.look();
  assert.equal(signals.length, 0);
  state.free = 5 * GiB;
  await guard.look();
  assert.deepEqual(signals.map(([pid, s]) => `${pid} ${s}`).sort(), [20, 21, 22, 40, 41, 50, 51].map((pid) => `${pid} SIGCONT`).sort());
  assert.deepEqual(said.map(([s]) => s).sort(), ["ember:c-a", "ember:c-b"]);
  assert.match(said[0]![1], /go on/);
});

test("the station stopping lets what it paused go on", async () => {
  const { guard, signals, state } = fake();
  state.free = 1 * GiB;
  await guard.look();
  signals.length = 0;
  guard.close();
  assert.equal(signals.filter(([, s]) => s === "SIGCONT").length, 7);
});

test("memory at critical pressure: the biggest command is ended and its agent told; the next not before 30 s", async () => {
  const { guard, said, signals, stopped, state } = fake();
  state.pressure = "warn";
  await guard.look();
  assert.equal(signals.length, 0);
  state.pressure = "critical";
  await guard.look();
  // cargo's shell holds 1.3 GB, the job's browser 1.2 GB.
  assert.deepEqual(signals.map(([pid, s]) => `${pid} ${s}`), ["20 SIGTERM", "21 SIGTERM", "22 SIGTERM", "20 SIGKILL", "21 SIGKILL", "22 SIGKILL"]);
  assert.deepEqual(said.map(([s]) => s), ["ember:c-a"]);
  assert.match(said[0]![1], /ended your cargo \(1\.3 GB\)/);
  signals.length = 0;
  state.now = 20_000;
  await guard.look();
  assert.equal(signals.length, 0);
  assert.equal(stopped.length, 0);
});

test("a job ended for memory is stopped as a job; a shared runtime's command is told to the session working where it runs", async () => {
  const table = TABLE.filter((x) => ![20, 21, 22].includes(x.pid));
  const { guard, said, stopped, state } = fake({ processes: async () => table });
  state.pressure = "critical";
  await guard.look();
  assert.deepEqual(stopped, ["j1"]);
  assert.deepEqual(said.map(([s]) => s), ["ember:c-b"]);

  const codexOnly = TABLE.filter((x) => [29, 30, 40].includes(x.pid)).concat([p(41, 40, 40, 800 * MB, "node")]);
  const other = fake({ processes: async () => codexOnly, jobs: () => [] });
  other.state.pressure = "critical";
  await other.guard.look();
  assert.deepEqual(other.said.map(([s]) => s), ["ember:c-x"]);
});

test("nothing big enough to free memory: nothing is ended", async () => {
  const small = TABLE.map((x) => ({ ...x, rssKb: Math.min(x.rssKb, 100 * MB) }));
  const { guard, signals, stopped, state } = fake({ processes: async () => small });
  state.pressure = "critical";
  await guard.look();
  assert.equal(signals.length, 0);
  assert.equal(stopped.length, 0);
});
