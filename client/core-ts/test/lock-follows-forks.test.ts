// The workspace lock as held after a read, where a station's chain went another way than the one held (the stations go
// by the rules' fork choice, station/src/cloud/log-keep.ts): the device keeps what each station showed it and goes by
// the rules' choice among all of it (src/lock-keep.ts), never putting an entry after one that is not its `prev`. The
// world: `ws` and its stations A and S, both named by its lock L, whose genesis names this device (the owner's app) and
// OLD, another app of the owner's that signs. P is a member put in; X and Y two entries after P: which wins is by the
// rules' second step (a removal of a device that signs, at equal weight), so no case turns on a hash.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { OTHERS_MS, fold, held, read } from "../src/views/lock.ts";
import { ME, elsewhere, genesis, grant, rig } from "./lock-rig.ts";
import { stationReplies } from "./station-fixture.ts";

const A = "aa".repeat(32);
const S = "bb".repeat(32);
const OLD = "ee".repeat(32);

const headOf = (chain: Entry[]): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
const short = (e: Entry) => entryHash(e).slice(0, 6);

/// A station of the lock as station/src/mesh/serve.ts answers it: its chain; `hashes`, whether it says the hash of its
/// entry at `after` (`after_hash`, as stations since 2026-11-12 do); `old`, one from before, which serves none of it.
function station(chain: Entry[], hashes: boolean) {
  const say = { old: false };
  const answer = (method: string, path: string): Effect.Effect<unknown, CoreError> => {
    if (say.old) return path.startsWith("/lock?") || path === "/lock" ? Effect.succeed({ head: headOf(chain), entries: [], takes: ["person"] }) : Effect.fail(new CoreError("http_404", "no route", 404));
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      const at = after >= 0 ? chain[after] : undefined;
      return Effect.succeed({ head: headOf(chain), entries: chain.filter((e) => e.seq > after), ...(hashes && at !== undefined ? { after_hash: entryHash(at) } : {}), ...serves });
    }
    if (method === "POST" && path === "/lock") return Effect.succeed({ taken: 1, head: headOf(chain) });
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    if (method === "POST" && path === "/lock/person") return Effect.succeed({ taken: 1 });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, say, answer };
}

/// `xWins`: X is the removal of OLD and Y a member put in (X wins); else the other way round.
async function setUp(xWins = false, hashes = true) {
  const g = grant();
  let me: Signer | null = null;
  const old = { id: OLD, sub: "s1", kind: "app", label: "old", sign_key: elsewhere().id };
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, [{ key: A, name: "a" }, { key: S, name: "s" }], g.keys, ME, [old]) }), undefined, [A, S]);
  const inner = r.core.inner;
  const signer = me! as Signer;
  const g0 = r.cloud.chains.get("ws")![0]!;
  const sign = (chain: Entry[], at: number, kind: string, body: unknown) => signer.sign(next("ws", headOf(chain), at, kind, body));
  const P = sign([g0], 1001, "member", { sub: "s3", email: "c@x.com", role: "member" });
  const removal = (chain: Entry[]) => sign(chain, 1002, "device.remove", { id: OLD });
  const member = (chain: Entry[]) => sign(chain, 1003, "member", { sub: "s4", email: "d@x.com", role: "member" });
  const X = xWins ? removal([g0, P]) : member([g0, P]);
  const Y = xWins ? member([g0, P]) : removal([g0, P]);
  const Z = sign([g0, P, Y], 1004, "member", { sub: "s5", email: "e@x.com", role: "member" });
  const names = new Map([g0, P, X, Y, Z].map((e, i) => [entryHash(e), ["g", "P", "X", "Y", "Z"][i]!]));
  const a = station([g0, P], hashes);
  const s = station([g0, P], hashes);
  const put = (st: { chain: Entry[] }, chain: Entry[]) => void st.chain.splice(0, st.chain.length, ...chain);
  const cloud = { asked: [] as string[] };
  stationReplies(r.host, (req) => {
    if (/\/v1\/workspaces\/ws\/(lock|devices)/.test(req.url)) cloud.asked.push(`${req.method} ${req.url.replace(/^.*\/v1\/workspaces\/ws/, "")}`);
    return r.cloud.reply(req);
  });
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return a.answer(method, path);
    if (ws === "ws" && id === S && path.startsWith("/lock")) return s.answer(method, path);
    return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let failed: unknown;
    inner.runner.fork(Effect.match(e, { onSuccess: () => { done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    await r.host.time.passUntil(5000, () => done);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    await r.host.time.pass(100);
  };
  // One station alone, as it tells its lock moved.
  const told = async (id: string) => {
    const st = id === A ? a : s;
    inner.stations.onEvent(`ws/${id}`, "lock", JSON.stringify({ workspace: "ws", head: headOf(st.chain) }));
    for (let t = 0; t < OTHERS_MS + 500; t += 10) await r.host.time.pass(10);
  };
  const said = (es: Entry[] | undefined) => (es ?? []).map((e) => names.get(entryHash(e)) ?? short(e)).join(",");
  const record = () => inner.data.record("lock", "ws") as { head: Head | null; entries: Entry[]; aside?: Entry[] } | null;
  /// What is held is `chain` (its head and its entries from the genesis), with `aside` kept off it.
  const holds = (chain: Entry[], aside: Entry[], why: string) => {
    const h = record();
    assert.equal(said(h?.entries), said(chain), `${why}: held`);
    assert.deepEqual(h?.head ?? null, headOf(chain), `${why}: its head`);
    assert.equal(said(h?.aside), said(aside), `${why}: kept aside`);
    for (let i = 1; i < (h?.entries.length ?? 0); i++) assert.equal(h!.entries[i]!.prev, entryHash(h!.entries[i - 1]!), `${why}: entry ${i} goes on from the one before`);
  };
  // (its key of its person's lock made before, as lock-stations.test.ts: the person's lock begun meanwhile is not the point)
  await run(inner.adb.personal().makeKey());
  return { r, inner, a, s, put, g0, P, X, Y, Z, run, told, holds, record, said, cloud, sign };
}

for (const hashes of [true, false])
  test(`a station that moved off the entry held for one that wins goes by, with what came after it (${hashes ? "it says after_hash" : "one that says none"})`, async () => {
    const w = await setUp(false, hashes);
    w.put(w.a, [w.g0, w.P, w.X]);
    w.put(w.s, [w.g0, w.P, w.X]);
    await w.run(read(w.inner, "ws"));
    w.holds([w.g0, w.P, w.X], [], "both on X");
    // S moved off X for Y (the removal of OLD, which wins at P by the rules), and took Z after it.
    w.put(w.s, [w.g0, w.P, w.Y, w.Z]);
    w.put(w.a, [w.g0, w.P, w.Y, w.Z]);
    await w.run(read(w.inner, "ws"));
    w.holds([w.g0, w.P, w.Y, w.Z], [w.X], "after the read");
    const f = fold(held(w.inner, "ws")!.entries);
    assert.ok(!f.devices.has(OLD), "the removal is gone by");
    assert.ok(f.members.has("s5") && !f.members.has("s4"), "Z's member in, X's not");
  });

test("a station at the same place as the entry held, on one that wins: the device moves to it", async () => {
  const w = await setUp();
  w.put(w.a, [w.g0, w.P, w.X]);
  w.put(w.s, [w.g0, w.P, w.X]);
  await w.run(read(w.inner, "ws"));
  w.put(w.s, [w.g0, w.P, w.Y]);
  await w.told(S);
  w.holds([w.g0, w.P, w.Y], [w.X], "after S alone");
});

test("a station on an entry that loses to the one held: the device stays and keeps it aside; read again, nothing changes", async () => {
  const w = await setUp(true);
  w.put(w.a, [w.g0, w.P, w.X]);
  w.put(w.s, [w.g0, w.P, w.X]);
  await w.run(read(w.inner, "ws"));
  w.put(w.s, [w.g0, w.P, w.Y]);
  await w.run(read(w.inner, "ws"));
  w.holds([w.g0, w.P, w.X], [w.Y], "after the read");
  await w.told(S);
  await w.run(read(w.inner, "ws"));
  w.holds([w.g0, w.P, w.X], [w.Y], "read again");
  // Y's own child does not make it win: the choice is at P.
  w.put(w.s, [w.g0, w.P, w.Y, w.Z]);
  await w.told(S);
  w.holds([w.g0, w.P, w.X], [w.Y, w.Z], "S went on after Y");
});

// Two stations, one on each branch: whatever order they are read in, the same chain is held.
for (const how of ["together", "A then S", "S then A"] as const)
  test(`two stations on two branches, read ${how}: the rules' choice is held`, async () => {
    const w = await setUp();
    await w.run(read(w.inner, "ws"));
    w.holds([w.g0, w.P], [], "both on P");
    w.put(w.a, [w.g0, w.P, w.X]);
    w.put(w.s, [w.g0, w.P, w.Y, w.Z]);
    if (how === "together") await w.run(read(w.inner, "ws"));
    else for (const id of how === "A then S" ? [A, S] : [S, A]) await w.told(id);
    w.holds([w.g0, w.P, w.Y, w.Z], [w.X], `read ${how}`);
  });

test("a station behind changes nothing; nor one whose entries do not verify", async () => {
  const w = await setUp();
  w.put(w.a, [w.g0, w.P, w.X]);
  w.put(w.s, [w.g0, w.P, w.X]);
  await w.run(read(w.inner, "ws"));
  w.put(w.s, [w.g0, w.P]);
  await w.told(S);
  w.holds([w.g0, w.P, w.X], [], "S behind");
  // Y's body changed after it was signed (its hash is another, its signature not over it), and an entry after it.
  const bad = { ...w.Y, body: { id: "dd".repeat(32) } } as Entry;
  const after = w.sign([w.g0, w.P, bad], 1005, "member", { sub: "s6", email: "f@x.com", role: "member" });
  w.put(w.s, [w.g0, w.P, bad, after]);
  await w.told(S);
  w.holds([w.g0, w.P, w.X], [], "S's entries do not verify");
});

test("the cloud's read (no station serving the lock): a chain gone another way is the rules' choice too", async () => {
  const w = await setUp();
  w.put(w.a, [w.g0, w.P, w.X]);
  w.put(w.s, [w.g0, w.P, w.X]);
  await w.run(read(w.inner, "ws"));
  w.a.say.old = true;
  w.s.say.old = true;
  w.r.cloud.chains.set("ws", [w.g0, w.P, w.Y, w.Z]);
  w.cloud.asked.length = 0;
  await w.run(read(w.inner, "ws"));
  assert.ok(w.cloud.asked.some((x) => x.startsWith("GET /lock")), w.cloud.asked.join());
  w.holds([w.g0, w.P, w.Y, w.Z], [w.X], "after the cloud's read");
});

test("a record from before (no aside) is read as before; one written now has the chain from the genesis as `entries`", async () => {
  const w = await setUp();
  w.put(w.a, [w.g0, w.P, w.X]);
  w.put(w.s, [w.g0, w.P, w.X]);
  await w.run(read(w.inner, "ws"));
  // As a core from before wrote it.
  w.inner.data.put("lock", "ws", { head: headOf([w.g0, w.P, w.X]), entries: [w.g0, w.P, w.X] });
  await w.run(read(w.inner, "ws"));
  w.holds([w.g0, w.P, w.X], [], "from before");
  assert.ok(!("aside" in w.record()!), "none aside: none written");
  w.put(w.s, [w.g0, w.P, w.Y, w.Z]);
  await w.told(S);
  const h = w.record()!;
  assert.deepEqual(Object.keys(h).sort(), ["aside", "entries", "head", "seen"]);
  // What a reader from before reads of it: `entries`, a plain array from the genesis, and the head its last.
  assert.ok(Array.isArray(h.entries) && h.entries[0]!.seq === 0 && h.entries[0]!.prev === null);
  assert.deepEqual(h.head, headOf(h.entries));
  assert.deepEqual(JSON.parse(JSON.stringify(h.entries)), JSON.parse(JSON.stringify([w.g0, w.P, w.Y, w.Z])));
  assert.deepEqual(JSON.parse(JSON.stringify(h.aside)), JSON.parse(JSON.stringify([w.X])));
});
