// After a move the root's person is a member like any other (the lead's, 2026-11-14): that they are in the list, bound
// by the root's log, is an implicit admit (`~root`, rules/src/lock/roster.mbt), which an owner's removal of them takes
// out where its `cancels` names the root's genesis hash; then an owner admits them again by a log begun anew, as any
// member whose every device was lost. The root's log stays what the workspace is rooted in: what its pair says counts
// as an owner's. Each case on the station's own code (`Cloud.locked`, the rules' `state4_moved`), alice the root's
// person (log R), bob an owner by her, carol an admin, dave a member.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mock, test } from "node:test";
import type { Admin } from "../src/api/admin.ts";
import { MOVED_FROM_BUILD, ROOT_OUT_FROM_BUILD } from "../src/api/moved-from.ts";
import { json } from "../src/api/request.ts";
import { LockRefusal, endpointBytes } from "../src/cloud/lock.ts";
import { Cloud, personChainsOf } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { CHAINS_A_PERSON } from "../src/mesh/person-chains.ts";
import type { Served } from "../src/mesh/served.ts";
import { ALPN, Reader, lockPartRoute, lockRoute, movedTooOld, refusalOf, serve, writeLine } from "../src/mesh/serve.ts";
import { GrantKey } from "./fake-control-plane.ts";
import { Log, WS, bring, ed, handover, station, viewerOf, world } from "./lock-moved-world.ts";
import { memoryMesh } from "./memory-mesh.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

/// `cloudKeys`: the keys the workspace's `open` says the control plane signs members' credentials with (none by default).
function setUp(cloudKeys: unknown[] = []) {
  const w = world();
  w.settings.cloud_keys = { keys: cloudKeys as never[] };
  handover(w);
  w.alice.say("member", { sub: "bob", email: "bob@x", lock: w.bob.genesis, role: "owner" });
  w.alice.say("member", { sub: "carol", email: "carol@x", lock: w.carol.genesis, role: "admin" });
  const dave = new Log("dave");
  w.alice.say("member", { sub: "dave", email: "dave@x", lock: dave.genesis, role: "member" });
  const c = station(w, 0);
  for (const l of [w.alice, w.bob, w.carol, dave]) bring(c, l);
  return { w, c, dave };
}
/// What the state in force says of `sub`: their role, the log they are bound by, their email, their devices' ids.
const of = (c: Cloud, sub: string) => {
  const s = c.locked()?.state;
  if (!s) return "no state";
  const m = s.members.get(sub);
  const devices = [...s.devices.values()].filter((d) => d.sub === sub).map((d) => d.id).sort();
  return m === undefined ? { in: false, devices } : { in: true, role: m.role, lock: s.persons.get(sub) ?? "none", email: m.email, devices };
};
const appsOf = (...ls: Log[]) => ls.map((l) => l.app.base.hex).sort();

test("i. an owner's removal of the root's person naming the root's log: they are out, no device of theirs in the state; the owner stays one, what he and the root's log said before and after counts, the state on with its settings", () => {
  const { w, c } = setUp();
  const before = c.locked()!.state!;
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  bring(c, w.bob);
  assert.deepEqual(of(c, "alice"), { in: false, devices: [] });
  assert.equal((of(c, "bob") as any).role, "owner");
  // (after it: the root's log admits erin, bob admits frank; both count)
  const erin = new Log("erin"), frank = new Log("frank");
  w.alice.say("member", { sub: "erin", email: "erin@x", lock: erin.genesis, role: "member" });
  w.bob.say("member", { sub: "frank", email: "frank@x", lock: frank.genesis, role: "member" });
  for (const l of [w.alice, w.bob, erin, frank]) bring(c, l);
  assert.deepEqual([of(c, "erin"), of(c, "frank")].map((x: any) => x.role), ["member", "member"]);
  assert.deepEqual([of(c, "carol"), of(c, "dave")].map((x: any) => x.role), ["admin", "member"]);
  const s = c.locked()!.state!;
  assert.equal(s.disabled, false, "on");
  assert.deepEqual([s.origins, s.rp_id, s.cloud_keys], [before.origins, before.rp_id, before.cloud_keys], "the settings the same");
  assert.equal(s.genesis, w.alice.genesis, "still rooted in her log");
});

test("ii. then the owner's admit of the root's person by a log begun anew: bound by it, an owner, her devices its own, her email the admit's", () => {
  const { w, c } = setUp();
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  const again = new Log("alice");
  w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  for (const l of [w.bob, again]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: again.genesis, email: "alice@new", devices: appsOf(again) });
});

test("iii. the owner's admit of the root's person by another log with no removal binds nothing: she is bound by the root's log as before", () => {
  const { w, c } = setUp();
  const again = new Log("alice");
  w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  for (const l of [w.bob, again]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("iv. an admin's or a member's removal of the root's person naming the root's log does nothing", () => {
  const { w, c, dave } = setUp();
  w.carol.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  dave.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  for (const l of [w.carol, dave]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("v. a removal of the root's person whose `cancels` does not name the root's log (none, or other hashes) does nothing, as before", () => {
  const { w, c } = setUp();
  w.bob.say("member.remove", { sub: "alice", cancels: [] });
  const other = w.bob.say("member", { sub: "erin", email: "erin@x", lock: w.bob.genesis, role: "member" });
  w.bob.say("member.remove", { sub: "alice", cancels: [other.h, w.bob.genesis, w.moved.sig.sig.slice(0, 64)] });
  bring(c, w.bob);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("vi. the root's person's own removal of themselves, on the root's log naming it: out (the root's pair needs nothing)", () => {
  const { w, c } = setUp();
  w.alice.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  bring(c, w.alice);
  assert.deepEqual(of(c, "alice"), { in: false, devices: [] });
  assert.equal((of(c, "bob") as any).role, "owner");
});

test("vii. lost twice: after ii, the owner's removal naming that admit and his admit by a third log: bound by the third", () => {
  const { w, c } = setUp();
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  const r2 = new Log("alice"), r3 = new Log("alice");
  const ii = w.bob.say("member", { sub: "alice", email: "alice@new", lock: r2.genesis, role: "owner" });
  w.bob.say("member.remove", { sub: "alice", cancels: [ii.h] });
  w.bob.say("member", { sub: "alice", email: "alice@third", lock: r3.genesis, role: "owner" });
  for (const l of [w.bob, r2, r3]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: r3.genesis, email: "alice@third", devices: appsOf(r3) });
});

test("viii. the owner's removal of the root's person naming the root's log and, on it, her removal of him: he is out, she in by the root's log", () => {
  const { w, c } = setUp();
  const bobs = [...w.alice.bodies.entries()].find(([, b]) => b.kind === "member" && b.sub === "bob" && b.role === "owner")![0];
  const first = [...w.alice.bodies.entries()].find(([, b]) => b.kind === "member" && b.sub === "bob")![0];
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  w.alice.say("member.remove", { sub: "bob", cancels: [first, bobs] });
  for (const l of [w.bob, w.alice]) bring(c, l);
  assert.deepEqual(of(c, "bob"), { in: false, devices: [] });
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("xi. bob and eve owners each removed by the other (a circle), bob's removal of the root's person naming the root's log: she stays in by it (only a cancellation that counts takes `~root` out); then her removal of bob: he is out, eve an owner again", () => {
  const { w, c } = setUp();
  const eve = new Log("eve");
  const eves = w.alice.say("member", { sub: "eve", email: "eve@x", lock: eve.genesis, role: "owner" });
  const bobs = [...w.alice.bodies.entries()].filter(([, b]) => b.kind === "member" && b.sub === "bob").map(([h]) => h);
  w.bob.say("member.remove", { sub: "eve", cancels: [eves.h] });
  eve.say("member.remove", { sub: "bob", cancels: bobs });
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  for (const l of [w.alice, w.bob, eve]) bring(c, l);
  assert.deepEqual([of(c, "bob"), of(c, "eve")].map((x: any) => x.in), [false, false], "bob and eve undecided: neither in");
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
  w.alice.say("member.remove", { sub: "bob", cancels: bobs });
  bring(c, w.alice);
  assert.deepEqual(of(c, "bob"), { in: false, devices: [] });
  assert.equal((of(c, "eve") as any).role, "owner", "eve an owner again");
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("x. on and off follow her: after ii, her new log's off: off; the lost log's open after it: still off (her new log's word stands once it says any); bob's removal of ii's admit: by the root's log again, on", () => {
  const { w, c } = setUp();
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  const again = new Log("alice");
  const ii = w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  for (const l of [w.bob, again]) bring(c, l);
  assert.notEqual(c.locked(), null, "on, by the root's open (her new log says none)");
  again.say("off", {});
  bring(c, again);
  assert.equal(c.locked(), null, "off: her new log's");
  w.alice.say("open", { ...w.settings, email: "alice@x" });
  bring(c, w.alice);
  assert.equal(c.locked(), null, "still off: the lost log's open counts no more");
  w.bob.say("member.remove", { sub: "alice", cancels: [ii.h] });
  bring(c, w.bob);
  assert.notEqual(c.locked(), null, "on again: the root's newest, an open");
  assert.deepEqual(of(c, "alice"), { in: false, devices: [] });
});

test("ix. every order the logs come in gives the same list", () => {
  const w = world();
  handover(w);
  w.alice.say("member", { sub: "bob", email: "bob@x", lock: w.bob.genesis, role: "owner" });
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  const again = new Log("alice");
  w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  const orders = [[w.alice, w.bob, w.carol, again], [again, w.carol, w.bob, w.alice], [w.bob, again, w.alice, w.carol]];
  const said = orders.map((ls, i) => {
    const c = station(w, i % 2);
    for (const l of ls) bring(c, l);
    return JSON.stringify(["alice", "bob", "carol"].map((sub) => of(c, sub)));
  });
  assert.deepEqual(new Set(said).size, 1, said.join("\n"));
  assert.equal(JSON.parse(said[0]!)[0].lock, again.genesis);
});

// A reader from before reads a removal naming the root's log as nothing, so every reader is to make the same state:
// a station says `rootout` in its GET /lock `serves` (a core says such a removal only where every station the list
// names says it), and a core of a release under ROOT_OUT_FROM_BUILD is told to update (`movedTooOld`, 426) only in a
// workspace whose state in force has the root's person out of `~root`: nowhere else is anyone told anything.
test("a station says `rootout` in what it serves", () => {
  const { c } = setUp();
  const [status, body] = lockRoute(c, "GET", [], Buffer.alloc(0), viewerOf("bob", { base: ed() }, "owner") as never) as [number, any];
  assert.equal(status, 200);
  assert.ok((body.serves as string[]).includes("rootout"), JSON.stringify(body.serves));
});

test("a core under ROOT_OUT_FROM_BUILD is told to update only where the root's person is out of `~root`: not before, not for a removal that names nothing of hers, not for an admit alone", () => {
  const { w, c } = setUp();
  const build = MOVED_FROM_BUILD;
  assert.ok(build < ROOT_OUT_FROM_BUILD);
  const v = viewerOf("bob", { base: ed() }, "owner") as never;
  const told = () => [movedTooOld(c, v, build), movedTooOld(c, v, ROOT_OUT_FROM_BUILD), c.rootOut(null)];
  assert.deepEqual(told(), [false, false, false], "as set up");
  const again = new Log("alice");
  w.bob.say("member.remove", { sub: "alice", cancels: [] });
  w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  for (const l of [w.bob, again]) bring(c, l);
  assert.deepEqual(told(), [false, false, false], "a removal naming nothing, an admit alone");
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  bring(c, w.bob);
  assert.deepEqual(told(), [true, false, true], "out of ~root: under the floor told, at it not");
  assert.equal(movedTooOld(c, v, MOVED_FROM_BUILD - 1), true, "under the move's floor, as before");
});

// Which log is hers a station says by the state in force (the lead, 2026-11-14; mesh/serve.ts `ownChainsOf`): her
// devices read it of GET /lock/person and of a refusal's `person`. Her log begun anew (R2) while `~root` binds her, and
// once she is out bound by nothing: both, as before this rule (a device still on R reads what it read before); once an
// owner's admit binds her by R2: R2 alone, so a device of R hears her lock was begun anew. R stays among the
// workspace's logs in every phase, and is never let go as a person's oldest (CHAINS_A_PERSON).
test("the root's person's own logs, as a station tells them: both while `~root` binds her and once she is out; her new one alone once an admit binds her by it; the root's log among the workspace's logs throughout", () => {
  const { w, c } = setUp();
  const r2 = new Log("alice");
  bring(c, r2);
  const own = () => {
    const [, out] = lockPartRoute(c, "person", "GET", Buffer.from(""), viewerOf("alice", r2.app, "owner") as never) as [number, { chains: { genesis: string }[] }];
    return out.chains.map((x) => (x.genesis === w.alice.genesis ? "R" : x.genesis === r2.genesis ? "R2" : "?")).sort().join(",");
  };
  const told = () => {
    const r = refusalOf(c, { lock: {} }, ed().hex, new LockRefusal("refused"), undefined, "alice") as { person?: { genesis: string }[] };
    return (r.person ?? []).map((x) => (x.genesis === w.alice.genesis ? "R" : x.genesis === r2.genesis ? "R2" : "?")).sort().join(",");
  };
  const logs = () => {
    const [, out] = lockPartRoute(c, "logs", "GET", Buffer.from(""), viewerOf("bob", w.bob.app, "owner") as never) as [number, { chains: { genesis: string }[] }];
    return out.chains.some((x) => x.genesis === w.alice.genesis);
  };
  assert.deepEqual([own(), told(), logs()], ["R,R2", "R,R2", true], "R2 begun, `~root` binding her");
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  bring(c, w.bob);
  assert.deepEqual([own(), told(), logs()], ["R,R2", "R,R2", true], "taken out, bound by nothing");
  w.bob.say("member", { sub: "alice", email: "alice@x", lock: r2.genesis, role: "owner" });
  bring(c, w.bob);
  assert.equal((of(c, "alice") as any).lock, r2.genesis);
  assert.deepEqual([own(), told(), logs()], ["R2", "R2", true], "bound by R2");
  // (more of her logs begun anew than a person's few kept: the root's stays)
  for (let i = 0; i < CHAINS_A_PERSON + 1; i++) bring(c, new Log("alice"));
  assert.ok(personChainsOf(c).kept(w.alice.genesis) !== null, "the root's log kept");
  assert.equal(c.locked()?.waiting, undefined, "the state not waiting for it");
});

// The MoonBit program answers a device's reads, its event stream and its marks itself (mesh/served.ts): what it refuses
// a core too old for is told it of each connection with its member (serve.ts `admission`'s `told`), by the rule
// `movedTooOld` goes by (`movedFloor`), and told again as the state in force changes with the connection open. Until
// 2026-11-15 it was told only whether the chain moved: a core under ROOT_OUT_FROM_BUILD where the root's person was out
// was told to update by Node's routes and answered by the program's (round 24 of apps/mbui/e2e/locks-moved.ts).
test("the MoonBit program is told the floor of a connection's workspace: MOVED_FROM_BUILD where its chain moved, ROOT_OUT_FROM_BUILD once the root's person is out of `~root`, told again as she goes out with the connection open", async (t) => {
  const key = new GrantKey("k");
  const { w, c } = setUp([key.jwk]);
  // (no timer of the station's fires here: the credential's expiry, the debounces of its own writes)
  t.mock.method(wall, "after", () => () => {});
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [at, device] = await Promise.all([bind(), bind()]);
  const told: unknown[] = [];
  // (what is told the program, each change once: as Served.viewer tells it)
  const served = { viewer: (_: number, v: { email: string } | null, moved?: boolean, floor?: number | null) => {
    const now = v === null ? null : { email: v.email, moved, floor };
    if (JSON.stringify(told.at(-1)) !== JSON.stringify(now)) told.push(now);
  } } as unknown as Served;
  const admin = { handle: async () => json(200, "{}"), readers: { names: new Map() } } as unknown as Admin;
  void (async () => {
    const conn = await at.accept();
    if (!conn) return;
    // (a connection the front hands requests of to the program: its id there)
    Object.assign(conn, { handed: 1 });
    void serve({ cloud: c, admin, up: () => true, served }, conn).catch(() => {});
  })();
  t.after(async () => {
    c.close();
    await Promise.all([at.close(), device.close()]);
  });
  const conn = await device.connect({ id: at.id() }, ALPN);
  const first = await conn.openBi();
  const control = new Reader(first);
  const credential = key.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub: "bob", email: "bob@x", name: "bob", ws: WS, role: "owner", device: device.id(), sid: "s", iat: NOW, exp: NOW + 3600 });
  await writeLine(first, { credential, protocol: 2, lock: { device: w.bob.app.base.hex, proof: w.bob.app.base.sign(endpointBytes(WS, device.id())) } });
  assert.equal((await control.line()).ok, true, "bob let in");
  // (a request answered: the connection opened by then)
  const stream = await conn.openBi();
  await writeLine(stream, { method: "GET", path: "/admin/api/who", headers: {} });
  await stream.finish();
  assert.equal((await new Reader(stream).line()).status, 200);
  assert.deepEqual(told, [{ email: "bob@x", moved: true, floor: MOVED_FROM_BUILD }], "its chain moved, she in by `~root`");
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  bring(c, w.bob);
  assert.equal(c.rootOut(null), true);
  assert.deepEqual(told.at(-1), { email: "bob@x", moved: true, floor: ROOT_OUT_FROM_BUILD }, "told again as she goes out, the connection open");
  conn.close(0, "done");
});
