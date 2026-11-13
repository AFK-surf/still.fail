// A workspace whose chain moved to its people's own logs, as this device reads it (src/lock-moved.ts, views/lock.ts
// `inForceOf`): the stations serve the logs and the statements' bodies (`serves` `logs`, `bodies`: GET /lock/logs,
// GET /lock/bodies), and every reader of the lock goes by what they say. The world: `ws`, its station A, its chain the
// rig's genesis (this device the owner's app) and a `moved` to alice's log; alice (r1) states the settings (`open`),
// bob (r2) a member and A a station; bob's log has a second app device and a web page of his.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { type Entry as StationEntry, entryHash as stationHash } from "../../../station/src/cloud/lock.ts";
import { key, signed } from "../../../station/test/lock-world-sim.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { bodyHash, wsTag } from "../src/lock-moved.ts";
import { held, inForceOf, pendingHeld, read } from "../src/views/lock.ts";
import { genesis, grant, rig } from "./lock-rig.ts";

const A = "aa".repeat(32);
const WEB = "c0".repeat(32);
/// The test clock's start (src/testing.ts TestTime), in seconds.
const T = Date.UTC(2026, 9, 6, 9, 0, 0) / 1000;

type Log = { sub: string; k: ReturnType<typeof key>; chain: StationEntry[]; said: string | null; n: number };
function person(sub: string, n: number, label: string): Log {
  const k = key(n);
  const g = signed({ v: 1, ws: `person:${sub}`, seq: 0, prev: null, at: T, kind: "genesis", body: { sub, device: { key: k.id, id: key(n + 100).hex, label } } } as Omit<StationEntry, "sig">, k);
  return { sub, k, chain: [g], said: null, n: 0 };
}
const gOf = (l: Log) => stationHash(l.chain[0]!);
function add(l: Log, kind: string, body: unknown, at = T): StationEntry {
  const last = l.chain[l.chain.length - 1]!;
  const e = signed({ v: 1, ws: `person:${l.sub}`, seq: l.chain.length, prev: stationHash(last), at, kind, body } as Omit<StationEntry, "sig">, l.k);
  l.chain.push(e);
  return e;
}
/// A statement of `ws` in `l`: its body (naming the one before it) and its commitment there.
function say(l: Log, kind: string, more: Record<string, unknown>): Record<string, unknown> {
  const b = { ws: "ws", kind, ...more, prev: l.said, salt: (++l.n + 0x5a00 * l.chain.length).toString(16).padStart(32, "0") };
  const h = bodyHash(b)!;
  add(l, "ws", { t: wsTag("ws", gOf(l)), h });
  l.said = h;
  return b;
}
const SETTINGS = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: { keys: [] } };

/// `first`: what the station serves from the first read on (the rig reads it as its link opens).
async function setUp(first: (st: { logs: Log[]; bodies: unknown[] }, w: { alice: Log; bob: Log; member: unknown }) => void = () => {}) {
  const g = grant();
  let me: Signer | null = null;
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys) }), undefined, [A]);
  const inner = r.core.inner;
  const signer = me! as Signer;
  const g0 = r.cloud.chains.get("ws")![0]!;
  const alice = person("r1", 6001, "alice's app");
  const bob = person("r2", 6002, "bob's app");
  const bob2 = key(6003);
  const open = say(alice, "open", { ...SETTINGS, email: "alice@x" });
  const member = say(alice, "member", { sub: "r2", email: "bob@x", lock: gOf(bob), role: "member" });
  const station = say(alice, "station", { key: A });
  add(bob, "device", { key: bob2.id, id: key(6103).hex, label: "bob's laptop" });
  add(bob, "web", { id: WEB, label: "bob's browser", exp: T + 300 });
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c[c.length - 1]!), genesis: entryHash(c[0]!) });
  const moved = signer.sign(next("ws", headOf([g0]), 1001, "moved", { root: gOf(alice) }));
  const st = { chain: [g0, moved] as Entry[], logs: [alice, bob] as Log[], bodies: [open, member, station] as unknown[], posted: [] as string[], given: [] as unknown[] };
  first(st, { alice, bob, member });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    const serves = { takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs"] };
    const c = st.chain;
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: headOf(c), entries: c.filter((e) => e.seq > after), ...(after >= 0 && c[after] ? { after_hash: entryHash(c[after]!) } : {}), ...serves });
    }
    if (method === "GET" && path === "/lock/logs") return Effect.succeed({ chains: st.logs.map((l) => ({ genesis: gOf(l), entries: l.chain })) });
    if (method === "GET" && path === "/lock/bodies") return Effect.succeed({ bodies: st.bodies, lacking: [] });
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    st.posted.push(`${method} ${path}`);
    if (method === "POST" && path === "/lock/bodies") st.given.push(...((body as { bodies?: unknown[] })?.bodies ?? []));
    if (method === "POST") return Effect.succeed({ taken: 1, head: headOf(c) });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return answer(method, path, body);
    return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    inner.runner.fork(Effect.match(e, { onSuccess: () => { done = true; }, onFailure: () => { done = true; } }));
    await r.host.time.passUntil(5000, () => done);
    assert.ok(done, "no answer");
    await r.host.time.pass(100);
  };
  // The station tells its lock's state changed, its head as it was (station/src/mesh/lock-events.ts).
  const told = async () => {
    inner.stations.onEvent(`ws/${A}`, "lock", JSON.stringify({ workspace: "ws", head: headOf(st.chain) }));
    for (let t = 0; t < 3000; t += 10) await r.host.time.pass(10);
  };
  await run(inner.adb.personal().makeKey());
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const who = async () => {
    const v = await lock();
    return { v, members: (v.members as any[]).map((m) => `${m.sub} ${m.role}: ${(m.groups as any[]).flatMap((x) => x.devices).map((d: any) => d.id.slice(0, 4)).sort().join(",")}`).sort().join("; ") };
  };
  return { r, inner, st, alice, bob, bob2, g0, moved, run, told, who, member, open, signer, headOf };
}

const bobs = (w: { bob: Log }, web: boolean) => `r1 owner: ${key(6101).hex.slice(0, 4)}; r2 member: ${[key(6102).hex.slice(0, 4), key(6103).hex.slice(0, 4), ...(web ? [WEB.slice(0, 4)] : [])].sort().join(",")}`;

test("a moved chain: the lock lists the members, roles, devices and stations its people's logs say, and a web page until its exp by this device's clock", async () => {
  const w = await setUp();
  await w.run(read(w.inner, "ws"));
  assert.equal(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  const s = inForceOf(w.inner, "ws");
  assert.equal(s.said, "on");
  assert.deepEqual([...s.f.stations.keys()], [A], "the stations the logs say");
  assert.equal(s.f.members.get("r2")?.email, "bob@x");
  assert.equal(s.f.added.get(WEB), T, "a device put on at its log entry's `at`");
  const now = await w.who();
  assert.equal(now.members, bobs(w, true), "the people's logs, not the genesis's s1 and s2");
  assert.equal(now.v.locked, true);
  // past the web page's exp, by this device's clock: gone from what is in force, and from the topic once it is made again
  await w.r.host.time.pass(400_000, 1000);
  assert.equal(inForceOf(w.inner, "ws").f.devices.has(WEB), false, "a web page past its exp is gone");
  await w.told();
  assert.equal((await w.who()).members, bobs(w, false));
});

test("a member's device taken off its log is gone after the station's lock event alone, its chain's head as it was", async () => {
  const w = await setUp();
  await w.run(read(w.inner, "ws"));
  assert.equal((await w.who()).members, bobs(w, true));
  add(w.bob, "device.remove", { key: w.bob2.id });
  await w.told();
  assert.equal((await w.who()).members, `r1 owner: ${key(6101).hex.slice(0, 4)}; r2 member: ${[key(6102).hex.slice(0, 4), WEB.slice(0, 4)].sort().join(",")}`);
});

test("a body lacking: its statement not in force; in force once a station gives it", async () => {
  const w = await setUp((st, x) => void (st.bodies = st.bodies.filter((b) => b !== x.member)));
  await w.run(read(w.inner, "ws"));
  assert.equal((await w.who()).members, `r1 owner: ${key(6101).hex.slice(0, 4)}`, "bob not in without his admit's body");
  w.st.bodies = [...w.st.bodies, w.member];
  await w.told();
  assert.equal((await w.who()).members, bobs(w, true));
});

test("off, then open again: the lock off, then on", async () => {
  const w = await setUp();
  await w.run(read(w.inner, "ws"));
  const off = say(w.alice, "off", {});
  w.st.bodies = [...w.st.bodies, off];
  await w.told();
  assert.equal(inForceOf(w.inner, "ws").said, "off");
  assert.equal((await w.who()).v.locked, false, "off");
  const open = say(w.alice, "open", { ...SETTINGS, email: "alice@x" });
  w.st.bodies = [...w.st.bodies, open];
  await w.told();
  assert.equal((await w.who()).v.locked, true, "on again");
});

test("waiting (no root's log here): nobody and nothing listed, never the folded chain's members, nothing asked of this device", async () => {
  const w = await setUp((st, x) => void (st.logs = [x.bob]));
  await w.run(read(w.inner, "ws"));
  assert.equal(inForceOf(w.inner, "ws").said, "waiting");
  const { v, members } = await w.who();
  assert.equal(members, "", "nobody");
  assert.equal(v.locked, true, "on");
  assert.equal(v.me.waiting, false, "this device is not asked to be approved");
  assert.equal(v.me.pair ?? null, null);
  assert.equal(v.signers, 0);
});

test("each writer on a moved chain answers lock_moved: nothing signed, nothing pending", async () => {
  const w = await setUp();
  await w.run(read(w.inner, "ws"));
  const before = held(w.inner, "ws")!.entries.length;
  for (const [name, params] of [["lock.disable", { workspace: "ws" }], ["lock.joinStation", { workspace: "ws", station: A }]] as const) {
    let code: string | undefined;
    try {
      await w.r.ask(name, params);
    } catch (e) {
      code = (e as { code?: string }).code;
    }
    assert.equal(code, "lock_moved", `${name} answers lock_moved`);
  }
  assert.equal(held(w.inner, "ws")!.entries.length, before, "nothing signed on the chain");
  assert.equal(pendingHeld(w.inner, "ws").length, 0, "nothing pending");
  assert.deepEqual(w.st.posted.filter((p) => p === "POST /lock"), [], "nothing brought to the station");
});
