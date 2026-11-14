// The workspace lock on a device (src/views/lock.ts): a device not in it waits and asks nothing by itself; one is
// approved only face to face (views/pair.ts), never with a press on a request kept at the cloud; a station's refusal
// names the workspace and where to approve; a change does not wait on the stations, nor on the cloud's "too many
// requests"; what a hello brings. Against a cloud that keeps chains and requests (the station fixture's host), on the
// test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { hooks } from "../src/core/execute.ts";
import { CoreError, HostError } from "../src/error.ts";
import { t } from "../src/i18n.ts";
import { type Entry, Signer, entryHash, next, shortCode } from "../src/lock.ts";
import { utf8 } from "../src/util.ts";
import { BEHIND_MS, BEHIND_TRIES, Lock, fold, held, pendingHeld, read, refusedAgain, signerKnown } from "../src/views/lock.ts";
import { jsonResponse } from "../src/testing.ts";
import { ME, PHONE, elsewhere, genesis, rig, unhex } from "./lock-rig.ts";
import { stationLater, stationReplies, status } from "./station-fixture.ts";

/// The signing key the lock's genesis names for this device.
const signerOfLock = (r: Awaited<ReturnType<typeof rig>>) => (r.cloud.chains.get("ws")![0]!.body as { devices: { sign_key: string }[] }).devices[0]!.sign_key;

const phoneRequest = { base: PHONE, sub: "s2", email: "b@x.com", kind: "app", label: "Pixel 8", sign_key: null, code: shortCode(PHONE), created_at: 1500 };
/// Another member's phone in the lock: one a trusted device may take out.
const phone = { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" };
/// A station of the workspace's that the lock names (lock-rig.ts `rig`'s `station`), and an older client's endpoint:
/// iroh ids, as the stations' rules take them.
const ST = "5a".repeat(32);
const OLDER = "9a".repeat(32);

test("a device not in the lock waits and asks nothing by itself", async () => {
  const r = await rig((_me) => ({ ws: genesis("ws", elsewhere(), false) }), (host) => {
    // No key kept yet, and the keychain refusing to keep one (a host whose `secure.*` does not work).
    host.secureSet = () => Effect.fail(new HostError("secure.set is not supported"));
    const get = host.secureGet!;
    host.secureGet = (key: string, opts: { user: boolean }) => (key === Signer.KEY ? Effect.succeed(null) : get(key, opts));
  });
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  await r.host.time.pass(15_000);
  const v = await lock();
  assert.deepEqual(r.cloud.asked, [], "nothing asked by itself");
  assert.equal(v.me.waiting, true, "its page shows instead of the workspace's");
  // A station refusing it asks nothing either.
  hooks.lockRefused!(r.core.inner, "ws", "st", null);
  await r.host.time.pass(5_000);
  assert.deepEqual(r.cloud.asked, []);
});

test("a device is approved only by the code typed on it: a request kept at the cloud (an older client's) is not shown, and no press approves it", async () => {
  // This app signs; an older client's phone asked through the cloud, as clients did before approving face to face.
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  r.cloud.requests.set("ws", [phoneRequest]);
  const v = await (await r.watch({ topic: "lock", workspace: "ws" }))();
  assert.equal(v.requests, undefined, "no list of devices to approve with a press");
  assert.equal(v.attention, 0);
  for (const name of ["lock.confirm", "lock.deny", "lock.request"]) {
    await assert.rejects(r.ask(name, { workspace: "ws", device: PHONE, code: shortCode(PHONE) }), Error, name);
  }
  assert.deepEqual(r.cloud.posted, [], "nothing signed");
  assert.deepEqual(r.cloud.asked, []);
});

test("a device that made its signing key after it started, then was confirmed: its vault sees it confirmed without a restart", async () => {
  const owner = elsewhere();
  // The owner's other app signs the lock; this one kept no key when it started (a device new to security mode).
  const r = await rig((_me) => ({ ws: genesis("ws", owner, true, [], {}, "ef".repeat(32)) }), (host) => {
    host.secure.delete(Signer.KEY);
    host.storage.delete(Signer.KEY);
  });
  // The vault page open from the start: it follows the lock as it is read.
  const vaults = await r.watch({ topic: "vaults", workspace: "ws" });
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  assert.equal((await lock()).me.waiting, true);
  assert.deepEqual([(await vaults()).locked, (await vaults()).canSign], [true, false]);
  // Asked by hand (`lock.pair`): its key made now; the owner's other device approves it.
  signerKnown(r.core.inner, (await Effect.runPromise(Signer.make(r.host))).id);
  const mine = Effect.runSync(Signer.load(r.host))!;
  const chain = r.cloud.chains.get("ws")!;
  const e = next("ws", r.cloud.head("ws"), 2000, "device", { id: ME, sub: "s1", kind: "app", label: "this", sign_key: mine.id });
  chain.push({ ...e, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } });
  r.core.inner.runner.fork(Effect.ignore(read(r.core.inner, "ws")));
  const l = await lock();
  assert.deepEqual([l.me.waiting, l.signs], [false, true]);
  const v = await vaults();
  assert.deepEqual([v.locked, v.canSign], [true, true], "the vault page offers to set up, not 'not confirmed'");
});

test("an app in the lock without its signing key (the genesis put it in before it kept one) is not waiting, but may be made one that signs", async () => {
  const owner = elsewhere();
  const r = await rig((_me) => ({ ws: genesis("ws", owner, true, [], {}, "ef".repeat(32), [{ id: ME, sub: "s1", kind: "app", label: "Windows" }]) }));
  const v = await (await r.watch({ topic: "lock", workspace: "ws" }))();
  assert.deepEqual([v.me.confirmed, v.me.waiting, v.signs, v.me.unsigned], [true, false, false, true]);
  // One that signs with its key is neither.
  const s = await rig((me) => ({ ws: genesis("ws", me, true) }));
  const w = await (await s.watch({ topic: "lock", workspace: "ws" }))();
  assert.deepEqual([w.signs, w.me.unsigned ?? false], [true, false]);
});

test("an iOS update that moved where its signing key was kept: the key the lock names is found again, and it signs", async () => {
  // The lock names this app's key; the update left it where the app's old home was, and approving face to face (none
  // online to approve) made another since.
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }), (host) => {
    host.securePastValues.set(Signer.KEY, [new Uint8Array(32).fill(7), host.secure.get(Signer.KEY)!.value]);
    host.secure.set(Signer.KEY, { value: new Uint8Array(32).fill(9), user: false });
  });
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  await r.host.time.pass(1_000);
  const v = await lock();
  assert.deepEqual([v.signs, v.me.unsigned ?? false], [true, false]);
  assert.equal(Effect.runSync(Signer.load(r.host))!.id, signerOfLock(r), "kept as this one's again");
});

test("a station's refusal names the workspace and the code to approve, where the device is not in that workspace's lock", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true), w2: genesis("w2", elsewhere(), false) }));
  await r.watch({ topic: "lock", workspace: "w2" });
  const said = hooks.lockRefused!(r.core.inner, "w2", "st2", null);
  assert.equal(said?.code, "lock_unconfirmed");
  assert.match(said!.message, /日常/);
  assert.ok(said!.message.includes(shortCode(ME)), said!.message);
  // Not asked again until its lock moves on, saying the same.
  const again = hooks.lockWaiting!(r.core.inner, "w2", "st2");
  assert.equal(again?.message, said!.message);
});


test("a change to the lock answers though its one station is offline, not once every station of the lock has heard: pending, the cloud not sent it", async () => {
  // `st` is protected, and never answers what it is brought: offline.
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: ST, name: "studio" }], {}, ME, [phone]) }), (host) => {
    stationLater(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/lock") ? new Promise(() => {}) : undefined));
  }, ST);
  const done = await r.ask("lock.removeDevice", { workspace: "ws", device: PHONE });
  assert.equal(done.pending.state, "waiting");
  assert.deepEqual(r.cloud.posted, []);
  assert.deepEqual(pendingHeld(r.core.inner, "ws").map((p) => [p.entry.kind, (p.entry.body as { id: string }).id]), [["device.remove", PHONE]]);
});

test("a change the cloud kept, its answer lost on the way back: done, not said to have failed", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], {}, ME, [phone]) }));
  r.cloud.lose.posts = 1;
  await r.ask("lock.removeDevice", { workspace: "ws", device: PHONE });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device.remove", PHONE]]);
  // Asked again (the person not sure it went): nothing more is signed, the device is gone already.
  await assert.rejects(r.ask("lock.removeDevice", { workspace: "ws", device: PHONE }));
  assert.equal(r.cloud.posted.length, 1);
});

test("a web page whose approval ran out waits to be approved again, and a station's refusal says so, not that the station has not heard", async () => {
  // This device a web page of s1's in the lock, its 30 days over (the stations refuse it: "this device's confirmation ran out").
  const r = await rig(() => ({ ws: genesis("ws", elsewhere(), false, [], {}, ME, [{ id: ME, sub: "s1", kind: "web", label: "Chrome", exp: 2000 }]) }));
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const me = (await lock()).me;
  assert.deepEqual([me.confirmed, me.waiting], [false, true], "it waits, as one not in the lock");
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  const said = hooks.lockRefused!(r.core.inner, "ws", "st", null);
  assert.equal(said?.code, "lock_unconfirmed");
  assert.ok(said!.message.includes(shortCode(ME)), said!.message);
  await r.host.time.pass(BEHIND_MS * 3);
  assert.deepEqual(woke, [], "not tried again as a station behind");
});

test("a station that takes none of the workspace's members, the lock turned on after it joined: protected all the same, the station pinning it from the cloud", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }), undefined, ST);
  await r.watch({ topic: "lock", workspace: "ws" });
  // (as the mesh says such a station's refusal)
  const call = r.core.inner.stations.requests.call.bind(r.core.inner.stations.requests);
  r.core.inner.stations.requests.call = ((addr: { station: string }, method: string, path: string, ...rest: unknown[]) =>
    addr.station === ST && method === "GET" && path.startsWith("/lock") ? Effect.fail(new CoreError("lock_station", t("core-logic.mesh.lock_station.unpinned"))) : (call as any)(addr, method, path, ...rest)) as never;
  const done = await r.ask("lock.joinStation", { workspace: "ws", station: ST });
  // (pending until the station shows it took it; the cloud, its only way there, sent it all the same)
  assert.equal(done.pending.state, "waiting");
  assert.deepEqual(r.cloud.chains.get("ws")!.slice(1).map((e) => [e.kind, (e.body as { key: string }).key]), [["station", ST]]);
});

test("a station that refuses this device though the lock names it has not heard yet: tried again shortly, not held", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  const said = hooks.lockRefused!(r.core.inner, "ws", "st", null);
  assert.equal(said?.code, "lock_unconfirmed");
  assert.equal(hooks.lockWaiting!(r.core.inner, "ws", "st"), null, "asked again as any station would be");
  await r.host.time.pass(BEHIND_MS - 10);
  assert.deepEqual(woke, []);
  await r.host.time.pass(20);
  assert.deepEqual(woke, ["ws/st"], "and woken soon to be");
  // Refused again and again: a few more tries, each later, then no more for this head.
  for (let i = 1; i < 8; i++) {
    hooks.lockRefused!(r.core.inner, "ws", "st", null);
    await r.host.time.pass(BEHIND_MS * (i + 1) + 10);
  }
  assert.equal(woke.length, BEHIND_TRIES, "as often as BEHIND_TRIES");
});

// The real-station end-to-end's round 6 (2026-11-12, twice in seven runs): a device taken off its person's own lock,
// the cloud frozen, refused by the station for that lock 5 ms before the station took the entry that takes it out of
// the workspace's lock; its held workspace lock still named it, and nothing tried that station again, so it never heard.
async function offItsOwnLock() {
  const owner = elsewhere();
  const OWNER = "ef".repeat(32);
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], {}, ME, [{ id: OWNER, sub: "s1", kind: "app", label: "owner's", sign_key: owner.id }]) }));
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const vaults = await r.watch({ topic: "vaults", workspace: "ws" });
  const signedOn = (kind: string, body: unknown): Entry => {
    const e = next("ws", r.cloud.head("ws"), r.host.nowMs() / 1000, kind, body);
    const s = { ...e, sig: { key: owner.id, alg: "Ed25519" as const, sig: owner.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } } as Entry;
    r.cloud.chains.set("ws", [...r.cloud.chains.get("ws")!, s]);
    return s;
  };
  // Its person bound a lock of their own here that this device is not on.
  signedOn("person", { sub: "s1", person: "ab".repeat(32) });
  r.core.inner.runner.fork(Effect.ignore(read(r.core.inner, "ws")));
  await r.host.time.pass(1_000);
  assert.equal(held(r.core.inner, "ws")!.entries.at(-1)!.kind, "person");
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  return { r, lock, vaults, signedOn, woke };
}

test("refused for its person's own lock while the workspace's lock held here still names it: tried again shortly, and hears the entry that takes it out", async () => {
  const w = await offItsOwnLock();
  const said = hooks.lockRefused!(w.r.core.inner, "ws", "st", null);
  assert.equal(said?.code, "lock_unconfirmed");
  assert.equal(hooks.lockWaiting!(w.r.core.inner, "ws", "st"), null, "asked again");
  await w.r.host.time.pass(BEHIND_MS + 10);
  assert.deepEqual(w.woke, ["ws/st"], "tried again within BEHIND_MS");
  // Meanwhile the station took the entry taking it out; its refusal now tells it.
  const out = w.signedOn("device.remove", { id: ME });
  hooks.lockRefused!(w.r.core.inner, "ws", "st", null, { entries: [out] });
  await w.r.host.time.pass(500);
  assert.equal(entryHash(held(w.r.core.inner, "ws")!.entries.at(-1)!), entryHash(out), "heard");
  const l = await w.lock();
  assert.ok(!l.signs && !(l.members ?? []).some((m: any) => (m.groups ?? []).some((g: any) => (g.devices ?? []).some((d: any) => d.mine && d.signs))), JSON.stringify(l.me));
  assert.equal((await w.vaults()).canSign, false, "its vault says it is out");
  // Not named any more: refused again (as the try already set going is), held until the lock moves on, no more tries.
  await w.r.host.time.pass(BEHIND_MS * 2 + 10);
  hooks.lockRefused!(w.r.core.inner, "ws", "st", null);
  assert.equal(hooks.lockWaiting!(w.r.core.inner, "ws", "st")?.code, "lock_unconfirmed", "held");
  const tries = w.woke.length;
  assert.ok(tries <= 2, `${tries} tries`);
  await w.r.host.time.pass(BEHIND_MS * (BEHIND_TRIES + 2));
  assert.equal(w.woke.length, tries, "no more");
});

test("refused for its person's own lock and nothing changes: tried again BEHIND_TRIES times, then not asked until the lock moves on", async () => {
  const w = await offItsOwnLock();
  for (let i = 0; i < 8; i++) {
    hooks.lockRefused!(w.r.core.inner, "ws", "st", null);
    await w.r.host.time.pass(BEHIND_MS * (i + 1) + 10);
  }
  assert.equal(w.woke.length, BEHIND_TRIES, "as often as BEHIND_TRIES");
  assert.equal(hooks.lockWaiting!(w.r.core.inner, "ws", "st")?.code, "lock_unconfirmed", "then held until the lock moves on");
});

test("a device the lock names without its signing key signs nothing: the cloud gets no entry the stations would refuse", async () => {
  // This app is in the lock without its key (put in before it kept one), and keeps one now; an older device signed so,
  // the cloud kept it, and every station refused it and all after it (2026-10-24).
  const owner = elsewhere();
  const r = await rig(() => ({ ws: genesis("ws", owner, false, [], {}, ME, [{ id: "ef".repeat(32), sub: "s1", kind: "app", label: "owner's", sign_key: owner.id }, { id: ME, sub: "s1", kind: "app", label: "this" }, phone]) }));
  await assert.rejects(r.ask("lock.removeDevice", { workspace: "ws", device: PHONE }), (e: { code: string }) => e.code === "lock_no_signer");
  assert.deepEqual(r.cloud.posted, []);
});

test("a station that keeps another lock says so, and is neither tried again as behind nor shown protected", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: ST, name: "studio" }]) }), undefined, ST);
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  // Its head is of another genesis (the lock turned on again while it kept the old one).
  const said = hooks.lockRefused!(r.core.inner, "ws", ST, { seq: 0, hash: "00".repeat(32), genesis: "00".repeat(32) });
  assert.equal(said?.code, "lock_other");
  assert.match(said!.message, /stillfail lock reset/);
  assert.equal(hooks.lockWaiting!(r.core.inner, "ws", ST)?.code, "lock_other", "not asked again until the lock moves on");
  await r.host.time.pass(BEHIND_MS * 4);
  assert.deepEqual(woke, []);
  assert.ok(!(await lock()).stations.some((s: { id: string; protected: boolean }) => s.id === ST && s.protected));
  // Behind on this one (its genesis, nothing after): as before, tried again shortly.
  const g = r.cloud.chains.get("ws")![0]!;
  assert.equal(hooks.lockRefused!(r.core.inner, "ws", "st2", { seq: 0, hash: entryHash(g), genesis: entryHash(g) })?.code, "lock_unconfirmed");
});

test("a hello brings what put this device in the lock lately, for a station that has not heard of it yet", async () => {
  const owner = elsewhere();
  const r = await rig(() => ({ ws: genesis("ws", owner, false) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const g = r.cloud.chains.get("ws")![0]!;
  const head = (e: Entry) => ({ seq: e.seq, hash: entryHash(e), genesis: entryHash(g) });
  const sign = (e: ReturnType<typeof next>): Entry => ({ ...e, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } });
  // Not in the lock: nothing to bring.
  assert.equal(r.core.inner.cloudSync.carry!("ws"), null);
  const approval = sign(next("ws", head(g), r.host.nowMs() / 1000, "device", { id: ME, sub: "s1", kind: "app", label: "this" }));
  const another = sign(next("ws", head(approval), r.host.nowMs() / 1000, "device", { id: PHONE, sub: "s2", kind: "app", label: "phone" }));
  r.cloud.chains.set("ws", [g, approval, another]);
  r.core.inner.data.put("lock", "ws", { head: head(another), entries: [g, approval, another] });
  assert.deepEqual(r.core.inner.cloudSync.carry!("ws"), [approval, another], "from the one that put it in on");
  // Put in long since: every station has heard by now.
  const old = sign(next("ws", head(g), r.host.nowMs() / 1000 - 8 * 86400, "device", { id: ME, sub: "s1", kind: "app", label: "this" }));
  r.cloud.chains.set("ws", [g, old]);
  r.core.inner.data.put("lock", "ws", { head: head(old), entries: [g, old] });
  assert.equal(r.core.inner.cloudSync.carry!("ws"), null);
  // Its person made a member lately too (their first device): a station takes no device of someone it has not heard of.
  const made = sign(next("ws", head(g), r.host.nowMs() / 1000, "member", { sub: "s3", email: "c@x.com", role: "member" }));
  const first = sign(next("ws", head(made), r.host.nowMs() / 1000, "device", { id: ME, sub: "s3", kind: "app", label: "this" }));
  r.cloud.chains.set("ws", [g, made, first]);
  r.core.inner.data.put("lock", "ws", { head: head(first), entries: [g, made, first] });
  assert.deepEqual(r.core.inner.cloudSync.carry!("ws"), [made, first], "from the one that made them a member on");
});

test("a change the cloud answers too many requests for is asked again a while later, not failed at once", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], {}, ME, [phone]) }));
  // The account's budget for this minute spent (by its other devices): the next two asks are turned away.
  let limited = 2;
  stationReplies(r.host, (req) => (req.url.includes("/lock") && limited-- > 0 ? status(429, { error: "rate_limited" }) : r.cloud.reply(req)));
  await r.ask("lock.removeDevice", { workspace: "ws", device: PHONE });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device.remove", PHONE]]);
});

test("the lock moved on while the cloud answers too many requests: read again a while later, not left behind until it moves again", async () => {
  const owner = elsewhere();
  const r = await rig(() => ({ ws: genesis("ws", owner, false, [], {}, ME, [phone]) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const g = r.cloud.chains.get("ws")![0]!;
  const sign = (e: ReturnType<typeof next>): Entry => ({ ...e, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } });
  // This device put in by the owner, the cloud turning the next read of the lock away (the account's budget spent).
  const approval = sign(next("ws", { seq: 0, hash: entryHash(g), genesis: entryHash(g) }, r.host.nowMs() / 1000, "device", { id: ME, sub: "s1", kind: "app", label: "this" }));
  r.cloud.chains.set("ws", [g, approval]);
  let limited = 1;
  stationReplies(r.host, (req) => (req.url.includes("/v1/workspaces/ws/lock?") && limited-- > 0 ? status(429, { error: "rate_limited" }) : r.cloud.reply(req)));
  r.core.inner.data.update({ topic: "workspace", workspace: "ws" }, (w) => ({ ...(w as object), lock: r.cloud.head("ws") }));
  await r.host.time.pass(1_000);
  assert.equal(limited, 0, "turned away once");
  assert.equal(held(r.core.inner, "ws")?.head?.seq, 0, "not read yet");
  await r.host.time.pass(10_000);
  assert.equal(held(r.core.inner, "ws")?.head?.seq, 1, "read again, and this device in the lock");
});

test("a station that refused this device is tried again as its person's own lock moves on, not only the workspace's", async () => {
  const r = await rig((_me) => ({ ws: genesis("ws", elsewhere(), false) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  hooks.lockRefused!(r.core.inner, "ws", "st", null);
  assert.notEqual(hooks.lockWaiting!(r.core.inner, "ws", "st"), null, "not asked again by itself");
  refusedAgain(r.core.inner, "ws");
  assert.deepEqual(woke, ["ws/st"]);
  assert.equal(hooks.lockWaiting!(r.core.inner, "ws", "st"), null);
});

test("the lock says its devices and people in words, as every page shows them", async () => {
  // This app signs; the other member's older web page is in it too.
  const older = { id: "ed25519:" + "cd".repeat(32), sub: "s2", kind: "web", label: "", endpoints: ["e1"] };
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], {}, ME, [older]) }));
  const v = await (await r.watch({ topic: "lock", workspace: "ws" }))();
  const owner = v.members.find((m: { sub: string }) => m.sub === "s1");
  const other = v.members.find((m: { sub: string }) => m.sub === "s2");
  assert.deepEqual([owner.roleText, other.roleText], ["Owner", "成员"]);
  const groups = (m: { groups: { appText: string; devices: { nameText: string; metaText: string }[] }[] }) =>
    m.groups.map((g) => [g.appText, g.devices.map((d) => [d.nameText, d.metaText])]);
  // (names that say no app together)
  assert.deepEqual(groups(owner), [["其他", [["this", "此设备 · 受信任"]]]]);
  // (whether it is a web page its mark says; when it was last used, nothing where the cloud would not say)
  assert.deepEqual(groups(other), [["其他", [["旧版客户端", ""]]]]);
  assert.equal(other.nameText, other.name || "b@x.com");
});

test("the people's devices by app say which machine each is and when it was last used, the most lately used first; what this device may take out", async () => {
  const phone = { id: PHONE, sub: "s1", kind: "app", label: "still.fail Android · OPPO PLP110", sign_key: "ed25519:" + "01".repeat(32) };
  const phone2 = { id: "78".repeat(32), sub: "s1", kind: "app", label: "still.fail Android · Pixel 9", sign_key: "ed25519:" + "02".repeat(32) };
  const page = { id: "ef".repeat(32), sub: "s1", kind: "web", label: "still.fail Web · Chrome · macOS" };
  const gone = { id: "12".repeat(32), sub: "s1", kind: "app", label: "" };
  const theirs = { id: "34".repeat(32), sub: "s2", kind: "app", label: "Pixel 8" };
  const older = { id: "56".repeat(32), sub: "s2", kind: "web", label: "", endpoints: [OLDER] };
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], {}, ME, [gone, page, phone, phone2, theirs, older]) }));
  const now = Math.floor(r.host.nowMs() / 1000);
  // What each told the cloud as it last asked for a credential (a web page's two endpoints: the latest says), an older
  // client by its endpoint; the one with no name said, not in 31 days.
  r.cloud.devices.set("ws", [
    { sub: "s1", device: "e-phone", base: PHONE, kind: "app", label: "still.fail mbui Android · OPPO Find N5", last_seen: now - 3600 },
    { sub: "s1", device: "e-phone2", base: phone2.id, kind: "app", label: phone2.label, last_seen: now - 7200 },
    { sub: "s1", device: "e-page-1", base: page.id, kind: "web", label: "still.fail Web · Chrome · macOS", last_seen: now - 12 * 86400 },
    { sub: "s1", device: "e-page-2", base: page.id, kind: "web", label: "still.fail 网页版 · Chrome · macOS", last_seen: now - 3 * 86400 - 50 },
    { sub: "s2", device: "e-theirs", base: theirs.id, kind: "app", label: null, last_seen: now - 2 * 86400 },
    { sub: "s2", device: OLDER, base: null, kind: null, label: null, last_seen: now - 40 * 3600 },
  ]);
  const v = await (await r.watch({ topic: "lock", workspace: "ws" }))();
  type Row = { nameText: string; fullText: string; metaText: string; removable: boolean };
  const groups = (sub: string) => v.members.find((m: { sub: string }) => m.sub === sub).groups
    .map((g: { appText: string; devices: Row[] }) => [g.appText, g.devices.map((d) => [d.nameText, d.metaText, d.removable])]);
  // (by the app each is, the group with this device first, then the one used most lately: those whose name says none,
  // this one's, together)
  assert.deepEqual(groups("s1"), [
    ["其他", [["this", "此设备 · 受信任", false], ["客户端", "超过一个月未使用", true]]],
    ["still.fail Android", [["OPPO Find N5", "一天内使用过 · 受信任", true], ["Pixel 9", "一天内使用过 · 受信任", true]]],
    ["still.fail 网页版", [["Chrome · macOS", "3 天前使用过", true]]],
  ]);
  // (someone else's: theirs alone to take out, an owner too takes the member out, not one device of theirs)
  assert.deepEqual(groups("s2"), [["其他", [["旧版客户端", "1 天前使用过", false], ["Pixel 8", "2 天前使用过", false]]]]);
  // (asked about in a line of its own: which machine, then which app)
  const phoneRow = v.members.find((m: { sub: string }) => m.sub === "s1").groups[1].devices[0] as Row;
  assert.equal(phoneRow.fullText, "OPPO Find N5 · still.fail Android");
  // Taken out: the entry this device signs, as any other change.
  await r.ask("lock.removeDevice", { workspace: "ws", device: PHONE });
  assert.deepEqual(r.cloud.posted.map((p) => [p.kind, p.id]), [["device.remove", PHONE]]);
});

test("turning the lock on says what it would sign in words: this device first, its people", async () => {
  const r = await rig(() => ({}));
  const draft = await r.watch({ topic: "lockDraft", workspace: "ws" });
  await r.host.time.pass(5_000);
  const d = await draft();
  const mine = d.devices.find((x: { current: boolean }) => x.current);
  assert.ok(mine, JSON.stringify(d));
  assert.equal(mine.nameText, `${mine.person} · 此设备`);
  assert.equal(mine.howText, "客户端 · 受信任");
  assert.ok(d.members.every((m: { roleText: string }) => m.roleText !== ""));
});

test("a member or a station taken out of a locked workspace, or a member given another role, is so in its lock first, by this device; the cloud's word alone where it signs nothing there", async () => {
  // (the locks' end to end, 2026-11-10: bob taken out of the workspace kept his devices in its lock, so a credential
  // the cloud went on giving him, or did not say it had ended, let him in still)
  const said: string[] = [];
  const answer = (r: Awaited<ReturnType<typeof rig>>) => {
    stationReplies(r.host, (req) => {
      if ((req.method === "DELETE" || req.method === "PATCH") && /\/v1\/workspaces\/[^/]+\/(members|stations)\/[^/]+$/.test(req.url)) {
        said.push(`cloud ${req.method} ${new URL(req.url).pathname}`);
        return { ok: true };
      }
      if (req.method === "POST" && /\/v1\/workspaces\/[^/]+\/lock$/.test(req.url)) said.push("lock");
      return r.cloud.reply(req);
    });
  };
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: ST, name: "studio" }], {}, ME, [phone]) }), (host) => {
    stationLater(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/lock") ? new Promise(() => {}) : undefined));
  }, ST);
  answer(r);
  await r.watch({ topic: "lock", workspace: "ws" });
  // (an admin the cloud made a member would still sign as one in the lock)
  // (its one station offline: each entry pending, signed before the cloud is asked, and the cloud not sent it)
  const last = () => { const p = pendingHeld(r.core.inner, "ws").at(-1)!; return [p.entry.kind, p.entry.body]; };
  await r.ask("workspace.setRole", { account: "s1", workspace: "ws", member: "s2", role: "admin" });
  assert.deepEqual(last(), ["member", { sub: "s2", email: "b@x.com", role: "admin" }]);
  assert.deepEqual(said, ["cloud PATCH /v1/workspaces/ws/members/s2"]);
  said.length = 0;
  await r.ask("workspace.removeMember", { account: "s1", workspace: "ws", member: "s2" });
  assert.deepEqual(last(), ["member.remove", { sub: "s2" }]);
  assert.deepEqual(said, ["cloud DELETE /v1/workspaces/ws/members/s2"], "out of the lock (pending) before the cloud is asked");
  said.length = 0;
  await r.ask("workspace.removeStation", { account: "s1", workspace: "ws", station: ST });
  // (its one station: the lock names none after its removal, which is the cloud's then, as a lock that never named one
  // is, before the cloud is asked; and what was pending is brought there then)
  assert.equal(said[0], "lock");
  assert.ok(said.includes(`cloud DELETE /v1/workspaces/ws/stations/${ST}`), said.join());
  await r.host.time.pass(1_000);
  assert.ok(held(r.core.inner, "ws")!.entries.some((e) => e.kind === "station.remove" && (e.body as { key: string }).key === ST));
  // (nothing left pending or failed: the role given and the removal brought in the order made, each as if made then)
  assert.deepEqual(pendingHeld(r.core.inner, "ws").map((p) => [p.entry.kind, p.state]), []);
  assert.ok(!fold(held(r.core.inner, "ws")!.entries).members.has("s2"), "s2 out");
  // One the lock does not name: the cloud's alone.
  said.length = 0;
  const length = r.cloud.chains.get("ws")!.length;
  await r.ask("workspace.removeStation", { account: "s1", workspace: "ws", station: OLDER });
  assert.deepEqual(said, [`cloud DELETE /v1/workspaces/ws/stations/${OLDER}`]);
  assert.equal(r.cloud.chains.get("ws")!.length, length);

  // A device the lock does not let sign: the cloud's word, as before.
  said.length = 0;
  const s = await rig(() => ({ ws: genesis("ws", elsewhere(), false, [], {}, ME, [phone]) }));
  answer(s);
  await s.watch({ topic: "lock", workspace: "ws" });
  await s.ask("workspace.removeMember", { account: "s1", workspace: "ws", member: "s2" });
  assert.deepEqual(said, ["cloud DELETE /v1/workspaces/ws/members/s2"]);
  assert.equal(s.cloud.chains.get("ws")!.length, 1);
});

test("people added to a locked workspace are in its lock with the role given: by their sub, or by their email until their first device is approved", async () => {
  // (2026-11-11: someone added as an owner came in a member, the lock making them one as their device was approved)
  const members = [
    { sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" },
    { sub: "s3", email: "c@x.com", role: "admin" }, { sub: "s4", email: "e@x.com", role: "member" },
  ];
  const json = (b: unknown) => Promise.resolve(jsonResponse(200, b));
  const seen = { members: false };
  let r: Awaited<ReturnType<typeof rig>> | null = null;
  r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: ST, name: "studio" }], {}, ME, [phone]) }), (host) => {
    stationLater(host, (req) => {
      const path = new URL(req.url).pathname;
      if (req.method === "POST" && path === "/admin/api/lock") return new Promise(() => {});
      if (req.method === "POST" && path === "/v1/workspaces/ws/members") {
        seen.members = true;
        return json({ joined: ["C@x.com"], added: ["d@x.com"], already: ["b@x.com"], view: { members } });
      }
      if (req.method === "DELETE" && path === "/v1/workspaces/ws/added/d%40x.com") return json({ members });
      if (req.method === "PATCH" && path === "/v1/workspaces/ws/members/s4") return json({ ok: true });
      if (req.method === "GET" && path === "/v1/workspaces/ws" && seen.members) {
        return json({ id: "ws", name: "W", role: "owner", lock: r!.cloud.head("ws"), lock_requests: 0, stations: [{ id: ST, name: "studio", online: true, last_seen: null }], members });
      }
      return undefined;
    });
  }, ST);
  await r.watch({ topic: "lock", workspace: "ws" });
  // (its one station offline: what is signed is pending, the cloud not sent it)
  const last = (n: number) => pendingHeld(r!.core.inner, "ws").slice(-n).map((p) => [p.entry.kind, p.entry.body]);

  await r.ask("workspace.addMembers", { account: "s1", workspace: "ws", role: "admin", emails: ["C@x.com", "d@x.com", "b@x.com"] });
  // (b@x.com the cloud had already, and the lock has as a member: left as they are)
  assert.deepEqual(last(2), [["member", { sub: "s3", email: "c@x.com", role: "admin" }], ["member", { sub: "pending:d@x.com", email: "", role: "admin" }]]);
  // Not on the lock's page: no one there yet to show devices of.
  const page = await (await r.watch({ topic: "lock", workspace: "ws" }))();
  assert.ok(!page.members.some((m: { sub: string }) => m.sub.startsWith("pending:")), JSON.stringify(page.members));

  // A role given to a member the lock has not heard of yet puts them in it with that role.
  await r.ask("workspace.setRole", { account: "s1", workspace: "ws", member: "s4", role: "admin" });
  assert.deepEqual(last(1), [["member", { sub: "s4", email: "e@x.com", role: "admin" }]]);

  // Their first device approved: the role they were added with, the name held for them taken out.
  const admitted = r.core.inner.runner.run(new Lock(r.core.inner, "ws", "s1", null).admit("s5", "d@x.com"));
  let over = false;
  void admitted.then(() => (over = true));
  await r.host.time.passUntil(20000, () => over);
  await admitted;
  // (the name held for them only pending: that adding dropped, their role from it)
  assert.deepEqual(last(1), [["member", { sub: "s5", email: "d@x.com", role: "admin" }]]);
  const named = () => pendingHeld(r!.core.inner, "ws").filter((p) => (p.entry.body as { sub?: string }).sub === "pending:d@x.com").length;
  assert.equal(named(), 0);

  // One added and taken back before they signed in: the adding dropped, nothing signed.
  await r.ask("workspace.addMembers", { account: "s1", workspace: "ws", role: "admin", emails: ["d@x.com"] });
  assert.equal(named(), 1);
  await r.ask("workspace.removeAdded", { account: "s1", workspace: "ws", email: "d@x.com" });
  assert.equal(named(), 0);
  assert.equal(r.cloud.chains.get("ws")!.length, 1);
});

// Nothing waits on a member with only a web page (the owner, 2026-11-14: 无感迁移; 「开了安全模式那就需要 app」): the
// upgrade carries their page until its `exp`, so there is nothing to tell them or owners and admins of them before it
// (the words that did, `core-misc.lock.appSoon` and `webOnly`, went with the hold, 2026-11-15).
test("safe mode on, not upgraded: a web page whose person has no app is told nothing of the upgrade, nor are owners and admins of them", async () => {
  // This device s1's web page (the owner's); s2 a web page alone too.
  const page = { id: ME, sub: "s1", kind: "web", label: "Chrome", exp: 4_000_000_000 };
  const theirs = { id: "ee".repeat(32), sub: "s2", kind: "web", label: "Chrome", exp: 4_000_000_000 };
  const lockOf = async (role: string) => {
    const r = await rig(() => ({ ws: genesis("ws", elsewhere(), false, [], {}, ME, [page, theirs]) }), (host) => void (host.appKeys = false), undefined, [], undefined, [], { role });
    const lock = await r.watch({ topic: "lock", workspace: "ws" });
    return await lock();
  };
  const texts = (v: any) => [v.appText ?? null, ...["s1", "s2"].map((s) => v.members.find((m: { sub: string }) => m.sub === s)?.appText ?? null)];
  for (const role of ["owner", "member"]) {
    const v = await lockOf(role);
    assert.equal(v.locked, true);
    assert.deepEqual(texts(v), [null, null, null], `nothing said, to the page or of the members (${role})`);
  }
});
