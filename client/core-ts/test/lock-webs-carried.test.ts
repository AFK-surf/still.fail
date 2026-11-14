// The web pages a workspace's chain names, carried by the chain as it moved once it moved (the model's D6, the lead's,
// 2026-11-14: rules/src/lock/state4.mbt `carry_of`), end to end on a core whose workspace's stations are the station's
// own code (station/src/cloud/state.ts `Cloud`, mesh/serve.ts `lockRoute`, `lockPartRoute`, `inLockBringing`,
// `refusalOf`): after a handover that says nothing but `moved`, a page the chain lets in is let in by both stations and
// in force here, whoever approved it (its own person's app, an owner, another's app), nothing said on its person's log
// and nobody asked, until its `exp` there; one run out, one the chain took off, one its person's log took off are not.
// (Until 2026-11-14 a member's app carried its own pages onto its log, `#addWebs`; the chain as it moved does that now.)
//
// The world: `ws`, its chain s0's (the owner, a log of their own, `owner`); s1 an admin, this core their app, its log
// pinned here (`myLog`); r2 a member with a log; stations A and B. s1's pages on the chain: W1 (its own app approved it),
// WX (runs out), WD (taken off the chain), WL (taken off s1's log), WO (put in by s0); r2's WR, put in by s1's app (an
// admin's may), so that only its person tells it from s1's own.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { Effect } from "effect";
import { type Entry as StationEntry, LockRefusal } from "../../../station/src/cloud/lock.ts";
import { Cloud, writeState } from "../../../station/src/cloud/state.ts";
import { wall } from "../../../station/src/ops/fibers.ts";
import { inLockBringing, lockPartRoute, lockRoute, refusalOf } from "../../../station/src/mesh/serve.ts";
import { type Key, Log, bring, ed, signed, viewerOf } from "../../../station/test/lock-moved-world.ts";
import { key, signed as simSigned } from "../../../station/test/lock-world-sim.ts";
import type { CoreError } from "../src/error.ts";
import { type Entry, type Signer, entryHash, next } from "../src/lock.ts";
import { httpError } from "../src/station/requests.ts";
import { hex, utf8 } from "../src/util.ts";
import { held, inForceOf, read } from "../src/views/lock.ts";
import { grant, rig, withoutMesh } from "./lock-rig.ts";

type J = any;
let clock = () => 0;
mock.method(wall, "now", () => clock());

const MINE = 7101;
const seedOf = (n: number) => {
  const s = new Uint8Array(32);
  new DataView(s.buffer).setUint32(28, n);
  return s;
};
const SETTINGS = (keys: unknown) => ({ origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: keys });
const DAY = 86400;

/// `flag`: the host offers the handover and hands chains over by itself (by default). `bare`: s1's log holds no `web` yet
/// (WL neither put on nor taken off it), so a page is said only once everything that keeps or reads that log takes one
/// (a person log holding none of the new kinds): D, the station of s1's other workspace, says nothing of builds until `d.says`.
async function setUp(o: { flag?: boolean; bare?: boolean } = {}) {
  const g = grant();
  const base = ed();
  const k = key(MINE);
  const owner = new Log("s0"), r2 = new Log("r2");
  const A = ed().hex, B = ed().hex, D = ed().hex;
  const W1 = ed(), WX = ed(), WD = ed(), WL = ed(), WO = ed(), WR = ed();
  let mine: Signer | null = null;
  let now = 0;
  // s1's own log: this device on it by its key there (no signer said yet: its first ask says it, `#restate`); WL put on
  // it and taken off it.
  const myLog: StationEntry[] = [simSigned({ v: 1, ws: "person:s1", seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub: "s1", device: { key: k.id, id: base.hex, label: "s1's app" } } } as Omit<StationEntry, "sig">, k)];
  const onMine = (kind: string, body: unknown) => {
    const last = myLog.at(-1)!;
    myLog.push(simSigned({ v: 1, ws: "person:s1", seq: last.seq + 1, prev: entryHash(last as unknown as Entry), at: 1000, kind, body } as Omit<StationEntry, "sig">, k));
  };
  if (o.bare !== true) {
    onMine("web", { id: WL.hex, label: "s1's old browser", exp: 1000 + 20 * DAY });
    onMine("web.remove", { id: WL.hex });
  }
  const gMe = entryHash(myLog[0] as unknown as Entry);
  const appOf = (sub: string, l: Log) => ({ id: l.app.base.hex, sub, kind: "app", label: `${sub}'s app`, sign_key: l.app.signer.id });
  const r = await rig((signer) => {
    mine = signer;
    const members = [{ sub: "s0", email: "o@x.com", role: "owner" }, { sub: "s1", email: "a@x.com", role: "admin" }, { sub: "r2", email: "b@x.com", role: "member" }];
    const devices = [appOf("s0", owner), { id: base.hex, sub: "s1", kind: "app", label: "s1's app", sign_key: signer.id }, appOf("r2", r2)];
    const e = next("ws", null, 1000, "genesis", { owner: "s0", ...SETTINGS(g.keys), members, devices, passkeys: [], stations: [{ key: A, name: "a" }, { key: B, name: "b" }], gateways: [] });
    return { ws: signed(e as Omit<StationEntry, "sig">, owner.app.signer) as unknown as Entry };
  }, (host) => {
    host.handOverByTests = o.flag !== false;
    // (pages said before any chain moved only where chains are handed over by themselves: views/lock.ts `handsOver`)
    host.handOverAuto = o.flag !== false;
    now = Math.floor(host.nowMs() / 1000);
    host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(myLog)));
    host.storage.set("personal-signer-id", utf8(k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, [A, B], [A, B], undefined, [D], { role: "admin" });
  clock = () => r.host.nowMs();
  const inner = r.core.inner;
  inner.mesh = () => withoutMesh(base.hex);
  const signer = mine! as Signer;
  const chain: Entry[] = [r.cloud.chains.get("ws")![0]!];
  const after = (by: Key | Signer, kind: string, body: unknown): Entry => {
    const last = chain[chain.length - 1]!;
    const e = next("ws", { seq: last.seq, hash: entryHash(last), genesis: entryHash(chain[0]!) }, Math.max(last.at, now), kind, body);
    const s = "signBytes" in by ? by.sign(e) : (signed(e as Omit<StationEntry, "sig">, by) as unknown as Entry);
    chain.push(s);
    return s;
  };
  const web = (k: Key, sub: string, label: string, exp: number) => ({ id: k.hex, sub, kind: "web", label, exp });
  after(owner.app.signer, "person", { sub: "s0", person: owner.genesis });
  after(signer, "person", { sub: "s1", person: gMe });
  after(r2.app.signer, "person", { sub: "r2", person: r2.genesis });
  after(signer, "device", web(W1, "s1", "s1's browser", now + 10 * DAY));
  after(signer, "device", web(WX, "s1", "s1's browser, running out", now + 5));
  after(signer, "device", web(WD, "s1", "s1's browser, taken off", now + 10 * DAY));
  after(signer, "device.remove", { id: WD.hex });
  after(signer, "device", web(WL, "s1", "s1's old browser", now + 10 * DAY));
  after(owner.app.signer, "device", web(WO, "s1", "s1's browser, by the owner", now + 10 * DAY));
  after(signer, "device", web(WR, "r2", "r2's browser", now + 10 * DAY));
  r.cloud.chains.set("ws", chain);
  const station = (id: string): Cloud => {
    const data = mkdtempSync(join(tmpdir(), "lock-webs-carried-"));
    writeState(data, { origin: "https://stillfail.test", station: id, workspace: "ws", workspace_name: "W", name: id.slice(0, 4), relay_url: "", relay_urls: [], grant_keys: g.keys, peers: [A, B].map((p, i) => ({ id: p, name: `s${i}` })), revocations: [] } as never);
    const c = new Cloud(data, false);
    c.takeLock(chain as unknown as StationEntry[]);
    for (const l of [owner, r2]) bring(c, l, false, "ws");
    // (s1's log, as their app brought it as it came to the station)
    const [status] = lockPartRoute(c, "person", "POST", Buffer.from(JSON.stringify({ chain: myLog })), viewerOf("s1", { base }, "admin", "ws") as never);
    assert.equal(status, 200, "s1's log taken");
    return c;
  };
  const stations = { A: station(A), B: station(B) };
  const viewer = viewerOf("s1", { base }, "admin", "ws");
  const d = { says: false };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (path.startsWith("/lock") && (id === A || id === B || id === D)) {
      if ((id === D || ws !== "ws") && d.says && method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [], serves: ["logs", "builds"], builds: { since: Math.floor(clock() / 1000), devices: {} } });
      if (id === D || ws !== "ws") return method === "POST" ? Effect.succeed({}) : Effect.fail(httpError(404, { error: "no route" }));
      const c = id === A ? stations.A : stations.B;
      const [p, q] = path.split("?") as [string, string | undefined];
      const buf = Buffer.from(body === null || body === undefined ? "" : JSON.stringify(body));
      const [status, out] = p === "/lock" ? lockRoute(c, method, q ? [...new URLSearchParams(q)] : [], buf, viewer as never) : lockPartRoute(c, p.slice("/lock/".length), method, buf, viewer as never);
      return status === 200 ? Effect.succeed(out) : Effect.fail(httpError(status, out));
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
  // (WX runs out)
  await r.host.time.pass(10_000);
  const asked = () => r.host.secureAsked.length;
  /// What s1's log says of web pages past what it said before.
  const webs = () => inner.adb.personal().entries("s1").slice(myLog.length).filter((e) => e.kind === "web" || e.kind === "web.remove").map((e) => ({ kind: e.kind, ...(e.body as J) }));
  /// Something else s1 asks for on this app (a chat's grant signed): the person asked once for it.
  const grantAsked = () => run(inner.adb.personal().signGrants("s1", [], "a grant"));
  /// s0 hands the chain over to its people's logs, as an owner's app does (views/lock.ts `handOver`): its statements on
  /// its log, the `moved` on the chain, both at A and B, the core then reading the chain.
  const handOver = async (said = true) => {
    if (said) {
      owner.say("open", { ...SETTINGS(g.keys), email: "o@x.com" }, "ws");
      owner.say("member", { sub: "s1", email: "a@x.com", lock: gMe, role: "admin" }, "ws");
      owner.say("member", { sub: "r2", email: "b@x.com", lock: r2.genesis, role: "member" }, "ws");
      owner.say("station", { key: A }, "ws");
      owner.say("station", { key: B }, "ws");
    }
    after(owner.app.signer, "moved", { root: owner.genesis });
    for (const c of Object.values(stations)) {
      bring(c, owner, true, "ws");
      c.takeLock([...chain] as unknown as StationEntry[]);
      assert.equal(c.chain(null)?.state?.moved, owner.genesis, "the station took the moved");
    }
    await run(read(inner, "ws"));
    assert.equal(held(inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  };
  /// A web page of s1's (`k`) at a station's hello: in, or refused with what the refusal tells it.
  const page = (c: Cloud, k: Key): { in: boolean; left?: J } => {
    const v = viewerOf("s1", { base: k }, "admin", "ws");
    const said = { lock: { device: k.hex, proof: v.lockDevice.proof } };
    try {
      inLockBringing(c, { viewer: v, exp: 4102444800, iat: 0, sid: "" } as never, "admin", v.device, said);
      return { in: true };
    } catch (e) {
      if (!(e instanceof LockRefusal)) throw e;
      return { in: false, left: (refusalOf(c, said, v.device, e, undefined, "s1") as J).left };
    }
  };
  return { r, inner, base, stations, W1, WX, WD, WL, WO, WR, asked, webs, grantAsked, handOver, page, run, d, now: () => now };
}

/// The handover as an owner's app makes it now (views/lock.ts `handOver`): `moved`, nothing said in any log.
const movedAlone = async (w: Awaited<ReturnType<typeof setUp>>) => w.handOver(false);

test("after a handover that says nothing: the chain's pages in at both stations and here, whoever approved them, nothing said on s1's log, nobody asked; one run out, taken off the chain or off s1's log, out", async () => {
  const w = await setUp();
  await movedAlone(w);
  await w.run(read(w.inner, "ws"));
  for (const [n, c] of Object.entries(w.stations)) {
    // (s1's own pages at s1's hello; r2's is r2's, in force below)
    for (const k of ["W1", "WO"] as const) assert.equal(w.page(c, w[k]).in, true, `${k} let in by ${n}`);
    for (const k of ["WX", "WD", "WL"] as const) assert.equal(w.page(c, w[k]).in, false, `${k} out at ${n}`);
  }
  const f = inForceOf(w.inner, "ws").f;
  for (const k of ["W1", "WO", "WR"] as const) assert.ok(f.devices.has(w[k].hex), `${k} in force here`);
  for (const k of ["WX", "WD", "WL"] as const) assert.ok(!f.devices.has(w[k].hex), `${k} not in force here`);
  assert.equal(f.devices.get(w.WR.hex)?.sub, "r2", "r2's page is r2's");
  assert.equal(w.asked(), 0, "nobody asked");
  assert.equal((await w.grantAsked()).error, undefined);
  assert.deepEqual(w.webs(), [], "nothing said on s1's log as their app signs something else either");
});

test("a carried page is out at its exp on the chain, at both stations and here", async () => {
  const w = await setUp();
  await movedAlone(w);
  w.r.host.advance((10 * DAY + 60) * 1000);
  await w.run(read(w.inner, "ws"));
  for (const [n, c] of Object.entries(w.stations)) assert.equal(w.page(c, w.W1).in, false, `W1 out at ${n}`);
  assert.ok(!inForceOf(w.inner, "ws").f.devices.has(w.W1.hex), "W1 not in force here");
});
