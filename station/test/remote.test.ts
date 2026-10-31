// the Rust station's remote.rs's tests ported (transfer paths, task_tests, session_tests, recovery_tests; same names, same
// checks), with the schedules on a TestClock; then two stations in one process, the source's tools reaching the target
// through a direct `call` that answers as the transport does.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { type Clock, type Duration, Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { signalGroup } from "../src/ops/group.ts";
import { Jobs, type Machine } from "../src/jobs/jobs.ts";
import { GIVE_UP_MS, IDLE_MS, type PeerCall, Refused, Remote, answerPeer, filePath, readJson, writeJson } from "../src/jobs/remote.ts";
import { type Load, OLDER } from "../src/jobs/load.ts";
import { type Json, Store } from "../src/store/store.ts";
import { remoteTools } from "../src/tools/remote.ts";
import { bytesOf, withBytes } from "../src/mesh/bus.ts";

const dirs: string[] = [];
const cleanup: (() => Promise<void> | void)[] = [];
after(async () => {
  for (const c of cleanup.reverse()) await c();
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function tempdir(): string {
  const d = mkdtempSync(join(tmpdir(), "remote-test-"));
  dirs.push(d);
  return d;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const turn = async () => {
  for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));
};

/// Waits for what real I/O does (a process, a peer's answer), looking every 5 ms. No deadline: it comes, however slow
/// the machine, or the test hangs.
async function until(_what: string, check: () => boolean) {
  while (!check()) await sleep(5);
}

/// A task's command that never ends by itself: running for as long as a test needs, however slow the machine.
const FOREVER = "tail -f /dev/null";

/// A TestClock, and how many sleeps were asked of it: a fiber asked for one is sleeping on it (an adjust reaches it).
function testClock() {
  const scope = Effect.runSync(Scope.make());
  cleanup.push(() => Effect.runPromise(Scope.close(scope, Exit.void)).catch(() => undefined));
  const test = Effect.runSync(Scope.provide(TestClock.make(), scope));
  let asked = 0;
  const clock: Clock.Clock & { adjust: typeof test.adjust; asked: () => number } = {
    ...test,
    sleep: (duration) =>
      Effect.suspend(() => {
        asked++;
        return test.sleep(duration);
      }),
    asked: () => asked,
  };
  return clock;
}

/// Moves `clock` on by `by` until `check` holds: a schedule's next round, whenever its fiber goes to sleep (no
/// deadline: what is checked for happens on rounds of the clock, however slow the machine).
async function rounds(_what: string, clock: ReturnType<typeof testClock>, by: Duration.Input, check: () => boolean) {
  while (!check()) {
    await Effect.runPromise(clock.adjust(by));
    await sleep(1);
  }
}

type Station = { dir: string; store: Store; jobs: Jobs; remote: Remote; told: [string, string][] };

function station(options: { clock?: Clock.Clock; jobsClock?: Clock.Clock; machine?: Machine; meshWaitMs?: number; dir?: string; store?: Store; jobs?: Jobs; notify?: (s: string, t: string) => void } = {}): Station {
  const dir = options.dir ?? tempdir();
  const store = options.store ?? Store.open(":memory:");
  const told: [string, string][] = [];
  const jobs = options.jobs ?? new Jobs({ store, data: dir, notify: () => {}, link: () => null, clock: options.jobsClock, machine: options.machine });
  const remote = new Remote({
    data: dir, store, jobs, clock: options.clock, meshWaitMs: options.meshWaitMs,
    notify: options.notify ?? ((session, text) => void told.push([session, text])),
  });
  cleanup.push(async () => {
    await remote.close();
    if (!options.jobs) {
      for (const job of store.listJobs(null)) if (job.pgid !== null) signalGroup(job.pgid, "SIGKILL");
      await jobs.shutdown();
    }
    if (!options.store) store.close();
  });
  return { dir, store, jobs, remote, told };
}

/// `request` as the other station takes it from the transport: its JSON, and the bytes after it.
const overWire = (request: Json) => {
  const taken = JSON.parse(JSON.stringify(request));
  const bytes = bytesOf(request);
  return bytes === null ? taken : withBytes(taken, bytes);
};
const b64 = (s: string) => Buffer.from(s).toString("base64");
const unb64 = (v: Json) => Buffer.from(v.data, "base64").toString();

// Each test has stations of its own (directories, stores, clocks): they run at once.
describe("remote", { concurrency: true }, () => {
  test("a request asked before the mesh is up waits for it; one it never comes up for is refused after the wait", async () => {
    // As a chat taken up as the station starts, on a subscription borrowed from another station.
    const s = station({ meshWaitMs: 2000 });
    const asked = s.remote.ask("b".repeat(64), { method: "share.lend", id: "sh-x" });
    await new Promise((r) => setTimeout(r, 100));
    const call: PeerCall = async (to, _workspace, request) => ({ to, method: request.method });
    s.remote.attach(call);
    assert.deepEqual(await asked, { to: "b".repeat(64), method: "share.lend" });
    const never = station({ meshWaitMs: 200 });
    const t0 = Date.now();
    await assert.rejects(never.remote.ask("b".repeat(64), {}), /station mesh is not ready/);
    assert.ok(Date.now() - t0 >= 180, "refused only after the wait");
  });

  test("transfer paths do not escape or follow links", () => {
    const dir = tempdir();
    for (const path of ["", "/etc/passwd", "../secret", "a/../../secret", "./a", "."]) {
      assert.throws(() => filePath(dir, path, true), Error, path);
    }
    symlinkSync("/tmp", join(dir, "link"));
    assert.throws(() => filePath(dir, "link/file", true));
    assert.throws(() => filePath(join(dir, "link"), "file", true));
    assert.ok(filePath(dir, "nested/file", true).startsWith(dir));
    assert.equal(filePath(dir, "a/./b", false), join(dir, "a", "b"), "a . inside is no component, as Path::components has it");
  });

  test("on Windows a backslash separates too, and a drive, a share or a stream is not relative", { skip: process.platform !== "win32" && "Windows only" }, () => {
    const dir = tempdir();
    for (const path of ["..\\outside.txt", "a\\..\\..\\secret", ".\\a", "C:\\Windows\\win.ini", "C:secret", "\\\\server\\share\\x", "\\x", "file:stream"]) {
      assert.throws(() => filePath(dir, path, true), Error, path);
    }
    assert.equal(filePath(dir, "nested\\file", false), join(dir, "nested", "file"));
  });

  // ── task_tests ──

  const call = (s: Station, peer: string, method: string, more: Json = {}) => s.remote.handle("ws", peer, { session: "s", key: "build-1", method, ...more });

  test("any workspace station may send a session a message and run tasks", async () => {
    const r = station();
    await assert.rejects(call(r, "peer-c", "session.message"), Error, "not taken before the hub is there");
    const got: [string, Json][] = [];
    r.remote.setInbox(async (peer, request) => {
      got.push([peer, request]);
      return { thread: "EMBER/1.1" };
    });
    const answer = await call(r, "peer-c", "session.message", { to: "k", text: "hi" });
    assert.equal(answer.thread, "EMBER/1.1");
    const [peer, request] = got.pop()!;
    assert.deepEqual([peer, request.to, request.text], ["peer-c", "k", "hi"]);
    for (const method of ["session.file", "session.put"]) {
      await call(r, "peer-c", method, { to: "k" });
      assert.equal(got.pop()![1].method, method, "a chat's files and a message's go where messages go");
    }
    assert.equal((await call(r, "peer-c", "describe")).messages, true);
    assert.equal((await call(r, "peer-c", "describe")).files, true);
    assert.equal((await call(r, "peer-c", "describe")).tasks, true, "any station of the workspace runs tasks");
    assert.deepEqual((await call(r, "peer-c", "task.list")).tasks, []);
  });

  test("tasks are owned, idempotent and return files", async () => {
    const r = station();
    const spec = { spec: { command: "cat input > output; echo ran >> count", name: "copy" } };
    await call(r, "peer-a", "task.prepare", spec);
    await call(r, "peer-a", "file.put", { path: "input", offset: 0, data: b64("hello"), final: true });
    const first = await call(r, "peer-a", "task.start");
    while ((await call(r, "peer-a", "task.get")).job.state === "running") await sleep(25);
    const again = await call(r, "peer-a", "task.start");
    assert.equal(first.job.id, again.job.id);
    assert.equal(again.job.exitCode, 0);
    for (const [path, expected] of [["output", "hello"], ["count", "ran\n"]]) {
      assert.equal(unb64(await call(r, "peer-a", "file.get", { path })), expected);
    }
    await assert.rejects(call(r, "peer-b", "task.get"));
    await call(r, "peer-c", "task.prepare", spec);
    assert.equal((await call(r, "peer-c", "task.get")).job, null, "another station's same key is a task of its own");
    await assert.rejects(call(r, "peer-a", "task.get", { session: "other" }));
    await assert.rejects(call(r, "peer-a", "task.prepare", { spec: { command: "echo wrong" } }));
    await assert.rejects(call(r, "peer-a", "file.put", { path: "input", offset: 0, data: "", final: true }));
  });

  test("removal from the workspace stops only that peer's task", async () => {
    const r = station();
    for (const peer of ["peer-a", "peer-b"]) {
      await call(r, peer, "task.prepare", { spec: { command: FOREVER } });
      await call(r, peer, "task.start");
    }
    await r.remote.revoke([{ workspace: "ws", peers: ["peer-b"] }], true);
    assert.equal((await call(r, "peer-a", "task.get")).job.state, "stopped");
    assert.equal((await call(r, "peer-b", "task.get")).job.state, "running");
    await call(r, "peer-b", "task.stop");
  });

  // ── session_tests ──

  const callAs = (s: Station, session: string, key: string, method: string, more: Json = {}) => s.remote.handle("ws", "peer-a", { session, key, method, ...more });

  test("a queued task tells the agent the measured capacity and the reason for its wait", async () => {
    const clock = testClock();
    let busy = 0;
    let total = 0;
    const machine: Machine = { cpus: () => 12, ticks: () => [busy += 55, total += 100], pressure: async () => "normal" };
    const r = station({ jobsClock: clock, machine });
    const capacity = { cpus: 12, cpuBusy: { share: 0.55, seconds: 60 }, memory: { totalBytes: 64 * 1024 ** 3, availableBytes: 45 * 1024 ** 3 }, checkedAt: 123 };
    let reads = 0;
    r.remote.setLoad(async () => { reads++; return capacity; });
    for (const key of ["first", "second", "third"]) {
      await callAs(r, "s", key, "task.prepare", { spec: { command: FOREVER } });
      const started = await callAs(r, "s", key, "task.start");
      if (key !== "first") {
        assert.equal(started.job.queued, true);
        assert.equal(started.queue.cause, "sampling");
        assert.deepEqual(started.queue.load, capacity);
      } else {
        assert.equal(reads, 0, "a task that starts at once does not wait on a host reading");
      }
    }
    const got = await callAs(r, "s", "second", "task.get");
    assert.equal(got.queue.cause, "sampling");
    assert.deepEqual(got.queue.load, capacity);
    assert.equal(got.queue.decision.cpuBusy, null, "the queue has not measured a whole window yet");
    const laterCapacity = { ...capacity, cpuBusy: { share: 0.25, seconds: 60 }, checkedAt: 456 };
    r.remote.setLoad(async () => laterCapacity);
    assert.deepEqual((await callAs(r, "s", "second", "task.get")).queue.load, laterCapacity, "a later request gets a new reading");
    r.remote.setLoad(async () => { reads++; return capacity; });
    reads = 0;
    const batch = await r.remote.handle("ws", "peer-a", { method: "task.gets", tasks: [{ session: "s", key: "second" }, { session: "s", key: "third" }] });
    assert.equal(reads, 1, "one capacity sample is shared by the whole batch");
    for (const task of batch.tasks) assert.deepEqual(task.result.queue.load, capacity);
    r.remote.setLoad(async () => { throw new Error("load unavailable"); });
    assert.deepEqual((await callAs(r, "s", "second", "task.get")).queue.load, { unavailable: "load unavailable" });
  });

  test("a slow capacity reading never holds up a queued task's reply", async () => {
    const clock = testClock();
    const jobsClock = testClock();
    const machine: Machine = { cpus: () => 12, ticks: () => [0, 0], pressure: async () => "normal" };
    const r = station({ clock, jobsClock, machine });
    r.remote.setLoad(() => new Promise(() => {}));
    await callAs(r, "s", "first", "task.prepare", { spec: { command: FOREVER } });
    await callAs(r, "s", "first", "task.start");
    await callAs(r, "s", "second", "task.prepare", { spec: { command: FOREVER } });
    const before = clock.asked();
    let answer: Json = null;
    void callAs(r, "s", "second", "task.start").then((got) => (answer = got));
    await until("the load timeout is armed", () => clock.asked() > before);
    await Effect.runPromise(clock.adjust("1 second"));
    await until("a queued task's reply", () => answer !== null);
    assert.equal(answer.job.queued, true);
    assert.deepEqual(answer.queue.load, { unavailable: "not measured within 1 s" });
  });

  test("a task that starts while its capacity is read is no longer reported queued", async () => {
    const clock = testClock();
    const jobsClock = testClock();
    let busy = 0;
    let total = 0;
    const machine: Machine = { cpus: () => 12, ticks: () => [busy += 20, total += 100], pressure: async () => "normal" };
    const r = station({ clock, jobsClock, machine });
    let read = false;
    let release!: (load: Json) => void;
    r.remote.setLoad(() => { read = true; return new Promise((resolve) => { release = resolve; }); });
    await callAs(r, "s", "first", "task.prepare", { spec: { command: FOREVER } });
    await callAs(r, "s", "first", "task.start");
    await callAs(r, "s", "second", "task.prepare", { spec: { name: "second", command: FOREVER } });
    const starting = callAs(r, "s", "second", "task.start");
    await until("the capacity is being read", () => read);
    await rounds("the second task starts", jobsClock, "5 seconds", () => r.store.listJobs(null).some((j) => j.name === "second" && j.queued !== true));
    release({ checkedAt: 123 });
    const answer = await starting;
    assert.notEqual(answer.job.queued, true);
    assert.equal(answer.queue, undefined);
  });

  async function run(s: Station, session: string, key: string, command: string): Promise<Json> {
    await callAs(s, session, key, "task.prepare", { spec: { command } });
    await callAs(s, session, key, "task.start");
    // A real process: looked at every 25 ms (no deadline).
    for (;;) {
      const got = await callAs(s, session, key, "task.get");
      if (got.job.state !== "running") return got;
      await sleep(25);
    }
  }

  test("a session's tasks share one directory that closing removes", async () => {
    const r = station();
    await run(r, "s", "clone", "mkdir repo && echo built > repo/out");
    assert.equal((await run(r, "s", "build", "cat repo/out > copy")).job.exitCode, 0);
    assert.equal(unb64(await callAs(r, "s", "build", "file.get", { path: "copy" })), "built\n");
    // Another session starts empty and is left alone when the first closes.
    assert.notEqual((await run(r, "t", "look", "test -e repo")).job.exitCode, 0);
    await callAs(r, "s", "long", "task.prepare", { spec: { command: FOREVER } });
    const long = await callAs(r, "s", "long", "task.start");
    await r.remote.handle("ws", "peer-a", { method: "session.close", session: "s" });
    assert.ok(!existsSync(r.remote.room("ws", "peer-a", "s")));
    assert.equal(r.store.getJob(long.job.id)!.state, "stopped");
    await assert.rejects(callAs(r, "s", "build", "task.get"), Error, "records go with the directory");
    assert.ok(existsSync(join(r.remote.room("ws", "peer-a", "t"), "work")));
    // Closing again (a retried request) is fine.
    await r.remote.handle("ws", "peer-a", { method: "session.close", session: "s" });
  });

  test("one chat's slow request holds up no other chat's, nor what only reads", async () => {
    // Every request of every chat was answered in one line: on a loaded station a task's state, asked by one chat,
    // waited behind another chat's sync past its caller's 30 s (2026-10-21, Studio for ccvm).
    const r = station();
    let release!: () => void;
    const released = new Promise<void>((resolve) => (release = resolve));
    const stop = r.jobs.stop.bind(r.jobs);
    r.jobs.stop = async (id: string) => {
      await released;
      return stop(id);
    };
    await callAs(r, "s", "long", "task.prepare", { spec: { command: FOREVER } });
    await callAs(r, "s", "long", "task.start");
    const stopping = callAs(r, "s", "long", "task.stop");
    let next = false;
    const queued = callAs(r, "s", "next", "task.prepare", { spec: { command: "true" } }).then(() => (next = true));
    assert.equal((await callAs(r, "s", "long", "task.get")).job.state, "running", "what only reads is answered at once");
    const both = await r.remote.handle("ws", "peer-a", { method: "task.gets", tasks: [{ session: "s", key: "long" }, { session: "s", key: "none" }] });
    assert.equal(both.tasks[0].result.job.state, "running");
    assert.deepEqual([both.tasks[1].key, both.tasks[1].error], ["none", "unknown task"]);
    assert.deepEqual(await callAs(r, "t", "other", "task.prepare", { spec: { command: "true" } }), { key: "other", prepared: true }, "another chat's is answered meanwhile");
    assert.equal(next, false, "the same chat's next one waits its turn");
    release();
    await stopping;
    await queued;
    assert.equal((await callAs(r, "s", "long", "task.get")).job.state, "stopped");
  });

  test("the target removes idle session and old task directories itself", async () => {
    const r = station();
    await run(r, "idle", "a", "touch made");
    await run(r, "recent", "a", "touch made");
    const old = join(r.remote.root, "incoming", "from-before");
    mkdirSync(join(old, "work"), { recursive: true });
    writeJson(join(old, "task.json"), { spec: { command: "true" }, workspace: "ws", station: "peer-a", session: "x", key: "k" });
    const later = Date.now() + IDLE_MS + 1000;
    const record = join(r.remote.room("ws", "peer-a", "recent"), "session.json");
    const seen = readJson(record);
    seen.seen = later;
    writeJson(record, seen);
    await r.remote.sweep(later);
    assert.ok(!existsSync(r.remote.room("ws", "peer-a", "idle")));
    assert.ok(existsSync(r.remote.room("ws", "peer-a", "recent")));
    assert.ok(!existsSync(old));
  });

  test("closing a source session asks each used station until answered", async () => {
    const clock = testClock();
    const r = station({ clock });
    mkdirSync(join(r.dir, "mesh"), { recursive: true });
    r.remote.recordUse("ws", "s", "up");
    r.remote.recordUse("ws", "s", "old");
    r.remote.recordUse("ws", "s", "down");
    r.remote.recordUse("ws", "other", "up");
    const asked: string[] = [];
    let down = 0;
    r.remote.attach(async (station, _workspace, request) => {
      assert.equal(request.method, "session.close");
      assert.equal(request.session, "s");
      asked.push(station);
      const n = station === "down" ? down++ : 0;
      if (station === "old") throw new Refused("unsupported peer method: session.close");
      if (station === "down" && n < 2) throw new Error("offline");
      return { closed: true };
    });
    r.remote.closeSession("s");
    const path = r.remote.usedPath("s");
    // Every station answered, as many rounds as it takes.
    await rounds("every station answered", clock, "1 second", () => !existsSync(path));
    assert.equal(asked.filter((s) => s === "up").length, 1);
    assert.equal(asked.filter((s) => s === "old").length, 1);
    assert.equal(asked.filter((s) => s === "down").length, 3);
    assert.ok(existsSync(r.remote.usedPath("other")));
  });

  // ── recovery_tests ──

  test("a persisted receipt reconnects and delivers to its original session", async () => {
    const clock = testClock();
    const first = station();
    const path = first.remote.outgoing("ws", "original-session", "target", "stable-key");
    writeJson(path, { workspace: "ws", session: "original-session", station: "target", key: "stable-key", delivered: false });
    await first.remote.close();
    const messages: [string, string][] = [];
    const restarted = station({ clock, dir: first.dir, store: first.store, jobs: first.jobs, notify: (s, t) => void messages.push([s, t]) });
    let attempts = 0;
    restarted.remote.attach(async (station, _workspace, request) => {
      const n = attempts++;
      assert.equal(station, "target");
      assert.equal(request.workspace, "ws");
      assert.equal(request.method, "task.gets", "recovery queries; it does not resubmit the command");
      assert.deepEqual(request.tasks, [{ session: "original-session", key: "stable-key" }]);
      if (n < 2) throw new Error("offline");
      return { tasks: [{ session: "original-session", key: "stable-key", result: { job: { state: "exited", exitCode: 0 }, log: "done", notices: [] } }] };
    });
    await rounds("delivered", clock, "1 second", () => readJson(path).delivered === true);
    assert.equal(attempts, 3);
    assert.equal(messages.length, 1);
    assert.equal(messages[0][0], "original-session");
    assert.ok(messages[0][1].includes("done"));
    assert.equal(readJson(path).delivered, true);
  });

  // ── two stations ──

  /// A source station "A" and a target "B" in one workspace; each one's calls reach the other as the transport would
  /// carry them (errors come back as Refused). `reach`: whether B's calls get through to A. `roster`: the stations the
  /// workspace has, as the cloud names them.
  function pair(roster: Json[] = [{ id: "A" }, { id: "B" }]) {
    const clock = testClock();
    const a = station({ clock });
    const b = station({ clock });
    mkdirSync(join(a.dir, "mesh"), { recursive: true });
    writeFileSync(join(a.dir, "mesh", "cloud.json"), JSON.stringify({ workspace: "ws", station: "A" }));
    const home = join(a.dir, "work");
    mkdirSync(home);
    a.store.insertSession({ key: "s1", connect: "ds", runtime: "claude", profile: "cc", workspace: home, token: "t1", createdBy: "ann", createdAt: Date.now(), lastActiveAt: Date.now() });
    const asked: Json[] = [];
    const transport: PeerCall = async (target, workspace, request) => {
      asked.push(request);
      if (target === "" && request.method === "peers") return { workspace: "ws", stations: roster, current: true };
      if (target !== "B") throw new Error("peer is not another station in this workspace");
      const answer = await answerPeer(b.remote, workspace ?? "ws", "A", overWire(request));
      if ("error" in answer) throw new Refused(answer.error);
      return answer.result;
    };
    a.remote.attach(transport);
    const back = { reach: true, told: [] as Json[] };
    b.remote.attach(async (target, workspace, request) => {
      if (target !== "A") throw new Error("peer is not another station in this workspace");
      if (!back.reach) throw new Error("not reached");
      back.told.push(request);
      const answer = await answerPeer(a.remote, workspace ?? "ws", "B", overWire(request));
      if ("error" in answer) throw new Refused(answer.error);
      return answer.result;
    });
    const tools = remoteTools(a.remote);
    const use = async (name: string, args: Json) => JSON.parse(await tools.find((t) => t.name === name)!.run("s1", args));
    return { a, b, home, clock, use, asked, back };
  }

  test("a session runs a task on another station: inputs up, its notices and end told here, its artifact down", async () => {
    const { a, b, home, clock, use } = pair();
    // Neither measures its load here: both say they cannot tell.
    assert.deepEqual((await use("station_list", {})).stations, [{ id: "A", here: true, load: OLDER }, { id: "B", load: OLDER }]);
    const described = await use("station_list", { station: "B" });
    assert.equal(described.tasks, true);
    assert.equal(described.fileChunkBytes, 256 * 1024);
    // An input bigger than one chunk goes up in pieces.
    const input = "abc\n".repeat(100_000);
    writeFileSync(join(home, "input.txt"), input);
    // It waits at a gate (a fifo) until its notice has been told, so that comes before its end.
    const gate = join(tempdir(), "gate");
    execFileSync("mkfifo", [gate]);
    const command = `cat '${gate}' >/dev/null; tr a-z A-Z < input.txt > out.txt`;
    assert.deepEqual(await use("station_task", { station: "B", key: "k1", action: "prepare", command, name: "upper" }), { key: "k1", prepared: true });
    const up = await use("station_file", { station: "B", key: "k1", direction: "upload", path: "input.txt", local: join(home, "input.txt") });
    assert.deepEqual(up, { uploaded: join(home, "input.txt"), bytes: input.length });
    const started = await use("station_task", { station: "B", key: "k1", action: "start" });
    assert.equal(started.job.state, "running");
    const job = b.store.getJob(started.job.id)!;
    assert.equal(job.sessionKey, "remote:ws:A:s1");
    // Its spec says who asked for it.
    const listed = await use("station_task", { station: "B", action: "list" });
    assert.deepEqual(listed.tasks[0].spec, { name: "upper", command, requestedBy: "ann" });
    // What it says on the way reaches the session that started it, once: B tells A, which asks then.
    b.jobs.notified(job.token, "half way");
    await until("its notice is told", () => a.told.length > 0);
    assert.equal(a.told.length, 1);
    assert.equal(a.told[0][0], "s1");
    assert.ok(a.told[0][1].startsWith("Remote task k1 on B: {") && a.told[0][1].includes("half way"), a.told[0][1]);
    await writeFile(gate, "go");
    await until("its end is told", () => a.told.length > 1);
    assert.equal(a.told.length, 2);
    assert.ok(a.told[1][1].includes('"state":"exited"'), a.told[1][1]);
    // Delivered: not told again.
    await Effect.runPromise(clock.adjust("30 seconds"));
    await turn();
    assert.equal(a.told.length, 2);
    const down = await use("station_file", { station: "B", key: "k1", direction: "download", path: "out.txt", local: "out.txt" });
    assert.deepEqual(down, { downloaded: join(home, "out.txt"), bytes: input.length });
    assert.equal(readFileSync(join(home, "out.txt"), "utf8"), input.toUpperCase());
    await assert.rejects(use("station_file", { station: "B", key: "k1", direction: "download", path: "out.txt", local: "out.txt" }), /already exists/);
    await assert.rejects(use("station_file", { station: "B", key: "k1", direction: "download", path: "out.txt", local: "/elsewhere/out.txt" }), /inside this session workspace/);
    // The chat closed: the target's directory for it goes.
    const room = b.remote.room("ws", "A", "s1");
    assert.ok(existsSync(room));
    const asleep = clock.asked();
    a.remote.closeSession("s1");
    await until("its directory goes", () => !existsSync(room));
    // Every station answered: the record goes at the next round.
    await until("the first round is over", () => clock.asked() > asleep);
    assert.ok(existsSync(a.remote.usedPath("s1")));
    await Effect.runPromise(clock.adjust("60 seconds"));
    await until("the record goes", () => !existsSync(a.remote.usedPath("s1")));
  });

  /// A station's load as one that measures it says it.
  const loadOf = (busy: number, turns: number): Load => ({
    os: "macOS 15.6", arch: "arm64", cpus: 12, cpuModel: "Apple M2 Max", cpuBusy: { share: busy, seconds: 60 }, loadAvg: [1.5, 2, 2.5],
    memory: { totalBytes: 64 * 1024 ** 3, availableBytes: 40 * 1024 ** 3 }, disk: { path: "/data", totalBytes: 1000 * 1024 ** 3, freeBytes: 200 * 1024 ** 3 },
    gpus: [{ name: "Apple M2 Max", cores: 30 }], running: { remoteTasks: 1, jobs: 2, services: 0, turns }, relay: { home: "https://r.example", ping: { relay: "https://r.example", ms: 12 } },
    checkedAt: 0,
  });

  test("station_list asks every station at once: a slow or offline one never holds up the list, an older one's load is unknown", async () => {
    const clock = testClock();
    const a = station({ clock });
    mkdirSync(join(a.dir, "mesh"), { recursive: true });
    writeFileSync(join(a.dir, "mesh", "cloud.json"), JSON.stringify({ workspace: "ws", station: "A" }));
    a.store.insertSession({ key: "s1", connect: "ds", runtime: "claude", profile: "cc", workspace: a.dir, token: "t1", createdBy: "ann", createdAt: Date.now(), lastActiveAt: Date.now() });
    a.remote.setLoad(async () => loadOf(0.05, 1));
    // B measures its load; D is from before (its describe says none); C never answers; E cannot be reached; F refuses.
    const b = station();
    b.remote.setLoad(async () => loadOf(0.9, 0));
    const d = station();
    let settled = 0;
    const transport: PeerCall = async (target, workspace, request) => {
      if (target === "" && request.method === "peers") return { workspace: "ws", stations: ["A", "B", "C", "D", "E", "F"].map((id) => ({ id, name: id.toLowerCase() })), current: true };
      if (target === "C") return new Promise(() => {});
      try {
        if (target === "E") throw new Error("peer unavailable or does not support station RPC: no route");
        if (target === "F") throw new Refused("station is starting");
        const answer = await answerPeer(target === "B" ? b.remote : d.remote, workspace ?? "ws", "A", request);
        if ("error" in answer) throw new Refused(answer.error);
        return answer.result;
      } finally {
        settled++;
      }
    };
    a.remote.attach(transport);
    const tools = remoteTools(a.remote);
    const use = async (name: string, args: Json) => JSON.parse(await tools.find((t) => t.name === name)!.run("s1", args));
    let listed: Json = null;
    void use("station_list", {}).then((l) => (listed = l));
    // All but C have answered (and what they said is taken: a turn of the event loop): C alone is waited for, two
    // seconds of the clock and no more.
    await until("B, D, E and F answered", () => settled === 4);
    await turn();
    assert.equal(listed, null);
    await rounds("the list is out", clock, "500 millis", () => listed !== null);
    const busy = (share: string, turns: string) =>
      `arm64 macOS 15.6, 12 cores (Apple M2 Max), GPU 30 cores; CPU ${share} busy over the last 60 s, load 1.5 / 2 / 2.5 (1 / 5 / 15 min); memory 40 GiB of 64 GiB free, disk 200 GiB of 1000 GiB free; running 1 remote task, 2 jobs, 0 services, ${turns}; relay ping 12 ms`;
    assert.deepEqual(listed, {
      workspace: "ws",
      current: true,
      stations: [
        { id: "A", name: "a", here: true, load: busy("5%", "1 agent turn") },
        { id: "B", name: "b", load: busy("90%", "0 agent turns") },
        { id: "C", name: "c", offline: "did not answer within 2 s" },
        { id: "D", name: "d", load: OLDER },
        { id: "E", name: "e", offline: "peer unavailable or does not support station RPC: no route" },
        { id: "F", name: "f", refused: "station is starting" },
      ],
    });
    // One in detail: all it said, its load in full and in a line; an older one's load unknown; this one itself.
    const one = await use("station_list", { station: "B" });
    assert.equal(one.tasks, true);
    assert.deepEqual(one.load, loadOf(0.9, 0));
    assert.equal(one.summary, busy("90%", "0 agent turns"));
    const older = await use("station_list", { station: "D" });
    assert.equal(older.load, OLDER);
    assert.equal(older.sync, 1);
    assert.deepEqual((await use("station_list", { station: "A" })).load, loadOf(0.05, 1));
  });

  test("a station that cannot measure its load within a second says so, and answers describe all the same", async () => {
    const clock = testClock();
    const s = station({ clock });
    s.remote.setLoad(() => new Promise(() => {}));
    let answer: Json = null;
    void answerPeer(s.remote, "ws", "A", { method: "describe" }).then((a) => (answer = a));
    await rounds("it answers", clock, "250 millis", () => answer !== null);
    assert.equal(answer.result.tasks, true);
    assert.deepEqual(answer.result.load, { unavailable: "not measured within 1 s" });
    s.remote.setLoad(async () => {
      throw new Error("no readers");
    });
    assert.deepEqual((await answerPeer(s.remote, "ws", "A", { method: "describe" })).result.load, { unavailable: "no readers" });
  });

  test("a start the target refuses is final, and asked for again only by a new start", async () => {
    const { a, use, asked, clock } = pair();
    await assert.rejects(use("station_task", { station: "B", key: "k", action: "start" }), (e: Error) => e instanceof Refused && /unknown task/.test(e.message));
    const record = readJson(a.remote.outgoing("ws", "s1", "B", "k"));
    assert.deepEqual([record.delivered, record.refused], [true, true]);
    const before = asked.length;
    await Effect.runPromise(clock.adjust("1 minute"));
    await turn();
    assert.equal(asked.filter((r) => r.method === "task.get").length, asked.slice(0, before).filter((r) => r.method === "task.get").length, "not followed");
    await assert.rejects(use("station_task", { station: "B", key: "", action: "get" }), /station and key are required/);
    await assert.rejects(use("station_task", { station: "B", key: "k", action: "run" }), /unknown task action/);
  });

  test("a station is named by its id or by the name station_list shows it by", async () => {
    const { a, b, use } = pair([{ id: "A", name: "Studio" }, { id: "B", name: "Mini1" }, { id: "C", name: "MBA" }, { id: "D", name: "mba" }]);
    assert.deepEqual(await use("station_task", { station: "mini1", key: "k", action: "prepare", command: "true" }), { key: "k", prepared: true });
    const started = await use("station_task", { station: "Mini1", key: "k", action: "start" });
    assert.equal(b.store.getJob(started.job.id)!.sessionKey, "remote:ws:A:s1");
    assert.ok(existsSync(a.remote.outgoing("ws", "s1", "B", "k")), "kept under its id, as one started by id is");
    assert.equal((await use("station_task", { station: "B", key: "k", action: "get" })).key, "k");
    await assert.rejects(use("station_task", { station: "MBA", key: "k", action: "get" }), /2 stations are named MBA/);
    await assert.rejects(use("station_task", { station: "Nowhere", key: "k", action: "get" }), /peer is not another station/);
  });

  test("a task's station tells of it: nothing asks about it while nothing happens to it", async () => {
    const { a, b, use, asked, clock } = pair();
    const started = await use("station_task", { station: "B", key: "k", action: "prepare", command: FOREVER });
    assert.equal(started.prepared, true);
    const job = (await use("station_task", { station: "B", key: "k", action: "start" })).job;
    assert.equal(job.state, "running");
    const before = asked.length;
    await Effect.runPromise(clock.adjust("10 minutes"));
    await turn();
    assert.deepEqual(asked.slice(before), [], "not asked about");
    await b.jobs.stop(job.id);
    await until("its end is told", () => a.told.length === 1);
    assert.ok(a.told[0][1].includes('"state":"stopped"'), a.told[0][1]);
    assert.deepEqual(asked.slice(before).map((r) => r.method), ["task.gets"], "asked once, after it was told");
    assert.equal(readJson(a.remote.outgoing("ws", "s1", "B", "k")).delivered, true);
  });

  test("a change the source was not reached for is told again until it is, and after the target restarts", async () => {
    const { a, b, use, clock, back } = pair();
    await use("station_task", { station: "B", key: "k", action: "prepare", command: FOREVER });
    const job = (await use("station_task", { station: "B", key: "k", action: "start" })).job;
    back.reach = false;
    b.jobs.notified(b.store.getJob(job.id)!.token, "one");
    await rounds("told again until reached", clock, "1 second", () => {
      back.reach = clock.asked() > 3;
      return a.told.length === 1;
    });
    assert.ok(a.told[0][1].includes("one"));
    // B stops before it tells A of its next change; started again, it tells A what A missed.
    back.reach = false;
    b.jobs.notified(b.store.getJob(job.id)!.token, "two");
    await b.remote.close();
    back.reach = true;
    const again = station({ clock, dir: b.dir, store: b.store, jobs: b.jobs });
    again.remote.attach(async (_target, workspace, request) => {
      const answer = await answerPeer(a.remote, workspace ?? "ws", "B", overWire(request));
      if ("error" in answer) throw new Refused(answer.error);
      return answer.result;
    });
    await until("what it missed is told", () => a.told.length === 2);
    assert.ok(a.told[1][1].includes("two"));
  });

  test("the tasks followed on a station from before task.changed are asked about in one request", async () => {
    const clock = testClock();
    const s = station({ clock });
    for (const key of ["k1", "k2", "k3"]) writeJson(s.remote.outgoing("ws", "s1", "old", key), { workspace: "ws", session: "s1", station: "old", key, delivered: false });
    const asked: Json[] = [];
    s.remote.attach(async (_station, _workspace, request) => {
      asked.push(request);
      return { tasks: request.tasks.map((t: Json) => ({ ...t, result: { key: t.key, job: { state: "running" }, log: "", notices: [] } })) };
    });
    const all = (r: Json) => r.method === "task.gets" && r.tasks.length === 3;
    await rounds("rounds asking about all three", clock, "5 seconds", () => asked.filter(all).length >= 3);
    assert.deepEqual(asked.find(all)!.tasks.map((t: Json) => t.key).sort(), ["k1", "k2", "k3"]);
    assert.ok(asked.every(all), "none on its own");
  });

  test("a station from before task.gets is asked about each task on its own", async () => {
    const clock = testClock();
    const s = station({ clock });
    const paths = ["k1", "k2"].map((key) => {
      const path = s.remote.outgoing("ws", "s1", "old", key);
      writeJson(path, { workspace: "ws", session: "s1", station: "old", key, delivered: false });
      return path;
    });
    const methods: string[] = [];
    s.remote.attach(async (_station, _workspace, request) => {
      methods.push(request.method);
      // What a station from before answers a request it does not know.
      if (request.method === "task.gets") throw new Refused("session and task key are required (at most 256 / 128 bytes)");
      return { job: { state: "exited", exitCode: 0 }, log: request.key, notices: [] };
    });
    await rounds("both told", clock, "5 seconds", () => paths.every((p) => readJson(p).delivered === true));
    assert.deepEqual(methods.sort(), ["task.get", "task.get", "task.gets"]);
    assert.deepEqual(s.told.map(([session]) => session), ["s1", "s1"]);
  });

  test("a task its station does not know, or never started, is told and no longer followed after a while", async () => {
    // Followed for good every 5 s: an agent whose prepare or start did not get through goes on with another key, and
    // ccvm followed 90 such tasks on Studio (2026-10-21).
    const clock = testClock();
    const store = Store.open(":memory:", null, clock);
    cleanup.push(() => store.close());
    const s = station({ clock, store });
    const record = (key: string) => {
      const path = s.remote.outgoing("ws", "s1", "B", key);
      writeJson(path, { workspace: "ws", session: "s1", station: "B", key, delivered: false });
      return path;
    };
    const [unknown, unstarted, running] = [record("unknown"), record("unstarted"), record("running")];
    s.remote.attach(async (_station, _workspace, request) => ({
      tasks: request.tasks.map((t: Json) =>
        t.key === "unknown" ? { ...t, error: "unknown task" }
        : t.key === "unstarted" ? { ...t, result: { key: t.key, job: null, log: null, notices: [] } }
        : { ...t, result: { key: t.key, job: { state: "running" }, log: "", notices: [] } }),
    }));
    await rounds("followed a while", clock, "1 minute", () => store.now() - readJson(unknown).since >= GIVE_UP_MS - 60_000);
    assert.equal(s.told.length, 0, "not before");
    await rounds("both given up", clock, "1 minute", () => s.told.length === 2);
    assert.deepEqual(s.told.map(([, text]) => text.split(":")[0]).sort(), ["Remote task unknown on B", "Remote task unstarted on B"]);
    assert.ok(s.told.some(([, text]) => text.includes("does not know it")));
    assert.ok(s.told.some(([, text]) => text.includes("never started")));
    for (const path of [unknown, unstarted]) assert.deepEqual([readJson(path).delivered, readJson(path).lost], [true, true]);
    assert.equal(readJson(running).delivered, false, "a running one is followed on");
  });
});
