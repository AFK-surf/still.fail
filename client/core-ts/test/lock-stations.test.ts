// The workspace lock read of its stations and brought to them, not the cloud (the root AGENTS.md,
// The cloud is the account system): the cloud asked only where no station answers, and what is signed sent to it too
// for the stations and devices from before, never waited on; a station that tells its lock moved is read again.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { ASKED_MS, Lock, OTHERS_MS, fold, held, pendingHeld, personalStations, read } from "../src/views/lock.ts";
import { ME, genesis, grant, rig } from "./lock-rig.ts";
import { REREAD_WAIT_MS, hooks } from "../src/core/execute.ts";
import { jsonResponse } from "../src/testing.ts";
import { Status, stationLater, stationReplies } from "./station-fixture.ts";

const A = "aa".repeat(32);
/// A second station of the workspace's, gone silent (its machine asleep): asked, it never answers.
const S = "bb".repeat(32);

/// A station of the lock as station/src/mesh/serve.ts answers it: its chain (`chain`), the devices that came to it
/// (`came`); `old`: one from before, which serves none of it.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const came: Record<string, unknown>[] = [];
  const say = { old: false, refuse: false, silent: false, asked: [] as string[] };
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    say.asked.push(`${method} ${path}`);
    // (its machine asleep, its network gone: asked, it never answers)
    if (say.silent) return Effect.never;
    if (say.refuse) return Effect.fail(new CoreError("lock_unconfirmed", "this device is not on the lock its person bound in this workspace"));
    if (say.old) return path.startsWith("/lock?") || path === "/lock" ? Effect.succeed({ head: head(), entries: [], takes: ["person"] }) : Effect.fail(new CoreError("http_404", "no route", 404));
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: head(), entries: chain.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      for (const e of (body as { entries: Entry[] }).entries) if (e.seq === chain.length) chain.push(e);
      return Effect.succeed({ taken: 1, head: head() });
    }
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: came });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    if (method === "POST" && path === "/lock/person") return Effect.succeed({ taken: 1 });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, came, say, head, answer };
}

/// A station keeping no lock, as station/src/mesh/serve.ts answers then: one of the workspace's that its lock does not
/// name (added and not protected yet: it goes by the cloud's word and lets the members in), or one reset.
function unprotected(method: string, path: string): Effect.Effect<unknown, CoreError> {
  if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) return Effect.succeed({ head: null, entries: [], takes: ["person"], serves: ["person", "devices", "told"] });
  if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
  if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
  return Effect.fail(new CoreError("http_404", "no route", 404));
}

/// `silent`: the workspace has the silent station too. `seen`: the control plane saw it lately (a station of the
/// person's that their lock waits for, views/lock.ts `personalStations` `answered`). `keyMade`: as below. `unnamed`:
/// the workspace has S too, awake, which its lock does not name and which keeps none (`unprotected`; what S was asked
/// is in `atS`). `reset`: A, or S where the lock names it, reset on its own machine since: it keeps no lock.
async function setUp(silent = false, { seen = false, keyMade = true, unnamed = false } = {}) {
  const g = grant();
  let me: Signer | null = null;
  const named = silent ? [{ key: A, name: "a" }, { key: S, name: "s" }] : [{ key: A, name: "a" }];
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, named, g.keys, ME, []) }), undefined, silent || unnamed ? [A, S] : A, seen ? [S] : []);
  const inner = r.core.inner;
  const st = station(r.cloud.chains.get("ws")![0]!);
  // What the cloud is asked of the lock, and whether it answers.
  const cloud = { asked: [] as string[], down: false };
  stationReplies(r.host, (req) => {
    if (!/\/v1\/workspaces\/ws\/(lock|devices)/.test(req.url)) return r.cloud.reply(req);
    cloud.asked.push(`${req.method} ${req.url.replace(/^.*\/v1\/workspaces\/ws/, "")}`);
    return cloud.down ? new Status(503, { error: "down" }) : r.cloud.reply(req);
  });
  // The silent one, until it wakes (answering as the other does; asked the while it slept, it never answers).
  const asleep = { now: true, asked: 0 };
  // What A alone was asked (the silent one, awake, answers as the same station and is noted in `st.say.asked` too).
  const atA: string[] = [];
  const atS: string[] = [];
  const reset = { A: false, S: false };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return (atA.push(`${method} ${path}`), reset.A ? unprotected(method, path) : st.answer(method, path, body));
    if (ws === "ws" && id === S && unnamed) return (atS.push(`${method} ${path}`), unprotected(method, path));
    if (ws === "ws" && id === S) return (asleep.asked++, asleep.now ? Effect.never : reset.S ? unprotected(method, path) : st.answer(method, path, body));
    return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let out: X | undefined;
    let failed: unknown;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    await r.host.time.passUntil(5000, () => done);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  // (its key of its person's lock made before: alone in the workspace's lock and its station answering, this device
  // would begin its person's lock by itself and bind it, views/lock.ts `ownLockFor`: entries these tests do not count.
  // `keyMade: false` for the test of that beginning: a key made before is one it could begin with only by asking, so
  // it would never begin quietly, personal-lock.ts `mayBeginQuietly`)
  if (keyMade) await run(inner.adb.personal().makeKey());
  return { r, inner, st, atA, atS, reset, cloud, run, asleep, signer: () => me! };
}

test("the lock is read of its stations, the devices that came with it; the cloud is not asked", async () => {
  const { inner, st, cloud, run, signer } = await setUp();
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  st.came.push({ sub: "s1", email: "a@x.com", device: "dd".repeat(32), base: ME, kind: "app", label: "Mac", first_seen: 900, last_seen: 1000 });
  cloud.asked.length = 0;
  await run(read(inner, "ws"));
  const h = held(inner, "ws")!;
  assert.equal(h.head?.seq, 1);
  assert.ok(fold(h.entries).members.has("s3"));
  assert.deepEqual(h.seen?.map((d) => d.label), ["Mac"]);
  assert.equal(cloud.asked.length, 0, cloud.asked.join());
  // A station from before serves none of it: the cloud is read, as before.
  st.say.old = true;
  await run(read(inner, "ws"));
  assert.ok(cloud.asked.some((a) => a.startsWith("GET /lock")));
});

test("an entry is brought to the stations and done once one took it: the cloud, down, is not waited on", async () => {
  const { inner, st, cloud, run, r } = await setUp();
  await run(read(inner, "ws"));
  cloud.down = true;
  const done = await run(new Lock(inner, "ws", "s1", null).append("member", { sub: "s3", email: "c@x.com", role: "member" }));
  assert.equal((done as { head: Head }).head.seq, 1);
  assert.equal(st.chain.length, 2);
  // Sent to the cloud as well, for those from before.
  await r.host.time.pass(100);
  assert.ok(cloud.asked.includes("POST /lock"));
  // No station answers the read before it is signed (one from before): the cloud is read, and, down, nothing is signed.
  st.say.old = true;
  await assert.rejects(run(new Lock(inner, "ws", "s1", null).append("member", { sub: "s4", email: "d@x.com", role: "member" })));
  assert.equal(pendingHeld(inner, "ws").length, 0);
});

test("a station that tells its lock moved is read again", async () => {
  const { inner, st, run, signer, r } = await setUp();
  await run(read(inner, "ws"));
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  inner.stations.onEvent(`ws/${A}`, "lock", JSON.stringify({ workspace: "ws", head: st.head() }));
  await r.host.time.passUntil(500, () => held(inner, "ws")?.head?.seq === 1);
  assert.equal(held(inner, "ws")?.head?.seq, 1);
});

test("a read that lands late does not take back what the lock came to hold meanwhile", async () => {
  // S on a slow line, asked alone as its link opened: each answer comes 3 s after it was asked, what S kept then.
  // Meanwhile A tells an entry more and is read. S's answer, behind by now, was held as read: the entry gone from this
  // device again, until the lock next moved.
  const { inner, st, run, signer, r, asleep } = await setUp(true);
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.head?.seq, 0);
  asleep.now = false;
  const call = inner.stations.requests.call;
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const said = (call as (...a: unknown[]) => Effect.Effect<unknown, CoreError>)(addr, method, path, body, ...rest);
    return addr.toString() === `ws/${S}` && path.startsWith("/lock") ? Effect.andThen(Effect.sleep(3_000), said) : said;
  }) as typeof inner.stations.requests.call;
  const opened = (id: string) => Effect.all(inner.stations.also.filter((p) => p.resume).map((p) => Effect.ignore(p.read(`ws/${id}`))), { discard: true });
  let landed = false;
  inner.runner.fork(Effect.andThen(opened(S), Effect.sync(() => { landed = true; })));
  await r.host.time.pass(100);
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  await run(opened(A));
  assert.equal(held(inner, "ws")?.head?.seq, 1);
  assert.equal(landed, false, "S's read still on its way");
  for (let i = 0; i < 200 && !landed; i++) await r.host.time.pass(100);
  assert.ok(landed, "S's read landed");
  assert.equal(held(inner, "ws")?.head?.seq, 1, "what S kept as it was asked is behind what is held, and does not replace it");
  assert.ok(fold(held(inner, "ws")!.entries).members.has("s3"));
});

test("a station the lock does not name, keeping none, read alone does not make this device forget the lock", async () => {
  // #5540: S, in the workspace and not protected yet, answers that it keeps no lock. Read alone (it told `lock`, its
  // link opened again), its answer was every answer of the read, and the device let go of the lock A still keeps.
  const { inner, st, run, signer, r, atS } = await setUp(false, { unnamed: true });
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  const h = held(inner, "ws")!;
  assert.equal(h.head?.seq, 1);
  // (S was asked too, and its answer, with A's beside it, left the lock as A keeps it)
  assert.ok(atS.some((a) => a.startsWith("GET /lock?")), atS.join());
  // S tells its lock moved: it alone is read.
  atS.length = 0;
  inner.stations.onEvent(`ws/${S}`, "lock", JSON.stringify({ workspace: "ws", head: null }));
  await r.host.time.passUntil(500, () => atS.includes("GET /lock/devices"));
  assert.ok(atS.includes("GET /lock/devices"), atS.join());
  await r.host.time.pass(100);
  assert.equal(held(inner, "ws")?.head?.hash, h.head!.hash);
  assert.deepEqual(held(inner, "ws")?.entries, h.entries);
  // S's link opens again (resumed): each part read again after an absence reads it alone, as station/sync.ts does.
  atS.length = 0;
  await run(Effect.all(inner.stations.also.filter((p) => p.resume).map((p) => Effect.ignore(p.read(`ws/${S}`))), { discard: true }));
  assert.ok(atS.some((a) => a.startsWith("GET /lock?")), atS.join());
  await r.host.time.pass(100);
  assert.equal(held(inner, "ws")?.head?.hash, h.head!.hash);
  assert.deepEqual(held(inner, "ws")?.entries, h.entries);
});

test("a station read alone tells who came to it: the devices that came to the others are kept", async () => {
  const { inner, st, run, r, atS } = await setUp(false, { unnamed: true });
  st.came.push({ sub: "s1", email: "a@x.com", device: "dd".repeat(32), base: ME, kind: "app", label: "Mac", first_seen: 900, last_seen: 1000 });
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  assert.deepEqual(held(inner, "ws")?.seen?.map((d) => d.label), ["Mac"]);
  // S, to which none came, tells its lock moved and is read alone: the Mac that came to A is listed still.
  atS.length = 0;
  inner.stations.onEvent(`ws/${S}`, "lock", JSON.stringify({ workspace: "ws", head: null }));
  await r.host.time.passUntil(500, () => atS.includes("GET /lock/devices"));
  assert.ok(atS.includes("GET /lock/devices"), atS.join());
  await r.host.time.pass(100);
  assert.deepEqual(held(inner, "ws")?.seen?.map((d) => d.label), ["Mac"]);
});

test("every station the lock names keeping none, this device lets the lock go", async () => {
  const { inner, run, r, reset } = await setUp(false, { unnamed: true });
  await run(read(inner, "ws"));
  assert.notEqual(held(inner, "ws")?.head, null);
  // A, the one station the lock names, reset on its own machine, tells it: read alone, its word is the lock's end.
  reset.A = true;
  inner.stations.onEvent(`ws/${A}`, "lock", JSON.stringify({ workspace: "ws", head: null }));
  await r.host.time.passUntil(500, () => held(inner, "ws")?.head == null);
  assert.equal(held(inner, "ws")?.head, null);
  assert.deepEqual(held(inner, "ws")?.entries, []);
});

test("one of the lock's two stations keeping none is not the lock's end: the other is asked, and it is once both keep none", async () => {
  const { inner, run, r, reset, asleep } = await setUp(true);
  // (S awake, and answered once: a station that did not answer the read before is not waited for in the next)
  asleep.now = false;
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  const h = held(inner, "ws")!;
  assert.notEqual(h.head, null);
  // A reset on its own machine tells it. Read alone it keeps none, and it is one the lock names: S, the other, is
  // asked too, and keeps the lock.
  reset.A = true;
  let asked = asleep.asked;
  inner.stations.onEvent(`ws/${A}`, "lock", JSON.stringify({ workspace: "ws", head: null }));
  await r.host.time.passUntil(500, () => asleep.asked !== asked);
  assert.ok(asleep.asked > asked, "S was asked as A said it keeps none");
  await r.host.time.pass(100);
  assert.equal(held(inner, "ws")?.head?.hash, h.head!.hash);
  assert.deepEqual(held(inner, "ws")?.entries, h.entries);
  // S reset too, telling it alone: A is asked with it, and with both keeping none the lock is let go.
  reset.S = true;
  inner.stations.onEvent(`ws/${S}`, "lock", JSON.stringify({ workspace: "ws", head: null }));
  await r.host.time.passUntil(500, () => held(inner, "ws")?.head == null);
  assert.equal(held(inner, "ws")?.head, null);
  assert.deepEqual(held(inner, "ws")?.entries, []);
});

test("a device holding no lock where the cloud's view says there is one reads it of a station as its link opens again", async () => {
  // #5540's devices, as they are once updated: the lock let go for an unnamed station's answer, the cloud's view of it
  // unchanged since, so nothing else reads it again.
  const { inner, st, run, r, atA } = await setUp(false, { unnamed: true });
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  const h = held(inner, "ws")!;
  assert.notEqual(h.head, null);
  inner.data.put("lock", "ws", { head: null, entries: [] });
  assert.equal(held(inner, "ws")?.head, null);
  // S's link opens again: it keeps none, but with none held every station is read (views/lock.ts readLockOf: which
  // lock to take is chosen among all their answers), so A is asked too and the lock it keeps is held again at once.
  atA.length = 0;
  await run(Effect.all(inner.stations.also.filter((p) => p.resume).map((p) => Effect.ignore(p.read(`ws/${S}`))), { discard: true }));
  assert.ok(atA.some((a) => a.startsWith("GET /lock")), atA.join());
  await r.host.time.pass(100);
  assert.equal(held(inner, "ws")?.head?.hash, st.head().hash);
  assert.deepEqual(held(inner, "ws")?.entries, h.entries);
});

test("the cloud keeping no lock, asked as no station answered, does not make this device forget the one it holds", async () => {
  const { inner, st, run, r, cloud } = await setUp();
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  const h = held(inner, "ws")!;
  assert.notEqual(h.head, null);
  // No station serves the lock now (as one from before), so the cloud is asked; and the cloud has lost it.
  st.say.old = true;
  r.cloud.chains.set("ws", []);
  cloud.asked.length = 0;
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  assert.ok(cloud.asked.some((a) => a.startsWith("GET /lock")), cloud.asked.join());
  assert.equal(held(inner, "ws")?.head?.hash, h.head!.hash);
  assert.deepEqual(held(inner, "ws")?.entries, h.entries);
});

test("the page to turn safe mode on, asked where none is held and the cloud's view says there is a lock, reads the lock instead", async () => {
  const { inner, st, run, r } = await setUp();
  await run(read(inner, "ws"));
  await r.host.time.pass(100);
  const h = held(inner, "ws")!;
  assert.notEqual(h.head, null);
  // (#5540's device: the lock let go, the stations keeping it still)
  inner.data.put("lock", "ws", { head: null, entries: [] });
  await r.watch({ topic: "lockDraft", workspace: "ws" });
  await r.host.time.passUntil(500, () => held(inner, "ws")?.head != null);
  assert.equal(held(inner, "ws")?.head?.hash, st.head().hash);
  assert.deepEqual(held(inner, "ws")?.entries, h.entries);
});

test("a station refusing this device tells its lock's last entries: one taken out hears so, with no cloud", async () => {
  const { inner, st, cloud, run, signer, r } = await setUp();
  await run(read(inner, "ws"));
  cloud.down = true;
  // This device taken out (the lock's devices without it), told only by the refusal.
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "device.remove", { id: ME })));
  hooks.lockRefused!(inner, "ws", A, st.head(), { entries: st.chain.slice(1) });
  await r.host.time.passUntil(500, () => held(inner, "ws")?.head?.seq === 1);
  assert.equal(held(inner, "ws")?.head?.seq, 1);
  assert.equal(fold(held(inner, "ws")!.entries).devices.has(ME), false);
  // Read again while refused (the workspace said the lock moved): the stations asked, the cloud not.
  st.say.refuse = true;
  cloud.asked.length = 0;
  await run(read(inner, "ws"));
  assert.equal(cloud.asked.length, 0, cloud.asked.join());
  st.say.refuse = false;
  // Entries that do not go on from the lock held are not taken.
  const other = signer().sign(next("ws", { seq: 1, hash: "ff".repeat(32), genesis: st.head().genesis }, 1002, "member", { sub: "s9", email: "x@x.com", role: "member" }));
  hooks.lockRefused!(inner, "ws", A, st.head(), { entries: [other] });
  await r.host.time.pass(100);
  assert.equal(held(inner, "ws")?.head?.seq, 1);
});

test("a station gone silent is not waited on: the locks are read of the one that answered and brought there", async () => {
  const { inner, st, cloud, run, signer, r, asleep } = await setUp(true);
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  cloud.asked.length = 0;
  // Read of the one that answers, the other waited for OTHERS_MS more, not until its link gives up.
  const t0 = r.host.nowMs();
  await run(read(inner, "ws"));
  assert.ok(r.host.nowMs() - t0 <= OTHERS_MS + 100, `read in ${r.host.nowMs() - t0} ms`);
  assert.equal(held(inner, "ws")?.head?.seq, 1);
  assert.equal(cloud.asked.length, 0, cloud.asked.join());
  // An entry: the lock read first, the silent one not waited for again (it was, once), then done once the one took it.
  const t1 = r.host.nowMs();
  await run(new Lock(inner, "ws", "s1", null).append("member", { sub: "s4", email: "d@x.com", role: "member" }));
  assert.ok(r.host.nowMs() - t1 <= 100, `taken in ${r.host.nowMs() - t1} ms`);
  assert.equal(st.chain.length, 3);
  // The person's own lock: read of the one that answered, brought, done once it took it.
  const own = personalStations(inner);
  const t2 = r.host.nowMs();
  assert.deepEqual(await run(own.read("s1")), []);
  assert.ok(r.host.nowMs() - t2 <= 100, `own lock read in ${r.host.nowMs() - t2} ms`);
  const t3 = r.host.nowMs();
  assert.equal(await run(own.bring("s1", [])), 1);
  assert.ok(r.host.nowMs() - t3 <= 100, `own lock taken in ${r.host.nowMs() - t3} ms`);
  // Refused by the one that answers (this device not let in yet): that is its answer, the silent one not waited on
  // until TAKEN_MS (a new device joining with one station asleep waited twice that before it could ask to be let in).
  st.say.refuse = true;
  const t4 = r.host.nowMs();
  await run(own.read("s1"));
  await run(read(inner, "ws"));
  assert.ok(r.host.nowMs() - t4 <= 2 * OTHERS_MS + 200, `refused in ${r.host.nowMs() - t4} ms`);
  st.say.refuse = false;
  // Awake again: once it answered something, it is waited for as before, and what it alone has is read of it.
  asleep.now = false;
  await run(read(inner, "ws"));
  await r.host.time.pass(10);
  asleep.now = true;
  const t5 = r.host.nowMs();
  await run(read(inner, "ws"));
  assert.ok(r.host.nowMs() - t5 >= OTHERS_MS, `waited for again: ${r.host.nowMs() - t5} ms`);
});

test("the one to begin its person's lock, held back for a station asleep, begins it once that one answers", async () => {
  const { inner, atA, run, r, asleep } = await setUp(true, { seen: true, keyMade: false });
  const personal = inner.adb.personal();
  const asked = r.host.secureAsked.length;
  // (both workspaces' locks read, as ownLockFor waits for: the other one is read of the cloud, with no stations)
  await run(read(inner, "w2"));
  await run(read(inner, "ws"));
  // Alone in the workspace's lock and signing there, this device is the one to begin; the silent station, seen lately,
  // has not answered a read of the person's lock, so it begins nothing. (Its read of A asked, and its wait for the
  // silent one over, so that nothing is still to come of it.)
  await r.host.time.passUntil(5000, () => atA.includes("GET /lock/person"));
  assert.ok(atA.includes("GET /lock/person"), "the person's lock read of A");
  await r.host.time.pass(2 * OTHERS_MS + 200);
  assert.equal(personal.standing("s1"), "none");
  assert.ok(!atA.includes("POST /lock/person"), atA.join());
  // Awake again, reached, and its person's lock read of it alone (as the core reads it of a station reached): the last
  // of their stations answered, and the one held back for it begins now, nothing else moving.
  asleep.now = false;
  await run(personal.refresh("s1", `ws/${S}`));
  await r.host.time.passUntil(10000, () => personal.standing("s1") === "member");
  assert.equal(personal.standing("s1"), "member");
  assert.equal(personal.entries("s1")[0]?.kind, "genesis");
  assert.ok(atA.includes("POST /lock/person"), atA.join());
  // Begun quietly: its key made then, its seed in hand, the person not asked.
  assert.equal(r.host.secureAsked.length, asked, JSON.stringify(r.host.secureAsked));
});

test("a locked workspace's roster changes answer within the stations' wait and the reread's while nothing read answers, pending in the lock, the cloud's roster asked after", async () => {
  // (2026-11-11: 添加 turned for minutes in a locked workspace whose stations were not reached; #5549 bounded only the
  // reread after. test/writes-answer.test.ts holds every cloud write to this in a workspace with no lock; here the six
  // of them the lock has a part in, in one this device signs for, its station having served the lock and gone silent)
  const { inner, st, run, r, cloud } = await setUp();
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.head?.seq, 0);
  const members = [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }];
  const json = (b: unknown) => Promise.resolve(jsonResponse(200, b));
  const said: string[] = [];
  // Every read of the cloud left unanswered, its writes answered at once (the lock's entries kept, lock-rig.ts).
  stationLater(r.host, (req) => {
    const path = new URL(req.url).pathname;
    if (req.method === "GET") return new Promise(() => {});
    if (req.method === "POST" && path === "/v1/workspaces/ws/lock") said.push("lock");
    if (req.method === "POST" && path === "/v1/workspaces/ws/members") return json({ joined: [], added: ["d@x.com"], already: [], view: { members } });
    if ((req.method === "PATCH" || req.method === "DELETE") && path === "/v1/workspaces/ws/members/s2") {
      said.push(`cloud ${req.method}`);
      return json({ ok: true });
    }
    if (req.method === "DELETE" && path === "/v1/workspaces/ws/added/d%40x.com") return json({ members });
    if (req.method === "DELETE" && path === `/v1/workspaces/ws/stations/${A}`) return json({ ok: true });
    if (req.method === "POST" && path === "/v1/workspaces/ws/enrollments") {
      return json({ token: "tok", install: "curl x | sh -s -- tok", installWindows: "& (irm x) tok", command: "stillfail station enroll https://x tok" });
    }
    return undefined;
  });
  // The station, which served the lock until now, answers nothing more: neither a read nor what it is brought.
  st.say.silent = true;
  const chain = () => r.cloud.chains.get("ws")!;
  const timed = async (name: string, params: Record<string, unknown>): Promise<any> => {
    const t0 = r.host.nowMs();
    const answer = await r.ask(name, { account: "s1", workspace: "ws", ...params });
    // (ask steps the clock 10 ms at a time, and passes 100 ms after the answer)
    assert.ok(r.host.nowMs() - t0 <= ASKED_MS + REREAD_WAIT_MS + 200, `${name} answered after ${r.host.nowMs() - t0} ms`);
    return answer;
  };
  // Each entry pending (no station took it), after the head held, which none of them moves; the cloud not sent it.
  const pends = async (name: string, params: Record<string, unknown>, kind: string, body: unknown) => {
    const length = chain().length;
    const head = held(inner, "ws")!.head!.hash;
    await timed(name, params);
    assert.equal(chain().length, length, `${name}: the cloud not sent it`);
    assert.equal(held(inner, "ws")!.head!.hash, head, `${name}: not held`);
    const p = pendingHeld(inner, "ws").at(-1)!;
    assert.deepEqual([p.state, p.entry.kind, p.entry.body, p.entry.prev], ["waiting", kind, body, head], name);
  };

  await pends("workspace.setRole", { member: "s2", role: "admin" }, "member", { sub: "s2", email: "b@x.com", role: "admin" });
  assert.deepEqual(said, ["cloud PATCH"], "the lock's entry before the cloud's roster is asked, still (pending, not sent to the cloud)");
  assert.ok(!cloud.asked.includes("POST /lock"), "the cloud not sent the lock's entry no station took");
  await pends("workspace.addMembers", { role: "admin", emails: ["d@x.com"] }, "member", { sub: "pending:d@x.com", email: "", role: "admin" });
  // Taken out again while their adding is pending: the adding dropped, nothing signed (it never took effect).
  const before = pendingHeld(inner, "ws").length;
  await timed("workspace.removeAdded", { email: "d@x.com" });
  assert.equal(pendingHeld(inner, "ws").length, before - 1);
  assert.ok(!pendingHeld(inner, "ws").some((p) => (p.entry.body as { sub?: string }).sub === "pending:d@x.com"));
  // The command pins the lock as its station last said it (it took none of the entries since): an entry of the chain.
  const enrolled = await timed("workspace.enroll", { name: "mini" });
  assert.ok(enrolled.command.endsWith(` --lock ${st.head().hash}`), enrolled.command);
  assert.equal(st.chain.length, 1);
  await pends("workspace.removeMember", { member: "s2" }, "member.remove", { sub: "s2" });
  // Its one station taken out: the lock names none after that, which is the cloud's to keep from it on, as a lock that
  // never named one is (a station gone for good is waited for by nothing), and held.
  const length = chain().length;
  await timed("workspace.removeStation", { station: A });
  assert.ok(chain().slice(length).some((e) => e.kind === "station.remove"), "the cloud keeps it");
  assert.ok(held(inner, "ws")!.entries.some((e) => e.kind === "station.remove" && (e.body as { key: string }).key === A), "held");
});
