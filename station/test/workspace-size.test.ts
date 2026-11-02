import assert from "node:assert/strict";
import { linkSync, lstatSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import { CHECK_MS, DEFAULT_LIMIT, GIB, REMIND_MS, WorkspaceReader, WorkspaceWatch, type WorkspaceReading } from "../src/jobs/workspace-size.ts";
import type { Remote } from "../src/jobs/remote.ts";
import { workspaceSizeTools } from "../src/tools/workspace-size.ts";
import { measuredUpTo } from "../src/sessions/footprint.ts";

const dirs: string[] = [];
const scopes: Scope.Closeable[] = [];
const watches: WorkspaceWatch[] = [];
after(async () => {
  for (const watch of watches) await watch.close();
  for (const scope of scopes) await Effect.runPromise(Scope.close(scope, Exit.void));
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
});

function rig() {
  const data = mkdtempSync(join(tmpdir(), "workspace-size-"));
  dirs.push(data);
  const scope = Effect.runSync(Scope.make());
  scopes.push(scope);
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  const state = { working: true, readings: [] as WorkspaceReading[] };
  const told: [string, string][] = [];
  const make = () => {
    const watch = new WorkspaceWatch({ data, clock, readings: async () => state.readings, working: () => state.working, notify: (s, text) => void told.push([s, text]) });
    watches.push(watch);
    return watch;
  };
  return { clock, state, told, make };
}

test("a working chat is warned above its limit, reminded hourly, and warned anew after it cleans up", async () => {
  const r = rig();
  const watch = r.make();
  const reading: WorkspaceReading = { session: "s1", station: "", name: "here", path: "/chat/workspace", bytes: 11 * GIB, complete: true };
  r.state.readings = [reading];
  await watch.look();
  assert.equal(watch.limit("s1", ""), DEFAULT_LIMIT);
  assert.equal(r.told.length, 1);
  assert.equal(r.told[0]![0], "s1");
  assert.match(r.told[0]![1], /11\.0 GiB.*10 GiB.*workspace_limit/s);
  await Effect.runPromise(r.clock.adjust(REMIND_MS - 1));
  await watch.look();
  assert.equal(r.told.length, 1);
  await Effect.runPromise(r.clock.adjust(1));
  await watch.look();
  assert.equal(r.told.length, 2, "still above the limit, remind it");
  reading.bytes = 9 * GIB;
  reading.complete = false;
  await watch.look();
  reading.bytes = 11 * GIB;
  await watch.look();
  assert.equal(r.told.length, 2, "a partial walk cannot prove the workspace was cleaned");
  reading.bytes = 9 * GIB;
  reading.complete = true;
  await watch.look();
  reading.bytes = 11 * GIB;
  await watch.look();
  assert.equal(r.told.length, 3, "after cleanup, crossing the limit is a new event");
  r.state.working = false;
  await Effect.runPromise(r.clock.adjust(REMIND_MS));
  await watch.look();
  assert.equal(r.told.length, 3, "a finished chat is not woken repeatedly");
});

test("limits and reminder state belong to the chat and station, and survive a restart", async () => {
  const r = rig();
  const first = r.make();
  r.state.readings = [
    { session: "s1", station: "", name: "here", path: "/local", bytes: 11 * GIB, complete: true },
    { session: "s1", station: "studio-id", name: "Studio", path: "/remote", bytes: 12 * GIB, complete: true },
    { session: "s2", station: "studio-id", name: "Studio", path: "/other", bytes: 12 * GIB, complete: true },
  ];
  first.setLimit("s1", "studio-id", 20);
  await first.look();
  assert.deepEqual(r.told.map(([session]) => session), ["s1", "s2"]);
  const next = r.make();
  assert.equal(next.limit("s1", "studio-id"), 20 * GIB);
  assert.equal(next.limit("s1", ""), DEFAULT_LIMIT);
  assert.equal(next.limit("s2", "studio-id"), DEFAULT_LIMIT);
  await next.look();
  assert.equal(r.told.length, 2, "a restart does not repeat the last notice immediately");
  r.state.readings[1]!.bytes = 21 * GIB;
  r.state.readings[1]!.complete = false;
  await next.look();
  assert.equal(r.told.length, 3);
  assert.match(r.told[2]![1], /Studio.*at least 21\.0 GiB.*20 GiB.*station: "studio-id"/s);
});

test("a limit raised while a notice is being delivered is kept", async () => {
  const r = rig();
  let began!: () => void;
  let finish!: () => void;
  const started = new Promise<void>((resolve) => { began = resolve; });
  const delivered = new Promise<void>((resolve) => { finish = resolve; });
  const watch = new WorkspaceWatch({
    data: dirs.at(-1)!, clock: r.clock,
    readings: async () => [{ session: "s1", station: "", name: "here", path: "/work", bytes: 11 * GIB, complete: true }],
    working: () => true,
    notify: async () => { began(); await delivered; },
  });
  watches.push(watch);
  const looking = watch.look();
  await started;
  watch.setLimit("s1", "", 20);
  finish();
  await looking;
  assert.equal(watch.limit("s1", ""), 20 * GIB);
  assert.equal(r.make().limit("s1", ""), 20 * GIB, "the newer limit survives a restart");
});

test("one undeliverable notice does not prevent other chats being warned", async () => {
  const r = rig();
  const reading = (session: string): WorkspaceReading => ({ session, station: "", name: "here", path: "/work", bytes: 11 * GIB, complete: true });
  const watch = new WorkspaceWatch({
    data: dirs.at(-1)!, clock: r.clock,
    readings: async () => [reading("s1"), reading("s2")],
    working: () => true,
    notify: (session) => { if (session === "s1") throw new Error("unavailable"); r.told.push([session, "warned"]); },
  });
  watches.push(watch);
  await watch.look();
  assert.deepEqual(r.told, [["s2", "warned"]]);
});

test("the background watch keeps checking an over-limit working chat", async () => {
  const r = rig();
  let checks = 0;
  const watch = new WorkspaceWatch({
    data: dirs.at(-1)!, clock: r.clock,
    readings: async () => { checks++; return [{ session: "s1", station: "", name: "here", path: "/work", bytes: 11 * GIB, complete: true }]; },
    working: () => true,
    notify: (session, text) => void r.told.push([session, text]),
  });
  watches.push(watch);
  const until = async (n: number) => {
    while (checks < n) await new Promise((resolve) => setImmediate(resolve));
    await new Promise((resolve) => setImmediate(resolve));
  };
  watch.start();
  await Effect.runPromise(r.clock.adjust("1 minute"));
  await until(1);
  assert.equal(r.told.length, 1);
  for (let n = 2; n <= 13; n++) {
    await Effect.runPromise(r.clock.adjust(CHECK_MS));
    await until(n);
  }
  assert.equal(r.told.length, 2, "the live schedule repeats after an hour");
});

test("the limit tool uses its caller's chat and validates the new limit", async () => {
  const r = rig();
  const watch = r.make();
  const remote = { workspaceStation: async (_session: string, named: string) => named === "Studio" ? "studio-id" : "" } as Remote;
  const [tool] = workspaceSizeTools(watch, remote);
  await tool!.run("s1", { station: "Studio", limit_gib: 25 });
  assert.equal(watch.limit("s1", "studio-id"), 25 * GIB);
  assert.equal(watch.limit("s2", "studio-id"), DEFAULT_LIMIT);
  await assert.rejects(tool!.run("s1", { limit_gib: 0 }), /positive whole/);
  await assert.rejects(tool!.run("s1", { limit_gib: 1.5 }), /positive whole/);
  await assert.rejects(tool!.run("s1", { limit_gib: "20" }), /positive whole/);
});

test("disk walks are shared, asynchronous, refreshed, and limited to one at a time", async () => {
  let now = 0;
  const started: string[] = [];
  const finish: ((size: { bytes: number; complete: boolean }) => void)[] = [];
  const reader = new WorkspaceReader(() => now, async (path) => {
    started.push(path);
    return new Promise<{ bytes: number; complete: boolean }>((resolve) => finish.push(resolve));
  });
  assert.equal(reader.size("a", 2), null);
  assert.equal(reader.size("a", 2), null);
  assert.equal(reader.size("b", 2), null);
  assert.deepEqual(started, ["a"]);
  finish.shift()!({ bytes: 3, complete: false });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(started, ["a", "b"]);
  assert.deepEqual(reader.size("a", 2), { bytes: 3, complete: false });
  finish.shift()!({ bytes: 4, complete: true });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(reader.size("b", 2), { bytes: 4, complete: true });
  assert.equal(reader.size("a", 4), null, "a higher limit needs more of an incomplete walk");
  finish.shift()!({ bytes: 5, complete: true });
  await new Promise((resolve) => setImmediate(resolve));
  now += CHECK_MS;
  assert.equal(reader.size("a", 2), null, "a stale value cannot falsely warn after cleanup");
  assert.deepEqual(started, ["a", "b", "a", "a"]);
  reader.close();
  finish.shift()!({ bytes: 2, complete: true });
});

test("a size walk stops once over the limit, and counts hard links once without following symlinks", async () => {
  const root = mkdtempSync(join(tmpdir(), "workspace-walk-"));
  dirs.push(root);
  const work = join(root, "work");
  mkdirSync(work);
  const file = join(work, "file");
  writeFileSync(file, Buffer.alloc(128 * 1024, 1));
  linkSync(file, join(work, "hard-link"));
  const outside = join(root, "outside");
  writeFileSync(outside, Buffer.alloc(1024 * 1024, 1));
  const link = join(work, "link");
  symlinkSync(outside, link);
  const expected = [work, file, link].reduce((total, p) => total + lstatSync(p).blocks * 512, 0);
  assert.deepEqual(await measuredUpTo(work, Number.MAX_SAFE_INTEGER), { bytes: expected, complete: true });
  const short = await measuredUpTo(work, 1);
  assert.equal(short.complete, false);
  assert.ok(short.bytes > 1 && short.bytes <= expected);
});
