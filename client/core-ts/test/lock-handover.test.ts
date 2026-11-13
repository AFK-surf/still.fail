// A workspace's chain handed over to its people's own logs by an owner's own app device (views/lock.ts `handOver`,
// src/lock-handover.ts), end to end on a core whose workspace's stations are the station's own code (station/src
// cloud/state.ts `Cloud`, its routes mesh/serve.ts `lockRoute`, `lockPartRoute`: what they take of entries, logs and
// bodies is what a station takes), the chain not moved until the act moves it: the person asked once; the statements
// on their own log in order, each `prev` the one before; the bodies at the workspace's stations alone; the `moved`; the
// state in force the chain's list before (held to the fourth round's model's `d4Old`, station/test/lock-roster4-model.ts),
// every device let in by the stations after. Members with a device that signs and no log: it waits; with none: not said,
// their chain role noted. No station: pending, carried on by calling it again. The chain changed before the `moved`:
// worked out again. Refused for anyone but an owner's own device with its log pinned; `unknown_call` without the host's
// flag.
//
// The world: `ws`, its chain this device's genesis (s1 the owner, this device its app; r2 bob an admin, r3 xena a
// member, each with an app device; stations A and B) and each member's `person` binding to their own log. w2, another
// workspace of s1's, lists station D, which takes nothing of `ws`.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { Effect } from "effect";
import { type Entry as StationEntry, entryHash as stationHash, fold as stationFold } from "../../../station/src/cloud/lock.ts";
import { Cloud, personChainsOf, writeState } from "../../../station/src/cloud/state.ts";
import { wall } from "../../../station/src/ops/fibers.ts";
import { inLock, lockPartRoute, lockRoute } from "../../../station/src/mesh/serve.ts";
import { type Dev, type Key, Log, bring, dev, ed, signed, viewerOf } from "../../../station/test/lock-moved-world.ts";
import { d4Diff, d4Old } from "../../../station/test/lock-roster4-model.ts";
import { key, signed as simSigned } from "../../../station/test/lock-world-sim.ts";
import type { CoreError } from "../src/error.ts";
import { type Entry, type Signer, canonical, entryHash, next } from "../src/lock.ts";
import { bodyHash } from "../src/lock-moved.ts";
import { httpError } from "../src/station/requests.ts";
import { hex, utf8 } from "../src/util.ts";
import { handOver, handOverState, held, inForceOf, notedRole, pendingHeld, read } from "../src/views/lock.ts";
import { serveTrusted, tryOne } from "../src/views/pair.ts";
import { grant, pipe, rig, withoutMesh } from "./lock-rig.ts";

/// The stations' clock: the core's (each test's rig sets it).
let clock = () => 0;
mock.method(wall, "now", () => clock());

const MINE = 7001;
const seedOf = (n: number) => {
  const s = new Uint8Array(32);
  new DataView(s.buffer).setUint32(28, n);
  return s;
};
const SETTINGS = (keys: unknown) => ({ origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: keys });

type Asked = { at: string; method: string; path: string; body: string };
type Opts = {
  /// More members of the chain: `ready: false` one with an app device and no log bound (r4); `web` one with only a web
  /// page (r5, an admin); `none` one with no device (r6, a member).
  more?: ("notReady" | "web" | "none")[];
  /// s1's own web page on the chain.
  myWeb?: boolean;
  /// s1 an admin (s0 the owner, its genesis signer); this device on the chain with another signer; s1's log not pinned;
  /// s1 a second owner (`second`: s0 the first, its genesis signer, bound to a log of their own as the others).
  mine?: "admin" | "otherKey" | "unpinned" | "second";
  /// Chains handed over by themselves here (`Host.handOverAuto`; off by default).
  auto?: boolean;
  /// The genesis's `at` (unix seconds; 1000 by default).
  genesisAt?: number;
  /// With `second`: s0 made an admin by s1 after the bindings (the genesis's person no owner any more).
  firstLowered?: boolean;
  /// The host offers `lock.handOver` (by default).
  flag?: boolean;
  /// bob (r2) an owner, not an admin.
  bobOwner?: boolean;
  /// The workspace's members as the cloud's view says them (none by default).
  view?: { sub: string; email: string; role: string }[];
  /// Members whose log no station keeps (their app device never brought it).
  unbrought?: ("r2" | "r3")[];
};

async function setUp(o: Opts = {}) {
  const g = grant();
  const base = ed();
  // s1's own log: this device on it by its key there (its seed sealed here), no signer said yet (said in the ask)
  const k = key(MINE);
  const myLog = [simSigned({ v: 1, ws: "person:s1", seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub: "s1", device: { key: k.id, id: base.hex, label: "s1's app" } } } as Omit<StationEntry, "sig">, k)];
  const gMe = stationHash(myLog[0]!);
  const bob = new Log("r2"), xena = new Log("r3"), r4 = new Log("r4"), s0 = dev(), first = new Log("s0");
  const A = ed().hex, B = ed().hex, D = ed().hex, WEB = ed(), WEB5 = ed();
  let mine: Signer | null = null;
  let now = 0;
  const other = ed();
  const appOf = (sub: string, d: Dev) => ({ id: d.base.hex, sub, kind: "app", label: `${sub}'s app`, sign_key: d.signer.id });
  const r = await rig((signer) => {
    mine = signer;
    const members = [{ sub: "s1", email: "a@x.com", role: o.mine === "admin" ? "admin" : "owner" }, { sub: "r2", email: "b@x.com", role: o.bobOwner ? "owner" : "admin" }, { sub: "r3", email: "c@x.com", role: "member" }];
    const devices: Record<string, unknown>[] = [{ id: base.hex, sub: "s1", kind: "app", label: "s1's app", sign_key: o.mine === "otherKey" ? other.id : signer.id }, appOf("r2", bob.app), appOf("r3", xena.app)];
    if (o.mine === "admin") members.unshift({ sub: "s0", email: "o@x.com", role: "owner" }), devices.unshift(appOf("s0", s0));
    if (o.mine === "second") members.unshift({ sub: "s0", email: "o@x.com", role: "owner" }), devices.unshift(appOf("s0", first.app));
    if (o.more?.includes("notReady")) members.push({ sub: "r4", email: "d@x.com", role: "member" }), devices.push(appOf("r4", r4.app));
    if (o.more?.includes("web")) members.push({ sub: "r5", email: "e@x.com", role: "admin" });
    if (o.more?.includes("none")) members.push({ sub: "r6", email: "f@x.com", role: "member" });
    const e = next("ws", null, o.genesisAt ?? 1000, "genesis", { owner: members[0]!.sub, ...SETTINGS(g.keys), members, devices, passkeys: [], stations: [{ key: A, name: "a" }, { key: B, name: "b" }], gateways: [] });
    const by = o.mine === "admin" ? s0.signer : o.mine === "second" ? first.app.signer : o.mine === "otherKey" ? other : null;
    return { ws: by === null ? signer.sign(e) : (signed(e as Omit<StationEntry, "sig">, by) as unknown as Entry) };
  }, (host) => {
    host.handOverByTests = o.flag !== false;
    host.handOverAuto = o.auto === true;
    now = Math.floor(host.nowMs() / 1000);
    if (o.mine === "unpinned") return;
    host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(myLog)));
    host.storage.set("personal-signer-id", utf8(k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, [A, B], [A, B], undefined, [D], o.view === undefined ? {} : { members: o.view });
  clock = () => r.host.nowMs();
  const inner = r.core.inner;
  inner.mesh = () => withoutMesh(base.hex);
  const signer = mine! as Signer;
  // The chain: the genesis, each member's binding, by their own device; the extras' web page.
  const chain: Entry[] = [r.cloud.chains.get("ws")![0]!];
  const after = (by: Key | Signer, kind: string, body: unknown): Entry => {
    const last = chain[chain.length - 1]!;
    const e = next("ws", { seq: last.seq, hash: entryHash(last), genesis: entryHash(chain[0]!) }, Math.max(last.at, now), kind, body);
    const s = "signBytes" in by ? by.sign(e) : (signed(e as Omit<StationEntry, "sig">, by) as unknown as Entry);
    chain.push(s);
    return s;
  };
  after(o.mine === "otherKey" ? other : signer, "person", { sub: "s1", person: gMe });
  after(bob.app.signer, "person", { sub: "r2", person: bob.genesis });
  after(xena.app.signer, "person", { sub: "r3", person: xena.genesis });
  if (o.mine === "second") after(first.app.signer, "person", { sub: "s0", person: first.genesis });
  if (o.firstLowered) after(signer, "member", { sub: "s0", email: "o@x.com", role: "admin" });
  if (o.myWeb) after(signer, "device", { id: WEB.hex, sub: "s1", kind: "web", label: "s1's browser", exp: now + 10 * 86400 });
  if (o.more?.includes("web")) after(o.mine === "admin" ? s0.signer : signer, "device", { id: WEB5.hex, sub: "r5", kind: "web", label: "r5's browser", exp: now + 10 * 86400 });
  r.cloud.chains.set("ws", chain);
  // Stations A and B, the station's own code, the chain pinned and the members' logs heard
  const station = (id: string): Cloud => {
    const data = mkdtempSync(join(tmpdir(), "lock-handover-"));
    writeState(data, { origin: "https://stillfail.test", station: id, workspace: "ws", workspace_name: "W", name: id.slice(0, 4), relay_url: "", relay_urls: [], grant_keys: g.keys, peers: [A, B].map((p, i) => ({ id: p, name: `s${i}` })), revocations: [] } as never);
    const c = new Cloud(data, false);
    c.takeLock(chain as unknown as StationEntry[]);
    // (each member's log as their app device brought it to the station, POST /lock/person)
    for (const l of [bob, xena, ...(o.mine === "second" ? [first] : [])]) if (!o.unbrought?.includes(l.sub as "r2" | "r3")) bring(c, l, false, "ws");
    return c;
  };
  const stations = { A: station(A), B: station(B) };
  const st = { silent: false, down: new Set<string>(), asked: [] as Asked[], hook: null as null | (() => void), early: [] as string[] };
  const viewer = viewerOf("s1", { base }, "owner", "ws");
  const route = (c: Cloud, method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (st.silent && method === "POST") return Effect.never;
    // (a `moved` brought to a station that does not hold every statement and body this device's log commits to: the
    // stations would wait, letting nobody in; noted, every test holds there are none)
    if (method === "POST" && path === "/lock" && ((body as { entries?: Entry[] })?.entries ?? []).some((e) => e.kind === "moved")) {
      const commits = inner.adb.personal().entries("s1").filter((e) => e.kind === "ws").map((e) => (e.body as { h: string }).h);
      const kept = c.bodies(null).all();
      if (commits.length === 0 || commits.some((h) => !kept.has(h))) st.early.push(`${c === stations.A ? "A" : "B"}: a moved with ${commits.filter((h) => kept.has(h)).length} of ${commits.length} bodies`);
    }
    const [p, q] = path.split("?") as [string, string | undefined];
    const buf = Buffer.from(body === null || body === undefined ? "" : JSON.stringify(body));
    const [status, out] = p === "/lock" ? lockRoute(c, method, q ? [...new URLSearchParams(q)] : [], buf, viewer as never) : lockPartRoute(c, p.slice("/lock/".length), method, buf, viewer as never);
    // (the first time statements were taken: what the test changes before the `moved`)
    if (status === 200 && p === "/lock/person" && Array.isArray((body as { bodies?: unknown })?.bodies) && st.hook) {
      const h = st.hook;
      st.hook = null;
      h();
    }
    return status === 200 ? Effect.succeed(out) : Effect.fail(httpError(status, out));
  };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (path.startsWith("/lock") && (id === A || id === B || id === D)) {
      const at = `${ws}/${id === A ? "A" : id === B ? "B" : "D"}`;
      st.asked.push({ at, method, path, body: JSON.stringify(body ?? null) });
      if (id === D || ws !== "ws") return method === "POST" ? Effect.succeed({}) : Effect.fail(httpError(404, { error: "no route" }));
      if (st.down.has(at.slice(-1))) return Effect.fail(httpError(503, { error: "not reached" }));
      return route(id === A ? stations.A : stations.B, method, path, body);
    }
    return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>): Promise<{ ok?: X; error?: CoreError }> => {
    let out: { ok?: X; error?: CoreError } | null = null;
    inner.runner.fork(Effect.match(e, { onSuccess: (ok) => void (out = { ok }), onFailure: (error) => void (out = { error }) }));
    await r.host.time.passUntil(30_000, () => out !== null);
    assert.ok(out !== null, "no answer");
    await r.host.time.pass(100);
    return out;
  };
  await run(inner.adb.personal().refresh("s1"));
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.entries.length, chain.length, "the chain held");
  const asked = () => r.host.secureAsked.length;
  /// What this device's own log says past what it said before: each statement's kind and whom, its body's `prev`.
  const said = () => inner.adb.personal().entries("s1").slice(myLog.length).filter((e) => e.kind === "ws").map((e) => {
    const h = (e.body as { h: string }).h;
    const b = ((inner.data.record("lockBodies", "ws") as { bodies?: Record<string, unknown>[] } | null)?.bodies ?? []).find((x) => bodyHash(x) === h);
    return b === undefined ? { what: "ws (no body)", prev: null, h } : { what: `${b.kind} ${b.sub ?? (b.key === A ? "A" : b.key === B ? "B" : "")}${b.role ? ` ${b.role}` : ""}`.trim(), prev: b.prev as string | null, h };
  });
  const hand = () => run(handOver(inner, "s1", "ws"));
  /// The chain's list as the model's D4 has it, by the station's own fold, rooted in s1's log.
  const d4Chain = (es: readonly Entry[]) => d4Old(stationFold(es as unknown as StationEntry[], null), gMe, Math.floor(r.host.nowMs() / 1000));
  /// Someone's first app device (`d`, with the log of their own `log`) asking this device as `sub`, the code shown here
  /// typed on it: the hello's answer and the proof's.
  const firstApp = async (sub: string, log: Log) => {
    const prompts = await r.watch({ topic: "lockPrompts" });
    const [trusted, phone] = await pipe();
    const id = log.app.base.hex;
    inner.runner.fork(serveTrusted(inner, id, base.hex, trusted));
    const first = await run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", id, sub) }], kind: "app", label: `${sub}'s app`, sign_key: log.app.signer.id, log: log.entries }), phone.next()));
    const answer = first.ok as { t: string };
    if (answer.t !== "code") return { answer, done: null };
    const code = ((await prompts()).pairing as { device: string; code: string }[]).find((p) => p.device === id)!.code;
    return { answer, done: await run(tryOne(inner, { id: base.hex, d: phone, workspaces: ["ws"] }, id, code)) };
  };
  /// An ask of the person's own lock's key for something else: grants signed (none: the ask alone).
  const askGrant = () => run(inner.adb.personal().signGrants("s1", [], "a grant"));
  return { r, inner, signer, chain, after, stations, st, asked, said, hand, run, d4Chain, gMe, bob, xena, r4, base, WEB, WEB5, A, B, viewer, firstApp, g, askGrant, now: () => now };
}

/// A second app device of `log`'s person (`d`) as the product puts it on their own log: a device entry signed by the
/// first device there (personal-lock.ts `#addApproved`), with the key it signs the chain with.
const onLog = (log: Log, d: Dev, label: string) => log.add("device", { key: d.key.id, id: d.base.hex, label, sign_key: d.signer.id });

/// The core's state in force as the model's D4 has one (test/lock-moved-check.ts's reading).
function d4Core(inner: any) {
  const f = inForceOf(inner, "ws");
  const devs = (sub: string, kind: string) => [...f.f.devices.values()].filter((d: any) => d.sub === sub && d.kind === kind);
  return {
    on: f.said === "on" ? "on" : f.said,
    settings: f.settings ? canonical(f.settings) : "-",
    members: new Map([...f.f.members].map(([sub, m]) => [sub, { role: m.role, email: m.email, lock: f.f.persons.get(sub) ?? "none", apps: devs(sub, "app").map((d: any) => d.sign_key).sort(), webs: devs(sub, "web").map((d: any) => d.id).sort() }])),
    stations: [...f.f.stations.keys()].sort(),
  };
}
/// A station's state as the model's D4 has one (its own `locked`), rooted in `root`.
const d4Station = (c: Cloud, root: string, now: number) => d4Old(c.locked(null)!.state!, root, now);
const admitted = (sub: string, d: { base: Key }, role: string) => ({ viewer: viewerOf(sub, d, role, "ws"), exp: 4102444800, iat: 0, sid: "s" });

test("an owner, an admin, a member, two stations: asked once, said in order, the bodies at A and B alone, moved, the chain's list in force, every device let in", async () => {
  const w = await setUp();
  const before = w.d4Chain(w.chain);
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(out.ok, null, "handed over");
  assert.equal(w.asked(), 1, "the person asked once");
  const said = w.said();
  assert.deepEqual(said.map((x) => x.what), ["open", "member r2 admin", "member r3 member", "station A", "station B"]);
  assert.deepEqual(said.map((x) => x.prev), [null, ...said.slice(0, -1).map((x) => x.h)], "each prev the one before");
  for (const [n, c] of Object.entries(w.stations)) {
    assert.equal(c.chain(null)?.state?.moved, w.gMe, `${n} took the moved`);
    assert.equal(c.bodies(null).all().size, 5, `${n} keeps the five bodies`);
  }
  const atD = w.st.asked.filter((q) => q.at.endsWith("/D"));
  assert.ok(atD.length > 0 && atD.every((q) => !/"bodies"|"salt"/.test(q.body)), `D, another workspace's, brought the chain alone: ${JSON.stringify(atD.map((q) => q.path))}`);
  const cloudBodies = w.r.host.requests.filter((q) => q.body != null && /"salt"/.test(typeof q.body === "string" ? q.body : new TextDecoder().decode(q.body as Uint8Array)));
  assert.deepEqual(cloudBodies.map((q) => q.url), [], "no body at the cloud");
  await w.run(read(w.inner, "ws"));
  assert.equal(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  const now = Math.floor(w.r.host.nowMs() / 1000);
  assert.deepEqual(d4Diff(before, d4Core(w.inner)), [], "the state in force here is the chain's list before (the model's d4Old)");
  for (const [n, c] of Object.entries(w.stations)) assert.deepEqual(d4Diff(before, d4Station(c, w.gMe, now)), [], `${n}'s state is the chain's list before`);
  for (const [sub, d, role] of [["s1", { base: w.base }, "owner"], ["r2", w.bob.app, "admin"], ["r3", w.xena.app, "member"]] as const) {
    const a = admitted(sub, d, role);
    assert.equal(inLock(w.stations.A, a as never, role, a.viewer.device).viewer.role, role, `${sub}'s app let in by A`);
  }
  const again = await w.hand();
  assert.equal(again.error, undefined);
  assert.equal(w.asked(), 1, "nothing more asked");
  assert.deepEqual(w.st.early, [], "no moved before a station held every body");
});

test("a member with a device that signs and no log of their own: lock_not_ready, nothing said, nobody asked; once their log is bound, handed over", async () => {
  const w = await setUp({ more: ["notReady"] });
  const out = await w.hand();
  assert.equal(out.error?.code, "lock_not_ready", out.error?.message);
  assert.match(out.error?.message ?? "", /r4/);
  assert.equal(w.asked(), 0, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing said");
  const bound = w.after(w.r4.app.signer, "person", { sub: "r4", person: w.r4.genesis });
  for (const c of Object.values(w.stations)) {
    c.takeLock([...w.chain] as unknown as StationEntry[]);
    bring(c, w.r4, false, "ws");
  }
  assert.ok(bound);
  const done = await w.hand();
  assert.equal(done.error, undefined, done.error?.message);
  assert.deepEqual(w.said().map((x) => x.what), ["open", "member r2 admin", "member r3 member", "member r4 member", "station A", "station B"]);
  assert.equal(w.asked(), 1);
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe);
});

test("a member with only a web page and one with no device: not said, the others handed over, each noted with the chain's role", async () => {
  const w = await setUp({ more: ["web", "none"] });
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.deepEqual(w.said().map((x) => x.what), ["open", "member r2 admin", "member r3 member", "station A", "station B"]);
  assert.equal(notedRole(w.inner, "ws", "s1", "r5", "e@x.com"), "admin", "r5 noted as the chain has them");
  assert.equal(notedRole(w.inner, "ws", "s1", "r6", "f@x.com"), "member");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual([...inForceOf(w.inner, "ws").f.members.keys()].sort(), ["r2", "r3", "s1"]);
  const page = admitted("r5", { base: w.WEB5 }, "admin");
  assert.throws(() => inLock(w.stations.A, page as never, "admin", page.viewer.device), "r5's web page out until their app comes");
});

test("the owner's own web page on the chain: said on their log in the same ask, let in after", async () => {
  const w = await setUp({ myWeb: true });
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), 1, "one ask");
  const webs = w.inner.adb.personal().entries("s1").filter((e) => e.kind === "web");
  assert.deepEqual(webs.map((e) => (e.body as { id: string }).id), [w.WEB.hex]);
  assert.equal((webs[0]!.body as { exp: number }).exp, (w.chain.find((e) => e.kind === "device")!.body as { exp: number }).exp, "its exp as the chain has it");
  const page = admitted("s1", { base: w.WEB }, "owner");
  assert.equal(inLock(w.stations.A, page as never, "owner", page.viewer.device).viewer.role, "owner", "let in by A");
});

test("no station reachable: the statements pending, no moved; a station back and handOver again: nothing said twice, nobody asked again, moved", async () => {
  const w = await setUp();
  w.st.silent = true;
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.ok((out.ok as { pending?: unknown } | null)?.pending, `pending: ${JSON.stringify(out.ok)}`);
  for (const c of Object.values(w.stations)) assert.equal(c.chain(null)?.state?.moved, undefined, "no moved at a station");
  assert.notEqual(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved");
  assert.ok(!pendingHeld(w.inner, "ws").some((x) => x.entry.kind === "moved"), "no moved signed while a statement waits");
  assert.equal(w.asked(), 1);
  w.st.silent = false;
  const again = await w.hand();
  assert.equal(again.error, undefined, again.error?.message);
  assert.equal(again.ok, null, `handed over: ${JSON.stringify(again.ok)}`);
  assert.equal(w.asked(), 1, "nobody asked again");
  assert.deepEqual(w.said().map((x) => x.what), ["open", "member r2 admin", "member r3 member", "station A", "station B"], "nothing said twice");
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe, "moved");
  assert.deepEqual(w.st.early, [], "no moved before a station held every body");
});

test("the chain changed between the statements and the moved: bob's own new device, on his log too, nothing more said; an admin's new member with a log, said first, one more ask", async () => {
  const w = await setUp();
  const phone = dev();
  w.st.hook = () => {
    // (approved by bob's app as the product does where his log is bound: on his log, then on the chain, views/pair.ts `approve`)
    onLog(w.bob, phone, "bob's phone");
    w.after(w.bob.app.signer, "device", { id: phone.base.hex, sub: "r2", kind: "app", label: "bob's phone", sign_key: phone.signer.id });
    for (const c of Object.values(w.stations)) {
      c.takeLock([...w.chain] as unknown as StationEntry[]);
      bring(c, w.bob, false, "ws");
    }
  };
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), 1);
  assert.equal(w.said().length, 5);
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe);
  assert.equal(w.stations.A.chain(null)?.state?.seq, w.chain.length, "the moved after bob's device");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(d4Core(w.inner).members.get("r2")?.apps, [w.bob.app.signer.id, phone.signer.id].sort(), "bob's phone in force with his app");

  const v = await setUp();
  const r7 = new Log("r7");
  v.st.hook = () => {
    v.after(v.bob.app.signer, "member", { sub: "r7", email: "g@x.com", role: "member" });
    v.after(v.bob.app.signer, "device", { id: r7.app.base.hex, sub: "r7", kind: "app", label: "r7's app", sign_key: r7.app.signer.id });
    v.after(r7.app.signer, "person", { sub: "r7", person: r7.genesis });
    for (const c of Object.values(v.stations)) {
      c.takeLock([...v.chain] as unknown as StationEntry[]);
      bring(c, r7, false, "ws");
    }
  };
  const more = await v.hand();
  assert.equal(more.error, undefined, more.error?.message);
  assert.equal(v.asked(), 2, "one more ask");
  assert.deepEqual(v.said().map((x) => x.what), ["open", "member r2 admin", "member r3 member", "station A", "station B", "member r7 member"]);
  assert.equal(v.stations.A.chain(null)?.state?.moved, v.gMe);
  await v.run(read(v.inner, "ws"));
  assert.deepEqual([...inForceOf(v.inner, "ws").f.members.keys()].sort(), ["r2", "r3", "r7", "s1"], "r7 in force after it");
});

test("a member bound to a log with a second app device on the chain and not on that log: lock_not_ready naming them, nothing said, nobody asked; once the device is on their log, handed over and both in force", async () => {
  const w = await setUp();
  const phone = dev();
  w.after(w.bob.app.signer, "device", { id: phone.base.hex, sub: "r2", kind: "app", label: "bob's phone", sign_key: phone.signer.id });
  for (const c of Object.values(w.stations)) c.takeLock([...w.chain] as unknown as StationEntry[]);
  const out = await w.hand();
  assert.equal(out.error?.code, "lock_not_ready", out.error?.message);
  assert.match(out.error?.message ?? "", /r2/);
  assert.doesNotMatch(out.error?.message ?? "", /r3/, "xena's devices are all on her log");
  assert.equal(w.asked(), 0, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing said");
  for (const c of Object.values(w.stations)) assert.equal(c.chain(null)?.state?.moved, undefined, "nothing moved");
  onLog(w.bob, phone, "bob's phone");
  for (const c of Object.values(w.stations)) bring(c, w.bob, false, "ws");
  const done = await w.hand();
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(done.ok, null, "handed over");
  assert.equal(w.asked(), 1);
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(d4Core(w.inner).members.get("r2")?.apps, [w.bob.app.signer.id, phone.signer.id].sort(), "both of bob's apps in force here");
  const now = Math.floor(w.r.host.nowMs() / 1000);
  assert.deepEqual(d4Diff(w.d4Chain(w.chain), d4Station(w.stations.A, w.gMe, now)), [], "A's state is the chain's list before, bob's phone in it");
  const p = admitted("r2", phone, "admin");
  assert.equal(inLock(w.stations.A, p as never, "admin", p.viewer.device).viewer.role, "admin", "bob's phone let in by A");
});

test("a member bound to a log no station keeps: lock_not_ready naming them, nothing said; once a station keeps it, handed over", async () => {
  const w = await setUp({ unbrought: ["r2"] });
  const out = await w.hand();
  assert.equal(out.error?.code, "lock_not_ready", out.error?.message);
  assert.match(out.error?.message ?? "", /r2/);
  assert.equal(w.asked(), 0, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing said");
  bring(w.stations.B, w.bob, false, "ws");
  const done = await w.hand();
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(d4Core(w.inner).members.get("r2")?.apps, [w.bob.app.signer.id], "bob's app in force here");
});

test("a device approved on the chain after the statements and before the moved, not on its person's log: the moved refused (lock_not_ready), nothing signed; on the log, the next handOver moves it, nobody asked again", async () => {
  const w = await setUp();
  const phone = dev();
  w.st.hook = () => {
    w.after(w.bob.app.signer, "device", { id: phone.base.hex, sub: "r2", kind: "app", label: "bob's phone", sign_key: phone.signer.id });
    for (const c of Object.values(w.stations)) c.takeLock([...w.chain] as unknown as StationEntry[]);
  };
  const out = await w.hand();
  assert.equal(out.error?.code, "lock_not_ready", out.error?.message);
  assert.match(out.error?.message ?? "", /r2/);
  assert.equal(w.asked(), 1, "asked once, for the statements");
  for (const c of Object.values(w.stations)) assert.equal(c.chain(null)?.state?.moved, undefined, "no moved at a station");
  assert.notEqual(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved");
  assert.ok(!pendingHeld(w.inner, "ws").some((x) => x.entry.kind === "moved"), "no moved pending");
  const still = await w.hand();
  assert.equal(still.error?.code, "lock_not_ready", "still waiting while the phone is on the chain alone");
  onLog(w.bob, phone, "bob's phone");
  for (const c of Object.values(w.stations)) bring(c, w.bob, false, "ws");
  const done = await w.hand();
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(done.ok, null, "handed over");
  assert.equal(w.asked(), 1, "nobody asked again");
  assert.equal(w.said().length, 5, "nothing said again");
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(d4Core(w.inner).members.get("r2")?.apps, [w.bob.app.signer.id, phone.signer.id].sort(), "bob's phone in force");
});

for (const mine of ["admin", "otherKey", "unpinned"] as const) {
  test(`refused, nobody asked, nothing said: ${mine === "admin" ? "not an owner" : mine === "otherKey" ? "not this person's own device by its signer" : "the person's log not pinned"}`, async () => {
    const w = await setUp({ mine });
    const out = await w.hand();
    assert.equal(out.error?.code, "forbidden", out.error?.message);
    assert.equal(w.asked(), 0);
    assert.equal(w.inner.adb.personal().entries("s1").filter((e) => e.kind === "ws").length, 0);
    assert.equal(w.stations.A.chain(null)?.state?.moved, undefined);
  });
}

test("without the host's flag: lock.handOver is no call", async () => {
  const w = await setUp({ flag: false });
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.handOver", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(out.error?.code, "unknown_call", out.error?.message);
  assert.equal(w.asked(), 0);
  const on = await setUp();
  const ok = await on.run(Effect.tryPromise({ try: () => on.r.ask("lock.handOver", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(ok.error, undefined, ok.error?.message);
  assert.equal(on.stations.A.chain(null)?.state?.moved, on.gMe, "with it: handed over");
});

test("the one with only a web page, not said at the move: their first app device after it asks, this owner's device shows the code, and they come in with the chain's role, the note used once; their old web page stays out", async () => {
  const view = [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "r2", email: "b@x.com", role: "admin" }, { sub: "r3", email: "c@x.com", role: "member" }, { sub: "r5", email: "e@x.com", role: "admin" }];
  const w = await setUp({ more: ["web"], view });
  assert.equal((await w.hand()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.equal(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved");
  assert.equal(notedRole(w.inner, "ws", "s1", "r5", "e@x.com"), "admin", "noted with the chain's role");
  const before = w.asked();
  const r5 = new Log("r5");
  for (const c of Object.values(w.stations)) bring(c, r5, false, "ws");
  const { answer, done } = await w.firstApp("r5", r5);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws"] }, "a code shown");
  assert.equal(done?.error, undefined, done?.error?.message);
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.deepEqual(w.said().slice(5).map((x) => x.what), ["member r5 admin"], "said with the chain's role");
  assert.equal(notedRole(w.inner, "ws", "s1", "r5", "e@x.com"), null, "the note used once");
  await w.run(read(w.inner, "ws"));
  const f = inForceOf(w.inner, "ws").f;
  assert.equal(f.members.get("r5")?.role, "admin", "r5 an admin in force here");
  assert.equal(f.persons.get("r5"), r5.genesis, "bound to the log their app brought");
  const app = admitted("r5", r5.app, "admin");
  assert.equal(inLock(w.stations.A, app as never, "admin", app.viewer.device).viewer.role, "admin", "their app let in by A as an admin");
  const page = admitted("r5", { base: w.WEB5 }, "admin");
  assert.throws(() => inLock(w.stations.A, page as never, "admin", page.viewer.device), "their old web page out until their own app approves it");
});

/// The workspace's stations meeting: each given what the other keeps of the chain (as another keeper's, so the fork
/// choice decides), of the person logs and of the bodies.
function meet(a: Cloud, b: Cloud) {
  for (const [x, y] of [[a, b], [b, a]] as const) for (const [g, es] of personChainsOf(x).every()) personChainsOf(y).keep(g, es, "ws");
  const ka = a.lockKept(null), kb = b.lockKept(null);
  a.keepLock(kb, null, true);
  b.keepLock(ka, null, true);
  const ba = [...a.bodies(null).all().values()], bb = [...b.bodies(null).all().values()];
  a.takeBodies(null, bb);
  b.takeBodies(null, ba);
}

for (const wins of ["bob", "this device"] as const) {
  test(`two owners hand over at once, each at a station the other's does not reach, then the stations meet: one moved stands (${wins}'s, by the fork choice), one chain and one state in force everywhere, the list the chain had`, async () => {
    const w = await setUp({ bobOwner: true });
    const [a, b] = [w.stations.A, w.stations.B];
    // xena's own new phone on the chain at one station before its owner hands over there: the fork is then between
    // her entry (a member's, one vote) and the other owner's moved (three), so the fork choice is the test's to say
    // (rules/src/lock/chain.mbt `lock_chain`'s weights), and the branch with her phone loses
    const phone = dev();
    const head = w.chain.at(-1)!;
    const on = (parent: Entry, by: Key, kind: string, body: unknown): Entry => signed(next("ws", { seq: parent.seq, hash: entryHash(parent), genesis: entryHash(w.chain[0]!) }, Math.max(parent.at, w.now()), kind, body) as Omit<StationEntry, "sig">, by) as unknown as Entry;
    const xenas = on(head, w.xena.app.signer, "device", { id: phone.base.hex, sub: "r3", kind: "app", label: "xena's phone", sign_key: phone.signer.id });
    // (on her own log too, as the product puts it there where her log is bound, kept by both stations: in force after the
    // move whichever branch stands)
    onLog(w.xena, phone, "xena's phone");
    for (const c of [a, b]) bring(c, w.xena, false, "ws");
    if (wins === "bob") a.takeLock([...w.chain, xenas] as unknown as StationEntry[]);
    // bob's app hands over at B, which this device does not reach: his log says the chain's list, B takes it, then his moved
    w.st.down.add("B");
    const settings = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: w.g.keys };
    w.bob.say("open", { ...settings, email: "b@x.com" }, "ws");
    w.bob.say("member", { sub: "s1", email: "a@x.com", lock: w.gMe, role: "owner" }, "ws");
    w.bob.say("member", { sub: "r3", email: "c@x.com", lock: w.xena.genesis, role: "member" }, "ws");
    w.bob.say("station", { key: w.A }, "ws");
    w.bob.say("station", { key: w.B }, "ws");
    const [took, said] = bring(b, w.bob, true, "ws");
    assert.equal(took, 200, JSON.stringify(said));
    assert.equal((said as { taken?: number }).taken, 5, "B takes bob's five bodies");
    const bobsAt = wins === "this device" ? on(xenas, w.bob.app.signer, "moved", { root: w.bob.genesis }) : on(head, w.bob.app.signer, "moved", { root: w.bob.genesis });
    b.takeLock([...w.chain, ...(wins === "this device" ? [xenas] : []), bobsAt] as unknown as StationEntry[]);
    assert.equal(b.chain(null)?.state?.moved, w.bob.genesis, "B moved to bob's log");
    // this device hands over at A
    const out = await w.hand();
    assert.equal(out.error, undefined, out.error?.message);
    assert.equal(out.ok, null, `handed over at A: ${JSON.stringify(out.ok)}`);
    assert.equal(a.chain(null)?.state?.moved, w.gMe, "A moved to s1's log");
    const asked = w.asked();
    // the stations meet, and this device reaches B again
    meet(a, b);
    w.st.down.clear();
    for (let n = 0; n < 3; n++) {
      await w.run(read(w.inner, "ws"));
      await w.run(w.inner.adb.personal().refresh("s1"));
    }
    const root = wins === "bob" ? w.bob.genesis : w.gMe;
    const list = w.d4Chain([...w.chain, xenas]);
    const nowS = Math.floor(w.r.host.nowMs() / 1000);
    for (const [n, c] of [["A", a], ["B", b]] as const) {
      assert.equal(c.chain(null)?.state?.moved, root, `${n} goes by ${wins}'s moved`);
      assert.deepEqual(d4Diff(list, d4Station(c, root, nowS)), [], `${n}'s state in force is the list the chain had`);
    }
    assert.equal(stationHash(a.lockAfter(-1).at(-1)!), stationHash(b.lockAfter(-1).at(-1)!), "one chain: the same head at both");
    const h = held(w.inner, "ws")!;
    assert.equal(h.entries.at(-1)?.kind, "moved");
    assert.equal((h.entries.at(-1)!.body as { root: string }).root, root, "this device goes by the same moved");
    assert.equal(inForceOf(w.inner, "ws").root, root);
    assert.deepEqual(d4Diff(list, d4Core(w.inner)), [], "the state in force here is the list the chain had");
    for (const [sub, d, role] of [["s1", { base: w.base }, "owner"], ["r2", w.bob.app, "owner"], ["r3", w.xena.app, "member"]] as const) {
      const x = admitted(sub, d, role);
      for (const c of [a, b]) assert.equal(inLock(c, x as never, role, x.viewer.device).viewer.role, role, `${sub}'s device let in`);
    }
    // the moved that lost: never signed again, nothing pending, nothing said or asked again
    const mine = (c: Cloud) => c.lockKept(null).filter((e) => e.kind === "moved" && e.sig.key === w.signer.id).length;
    assert.deepEqual([mine(a), mine(b)], [1, 1], "this device's moved signed once");
    assert.ok(!pendingHeld(w.inner, "ws").some((x) => x.entry.kind === "moved"), "no moved pending here");
    const again = await w.hand();
    assert.equal(again.error, undefined, again.error?.message);
    assert.equal(again.ok, null, "handOver again: handed over (it moved), nothing done");
    assert.deepEqual([mine(a), mine(b)], [1, 1], "nor signed by handOver again");
    assert.equal(w.asked(), asked, "nobody asked again");
    assert.equal(w.said().length, 5, "nothing said again");
    if (wins === "bob") {
      // this device's person: an owner of the standing state by bob's `member`; their own statements under a root
      // nothing reads; off and on again are the root's alone
      const f = inForceOf(w.inner, "ws").f;
      assert.equal(f.members.get("s1")?.role, "owner", "an owner by bob's statement");
      assert.equal(f.persons.get("s1"), w.gMe, "by their own log");
      const off = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
      assert.equal(off.error?.code, "lock_root_only", off.error?.message);
      assert.equal(w.asked(), asked, "nobody asked for it");
    }
  });
}

// Handed over by itself (views/lock.ts `handsOver`, `movedBySelf`; personal-lock.ts `#addHandOvers`): nobody calls
// `lock.handOver`; the statements ride on an ask of the person's own lock's key for something else, the `moved` follows
// with no key as the lock is held. The switch is the host's `handOverAuto` here (HAND_OVER_FROM is null).
const DAY = 86400;
const T0 = Date.UTC(2026, 9, 6, 9, 0, 0) / 1000;
const MOVED_SAYS = ["open", "member r2 admin", "member r3 member", "station A", "station B"];
const movedAt = (w: Awaited<ReturnType<typeof setUp>>) => Object.values(w.stations).map((c) => c.chain(null)?.state?.moved ?? null);

test("the switch off: whatever is asked (a grant, an own device approved), nothing said and nothing moved", async () => {
  const w = await setUp();
  assert.equal(handOverState(w.inner, "ws"), null, "not this device's to hand over by itself");
  assert.equal((await w.askGrant()).error, undefined);
  const d = dev();
  const added = await w.run(w.inner.adb.personal().addDevice("s1", { key: d.key.id, id: d.base.hex, label: "s1's second", sign_key: d.signer.id }, "a device"));
  assert.equal(added.error, undefined, added.error?.message);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(w.said(), [], "nothing said");
  assert.notEqual(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved");
  assert.deepEqual(movedAt(w), [null, null]);
});

for (const how of ["a grant", "an own device approved"] as const) {
  test(`on: the genesis's person's device hands over as it answers ${how}, one ask in all, the chain's list in force`, async () => {
    const w = await setUp({ auto: true });
    const before = w.d4Chain(w.chain);
    assert.deepEqual(handOverState(w.inner, "ws"), { asks: true }, "to be said, no ask yet");
    await w.run(read(w.inner, "ws"));
    assert.deepEqual(w.said(), [], "nothing said with no ask");
    if (how === "a grant") assert.equal((await w.askGrant()).error, undefined);
    else {
      const d = dev();
      const out = await w.run(w.inner.adb.personal().addDevice("s1", { key: d.key.id, id: d.base.hex, label: "s1's second", sign_key: d.signer.id }, "a device"));
      assert.equal(out.error, undefined, out.error?.message);
    }
    assert.deepEqual(w.said().map((x) => x.what), MOVED_SAYS, "said in that ask");
    await w.run(read(w.inner, "ws"));
    assert.equal(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved", "moved, nobody calling lock.handOver");
    assert.deepEqual(movedAt(w), [w.gMe, w.gMe]);
    assert.equal(w.asked(), 1, "one ask in all");
    assert.equal(handOverState(w.inner, "ws"), null, "moved");
    // (the device approved on s1's own log is s1's in the state rooted there, though the chain never named it)
    assert.deepEqual(d4Diff(before, d4Core(w.inner)), how === "a grant" ? [] : ["apps s1"], "the chain's list in force (the model's d4Old)");
    assert.deepEqual(w.st.early, [], "no moved before a station held every body");
  });
}

test("another owner's device: not before 14 days from the genesis, then as it answers an ask", async () => {
  const w = await setUp({ auto: true, mine: "second", genesisAt: T0 - 13 * DAY });
  assert.equal(handOverState(w.inner, "ws"), null, "the first owner's yet");
  assert.equal((await w.askGrant()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(w.said(), [], "nothing said before 14 days");
  w.r.host.advance((DAY + 60) * 1000);
  assert.deepEqual(handOverState(w.inner, "ws"), { asks: true });
  assert.equal((await w.askGrant()).error, undefined);
  assert.deepEqual(w.said().map((x) => x.what), ["open", "member s0 owner", "member r2 admin", "member r3 member", "station A", "station B"]);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved to s1's log");
  assert.equal(w.asked(), 2);
});

test("another owner's device at once where the genesis's person is no owner any more", async () => {
  const w = await setUp({ auto: true, mine: "second", genesisAt: T0 - DAY, firstLowered: true });
  assert.deepEqual(handOverState(w.inner, "ws"), { asks: true });
  assert.equal((await w.askGrant()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe]);
  assert.equal(w.asked(), 1);
});

test("a member not ready: nothing said, handOverState names them; ready, said at the next ask and moved", async () => {
  const w = await setUp({ auto: true, more: ["notReady"] });
  assert.equal((await w.askGrant()).error, undefined);
  assert.deepEqual(w.said(), [], "nothing said");
  assert.deepEqual(handOverState(w.inner, "ws"), { waits: ["r4"] });
  w.after(w.r4.app.signer, "person", { sub: "r4", person: w.r4.genesis });
  for (const c of Object.values(w.stations)) {
    c.takeLock([...w.chain] as unknown as StationEntry[]);
    bring(c, w.r4, false, "ws");
  }
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(handOverState(w.inner, "ws"), { asks: true }, "ready: what is to be said waits for an ask");
  assert.deepEqual(movedAt(w), [null, null]);
  assert.equal((await w.askGrant()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe]);
  assert.equal(w.asked(), 2, "one more ask where nothing was said");
});

test("a member not ready after all was said: it waits, then moves by itself once they are, no ask more", async () => {
  const w = await setUp({ auto: true });
  w.st.hook = () => {
    // (as the statements are taken: a new app device of xena's on the chain, not on her log)
    const d = dev();
    w.after(w.xena.app.signer, "device", { id: d.base.hex, sub: "r3", kind: "app", label: "r3's second", sign_key: d.signer.id });
    for (const c of Object.values(w.stations)) c.takeLock([...w.chain] as unknown as StationEntry[]);
    onLog(w.xena, d, "r3's second");
  };
  assert.equal((await w.askGrant()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(handOverState(w.inner, "ws"), { waits: ["r3"] });
  assert.deepEqual(movedAt(w), [null, null]);
  for (const c of Object.values(w.stations)) bring(c, w.xena, false, "ws");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved as the lock was read");
  assert.equal(w.asked(), 1, "no ask more");
});

test("stations all down at the ask: said and pending, nothing moved; one back, moved as it took them, no ask", async () => {
  const w = await setUp({ auto: true });
  w.st.silent = true;
  assert.equal((await w.askGrant()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [null, null]);
  assert.notEqual(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved");
  assert.deepEqual(handOverState(w.inner, "ws"), { moving: true }, "all said, not taken");
  w.st.silent = false;
  await w.run(w.inner.adb.personal().refresh("s1"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe]);
  assert.equal(w.asked(), 1);
  assert.deepEqual(w.said().map((x) => x.what), MOVED_SAYS, "nothing said twice");
});
