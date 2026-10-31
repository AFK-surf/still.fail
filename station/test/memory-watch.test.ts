// The watch over the memory of what the agents run (jobs/memory.ts): what a unit is, who is told when, and that only a
// machine about to run out of memory has anything stopped (the largest, one at a time). The process table, the
// system's pressure and the signals are the test's; time is a TestClock.
import assert from "node:assert/strict";
import { after, test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import type { Pressure } from "../src/jobs/admit.ts";
import { MemoryWatch, SETTLE_MS, STOP_GRACE_MS, type Unit, limitOf, unitsOf } from "../src/jobs/memory.ts";
import type { ProcessInfo } from "../src/platform/index.ts";
import { fieldOrNull, parsePs, parseTopMem, pressureOfAvailable, pressureOfLevel } from "../src/platform/text.ts";

const GiB = 1024 ** 3;
const p = (pid: number, ppid: number, pgid: number, gib: number, command = "node"): ProcessInfo => ({ pid, ppid, pgid, bytes: gib * GiB, command });

const scopes: Scope.Closeable[] = [];
after(async () => {
  for (const scope of scopes) await Effect.runPromise(Scope.close(scope, Exit.void)).catch(() => undefined);
});

test("a unit is a job's group and what it started, or one command a runtime started; the runtime itself is none", () => {
  const table = [
    p(1, 0, 1, 0, "launchd"),
    p(10, 1, 10, 0.2, "stillfail-station"),
    // A runner, its runtime (claude), two commands it runs: a shell running a build, and an MCP server.
    p(20, 1, 20, 0, "stillfail-runner"),
    p(21, 20, 20, 0.5, "claude"),
    p(22, 21, 22, 0.1, "/bin/zsh"),
    p(23, 22, 22, 3, "/usr/bin/zig"),
    p(24, 21, 24, 0.3, "mcp"),
    // A job: its shell, a server it started that left its parent behind (still in its group).
    p(30, 1, 30, 0.1, "sh"),
    p(31, 30, 30, 1, "cargo"),
    p(32, 1, 30, 2, "server"),
    // Someone else's.
    p(40, 1, 40, 9, "Xcode"),
  ];
  const units = unitsOf(table, [{ id: "job_1", session: "s1", pgid: 30, label: 'Job "build" (job_1)' }], [{ pid: 21, session: "s2" }], 10);
  assert.deepEqual(
    units.map((u) => [u.key, u.session, u.pids.sort((a, b) => a - b), Math.round((u.bytes / GiB) * 10) / 10]),
    [
      ["job:job_1", "s1", [30, 31, 32], 3.1],
      ["pid:22", "s2", [22, 23], 3.1],
      ["pid:24", "s2", [24], 0.3],
    ],
  );
  assert.equal(units[1]!.label, "command zig (pid 22)");
});

test("what the machines say reads", () => {
  assert.equal(fieldOrNull("Anonymous pages: 0.\n", "Anonymous pages"), 0);
  assert.equal(fieldOrNull("Anonymous pages: 123.\n", "Anonymous pages"), 123);
  assert.equal(fieldOrNull("Anonymous pages: unknown\n", "Anonymous pages"), null);
  assert.equal(fieldOrNull("Pages wired down: 123.\n", "Anonymous pages"), null);
  assert.equal(pressureOfLevel("1\n"), "normal");
  assert.equal(pressureOfLevel("2"), "high");
  assert.equal(pressureOfLevel("4"), "critical");
  assert.equal(pressureOfLevel(""), null);
  assert.equal(pressureOfAvailable(50, 100), "normal");
  assert.equal(pressureOfAvailable(9, 100), "high");
  assert.equal(pressureOfAvailable(3, 100), "critical");
  assert.equal(pressureOfAvailable(1, 0), null);
  assert.equal(pressureOfAvailable(fieldOrNull("MemTotal: 100 kB\n", "MemAvailable"), 100), null);
  assert.equal(pressureOfAvailable(0, null), null);
  assert.equal(pressureOfAvailable(101, 100), null);
  assert.deepEqual(parsePs("  1     0     1  1024 /sbin/launchd\n99705 99451 99705 27 node a b\n"), [
    { pid: 1, ppid: 0, pgid: 1, bytes: 1024 * 1024, command: "/sbin/launchd" },
    { pid: 99705, ppid: 99451, pgid: 99705, bytes: 27 * 1024, command: "node a b" },
  ]);
  const top = parseTopMem("Processes: 699 total\nPID    MEM\n99705  27M\n95698  3056K\n95445  2873M+\n100 1.5G-\n7 12B\n");
  assert.deepEqual([...top], [[99705, 27 * 1024 ** 2], [95698, 3056 * 1024], [95445, 2873 * 1024 ** 2], [100, 1.5 * GiB], [7, 12]]);
});

type Rig = ReturnType<typeof rig>;

function rig() {
  const scope = Effect.runSync(Scope.make());
  scopes.push(scope);
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  const state = { pressure: "normal" as Pressure, table: [] as ProcessInfo[], exact: [] as boolean[] };
  const told: [string | null, string][] = [];
  const signals: [number, string][] = [];
  const stoppedJobs: string[] = [];
  const watch = new MemoryWatch({
    clock,
    pressure: async () => state.pressure,
    table: async (exact) => {
      state.exact.push(exact);
      return state.table;
    },
    totalBytes: () => 64 * GiB,
    cwds: async (pids) => new Map(pids.map((pid) => [pid, `/sessions/s9/workspace/sub`])),
    jobs: () => [{ id: "job_1", session: "remote:x", pgid: 30, label: 'Job "build" (job_1)' }],
    // A runtime of one session's, and one shared by sessions (codex's host).
    agents: async () => [{ pid: 21, session: "s2" }, { pid: 51, session: null }],
    sessionAt: (dir) => (dir.startsWith("/sessions/s9/workspace") ? "s9" : null),
    tell: (u: Unit, text) => void told.push([u.job ?? u.session, text]),
    stopJob: async (id) => void stoppedJobs.push(id),
    signal: (pid, signal) => void signals.push([pid, signal]),
    self: 10,
  });
  return { watch, clock, state, told, signals, stoppedJobs };
}

const tables = {
  /// A job of 3 GiB, a command of 9 GiB, a codex command of 1 GiB.
  some: (build = 9) => [
    p(21, 20, 20, 0.5, "claude"),
    p(22, 21, 22, 0.1, "zsh"),
    p(23, 22, 22, build, "zig"),
    p(30, 1, 30, 3, "sh"),
    p(51, 50, 50, 0.4, "codex"),
    p(52, 51, 52, 1, "pnpm"),
  ],
};

test("much memory is told to its agent, again when it doubles; nothing is stopped for it", async () => {
  const r = rig();
  r.state.table = tables.some();
  await r.watch.look();
  // The limit on 64 GiB is 8 GiB: the 9 GiB command is told, the 3 GiB job not.
  assert.equal(limitOf(64 * GiB), 8 * GiB);
  assert.deepEqual(r.told.map(([who]) => who), ["s2"]);
  assert.match(r.told[0]![1], /command zig \(pid 22\) on this station uses 9\.1 GiB/);
  await r.watch.look();
  assert.equal(r.told.length, 1, "told once");
  r.state.table = tables.some(19);
  await r.watch.look();
  assert.equal(r.told.length, 2, "again, as it doubled");
  assert.deepEqual(r.signals, []);
  assert.deepEqual(r.stoppedJobs, []);
  assert.deepEqual(r.state.exact, [false, false, false], "resident memory is enough while there is no pressure");
});

test("under pressure the largest few are told once, and still nothing is stopped", async () => {
  const r = rig();
  r.state.table = tables.some(4);
  r.state.pressure = "high";
  await r.watch.look();
  await r.watch.look();
  assert.deepEqual(r.told.map(([who]) => who), ["s2", "job_1", "s9"], "the codex command's session found by its directory");
  assert.match(r.told[0]![1], /memory is under pressure/);
  assert.deepEqual(r.signals, []);
  assert.deepEqual(r.state.exact, [true, true], "read exactly under pressure");
  // Eased, and again under pressure: told again.
  r.state.pressure = "normal";
  await r.watch.look();
  r.state.pressure = "high";
  await r.watch.look();
  assert.equal(r.told.length, 6);
});

async function stopping(r: Rig, look: Promise<unknown>) {
  // A command's stop waits STOP_GRACE_MS before the SIGKILL.
  for (let i = 0; i < 10 && r.signals.length > 0 && !r.signals.some(([, s]) => s === "SIGKILL"); i++) {
    await Effect.runPromise(r.clock.adjust(`${STOP_GRACE_MS} millis`));
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  await look;
}

test("about to run out, the largest is stopped and its agent told why; the next only after a while, if still so", async () => {
  const r = rig();
  r.state.table = tables.some(9);
  r.state.pressure = "critical";
  const first = r.watch.look();
  await new Promise((resolve) => setTimeout(resolve, 1));
  await stopping(r, first);
  assert.deepEqual(r.signals, [[22, "SIGTERM"], [23, "SIGTERM"], [22, "SIGKILL"], [23, "SIGKILL"]]);
  assert.ok(r.told.some(([who, text]) => who === "s2" && /about to run out of memory, so it stopped your command zig/.test(text)));
  // Still critical, the big command gone: the job is next, but not before SETTLE_MS.
  r.state.table = tables.some(0).filter((x) => x.pid !== 22 && x.pid !== 23);
  await r.watch.look();
  assert.deepEqual(r.stoppedJobs, []);
  await Effect.runPromise(r.clock.adjust(`${SETTLE_MS} millis`));
  await r.watch.look();
  assert.deepEqual(r.stoppedJobs, ["job_1"]);
  assert.ok(r.told.some(([who, text]) => who === "job_1" && /stopped your Job "build"/.test(text)));
});
