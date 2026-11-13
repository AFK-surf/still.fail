// A change of a moved workspace's list said as statements in this person's own log (src/lock-statements.ts,
// personal-lock.ts `say`, views/lock.ts `sayMoved`), end to end on a core: the person asked once; the entries on their
// log in order; the bodies at the workspace's stations the list names and at no other station, nor the cloud (every
// request read); the take-over (whom a removal would take out besides, said again first); a role changed; a station in
// and out; off and on again by the root alone; refused before anyone is asked where it would do nothing; pending while
// no station of the workspace answers, in effect once one does; nothing signed where the person says no.
//
// The world: `ws`, its chain the rig's genesis and a `moved` to a person log; its stations A (in the list) and C (the
// workspace's view lists it, the list does not). This device's person s1 has their own log (this device on it, its key
// known here); bob (r2) and xena (r3) theirs. `root: "me"`: s1's log is the root and says the settings, bob an admin
// and A a station; bob's says xena a member. `root: "alice"`: alice's log (r1) is the root and says those, and s1 as
// `mine` (an owner, or a member).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { type Entry as StationEntry, entryHash as stationHash } from "../../../station/src/cloud/lock.ts";
import { key, signed } from "../../../station/test/lock-world-sim.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, type Signer, entryHash, next } from "../src/lock.ts";
import { bodyHash, wsTag } from "../src/lock-moved.ts";
import { held, inForceOf, read, roster } from "../src/views/lock.ts";
import { hex, utf8 } from "../src/util.ts";
import { ME, genesis, grant, rig } from "./lock-rig.ts";

const A = "aa".repeat(32);
const C = "cc".repeat(32);
const T = Date.UTC(2026, 9, 6, 9, 0, 0) / 1000;
/// This device's key on s1's own log (its seed kept in the host's secure storage, as personal-lock.ts keeps it).
const MINE = 7001;
const seedOf = (n: number) => {
  const s = new Uint8Array(32);
  new DataView(s.buffer).setUint32(28, n);
  return s;
};

type Log = { sub: string; k: ReturnType<typeof key>; chain: StationEntry[]; said: string | null; n: number };
function person(sub: string, n: number, id: string): Log {
  const k = key(n);
  const g = signed({ v: 1, ws: `person:${sub}`, seq: 0, prev: null, at: T, kind: "genesis", body: { sub, device: { key: k.id, id, label: `${sub}'s app` } } } as Omit<StationEntry, "sig">, k);
  return { sub, k, chain: [g], said: null, n: 0 };
}
const gOf = (l: Log) => stationHash(l.chain[0]!);
function say(l: Log, kind: string, more: Record<string, unknown>): Record<string, unknown> {
  const b = { ws: "ws", kind, ...more, prev: l.said, salt: (++l.n + 0x5a00 * l.chain.length).toString(16).padStart(32, "0") };
  const h = bodyHash(b)!;
  const last = l.chain[l.chain.length - 1]!;
  l.chain.push(signed({ v: 1, ws: `person:${l.sub}`, seq: l.chain.length, prev: stationHash(last), at: T, kind: "ws", body: { t: wsTag("ws", gOf(l)), h } } as Omit<StationEntry, "sig">, l.k));
  l.said = h;
  return b;
}
const SETTINGS = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: { keys: [] } };

/// What a station was brought of a person's lock: by whom it was asked (its address), the chain's length, the bodies.
type Brought = { at: string; length: number; bodies: unknown[] | null };

async function setUp(o: { root?: "me" | "alice"; mine?: "owner" | "member" } = {}) {
  const me = person("s1", MINE, ME);
  const bob = person("r2", 6002, key(6102).hex);
  const xena = person("r3", 6004, key(6104).hex);
  const alice = person("r1", 6001, key(6101).hex);
  const root = o.root === "alice" ? alice : me;
  const bodies: unknown[] = [];
  bodies.push(say(root, "open", { ...SETTINGS, email: "a@x.com" }));
  if (o.root === "alice") bodies.push(say(alice, "member", { sub: "s1", email: "a@x.com", lock: gOf(me), role: o.mine ?? "owner" }));
  bodies.push(say(root, "member", { sub: "r2", email: "b@x.com", lock: gOf(bob), role: "admin" }));
  bodies.push(say(root, "station", { key: A }));
  bodies.push(say(bob, "member", { sub: "r3", email: "c@x.com", lock: gOf(xena), role: "member" }));
  const g = grant();
  let mine: Signer | null = null;
  const r = await rig((signer) => ((mine = signer), { ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME) }), (host) => {
    // (s1's own lock as this device pinned it before: its chain kept, its key's seed sealed, its id known)
    host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(me.chain)));
    host.storage.set("personal-signer-id", utf8(me.k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, [A, C], [A, C]);
  const inner = r.core.inner;
  const signer = mine! as Signer;
  const g0 = r.cloud.chains.get("ws")![0]!;
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c[c.length - 1]!), genesis: entryHash(c[0]!) });
  const moved = signer.sign(next("ws", headOf([g0]), 1001, "moved", { root: gOf(root) }));
  const st = { chain: [g0, moved] as Entry[], logs: [alice, bob, xena].filter((l) => l !== root || o.root === "alice"), bodies, brought: [] as Brought[], silent: false, own: me.chain as unknown as Entry[] };
  const answer = (at: string, method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    const serves = { takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) return Effect.succeed({ head: headOf(st.chain), entries: st.chain, ...serves });
    if (method === "GET" && path === "/lock/logs") return Effect.succeed({ chains: st.logs.map((l) => ({ genesis: gOf(l), entries: l.chain })) });
    if (method === "GET" && path === "/lock/bodies") return Effect.succeed({ bodies: st.bodies, lacking: [] });
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [{ genesis: entryHash(st.own[0]!), entries: st.own }] });
    if (st.silent && method === "POST") return Effect.never;
    if (method === "POST" && path === "/lock/person") {
      const b = body as { chain?: Entry[]; bodies?: unknown[] };
      const chain = b.chain ?? [];
      st.brought.push({ at, length: chain.length, bodies: b.bodies ?? null });
      if (chain.length > st.own.length) st.own = chain;
      for (const x of b.bodies ?? []) if (!st.bodies.some((y) => bodyHash(y) === bodyHash(x))) st.bodies.push(x);
      return Effect.succeed({ genesis: entryHash(chain[0]!), length: chain.length });
    }
    if (method === "POST") return Effect.succeed({ taken: 1, head: headOf(st.chain) });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if ((id === A || id === C) && path.startsWith("/lock")) return answer(`${ws}/${id === A ? "A" : "C"}`, method, path, body);
    return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>): Promise<{ ok?: X; error?: CoreError }> => {
    let out: { ok?: X; error?: CoreError } | null = null;
    inner.runner.fork(Effect.match(e, { onSuccess: (ok) => void (out = { ok }), onFailure: (error) => void (out = { error }) }));
    await r.host.time.passUntil(20_000, () => out !== null);
    assert.ok(out !== null, "no answer");
    await r.host.time.pass(100);
    return out;
  };
  await run(inner.adb.personal().refresh("s1"));
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  assert.equal(inner.adb.personal().standing("s1"), "member", "this device on its own lock");
  // What this device's own log says now, past what it said before: each statement's kind and whom, by its body.
  // (this device said again on it with the key it signs workspaces' locks with, as any act with the seed in hand does
  // where its entry lacks it: personal-lock.ts `#restate`; not a statement)
  const said = () => inner.adb.personal().entries("s1").slice(me.chain.length).filter((e) => e.kind === "ws").map((e) => {
    const h = (e.body as { h?: string }).h;
    const b = [...st.bodies, ...(inner.data.record("lockBodies", "ws") as { bodies?: unknown[] } | null)?.bodies ?? []].find((x) => bodyHash(x) === h) as Record<string, unknown> | undefined;
    return b === undefined ? `${e.kind} (no body)` : `${b.kind} ${b.sub ?? (b.key === A ? "A" : b.key === C ? "C" : "")}${b.role ? ` ${b.role}` : ""}`.trim();
  });
  const members = () => [...inForceOf(inner, "ws").f.members].map(([sub, m]) => `${sub} ${m.role}`).sort().join(", ");
  const asked = () => r.host.secureAsked.length;
  /// Every request the cloud was sent since the start that carries a body's salt: none may.
  const cloudBodies = () => r.host.requests.filter((q) => q.body !== null && q.body !== undefined && /"salt"/.test(typeof q.body === "string" ? q.body : new TextDecoder().decode(q.body as Uint8Array)));
  return { r, inner, st, run, said, members, asked, cloudBodies, me, bob, xena };
}

test("taking bob out: the person asked once, xena whom he let in said again first, the bodies at A alone, the chain at C, nothing at the cloud", async () => {
  const w = await setUp();
  assert.equal(w.members(), "r2 admin, r3 member, s1 owner");
  const before = w.asked();
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r2", gone: true }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.deepEqual(w.said(), ["member r3 member", "member.remove r2"], "xena said again, then bob taken out, on s1's own log in that order");
  assert.equal(w.members(), "r3 member, s1 owner", "xena stays");
  const withBodies = w.st.brought.filter((b) => b.bodies !== null);
  assert.ok(withBodies.length > 0 && withBodies.every((b) => b.at === "ws/A"), `the bodies brought to A alone: ${JSON.stringify(withBodies.map((b) => b.at))}`);
  assert.deepEqual(withBodies[0]!.bodies!.map((b) => (b as { kind: string }).kind), ["member", "member.remove"], "both, with their chain");
  assert.ok(w.st.brought.some((b) => b.at.endsWith("/C") && b.bodies === null), "C, which the list does not name, brought the chain alone");
  assert.deepEqual(w.cloudBodies().map((q) => q.url), [], "no body sent to the cloud");
});

test("a role lowered: the removal and the admit with the log that binds bob now, xena whom he let in as an admin said again", async () => {
  const w = await setUp();
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r2", role: "member" }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.deepEqual(w.said(), ["member r3 member", "member.remove r2", "member r2 member"]);
  assert.equal(w.members(), "r2 member, r3 member, s1 owner");
});

test("a station taken in (C, which the workspace lists) and A taken out: C given the bodies from its own on", async () => {
  const w = await setUp();
  const inC = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.joinStation", { workspace: "ws", station: C }), catch: (e) => e as CoreError }));
  assert.equal(inC.error, undefined, inC.error?.message);
  assert.deepEqual([...inForceOf(w.inner, "ws").f.stations.keys()].sort(), [A, C].sort());
  assert.ok(w.st.brought.some((b) => b.at === "ws/C" && b.bodies !== null), "C brought the body that takes it in");
  const outA = await w.run(roster(w.inner, "s1", "ws", { station: A }));
  assert.equal(outA.error, undefined, outA.error?.message);
  assert.deepEqual(w.said(), ["station C", "station.remove A"]);
  assert.deepEqual([...inForceOf(w.inner, "ws").f.stations.keys()], [C]);
});

test("off and on again by the root's person; another owner refused with lock_root_only, nobody asked", async () => {
  const w = await setUp();
  const off = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(off.error, undefined, off.error?.message);
  assert.equal(inForceOf(w.inner, "ws").said, "off");
  const on = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.open", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(on.error, undefined, on.error?.message);
  assert.equal(inForceOf(w.inner, "ws").said, "on");
  assert.deepEqual(w.said(), ["off", "open"]);
  const o = await setUp({ root: "alice" });
  const before = o.asked();
  const refused = await o.run(Effect.tryPromise({ try: () => o.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal((refused.error as { code?: string } | undefined)?.code, "lock_root_only");
  assert.equal(o.asked(), before, "nobody asked");
  assert.deepEqual(o.said(), [], "nothing signed");
});

test("an act that would have no effect (a member taking an admin out) is refused before the person is asked", async () => {
  const w = await setUp({ root: "alice", mine: "member" });
  const before = w.asked();
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r2", gone: true }));
  assert.equal(out.error?.code, "forbidden");
  assert.equal(w.asked(), before, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing signed");
  assert.equal(w.members(), "r1 owner, r2 admin, r3 member, s1 member");
});

test("no station of the workspace answering: pending, its stations named, in effect once one answers, nothing lost", async () => {
  const w = await setUp();
  w.st.silent = true;
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r2", gone: true }));
  assert.equal(out.error, undefined, out.error?.message);
  const row = (out.ok as { pending?: { stations: string[]; state: string } } | null)?.pending;
  assert.equal(row?.state, "waiting", "pending");
  assert.deepEqual(row?.stations, ["studio"], "waiting for A, the workspace's station the list names");
  assert.equal(w.members(), "r2 admin, r3 member, s1 owner", "not in effect while pending");
  w.st.silent = false;
  await w.run(w.inner.adb.personal().refresh("s1"));
  await w.r.host.time.pass(5000);
  assert.deepEqual(w.said(), ["member r3 member", "member.remove r2"]);
  assert.equal(w.members(), "r3 member, s1 owner", "in effect once A took them");
  assert.equal(w.inner.adb.personal().pending("s1").length, 0, "nothing pending");
  assert.deepEqual(w.cloudBodies().map((q) => q.url), [], "no body sent to the cloud");
});

test("the person refusing the ask: nothing signed, nothing pending", async () => {
  const w = await setUp();
  w.r.host.secureRefused = true;
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r2", gone: true }));
  assert.ok(out.error !== undefined, "refused");
  assert.deepEqual(w.said(), []);
  assert.equal(w.inner.adb.personal().pending("s1").length, 0);
  assert.equal(w.st.brought.length, 0, "nothing brought");
});
