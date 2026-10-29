// station_task's `dir` (jobs/dirsync.ts): a source session's directory mirrored on another station before each start,
// only what changed sent, over the real station transport (mesh/peer.ts, its 1 MiB messages) between endpoints
// connected in memory; then what a task brings back and the patch of what it changed.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, renameSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { type Clock, type Duration, Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { Cloud } from "../src/cloud/state.ts";
import { signalGroup } from "../src/ops/group.ts";
import { LOOK_MS } from "../src/jobs/admit.ts";
import { Jobs, type Machine, STOP_LOOK_MS } from "../src/jobs/jobs.ts";
import { blobId, listLocal } from "../src/jobs/dirsync.ts";
import { MIRROR_IDLE_MS, MIRROR_RECENT_MS, type PeerCall, Refused, Remote, hash, readJson, writeJson } from "../src/jobs/remote.ts";
import { DISK_LOW_BYTES } from "../src/ops/disk.ts";
import { PEER_ALPN, PEER_BYTES_ALPN, peerCall, servePeer } from "../src/mesh/peer.ts";
import { type Json, Store } from "../src/store/store.ts";
import { remoteTools } from "../src/tools/remote.ts";
import { memoryMesh } from "./memory-mesh.ts";

const dirs: string[] = [];
const cleanup: (() => Promise<void> | void)[] = [];
after(async () => {
  for (const c of cleanup.reverse()) await c();
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function tempdir(): string {
  const d = mkdtempSync(join(tmpdir(), "dirsync-test-"));
  dirs.push(d);
  return d;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/// Waits for what real I/O does (a process), looking every 5 ms. No deadline.
async function until(_what: string, check: () => boolean) {
  while (!check()) await sleep(5);
}

const FOREVER = "tail -f /dev/null";

function testClock() {
  const scope = Effect.runSync(Scope.make());
  cleanup.push(() => Effect.runPromise(Scope.close(scope, Exit.void)).catch(() => undefined));
  return Effect.runSync(Scope.provide(TestClock.make(), scope));
}

/// Moves `clock` on by `by` until `check` holds (no deadline).
async function rounds(clock: ReturnType<typeof testClock>, by: Duration.Input, check: () => boolean) {
  while (!check()) {
    await Effect.runPromise(clock.adjust(by));
    await sleep(1);
  }
}

const git = (dir: string, ...args: string[]) =>
  execFileSync("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "init.defaultBranch=main", "-c", "core.autocrlf=false", ...args], { encoding: "utf8" });

const cloudOf = (station: string, peers: string[]): any =>
  Object.assign(Object.create(Cloud.prototype), {
    state: { workspace: "ws", workspace_name: "ws", name: "", station, peers: peers.map((id) => ({ id })), revocations: [], joined: [] },
    lock: null,
    peersCurrent: true,
    relays: () => [],
  });

/// A machine with room for every task (jobs/admit.ts): its CPUs idle, its memory under no pressure.
const idle: Machine = (() => {
  let t = 0;
  return { cpus: () => 8, ticks: () => [0, (t += 1000)] as [number, number], pressure: async () => "normal" as const };
})();

/// A source station A and a target B of workspace "ws", A's requests to B over the station transport (in memory). `old`:
/// B answers as a station from before directory sync would. `asked`: the methods A asked B, in order. `queue`: B's jobs
/// on a clock of their own (`queueClock`) and an idle machine, where a test starts a task beside one running (its queue
/// waits for room on that clock, not on the machine the test runs on). `before`: both speak the transport of before
/// 2026-10-29 only, files and contents going in chunks of base64.
async function pair(options: { queue?: boolean; before?: boolean } = {}) {
  const clock = testClock();
  const queueClock = options.queue ? testClock() : undefined;
  const mesh = memoryMesh();
  const alpns = options.before ? [PEER_ALPN] : [PEER_BYTES_ALPN, PEER_ALPN];
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns, relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target] = await Promise.all([bind(), bind()]);
  cleanup.push(() => Promise.all([source.close(), target.close()]).then(() => undefined));
  /// What the target's disk has free (`disk.free`; plenty unless a test says otherwise).
  const disk = { free: () => 500 * 1024 ** 3 };
  const make = (dir: string, options: { clock?: Clock.Clock; diskFree?: (path: string) => number; jobsClock?: Clock.Clock; machine?: Machine } = {}) => {
    const store = Store.open(":memory:");
    const told: [string, string][] = [];
    const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null, clock: options.jobsClock, machine: options.machine });
    const remote = new Remote({ data: dir, store, jobs, clock: options.clock, diskFree: options.diskFree, notify: (session, text) => void told.push([session, text]) });
    cleanup.push(async () => {
      await remote.close();
      for (const job of store.listJobs(null)) if (job.pgid !== null) signalGroup(job.pgid, "SIGKILL");
      await jobs.shutdown();
      store.close();
    });
    return { dir, store, jobs, remote, told };
  };
  const a = make(tempdir(), { clock });
  const b = make(tempdir(), { diskFree: () => disk.free(), ...(queueClock ? { jobsClock: queueClock, machine: idle } : {}) });
  const B = target.id();
  mkdirSync(join(a.dir, "mesh"), { recursive: true });
  writeFileSync(join(a.dir, "mesh", "cloud.json"), JSON.stringify({ workspace: "ws", station: source.id() }));
  const home = join(a.dir, "work");
  mkdirSync(home);
  a.store.insertSession({ key: "s1", connect: "ds", runtime: "claude", profile: "cc", workspace: home, token: "t1", createdBy: "ann", createdAt: Date.now(), lastActiveAt: Date.now() });
  const targetCloud = cloudOf(B, [source.id()]);
  void (async () => {
    for (;;) {
      const conn = await target.accept();
      if (!conn) return;
      void servePeer(conn, targetCloud, b.remote).catch(() => {});
    }
  })();
  const port = target.sockets()[0]!.split(":").at(-1);
  const call = peerCall(source, cloudOf(source.id(), [B]), (id) => ({ id, ips: [`127.0.0.1:${port}`] }));
  // B tells A of its tasks (`task.changed`) over the transport the other way.
  const sourceCloud = cloudOf(source.id(), [B]);
  void (async () => {
    for (;;) {
      const conn = await source.accept();
      if (!conn) return;
      void servePeer(conn, sourceCloud, a.remote).catch(() => {});
    }
  })();
  const sourcePort = source.sockets()[0]!.split(":").at(-1);
  b.remote.attach(peerCall(target, targetCloud, (id) => ({ id, ips: [`127.0.0.1:${sourcePort}`] })));
  /// `hold`: the methods held before they are asked, until `release`d. `bulk`/`most`: the bulk requests (contents,
  /// files' chunks) under way now, and the most there were at once.
  const state = { old: false, asked: [] as string[], hold: new Set<string>(), held: [] as (() => void)[], bulk: 0, most: 0 };
  const release = () => {
    state.hold.clear();
    for (const go of state.held.splice(0)) go();
  };
  const transport: PeerCall = async (to, workspace, request) => {
    if (to !== "") state.asked.push(request.method);
    if (state.hold.has(request.method)) await new Promise<void>((go) => state.held.push(go));
    if (/^(sync\.put|file\.put|file\.get)$/.test(request.method)) {
      state.most = Math.max(state.most, ++state.bulk);
      try {
        return await call(to, workspace, request);
      } finally {
        state.bulk--;
      }
    }
    if (state.old && request.method === "describe") {
      const { sync: _, ...before } = await call(to, workspace, request);
      return before;
    }
    if (state.old && /^(sync\.|task\.files$)/.test(request.method)) throw new Refused(`unsupported peer method: ${request.method}`);
    return call(to, workspace, request);
  };
  a.remote.attach(transport);
  const tools = remoteTools(a.remote);
  const use = async (name: string, args: Json) => JSON.parse(await tools.find((t) => t.name === name)!.run("s1", { station: B, ...args }));
  /// Prepares and starts `key` (running `command` in `dir`), and waits for its process to end.
  const run = async (key: string, dir: string, command: string, more: Json = {}) => {
    const prepared = await use("station_task", { key, action: "prepare", command, dir, ...more });
    const started = await use("station_task", { key, action: "start" });
    await until("it ends", () => b.store.getJob(started.job.id)!.state !== "running");
    return { prepared, started, sync: started.sync };
  };
  const mirror = (name: string) => join(b.remote.room("ws", source.id(), "s1"), "work", name);
  return { a, b, A: source.id(), B, home, clock, queueClock, use, run, mirror, state, release, disk };
}

const stamp = (path: string) => {
  const st = lstatSync(path);
  return [st.mtimeMs, st.ino, st.size];
};

describe("dirsync", { concurrency: true }, () => {
  test("a content's id is Git's blob id", () => {
    assert.equal(blobId(Buffer.from("hello\n")), "ce013625030ba8dba906f756967f9e9ca394464a");
    assert.equal(blobId(Buffer.alloc(0)), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391");
  });

  test("a Git directory sends what Git names; the next start only what changed, leaving the rest of the mirror alone", async () => {
    const p = await pair();
    const repo = join(p.home, "app");
    mkdirSync(join(repo, "src"), { recursive: true });
    writeFileSync(join(repo, ".gitignore"), "node_modules/\ndist/\n");
    writeFileSync(join(repo, "src", "a.txt"), "alpha\n");
    writeFileSync(join(repo, "src", "b.txt"), "beta\n");
    writeFileSync(join(repo, "run.sh"), "#!/bin/sh\necho run\n");
    chmodSync(join(repo, "run.sh"), 0o755);
    // Not compressible: it goes as it is.
    const big = randomBytes(3 * 1024 * 1024 + 17);
    writeFileSync(join(repo, "big.bin"), big);
    // Checked out with CRLF, LF in the index: its bytes are not what the index names.
    writeFileSync(join(repo, ".gitattributes"), "*.bat text eol=crlf\n");
    writeFileSync(join(repo, "w.bat"), "@echo off\r\necho hi\r\n");
    symlinkSync("src/a.txt", join(repo, "inside"));
    symlinkSync("/etc/hosts", join(repo, "outside"));
    git(repo, "init", "-q");
    git(repo, "add", "-A");
    git(repo, "commit", "-q", "-m", "first");
    writeFileSync(join(repo, "notes.txt"), "untracked\n");
    mkdirSync(join(repo, "node_modules", "dep"), { recursive: true });
    writeFileSync(join(repo, "node_modules", "dep", "index.js"), "ignored\n");
    mkdirSync(join(repo, "dist"));
    writeFileSync(join(repo, "dist", "out.js"), "ignored\n");

    // The command leaves build output of its own beside the synced files.
    const first = await p.run("k1", repo, "mkdir -p node_modules && echo warm > node_modules/keep.js && cat src/a.txt > made.txt");
    assert.equal(first.prepared.dir, "app");
    assert.equal(first.started.job.cwd, p.mirror("app"));
    assert.equal(p.b.store.getJob(first.started.job.id)!.exitCode, 0);
    const s1 = first.sync;
    assert.equal(s1.git, true);
    assert.equal(s1.files, 9, "tracked and untracked, not ignored, not the link leading out");
    assert.deepEqual(s1.skipped, [{ path: "outside", why: "symbolic link leading out of the directory" }]);
    assert.equal(s1.sent.files, 9);
    assert.equal(s1.written, 9);
    assert.equal(s1.sent.requests, 1, "all of it after one request");
    const m = p.mirror("app");
    assert.equal(readFileSync(join(m, "src", "a.txt"), "utf8"), "alpha\n");
    assert.equal(readFileSync(join(m, "notes.txt"), "utf8"), "untracked\n");
    assert.equal(readFileSync(join(m, "w.bat"), "utf8"), "@echo off\r\necho hi\r\n", "the bytes on disk");
    assert.ok(readFileSync(join(m, "big.bin")).equals(big));
    assert.ok(statSync(join(m, "run.sh")).mode & 0o100, "the exec bit");
    assert.equal(statSync(join(m, "src", "a.txt")).mode & 0o111, 0);
    assert.equal(readlinkSync(join(m, "inside")), "src/a.txt");
    for (const gone of ["outside", "dist", join("node_modules", "dep"), ".git"]) assert.ok(!existsSync(join(m, gone)), gone);
    assert.equal(readFileSync(join(m, "made.txt"), "utf8"), "alpha\n");

    const kept = Object.fromEntries(["big.bin", "run.sh", "w.bat", "notes.txt", join("node_modules", "keep.js"), "made.txt"].map((f) => [f, stamp(join(m, f))]));
    writeFileSync(join(repo, "src", "a.txt"), "alpha, again\n");
    rmSync(join(repo, "src", "b.txt"));
    writeFileSync(join(repo, "src", "c.txt"), "gamma\n");
    const second = await p.run("k2", repo, "cat src/a.txt src/c.txt > made2.txt");
    const s2 = second.sync;
    assert.deepEqual([s2.files, s2.sent.files, s2.sent.bytes, s2.written, s2.removed, s2.sent.requests], [9, 2, 19, 2, 1, 1]);
    assert.equal(readFileSync(join(m, "src", "a.txt"), "utf8"), "alpha, again\n");
    assert.ok(!existsSync(join(m, "src", "b.txt")));
    assert.equal(readFileSync(join(m, "made2.txt"), "utf8"), "alpha, again\ngamma\n");
    for (const [file, was] of Object.entries(kept)) assert.deepEqual(stamp(join(m, file)), was, `${file} untouched`);
    assert.equal(readFileSync(join(m, "node_modules", "keep.js"), "utf8"), "warm\n");

    // Nothing changed: nothing goes.
    const third = await p.run("k3", repo, "true");
    assert.deepEqual([third.sync.sent.files, third.sync.written, third.sync.removed, third.sync.sent.requests], [0, 0, 0, 0]);
    // A synced file a command changed is put back by the next sync (and only that one).
    const fourth = await p.run("k4", repo, "echo local > src/a.txt");
    assert.equal(fourth.sync.sent.files, 0);
    const fifth = await p.run("k5", repo, "true");
    assert.deepEqual([fifth.sync.sent.files, fifth.sync.written], [1, 1]);
    assert.equal(readFileSync(join(m, "src", "a.txt"), "utf8"), "alpha, again\n");
    // Starting a started key again syncs nothing and returns its job.
    const again = await p.use("station_task", { key: "k5", action: "start" });
    assert.equal(again.job.id, fifth.started.job.id);
    assert.equal(again.sync, undefined);
  });

  test("a directory outside Git: all its files but dependencies and build output", async () => {
    const p = await pair();
    const dir = join(tempdir(), "plain");
    mkdirSync(join(dir, "src", "node_modules", "x"), { recursive: true });
    mkdirSync(join(dir, "target", "debug"), { recursive: true });
    writeFileSync(join(dir, "src", "main.c"), "int main;\n");
    writeFileSync(join(dir, "src", "node_modules", "x", "i.js"), "no\n");
    writeFileSync(join(dir, "target", "debug", "app"), "no\n");
    writeFileSync(join(dir, "same-1"), "twins\n");
    writeFileSync(join(dir, "same-2"), "twins\n");
    const local = await listLocal(dir);
    assert.equal(local.git, false);
    assert.deepEqual(local.files.map((f) => f.path), ["same-1", "same-2", "src/main.c"]);
    const first = await p.run("p1", dir, "ls -R . > ../tree.txt");
    assert.deepEqual([first.sync.git, first.sync.files, first.sync.sent.files, first.sync.written], [false, 3, 2, 3], "one content sent once");
    const m = p.mirror("plain");
    assert.equal(readFileSync(join(m, "same-2"), "utf8"), "twins\n");
    assert.ok(!existsSync(join(m, "target")));
    assert.ok(!existsSync(join(m, "src", "node_modules")));
    // A rename on the source is a copy there, nothing sent.
    const before = stamp(join(m, "src", "main.c"));
    execFileSync("mv", [join(dir, "same-2"), join(dir, "renamed")]);
    const second = await p.run("p2", dir, "true");
    assert.deepEqual([second.sync.sent.files, second.sync.written, second.sync.removed], [0, 1, 1]);
    assert.equal(readFileSync(join(m, "renamed"), "utf8"), "twins\n");
    assert.deepEqual(stamp(join(m, "src", "main.c")), before);
  });

  test("a session's prepared tasks are kept in a directory of its own, one from before moved there; closing it removes them", async () => {
    const p = await pair();
    const dir = join(tempdir(), "kept");
    mkdirSync(dir);
    writeFileSync(join(dir, "a.txt"), "a\n");
    const prepared = join(p.a.dir, "remote", "prepared");
    const own = join(prepared, hash("s1"));
    await p.use("station_task", { key: "k1", action: "prepare", command: "true", dir });
    const [name] = readdirSync(own);
    assert.ok(name!.endsWith(".json"));
    // Kept as before: started from there until it is moved, then moved into the session's.
    renameSync(join(own, name!), join(prepared, name!));
    assert.equal((await p.use("station_task", { key: "k1", action: "start" })).sync.git, false);
    await p.a.remote["movePrepared"]();
    assert.deepEqual(readdirSync(prepared), [hash("s1")]);
    assert.deepEqual(readdirSync(own), [name]);
    p.a.remote.closeSession("s1");
    await until("its prepared tasks go", () => !existsSync(own));
  });

  test("one task at a time in a mirror: a sync while one runs there is refused, nothing started", async () => {
    const p = await pair({ queue: true });
    const queueClock = p.queueClock!;
    const dir = join(tempdir(), "busy");
    mkdirSync(dir);
    writeFileSync(join(dir, "f"), "1\n");
    await p.use("station_task", { key: "long", action: "prepare", command: FOREVER, dir });
    const long = await p.use("station_task", { key: "long", action: "start" });
    assert.equal(long.job.state, "running");
    await p.use("station_task", { key: "next", action: "prepare", command: "true", dir });
    writeFileSync(join(dir, "f"), "2\n");
    await assert.rejects(p.use("station_task", { key: "next", action: "start" }), /nothing was started: task long is running in busy/);
    assert.equal(readFileSync(join(p.mirror("busy"), "f"), "utf8"), "1\n", "the running task's files untouched");
    assert.deepEqual((await p.use("station_task", { key: "next", action: "get" })).job, null);
    // Another directory of the session is free meanwhile.
    const other = join(tempdir(), "other");
    mkdirSync(other);
    writeFileSync(join(other, "g"), "g\n");
    // (started beside the long one once the queue has room: on its clock, a look at a time)
    await p.use("station_task", { key: "free", action: "prepare", command: "cat g", dir: other });
    const free = await p.use("station_task", { key: "free", action: "start" });
    assert.equal(free.sync.sent.files, 1);
    await rounds(queueClock, `${LOOK_MS} millis`, () => p.b.store.getJob(free.job.id)!.state !== "running");
    // (its stop's grace looks on that clock too)
    let stopped = false;
    const stopping = p.use("station_task", { key: "long", action: "stop" }).finally(() => (stopped = true));
    await rounds(queueClock, `${STOP_LOOK_MS} millis`, () => stopped);
    await stopping;
    const next = await p.use("station_task", { key: "next", action: "start" });
    assert.equal(next.sync.sent.files, 1);
    assert.equal(readFileSync(join(p.mirror("busy"), "f"), "utf8"), "2\n");
  });

  test("to a station from before, contents and files go in chunks of base64, each within its transport's message", async () => {
    const p = await pair({ before: true });
    const dir = join(p.home, "old");
    mkdirSync(dir);
    // Not compressible: in several requests.
    const big = randomBytes(3 * 1024 * 1024 + 17);
    writeFileSync(join(dir, "big.bin"), big);
    const ran = await p.run("k1", dir, "cp big.bin out.bin");
    assert.ok(ran.sync.sent.requests >= 5, `in pieces: ${ran.sync.sent.requests}`);
    assert.ok(readFileSync(join(p.mirror("old"), "big.bin")).equals(big));
    const input = join(p.home, "input.bin");
    writeFileSync(input, big);
    await p.use("station_task", { key: "up", action: "prepare", command: "cp input.bin copy.bin" });
    const before = p.state.asked.length;
    assert.equal((await p.use("station_file", { key: "up", direction: "upload", local: input, path: "input.bin" })).bytes, big.length);
    assert.ok(p.state.asked.slice(before).filter((m) => m === "file.put").length >= 12, "256 KiB at a time");
    const started = await p.use("station_task", { key: "up", action: "start" });
    await until("it ends", () => p.b.store.getJob(started.job.id)!.state !== "running");
    await p.use("station_file", { key: "up", direction: "download", path: "copy.bin", local: "copy.bin" });
    assert.ok(readFileSync(join(p.home, "copy.bin")).equals(big));
    assert.ok(p.state.asked.filter((m) => m === "file.get").length >= 12, "256 KiB at a time");
  });

  test("a station's syncs send their contents one request at a time, side by side as they go", async () => {
    const p = await pair();
    const dirs = ["one", "two", "three"].map((name) => {
      const dir = join(tempdir(), name);
      mkdirSync(dir);
      // Random, so nothing packs small.
      for (let i = 0; i < 3; i++) writeFileSync(join(dir, `f${i}`), randomBytes(900 * 1024));
      return dir;
    });
    for (const [i, dir] of dirs.entries()) await p.use("station_task", { key: `k${i}`, action: "prepare", command: "cat f0 f1 f2 | wc -c", dir });
    const started = await Promise.all(dirs.map((_, i) => p.use("station_task", { key: `k${i}`, action: "start" })));
    for (const s of started) assert.equal(s.sync.sent.files, 3);
    assert.equal(p.state.asked.filter((m) => m === "sync.put").length, 3, "each directory's contents after one request");
    assert.equal(p.state.most, 1, "never two contents' requests under way at once");
    for (const s of started) await until("it ends", () => p.b.store.getJob(s.job.id)!.state !== "running");
    // A file uploaded meanwhile waits its turn the same way.
    const input = join(p.home, "input.bin");
    writeFileSync(input, randomBytes(700 * 1024));
    for (let i = 0; i < 3; i++) writeFileSync(join(dirs[0]!, `f${i}`), randomBytes(900 * 1024));
    await p.use("station_task", { key: "up", action: "prepare", command: "wc -c input.bin" });
    await p.use("station_task", { key: "k3", action: "prepare", command: "true", dir: dirs[0] });
    const [upload, synced] = await Promise.all([
      p.use("station_file", { key: "up", direction: "upload", local: input, path: "input.bin" }),
      p.use("station_task", { key: "k3", action: "start" }),
    ]);
    assert.equal(synced.sync.sent.files, 3);
    assert.equal(upload.bytes, 700 * 1024);
    assert.equal(p.state.most, 1);
  });

  test("a start whose sync outlasts its answer says so; asked again with the key it takes up that sync, not another", async () => {
    const p = await pair();
    const dir = join(tempdir(), "big");
    mkdirSync(dir);
    writeFileSync(join(dir, "f"), randomBytes(64 * 1024));
    await p.use("station_task", { key: "k", action: "prepare", command: "wc -c f", dir });
    p.state.hold.add("sync.put");
    const ask = () => {
      const answer = { value: null as Json };
      const asked = p.use("station_task", { key: "k", action: "start" }).then((v) => (answer.value = v));
      return { answer, asked };
    };
    // Its answer comes once SYNC_ANSWER_MS has gone by on the clock, whatever the sync does meanwhile.
    const first = ask();
    await until("the contents are sent", () => p.state.held.length === 1);
    await rounds(p.clock, "5 seconds", () => first.answer.value !== null);
    assert.equal(first.answer.value.syncing, true);
    assert.match(first.answer.value.note, /still being synced .*same key/);
    const again = ask();
    await rounds(p.clock, "5 seconds", () => again.answer.value !== null);
    assert.equal(again.answer.value.syncing, true);
    assert.equal(p.state.asked.filter((m) => m === "sync.begin").length, 1, "asked again: no other sync began");
    assert.equal(p.state.held.length, 1, "and nothing more was sent");
    // The sync ends while no start waits: the next start takes what it did and starts the task.
    p.release();
    await until("it is committed", () => p.state.asked.includes("sync.commit"));
    const last = await p.use("station_task", { key: "k", action: "start" });
    assert.equal(last.sync.sent.files, 1);
    assert.equal(last.job.state, "running");
    assert.equal(p.state.asked.filter((m) => m === "sync.begin").length, 1);
    await until("it ends", () => p.b.store.getJob(last.job.id)!.state !== "running");
    // A start after that is one asked again: the same job (its sync only finds the task started).
    const after = await p.use("station_task", { key: "k", action: "start" });
    assert.equal(after.job.id, last.job.id);
    assert.equal(p.state.asked.filter((m) => m === "sync.begin").length, 2);
  });

  test("a station from before directory sync is refused before anything runs there", async () => {
    const p = await pair();
    const dir = join(tempdir(), "repo");
    mkdirSync(dir);
    writeFileSync(join(dir, "f"), "1\n");
    p.state.old = true;
    await assert.rejects(p.use("station_task", { key: "k", action: "prepare", command: "make", dir }), /from before directory sync and would run the task without the files/);
    assert.ok(!p.state.asked.includes("task.prepare"));
    await assert.rejects(p.use("station_task", { key: "k", action: "prepare", command: "make", dir: "relative" }), /absolute path/);
    // One that changed under it after prepare: start refuses, nothing started.
    p.state.old = false;
    await p.use("station_task", { key: "k", action: "prepare", command: "make", dir });
    p.state.old = true;
    await assert.rejects(p.use("station_task", { key: "k", action: "start" }), /cannot sync directories .*nothing was started/);
    assert.ok(!p.state.asked.includes("task.start"));
    // And a target never starts a task with a directory that was not synced (a source that does not sync).
    p.state.old = false;
    await assert.rejects(p.b.remote.handle("ws", p.A, { method: "task.start", session: "s1", key: "k" }), /has not been synced/);
    // Tasks without a directory work as before.
    const plain = await p.use("station_task", { key: "plain", action: "prepare", command: "true" });
    assert.deepEqual(plain, { key: "plain", prepared: true });
  });

  test("what a task brings back comes into the session, and what it changed of its directory as a patch", async () => {
    const p = await pair();
    const repo = join(p.home, "proj");
    mkdirSync(join(repo, "src"), { recursive: true });
    writeFileSync(join(repo, "src", "a.txt"), "one\n");
    writeFileSync(join(repo, "src", "gone.txt"), "bye\n");
    git(repo, "init", "-q");
    git(repo, "add", "-A");
    git(repo, "commit", "-q", "-m", "first");
    const command = "mkdir -p out/sub && echo report > out/r.txt && printf 'bin' > out/sub/b.bin && echo two >> src/a.txt && rm src/gone.txt";
    const { started } = await p.run("k1", repo, command, { back: ["out", "missing.txt"] });
    assert.equal(p.b.store.getJob(started.job.id)!.exitCode, 0);
    await rounds(p.clock, "5 seconds", () => p.a.told.length > 0);
    const told = p.a.told[0]![1];
    const result = JSON.parse(told.slice(told.indexOf("{")));
    const back = join(p.home, "station-back", "k1");
    assert.deepEqual(result.back.files, { dir: back, count: 2, files: ["out/r.txt", "out/sub/b.bin"], missing: ["missing.txt: not there"] });
    assert.equal(readFileSync(join(back, "out", "r.txt"), "utf8"), "report\n");
    assert.equal(readFileSync(join(back, "out", "sub", "b.bin"), "utf8"), "bin");
    assert.deepEqual(result.back.changed.files, ["src/a.txt", "src/gone.txt"]);
    // Nothing here was changed; the patch applies.
    assert.equal(readFileSync(join(repo, "src", "a.txt"), "utf8"), "one\n");
    assert.equal(result.back.changed.patch, join(back, "changes.patch"));
    git(repo, "apply", "--check", result.back.changed.patch);
    git(repo, "apply", result.back.changed.patch);
    assert.equal(readFileSync(join(repo, "src", "a.txt"), "utf8"), "one\ntwo\n");
    assert.ok(!existsSync(join(repo, "src", "gone.txt")));
  });

  /// A directory of `files` (name → contents) under a new temporary one.
  const dirOf = (name: string, files: Record<string, string>) => {
    const dir = join(tempdir(), name);
    mkdirSync(dir);
    for (const [file, contents] of Object.entries(files)) writeFileSync(join(dir, file), contents);
    return dir;
  };
  /// Says when a mirror of the session was last used, as the target's record keeps it.
  const usedAt = (p: Awaited<ReturnType<typeof pair>>, at: Record<string, number>) => {
    const record = join(p.b.remote.room("ws", p.A, "s1"), "mirrors-used.json");
    writeJson(record, { ...readJson(record), ...at });
  };

  test("a mirror no task has used for a day goes with what its tasks made; the session's other files stay, the next start syncs it anew", async () => {
    const p = await pair();
    const old = dirOf("old", { "a.txt": "a\n", "b.txt": "b\n" });
    const fresh = dirOf("fresh", { "c.txt": "c\n" });
    await p.run("o1", old, "echo built > made.txt");
    await p.run("f1", fresh, "true");
    // Something a task made beside the mirrors, in the session's own directory.
    const own = join(p.b.remote.room("ws", p.A, "s1"), "work", "ember-src");
    mkdirSync(own);
    writeFileSync(join(own, "keep"), "x\n");
    const later = Date.now() + MIRROR_IDLE_MS + 60_000;
    usedAt(p, { fresh: later - 1000 });
    await p.b.remote.sweep(later);
    assert.ok(!existsSync(p.mirror("old")), "the unused mirror went");
    assert.ok(existsSync(join(p.mirror("fresh"), "c.txt")), "the one used within the day stays");
    assert.ok(existsSync(join(own, "keep")), "what is not a mirror stays");
    assert.ok(existsSync(p.b.remote.room("ws", p.A, "s1")), "the session's directory stays");
    // Started again, it is synced from nothing: every file goes.
    const again = await p.run("o2", old, "cat a.txt b.txt > both.txt; test ! -e made.txt");
    assert.equal(p.b.store.getJob(again.started.job.id)!.exitCode, 0);
    assert.deepEqual([again.sync.sent.files, again.sync.written], [2, 2]);
    assert.equal(readFileSync(join(p.mirror("old"), "both.txt"), "utf8"), "a\nb\n");
  });

  test("on a disk running low the longest unused mirrors go first, until there is enough free; one in use or used within the hour stays", async () => {
    const p = await pair();
    const names = ["oldest", "older", "recent", "busy"];
    const dirs = Object.fromEntries(names.map((name) => [name, dirOf(name, { "f.txt": `${name}\n` })]));
    // One after another: an ended task counts as a use, so these were used in this order.
    for (const name of names) await p.run(`${name}-1`, dirs[name]!, "true");
    await p.use("station_task", { key: "busy-2", action: "prepare", command: FOREVER, dir: dirs.busy });
    await p.use("station_task", { key: "busy-2", action: "start" });
    const now = Date.now() + 3 * MIRROR_RECENT_MS;
    const left = () => names.filter((n) => existsSync(p.mirror(n)));
    // Plenty free: nothing goes.
    await p.b.remote.relieve(now);
    assert.deepEqual(left(), names);
    // Low until the first has gone.
    p.disk.free = () => (existsSync(p.mirror("oldest")) ? DISK_LOW_BYTES - 1 : DISK_LOW_BYTES);
    await p.b.remote.relieve(now);
    assert.deepEqual(left(), ["older", "recent", "busy"], "the longest unused went, and only it");
    // Still low: the rest go, but the one used within the hour and the one a task runs in.
    usedAt(p, { recent: now - 60_000 });
    p.disk.free = () => DISK_LOW_BYTES - 1;
    await p.b.remote.relieve(now);
    assert.deepEqual(left(), ["recent", "busy"]);
    await p.use("station_task", { key: "busy-2", action: "stop" });
  });
});
