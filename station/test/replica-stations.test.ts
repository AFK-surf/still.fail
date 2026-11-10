// A workspace's stations keeping each other's copies (replica/copies.ts, peers.ts, places.ts), over a mesh of the test's
// (a request's JSON and the bytes after it, as the station transport carries them; a station away fails it) and on the
// test's clock: a lost station's chats come back complete in a new one, from the stations that keep them; one away a
// month catches up; the stations that keep a copy change without fewer than two holding it; a
// workspace's copies stay with its stations; a station rolled back loses nothing they hold.
import assert from "node:assert/strict";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { afterEach, test } from "node:test";
import { Effect, Exit, Scope, type Clock } from "effect";
import { TestClock } from "effect/testing";
import { PeerBus, bytesOf, withBytes } from "../src/mesh/bus.ts";
import { Fibers } from "../src/ops/fibers.ts";
import { Copies, keptDir } from "../src/replica/copies.ts";
import { keepers } from "../src/replica/peers.ts";
import { FolderPlace } from "../src/replica/places.ts";
import { readCopy, takeBack } from "../src/replica/restore.ts";
import { InlineRunner } from "../src/replica/runner.ts";
import { Store } from "../src/store/store.ts";
import { HOME, OTHER, chat, dataDir, rowsOf, station } from "./replica-fakes.ts";

type Json = any;
const scopes: Scope.Closeable[] = [];
const closing: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const c of closing.splice(0).reverse()) await c().catch(() => {});
  for (const s of scopes.splice(0)) await Effect.runPromise(Scope.close(s, Exit.void));
});

function testClock(): Clock.Clock & { move: (ms: number) => Promise<void> } {
  const scope = Effect.runSync(Scope.make());
  scopes.push(scope);
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  return Object.assign(clock, { move: (ms: number) => Effect.runPromise(clock.adjust(`${ms} millis`)) });
}

/// What crosses the mesh: its JSON as a copy, the bytes after it as they are.
function across(v: Json): Json {
  const bytes = bytesOf(v);
  const copy = JSON.parse(JSON.stringify(v));
  return bytes === null ? copy : withBytes(copy, bytes);
}

type Node = { id: string; data: string; store: Store; copies: Copies; up: boolean; workspaces: string[]; bus: PeerBus };

/// A workspace's stations on the test's mesh, each in the workspaces it says; its roster is `roster` as it is now.
class Mesh {
  readonly nodes = new Map<string, Node>();
  readonly rosters = new Map<string, string[]>();
  readonly clock = testClock();
  asks = 0;
  /// The requests each station was asked, by method (and kind, for `replica.put`).
  readonly asked = new Map<string, Map<string, number>>();

  add(id: string, workspaces: string[], made?: { data: string; store: Store }): Node {
    const data = made?.data ?? dataDir(id.slice(0, 4));
    const store = made?.store ?? Store.open(join(data, "stillfail.db"), join(data, "archive"));
    const bus = new PeerBus({ sleep: async () => {} });
    const fibers = new Fibers("copies", this.clock);
    const node = { id, data, store, up: true, workspaces, bus } as Node;
    bus.attach(async (to, ws, request) => {
      this.asks++;
      let m = this.asked.get(to);
      if (m === undefined) this.asked.set(to, (m = new Map()));
      const what = request?.method === "replica.put" ? `put:${request.kind}` : String(request?.method);
      m.set(what, (m.get(what) ?? 0) + 1);
      const there = this.nodes.get(to);
      if (there === undefined || !there.up || !node.up) throw new Error("station unreachable");
      if (ws !== null && (!there.workspaces.includes(ws) || !(this.rosters.get(ws) ?? []).includes(id))) throw new Error("peer is not another station in this workspace");
      return across(await there.bus.handle(ws ?? "", id, across(request)));
    });
    const runner = new InlineRunner({ db: join(data, "stillfail.db"), replica: join(data, "replica"), dataDir: data, origin: id, now: () => this.clock.currentTimeMillisUnsafe() });
    node.copies = new Copies({
      data,
      here: () => id,
      places: () => ({ home: node.workspaces[0] ?? null, workspaces: node.workspaces.map((w) => ({ workspace: w, name: `${id.slice(0, 4)} in ${w}` })) }),
      roster: (ws) => (this.rosters.get(ws) ?? []).map((s) => ({ id: s, name: s.slice(0, 4) })),
      ask: (s, r) => bus.ask(s, r),
      runner,
      fibers,
      changed: () => {},
      restart: async () => null,
    });
    (node as Json).runner = runner;
    bus.on("replica.", node.copies.answers());
    store.subscribe((c) => node.copies.told(c));
    this.nodes.set(id, node);
    closing.push(async () => {
      await node.copies.close();
      await runner.close();
      await fibers.close();
      try { store.close(); } catch {}
    });
    return node;
  }

  /// Every station's export and places brought to rest.
  async settle(): Promise<void> {
    for (let i = 0; i < 3; i++) for (const n of this.nodes.values()) if (n.up) await n.copies.settle();
  }
}

const id = (c: string) => c.repeat(64);

/// The stations that hold `origin`'s copy in `ws` (a head there), of `among`.
function holders(mesh: Mesh, ws: string, origin: string): string[] {
  return [...mesh.nodes.values()].filter((n) => existsSync(join(keptDir(n.data), ws, origin)) && readdirSync(join(keptDir(n.data), ws, origin)).some((g) => existsSync(join(keptDir(n.data), ws, origin, g, "head.json")))).map((n) => n.id);
}

/// `node` started again after its restore was brought: what it brought put in before its store opens.
function startAgain(node: Node): DatabaseSync {
  node.store.close();
  const ready = takeBack(node.data, join(node.data, "stillfail.db"), 0);
  assert.ok(ready !== null, "a restore was waiting");
  return new DatabaseSync(join(node.data, "stillfail.db"));
}

/// Every row that must survive of `ws`'s chats on `before` equals what `after` holds now, paths moved.
function same(before: DatabaseSync, beforeData: string, after: DatabaseSync, afterData: string, ws: string | null) {
  const want = rowsOf(before, ws, beforeData, afterData);
  const got = rowsOf(after, ws);
  for (const table of Object.keys(want)) assert.deepEqual([...got[table]!.entries()].sort(), [...want[table]!.entries()].sort(), `${table} as it was`);
  assert.ok(want.entries!.size > 30, "it had messages");
}

test("a lost station's chats come back complete in a new station, from the stations that keep them", async () => {
  const mesh = new Mesh();
  const [A, B, C, D] = [id("a"), id("b"), id("c"), id("d")];
  mesh.rosters.set(HOME, [A, B, C]);
  const made = station();
  const a = mesh.add(A, [HOME], made);
  mesh.add(B, [HOME]);
  mesh.add(C, [HOME]);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  // deleted after it was copied: deleted in the copies too
  made.store.deleteSession(made.deleted);
  await mesh.settle();
  assert.deepEqual(holders(mesh, HOME, A).sort(), keepers(HOME, A, [A, B, C]).sort());
  assert.deepEqual(holders(mesh, HOME, A).sort(), [B, C]);
  // a new station while A is there: A's backup is not offered (A answers; its chats are its own)
  mesh.rosters.set(HOME, [A, B, C, D]);
  const d = mesh.add(D, [HOME]);
  await d.copies.start();
  await mesh.settle();
  assert.equal(((await d.copies.restorable(HOME)) as Json[]).some((o) => o.station === A), false, "a station that is there is not offered");
  // A is lost
  a.up = false;
  const before = new DatabaseSync(made.db);
  const offered = (await d.copies.restorable(HOME)) as Json[];
  const of = offered.find((o) => o.station === A);
  assert.ok(of, "the lost station's copy is offered");
  assert.equal(of.chats, 2);
  // (D came: it is one of the two that keep A's copy now, the one it took the place of gave it up)
  assert.deepEqual(of.from.map((f: Json) => f.station).sort(), keepers(HOME, A, [A, B, C, D]).sort());
  await d.copies.restore(HOME, A, of.gen, { station: of.from.find((f: Json) => f.station !== D).station });
  const after = startAgain(d);
  same(before, made.data, after, d.data, null);
  // its file, as it was, where its message says
  const path = (JSON.parse((after.prepare("SELECT attachments FROM entries WHERE ts = 'a.pic'").get() as { attachments: string }).attachments) as { path: string }[])[0]!.path;
  assert.ok(path.startsWith(d.data));
  assert.equal(readFileSync(path, "utf8"), "a picture");
  // the deleted chat stays deleted; the archived one is there, archived
  assert.equal(after.prepare("SELECT COUNT(*) AS n FROM sessions WHERE key = 'chat:gone'").get()!.n, 0);
  assert.equal(JSON.stringify(after.prepare("SELECT text FROM entries").all()).includes("chat:gone"), false);
  assert.notEqual((after.prepare("SELECT archived_at FROM sessions WHERE key = 'chat:b'").get() as Json).archived_at, null);
  // the other workspace's chat was not in this one's copy
  assert.equal(after.prepare("SELECT COUNT(*) AS n FROM sessions WHERE key = 'chat:o'").get()!.n, 0);
  after.close();
  before.close();
});

test("a station away for a month catches up when it is back, told by nobody but its coming back", async () => {
  const mesh = new Mesh();
  const [A, B, C] = [id("a"), id("b"), id("c")];
  mesh.rosters.set(HOME, [A, B, C]);
  const made = station();
  const a = mesh.add(A, [HOME], made);
  const b = mesh.add(B, [HOME]);
  mesh.add(C, [HOME]);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  b.up = false;
  const thread = made.store.sessionThreads("chat:a")[0]!.thread.id;
  const day = 86_400_000;
  for (let i = 0; i < 30; i++) {
    made.store.insertMessage({ thread, ts: `day.${i}`, authorKind: "person", author: "p@x", text: `day ${i}` });
    await a.copies.settle();
    await mesh.clock.move(day);
  }
  const head = ((await a.copies.overview(HOME)) as Json);
  const was = mesh.asks;
  // a month of tries backing off: a few a day at most, none at all once it is back
  await mesh.clock.move(day);
  assert.ok(mesh.asks - was <= 24 * 6 + 10, `${mesh.asks - was} asks a day while it was away`);
  b.up = true;
  await b.copies.start();
  await mesh.settle();
  const keptB = new FolderPlace(keptDir(b.data));
  const held = await keptB.held(HOME, A);
  assert.equal(held.gens.at(-1)!.head!.to, head.to, "it holds as much as A has");
  const { folded } = readCopy(join(keptDir(b.data), HOME, A, held.gens.at(-1)!.gen));
  assert.ok(folded.table("entries").some((r) => r.text === "day 29"));
});

test("the stations that keep a copy change as stations come, and never fewer than two hold it meanwhile", async () => {
  const mesh = new Mesh();
  const A = id("a");
  const others = ["b", "c", "d", "e", "f", "1", "2", "3", "4", "5"].map(id);
  // a fourth station that takes one of the first three's place as A's keeper
  const first = [others[0]!, others[1]!, others[2]!];
  const newcomer = others.slice(3).find((s) => keepers(HOME, A, [A, ...first, s]).includes(s))!;
  assert.ok(newcomer);
  mesh.rosters.set(HOME, [A, ...first]);
  mesh.add(A, [HOME], station());
  for (const s of first) mesh.add(s, [HOME]);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  const was = holders(mesh, HOME, A);
  assert.equal(was.length, 2);
  // the newcomer joins but is not reached yet: the one it displaces keeps its copy
  mesh.rosters.set(HOME, [A, ...first, newcomer]);
  const n = mesh.add(newcomer, [HOME]);
  n.up = false;
  for (const x of mesh.nodes.values()) if (x.up) await x.copies.placesChanged();
  await mesh.settle();
  assert.ok(holders(mesh, HOME, A).length >= 2, "two hold it while the newcomer is away");
  assert.deepEqual(holders(mesh, HOME, A).sort(), was.sort());
  // it is reached: it is given the copy, then the one it displaced lets its own go
  n.up = true;
  await n.copies.start();
  await mesh.settle();
  await mesh.clock.move(60_000);
  await mesh.settle();
  assert.deepEqual(holders(mesh, HOME, A).sort(), keepers(HOME, A, [A, ...first, newcomer]).sort());
});

test("a workspace's copies are kept only by its own stations, and a station that leaves one keeps nothing of it", async () => {
  const mesh = new Mesh();
  const [S, P, Q] = [id("a"), id("b"), id("c")];
  mesh.rosters.set(HOME, [S, P]);
  mesh.rosters.set(OTHER, [S, Q]);
  const made = station();
  const s = mesh.add(S, [HOME, OTHER], made);
  const p = mesh.add(P, [HOME]);
  const q = mesh.add(Q, [OTHER]);
  // P keeps a chat of its own in the home workspace: S keeps P's copy
  chat(p.store, p.data, "chat:p", null, 3);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  const inP = await new FolderPlace(keptDir(p.data)).origins(OTHER);
  assert.equal(inP.length, 0, "P keeps nothing of the other workspace");
  const keptP = (await new FolderPlace(keptDir(p.data)).origins(HOME)).find((o) => o.origin === S)!;
  const { folded: atP } = readCopy(join(keptDir(p.data), HOME, S, keptP.heads.at(-1)!.gen));
  assert.equal(atP.table("sessions").some((r) => r.key === "chat:o"), false);
  const keptQ = (await new FolderPlace(keptDir(q.data)).origins(OTHER)).find((o) => o.origin === S)!;
  const { folded: atQ } = readCopy(join(keptDir(q.data), OTHER, S, keptQ.heads.at(-1)!.gen));
  assert.deepEqual(atQ.table("sessions").map((r) => r.key), ["chat:o"]);
  assert.equal(JSON.stringify(atQ.table("entries")).includes("chat:a says"), false);
  assert.equal((await new FolderPlace(keptDir(q.data)).origins(HOME)).length, 0);
  // S leaves the home workspace: nothing of it stays on S
  assert.ok(existsSync(join(keptDir(s.data), HOME, P)));
  s.workspaces = [OTHER];
  await s.copies.placesChanged();
  assert.equal(existsSync(join(keptDir(s.data), HOME)), false);
  assert.equal(existsSync(join(s.data, "replica", "own", HOME)), false);
  // and P asked by a station not of the workspace refuses
  await assert.rejects(q.bus.ask(P, { method: "replica.list", workspace: HOME }));
});

test("a station rolled back to an older copy of its data loses nothing the others hold: a new generation beside it", async () => {
  const mesh = new Mesh();
  const [A, B, C] = [id("a"), id("b"), id("c")];
  mesh.rosters.set(HOME, [A, B, C]);
  const made = station();
  const a = mesh.add(A, [HOME], made);
  mesh.add(B, [HOME]);
  mesh.add(C, [HOME]);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  // its data as a backup keeps it
  const backup = dataDir("backup");
  rmSync(backup, { recursive: true, force: true });
  made.store.db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
  cpSync(made.data, backup, { recursive: true });
  const thread = made.store.sessionThreads("chat:a")[0]!.thread.id;
  made.store.insertMessage({ thread, ts: "after.backup", authorKind: "person", author: "p@x", text: "said after the backup" });
  await mesh.settle();
  const held = await new FolderPlace(keptDir(mesh.nodes.get(B)!.data)).held(HOME, A);
  const genBefore = held.gens.at(-1)!;
  // the backup put back, the station started again
  await a.copies.close();
  a.up = false;
  a.store.close();
  rmSync(made.data, { recursive: true, force: true });
  cpSync(backup, made.data, { recursive: true });
  mesh.nodes.delete(A);
  const again = mesh.add(A, [HOME], { data: made.data, store: Store.open(made.db, join(made.data, "archive")) });
  again.store.insertMessage({ thread, ts: "after.restore", authorKind: "person", author: "p@x", text: "said after it was put back" });
  await again.copies.start();
  await mesh.settle();
  for (const keeper of [B, C]) {
    const gens = (await new FolderPlace(keptDir(mesh.nodes.get(keeper)!.data)).held(HOME, A)).gens;
    assert.equal(gens.length, 2, "both generations kept");
    const old = gens.find((g) => g.gen === genBefore.gen)!;
    assert.equal(old.head!.to, genBefore.head!.to, "the older generation as it was");
    const { folded: lost } = readCopy(join(keptDir(mesh.nodes.get(keeper)!.data), HOME, A, old.gen));
    assert.ok(lost.table("entries").some((r) => r.text === "said after the backup"), "what the backup lacks is still held");
    const { folded: now } = readCopy(join(keptDir(mesh.nodes.get(keeper)!.data), HOME, A, gens.find((g) => g.gen !== genBefore.gen)!.gen));
    assert.ok(now.table("entries").some((r) => r.text === "said after it was put back"));
  }
});

test("a copy whose writer stopped between a batch and its head is the copy as its head says, and the next batch goes on from it", async () => {
  const mesh = new Mesh();
  const [A, B, D] = [id("a"), id("b"), id("d")];
  mesh.rosters.set(HOME, [A, B]);
  const made = station();
  const a = mesh.add(A, [HOME], made);
  const b = mesh.add(B, [HOME]);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  const place = new FolderPlace(keptDir(b.data));
  const gen = (await place.held(HOME, A)).gens[0]!;
  // a batch put there whole, then the writer stopped before the head (and half of another, left as it was)
  const stray = "9999999990-9999999990-deadbeef.ndjson.zst";
  mkdirSync(join(place.dir(HOME, A), gen.gen, "log"), { recursive: true });
  await place.put(HOME, A, gen.gen, "batch", stray, Buffer.from("not a whole batch"));
  const before = new DatabaseSync(made.db);
  a.up = false;
  mesh.rosters.set(HOME, [A, B, D]);
  const d = mesh.add(D, [HOME]);
  await d.copies.start();
  const of = ((await d.copies.restorable(HOME)) as Json[]).find((o) => o.station === A)!;
  await d.copies.restore(HOME, A, of.gen, { station: B });
  const after = startAgain(d);
  same(before, made.data, after, d.data, null);
  after.close();
  before.close();
  // the writer back (started again): what it writes next goes on from the head, and the stray batch goes
  a.up = true;
  mesh.rosters.set(HOME, [A, B]);
  await a.copies.start();
  const thread = made.store.sessionThreads("chat:a")[0]!.thread.id;
  made.store.insertMessage({ thread, ts: "on", authorKind: "person", author: "p@x", text: "goes on" });
  await a.copies.settle();
  const now = (await place.held(HOME, A)).gens[0]!;
  assert.equal(now.batches.includes(stray), false);
  assert.ok(now.head!.to > gen.head!.to);
});

test("a keeper is sent each new batch and head alone: what it holds is asked only as the station starts", async () => {
  const mesh = new Mesh();
  const [A, B] = [id("a"), id("b")];
  mesh.rosters.set(HOME, [A, B]);
  const made = station();
  const a = mesh.add(A, [HOME], made);
  mesh.add(B, [HOME]);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  const before = new Map(mesh.asked.get(B));
  const thread = made.store.sessionThreads("chat:a")[0]!.thread.id;
  const N = 12;
  for (let i = 0; i < N; i++) {
    made.store.insertMessage({ thread, ts: `n.${i}`, authorKind: "person", author: "p@x", text: `message ${i}` });
    await a.copies.settle();
  }
  // a pass with nothing new levels nothing
  await a.copies.settle();
  const after = mesh.asked.get(B)!;
  const delta = (k: string) => (after.get(k) ?? 0) - (before.get(k) ?? 0);
  assert.equal(delta("replica.held"), 0, "no listing asked of it");
  assert.equal(delta("put:head"), N, "a head a pass");
  // (a batch a pass, and those small batches folded into one now and then)
  assert.ok(delta("put:batch") >= N && delta("put:batch") <= N + Math.ceil(N / 3), `${delta("put:batch")} batches sent`);
  const { folded } = readCopy(join(keptDir(mesh.nodes.get(B)!.data), HOME, A, (await new FolderPlace(keptDir(mesh.nodes.get(B)!.data)).held(HOME, A)).gens[0]!.gen));
  assert.ok(folded.table("entries").some((r) => r.text === `message ${N - 1}`));
});

test("while a keeper is not reached, the next station holds the copy; once it is back, it is given the copy and the next lets its own go", async () => {
  const mesh = new Mesh();
  const A = id("a");
  const others = ["b", "c", "d"].map(id);
  mesh.rosters.set(HOME, [A, ...others]);
  const a = mesh.add(A, [HOME], station());
  for (const s of others) mesh.add(s, [HOME]);
  const [first, second] = keepers(HOME, A, [A, ...others]);
  const third = others.find((s) => s !== first && s !== second)!;
  const down = mesh.nodes.get(first!)!;
  down.up = false;
  for (const n of mesh.nodes.values()) if (n.up) await n.copies.start();
  await mesh.settle();
  await mesh.clock.move(60_000);
  await mesh.settle();
  assert.deepEqual(holders(mesh, HOME, A).sort(), [second!, third].sort(), "the next one holds it while the first is away");
  const o = (await a.copies.overview(HOME)) as Json;
  const away = o.keepers.find((k: Json) => k.station === first);
  assert.equal(away.reason, "offline");
  assert.equal(o.keepers.find((k: Json) => k.station === third).error, null, "the next one is among those said to hold it");
  // the first back: it is brought the copy, the third hands over and lets its own go
  down.up = true;
  await down.copies.start();
  await mesh.settle();
  await mesh.clock.move(60_000);
  await mesh.settle();
  assert.deepEqual(holders(mesh, HOME, A).sort(), [first!, second!].sort());
});

test("the export failing is said in the settings, and tried again with a backoff until it goes", async () => {
  const mesh = new Mesh();
  const A = id("a");
  mesh.rosters.set(HOME, [A]);
  const a = mesh.add(A, [HOME], station());
  await a.copies.start();
  await mesh.settle();
  // its thread ends: every pass fails until it is started again
  const fail = { on: true };
  const real = (a as Json).runner as InlineRunner;
  const pass = real.pass.bind(real);
  real.pass = (told) => (fail.on ? Promise.reject(new Error("the copies' thread ended (1)")) : pass(told));
  const thread = a.store.sessionThreads("chat:a")[0]!.thread.id;
  a.store.insertMessage({ thread, ts: "x", authorKind: "person", author: "p@x", text: "while it is down" });
  await a.copies.settle();
  const o = (await a.copies.overview(HOME)) as Json;
  assert.match(o.stopped.error, /thread ended/);
  const tries = o.stopped.tries;
  await mesh.clock.move(4_000);
  assert.equal(((await a.copies.overview(HOME)) as Json).stopped.tries, tries, "not again before its backoff");
  fail.on = false;
  await mesh.clock.move(60_000);
  await a.copies.settle();
  assert.equal(((await a.copies.overview(HOME)) as Json).stopped, null);
});
