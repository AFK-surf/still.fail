// The workspace lock on a device (src/views/lock.ts): a device not in it waits and asks nothing by itself; one is
// approved only face to face (views/pair.ts), never with a press on a request kept at the cloud; a station's refusal
// names the workspace and where to approve; a change does not wait on the stations, nor on the cloud's "too many
// requests"; what a hello brings. Against a cloud that keeps chains and requests (the station fixture's host), on the
// test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { hooks } from "../src/core/execute.ts";
import { HostError } from "../src/error.ts";
import { type Entry, Signer, entryHash, next, shortCode } from "../src/lock.ts";
import { utf8 } from "../src/util.ts";
import { BEHIND_MS, BEHIND_TRIES, read, signerKnown } from "../src/views/lock.ts";
import { ME, PHONE, elsewhere, genesis, rig, unhex } from "./lock-rig.ts";
import { stationLater, stationReplies, status } from "./station-fixture.ts";

const phoneRequest = { base: PHONE, sub: "s2", email: "b@x.com", kind: "app", label: "Pixel 8", sign_key: null, code: shortCode(PHONE), created_at: 1500 };
/// Another member's phone in the lock: one a trusted device may take out.
const phone = { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" };

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


test("a change to the lock is done once the cloud keeps it, not once every station of the lock has heard (one offline held it up)", async () => {
  // `st` is protected, and never answers what it is brought: offline.
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: "st", name: "studio" }], {}, ME, [phone]) }), (host) => {
    stationLater(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/lock") ? new Promise(() => {}) : undefined));
  });
  await r.ask("lock.removeDevice", { workspace: "ws", device: PHONE });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device.remove", PHONE]]);
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

test("a device the lock names without its signing key signs nothing: the cloud gets no entry the stations would refuse", async () => {
  // This app is in the lock without its key (put in before it kept one), and keeps one now; an older device signed so,
  // the cloud kept it, and every station refused it and all after it (2026-10-24).
  const owner = elsewhere();
  const r = await rig(() => ({ ws: genesis("ws", owner, false, [], {}, ME, [{ id: "ef".repeat(32), sub: "s1", kind: "app", label: "owner's", sign_key: owner.id }, { id: ME, sub: "s1", kind: "app", label: "this" }, phone]) }));
  await assert.rejects(r.ask("lock.removeDevice", { workspace: "ws", device: PHONE }), (e: { code: string }) => e.code === "lock_no_signer");
  assert.deepEqual(r.cloud.posted, []);
});

test("a station that keeps another lock says so, and is neither tried again as behind nor shown protected", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: "st", name: "studio" }]) }));
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  const woke: string[] = [];
  r.core.inner.stations.cameOnline = (address: string) => void woke.push(address);
  // Its head is of another genesis (the lock turned on again while it kept the old one).
  const said = hooks.lockRefused!(r.core.inner, "ws", "st", { seq: 0, hash: "00".repeat(32), genesis: "00".repeat(32) });
  assert.equal(said?.code, "lock_other");
  assert.match(said!.message, /stillfail lock reset/);
  assert.equal(hooks.lockWaiting!(r.core.inner, "ws", "st")?.code, "lock_other", "not asked again until the lock moves on");
  await r.host.time.pass(BEHIND_MS * 4);
  assert.deepEqual(woke, []);
  assert.ok(!(await lock()).stations.some((s: { id: string; protected: boolean }) => s.id === "st" && s.protected));
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
});

test("a change the cloud answers too many requests for is asked again a while later, not failed at once", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], {}, ME, [phone]) }));
  // The account's budget for this minute spent (by its other devices): the next two asks are turned away.
  let limited = 2;
  stationReplies(r.host, (req) => (req.url.includes("/lock") && limited-- > 0 ? status(429, { error: "rate_limited" }) : r.cloud.reply(req)));
  await r.ask("lock.removeDevice", { workspace: "ws", device: PHONE });
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device.remove", PHONE]]);
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
  const page = { id: "ef".repeat(32), sub: "s1", kind: "web", label: "still.fail Web · Chrome · macOS" };
  const gone = { id: "12".repeat(32), sub: "s1", kind: "app", label: "" };
  const theirs = { id: "34".repeat(32), sub: "s2", kind: "app", label: "Pixel 8" };
  const older = { id: "56".repeat(32), sub: "s2", kind: "web", label: "", endpoints: ["e-older"] };
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], {}, ME, [gone, page, phone, theirs, older]) }));
  const now = Math.floor(r.host.nowMs() / 1000);
  // What each told the cloud as it last asked for a credential (a web page's two endpoints: the latest says), an older
  // client by its endpoint; the one with no name said, not in 31 days.
  r.cloud.devices.set("ws", [
    { sub: "s1", device: "e-phone", base: PHONE, kind: "app", label: "still.fail mbui Android · OPPO Find N5", last_seen: now - 3600 },
    { sub: "s1", device: "e-page-1", base: page.id, kind: "web", label: "still.fail Web · Chrome · macOS", last_seen: now - 12 * 86400 },
    { sub: "s1", device: "e-page-2", base: page.id, kind: "web", label: "still.fail 网页版 · Chrome · macOS", last_seen: now - 3 * 86400 - 50 },
    { sub: "s2", device: "e-theirs", base: theirs.id, kind: "app", label: null, last_seen: now - 2 * 86400 },
    { sub: "s2", device: "e-older", base: null, kind: null, label: null, last_seen: now - 40 * 3600 },
  ]);
  const v = await (await r.watch({ topic: "lock", workspace: "ws" }))();
  type Row = { nameText: string; fullText: string; metaText: string; removable: boolean };
  const groups = (sub: string) => v.members.find((m: { sub: string }) => m.sub === sub).groups
    .map((g: { appText: string; devices: Row[] }) => [g.appText, g.devices.map((d) => [d.nameText, d.metaText, d.removable])]);
  // (by the app each is, the group with this device first, then the one used most lately: those whose name says none,
  // this one's, together)
  assert.deepEqual(groups("s1"), [
    ["其他", [["this", "此设备 · 受信任", false], ["客户端", "超过一个月未使用", true]]],
    ["still.fail mbui Android", [["OPPO Find N5", "一天内使用过 · 受信任", true]]],
    ["still.fail 网页版", [["Chrome · macOS", "3 天前使用过", true]]],
  ]);
  assert.deepEqual(groups("s2"), [["其他", [["旧版客户端", "1 天前使用过", true], ["Pixel 8", "2 天前使用过", true]]]]);
  // (asked about in a line of its own: which machine, then which app)
  const phoneRow = v.members.find((m: { sub: string }) => m.sub === "s1").groups[1].devices[0] as Row;
  assert.equal(phoneRow.fullText, "OPPO Find N5 · still.fail mbui Android");
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
