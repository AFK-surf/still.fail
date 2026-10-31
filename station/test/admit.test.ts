// The station's queue for other stations' tasks (jobs/admit.ts): which waiting task starts, and when, by what is
// measured (the CPUs over the last seconds, what the system says of its memory) and nothing estimated; who has the
// screen; then the queue in Jobs itself, on a TestClock and a machine the test says.
import assert from "node:assert/strict";
import { type ChildProcess, spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { type Clock, Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { BUSY_SPAN_MS, Busy, type Claim, HELD_LONG_MS, LOOK_MS, RAMP_MS, type Pressure, claimsOf, cpusFor, overstaying, pick, place, served } from "../src/jobs/admit.ts";
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
    assert.deepEqual(pick(waiting, running, { busy: 0, pressure: "normal" }, RAMP_MS - 1, 0, never), { wait: "busy", cause: "sampling" });
    assert.deepEqual(pick(waiting, running, { busy: 0.9, pressure: "normal" }, RAMP_MS, 0, never), { wait: "busy", cause: "cpu" });
    assert.deepEqual(pick(waiting, running, { busy: null, pressure: "normal" }, RAMP_MS, 0, never), { wait: "busy", cause: "sampling" });
    assert.deepEqual(pick(waiting, running, { busy: 0.5, pressure: "normal" }, RAMP_MS, 0, never), { start: w("a", "s", 1) });
  });

  test("a CPU wait says whether it is measuring or the measured CPUs are busy", () => {
    const running = [{ id: "x", screen: false }];
    const waiting = [w("a", "s", 1)];
    assert.deepEqual(pick(waiting, running, { busy: 0.2, pressure: "normal" }, RAMP_MS - 1, 0, never), { wait: "busy", cause: "sampling" });
    assert.deepEqual(pick(waiting, running, { busy: null, pressure: "normal" }, RAMP_MS, 0, never), { wait: "busy", cause: "sampling" });
    assert.deepEqual(pick(waiting, running, { busy: 0.9, pressure: "normal" }, RAMP_MS, 0, never), { wait: "busy", cause: "cpu" });
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

  test("a task that uses the screen throughout waits while a command holds it, and for one that asked before it came", () => {
    const room = { busy: 0, pressure: "normal" as Pressure };
    const holding = claimsOf([{ job: "x", pid: 1, at: 0, held: true }]);
    assert.deepEqual(pick([w("a", "s", 1, true)], [], room, 0, null, never, holding), { wait: "screen" });
    assert.deepEqual(pick([w("a", "s", 1, true), w("b", "s", 2)], [], room, 0, null, never, holding), { start: w("b", "s", 2) });
    const asked = claimsOf([{ job: "x", pid: 1, at: 5, held: false }]);
    assert.deepEqual(pick([w("a", "s", 5, true)], [], room, 0, null, never, asked), { wait: "screen" });
    assert.deepEqual(pick([w("a", "s", 4, true)], [], room, 0, null, never, asked), { start: w("a", "s", 4, true) }, "it came first");
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

test("the screen goes to the first command that asked while no task has it, and at once to one whose task has it", () => {
  const c = (job: string, pid: number, held = false, since?: number): Claim => ({ job, pid, at: pid, held, ...(since === undefined ? {} : { since }) });
  assert.deepEqual(served([c("a", 1), c("b", 2), c("a", 3)], new Set(), 9), [c("a", 1, true, 9), c("b", 2), c("a", 3, true, 9)]);
  assert.deepEqual(served([c("b", 2, true), c("a", 3)], new Set(), 9), [c("b", 2, true), c("a", 3)], "b's until it gives it back");
  assert.deepEqual(served([c("a", 1), c("t", 2)], new Set(["t"]), 9), [c("a", 1), c("t", 2, true, 9)], "inside a task that has it throughout");
  assert.deepEqual(claimsOf([c("b", 2, true), c("a", 3), c("c", 4)]), { held: true, asked: 3 });
  assert.deepEqual(claimsOf([]), { held: false, asked: null });
});

test("while a person uses the screen nothing more is given it; what has it goes on, and a command of its own still gets it", () => {
  const c = (job: string, pid: number, held = false, since?: number): Claim => ({ job, pid, at: pid, held, ...(since === undefined ? {} : { since }) });
  assert.deepEqual(served([c("a", 1), c("b", 2)], new Set(), 9, true), [c("a", 1), c("b", 2)], "none given");
  assert.deepEqual(served([c("a", 1, true, 5), c("a", 3)], new Set(), 9, true), [c("a", 1, true, 5), c("a", 3, true, 9)], "a's own");
  // the queue's tasks that use the screen throughout wait for the person, said so; the others start
  const screen = w("s", "x", 1, true);
  assert.deepEqual(pick([screen], [], { busy: 0, pressure: "normal", person: true }, 0, null, never), { wait: "person" });
  assert.deepEqual(pick([screen, w("p", "y", 2)], [], { busy: 0, pressure: "normal", person: true }, 0, null, never), { start: w("p", "y", 2) });
  // another task's having it says so before the person
  assert.deepEqual(pick([screen], [], { busy: 0, pressure: "normal", person: true }, 0, null, never, { held: true, asked: null }), { wait: "screen" });
});

test("a command that has held the screen long while another waits is told; none is while none waits", () => {
  const c = (job: string, pid: number, held: boolean, since?: number): Claim => ({ job, pid, at: 0, held, ...(since === undefined ? {} : { since }) });
  const long = c("vm", 1, true, 0);
  assert.deepEqual(overstaying([long], HELD_LONG_MS), [], "no one waits");
  assert.deepEqual(overstaying([long, c("pic", 2, false)], HELD_LONG_MS), [long]);
  assert.deepEqual(overstaying([long, c("pic", 2, false)], HELD_LONG_MS - 1), [], "not long yet");
  assert.deepEqual(overstaying([c("old", 3, true), c("pic", 2, false)], HELD_LONG_MS), [c("old", 3, true)], "an earlier station's: since it asked");
});

test("how busy the CPUs were is over the last seconds only, and unknown until they span enough of them", () => {
  const busy = new Busy();
  busy.note(0, [0, 0]);
  busy.note(LOOK_MS, [5, 10]);
  assert.equal(busy.share(), null, "less than half the span");
  busy.note(BUSY_SPAN_MS / 2, [10, 20]);
  assert.equal(busy.share(), 0.5);
  assert.deepEqual(busy.sample(), { share: 0.5, seconds: 10, checkedAt: BUSY_SPAN_MS / 2 });
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
function machine(state: { busy: number; pressure: Pressure; idle?: number }): Machine {
  let [b, t] = [0, 0];
  return {
    cpus: () => 8,
    ticks: () => {
      t += 1000;
      b += 1000 * state.busy;
      return [b, t];
    },
    pressure: async () => state.pressure,
    inputIdle: async () => state.idle ?? null,
  };
}

function rig(state: { busy: number; pressure: Pressure; idle?: number }, store?: Store, data?: string) {
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
    assert.equal(r.jobs.queueOf(second.id)!.why, "busy");
    assert.equal(r.jobs.queueOf(second.id)!.cause, "sampling");
    // However long the CPUs stay busy, it waits.
    await r.clock.move(RAMP_MS * 4);
    assert.equal(r.store.getJob(second.id)!.queued, true);
    await looks(r.clock, () => r.jobs.queueOf(second.id)!.decision.cpuBusy !== null);
    assert.equal(r.jobs.queueOf(second.id)!.cause, "cpu");
    assert.equal(r.jobs.queueOf(second.id)!.decision.cpuBusy!.share, 1);
    assert.equal(r.jobs.queueOf(second.id)!.decision.memoryPressure, "normal");
    await stop(r, first.id);
    await until("it starts and ends", () => r.store.getJob(second.id)!.state === "exited");
    assert.equal(r.jobs.queueOf(second.id), null);
  });

  test("each waiting task says its own blocker when another task uses the screen", async () => {
    const r = rig({ busy: 0, pressure: "normal" });
    r.start("shots", "a", FOREVER, true);
    const screen = r.start("next-shots", "b", FOREVER, true);
    const plain = r.start("tests", "c", FOREVER);
    const screenQueue = r.jobs.queueOf(screen.id)!;
    const plainQueue = r.jobs.queueOf(plain.id)!;
    assert.equal(screenQueue.why, "screen");
    assert.match(screenQueue.holder!, /^shots /);
    assert.equal(plainQueue.why, "busy");
    assert.equal(plainQueue.cause, "sampling");
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

  test("a command waits for the screen while a task has it throughout, has it once that ends, and a task that uses it after the command asked waits for it", async () => {
    const state = { busy: 0, pressure: "normal" as Pressure };
    const r = rig(state);
    const shots = r.start("shots", "a", FOREVER, true);
    const tests = r.start("tests", "b", FOREVER);
    await looks(r.clock, () => r.store.getJob(tests.id)!.queued !== true);
    const p = aShell();
    const token = r.store.getJob(tests.id)!.token;
    const asked = r.jobs.screenAsked(token, "take", p.pid!);
    assert.equal(asked.screen, "waiting");
    // (who has it, said: the task, its chat, how long)
    assert.match("who" in asked ? asked.who ?? "" : "", /^shots \(remote_shots\) of chat remote:a, for \d+ min$/);
    // The task that has the screen throughout: its own commands have it at once.
    assert.deepEqual(r.jobs.screenAsked(r.store.getJob(shots.id)!.token, "take", aShell().pid!), { screen: "yours" });
    const later = r.start("later", "c", "true", true);
    await stop(r, shots.id);
    assert.deepEqual(r.jobs.screenAsked(token, "take", p.pid!), { screen: "yours" }, "asked again, it has it");
    await r.clock.move(RAMP_MS * 2);
    await sleep(5);
    assert.equal(r.store.getJob(later.id)!.queued, true, "the command asked first");
    assert.equal(r.jobs.queueOf(later.id)!.why, "screen");
    assert.deepEqual(r.jobs.screenAsked(token, "give", p.pid!), { screen: "given" });
    await looks(r.clock, () => r.store.getJob(later.id)!.queued !== true);
  });

  test("a command killed before it gave the screen back no longer has it; one that has it through a restart still does", async () => {
    const state = { busy: 0, pressure: "normal" as Pressure };
    const r = rig(state);
    const one = r.jobs.start("s1", "one", FOREVER, join(r.dir, "work"), null, false);
    const two = r.jobs.start("s2", "two", FOREVER, join(r.dir, "work"), null, false);
    const [p1, p2] = [aShell(), aShell()];
    assert.deepEqual(r.jobs.screenAsked(one.token, "take", p1.pid!), { screen: "yours" });
    await r.jobs.shutdown();
    const again = rig(state, r.store, r.dir);
    again.jobs.relaunch();
    const waiting = again.jobs.screenAsked(two.token, "take", p2.pid!);
    assert.equal(waiting.screen, "waiting", "the next station knows who has it");
    assert.match("who" in waiting ? waiting.who ?? "" : "", /^one \(.+\) of chat s1, for \d+ min$/);
    p1.kill("SIGKILL");
    await until("it is gone", () => p1.exitCode !== null || p1.signalCode !== null);
    assert.deepEqual(again.jobs.screenAsked(two.token, "take", p2.pid!), { screen: "yours" });
    assert.throws(() => again.jobs.screenAsked("nope", "take", p2.pid!), /unknown job token/);
  });
});

test("while a person uses the machine a command waits for the screen, told so; once they leave it has it", async () => {
  const state = { busy: 0, pressure: "normal" as Pressure, idle: 5_000 };
  const r = rig(state);
  const one = r.jobs.start("s1", "one", FOREVER, join(r.dir, "work"), null, false);
  const p = aShell();
  // (the first ask reads the machine's input: the second answers by it)
  r.jobs.screenAsked(one.token, "take", p.pid!);
  await sleep(5);
  r.jobs.screenAsked(one.token, "give", p.pid!);
  const asked = r.jobs.screenAsked(one.token, "take", p.pid!);
  assert.deepEqual(asked, { screen: "waiting", place: 1, who: "a person using this machine" });
  state.idle = 10 * 60_000;
  // (read as it is asked, apart from the answer: the next ask, a second later, has it)
  await sleep(5);
  r.jobs.screenAsked(one.token, "take", p.pid!);
  await sleep(5);
  assert.deepEqual(r.jobs.screenAsked(one.token, "take", p.pid!), { screen: "yours" });
});

test("a command that holds the screen long while another waits has its agent told, once", async () => {
  const state = { busy: 0, pressure: "normal" as Pressure };
  const r = rig(state);
  const vm = r.jobs.start("s1", "vm", FOREVER, join(r.dir, "work"), null, false);
  const pics = r.jobs.start("s2", "pictures", FOREVER, join(r.dir, "work"), null, false);
  const [p1, p2] = [aShell(), aShell()];
  // (the clock said, not read: the screen given at t0 itself, held HELD_LONG_MS to the millisecond below)
  const t0 = r.store.now();
  r.store.now = () => t0;
  assert.deepEqual(r.jobs.screenAsked(vm.token, "take", p1.pid!), { screen: "yours" });
  r.store.now = () => t0 + HELD_LONG_MS;
  r.jobs.screenAsked(pics.token, "take", p2.pid!);
  r.jobs.screenAsked(pics.token, "take", p2.pid!);
  const said = r.told.filter((t) => t.includes("has held this machine's screen"));
  assert.equal(said.length, 1);
  assert.match(said[0]!, /stillfail-job show/);
});

/// A process of the test's for a command that asks for the screen (its shell, as `stillfail-job screen`'s): there until
/// the test ends, or kills it.
const processes: ChildProcess[] = [];
after(() => {
  for (const p of processes) p.kill("SIGKILL");
});
function aShell(): ChildProcess {
  const p = spawn("sh", ["-c", FOREVER], { stdio: "ignore" });
  processes.push(p);
  return p;
}
