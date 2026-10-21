// The workspace lock on a device (src/views/lock.ts): a device not in it waits and asks by hand, and one whose key cannot
// be kept says its request did not go; a station's refusal names the workspace and where to approve; approving does not
// wait on the stations, nor on the cloud's "too many requests"; what a hello brings. Against a cloud that keeps chains
// and requests (the station fixture's host), on the test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { hooks } from "../src/core/execute.ts";
import { HostError } from "../src/error.ts";
import { type Entry, Signer, entryHash, next, shortCode } from "../src/lock.ts";
import { utf8 } from "../src/util.ts";
import { BEHIND_MS, BEHIND_TRIES, read } from "../src/views/lock.ts";
import { ME, PHONE, elsewhere, genesis, rig, unhex } from "./lock-rig.ts";
import { stationLater, stationReplies, status } from "./station-fixture.ts";

const phoneRequest = { base: PHONE, sub: "s2", email: "b@x.com", kind: "app", label: "Pixel 8", sign_key: null, code: shortCode(PHONE), created_at: 1500 };

test("a device not in the lock waits and asks only by hand; one that cannot keep its key says its request did not go", async () => {
  let broken = true;
  const r = await rig((_me) => ({ ws: genesis("ws", elsewhere(), false) }), (host) => {
    // No key kept yet, and the keychain refusing to keep one (a host whose `secure.*` does not work).
    const set = host.secureSet!;
    host.secureSet = (key: string, value: Uint8Array, opts: { user: boolean }) => (broken ? Effect.fail(new HostError("secure.set is not supported")) : set(key, value, opts));
    const get = host.secureGet!;
    host.secureGet = (key: string, opts: { user: boolean }) => (key === Signer.KEY ? Effect.succeed(null) : get(key, opts));
  });
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  await r.host.time.pass(15_000);
  const v = await lock();
  assert.deepEqual(r.cloud.asked, [], "nothing asked by itself");
  assert.equal(v.me.waiting, true, "its page shows instead of the workspace's");
  assert.equal(v.me.asked, false);
  // A station refusing it asks nothing either.
  hooks.lockRefused!(r.core.inner, "ws", "st");
  await r.host.time.pass(5_000);
  assert.deepEqual(r.cloud.asked, []);
  // Asked by hand: the key cannot be kept, said; nothing reached the cloud.
  await assert.rejects(r.ask("lock.request", { workspace: "ws" }), (e: { code: string }) => e.code === "lock_key");
  assert.deepEqual(r.cloud.asked, []);
  assert.match((await lock()).me.failed, /secure\.set is not supported/);
  // Again once the keychain keeps it: sent, and what kept it is past.
  broken = false;
  await r.ask("lock.request", { workspace: "ws" });
  assert.deepEqual(r.cloud.asked, ["ws"]);
  const after = await lock();
  assert.equal(after.me.failed ?? null, null);
  assert.equal(after.me.asked, true);
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
  // Asked by hand: its key made now; the owner's other device confirms it.
  await r.ask("lock.request", { workspace: "ws" });
  const mine = Effect.runSync(Signer.load(r.host))!;
  const chain = r.cloud.chains.get("ws")!;
  const e = next("ws", r.cloud.head("ws"), 2000, "device", { id: ME, sub: "s1", kind: "app", label: "this", sign_key: mine.id });
  chain.push({ ...e, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } });
  r.cloud.requests.set("ws", []);
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

test("a station's refusal names the workspace and the code to approve, where the device is not in that workspace's lock", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true), w2: genesis("w2", elsewhere(), false) }));
  await r.watch({ topic: "lock", workspace: "w2" });
  const said = hooks.lockRefused!(r.core.inner, "w2", "st2");
  assert.equal(said?.code, "lock_unconfirmed");
  assert.match(said!.message, /日常/);
  assert.ok(said!.message.includes(shortCode(ME)), said!.message);
  // Not asked again until its lock moves on, saying the same.
  const again = hooks.lockWaiting!(r.core.inner, "w2", "st2");
  assert.equal(again?.message, said!.message);
});


test("an approval is done once the cloud keeps it, not once every station of the lock has heard (one offline held it up)", async () => {
  // `st` is protected, and never answers what it is brought: offline.
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: "st", name: "studio" }]) }), (host) => {
    stationLater(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/lock") ? new Promise(() => {}) : undefined));
  });
  r.cloud.requests.set("ws", [phoneRequest]);
  await r.ask("lock.confirm", { workspace: "ws", device: PHONE, code: shortCode(PHONE) });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
  assert.deepEqual(r.cloud.requests.get("ws"), [], "its request gone with it");
});

test("a station that refuses this device though the lock names it has not heard yet: tried again shortly, not held", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  const said = hooks.lockRefused!(r.core.inner, "ws", "st");
  assert.equal(said?.code, "lock_unconfirmed");
  assert.equal(hooks.lockWaiting!(r.core.inner, "ws", "st"), null, "asked again as any station would be");
  await r.host.time.pass(BEHIND_MS - 10);
  assert.deepEqual(woke, []);
  await r.host.time.pass(20);
  assert.deepEqual(woke, ["ws/st"], "and woken soon to be");
  // Refused again and again: a few more tries, each later, then no more for this head.
  for (let i = 1; i < 8; i++) {
    hooks.lockRefused!(r.core.inner, "ws", "st");
    await r.host.time.pass(BEHIND_MS * (i + 1) + 10);
  }
  assert.equal(woke.length, BEHIND_TRIES, "as often as BEHIND_TRIES");
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
  r.core.inner.data.put("lock", "ws", { head: head(another), entries: [g, approval, another], requests: [] });
  assert.deepEqual(r.core.inner.cloudSync.carry!("ws"), [approval, another], "from the one that put it in on");
  // Put in long since: every station has heard by now.
  const old = sign(next("ws", head(g), r.host.nowMs() / 1000 - 8 * 86400, "device", { id: ME, sub: "s1", kind: "app", label: "this" }));
  r.cloud.chains.set("ws", [g, old]);
  r.core.inner.data.put("lock", "ws", { head: head(old), entries: [g, old], requests: [] });
  assert.equal(r.core.inner.cloudSync.carry!("ws"), null);
});

test("an approval the cloud answers too many requests for is asked again a while later, not failed at once", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true) }));
  r.cloud.requests.set("ws", [phoneRequest]);
  // The account's budget for this minute spent (by its other devices): the next two asks are turned away.
  let limited = 2;
  stationReplies(r.host, (req) => (req.url.includes("/lock") && limited-- > 0 ? status(429, { error: "rate_limited" }) : r.cloud.reply(req)));
  await r.ask("lock.confirm", { workspace: "ws", device: PHONE, code: shortCode(PHONE) });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
});
