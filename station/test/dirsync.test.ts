// station_task's `dir` (jobs/dirsync.ts): a source session's directory mirrored on another station before each start,
// only what changed sent, over the real station transport (mesh/peer.ts, its 1 MiB messages) between endpoints
// connected in memory; then what a task brings back and the patch of what it changed.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import { type Clock, type Duration, Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { Cloud } from "../src/cloud/state.ts";
import { signalGroup } from "../src/jobs/group.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { blobId, listLocal } from "../src/jobs/dirsync.ts";
import { type PeerCall, Refused, Remote } from "../src/jobs/remote.ts";
import { PEER_ALPN, peerCall, servePeer } from "../src/mesh/peer.ts";
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

/// A source station A and a target B of workspace "ws", A's requests to B over the station transport (in memory). `old`:
/// B answers as a station from before directory sync would. `asked`: the methods A asked B, in order.
async function pair() {
  const clock = testClock();
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [source, target] = await Promise.all([bind(), bind()]);
  cleanup.push(() => Promise.all([source.close(), target.close()]).then(() => undefined));
  const make = (dir: string, options: { clock?: Clock.Clock } = {}) => {
    const store = Store.open(":memory:");
    const told: [string, string][] = [];
    const jobs = new Jobs({ store, data: dir, notify: () => {}, link: () => null });
    const remote = new Remote({ data: dir, store, jobs, clock: options.clock, notify: (session, text) => void told.push([session, text]) });
    cleanup.push(async () => {
      await remote.close();
      for (const job of store.listJobs(null)) if (job.pgid !== null) signalGroup(job.pgid, "SIGKILL");
      await jobs.shutdown();
      store.close();
    });
    return { dir, store, jobs, remote, told };
  };
  const a = make(tempdir(), { clock });
  const b = make(tempdir());
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
  const state = { old: false, asked: [] as string[] };
  const transport: PeerCall = async (to, workspace, request) => {
    if (to !== "") state.asked.push(request.method);
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
  return { a, b, A: source.id(), B, home, clock, use, run, mirror, state };
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
    // Not compressible, more than a request holds: in several.
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
    assert.ok(s1.sent.requests >= 7, `the big file in pieces, each request within the transport's message: ${s1.sent.requests}`);
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

  test("one task at a time in a mirror: a sync while one runs there is refused, nothing started", async () => {
    const p = await pair();
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
    assert.equal((await p.run("free", other, "cat g")).sync.sent.files, 1);
    await p.use("station_task", { key: "long", action: "stop" });
    const next = await p.use("station_task", { key: "next", action: "start" });
    assert.equal(next.sync.sent.files, 1);
    assert.equal(readFileSync(join(p.mirror("busy"), "f"), "utf8"), "2\n");
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
});
