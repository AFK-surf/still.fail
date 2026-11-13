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
import { type Dev, type Key, Log, dev, ed, signed, viewerOf } from "../../../station/test/lock-moved-world.ts";
import { d4Diff, d4Old } from "../../../station/test/lock-roster4-model.ts";
import { key, signed as simSigned } from "../../../station/test/lock-world-sim.ts";
import type { CoreError } from "../src/error.ts";
import { type Entry, type Signer, canonical, entryHash, next } from "../src/lock.ts";
import { bodyHash } from "../src/lock-moved.ts";
import { httpError } from "../src/station/requests.ts";
import { hex, utf8 } from "../src/util.ts";
import { handOver, held, inForceOf, notedRole, pendingHeld, read } from "../src/views/lock.ts";
import { grant, rig, withoutMesh } from "./lock-rig.ts";

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
  /// s1 an admin (s0 the owner, its genesis signer); this device on the chain with another signer; s1's log not pinned.
  mine?: "admin" | "otherKey" | "unpinned";
  /// The host offers `lock.handOver` (by default).
  flag?: boolean;
};

async function setUp(o: Opts = {}) {
  const g = grant();
  const base = ed();
  // s1's own log: this device on it by its key there (its seed sealed here), no signer said yet (said in the ask)
  const k = key(MINE);
  const myLog = [simSigned({ v: 1, ws: "person:s1", seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub: "s1", device: { key: k.id, id: base.hex, label: "s1's app" } } } as Omit<StationEntry, "sig">, k)];
  const gMe = stationHash(myLog[0]!);
  const bob = new Log("r2"), xena = new Log("r3"), r4 = new Log("r4"), s0 = dev();
  const A = ed().hex, B = ed().hex, D = ed().hex, WEB = ed(), WEB5 = ed();
  let mine: Signer | null = null;
  let now = 0;
  const other = ed();
  const appOf = (sub: string, d: Dev) => ({ id: d.base.hex, sub, kind: "app", label: `${sub}'s app`, sign_key: d.signer.id });
  const r = await rig((signer) => {
    mine = signer;
    const members = [{ sub: "s1", email: "a@x.com", role: o.mine === "admin" ? "admin" : "owner" }, { sub: "r2", email: "b@x.com", role: "admin" }, { sub: "r3", email: "c@x.com", role: "member" }];
    const devices: Record<string, unknown>[] = [{ id: base.hex, sub: "s1", kind: "app", label: "s1's app", sign_key: o.mine === "otherKey" ? other.id : signer.id }, appOf("r2", bob.app), appOf("r3", xena.app)];
    if (o.mine === "admin") members.unshift({ sub: "s0", email: "o@x.com", role: "owner" }), devices.unshift(appOf("s0", s0));
    if (o.more?.includes("notReady")) members.push({ sub: "r4", email: "d@x.com", role: "member" }), devices.push(appOf("r4", r4.app));
    if (o.more?.includes("web")) members.push({ sub: "r5", email: "e@x.com", role: "admin" });
    if (o.more?.includes("none")) members.push({ sub: "r6", email: "f@x.com", role: "member" });
    const e = next("ws", null, 1000, "genesis", { owner: members[0]!.sub, ...SETTINGS(g.keys), members, devices, passkeys: [], stations: [{ key: A, name: "a" }, { key: B, name: "b" }], gateways: [] });
    const by = o.mine === "admin" ? s0.signer : o.mine === "otherKey" ? other : null;
    return { ws: by === null ? signer.sign(e) : (signed(e as Omit<StationEntry, "sig">, by) as unknown as Entry) };
  }, (host) => {
    host.handOverByTests = o.flag !== false;
    now = Math.floor(host.nowMs() / 1000);
    if (o.mine === "unpinned") return;
    host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(myLog)));
    host.storage.set("personal-signer-id", utf8(k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, [A, B], [A, B], undefined, [D]);
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
  if (o.myWeb) after(signer, "device", { id: WEB.hex, sub: "s1", kind: "web", label: "s1's browser", exp: now + 10 * 86400 });
  if (o.more?.includes("web")) after(o.mine === "admin" ? s0.signer : signer, "device", { id: WEB5.hex, sub: "r5", kind: "web", label: "r5's browser", exp: now + 10 * 86400 });
  r.cloud.chains.set("ws", chain);
  // Stations A and B, the station's own code, the chain pinned and the members' logs heard
  const station = (id: string): Cloud => {
    const data = mkdtempSync(join(tmpdir(), "lock-handover-"));
    writeState(data, { origin: "https://stillfail.test", station: id, workspace: "ws", workspace_name: "W", name: id.slice(0, 4), relay_url: "", relay_urls: [], grant_keys: g.keys, peers: [A, B].map((p, i) => ({ id: p, name: `s${i}` })), revocations: [] } as never);
    const c = new Cloud(data, false);
    c.takeLock(chain as unknown as StationEntry[]);
    for (const l of [bob, xena]) personChainsOf(c).keep(l.genesis, l.entries, "ws");
    return c;
  };
  const stations = { A: station(A), B: station(B) };
  const st = { silent: false, asked: [] as Asked[], hook: null as null | (() => void) };
  const viewer = viewerOf("s1", { base }, "owner", "ws");
  const route = (c: Cloud, method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (st.silent && method === "POST") return Effect.never;
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
  return { r, inner, signer, chain, after, stations, st, asked, said, hand, run, d4Chain, gMe, bob, xena, r4, base, WEB, WEB5, A, B, viewer };
}

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
    personChainsOf(c).keep(w.r4.genesis, w.r4.entries, "ws");
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
  assert.equal(w.stations.A.chain(null)?.state?.moved, undefined, "no moved");
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
});

test("the chain changed between the statements and the moved: bob's own new device, nothing more said; an admin's new member with a log, said first, one more ask", async () => {
  const w = await setUp();
  const phone = dev();
  w.st.hook = () => {
    w.after(w.bob.app.signer, "device", { id: phone.base.hex, sub: "r2", kind: "app", label: "bob's phone", sign_key: phone.signer.id });
    for (const c of Object.values(w.stations)) c.takeLock([...w.chain] as unknown as StationEntry[]);
  };
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), 1);
  assert.equal(w.said().length, 5);
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe);
  assert.equal(w.stations.A.chain(null)?.state?.seq, w.chain.length, "the moved after bob's device");

  const v = await setUp();
  const r7 = new Log("r7");
  v.st.hook = () => {
    v.after(v.bob.app.signer, "member", { sub: "r7", email: "g@x.com", role: "member" });
    v.after(v.bob.app.signer, "device", { id: r7.app.base.hex, sub: "r7", kind: "app", label: "r7's app", sign_key: r7.app.signer.id });
    v.after(r7.app.signer, "person", { sub: "r7", person: r7.genesis });
    for (const c of Object.values(v.stations)) {
      c.takeLock([...v.chain] as unknown as StationEntry[]);
      personChainsOf(c).keep(r7.genesis, r7.entries, "ws");
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
