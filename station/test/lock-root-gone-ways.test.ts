// The root's person of a moved workspace gone (every device of alice's lost), each step tried on the station's own code
// beside the same step on a chain that never moved, and the way out on the machines (`stillfail lock reset`,
// Cloud.resetLock) on one station of two and on both: whom a refusal tells her new app to ask (serve.ts `leftOf`), what
// another owner's statements still do, what pins a station's lock again (the plane's frame, another station's sync, an
// owner's device's POST /lock) and what a new genesis meets at a station and at the cloud's copy (cloud/src/lock.ts
// `keepLockAt`). What is so on 2026-11-14, held as found: nothing here is a design, and a test whose name says "held as
// found" asserts a fault as it stands (lock-root-gone.test.ts holds three more).
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { type Entry, LockRefusal, endpointBytes, entryHash } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { answerLock, syncWith } from "../src/mesh/lock-sync.ts";
import { inLock, lockRoute, refusalOf } from "../src/mesh/serve.ts";
import { keepLockAt } from "../../cloud/src/lock.ts";
import { type Dev, Log, WS, bring, dev, ed, handover, signed, station, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

type C = ReturnType<typeof station>;
const as = (sub: string, d: { base: any }, role = "member") => ({ viewer: viewerOf(sub, d, role), exp: NOW + 10 * 86400, iat: NOW, sid: "s" });
const lets = (c: C, sub: string, d: { base: any }, role = "member") => {
  const a = as(sub, d, role);
  try {
    return inLock(c, a as never, role, a.viewer.device).viewer.role;
  } catch (e) {
    if (e instanceof LockRefusal) return null;
    throw e;
  }
};
/// What a station's hello refusal tells device `d` of `sub` (`person`: the log its hello brings).
const leftFor = (c: C, d: { base: any }, sub: string, person?: Entry[]) => {
  const endpoint = ed().hex;
  const hello = { lock: { device: d.base.hex, proof: d.base.sign(endpointBytes(WS, endpoint)), ...(person ? { person } : {}) } };
  return (refusalOf(c, hello, endpoint, new LockRefusal("refused"), undefined, sub) as { left?: { approvers: string[]; apps?: boolean } }).left;
};
/// POST /lock of `entries` (and, moved, the logs and bodies) by `sub`'s device `d` in role `role`: its status and body.
const post = (c: C, sub: string, d: { base: any }, role: string, entries: Entry[], logs?: Log[]) => {
  const said = { entries, ...(logs ? { logs: logs.map((l) => l.entries), bodies: logs.flatMap((l) => [...l.bodies.values()]) } : {}) };
  return lockRoute(c, "POST", [], Buffer.from(JSON.stringify(said)), viewerOf(sub, d, role) as never);
};
/// The next entry of `c`'s chain (the home one), signed by `key`.
const next = (c: C, kind: string, body: unknown, key: Dev["signer"]): Entry => {
  const head = c.lockAfter(-1).at(-1)!;
  return signed({ v: 1, ws: WS, seq: head.seq + 1, prev: entryHash(head), at: NOW, kind, body }, key);
};
const appOf = (sub: string, d: Dev, label = `${sub}'s new app`) => ({ id: d.base.hex, sub, kind: "app", label, sign_key: d.signer.id });

/// Moved: alice the root, bob made an owner by her, carol a member; both stations given every log.
function moved() {
  const w = world();
  const said = handover(w);
  w.alice.say("member", { sub: "bob", email: "bob@x", lock: w.bob.genesis, role: "owner" });
  const c = [station(w, 0), station(w, 1)];
  for (const s of c) for (const l of [w.alice, w.bob, w.carol]) bring(s, l);
  return { w, c, said };
}
/// Never moved: the same chain, bob made an owner on it by alice; both stations pin it.
function unmoved() {
  const w = world();
  const c = [station(w, 0, false), station(w, 1, false)];
  const owner = next(c[0]!, "member", { sub: "bob", email: "bob@x", role: "owner" }, w.alice.app.signer);
  for (const s of c) assert.equal(post(s, "alice", w.alice.app, "owner", [owner])[0], 200);
  return { w, c, chain: [w.first, owner] };
}
/// Moved, alice the only member: a chain naming her alone, her log opening it and naming both stations.
function alone() {
  const w = world();
  const body = { ...(w.first.body as any), members: [{ sub: "alice", email: "alice@x", role: "owner" }], devices: [(w.first.body as any).devices[0]] };
  const first = signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body }, w.alice.app.signer);
  const mv = signed({ v: 1, ws: WS, seq: 1, prev: entryHash(first), at: 1000, kind: "moved", body: { root: w.alice.genesis } }, w.alice.app.signer);
  w.alice.say("open", { ...w.settings, email: "alice@x" });
  for (const s of w.stations.slice(0, 2)) w.alice.say("station", { key: s.hex });
  const v = { ...w, first, moved: mv };
  const c = [station(v, 0), station(v, 1)];
  for (const s of c) bring(s, w.alice);
  return { w: v, c };
}
const reset = (s: C) => {
  assert.equal(Cloud.resetLock(s.data), true);
  return new Cloud(s.data, false);
};

// ── A1: her new app, whom it is told to ask ──

test("A1 moved, held as found: alice's new app (no log known, then her log begun anew) is told to ask only her lost app, not bob's", () => {
  const { w, c } = moved();
  const phone = dev();
  assert.equal(lets(c[0]!, "alice", phone, "owner"), null, "refused");
  assert.deepEqual(leftFor(c[0]!, phone, "alice"), { approvers: [w.alice.app.base.hex], apps: true }, "her lost app alone");
  const again = new Log("alice", phone);
  assert.deepEqual(leftFor(c[0]!, phone, "alice", again.entries), { approvers: [w.alice.app.base.hex], apps: true }, "the same with her new log brought");
});

test("A1 moved, held as found: carol an admin and bob not there: alice's new app still told her lost app alone; carol's admit of her new log binds nothing", () => {
  const { w, c, said } = moved();
  w.alice.say("member.remove", { sub: "carol", cancels: [said.carol.h] });
  w.alice.say("member", { sub: "carol", email: "carol@x", lock: w.carol.genesis, role: "admin" });
  for (const s of c) bring(s, w.alice);
  assert.equal(c[0]!.locked()?.state?.members.get("carol")?.role, "admin");
  const phone = dev();
  const again = new Log("alice", phone);
  assert.deepEqual(leftFor(c[0]!, phone, "alice", again.entries)?.approvers, [w.alice.app.base.hex]);
  w.carol.say("member", { sub: "alice", email: "alice@x", lock: again.genesis, role: "owner" });
  bring(c[0]!, w.carol);
  assert.equal(c[0]!.locked()?.state?.persons.get("alice"), w.alice.genesis, "bound by her lost log still");
  bring(c[0]!, again);
  assert.equal(lets(c[0]!, "alice", phone, "owner"), null, "her new app refused");
});

test("A1 moved, alice the only member, held as found: her new app is told her lost app alone; no other device anywhere", () => {
  const { w, c } = alone();
  assert.deepEqual([...c[0]!.locked()!.state!.members.keys()], ["alice"]);
  const phone = dev();
  assert.deepEqual(leftFor(c[0]!, phone, "alice"), { approvers: [w.alice.app.base.hex], apps: true });
  assert.equal(lets(c[0]!, "alice", phone, "owner"), null);
});

// ── A4: the same on a chain that never moved ──

test("A4 unmoved: alice's new app refused and told nothing (`left` absent); bob, an owner, puts it on the chain: let in, not her own (her lost app is), so its signatures do not count", () => {
  const { w, c } = unmoved();
  const phone = dev();
  assert.equal(lets(c[0]!, "alice", phone, "owner"), null, "refused");
  assert.equal(leftFor(c[0]!, phone, "alice"), undefined, "no `left` before a move: the core asks the owners and admins the chain names");
  const put = next(c[0]!, "device", appOf("alice", phone), w.bob.app.signer);
  assert.equal(post(c[0]!, "bob", w.bob.app, "owner", [put])[0], 200, "bob's entry taken");
  assert.equal(lets(c[0]!, "alice", phone, "owner"), "owner", "her new app let in");
  assert.equal(c[0]!.chain()?.state?.devices.get(phone.base.hex)?.own, false, "not her own: she has one already");
});

test("A4 unmoved, held as found: bob takes her lost app off and puts her new one on: still not her own (she signed on the chain before), so its `disable` is taken and changes nothing", () => {
  const { w, c } = unmoved();
  const phone = dev();
  const off = next(c[0]!, "device.remove", { id: w.alice.app.base.hex }, w.bob.app.signer);
  assert.equal(post(c[0]!, "bob", w.bob.app, "owner", [off])[0], 200);
  const put = next(c[0]!, "device", appOf("alice", phone), w.bob.app.signer);
  assert.equal(post(c[0]!, "bob", w.bob.app, "owner", [put])[0], 200);
  assert.equal(lets(c[0]!, "alice", phone, "owner"), "owner", "let in");
  assert.equal(c[0]!.chain()?.state?.devices.get(phone.base.hex)?.own, false, "not her own");
  const disable = next(c[0]!, "disable", {}, phone.signer);
  const [status, out] = post(c[0]!, "alice", phone, "owner", [disable]);
  assert.deepEqual([status, c[0]!.locked() === null], [200, false], `her off: ${JSON.stringify(out)}`);
});

// ── A3: with alice gone, what bob can still do ──

test("A3 moved: bob, an owner, still adds and admits a member, changes a role, takes a member out, protects and takes out a station, approves his own device and web page", () => {
  const { w, c, said } = moved();
  const s = c[0]!;
  const st = () => s.locked()!.state!;
  const dan = new Log("dan");
  w.bob.say("member", { sub: "dan", email: "dan@x", lock: dan.genesis, role: "member" });
  bring(s, w.bob);
  bring(s, dan);
  assert.equal(st().members.get("dan")?.role, "member", "dan added");
  assert.equal(lets(s, "dan", dan.app), "member", "dan's app let in");
  w.bob.say("member.remove", { sub: "carol", cancels: [said.carol.h] });
  w.bob.say("member", { sub: "carol", email: "carol@x", lock: w.carol.genesis, role: "admin" });
  bring(s, w.bob);
  assert.equal(st().members.get("carol")?.role, "admin", "carol's role changed");
  const c2 = w.bob.say("member.remove", { sub: "dan", cancels: [[...w.bob.bodies.entries()].find(([, b]) => b.kind === "member" && b.sub === "dan")![0]] });
  bring(s, w.bob);
  assert.equal(st().members.has("dan"), false, "dan taken out");
  assert.equal(lets(s, "dan", dan.app), null, "dan's app out");
  assert.ok(c2.h.length > 0);
  const s2 = w.stations[2]!.hex;
  const protect = w.bob.say("station", { key: s2 });
  bring(s, w.bob);
  assert.ok(st().stations.has(s2), "a station protected");
  w.bob.say("station.remove", { key: s2, cancels: [protect.h] });
  w.bob.say("station.remove", { key: w.stations[1]!.hex, cancels: [said.s1.h] });
  bring(s, w.bob);
  assert.equal(st().stations.has(s2), false, "that station out");
  assert.equal(st().stations.has(w.stations[1]!.hex), false, "s1, which alice named, out");
  const phone = dev();
  w.bob.add("device", { key: phone.key.id, id: phone.base.hex, label: "phone", sign_key: phone.signer.id });
  const web = ed();
  w.bob.add("web", { id: web.hex, label: "browser", exp: NOW + 86400 }, w.bob.app.key, NOW);
  bring(s, w.bob);
  assert.equal(lets(s, "bob", phone, "owner"), "owner", "his new device");
  assert.equal(lets(s, "bob", { base: web }, "owner"), "owner", "his web page");
});

test("A3 moved, held as found: bob's off counts for nothing (the root's log alone says it) and his open neither", () => {
  const { w, c } = moved();
  w.bob.say("off", {});
  bring(c[0]!, w.bob);
  assert.notEqual(c[0]!.locked(), null, "still on");
  w.bob.say("open", { ...w.settings, email: "bob@x" });
  bring(c[0]!, w.bob);
  assert.notEqual(c[0]!.locked(), null);
});

test("A3 unmoved: bob, an owner, turns the lock off with his own app's `disable`", () => {
  const { w, c } = unmoved();
  assert.equal(post(c[0]!, "bob", w.bob.app, "owner", [next(c[0]!, "disable", {}, w.bob.app.signer)])[0], 200);
  assert.equal(c[0]!.locked(), null);
});

// ── B1: reset on one station of two ──

for (const kind of ["moved", "unmoved"] as const) {
  test(`B1 ${kind}: reset on s0; the plane's frame of the chain pins nothing; s1's sync brings it nothing either way`, async () => {
    const t = kind === "moved" ? moved() : unmoved();
    const r = reset(t.c[0]!);
    const chain = kind === "moved" ? [t.w.first, t.w.moved] : (t as ReturnType<typeof unmoved>).chain;
    // (the plane's `lock` frame of the home workspace: a station enrolled with no lock's hash pins none by it)
    applyState(r, JSON.stringify({ type: "lock", entries: chain }));
    assert.equal(r.chain(), null, "the plane's frame pins nothing");
    // s1 bringing s0 level (s1 asks, s0 answers) and s0 bringing s1 (s0 pins none: it asks nothing)
    const s1 = t.c[1]!;
    await syncWith(s1, async (_p, ws, req) => answerLock(r, req, ws, t.w.stations[1]!.hex) as any, t.w.stations[0]!.hex);
    assert.equal(r.chain(), null, "s1's sync gives it nothing: it says no lock, so s1 offers none");
    assert.throws(() => answerLock(r, { method: "lock.put", entries: chain }), /no workspace lock/, "and a put is refused: a peer never pins one");
    await syncWith(r, async (_p, ws, req) => answerLock(s1, req, ws, t.w.stations[0]!.hex) as any, t.w.stations[1]!.hex);
    assert.equal(r.chain(), null);
  });
}

test("B1 moved: on the reset station bob's app brings the moved chain with the logs and bodies (POST /lock): pinned, bob still an owner there", () => {
  const { w, c } = moved();
  const r = reset(c[0]!);
  const [status, out] = post(r, "bob", w.bob.app, "owner", [w.first, w.moved], [w.alice, w.bob, w.carol]);
  assert.equal(status, 200, JSON.stringify(out));
  assert.equal(r.chain()?.state?.head, entryHash(w.moved));
  assert.equal(r.locked()?.state?.members.get("alice")?.role, "owner", "the root alice still");
  assert.equal(lets(r, "alice", dev(), "owner"), null, "her new app refused again");
});

test("B1 moved: the moved chain brought without the logs and bodies is refused", () => {
  const { w, c } = moved();
  const r = reset(c[0]!);
  const [status, out] = post(r, "bob", w.bob.app, "owner", [w.first, w.moved]);
  assert.equal(status, 403);
  assert.match(String((out as any).error), /logs and bodies/);
});

test("B1 unmoved: on the reset station bob's app brings the chain (POST /lock): pinned", () => {
  const t = unmoved();
  const r = reset(t.c[0]!);
  assert.equal(post(r, "bob", t.w.bob.app, "owner", t.chain)[0], 200);
  assert.equal(r.chain()?.state?.head, entryHash(t.chain.at(-1)!));
});

// ── B2: reset on every station, safe mode turned on anew ──

/// A new genesis bob's app makes: the members the workspace has, bob its owner, his app its one device, both stations.
const anew = (w: ReturnType<typeof world>, owner: Log, members: string[]) => signed({
  v: 1, ws: WS, seq: 0, prev: null, at: NOW, kind: "genesis",
  body: {
    owner: owner.sub, origins: w.settings.origins, rp_id: w.settings.rp_id, cloud_keys: { keys: [] }, passkeys: [], gateways: [],
    members: members.map((sub) => ({ sub, email: `${sub}@x`, role: sub === owner.sub ? "owner" : "member" })),
    devices: [{ id: owner.app.base.hex, sub: owner.sub, kind: "app", label: owner.sub, sign_key: owner.app.signer.id }],
    stations: w.stations.slice(0, 2).map((s, i) => ({ key: s.hex, name: `s${i}` })),
  },
}, owner.app.signer);

for (const kind of ["moved", "unmoved"] as const) {
  test(`B2 ${kind}: reset on both; bob's new genesis (POST /lock) pinned on each, alice's new app out until he puts it on; the old chain's devices refused`, () => {
    const t = kind === "moved" ? moved() : unmoved();
    const r = t.c.map(reset);
    for (const s of r) assert.equal(lets(s, "carol", t.w.carol.app), "member", "unlocked: the credential alone");
    const g = anew(t.w, t.w.bob, ["alice", "bob", "carol"]);
    for (const s of r) assert.equal(post(s, "bob", t.w.bob.app, "owner", [g])[0], 200, "pinned");
    assert.equal(r[0]!.chain()?.state?.moved, undefined, "a chain that never moved");
    assert.equal(lets(r[0]!, "carol", t.w.carol.app), null, "carol's app is on no chain now: refused");
    assert.equal(leftFor(r[0]!, t.w.carol.app, "carol"), undefined, "and told nothing of whom to ask (as before a move)");
    const phone = dev();
    const put = signed({ v: 1, ws: WS, seq: 1, prev: entryHash(g), at: NOW, kind: "device", body: appOf("alice", phone) }, t.w.bob.app.signer);
    assert.equal(post(r[0]!, "bob", t.w.bob.app, "owner", [put])[0], 200);
    assert.equal(lets(r[0]!, "alice", phone, "member"), "member", "alice's new app let in, in the role bob's genesis gave her");
    assert.equal(r[0]!.chain()?.state?.devices.get(phone.base.hex)?.own, true, "her own: her first on this chain");
  });
}

test("B2 moved, alice the only member: reset on both; her new app's own genesis pinned (its credential's role owner, the genesis naming it)", () => {
  const { w, c } = alone();
  const r = c.map(reset);
  const again = new Log("alice", dev());
  const g = anew(w, again, ["alice"]);
  for (const s of r) assert.equal(post(s, "alice", again.app, "owner", [g])[0], 200);
  assert.equal(lets(r[0]!, "alice", again.app, "owner"), "owner");
});

test("B2: a new genesis by a member who is no owner is refused at a reset station", () => {
  const t = unmoved();
  const r = reset(t.c[0]!);
  const g = anew(t.w, t.w.carol, ["carol"]);
  assert.equal(post(r, "carol", t.w.carol.app, "member", [g])[0], 403);
});

for (const kind of ["moved", "unmoved"] as const) {
  test(`B2 ${kind}, the cloud's copy: a new genesis over the kept chain is refused lock_exists; after the owner's clearLock (none kept) it is taken`, () => {
    const t = kind === "moved" ? moved() : unmoved();
    const kept = { entries: (kind === "moved" ? [t.w.first, t.w.moved] : (t as ReturnType<typeof unmoved>).chain) as any[], aside: [] };
    const g = anew(t.w, t.w.bob, ["alice", "bob", "carol"]) as any;
    assert.throws(() => keepLockAt(kept, [g], NOW, false), (e: any) => e?.code === "lock_exists");
    assert.throws(() => keepLockAt(kept, [g], NOW, true), (e: any) => e?.code === "lock_exists", "as another keeper's too");
    const took = keepLockAt({ entries: [], aside: [] }, [g], NOW, false);
    assert.equal(took.changed, true);
    assert.equal(took.kept.entries.length, 1);
  });
}
