// A device a moved workspace's list does not name, end to end on a core whose station is the station's own code
// (station/src/cloud/state.ts `Cloud`; its hello's admission and refusal, mesh/serve.ts `inLockBringing`, `refusalOf`;
// its routes `lockRoute`, `lockPartRoute`): the station gives it nothing but the chain (the cloud's copy) and its
// refusal, which says it is left out and whom to ask (`left`). The device shows what it shows before a move where it
// is not confirmed (able to ask, its try's `pair`), dials those it was told to, and once let in reads the logs and
// bodies as any device of the list (2026-11-14: such a device sat `waiting` for good on real stations).
//
// The world: `ws`, its chain alice's (r1, the owner; bob r2 an admin) then a `moved` to alice's own log, which says
// the settings, bob and station A (and, `named`, s1 a member by the log of s1's app X). This core is s1's: a new app
// or web page (`base`) no log binds.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { Effect } from "effect";
import { type Entry as StationEntry, LockRefusal, entryHash as stationHash } from "../../../station/src/cloud/lock.ts";
import { Cloud, writeState } from "../../../station/src/cloud/state.ts";
import { wall } from "../../../station/src/ops/fibers.ts";
import { inLockBringing, lockPartRoute, lockRoute, refusalOf } from "../../../station/src/mesh/serve.ts";
import { Log, bring as brought, ed, signed, viewerOf } from "../../../station/test/lock-moved-world.ts";
import { hooks } from "../src/core/execute.ts";
import { CoreError } from "../src/error.ts";
import type { Entry } from "../src/lock.ts";
import { pairSession, pakeKeys, pakeStart } from "../src/pair.ts";
import { httpError } from "../src/station/requests.ts";
import { hex } from "../src/util.ts";
import { held, read } from "../src/views/lock.ts";
import { dialer } from "../src/views/pair.ts";
import { grant, pipe, rig } from "./lock-rig.ts";
import { stationReplies } from "./station-fixture.ts";

let clock = () => 0;
mock.method(wall, "now", () => clock());

const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
/// The code the trusted devices here show (as typed on the new device).
const CODE = "246810";
type J = any;
/// What a trusted device answers once the code is confirmed (it signs what lets the new one in first), by its base id.
type Approver = { where: (hello: J) => string[]; approve: (hello: J) => J };

/// `named`: s1 a member by X's log. `web`: this core a web page. `waiting`: the station given no root's log.
async function setUp(o: { named?: boolean; web?: boolean; waiting?: boolean } = {}) {
  const g = grant();
  const settings = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: g.keys };
  const alice = new Log("r1"), bob = new Log("r2"), x = new Log("s1");
  const A = ed().hex, base = ed();
  alice.say("open", { ...settings, email: "r1@x.com" }, "ws");
  alice.say("member", { sub: "r2", email: "r2@x.com", lock: bob.genesis, role: "admin" }, "ws");
  alice.say("station", { key: A }, "ws");
  if (o.named) alice.say("member", { sub: "s1", email: "s1@x.com", lock: x.genesis, role: "member" }, "ws");
  const app = (l: Log) => ({ id: l.app.base.hex, sub: l.sub, kind: "app", label: `${l.sub}'s app`, sign_key: l.app.signer.id });
  const body = {
    owner: "r1", ...settings, passkeys: [], stations: [{ key: A, name: "a" }], gateways: [],
    members: [{ sub: "r1", email: "r1@x.com", role: "owner" }, { sub: "r2", email: "r2@x.com", role: "admin" }, ...(o.named ? [{ sub: "s1", email: "s1@x.com", role: "member" }] : [])],
    devices: [app(alice), app(bob), ...(o.named ? [app(x)] : [])],
  };
  const first = signed({ v: 1, ws: "ws", seq: 0, prev: null, at: 1000, kind: "genesis", body }, alice.app.signer);
  const moved = signed({ v: 1, ws: "ws", seq: 1, prev: stationHash(first), at: 1000, kind: "moved", body: { root: alice.genesis } }, alice.app.signer);
  const r = await rig(() => ({ ws: first as unknown as Entry }), (host) => {
    if (o.web) host.appKeys = false;
  }, [A], [A], undefined, [], { role: "member" });
  clock = () => r.host.nowMs();
  // (the cloud's copy of a person's own lock, for the devices from before: it keeps none of s1's)
  stationReplies(r.host, (req) => (req.url.endsWith("/v1/me/personal-lock") ? (req.method === "GET" ? { entries: [] } : { ok: true }) : r.cloud.reply(req)));
  r.cloud.chains.set("ws", [first, moved] as unknown as Entry[]);
  const inner = r.core.inner;
  inner.mesh = () => Effect.succeed({ deviceId: () => base.hex, lockClaim: () => null, link: () => Effect.fail(CoreError.plainly("mesh", "no station link here")) } as never);
  inner.cloudSync.credential = () => Effect.succeed({ credential: "signed-member", issued_at: 1000, expires_at: 4102444800, relay_url: "https://relay.example" });
  // Station A: the station's own code, the chain pinned and moved, the logs and bodies its members' devices gave it.
  const data = mkdtempSync(join(tmpdir(), "lock-left-out-"));
  writeState(data, { origin: "https://stillfail.test", station: A, workspace: "ws", workspace_name: "W", name: "a", relay_url: "", relay_urls: [], grant_keys: g.keys, peers: [{ id: A, name: "a" }], revocations: [] } as never);
  const c = new Cloud(data, false);
  c.takeLock([first]);
  c.takeLock([first, moved], null, true);
  // (as each member's app device brings them, POST /lock/person)
  const bring = (l: Log) => void brought(c, l, true, "ws");
  for (const l of o.waiting ? [bob] : o.named ? [alice, bob, x] : [alice, bob]) bring(l);
  const viewer = viewerOf("s1", { base }, "member", "ws");
  /// What the station does to each of its asks: `lie`, a device its refusals name to ask in place of those it would.
  const st = { lie: null as string | null, refusals: [] as J[], admitted: 0 };
  /// The link's hello to A, as the station answers it: null where it lets this device in; else its refusal, told the
  /// core as the mesh tells it (mesh.ts `refusedFor`).
  const hello = (): CoreError | null => {
    const own = inner.adb.personal().entries("s1");
    const said = { lock: { device: base.hex, proof: viewer.lockDevice.proof, ...(own.length > 0 ? { person: own } : {}) } };
    try {
      inLockBringing(c, { viewer, exp: 4102444800, iat: 0, sid: "" } as never, "member", viewer.device, said);
    } catch (e) {
      if (!(e instanceof LockRefusal)) throw e;
      const refusal = refusalOf(c, said, viewer.device, e, undefined, "s1") as J;
      if (st.lie !== null && refusal.left !== undefined) refusal.left = { approvers: [st.lie] };
      st.refusals.push(refusal);
      return hooks.lockRefused?.(inner, "ws", A, refusal.lock, refusal) ?? new CoreError("lock_unconfirmed", e.message);
    }
    st.admitted++;
    return null;
  };
  // A station tried again (views/lock.ts `refusedAgain`): its link dials it, and once let in the lock is read as a link
  // that opens reads it.
  const cameOnline = inner.stations.cameOnline.bind(inner.stations);
  inner.stations.cameOnline = (address: string) => {
    cameOnline(address);
    if (address === `ws/${A}` && hello() === null) inner.runner.fork(Effect.ignore(read(inner, "ws")));
  };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (id !== A || !path.startsWith("/lock")) return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
    if (ws !== "ws") return Effect.fail(httpError(404, { error: "no route" }));
    // (its link's hello first: a station that refused this device is not dialled again until told to, as the mesh does)
    const waits = hooks.lockWaiting?.(inner, ws, A) ?? null;
    if (waits !== null) return Effect.fail(waits);
    const no = hello();
    if (no !== null) return Effect.fail(no);
    const [p, q] = path.split("?") as [string, string | undefined];
    const buf = Buffer.from(body === null || body === undefined ? "" : JSON.stringify(body));
    const [status, out] = p === "/lock" ? lockRoute(c, method, q ? [...new URLSearchParams(q)] : [], buf, viewer as never) : lockPartRoute(c, p.slice("/lock/".length), method, buf, viewer as never);
    return status === 200 ? Effect.succeed(out) : Effect.fail(httpError(status, out));
  }) as typeof inner.stations.requests.call;
  // The trusted devices it dials: each it knows answers as a device on the lock does (a code, the exchange, what it
  // signs, then `approved`); any other, that it approves nothing here.
  const approvers = new Map<string, Approver>();
  const dialled: string[] = [];
  dialer.open = (_inner, id) => Effect.flatMap(Effect.promise(() => pipe()), ([here, there]) => Effect.sync(() => {
    dialled.push(id);
    inner.runner.fork(Effect.gen(function* () {
      const hello = (yield* there.next()) as J;
      const a = approvers.get(id);
      if (a === undefined) return yield* there.send({ t: "no", error: "not_here" });
      const where = a.where(hello);
      yield* there.send({ t: "code", workspaces: where });
      const m = (yield* there.next()) as J;
      const p = pakeStart(CODE, pairSession(base.hex, id, where), (b) => b.fill(5));
      const keys = pakeKeys(p, unhex(m.y), "trusted")!;
      yield* there.send({ t: "pake", y: hex(p.share), mac: hex(keys.mine) });
      yield* there.next();
      yield* there.send(a.approve(hello));
    }));
    return here;
  }));
  const run = async <X>(e: Effect.Effect<X, any>): Promise<{ ok?: X; error?: CoreError }> => {
    let out: { ok?: X; error?: CoreError } | null = null;
    inner.runner.fork(Effect.match(e, { onSuccess: (ok) => void (out = { ok }), onFailure: (error) => void (out = { error }) }));
    await r.host.time.passUntil(30_000, () => out !== null);
    assert.ok(out !== null, "no answer");
    await r.host.time.pass(100);
    return out;
  };
  const ask = (name: string, params: Record<string, unknown>) => run(Effect.tryPromise({ try: () => r.ask(name, params), catch: (e) => e as CoreError }));
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  /// The page as it stands once what was set going settled.
  const page = async () => {
    await r.host.time.pass(2_000);
    return (await lock()) as J;
  };
  const now = () => Math.floor(r.host.nowMs() / 1000);
  /// What a failure says of where it got: the station's refusals and admissions, the page.
  const why = () => `refused ${st.refusals.length}, last left ${JSON.stringify(st.refusals.at(-1)?.left)?.slice(0, 30)} error ${String(st.refusals.at(-1)?.error).slice(0, 80)}; admitted ${st.admitted}; standing ${inner.adb.personal().standing("s1")}`;
  return { why, r, inner, c, st, alice, bob, x, base, A, approvers, dialled, run, ask, page, bring, now, hello };
}

/// Whom the page lists: each member's sub.
const subs = (v: J) => (v.members as J[]).map((m) => m.sub).sort().join(",");

test("a newcomer's first app: not confirmed and able to ask; it dials an owner's device, the code, `member` said, then it is in and reads the list", async () => {
  const w = await setUp();
  const before = await w.page();
  assert.equal(w.st.refusals.at(-1)?.left !== undefined, true, "told left out");
  assert.deepEqual([before.me.confirmed, before.me.waiting], [false, true], "not confirmed, able to ask");
  w.approvers.set(w.alice.app.base.hex, {
    where: () => ["ws"],
    approve: (hello) => {
      w.alice.say("member", { sub: "s1", email: "s1@x.com", lock: stationHash(hello.log[0]), role: "member" }, "ws");
      w.bring(w.alice);
      return { t: "approved", workspaces: ["ws"], failed: [] };
    },
  });
  const asked = await w.ask("lock.pair", { workspace: "ws" });
  assert.equal(asked.error, undefined, asked.error?.message);
  const trying = await w.page();
  assert.ok(trying.me.pair !== null, "its try on the page");
  assert.ok(w.dialled.includes(w.alice.app.base.hex), `alice's app dialled (${w.alice.app.base.hex.slice(0, 8)}; dialled ${w.dialled.map((d) => d.slice(0, 8))}; ${w.why()})`);
  assert.equal(w.dialled.includes(w.x.app.base.hex), false, "no one else's");
  const done = await w.ask("lock.pairCode", { workspace: "ws", code: CODE });
  assert.equal(done.error, undefined, done.error?.message);
  const after = await w.page();
  assert.equal(after.me.confirmed, true, `in (${w.why()})`);
  assert.equal(subs(after), "r1,r2,s1", "it reads the list");
});

test("a newcomer approved before a station took its `member` statement (2026-11-14, real stations): tried again as it is, and in once a station takes it", async () => {
  const w = await setUp();
  w.approvers.set(w.alice.app.base.hex, {
    where: () => ["ws"],
    approve: (hello) => {
      w.alice.say("member", { sub: "s1", email: "s1@x.com", lock: stationHash(hello.log[0]), role: "member" }, "ws");
      return { t: "approved", workspaces: ["ws"], failed: [] };
    },
  });
  assert.equal((await w.ask("lock.pair", { workspace: "ws" })).error, undefined);
  const done = await w.ask("lock.pairCode", { workspace: "ws", code: CODE });
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal((await w.page()).me.confirmed, false, "not in while no station took it");
  w.bring(w.alice);
  await w.r.host.time.pass(10_000);
  const after = await w.page();
  assert.equal(after.me.confirmed, true, `in (${w.why()})`);
  assert.equal(subs(after), "r1,r2,s1");
});

test("a member's new web page: it asks that member's own app, `web` said, in", async () => {
  const w = await setUp({ named: true, web: true });
  const before = await w.page();
  assert.deepEqual(w.st.refusals.at(-1)?.left, { approvers: [w.x.app.base.hex] }, "told to ask X");
  assert.deepEqual([before.me.confirmed, before.me.waiting], [false, true], "not confirmed, able to ask");
  w.approvers.set(w.x.app.base.hex, {
    where: () => ["ws"],
    approve: () => {
      w.x.add("web", { id: w.base.hex, label: "Chrome", exp: w.now() + 30 * 86400 }, w.x.app.key, w.now());
      w.bring(w.x);
      return { t: "approved", workspaces: ["ws"], failed: [] };
    },
  });
  assert.equal((await w.ask("lock.pair", { workspace: "ws" })).error, undefined);
  assert.deepEqual(w.dialled, [w.x.app.base.hex], "X alone dialled");
  const done = await w.ask("lock.pairCode", { workspace: "ws", code: CODE });
  assert.equal(done.error, undefined, done.error?.message);
  const after = await w.page();
  assert.equal(after.me.confirmed, true, `in (${w.why()})`);
  assert.equal(subs(after), "r1,r2,s1");
});

test("a member's web page left out, said on their log meanwhile by their app (carried from the chain, personal-lock.ts `#addWebs`), nothing asked on the page: as it is, not tried again while it only waits (ten minutes), let in at its next hello", async () => {
  const w = await setUp({ named: true, web: true });
  const before = await w.page();
  assert.deepEqual([before.me.confirmed, before.me.waiting], [false, true], "out, able to ask");
  const refused = w.st.refusals.length;
  w.x.add("web", { id: w.base.hex, label: "Chrome", exp: w.now() + 20 * 86400 }, w.x.app.key, w.now());
  w.bring(w.x);
  await w.r.host.time.pass(600_000);
  const after = await w.page();
  assert.deepEqual([after.me.confirmed, w.st.refusals.length - refused, w.st.admitted], [false, 0, 0], "not tried again: nothing tells a page refused that its person's log changed");
  assert.equal(w.hello(), null, "its next hello (the page opened again) let in");
});

test("a member's own second app: the personal exchange with their app on the log, then in", async () => {
  const w = await setUp({ named: true });
  const before = await w.page();
  assert.deepEqual([before.me.confirmed, before.me.waiting], [false, true], "not confirmed, able to ask");
  w.approvers.set(w.x.app.base.hex, {
    where: () => ["person:s1"],
    approve: (hello) => {
      w.x.add("device", { key: hello.personal.key, id: w.base.hex, label: "Pixel", sign_key: hello.sign_key });
      w.bring(w.x);
      return { t: "approved", workspaces: ["person:s1"], chains: { s1: w.x.entries } };
    },
  });
  assert.equal((await w.ask("lock.pair", { workspace: "ws" })).error, undefined);
  assert.deepEqual(w.dialled, [w.x.app.base.hex], "X alone dialled");
  const done = await w.ask("lock.pairCode", { workspace: "ws", code: CODE });
  assert.equal(done.error, undefined, done.error?.message);
  const after = await w.page();
  assert.equal(after.me.confirmed, true, `in (${w.why()})`);
  assert.equal(subs(after), "r1,r2,s1");
});

test("a station that names a wrong device to ask: nothing let in, the page still able to ask", async () => {
  const w = await setUp();
  const liar = ed().hex;
  w.st.lie = liar;
  hooks.lockRefused?.(w.inner, "ws", w.A, null, { left: { approvers: [liar] } });
  w.approvers.set(w.alice.app.base.hex, { where: () => ["ws"], approve: () => ({ t: "approved", workspaces: ["ws"], failed: [] }) });
  assert.equal((await w.ask("lock.pair", { workspace: "ws" })).error, undefined);
  assert.deepEqual(w.dialled, [liar], "only the device it was told of");
  const after = await w.page();
  assert.deepEqual([after.me.confirmed, after.me.waiting], [false, true], "not in, able to ask");
  assert.equal(w.st.admitted, 0, "never let in");
});

test("a station only waiting for the root's log: as today, nothing listed, nothing to ask", async () => {
  const w = await setUp({ waiting: true });
  const v = await w.page();
  assert.equal(w.st.refusals.some((x) => x.left !== undefined), false, "nobody told left out");
  assert.deepEqual([v.me.confirmed, v.me.waiting, v.me.pair ?? null], [false, false, null]);
  assert.equal(subs(v), "");
});
