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
import { signalGroup } from "../src/jobs/group.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { IDLE_MS, type PeerCall, Refused, Remote, answerPeer, filePath, readJson, writeJson } from "../src/jobs/remote.ts";
import { type Json, Store, nowMs } from "../src/store/store.ts";
import { remoteTools } from "../src/tools/remote.ts";

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

/// Waits for what real I/O does (a process, a peer's answer), `ms` at most.
async function until(what: string, check: () => boolean, ms = 5000) {
  const end = Date.now() + ms;
  while (!check()) {
    if (Date.now() > end) assert.fail(`never: ${what}`);
    await sleep(5);
  }
}

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

/// Moves `clock` on by `by` until `check` holds: a schedule's next round, whenever its fiber goes to sleep.
async function rounds(what: string, clock: ReturnType<typeof testClock>, by: Duration.Input, check: () => boolean) {
  const end = Date.now() + 5000;
  while (!check()) {
    if (Date.now() > end) assert.fail(`never: ${what}`);
    await Effect.runPromise(clock.adjust(by));
    await sleep(1);
  }
}

type Station = { dir: string; store: Store; jobs: Jobs; remote: Remote; told: [string, string][] };

function station(allow: string[], options: { clock?: Clock.Clock; dir?: string; store?: Store; jobs?: Jobs; notify?: (s: string, t: string) => void } = {}): Station {
  const dir = options.dir ?? tempdir();
  const store = options.store ?? Store.open(":memory:");
  const told: [string, string][] = [];
  const jobs = options.jobs ?? new Jobs({ store, data: dir, notify: () => {}, link: () => null });
  const config = { remoteTasks: { allow } };
  const remote = new Remote({
    data: dir, store, jobs, config: () => config, clock: options.clock,
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

const b64 = (s: string) => Buffer.from(s).toString("base64");
const unb64 = (v: Json) => Buffer.from(v.data, "base64").toString();

// Each test has stations of its own (directories, stores, clocks): they run at once.
describe("remote", { concurrency: true }, () => {
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

  // ── task_tests ──

  const call = (s: Station, peer: string, method: string, more: Json = {}) => s.remote.handle("ws", peer, { session: "s", key: "build-1", method, ...more });

  test("any workspace station may send a session a message, trusted for tasks or not", async () => {
    const r = station(["peer-a", "peer-b"]);
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
    assert.equal((await call(r, "peer-c", "describe")).messages, true);
    await assert.rejects(call(r, "peer-c", "task.list"), Error, "tasks still need remoteTasks.allow");
  });

  test("tasks are owned, idempotent and return files", async () => {
    const r = station(["peer-a", "peer-b"]);
    const spec = { spec: { command: "cat input > output; echo ran >> count", name: "copy" } };
    await call(r, "peer-a", "task.prepare", spec);
    await call(r, "peer-a", "file.put", { path: "input", offset: 0, data: b64("hello"), final: true });
    const first = await call(r, "peer-a", "task.start");
    for (let i = 0; i < 200; i++) {
      if ((await call(r, "peer-a", "task.get")).job.state !== "running") break;
      await sleep(25);
    }
    const again = await call(r, "peer-a", "task.start");
    assert.equal(first.job.id, again.job.id);
    assert.equal(again.job.exitCode, 0);
    for (const [path, expected] of [["output", "hello"], ["count", "ran\n"]]) {
      assert.equal(unb64(await call(r, "peer-a", "file.get", { path })), expected);
    }
    await assert.rejects(call(r, "peer-b", "task.get"));
    await assert.rejects(call(r, "peer-c", "task.prepare", spec));
    await assert.rejects(call(r, "peer-a", "task.get", { session: "other" }));
    await assert.rejects(call(r, "peer-a", "task.prepare", { spec: { command: "echo wrong" } }));
    await assert.rejects(call(r, "peer-a", "file.put", { path: "input", offset: 0, data: "", final: true }));
  });

  test("withdrawal stops only the revoked peer's task", async () => {
    const r = station(["peer-a", "peer-b"]);
    for (const peer of ["peer-a", "peer-b"]) {
      await call(r, peer, "task.prepare", { spec: { command: "sleep 30" } });
      await call(r, peer, "task.start");
    }
    await r.remote.revoke("ws", ["peer-b"], true);
    assert.equal((await call(r, "peer-a", "task.get")).job.state, "stopped");
    assert.equal((await call(r, "peer-b", "task.get")).job.state, "running");
    await call(r, "peer-b", "task.stop");
  });

  // ── session_tests ──

  const callAs = (s: Station, session: string, key: string, method: string, more: Json = {}) => s.remote.handle("ws", "peer-a", { session, key, method, ...more });

  async function run(s: Station, session: string, key: string, command: string): Promise<Json> {
    await callAs(s, session, key, "task.prepare", { spec: { command } });
    await callAs(s, session, key, "task.start");
    for (let i = 0; i < 200; i++) {
      const got = await callAs(s, session, key, "task.get");
      if (got.job.state !== "running") return got;
      await sleep(25);
    }
    assert.fail("task did not finish");
  }

  test("a session's tasks share one directory that closing removes", async () => {
    const r = station(["peer-a"]);
    await run(r, "s", "clone", "mkdir repo && echo built > repo/out");
    assert.equal((await run(r, "s", "build", "cat repo/out > copy")).job.exitCode, 0);
    assert.equal(unb64(await callAs(r, "s", "build", "file.get", { path: "copy" })), "built\n");
    // Another session starts empty and is left alone when the first closes.
    assert.notEqual((await run(r, "t", "look", "test -e repo")).job.exitCode, 0);
    await callAs(r, "s", "long", "task.prepare", { spec: { command: "sleep 30" } });
    const long = await callAs(r, "s", "long", "task.start");
    await r.remote.handle("ws", "peer-a", { method: "session.close", session: "s" });
    assert.ok(!existsSync(r.remote.room("ws", "peer-a", "s")));
    assert.equal(r.store.getJob(long.job.id)!.state, "stopped");
    await assert.rejects(callAs(r, "s", "build", "task.get"), Error, "records go with the directory");
    assert.ok(existsSync(join(r.remote.room("ws", "peer-a", "t"), "work")));
    // Closing again (a retried request) is fine.
    await r.remote.handle("ws", "peer-a", { method: "session.close", session: "s" });
  });

  test("the target removes idle session and old task directories itself", async () => {
    const r = station(["peer-a"]);
    await run(r, "idle", "a", "touch made");
    await run(r, "recent", "a", "touch made");
    const old = join(r.remote.root, "incoming", "from-before");
    mkdirSync(join(old, "work"), { recursive: true });
    writeJson(join(old, "task.json"), { spec: { command: "true" }, workspace: "ws", station: "peer-a", session: "x", key: "k" });
    const later = nowMs() + IDLE_MS + 1000;
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
    const r = station(["peer-a"], { clock });
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
    for (let i = 0; i < 300; i++) {
      await Effect.runPromise(clock.adjust("1 second"));
      await turn();
      if (!existsSync(path)) break;
    }
    assert.ok(!existsSync(path), "every station answered");
    assert.equal(asked.filter((s) => s === "up").length, 1);
    assert.equal(asked.filter((s) => s === "old").length, 1);
    assert.equal(asked.filter((s) => s === "down").length, 3);
    assert.ok(existsSync(r.remote.usedPath("other")));
  });

  // ── recovery_tests ──

  test("a persisted receipt reconnects and delivers to its original session", async () => {
    const clock = testClock();
    const first = station([]);
    const path = first.remote.outgoing("ws", "original-session", "target", "stable-key");
    writeJson(path, { workspace: "ws", session: "original-session", station: "target", key: "stable-key", delivered: false });
    await first.remote.close();
    const messages: [string, string][] = [];
    const restarted = station([], { clock, dir: first.dir, store: first.store, jobs: first.jobs, notify: (s, t) => void messages.push([s, t]) });
    let attempts = 0;
    restarted.remote.attach(async (station, _workspace, request) => {
      const n = attempts++;
      assert.equal(station, "target");
      assert.equal(request.workspace, "ws");
      assert.equal(request.session, "original-session");
      assert.equal(request.key, "stable-key");
      assert.equal(request.method, "task.get", "recovery queries; it does not resubmit the command");
      if (n < 2) throw new Error("offline");
      return { job: { state: "exited", exitCode: 0 }, log: "done", notices: [] };
    });
    for (let i = 0; i < 20; i++) {
      await Effect.runPromise(clock.adjust("1 second"));
      await turn();
      if (readJson(path).delivered === true) break;
    }
    assert.equal(attempts, 3);
    assert.equal(messages.length, 1);
    assert.equal(messages[0][0], "original-session");
    assert.ok(messages[0][1].includes("done"));
    assert.equal(readJson(path).delivered, true);
  });

  // ── two stations ──

  /// A source station "A" and a target "B" that trusts it, in one workspace; A's calls reach B as the transport would
  /// carry them (B's errors come back as Refused).
  function pair(allow = ["A"]) {
    const clock = testClock();
    const a = station([], { clock });
    const b = station(allow);
    mkdirSync(join(a.dir, "mesh"), { recursive: true });
    writeFileSync(join(a.dir, "mesh", "cloud.json"), JSON.stringify({ workspace: "ws", station: "A" }));
    const home = join(a.dir, "work");
    mkdirSync(home);
    a.store.insertSession({ key: "s1", connect: "ds", runtime: "claude", profile: "cc", workspace: home, token: "t1", createdBy: "ann", createdAt: nowMs(), lastActiveAt: nowMs() });
    const asked: Json[] = [];
    const transport: PeerCall = async (target, workspace, request) => {
      asked.push(request);
      if (target === "" && request.method === "peers") return { workspace: "ws", stations: [{ id: "A" }, { id: "B" }], current: true };
      if (target !== "B") throw new Error("peer is not another station in this workspace");
      const answer = await answerPeer(b.remote, workspace ?? "ws", "A", JSON.parse(JSON.stringify(request)));
      if ("error" in answer) throw new Refused(answer.error);
      return answer.result;
    };
    a.remote.attach(transport);
    const tools = remoteTools(a.remote);
    const use = async (name: string, args: Json) => JSON.parse(await tools.find((t) => t.name === name)!.run("s1", args));
    return { a, b, home, clock, use, asked };
  }

  test("a session runs a task on another station: inputs up, its notices and end told here, its artifact down", async () => {
    const { a, b, home, clock, use } = pair();
    assert.deepEqual((await use("station_list", {})).stations, [{ id: "A" }, { id: "B" }]);
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
    // What it says on the way reaches the session that started it, once (as many rounds as it takes).
    b.jobs.notified(job.token, "half way");
    await rounds("its notice is told", clock, "5 seconds", () => a.told.length > 0);
    assert.equal(a.told.length, 1);
    assert.equal(a.told[0][0], "s1");
    assert.ok(a.told[0][1].startsWith("Remote task k1 on B: {") && a.told[0][1].includes("half way"), a.told[0][1]);
    await writeFile(gate, "go");
    await until("it ends", () => b.store.getJob(job.id)!.state !== "running");
    await rounds("its end is told", clock, "5 seconds", () => a.told.length > 1);
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
    await turn();
    assert.ok(!existsSync(a.remote.usedPath("s1")));
  });

  test("a start the target refuses is final, and asked for again only by a new start", async () => {
    const { a, use, asked, clock } = pair([]);
    await assert.rejects(use("station_task", { station: "B", key: "k", action: "start" }), (e: Error) => e instanceof Refused && /remoteTasks.allow/.test(e.message));
    const record = readJson(a.remote.outgoing("ws", "s1", "B", "k"));
    assert.deepEqual([record.delivered, record.refused], [true, true]);
    const before = asked.length;
    await Effect.runPromise(clock.adjust("1 minute"));
    await turn();
    assert.equal(asked.filter((r) => r.method === "task.get").length, asked.slice(0, before).filter((r) => r.method === "task.get").length, "not followed");
    await assert.rejects(use("station_task", { station: "B", key: "", action: "get" }), /station and key are required/);
    await assert.rejects(use("station_task", { station: "B", key: "k", action: "run" }), /unknown task action/);
  });
});
