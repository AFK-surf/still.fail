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
import { bodyHash, made, wsTag } from "../src/lock-moved.ts";
import { Lock, bindPerson, deliver, held, inForceOf, keepToPerson, lockSeen, ownLockFor, pendingHeld, read } from "../src/views/lock.ts";
import { jsonResponse } from "../src/testing.ts";
import { ME, elsewhere, genesis, grant, rig, unhex } from "./lock-rig.ts";
import { utf8 } from "../src/util.ts";
import { stationLater } from "./station-fixture.ts";

const A = "aa".repeat(32);
const OTHER = "e1".repeat(32);
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

/// `first`: what the station serves from the first read on (the rig reads it as its link opens). `other`: the genesis
/// names a second device of the owner's (`elsewhere`), which signs the `moved`: none of this device's own entries is
/// then off the chain as it changes branch (`again` would sign it again).
type Served = { chain: Entry[]; logs: Log[]; bodies: unknown[]; posted: string[]; given: unknown[]; lacking: string[]; silent: boolean; brought: string[] };
async function setUp(first: (st: Served, w: { alice: Log; bob: Log; member: unknown; open: unknown }) => void = () => {}, opts: { other?: boolean } = {}) {
  const g = grant();
  let me: Signer | null = null;
  const other = elsewhere();
  const more = opts.other ? [{ id: OTHER, sub: "s1", kind: "app", label: "the owner's other", sign_key: other.id }] : [];
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME, more) }), undefined, [A]);
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
  // (as src/lock.ts Signer.sign, with the other device's key)
  const byOther = (e: Omit<Entry, "sig">): Entry => ({ ...e, sig: { key: other.id, alg: "Ed25519", sig: other.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e as Entry))])) } });
  const sign = (e: Omit<Entry, "sig">): Entry => (opts.other ? byOther(e) : signer.sign(e));
  const moved = sign(next("ws", headOf([g0]), 1001, "moved", { root: gOf(alice) }));
  const st: Served = { chain: [g0, moved], logs: [alice, bob], bodies: [open, member, station], posted: [], given: [], lacking: [], silent: false, brought: [] };
  first(st, { alice, bob, member, open });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    const serves = { takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs"] };
    const c = st.chain;
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: headOf(c), entries: c.filter((e) => e.seq > after), ...(after >= 0 && c[after] ? { after_hash: entryHash(c[after]!) } : {}), ...serves });
    }
    if (method === "GET" && path === "/lock/logs") return Effect.succeed({ chains: st.logs.map((l) => ({ genesis: gOf(l), entries: l.chain })) });
    if (method === "GET" && path === "/lock/bodies") return Effect.succeed({ bodies: st.bodies, lacking: st.lacking });
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    st.posted.push(`${method} ${path}`);
    // (silent: what it is brought it neither takes nor refuses)
    if (st.silent && method === "POST") return Effect.never;
    if (method === "POST" && path === "/lock") st.brought.push(...((body as { entries?: Entry[] })?.entries ?? []).map((e) => entryHash(e)));
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
  return { r, inner, st, alice, bob, bob2, g0, moved, run, told, who, member, open, signer, sign, headOf };
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

test("a body this device keeps that a station says it lacks is brought to it, once a read", async () => {
  const w = await setUp();
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(w.st.given, [], "none lacking: none brought");
  const h = bodyHash(w.member)!;
  w.st.bodies = w.st.bodies.filter((b) => b !== w.member);
  w.st.lacking = [h];
  await w.told();
  assert.deepEqual(w.st.given.map((b) => bodyHash(b)), [h], "the one it lacks, once");
  assert.equal(w.st.posted.filter((p) => p === "POST /lock/bodies").length, 1);
});

// ── made once (views/lock.ts `inForceOf`): the rules' state of the logs is made again only as what it is made of
// changes, or this device's clock passes a web page's `at - 600` or `exp` ──

test("the state in force is made once while what it is made of stands: a body come, a log changed, the clock past a web page's exp each make it again, once", async () => {
  const w = await setUp((st, x) => void (st.bodies = st.bodies.filter((b) => b !== x.member)));
  await w.run(read(w.inner, "ws"));
  // (the lock's topic made again, nothing it reads changed)
  const again = async () => {
    lockSeen(w.inner).touch("lock ws", "prompts");
    return await w.who();
  };
  await w.who();
  made.count = 0;
  await again();
  await again();
  assert.equal(made.count, 0, `the topic made twice, nothing changed: the state made before stands (made ${made.count} times)`);
  made.count = 0;
  w.st.bodies = [...w.st.bodies, w.member];
  await w.told();
  await again();
  assert.equal(made.count, 1, "a body taken: made again, once");
  assert.equal((await w.who()).members, bobs(w, true));
  made.count = 0;
  add(w.bob, "device.remove", { key: w.bob2.id });
  await w.told();
  await again();
  assert.equal(made.count, 1, "a log changed: made again, once");
  made.count = 0;
  await w.r.host.time.pass(400_000, 1000);
  await again();
  await again();
  assert.equal(made.count, 1, "past the web page's exp by this device's clock: made again, once");
  assert.equal(inForceOf(w.inner, "ws").f.devices.has(WEB), false, "and the web page is gone from it");
});

// ── the chain changing branch, waiting, the writers, what was pending ──

test("the chain changing branch to one without `moved`: the folded chain in force again, a writer signs again; back to one with it: the people's logs'", async () => {
  const w = await setUp(() => {}, { other: true });
  await w.run(read(w.inner, "ws"));
  assert.equal(inForceOf(w.inner, "ws").said, "on");
  // (at the moved one's place, by the same key: the fork choice goes by the hash)
  const at = (n: number, kind: string, body: unknown) => w.sign(next("ws", w.headOf([w.g0]), n, kind, body));
  let x: Entry | null = null;
  for (let n = 2000; n < 2100 && x === null; n++) {
    const e = at(n, "member", { sub: "s3", email: "c@x.com", role: "member" });
    if (entryHash(e) < entryHash(w.moved)) x = e;
  }
  let m2: Entry | null = null;
  for (let n = 3000; n < 3100 && m2 === null && x !== null; n++) {
    const e = at(n, "moved", { root: gOf(w.alice) });
    if (entryHash(e) < entryHash(x)) m2 = e;
  }
  assert.ok(x !== null && m2 !== null, "entries that win in turn");
  w.st.chain = [w.g0, x];
  await w.told();
  assert.equal(held(w.inner, "ws")!.head?.hash, entryHash(x), "on the branch without `moved`");
  const s = inForceOf(w.inner, "ws");
  assert.equal(s.said, "chain");
  assert.deepEqual([...s.f.members.keys()].sort(), ["s1", "s2", "s3"], "the folded chain's members");
  assert.equal((await w.who()).members.split("; ").map((m) => m.split(" ")[0]).join(","), "s1,s2,s3");
  stationLater(w.r.host, (req) => (req.method === "PATCH" && new URL(req.url).pathname === "/v1/workspaces/ws/members/s2" ? Promise.resolve(jsonResponse(200, { ok: true })) : undefined));
  let code: string | undefined;
  try {
    await w.r.ask("workspace.setRole", { account: "s1", workspace: "ws", member: "s2", role: "admin" });
  } catch (e) {
    code = (e as { code?: string }).code;
  }
  assert.notEqual(code, "lock_moved", "a writer signs on the chain again");
  assert.ok(w.st.posted.includes("POST /lock"), "and brings it to the station");
  w.st.chain = [w.g0, m2];
  await w.told();
  assert.equal(held(w.inner, "ws")!.head?.hash, entryHash(m2), "back on a branch with `moved`");
  assert.equal(inForceOf(w.inner, "ws").said, "on");
  assert.equal((await w.who()).members, bobs(w, true), "the people's logs' again");
});

test("waiting with the root's log here and its `open`'s body lacking: nobody and nothing listed; in force once the body comes", async () => {
  const w = await setUp((st, x) => void (st.bodies = st.bodies.filter((b) => b !== x.open)));
  await w.run(read(w.inner, "ws"));
  assert.ok(held(w.inner, "ws")!.entries.some((e) => e.kind === "moved"));
  const s = inForceOf(w.inner, "ws");
  assert.equal(s.said, "waiting");
  assert.deepEqual([s.f.members.size, s.f.devices.size, s.f.stations.size], [0, 0, 0], "nobody and nothing");
  const { v, members } = await w.who();
  assert.equal(members, "", "nobody");
  assert.equal(v.signers, 0);
  assert.equal(v.me.waiting, false, "this device is not asked to be approved");
  assert.ok(!(v.stations as any[]).some((x) => x.protected), "no station listed as the lock's");
  w.st.bodies = [...w.st.bodies, w.open];
  await w.told();
  assert.equal(inForceOf(w.inner, "ws").said, "on");
  assert.equal((await w.who()).members, bobs(w, true));
});

test("each writer by its own call on a moved chain, this device on no log of its person's, answers lock_moved but adding a member and an enrollment: nothing signed, nothing pending, nobody asked", async () => {
  const w = await setUp();
  await w.run(read(w.inner, "ws"));
  const members = [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }];
  stationLater(w.r.host, (req) => {
    const path = new URL(req.url).pathname;
    const ok = (b: unknown) => Promise.resolve(jsonResponse(200, b));
    if (req.method === "POST" && path === "/v1/workspaces/ws/members") return ok({ joined: [], added: ["d@x.com"], already: [], view: { members } });
    if (req.method === "POST" && path === "/v1/workspaces/ws/enrollments") return ok({ token: "tok", command: "stillfail station enroll https://x tok" });
    if ((req.method === "PATCH" || req.method === "DELETE") && path === "/v1/workspaces/ws/members/s2") return ok({ ok: true });
    if (req.method === "DELETE" && path === `/v1/workspaces/ws/stations/${A}`) return ok({ ok: true });
    return undefined;
  });
  const before = { held: held(w.inner, "ws")!.entries.length, cloud: w.r.cloud.posted.length, asked: w.r.host.secureAsked.length };
  const calls: [string, Record<string, unknown>][] = [
    ["workspace.addMembers", { account: "s1", workspace: "ws", role: "admin", emails: ["d@x.com"] }],
    ["workspace.setRole", { account: "s1", workspace: "ws", member: "s2", role: "admin" }],
    ["workspace.removeMember", { account: "s1", workspace: "ws", member: "s2" }],
    ["workspace.removeStation", { account: "s1", workspace: "ws", station: A }],
    ["workspace.enroll", { account: "s1", workspace: "ws", name: "mini" }],
    ["lock.renew", { workspace: "ws", device: WEB }],
    ["lock.disable", { workspace: "ws" }],
    ["lock.joinStation", { workspace: "ws", station: A }],
  ];
  const codes: string[] = [];
  for (const [name, params] of calls) {
    let code = "answered";
    try {
      await w.r.ask(name, params);
    } catch (e) {
      code = (e as { code?: string }).code ?? "no code";
    }
    codes.push(`${name} ${code}`);
  }
  // Approving a device: what views/pair.ts `approve` signs, its person admitted first where the lock has not heard of
  // them, then the device.
  for (const [name, e] of [
    ["admit", new Lock(w.inner, "ws", "s1", null).admit("r3", "c@x.com")],
    ["approve", new Lock(w.inner, "ws", "s1", null).append("device", { id: "d0".repeat(32), sub: "r2", kind: "app", label: "new" })],
  ] as const) {
    let code = "answered";
    await w.run(Effect.match(e as Effect.Effect<unknown, CoreError>, { onSuccess: () => {}, onFailure: (err) => void (code = err.code) }));
    codes.push(`${name} ${code}`);
  }
  // (adding a member is the cloud's part alone there and an enrollment's commands pin the chain held: both answer,
  // signing nothing, test/lock-admits.test.ts; the rest need this device on its person's own log, which it is not)
  const answers = new Set(["workspace.addMembers", "workspace.enroll"]);
  assert.deepEqual(codes, [...calls.map(([name]) => `${name} ${answers.has(name) ? "answered" : "lock_moved"}`), "admit lock_moved", "approve lock_moved"]);
  assert.equal(held(w.inner, "ws")!.entries.length, before.held, "nothing signed on the chain");
  assert.equal(pendingHeld(w.inner, "ws").length, 0, "nothing pending");
  assert.deepEqual(w.st.posted.filter((p) => p.startsWith("POST /lock") && p !== "POST /lock/bodies"), [], "nothing brought to the station");
  assert.equal(w.r.cloud.posted.length, before.cloud, "nothing sent to the cloud's lock");
  assert.equal(w.r.host.secureAsked.length, before.asked, "nobody asked");
});

test("the background writers on a moved chain, their causes present: a read signs nothing and asks nothing of the person", async () => {
  // (an entry of this device's at the moved one's place that loses to it: `again`'s cause; the genesis naming this
  // device and no lock of its person's own begun: `ownLockFor`'s, and from it `bindPerson`'s)
  const w = await setUp((st) => void (st.chain = [st.chain[0]!]));
  let x: Entry | null = null;
  for (let n = 2000; n < 2100 && x === null; n++) {
    const e = w.signer.sign(next("ws", w.headOf([w.g0]), n, "member", { sub: "s3", email: "c@x.com", role: "member" }));
    if (entryHash(e) > entryHash(w.moved)) x = e;
  }
  assert.ok(x !== null);
  w.st.chain = [w.g0, x];
  await w.run(read(w.inner, "ws"));
  for (let t = 0; t < 3000; t += 10) await w.r.host.time.pass(10);
  assert.equal(held(w.inner, "ws")!.head?.hash, entryHash(x));
  const before = { posted: w.st.posted.length, brought: w.st.brought.length, cloud: w.r.cloud.posted.length, asked: w.r.host.secureAsked.length, pending: pendingHeld(w.inner, "ws").length };
  w.st.chain = [w.g0, w.moved];
  await w.told();
  const h = held(w.inner, "ws")!;
  assert.equal(h.head?.hash, entryHash(w.moved), "moved");
  assert.ok((h.aside ?? []).some((e) => entryHash(e) === entryHash(x!)), "this device's own entry off the chain");
  for (const e of [bindPerson(w.inner, "ws"), keepToPerson(w.inner, "ws"), ownLockFor(w.inner, "ws"), Effect.sync(() => deliver(w.inner, "ws"))]) await w.run(e);
  for (let t = 0; t < 3000; t += 10) await w.r.host.time.pass(10);
  // (what a station showed and lacks now is carried to it, `carry`: the chain read for itself, nothing signed)
  const known = new Set([w.g0, x, w.moved].map((e) => entryHash(e)));
  assert.deepEqual(w.st.brought.slice(before.brought).filter((h) => !known.has(h)), [], "nothing signed brought to the station");
  assert.deepEqual(w.st.posted.slice(before.posted).filter((p) => p !== "POST /lock/bodies" && p !== "POST /lock"), [], "nothing else brought (no lock of the person's own begun)");
  assert.equal(w.r.cloud.posted.length, before.cloud, "nothing sent to the cloud's lock");
  assert.equal(w.r.host.secureAsked.length, before.asked, "nobody asked");
  assert.equal(held(w.inner, "ws")!.entries.length, h.entries.length, "nothing signed on the chain");
  assert.ok(pendingHeld(w.inner, "ws").length <= before.pending, "nothing pending more");
});

test("a change pending on a chain that then moves: failed, told as one that did not take effect, never waiting for ever", async () => {
  const w = await setUp((st) => void (st.chain = [st.chain[0]!]));
  await w.run(read(w.inner, "ws"));
  stationLater(w.r.host, (req) => (req.method === "PATCH" && new URL(req.url).pathname === "/v1/workspaces/ws/members/s2" ? Promise.resolve(jsonResponse(200, { ok: true })) : undefined));
  w.st.silent = true;
  const a = await w.r.ask("workspace.setRole", { account: "s1", workspace: "ws", member: "s2", role: "admin" });
  assert.equal(a?.pending?.state, "waiting", JSON.stringify(a));
  w.st.silent = false;
  w.st.chain = [w.g0, w.moved];
  await w.told();
  assert.equal(held(w.inner, "ws")!.head?.hash, entryHash(w.moved), "moved");
  assert.deepEqual(pendingHeld(w.inner, "ws").map((x) => x.state), ["failed"], "not waiting");
  const rows = (await w.who()).v.pending as any[];
  assert.deepEqual(rows.map((x) => x.state), ["failed"]);
  assert.match(rows[0].text, /没有生效|didn't take effect/);
});
