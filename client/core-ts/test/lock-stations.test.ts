// The workspace lock read of its stations and brought to them, not the cloud (the root AGENTS.md,
// The cloud is the account system): the cloud asked only where no station answers, and what is signed sent to it too
// for the stations and devices from before, never waited on; a station that tells its lock moved is read again.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { Lock, OTHERS_MS, fold, held, personalStations, read } from "../src/views/lock.ts";
import { ME, genesis, grant, rig } from "./lock-rig.ts";
import { hooks } from "../src/core/execute.ts";
import { Status, stationReplies } from "./station-fixture.ts";

const A = "aa".repeat(32);
/// A second station of the workspace's, gone silent (its machine asleep): asked, it never answers.
const S = "bb".repeat(32);

/// A station of the lock as station/src/mesh/serve.ts answers it: its chain (`chain`), the devices that came to it
/// (`came`); `old`: one from before, which serves none of it.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const came: Record<string, unknown>[] = [];
  const say = { old: false, refuse: false, asked: [] as string[] };
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    say.asked.push(`${method} ${path}`);
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

async function setUp(silent = false) {
  const g = grant();
  let me: Signer | null = null;
  const named = silent ? [{ key: A, name: "a" }, { key: S, name: "s" }] : [{ key: A, name: "a" }];
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, named, g.keys, ME, []) }), undefined, silent ? [A, S] : A);
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
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return st.answer(method, path, body);
    if (ws === "ws" && id === S) return (asleep.asked++, asleep.now ? Effect.never : st.answer(method, path, body));
    return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let out: X | undefined;
    let failed: unknown;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    for (let i = 0; i < 500 && !done; i++) await r.host.time.pass(10);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  // (its key of its person's lock made before: alone in the workspace's lock and its station answering, this device
  // would begin its person's lock by itself and bind it, views/lock.ts `ownLockFor`: entries these tests do not count)
  await run(inner.adb.personal().makeKey());
  return { r, inner, st, cloud, run, asleep, signer: () => me! };
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
  // No station takes it (one from before): the cloud is what takes it, and its failure is the call's.
  st.say.old = true;
  await assert.rejects(run(new Lock(inner, "ws", "s1", null).append("member", { sub: "s4", email: "d@x.com", role: "member" })));
});

test("a station that tells its lock moved is read again", async () => {
  const { inner, st, run, signer, r } = await setUp();
  await run(read(inner, "ws"));
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  inner.stations.onEvent(`ws/${A}`, "lock", JSON.stringify({ workspace: "ws", head: st.head() }));
  for (let i = 0; i < 50 && held(inner, "ws")?.head?.seq !== 1; i++) await r.host.time.pass(10);
  assert.equal(held(inner, "ws")?.head?.seq, 1);
});

test("a station refusing this device tells its lock's last entries: one taken out hears so, with no cloud", async () => {
  const { inner, st, cloud, run, signer, r } = await setUp();
  await run(read(inner, "ws"));
  cloud.down = true;
  // This device taken out (the lock's devices without it), told only by the refusal.
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "device.remove", { id: ME })));
  hooks.lockRefused!(inner, "ws", A, st.head(), { entries: st.chain.slice(1) });
  for (let i = 0; i < 50 && held(inner, "ws")?.head?.seq !== 1; i++) await r.host.time.pass(10);
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
