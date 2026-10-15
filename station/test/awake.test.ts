// The machine held awake while the station has work going (src/ops/awake.ts).
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import { Effect } from "effect";
import { Awake, working } from "../src/ops/awake.ts";
import { Fibers, liveClock } from "../src/ops/fibers.ts";
import { WINDOWS, platform } from "../src/platform/index.ts";

/// A part's clock that stands where it is set and never wakes a wait: each step is a `check()` of the test's.
function standing() {
  let now = 1_000_000;
  const clock = { ...liveClock, currentTimeMillisUnsafe: () => now, sleep: () => Effect.never };
  return { fibers: new Fibers("awake", clock), move: (ms: number) => void (now += ms) };
}

test("held while there is work, let go a minute after it ends", async () => {
  const { fibers, move } = standing();
  let busy = false;
  const holds: string[] = [];
  let released = 0;
  const awake = new Awake({ working: () => busy, hold: (why) => (holds.push(why), () => void released++), fibers });
  awake.check();
  assert.equal(awake.held, false);
  busy = true;
  awake.check();
  assert.equal(awake.held, true);
  awake.check();
  assert.equal(holds.length, 1, "held once, not again while held");
  busy = false;
  move(30_000);
  awake.check();
  assert.equal(awake.held, true, "a next turn often follows: still held");
  move(31_000);
  awake.check();
  assert.equal(awake.held, false);
  assert.equal(released, 1);
  busy = true;
  awake.check();
  await awake.close();
  assert.equal(released, 2, "closing lets go");
});

test("a machine with no way to hold it: asked again, no failure", async () => {
  const { fibers } = standing();
  let asked = 0;
  const awake = new Awake({ working: () => true, hold: () => (asked++, null), fibers });
  awake.check();
  awake.check();
  assert.equal(awake.held, false);
  assert.equal(asked, 2);
  await awake.close();
});

test("work is a running turn, a wait on what a session started, or a running job that is not a service on a port", () => {
  type Last = { declared: string | null; endedAt: number | null; waitSeconds: number | null };
  const store = (sessions: { running: boolean }[], jobs: { state: string; watch: boolean; port: number | null }[], last: Last[] = []) =>
    ({ listSessions: () => sessions, listJobs: () => jobs, sessionStats: () => new Map(last.map((l, i) => [String(i), { lastTurn: l }])) }) as never;
  const now = 10_000_000;
  assert.equal(working(store([{ running: false }], []), now), false);
  assert.equal(working(store([{ running: true }], []), now), true);
  assert.equal(working(store([], [{ state: "running", watch: false, port: null }]), now), true);
  assert.equal(working(store([], [{ state: "running", watch: false, port: 5173 }]), now), false);
  assert.equal(working(store([], [{ state: "running", watch: true, port: 5173 }]), now), true);
  assert.equal(working(store([], [{ state: "exited", watch: false, port: null }]), now), false);
  // Waiting on CI for up to 10 minutes, 5 minutes in: work; long past its wait (stopped, or nothing came of it): not.
  assert.equal(working(store([], [], [{ declared: "waiting", endedAt: now - 300_000, waitSeconds: 600 }]), now), true);
  assert.equal(working(store([], [], [{ declared: "waiting", endedAt: now - 3_600_000, waitSeconds: 600 }]), now), false);
  assert.equal(working(store([], [], [{ declared: "all_done", endedAt: now - 1000, waitSeconds: null }]), now), false);
});

/// Windows' system-wide execution state (CallNtPowerInformation SystemExecutionState): ES_SYSTEM_REQUIRED is 0x1.
const STATE = [
  `Add-Type -Namespace P -Name N -MemberDefinition '[DllImport("powrprof.dll")] public static extern uint CallNtPowerInformation(int level, System.IntPtr i, uint il, out uint o, uint ol);'`,
  "$o = 0; [void][P.N]::CallNtPowerInformation(16, [IntPtr]::Zero, 0, [ref]$o, 4); $o",
].join("; ");
const systemRequired = () => (Number(execFileSync("powershell", ["-NoProfile", "-NonInteractive", "-Command", STATE], { encoding: "utf8" }).trim()) & 1) === 1;

test("Windows: the holder keeps the system required until let go", { skip: !WINDOWS }, async () => {
  const release = platform.holdAwake("still.fail test");
  assert.ok(release);
  try {
    let held = false;
    for (let i = 0; i < 40 && !held; i++) {
      await new Promise((r) => setTimeout(r, 250));
      held = systemRequired();
    }
    assert.ok(held, "the system is required while held");
  } finally {
    release();
  }
});
