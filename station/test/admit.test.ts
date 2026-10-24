// The station's queue for other stations' tasks (jobs/admit.ts): which waiting task starts, and when, by what is
// measured (the CPUs over the last seconds, what the system says of its memory) and nothing estimated; then the queue
// in Jobs itself, on a TestClock and a machine the test says.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { type Clock, Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { BUSY_SPAN_MS, Busy, LOOK_MS, RAMP_MS, type Pressure, cpusFor, pick, place } from "../src/jobs/admit.ts";
import { Jobs, type Machine, STOP_LOOK_MS } from "../src/jobs/jobs.ts";
import { signalGroup } from "../src/ops/group.ts";
import { Store } from "../src/store/store.ts";
import { WINDOWS } from "../src/platform/index.ts";

const w = (id: string, session: string, queuedAt: number, screen = false) => ({ id, session, screen, queuedAt });
const never = () => null;

describe("which task starts", () => {
  test("with none of the queue running, the first starts however busy the machine is", () => {
    assert.deepEqual(pick([w("a", "s", 1), w("b", "s", 2)], [], { busy: 1, pressure: "normal" }, 0, null, never), { start: w("a", "s", 1) });
  });

  test("another waits for the last to get going, then for the CPUs to have room", () => {
    const running = [{ id: "x", screen: false }];
    const waiting = [w("a", "s", 1)];
    assert.deepEqual(pick(waiting, running, { busy: 0, pressure: "normal" }, RAMP_MS - 1, 0, never), { wait: "busy" });
    assert.deepEqual(pick(waiting, running, { busy: 0.9, pressure: "normal" }, RAMP_MS, 0, never), { wait: "busy" });
    assert.deepEqual(pick(waiting, running, { busy: null, pressure: "normal" }, RAMP_MS, 0, never), { wait: "busy" });
    assert.deepEqual(pick(waiting, running, { busy: 0.5, pressure: "normal" }, RAMP_MS, 0, never), { start: w("a", "s", 1) });
  });

  test("none starts while the memory is under pressure, not even the first", () => {
    for (const pressure of ["high", "critical"] as Pressure[]) {
      assert.deepEqual(pick([w("a", "s", 1)], [], { busy: 0, pressure }, 0, null, never), { wait: "memory" });
    }
    // Not read: the CPUs decide.
    assert.deepEqual(pick([w("a", "s", 1)], [], { busy: 0, pressure: null }, 0, null, never), { start: w("a", "s", 1) });
  });

  test("a task that uses the screen waits for the other one, and lets those that do not go first", () => {
    const running = [{ id: "x", screen: true }];
    assert.deepEqual(pick([w("a", "s", 1, true)], running, { busy: 0, pressure: "normal" }, RAMP_MS, 0, never), { wait: "screen" });
    assert.deepEqual(pick([w("a", "s", 1, true), w("b", "s", 2)], running, { busy: 0, pressure: "normal" }, RAMP_MS, 0, never), { start: w("b", "s", 2) });
  });

  test("the session whose task last started longest ago goes first: ten of one do not keep another's behind them", () => {
    const waiting = [w("a1", "a", 1), w("a2", "a", 2), w("a3", "a", 3), w("b1", "b", 4)];
    const last = (s: string) => (s === "a" ? 100 : null);
    assert.deepEqual(pick(waiting, [], { busy: 0, pressure: "normal" }, 0, null, last), { start: w("b1", "b", 4) });
    assert.equal(place(waiting, "b1", last), 1);
    assert.equal(place(waiting, "a1", last), 2);
    assert.equal(place(waiting, "a3", last), 4);
    assert.equal(place(waiting, "gone", last), null);
  });
});

test("how busy the CPUs were is over the last seconds only, and unknown until they span enough of them", () => {
  const busy = new Busy();
  busy.note(0, [0, 0]);
  busy.note(LOOK_MS, [5, 10]);
  assert.equal(busy.share(), null, "less than half the span");
  busy.note(BUSY_SPAN_MS / 2, [10, 20]);
  assert.equal(busy.share(), 0.5);
  // A long while later: what was noted then is not compared with.
  busy.note(10 * BUSY_SPAN_MS, [20, 40]);
  assert.equal(busy.share(), null);
  busy.note(10 * BUSY_SPAN_MS + BUSY_SPAN_MS, [29, 50]);
  assert.equal(busy.share(), 0.9);
});

test("since a task started, how busy the CPUs were is over the ticks noted from then on", () => {
  const busy = new Busy();
  busy.note(0, [0, 0]);
  busy.note(LOOK_MS, [10, 10]);
  busy.note(2 * LOOK_MS, [11, 20]);
  busy.note(3 * LOOK_MS, [12, 30]);
  assert.equal(busy.share(), 0.4);
  assert.equal(busy.share(LOOK_MS), 0.1, "the busy first look before the start left out");
  assert.equal(busy.share(2 * LOOK_MS), null, "less than two looks since");
});

test("a task started beside others is told how many CPUs are free, unless its environment says already", () => {
  assert.deepEqual(cpusFor({}, 12, 0.5, true), {}, "alone: the machine is its");
  assert.deepEqual(cpusFor({}, 12, 0.5, false), { STILLFAIL_CPUS: "6", MAKEFLAGS: "-j6", CARGO_BUILD_JOBS: "6", CMAKE_BUILD_PARALLEL_LEVEL: "6" });
  assert.deepEqual(cpusFor({ MAKEFLAGS: "-j2", CARGO_BUILD_JOBS: "3" }, 12, 0.99, false), { STILLFAIL_CPUS: "1", CMAKE_BUILD_PARALLEL_LEVEL: "1" });
});

// ── the queue in Jobs ──

const dirs: string[] = [];
const all: Jobs[] = [];
const scopes: Scope.Closeable[] = [];
after(async () => {
  for (const j of all) {
    for (const job of j.store.listJobs(null)) if (job.pgid !== null) signalGroup(job.pgid, "SIGKILL");
    await j.shutdown().catch(() => undefined);
  }
  for (const scope of scopes) await Effect.runPromise(Scope.close(scope, Exit.void)).catch(() => undefined);
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function testClock(): Clock.Clock & { move: (ms: number) => Promise<void> } {
  const scope = Effect.runSync(Scope.make());
  scopes.push(scope);
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  return Object.assign(clock, { move: (ms: number) => Effect.runPromise(clock.adjust(`${ms} millis`)) });
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Waits for what a real process does, looking every 5 ms; no deadline.
async function until(_what: string, check: () => boolean) {
  while (!check()) await sleep(5);
}

/// A machine whose CPUs and memory the test says: `busy` the share since the last look.
function machine(state: { busy: number; pressure: Pressure }): Machine {
  let [b, t] = [0, 0];
  return {
    cpus: () => 8,
    ticks: () => {
      t += 1000;
      b += 1000 * state.busy;
      return [b, t];
    },
    pressure: async () => state.pressure,
  };
}

function rig(state: { busy: number; pressure: Pressure }, store?: Store, data?: string) {
  const dir = data ?? mkdtempSync(join(tmpdir(), "admit-test-"));
  if (data === undefined) dirs.push(dir);
  const work = join(dir, "work");
  mkdirSync(work, { recursive: true });
  const s = store ?? Store.open(":memory:");
  const clock = testClock();
  const told: string[] = [];
  const jobs = new Jobs({ store: s, data: dir, notify: (_s, t) => void told.push(t), link: () => null, clock, machine: machine(state) });
  all.push(jobs);
  const start = (id: string, session: string, command: string, screen = false) =>
    jobs.startId(`remote:${session}`, id, command, work, null, false, `remote_${id}`, false, { screen });
  return { jobs, store: s, clock, start, dir, told };
}

/// Stops a job. Its group may outlive its leader a moment (what it ran not yet reaped), and the stop's grace looks again
/// on the rig's clock: moved here, a look of the stop at a time, until the stop is over.
async function stop(r: { jobs: Jobs; clock: { move: (ms: number) => Promise<void> } }, id: string) {
  let over = false;
  const stopped = r.jobs.stop(id).finally(() => (over = true));
  while (!over) {
    await r.clock.move(STOP_LOOK_MS);
    await sleep(5);
  }
  return stopped;
}

/// Moves the clock on, a look at a time, until `check` holds.
async function looks(clock: { move: (ms: number) => Promise<void> }, check: () => boolean) {
  while (!check()) {
    await clock.move(LOOK_MS);
    await sleep(5);
  }
}

const FOREVER = "tail -f /dev/null";

describe("the queue", { skip: WINDOWS && "jobs' groups and sh" }, () => {
  test("a task that comes while another runs waits, and starts once that one ends", async () => {
    const state = { busy: 1, pressure: "normal" as Pressure };
    const r = rig(state);
    const first = r.start("one", "a", FOREVER);
    assert.notEqual(first.queued, true);
    assert.notEqual(first.pgid, null);
    const second = r.start("two", "b", "echo $STILLFAIL_CPUS");
    assert.equal(second.queued, true);
    assert.equal(second.state, "running", "running as far as its agent is concerned");
    assert.deepEqual(r.jobs.queueOf(second.id), { place: 1, why: "busy" });
    // However long the CPUs stay busy, it waits.
    await r.clock.move(RAMP_MS * 4);
    assert.equal(r.store.getJob(second.id)!.queued, true);
    await stop(r, first.id);
    await until("it starts and ends", () => r.store.getJob(second.id)!.state === "exited");
    assert.equal(r.jobs.queueOf(second.id), null);
  });

  test("with room on the CPUs, the next starts once the last has had its ramp, told how many CPUs are free", async () => {
    const state = { busy: 0.25, pressure: "normal" as Pressure };
    const r = rig(state);
    r.start("one", "a", FOREVER);
    const second = r.start("two", "a", `printf '%s' "$STILLFAIL_CPUS" > cpus`);
    assert.equal(second.queued, true);
    await looks(r.clock, () => r.store.getJob(second.id)!.queued !== true);
    await until("it ends", () => r.store.getJob(second.id)!.state === "exited");
    assert.equal(readFileSync(join(r.dir, "work", "cpus"), "utf8"), "6");
  });

  test("one started that has ended holds nothing back: the next starts at once, or at the next look", async () => {
    const state = { busy: 0.05, pressure: "normal" as Pressure };
    const r = rig(state);
    r.start("one", "a", FOREVER);
    const quick = r.start("two", "b", "true");
    await looks(r.clock, () => r.store.getJob(quick.id)!.queued !== true);
    await until("it ends", () => r.store.getJob(quick.id)!.state === "exited");
    // (the first still runs: under the old flat ramp this one waited for the ended one's)
    const next = r.start("three", "c", "true");
    if (next.queued === true) {
      await r.clock.move(LOOK_MS);
      await sleep(5);
    }
    assert.notEqual(r.store.getJob(next.id)!.queued, true, "not held for the ended one's ramp");
  });

  test("while the memory is under pressure nothing starts; once it eases the waiting one does", async () => {
    const state = { busy: 0, pressure: "high" as Pressure };
    const r = rig(state);
    const first = r.start("one", "a", FOREVER);
    const second = r.start("two", "b", "true");
    await r.clock.move(LOOK_MS);
    await sleep(5);
    await stop(r, first.id);
    await r.clock.move(RAMP_MS * 2);
    await sleep(5);
    assert.equal(r.store.getJob(second.id)!.queued, true);
    assert.equal(r.jobs.queueOf(second.id)!.why, "memory");
    state.pressure = "normal";
    await looks(r.clock, () => r.store.getJob(second.id)!.queued !== true);
  });

  test("a waiting task stopped never runs; one left waiting through a restart starts after it", async () => {
    const state = { busy: 0, pressure: "high" as Pressure };
    const r = rig(state);
    const first = r.start("one", "a", FOREVER);
    const stopped = r.start("two", "b", "touch ran");
    const kept = r.start("three", "c", "true");
    // The queue has looked at the memory.
    await r.clock.move(LOOK_MS);
    await sleep(5);
    await r.jobs.stop(stopped.id);
    assert.equal(r.store.getJob(stopped.id)!.state, "stopped");
    await stop(r, first.id);
    assert.equal(r.store.getJob(kept.id)!.queued, true, "the memory still under pressure");
    // The station stops while it waits, and the next takes it up once the memory has eased.
    await r.jobs.shutdown();
    state.pressure = "normal";
    const again = rig(state, r.store, r.dir);
    again.jobs.relaunch();
    await until("it ran", () => r.store.getJob(kept.id)!.state === "exited");
    assert.equal(existsSync(join(r.dir, "work", "ran")), false);
  });
});
