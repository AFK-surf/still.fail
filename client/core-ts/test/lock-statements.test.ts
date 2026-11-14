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
import { Core } from "../src/core.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, type Signer, entryHash, next } from "../src/lock.ts";
import { bodyHash, wsTag } from "../src/lock-moved.ts";
import { held, inForceOf, movedHere, movedWorks, read, roster, safeMode } from "../src/views/lock.ts";
import { joinable } from "../src/views/memberships.ts";
import { jsonResponse } from "../src/testing.ts";
import { hex, utf8 } from "../src/util.ts";
import { HostWire } from "../src/station/wire.ts";
import { ME, committed, genesis, givesTo, grant, rig, stationState, withoutMesh } from "./lock-rig.ts";
import { stationLater } from "./station-fixture.ts";

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

type Log = { sub: string; k: ReturnType<typeof key>; chain: StationEntry[]; said: string | null; said2?: string | null; n: number };
function person(sub: string, n: number, id: string): Log {
  const k = key(n);
  const g = signed({ v: 1, ws: `person:${sub}`, seq: 0, prev: null, at: T, kind: "genesis", body: { sub, device: { key: k.id, id, label: `${sub}'s app` } } } as Omit<StationEntry, "sig">, k);
  return { sub, k, chain: [g], said: null, n: 0 };
}
const gOf = (l: Log) => stationHash(l.chain[0]!);
function say(l: Log, kind: string, more: Record<string, unknown>, ws: "ws" | "w2" = "ws"): Record<string, unknown> {
  const b = { ws, kind, ...more, prev: ws === "ws" ? l.said : (l.said2 ?? null), salt: (++l.n + 0x5a00 * l.chain.length).toString(16).padStart(32, "0") };
  const h = bodyHash(b)!;
  const last = l.chain[l.chain.length - 1]!;
  l.chain.push(signed({ v: 1, ws: `person:${l.sub}`, seq: l.chain.length, prev: stationHash(last), at: T, kind: "ws", body: { t: wsTag(ws, gOf(l)), h } } as Omit<StationEntry, "sig">, l.k));
  if (ws === "ws") l.said = h;
  else l.said2 = h;
  return b;
}
const SETTINGS = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: { keys: [] } };

/// What a station was brought of a person's lock: by whom it was asked (its address), the chain's length, the bodies.
type Brought = { at: string; length: number; bodies: unknown[] | null };
/// Every request a station of the rig got: by whom it was asked (its address), how, and what it carried, as JSON.
type Asked = { at: string; method: string; path: string; body: string };
/// The stations of w2 (`two`): B in its list, D listed by its view alone.
const B = "bb".repeat(32);
const D = "dd".repeat(32);

/// s1's other devices (`devices`): D2 and D3, put on s1's own log by this device before anything is said.
const D2 = key(7002);
const D3 = key(7003);
/// An entry of s1's own log signed by `by` after `chain`, at its head's time.
function onOwn(chain: StationEntry[], by: ReturnType<typeof key>, kind: string, body: unknown): StationEntry {
  const last = chain[chain.length - 1]!;
  return signed({ v: 1, ws: last.ws, seq: chain.length, prev: stationHash(last), at: last.at, kind, body } as Omit<StationEntry, "sig">, by);
}

/// `root: "lost"`: s1's lost log the root (every device of it gone), which took s1 out by its own genesis and admitted
/// s1 again by this device's log as an owner (`~root` out, rules/AGENTS.md): s1 bound by a real admit.
async function setUp(o: { root?: "me" | "alice" | "lost"; mine?: "owner" | "member"; devices?: boolean; two?: boolean } = {}) {
  const me = person("s1", MINE, ME);
  if (o.devices) for (const [k, n] of [[D2, "d2"], [D3, "d3"]] as const) me.chain.push(onOwn(me.chain, me.k, "device", { key: k.id, id: n.repeat(32), label: `s1's ${n}` }));
  const bob = person("r2", 6002, key(6102).hex);
  const xena = person("r3", 6004, key(6104).hex);
  const alice = person("r1", 6001, key(6101).hex);
  const lost = person("s1", 6009, key(6109).hex);
  const root = o.root === "alice" ? alice : o.root === "lost" ? lost : me;
  const bodies: unknown[] = [];
  bodies.push(say(root, "open", { ...SETTINGS, email: "a@x.com" }));
  // (the chain's own list, the rig's genesis: s1 its owner, s2 a member, carried once it moved until a removal of each
  // is said, rules `state4_moved`; the root says one of each but its own person, so what follows says the list alone)
  bodies.push(say(root, "member.remove", { sub: "s2", cancels: [] }));
  if (o.root === "alice") bodies.push(say(alice, "member.remove", { sub: "s1", cancels: [] }));
  if (o.root === "alice") bodies.push(say(alice, "member", { sub: "s1", email: "a@x.com", lock: gOf(me), role: o.mine ?? "owner" }));
  if (o.root === "lost") bodies.push(say(lost, "member.remove", { sub: "s1", cancels: [gOf(lost)] }), say(lost, "member", { sub: "s1", email: "a@x.com", lock: gOf(me), role: "owner" }));
  bodies.push(say(root, "member", { sub: "r2", email: "b@x.com", lock: gOf(bob), role: "admin" }));
  bodies.push(say(root, "station", { key: A }));
  bodies.push(say(bob, "member", { sub: "r3", email: "c@x.com", lock: gOf(xena), role: "member" }));
  // (w2, where `two`: rooted in s1's log too, B its station)
  const bodies2: unknown[] = [];
  if (o.two) bodies2.push(say(me, "open", { ...SETTINGS, email: "a@x.com" }, "w2"), say(me, "member.remove", { sub: "s2", cancels: [] }, "w2"), say(me, "station", { key: B }, "w2"));
  const g = grant();
  let mine: Signer | null = null;
  const r = await rig((signer) => ((mine = signer), { ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME), ...(o.two ? { w2: genesis("w2", signer, true, [{ key: B, name: "b" }], g.keys, ME) } : {}) }), (host) => {
    // (s1's own lock as this device pinned it before: its chain kept, its key's seed sealed, its id known)
    host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(me.chain)));
    host.storage.set("personal-signer-id", utf8(me.k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, [A, C], [A, C], undefined, o.two ? [B, D] : []);
  const inner = r.core.inner;
  const signer = mine! as Signer;
  const g0 = r.cloud.chains.get("ws")![0]!;
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c[c.length - 1]!), genesis: entryHash(c[0]!) });
  const moved = signer.sign(next("ws", headOf([g0]), 1001, "moved", { root: gOf(root) }));
  const st = { chain: [g0, moved] as Entry[], logs: [alice, bob, xena, ...(o.root === "lost" ? [lost] : [])], bodies, brought: [] as Brought[], silent: false, own: me.chain as unknown as Entry[], asked: [] as Asked[], reset: false, opened: [] as Entry[][], rootout: false };
  const g2 = o.two ? r.cloud.chains.get("w2")![0]! : null;
  const st2 = { chain: g2 === null ? [] : [g2, signer.sign(next("w2", headOf([g2]), 1001, "moved", { root: gOf(me) }))] as Entry[], logs: [] as Log[], bodies: bodies2, brought: [] as Brought[], silent: false };
  // (each workspace's stations its own chain, logs and bodies; s1's own log the same at all of them)
  const answer = (at: string, method: string, path: string, body: unknown, x: Omit<typeof st, "own" | "asked" | "reset" | "opened" | "rootout"> = st): Effect.Effect<unknown, CoreError> => {
    st.asked.push({ at, method, path, body: JSON.stringify(body ?? null) });
    const serves = { takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs", ...(st.rootout ? ["rootout"] : [])] };
    // (`reset`: every station of ws reset on its machine, `stillfail lock reset`: none kept, a genesis brought pinned, as
    // station/src/mesh/serve.ts `lockRoute` pins one its owner's device brings where none is)
    if (x === st && st.reset && path.startsWith("/lock") && !path.startsWith("/lock/person")) {
      if (method === "GET" && (path === "/lock" || path.startsWith("/lock?"))) return Effect.succeed({ head: null, entries: [], ...serves });
      if (method === "GET" && path === "/lock/logs") return Effect.succeed({ chains: [] });
      if (method === "GET" && path === "/lock/bodies") return Effect.succeed({ bodies: [], lacking: [] });
      if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
      if (method === "POST" && path === "/lock") {
        const es = ((body as { entries?: Entry[] })?.entries ?? []) as Entry[];
        st.opened.push(es);
        return Effect.succeed({ taken: es.length, head: headOf(es) });
      }
    }
    // (what the station keeps as a station does: the lock only where its list names it, a station the list does not
    // name keeping none, as one the chain never named (`keeps`); the logs and bodies given only to a device that list names)
    const logs = [st.own, ...x.logs.map((l) => l.chain as unknown as Entry[])];
    const id = at.endsWith("/A") ? A : at.endsWith("/C") ? C : at.endsWith("/B") ? B : D;
    const f = stationState(at.split("/")[0]!, x.chain, logs, x.bodies, r.host.nowMs());
    // (A and B pinned their chain, whose genesis names them; C and D keep it only once its list names them)
    const keeps = id === A || id === B || f.f.stations.has(id);
    const gives = keeps && givesTo(at.split("/")[0]!, x.chain, logs, x.bodies, r.host.nowMs(), ME);
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) return Effect.succeed(keeps ? { head: headOf(x.chain), entries: x.chain, ...serves } : { head: null, entries: [], ...serves });
    if (method === "GET" && path === "/lock/logs") return Effect.succeed({ chains: gives ? x.logs.map((l) => ({ genesis: gOf(l), entries: l.chain })) : [] });
    if (method === "GET" && path === "/lock/bodies") return Effect.succeed(gives ? { bodies: x.bodies, lacking: [] } : { bodies: [], lacking: [] });
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [{ genesis: entryHash(st.own[0]!), entries: st.own }] });
    if (x.silent && method === "POST") return Effect.never;
    if (method === "POST" && path === "/lock/person") {
      const b = body as { chain?: Entry[]; bodies?: unknown[] };
      const chain = b.chain ?? [];
      x.brought.push({ at, length: chain.length, bodies: b.bodies ?? null });
      if (chain.length > st.own.length) st.own = chain;
      // (a body taken only by a station keeping the workspace's lock, against an entry kept that commits to it)
      const kept = [st.own, ...x.logs.map((l) => l.chain as unknown as Entry[])];
      for (const n of b.bodies ?? []) if (keeps && committed(at.split("/")[0]!, kept, n) && !x.bodies.some((y) => bodyHash(y) === bodyHash(n))) x.bodies.push(n);
      return Effect.succeed({ genesis: entryHash(chain[0]!), length: chain.length });
    }
    if (method === "POST") return Effect.succeed({ taken: 1, head: headOf(x.chain) });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  // (the rig's stations reached by a core: this one, or one started anew on the same host)
  const reach = (at: typeof inner) => {
    const original = at.stations.requests.call.bind(at.stations.requests);
    at.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
      const [ws, id] = addr.toString().split("/");
      if ((id === A || id === C) && path.startsWith("/lock")) return answer(`${ws}/${id === A ? "A" : "C"}`, method, path, body);
      if ((id === B || id === D) && path.startsWith("/lock")) return answer(`${ws}/${id === B ? "B" : "D"}`, method, path, body, st2);
      return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
    }) as typeof at.stations.requests.call;
  };
  reach(inner);
  const run = async <X>(e: Effect.Effect<X, any>, on: typeof inner = inner): Promise<{ ok?: X; error?: CoreError }> => {
    let out: { ok?: X; error?: CoreError } | null = null;
    on.runner.fork(Effect.match(e, { onSuccess: (ok) => void (out = { ok }), onFailure: (error) => void (out = { error }) }));
    await r.host.time.passUntil(20_000, () => out !== null);
    assert.ok(out !== null, "no answer");
    await r.host.time.pass(100);
    return out;
  };
  await run(inner.adb.personal().refresh("s1"));
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  if (o.two) {
    await run(read(inner, "w2"));
    assert.equal(held(inner, "w2")?.entries.at(-1)?.kind, "moved", "w2's chain held moved");
  }
  assert.equal(inner.adb.personal().standing("s1"), "member", "this device on its own lock");
  // What this device's own log says now, past what it said before: each statement's kind and whom, by its body.
  // (this device said again on it with the key it signs workspaces' locks with, as any act with the seed in hand does
  // where its entry lacks it: personal-lock.ts `#restate`; not a statement)
  const said = (by?: string) => inner.adb.personal().entries("s1").slice(me.chain.length).filter((e) => e.kind === "ws" && (by === undefined || e.sig?.key === by)).map((e) => {
    const h = (e.body as { h?: string }).h;
    const b = [...st.bodies, ...(inner.data.record("lockBodies", "ws") as { bodies?: unknown[] } | null)?.bodies ?? []].find((x) => bodyHash(x) === h) as Record<string, unknown> | undefined;
    return b === undefined ? `${e.kind} (no body)` : `${b.kind} ${b.sub ?? (b.key === A ? "A" : b.key === C ? "C" : "")}${b.role ? ` ${b.role}` : ""}`.trim();
  });
  const members = () => [...inForceOf(inner, "ws").f.members].map(([sub, m]) => `${sub} ${m.role}`).sort().join(", ");
  const asked = () => r.host.secureAsked.length;
  /// Every request the cloud was sent since the start that carries a body's salt: none may.
  const cloudBodies = () => r.host.requests.filter((q) => q.body !== null && q.body !== undefined && /"salt"/.test(typeof q.body === "string" ? q.body : new TextDecoder().decode(q.body as Uint8Array)));
  return { r, inner, st, st2, run, reach, said, members, asked, cloudBodies, me, bob, xena, lostOff: (more?: (lost: Record<string, unknown>[]) => Record<string, unknown>[], o?: { closed?: boolean }) => lostOff({ inner, st, run, me, r }, more, o) };
}

/// This device's statements past what s1's log said before, then a read that moves s1's own log off them with no seed
/// in hand: D2 takes D3 off at the place the first hung (winning there by the rules' second step, a removal), then says
/// `more` (what it says, as bodies but for `prev` and `salt`), their bodies at the workspace's stations. The statements
/// lost, their entries and bodies.
async function lostOff(w: { inner: any; st: any; run: <X>(e: Effect.Effect<X, any>) => Promise<{ ok?: X; error?: CoreError }>; me: Log; r: any }, more: (lost: Record<string, unknown>[]) => Record<string, unknown>[] = () => [], o: { closed?: boolean } = {}) {
  const personal = w.inner.adb.personal();
  const own = personal.entries("s1") as unknown as StationEntry[];
  const at = own.findIndex((e, i) => i >= w.me.chain.length && e.kind === "ws");
  assert.ok(at > 0, "a statement pinned");
  const base = own.slice(0, at);
  const kept = [...w.st.bodies, ...((w.inner.data.record("lockBodies", "ws") as { bodies?: unknown[] } | null)?.bodies ?? [])];
  const entries = own.slice(at).filter((e) => e.kind === "ws");
  const lost = entries.map((e) => kept.find((b) => bodyHash(b) === (e.body as { h: string }).h) as Record<string, unknown>);
  const chain = [...base, onOwn(base, D2, "device.remove", { key: D3.id })];
  let prev: string | null = w.me.said;
  let n = 0;
  for (const s of more(lost)) {
    const b = { ...s, ws: "ws", prev, salt: (0xd200 + ++n).toString(16).padStart(32, "0") };
    prev = bodyHash(b)!;
    chain.push(onOwn(chain, D2, "ws", { t: wsTag("ws", gOf(w.me)), h: prev }));
    w.st.bodies.push(b);
  }
  w.st.own = chain as unknown as Entry[];
  if (o.closed) return { lost, entries: entries as unknown as Entry[] };
  await w.run(personal.refresh("s1"));
  await w.run(read(w.inner, "ws"));
  await w.r.host.time.pass(1000);
  return { lost, entries: entries as unknown as Entry[] };
}

/// What a body says, but for the one before it and its salt.
const meaning = (b: Record<string, unknown>) => {
  const { prev: _p, salt: _s, ...said } = b;
  return said;
};

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

// The door a station keeping no lock pins one by, as before a move (`joinStation` brings it the whole chain): the chain
// as it moved brought to C with the logs and bodies its state is made of once that state names it (station/src/mesh/
// moved-pin.ts `pinBrought`). 2026-11-14, the locks' end to end, round 17 run moved: 「保护」 left the station unprotected.
test("a station taken in after the move (C): the chain as it moved brought to it with the logs and bodies that name it", async () => {
  const w = await setUp();
  const inC = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.joinStation", { workspace: "ws", station: C }), catch: (e) => e as CoreError }));
  assert.equal(inC.error, undefined, inC.error?.message);
  const posted = w.st.asked.filter((a) => a.at === "ws/C" && a.method === "POST" && a.path === "/lock").map((a) => JSON.parse(a.body) as { entries?: Entry[]; logs?: Entry[][]; bodies?: unknown[] });
  assert.equal(posted.length, 1, `brought once: ${JSON.stringify(w.st.asked.filter((a) => a.at === "ws/C").map((a) => `${a.method} ${a.path}`))}`);
  assert.equal(posted[0]!.entries?.at(-1)?.kind, "moved", "the chain as it moved");
  assert.ok((posted[0]!.logs?.length ?? 0) >= 2, "the logs");
  assert.ok((posted[0]!.bodies ?? []).some((b) => (b as { kind?: string; key?: string }).kind === "station" && (b as { key?: string }).key === C), "the body that names it among the bodies");
});

// Not reached at the press: brought as that station is next read, nothing pressed again (the lead, 2026-11-14: as an
// unmoved chain's `station` entry reaches its station whenever it is next read).
test("a station taken in after the move, unreachable at the press: brought the chain, logs and bodies as it is next read, nothing pressed", async () => {
  const w = await setUp();
  // (C keeps no lock until a POST /lock reaches it; unreachable until `up`)
  let up = false;
  let pinned = false;
  const posts: string[] = [];
  const through = w.inner.stations.requests.call.bind(w.inner.stations.requests);
  w.inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    if (addr.toString().endsWith(`/${C}`) && path.startsWith("/lock")) {
      if (method === "POST" && path === "/lock") {
        posts.push(up ? "reached" : "unreachable");
        if (!up) return Effect.fail(new CoreError("station_offline", "not reached"));
        pinned = true;
        return Effect.succeed({ taken: 2, head: null });
      }
      if (!up) return Effect.fail(new CoreError("station_offline", "not reached"));
      if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after=")) && !pinned) return Effect.succeed({ head: null, entries: [], takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs"] });
    }
    return (through as (...x: unknown[]) => Effect.Effect<unknown, CoreError>)(addr, method, path, body, ...rest);
  }) as typeof w.inner.stations.requests.call;
  const asked = w.asked();
  const inC = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.joinStation", { workspace: "ws", station: C }), catch: (e) => e as CoreError }));
  assert.equal(inC.error, undefined, inC.error?.message);
  assert.deepEqual(posts, ["unreachable"], "tried at the press");
  up = true;
  await w.run(read(w.inner, "ws"));
  console.log(`C brought: ${posts.join(", ")}; asked ${w.asked() - asked}`);
  assert.deepEqual(posts, ["unreachable", "reached"], "brought as it was next read");
  assert.equal(w.asked() - asked, 1, "the person asked once, at the press");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(posts, ["unreachable", "reached"], "not brought again once taken");
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

test("添加 station goes by the lock held, not the workspace's view: moved and on, in safe mode though the view says nothing; off, out of it though the view says locked", async () => {
  const w = await setUp();
  // (the view as a cloud of today has it after a handover: `locked` for good, the chain's last entry being `moved`)
  const viewSays = (locked: boolean) => w.inner.data.update({ topic: "workspace", workspace: "ws" }, (v: any) => {
    const { locked: _, ...rest } = v;
    return locked ? { ...rest, locked: true } : rest;
  });
  // (the account's list naming s1 an owner of both, as the cloud's does: who may add a station there)
  for (const a of w.inner.accounts.list()) {
    const me = w.inner.data.record("me", a.sub) as { workspaces: object[] };
    w.inner.data.put("me", a.sub, { ...me, workspaces: me.workspaces.map((x) => ({ ...x, role: "owner" })) });
  }
  // ws's stations offered to w2 (no lock held there, its view saying none): to be picked only while ws is not in safe mode
  const needsLock = () => (joinable(w.inner, "w2").items as { id: string; needsLock?: boolean }[]).filter((s) => s.id === A || s.id === C).map((s) => s.needsLock === true);
  viewSays(false);
  assert.deepEqual(needsLock(), [true, true], "on: they need w2 in safe mode");
  const off = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(off.error, undefined, off.error?.message);
  assert.equal(inForceOf(w.inner, "ws").said, "off");
  viewSays(true);
  // (what the lock held says kept beside it in a turn of its own, as the state is made anew)
  await w.r.host.time.pass(100);
  assert.deepEqual(needsLock(), [false, false], "off: to be picked");
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

// Taking off or renewing someone else's app device where the chain moved: theirs alone, on their own log (the root
// AGENTS.md: owners and admins take a member out, never one device of someone else's), refused in words that say so
// and what to do instead (2026-11-14: `lock_moved`'s English named what people are never told).
test("an owner taking another member's app device off: refused in words that say it is theirs alone and to take the member out; nobody asked, nothing signed", async () => {
  const w = await setUp();
  const theirs = [...inForceOf(w.inner, "ws").f.devices.values()].find((d) => d.kind === "app" && d.sub !== "s1");
  assert.ok(theirs !== undefined, "another member's app in the state");
  const before = w.asked();
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.removeDevice", { workspace: "ws", device: theirs.id }), catch: (e) => e as CoreError }));
  assert.equal(out.error?.message, "此设备属于其他成员，只能由其本人移除；要让此成员不能再访问，请将其移出 workspace");
  assert.equal(w.asked(), before, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing signed");
});

// An app device of the person's own renewed where the chain moved: its log lets it in with no expiry (the rules' state
// says none for an app), so there is nothing to renew and nothing to refuse. Before, it was refused in the words for
// another member's device (2026-11-14, the locks' end to end on main after #6102: "B lock.renew: 此设备属于其他成员…").
test("renewing this person's own app device where the chain moved: done with nothing to do (an app does not run out there); not refused as another's, nobody asked, nothing signed", async () => {
  const w = await setUp();
  const mine = inForceOf(w.inner, "ws").f.devices.get(ME);
  assert.equal(mine?.kind, "app", "this device's app in the state");
  assert.equal(mine?.exp, undefined, "with no expiry");
  const before = w.asked();
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.renew", { workspace: "ws", device: ME }), catch: (e) => e as CoreError }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), before, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing signed");
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

/// The next act with the seed in hand: C taken in (the workspace lists it, the list does not).
const takeC = (w: Awaited<ReturnType<typeof setUp>>) => w.run(Effect.tryPromise({ try: () => w.r.ask("lock.joinStation", { workspace: "ws", station: C }), catch: (e) => e as CoreError }));
const hOf = (e: Entry) => (e.body as { h: string }).h;
/// This device's statements on s1's log past what it said before.
const mineOn = (w: Awaited<ReturnType<typeof setUp>>) => w.inner.adb.personal().entries("s1").slice(w.me.chain.length).filter((e) => e.kind === "ws" && e.sig?.key === w.me.k.id);

test("a role lowered, its statements lost together with no seed in hand: told as not in effect, nobody asked; the next act signs them again first, in the order made, with the same bodies, bob ending a member", async () => {
  const w = await setUp({ devices: true });
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r2", role: "member" }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.deepEqual(w.said(), ["member r3 member", "member.remove r2", "member r2 member"]);
  const asked = w.asked();
  const { entries } = await w.lostOff();
  assert.equal(w.asked(), asked, "nobody asked");
  assert.deepEqual(w.said(), [], "off the chain pinned");
  assert.equal(w.members(), "r2 admin, r3 member, s1 owner", "not in effect");
  const rows = w.inner.adb.personal().pending("s1");
  assert.deepEqual(rows.map((x) => x.state), ["failed"], `told as not in effect, the change meant: ${JSON.stringify(rows)}`);
  const inC = await takeC(w);
  assert.equal(inC.error, undefined, inC.error?.message);
  assert.equal(w.asked() - asked, 1, "the person asked once, for C");
  assert.deepEqual(w.said(), ["member r3 member", "member.remove r2", "member r2 member", "station C"], "signed again first, in the order made");
  assert.deepEqual(mineOn(w).slice(0, 3).map(hOf), entries.map(hOf), "the same bodies: each one's prev still before it");
  assert.equal(w.members(), "r2 member, r3 member, s1 owner", "bob a member, as meant");
  assert.deepEqual(w.inner.adb.personal().pending("s1"), [], "nothing left to tell");
  assert.deepEqual(w.cloudBodies().map((q) => q.url), [], "no body sent to the cloud");
});

test("lost, then someone else (s1's D2) says bob is an admin since: what is about bob let be and told, xena said again", async () => {
  const w = await setUp({ devices: true });
  await w.run(roster(w.inner, "s1", "ws", { member: "r2", role: "member" }));
  await w.lostOff((lost) => [{ ...meaning(lost[2]!), role: "admin" }]);
  const inC = await takeC(w);
  assert.equal(inC.error, undefined, inC.error?.message);
  assert.deepEqual(w.said(w.me.k.id), ["member r3 member", "station C"], "the removal and the admit of bob not signed again");
  assert.equal(w.members(), "r2 admin, r3 member, s1 owner");
  const rows = w.inner.adb.personal().pending("s1");
  assert.deepEqual(rows.map((x) => x.state), ["failed"], `told: ${JSON.stringify(rows)}`);
});

test("lost, then D2 says xena otherwise since: xena let be, and the removal and the admit of bob signed again with new bodies, their prev gone", async () => {
  const w = await setUp({ devices: true });
  await w.run(roster(w.inner, "s1", "ws", { member: "r2", role: "member" }));
  const { entries } = await w.lostOff((lost) => [{ ...meaning(lost[0]!), role: "admin" }]);
  const inC = await takeC(w);
  assert.equal(inC.error, undefined, inC.error?.message);
  assert.deepEqual(w.said(w.me.k.id), ["member.remove r2", "member r2 member", "station C"]);
  const again = mineOn(w).slice(0, 2).map(hOf);
  assert.ok(again.every((h) => !entries.map(hOf).includes(h)), "new bodies");
  assert.equal(w.members(), "r2 member, r3 admin, s1 owner");
  assert.deepEqual(w.inner.adb.personal().pending("s1"), [], "nothing to tell: what the person meant took effect");
});

test("lost, then D2 says the same since: nothing signed again, nothing told", async () => {
  const w = await setUp({ devices: true });
  await w.run(roster(w.inner, "s1", "ws", { member: "r2", gone: true }));
  await w.lostOff((lost) => lost.map(meaning));
  const inC = await takeC(w);
  assert.equal(inC.error, undefined, inC.error?.message);
  assert.deepEqual(w.said(w.me.k.id), ["station C"]);
  assert.equal(w.members(), "r3 member, s1 owner");
  assert.deepEqual(w.inner.adb.personal().pending("s1"), []);
});

/// What a request carried, as text.
const textOf = (b: unknown) => (b === null || b === undefined ? "" : typeof b === "string" ? b : new TextDecoder().decode(b as Uint8Array));

for (const where of ["ws", "w2"] as const) {
  test(`a person in two moved workspaces, an act in ${where}: its bodies at its stations the list names alone; the other's stations the chain alone; the cloud only the entries, a tag and a hash each`, async () => {
    const w = await setUp({ two: true });
    const other = where === "ws" ? "w2" : "ws";
    const kept = (ws: string) => ((w.inner.data.record("lockBodies", ws) as { bodies?: { salt?: string }[] } | null)?.bodies ?? []);
    const had = new Set(kept(where).map((b) => b.salt));
    const fromAsked = w.st.asked.length, fromCloud = w.r.host.requests.length;
    // (in ws bob taken out; in w2 D taken in, which its view lists and its list does not)
    const out = where === "ws" ? await w.run(roster(w.inner, "s1", "ws", { member: "r2", gone: true })) : await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.joinStation", { workspace: "w2", station: D }), catch: (e) => e as CoreError }));
    assert.equal(out.error, undefined, out.error?.message);
    await w.r.host.time.pass(2000);
    const salts = kept(where).map((b) => b.salt!).filter((x) => !had.has(x));
    assert.ok(salts.length > 0, "statements made");
    const asked = w.st.asked.slice(fromAsked);
    const named = where === "ws" ? ["ws/A"] : ["w2/B", "w2/D"];
    const carries = (q: Asked) => /"bodies"/.test(q.body) || (q.method === "POST" && q.path === "/lock/bodies") || salts.some((x) => q.body.includes(x));
    assert.deepEqual([...new Set(asked.filter(carries).map((q) => q.at))].sort(), named, "the bodies at the stations of the workspace the list names alone");
    const there = asked.filter((q) => q.at.startsWith(`${other}/`));
    assert.ok(there.some((q) => q.method === "POST" && q.path === "/lock/person" && /"chain"/.test(q.body)), `${other}'s stations brought the chain: ${JSON.stringify(there.map((q) => `${q.method} ${q.path}`))}`);
    assert.deepEqual(there.filter(carries).map((q) => `${q.at} ${q.method} ${q.path}`), [], `nothing of a body at ${other}'s stations`);
    // The cloud: the entries of s1's log alone (POST /v1/me/personal-lock), each statement's `ws {t, h}`.
    const cloud = w.r.host.requests.slice(fromCloud);
    assert.deepEqual(cloud.filter((q) => salts.some((x) => textOf(q.body).includes(x)) || /"bodies"/.test(textOf(q.body))).map((q) => q.url), [], "no body at the cloud");
    const sent = cloud.filter((q) => q.url.endsWith("/v1/me/personal-lock")).flatMap((q) => (JSON.parse(textOf(q.body)) as { entries?: Entry[] }).entries ?? []).filter((e) => e.kind === "ws");
    assert.ok(sent.length > 0 && sent.every((e) => Object.keys(e.body as object).sort().join() === "h,t"), `the cloud sent the entries alone: ${JSON.stringify(sent.map((e) => e.body))}`);
  });
}

/// The cloud refusing the write of bob's removal (the call's part past the lock).
function cloudRefuses(w: Awaited<ReturnType<typeof setUp>>) {
  stationLater(w.r.host, (req) => (req.method === "DELETE" && new URL(req.url).pathname === "/v1/workspaces/ws/members/r2" ? Promise.resolve(jsonResponse(500, { error: { code: "internal", message: "the cloud failed" } })) : undefined));
}
const keptKinds = (w: Awaited<ReturnType<typeof setUp>>) => (((w.inner.data.record("lockBodies", "ws") as { bodies?: { kind: string }[] } | null)?.bodies ?? []).map((b) => b.kind)).sort().join(", ");

test("bob taken out, its statements pending, the cloud's write then failing: dropped as a chain entry is, its bodies let go of here, never brought once A is back", async () => {
  const w = await setUp();
  cloudRefuses(w);
  const before = keptKinds(w);
  w.st.silent = true;
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("workspace.removeMember", { account: "s1", workspace: "ws", member: "r2" }), catch: (e) => e as CoreError }));
  assert.ok(out.error !== undefined, "the call fails, as the cloud's write did");
  assert.deepEqual(w.inner.adb.personal().pending("s1"), [], "nothing pending");
  assert.equal(keptKinds(w), before, "the bodies said let go of here");
  w.st.silent = false;
  await w.run(w.inner.adb.personal().refresh("s1"));
  await w.r.host.time.pass(5000);
  assert.deepEqual(w.said(), [], "never brought");
  assert.deepEqual(w.st.brought.filter((b) => b.bodies !== null), [], "no body brought");
  assert.equal(w.members(), "r2 admin, r3 member, s1 owner");
});

test("bob taken out, its statements taken by A, the cloud's write then failing: they stay, as a chain entry taken does", async () => {
  const w = await setUp();
  cloudRefuses(w);
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("workspace.removeMember", { account: "s1", workspace: "ws", member: "r2" }), catch: (e) => e as CoreError }));
  assert.ok(out.error !== undefined, "the call fails, as the cloud's write did");
  assert.deepEqual(w.said(), ["member r3 member", "member.remove r2"], `the call: ${out.error?.code} ${out.error?.message}`);
  assert.equal(w.members(), "r3 member, s1 owner");
});

type Row = { id: string; state: string; text: string; stations: string[] };
const rowsOf = (v: { pending?: Row[] } | undefined) => (v?.pending ?? []).map((x) => [x.state, x.text, x.stations]);

test("the lock's topic: a statement pending shows as a chain entry's, its workspace's stations named, on its workspace's topic alone; gone once taken", async () => {
  const w = await setUp({ two: true });
  const lock = await w.r.watch({ topic: "lock", workspace: "ws" });
  const other = await w.r.watch({ topic: "lock", workspace: "w2" });
  w.st.silent = true;
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r2", gone: true }));
  const row = (out.ok as { pending: Row }).pending;
  assert.match(row.text, /^移除成员 .+：已记下，等 studio 上线后生效$/);
  assert.deepEqual(rowsOf(await lock()), [["waiting", row.text, ["studio"]]], "the call's row, as a chain entry's");
  assert.deepEqual(rowsOf(await other()), [], "not on w2's topic");
  w.st.silent = false;
  await w.run(w.inner.adb.personal().refresh("s1"));
  await w.r.host.time.pass(5000);
  assert.equal(w.members(), "r3 member, s1 owner");
  assert.deepEqual(rowsOf(await lock()), [], "gone once taken");
});

test("the lock's topic: a statement lost with no seed in hand a failed row; let be once the seed is in hand, a failed row saying what changed; each dismissed by its call", async () => {
  const w = await setUp({ devices: true });
  const lock = await w.r.watch({ topic: "lock", workspace: "ws" });
  await w.run(roster(w.inner, "s1", "ws", { member: "r2", role: "member" }));
  await w.lostOff((lost) => [{ ...meaning(lost[2]!), role: "admin" }]);
  const lost = (await lock()).pending as Row[];
  assert.deepEqual(lost.map((x) => x.state), ["failed"], `lost: ${JSON.stringify(lost)} ${JSON.stringify(w.inner.adb.personal().pending("s1"))}`);
  assert.match(lost[0]!.text, /^把 .+ 改为.+：没有生效/);
  await w.r.ask("lock.pendingDismiss", { workspace: "ws", id: lost[0]!.id });
  assert.deepEqual(rowsOf(await lock()), [], "dismissed");
  const inC = await takeC(w);
  assert.equal(inC.error, undefined, inC.error?.message);
  const let_ = (await lock()).pending as Row[];
  assert.deepEqual(let_.map((x) => x.state), ["failed"], `let be: ${JSON.stringify(let_)} ${JSON.stringify(w.inner.adb.personal().pending("s1"))}`);
  assert.notEqual(let_[0]!.text, lost[0]!.text, "the words of one changed after it");
  await w.r.ask("lock.pendingDismiss", { workspace: "ws", id: let_[0]!.id });
  assert.deepEqual(rowsOf(await lock()), [], "dismissed");
});

test("a role lowered, then the app closed and s1's log moved off its statements meanwhile: as it starts and finds them lost, told as not in effect", async () => {
  const w = await setUp({ devices: true });
  await w.run(roster(w.inner, "s1", "ws", { member: "r2", role: "member" }));
  await w.lostOff(undefined, { closed: true });
  const again = await Core.create(w.r.host, { clock: w.r.host.time.clock, sample: 0, wire: () => new HostWire(w.r.host) });
  again.inner.mesh = () => withoutMesh(ME);
  w.reach(again.inner);
  await w.run(again.inner.adb.personal().refresh("s1"), again.inner);
  await w.run(read(again.inner, "ws"), again.inner);
  await w.r.host.time.pass(1000);
  const rows = again.inner.adb.personal().pending("s1");
  assert.deepEqual(rows.map((x) => x.state), ["failed"], `told as not in effect: ${JSON.stringify(rows)}`);
  assert.match(rows[0]!.text, /^把 .+ 改为.+：没有生效/);
});

// 2026-11-14, the root's person gone (station/test/lock-root-gone-ways.test.ts holds the stations' side): what the way
// out lock_root_only names does on this device, every station of the workspace reset on its machine. What is so, held as
// found: nothing here is a design.
test("the root's person gone: another owner told lock_root_only names `stillfail lock reset`; once every station the chain names keeps none, the moved chain is let go here and safe mode turned on anew is a new genesis brought to the stations", async () => {
  const o = await setUp({ root: "alice" });
  const refused = await o.run(Effect.tryPromise({ try: () => o.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal((refused.error as { code?: string } | undefined)?.code, "lock_root_only");
  assert.match(String(refused.error?.message), /stillfail lock reset/, "the way out it names");
  o.st.reset = true;
  // (the view as a cloud of today has it once the chain moved: `locked` for good, whatever the root's log says)
  o.inner.data.update({ topic: "workspace", workspace: "ws" }, (v: any) => ({ ...v, locked: true }));
  await o.run(read(o.inner, "ws"));
  assert.equal(held(o.inner, "ws")?.head ?? null, null, "the moved chain let go: every station the chain names keeps none");
  assert.equal(movedHere(o.inner, "ws"), false);
  assert.equal(safeMode(o.inner, "ws"), true, "still shown in safe mode, by the view's `locked` (none held on)");
  const on = await o.run(Effect.tryPromise({ try: () => o.r.ask("lock.open", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(on.error, undefined, on.error?.message);
  assert.deepEqual(o.st.opened.map((es) => es.map((e) => e.kind).join(",")), ["genesis", "genesis"], "a new genesis brought to A and C, as on a chain that never moved");
});

// After a move the root's person is a member like any other (rules/AGENTS.md, `~root`; the lead, 2026-11-14): another
// owner's removal of them names the root's log, but only where every station the list names said `rootout` (a reader
// from before reads it as nothing); elsewhere the act is as before: refused, it would not do what it means.
test("another owner takes the root's person out: refused as before where a station has not said `rootout`; where every one has, the removal names the root's log and they are out, nobody else", async () => {
  const o = await setUp({ root: "alice" });
  assert.equal(o.members(), "r1 owner, r2 admin, r3 member, s1 owner");
  const before = o.asked();
  const refused = await o.run(roster(o.inner, "s1", "ws", { member: "r1", gone: true }));
  assert.equal((refused.error as { code?: string } | undefined)?.code, "forbidden", "as before: it would not do what it means");
  assert.equal(o.asked(), before, "nobody asked");
  o.st.rootout = true;
  await o.run(read(o.inner, "ws"));
  const out = await o.run(roster(o.inner, "s1", "ws", { member: "r1", gone: true }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(o.asked() - before, 1, "the person asked once");
  assert.deepEqual(o.said(), ["member.remove r1"]);
  assert.equal(o.members(), "r2 admin, r3 member, s1 owner", "the root's person out, nobody else");
  const kept = (o.inner.data.record("lockBodies", "ws") as { bodies?: { kind: string; cancels?: string[] }[] }).bodies ?? [];
  const alice = o.st.logs.find((l) => l.sub === "r1")!;
  assert.ok(kept.some((b) => b.kind === "member.remove" && (b.cancels ?? []).includes(gOf(alice))), "it names the root's log");
});

// Step 4 (the lead's, 2026-11-14): `open` and `off` follow the root's person. Bound by a real admit to the log this device
// is on (`~root` out), they turn it off and on again from here; on the root's log alone before.
test("the root's person bound again by a log of theirs: this device on it turns safe mode off and on again", async () => {
  const w = await setUp({ root: "lost" });
  assert.equal(w.members(), "r2 admin, r3 member, s1 owner");
  const off = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(off.error, undefined, off.error?.message);
  assert.equal(inForceOf(w.inner, "ws").said, "off");
  const on = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.open", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(on.error, undefined, on.error?.message);
  assert.equal(inForceOf(w.inner, "ws").said, "on");
  assert.deepEqual(w.said(), ["off", "open"]);
});

// The root's person's new app approved by another owner (views/pair.ts `admitOf`: `again` while the list names them):
// what this device would say works where every station said `rootout`, the removal first naming the root's log.
test("the root's person's app begun anew, approved by another owner: the removal and the admit by the new log work only where every station said `rootout`", async () => {
  const o = await setUp({ root: "alice" });
  const again = person("r1", 6011, key(6111).hex);
  const meant = [{ kind: "member.remove" as const, sub: "r1" }, { kind: "member" as const, sub: "r1", email: "a@x.com", lock: gOf(again), role: "owner" }];
  assert.equal(movedWorks(o.inner, "ws", "s1", meant), false, "before: it would not do what it means");
  o.st.rootout = true;
  await o.run(read(o.inner, "ws"));
  assert.equal(movedWorks(o.inner, "ws", "s1", meant), true, "every station said rootout");
});
