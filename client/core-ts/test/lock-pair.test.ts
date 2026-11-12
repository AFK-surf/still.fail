// Approving a new device face to face (src/pair.ts, src/views/pair.ts): the exchange on its own, then a trusted device's
// core met by a new device over a stream of its own: the code it shows, typed right, signs the new device in; typed
// wrong, it says how many tries are left, and after PAIR_TRIES it signs nothing; turned away, nothing; its prompt
// closed, the code still signs it in; ended there, the new device is told why (not that it typed wrong); a credential
// for another device, nothing; a new device that dialled someone else (its idea of the other end not the trusted one's)
// cannot prove even the right code. The code is good for PAIR_WAIT_MS from when it is shown, wrong ones not putting it
// off; the new device hears its trusted devices end it while nothing is typed (turned away, too old, gone, silent past
// its time) and says why at once. Someone made a member since the lock was turned on is shown a code by an owner's
// device, and made a member as the code signs their device in. On the test clock, the trusted core's lock at a cloud
// that keeps chains.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { CoreError, HostError } from "../src/error.ts";
import { hooks } from "../src/core/execute.ts";
import { PAIR_TRIES, pairCode, pairSession, pakeKeys, pakeStart, sameMac, typedCode } from "../src/pair.ts";
import { utf8 } from "../src/util.ts";
import { Bridge, BridgeHost } from "../src/hosts/bridge.ts";
import { t } from "../src/i18n.ts";
import { type Entry, Signer, entryHash, next, signedBytes } from "../src/lock.ts";
import { PersonalLock, checkChain } from "../src/personal-lock.ts";
import { Lock, TAKEN_MS, bindPerson, fold, held, keepToPerson, onBoundPerson, pairs, pendingHeld, putOnBound, read, signerOf } from "../src/views/lock.ts";
import { checkLock } from "../src/vault/lock-check.ts";
import { keep, PAIR_GRACE_MS, PAIR_WAIT_MS, personalBegin, served, serveTrusted, trying, tryOne } from "../src/views/pair.ts";
import { ME, PHONE, elsewhere, genesis, grant, pipe, rig, withoutMesh } from "./lock-rig.ts";
import { Status, started, stationReplies } from "./station-fixture.ts";

const random = (b: Uint8Array) => {
  for (let i = 0; i < b.length; i++) b[i] = (Math.random() * 256) | 0;
};

test("the exchange: the same code and the same two ends make the same key; another code, or another end, does not", () => {
  const code = pairCode(random);
  assert.match(code, /^[0-9]{6}$/);
  assert.equal(typedCode(`${code.slice(0, 3)} ${code.slice(3)}`), code);
  assert.equal(typedCode("12345"), null);
  assert.equal(typedCode("12a456"), null);
  const session = pairSession("aa", "bb", ["ws"]);
  const n = pakeStart(code, session, random), tr = pakeStart(code, session, random);
  const kn = pakeKeys(n, tr.share, "new")!, kt = pakeKeys(tr, n.share, "trusted")!;
  assert.ok(sameMac(kn.mine, kt.theirs) && sameMac(kt.mine, kn.theirs), "the right code");
  const other = pakeStart(pairCode(random), session, random);
  assert.ok(!sameMac(pakeKeys(other, tr.share, "new")!.mine, pakeKeys(tr, other.share, "trusted")!.theirs), "another code");
  const elsewhere = pakeStart(code, pairSession("aa", "cc", ["ws"]), random);
  assert.ok(!sameMac(pakeKeys(elsewhere, tr.share, "new")!.mine, pakeKeys(tr, elsewhere.share, "trusted")!.theirs), "another end");
  assert.equal(pakeKeys(n, new Uint8Array(32), "new"), null, "the identity is no share");
});

/// `inLock`: the phone in the lock already (an app of s2's, as the genesis put it: its sign key, if any); `others`:
/// more devices the genesis puts in.
async function met(inLock?: { sign_key?: string }, others: Record<string, unknown>[] = []) {
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME, [...(inLock ? [{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8", ...inLock }] : []), ...others]) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const [trusted, phone] = await pipe();
  r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, trusted));
  /// An effect run on the core's clock, waited for.
  const run = async <A>(e: Effect.Effect<A, any>): Promise<{ ok: A } | { err: any }> => {
    const out: ({ ok: A } | { err: any })[] = [];
    r.core.inner.runner.fork(Effect.map(Effect.result(e), (x) => out.push(x._tag === "Success" ? { ok: x.success } : { err: x.failure })));
    await r.host.time.passUntil(5000, () => out.length !== 0);
    return out[0] ?? { err: "no answer" };
  };
  const hello = (credential = g.credential("ws", PHONE, "s2")) =>
    run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }), phone.next()));
  const prove = (code: string, trustedId = ME) => run(tryOne(r.core.inner, { id: trustedId, d: phone, workspaces: ["ws"] }, PHONE, code));
  return { ...r, g, prompts, phone, run, hello, prove };
}

test("a new device met face to face: the code the trusted device shows, typed right, signs it in", async () => {
  const m = await met();
  assert.deepEqual(await m.hello(), { ok: { t: "code", workspaces: ["ws"] } });
  const shown = (await m.prompts()).pairing;
  assert.equal(shown.length, 1);
  assert.equal(shown[0].device, PHONE);
  assert.equal(shown[0].name, "李二");
  assert.equal(shown[0].deviceText, "Pixel 8");
  assert.deepEqual(shown[0].workspaces.map((w: { id: string; name: string }) => [w.id, w.name]), [["ws", "W"]]);
  const done = await m.prove(shown[0].code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.deepEqual(m.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
  const entry = m.cloud.chains.get("ws")!.at(-1)!;
  assert.deepEqual(entry.body, { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) });
  assert.deepEqual((await m.prompts()).pairing, [], "no longer shown");
});

test("a trusted app still loading its signing key waits before answering a new device", async () => {
  const g = grant();
  const ready = Deferred.makeUnsafe<void>();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME) }), (host) => {
    const read = host.secureGet!;
    host.secureGet = (key, opts) => key === Signer.KEY && !opts.user
      ? Effect.andThen(Deferred.await(ready), read.call(host, key, opts))
      : read.call(host, key, opts);
  });
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const [trusted, phone] = await pipe();
  r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, trusted));
  const answers: unknown[] = [];
  r.core.inner.runner.fork(Effect.ignore(Effect.andThen(
    phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", PHONE, "s2") }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }),
    Effect.map(phone.next(), (answer) => { answers.push(answer); }),
  )));
  await r.host.time.pass(500);
  assert.deepEqual(answers, [], "the device has not refused while its own key is still loading");
  Deferred.doneUnsafe(ready, Effect.void);
  await r.host.time.pass(1_000);
  assert.deepEqual(answers, [{ t: "code", workspaces: ["ws"] }]);
  assert.equal((await prompts()).pairing.length, 1);
});

test("a trusted app finishes pairing after its signing key loads, even when a stream read cannot be cancelled", async () => {
  const g = grant();
  const ready = Deferred.makeUnsafe<void>();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME) }), (host) => {
    const read = host.secureGet!;
    host.secureGet = (key, opts) => key === Signer.KEY && !opts.user
      ? Effect.andThen(Deferred.await(ready), read.call(host, key, opts))
      : read.call(host, key, opts);
  });
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const [trusted, phone] = await pipe();
  // Native and binding reads continue in the host even if the effect waiting on them is interrupted.
  const uncancellable = { ...trusted, next: () => Effect.promise(() => Effect.runPromise(trusted.next())) };
  r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, uncancellable));
  await Effect.runPromise(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", PHONE, "s2") }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }));
  await r.host.time.pass(500);
  Deferred.doneUnsafe(ready, Effect.void);
  const answers: unknown[] = [];
  r.core.inner.runner.fork(Effect.map(phone.next(), (answer) => { answers.push(answer); }));
  await r.host.time.pass(1_000);
  assert.deepEqual(answers, [{ t: "code", workspaces: ["ws"] }]);
  const code = (await prompts()).pairing[0].code;
  const results: unknown[] = [];
  r.core.inner.runner.fork(Effect.map(Effect.result(tryOne(r.core.inner, { id: ME, d: phone, workspaces: ["ws"] }, PHONE, code)), (result) => { results.push(result); }));
  await r.host.time.pass(5_000);
  assert.equal(results.length, 1, "the verification exchange is not lost to a second in-flight read");
  assert.equal((results[0] as { _tag: string })._tag, "Success");
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
});

test("a new device goes away while the trusted app loads its key: no prompt remains", async () => {
  const g = grant();
  const ready = Deferred.makeUnsafe<void>();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME) }), (host) => {
    const read = host.secureGet!;
    host.secureGet = (key, opts) => key === Signer.KEY && !opts.user
      ? Effect.andThen(Deferred.await(ready), read.call(host, key, opts))
      : read.call(host, key, opts);
  });
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const [trusted, phone] = await pipe();
  const finished: boolean[] = [];
  r.core.inner.runner.fork(Effect.map(serveTrusted(r.core.inner, PHONE, ME, trusted), () => { finished.push(true); }));
  await Effect.runPromise(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", PHONE, "s2") }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }));
  await r.host.time.pass(500);
  phone.close();
  await r.host.time.pass(500);
  assert.deepEqual(finished, [true], "the request stops when the connection closes");
  Deferred.doneUnsafe(ready, Effect.void);
  await r.host.time.pass(500);
  assert.deepEqual((await prompts()).pairing, []);
});

test("a trusted device whose newer lock is still being read waits before answering", async () => {
  const g = grant();
  const owner = elsewhere();
  let ownKey = "";
  const r = await rig((me) => {
    ownKey = me.id;
    return { ws: genesis("ws", owner, false, [], g.keys, ME, [{ id: "aa".repeat(32), sub: "s1", kind: "app", label: "owner", sign_key: owner.id }]) };
  });
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const added = next("ws", r.cloud.head("ws"), r.host.nowMs() / 1000, "device", { id: ME, sub: "s1", kind: "app", label: "this", sign_key: ownKey });
  const signed: Entry = { ...added, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(signedBytes(entryHash(added))) } };
  r.cloud.chains.set("ws", [...r.cloud.chains.get("ws")!, signed]);
  const release = r.host.hold("/v1/workspaces/ws/lock?after=0");
  const topic = { topic: "workspace", workspace: "ws" };
  r.core.inner.data.set(topic, { ...(r.core.inner.data.shared(topic) as object), lock: r.cloud.head("ws") });
  await r.host.time.pass(500);
  assert.ok(r.core.inner.scheduler.pending().some((s) => s.includes("lock/ws")), "the newer lock is being read");
  const [trusted, phone] = await pipe();
  r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, trusted));
  const answers: unknown[] = [];
  r.core.inner.runner.fork(Effect.ignore(Effect.andThen(
    phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", PHONE, "s1") }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }),
    Effect.map(phone.next(), (answer) => { answers.push(answer); }),
  )));
  await r.host.time.pass(500);
  assert.deepEqual(answers, [], "the old lock must not make the trusted device refuse prematurely");
  release();
  await r.host.time.pass(2_000);
  assert.deepEqual(answers, [{ t: "code", workspaces: ["ws"] }]);
  assert.equal((await prompts()).pairing.length, 1);
});

test("a newer lock changes who may approve: the old permission does not show a code", async () => {
  const m = await met();
  const signer = Effect.runSync(Signer.make(m.host));
  const added = signer.sign(next("ws", m.cloud.head("ws"), m.host.nowMs() / 1000, "device", {
    id: "ee".repeat(32), sub: "s2", kind: "app", label: "their first", sign_key: "ed25519:" + "22".repeat(32),
  }));
  m.cloud.chains.set("ws", [...m.cloud.chains.get("ws")!, added]);
  const release = m.host.hold("/v1/workspaces/ws/lock?after=0");
  const topic = { topic: "workspace", workspace: "ws" };
  m.core.inner.data.set(topic, { ...(m.core.inner.data.shared(topic) as object), lock: m.cloud.head("ws") });
  await m.host.time.pass(500);
  await Effect.runPromise(m.phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: m.g.credential("ws", PHONE, "s2") }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }));
  const answers: unknown[] = [];
  m.core.inner.runner.fork(Effect.map(m.phone.next(), (answer) => { answers.push(answer); }));
  await m.host.time.pass(500);
  assert.deepEqual(answers, [], "the old permission is not used while the newer lock is loading");
  release();
  await m.host.time.pass(2_000);
  assert.deepEqual(answers, [{ t: "no", error: "not_here" }]);
  assert.deepEqual((await m.prompts()).pairing, []);
});

test("a newer lock cannot be read: a permission from the old one does not show a code", async () => {
  const m = await met();
  const signer = Effect.runSync(Signer.make(m.host));
  const added = signer.sign(next("ws", m.cloud.head("ws"), m.host.nowMs() / 1000, "device", {
    id: "ee".repeat(32), sub: "s2", kind: "app", label: "their first", sign_key: "ed25519:" + "22".repeat(32),
  }));
  m.cloud.chains.set("ws", [...m.cloud.chains.get("ws")!, added]);
  stationReplies(m.host, (req) => (req.method === "GET" && req.url.includes("/v1/workspaces/ws/lock") ? new Status(503, { error: "unavailable" }) : m.cloud.reply(req)));
  const topic = { topic: "workspace", workspace: "ws" };
  m.core.inner.data.set(topic, { ...(m.core.inner.data.shared(topic) as object), lock: m.cloud.head("ws") });
  await m.host.time.pass(500);
  assert.deepEqual(await m.hello(), { ok: { t: "no", error: "not_here" } });
  assert.deepEqual((await m.prompts()).pairing, []);
});

test("a read that succeeds but is still behind the known lock does not use old permission", async () => {
  const m = await met();
  const signer = Effect.runSync(Signer.make(m.host));
  const old = m.cloud.chains.get("ws")!;
  const added = signer.sign(next("ws", m.cloud.head("ws"), m.host.nowMs() / 1000, "device", {
    id: "ee".repeat(32), sub: "s2", kind: "app", label: "their first", sign_key: "ed25519:" + "22".repeat(32),
  }));
  m.cloud.chains.set("ws", [...old, added]);
  const newer = m.cloud.head("ws");
  m.cloud.chains.set("ws", old);
  const topic = { topic: "workspace", workspace: "ws" };
  m.core.inner.data.set(topic, { ...(m.core.inner.data.shared(topic) as object), lock: newer });
  await m.host.time.pass(500);
  assert.deepEqual(await m.hello(), { ok: { t: "no", error: "not_here" } });
  assert.deepEqual((await m.prompts()).pairing, []);
});

// The real-station end-to-end's round 8 after round 7b's B lost its renewal (2026-11-12): the cloud, frozen while the
// stations forked, took B's entry as it came back (it appends at its head only) and refused the one B signed again
// after the head that won; the cloud's view went on naming B's entry, which B holds aside, and B never showed bob's
// first device a code.
test("the cloud's view names an entry this device holds aside (it lost the fork, the cloud appending at its head only): not a newer lock to wait for, the code shown", async () => {
  const old = elsewhere();
  const OLD = "dd".repeat(32);
  const m = await met(undefined, [{ id: OLD, sub: "s1", kind: "app", label: "old", sign_key: old.id }]);
  const signer = Effect.runSync(Signer.make(m.host));
  const g0 = m.cloud.chains.get("ws")![0]!;
  const after = { seq: 0, hash: entryHash(g0), genesis: entryHash(g0) };
  const at = m.host.nowMs() / 1000;
  // X: this device's entry, which lost; Y: the entry that won at its place (a removal of a device that signs).
  const X = signer.sign(next("ws", after, at, "device", { id: "ef".repeat(32), sub: "s1", kind: "web", label: "page" }));
  const Y = signer.sign(next("ws", after, at + 1, "device.remove", { id: OLD }));
  m.cloud.chains.set("ws", [g0, X]);
  m.core.inner.data.put("lock", "ws", { head: { seq: 1, hash: entryHash(Y), genesis: entryHash(g0) }, entries: [g0, Y], aside: [X] });
  const topic = { topic: "workspace", workspace: "ws" };
  m.core.inner.data.set(topic, { ...(m.core.inner.data.shared(topic) as object), lock: m.cloud.head("ws") });
  await m.host.time.pass(500);
  assert.deepEqual(held(m.core.inner, "ws")!.entries.map(entryHash), [g0, Y].map(entryHash), "Y held");
  assert.deepEqual(await m.hello(), { ok: { t: "code", workspaces: ["ws"] } });
  assert.equal((await m.prompts()).pairing.length, 1);
});

test("one workspace's lock is updating: another ready workspace can show a code immediately", async () => {
  const g = grant();
  const r = await rig((me) => ({
    ws: genesis("ws", me, true, [], g.keys, ME),
    w2: genesis("w2", me, true, [], g.keys, ME),
  }));
  await r.watch({ topic: "lock", workspace: "ws" });
  await r.watch({ topic: "lock", workspace: "w2" });
  const signer = Effect.runSync(Signer.make(r.host));
  const added = signer.sign(next("w2", r.cloud.head("w2"), r.host.nowMs() / 1000, "member", { sub: "s3", email: "s3@x.com", role: "member" }));
  r.cloud.chains.set("w2", [...r.cloud.chains.get("w2")!, added]);
  const release = r.host.hold("/v1/workspaces/w2/lock?after=0");
  const topic = { topic: "workspace", workspace: "w2" };
  r.core.inner.data.set(topic, { ...(r.core.inner.data.shared(topic) as object), lock: r.cloud.head("w2") });
  await r.host.time.pass(500);
  const [trusted, phone] = await pipe();
  r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, trusted));
  const answers: unknown[] = [];
  r.core.inner.runner.fork(Effect.ignore(Effect.andThen(
    phone.send({ t: "hello", v: 1, workspaces: ["ws", "w2"].map((ws) => ({ ws, credential: g.credential(ws, PHONE, "s2") })), kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }),
    Effect.map(phone.next(), (answer) => { answers.push(answer); }),
  )));
  await r.host.time.pass(1_000);
  assert.deepEqual(answers, [{ t: "code", workspaces: ["ws"] }]);
  release();
});

test("two workspaces are updating: the first ready one can show a code without waiting for the other", async () => {
  const g = grant();
  const owner = elsewhere();
  let ownKey = "";
  const r = await rig((me) => {
    ownKey = me.id;
    return Object.fromEntries(["ws", "w2"].map((ws) => [
      ws, genesis(ws, owner, false, [], g.keys, ME, [{ id: "aa".repeat(32), sub: "s1", kind: "app", label: "owner", sign_key: owner.id }]),
    ]));
  });
  for (const ws of ["ws", "w2"]) await r.watch({ topic: "lock", workspace: ws });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const releases = ["ws", "w2"].map((ws) => {
    const added = next(ws, r.cloud.head(ws), r.host.nowMs() / 1000, "device", { id: ME, sub: "s1", kind: "app", label: "this", sign_key: ownKey });
    const signed: Entry = { ...added, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(signedBytes(entryHash(added))) } };
    r.cloud.chains.set(ws, [...r.cloud.chains.get(ws)!, signed]);
    const release = r.host.hold(`/v1/workspaces/${ws}/lock?after=0`);
    const topic = { topic: "workspace", workspace: ws };
    r.core.inner.data.set(topic, { ...(r.core.inner.data.shared(topic) as object), lock: r.cloud.head(ws) });
    return release;
  });
  await r.host.time.pass(500);
  const [trusted, phone] = await pipe();
  r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, trusted));
  const answers: unknown[] = [];
  r.core.inner.runner.fork(Effect.ignore(Effect.andThen(
    phone.send({ t: "hello", v: 1, workspaces: ["ws", "w2"].map((ws) => ({ ws, credential: g.credential(ws, PHONE, "s1") })), kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }),
    Effect.map(phone.next(), (answer) => { answers.push(answer); }),
  )));
  await r.host.time.pass(500);
  assert.deepEqual(answers, []);
  releases[0]!();
  await r.host.time.pass(2_000);
  assert.deepEqual(answers, [{ t: "code", workspaces: ["ws"] }]);
  const shown = (await prompts()).pairing;
  assert.equal(shown.length, 1);
  const results: unknown[] = [];
  r.core.inner.runner.fork(Effect.map(Effect.result(tryOne(r.core.inner, { id: ME, d: phone, workspaces: ["ws"] }, PHONE, shown[0].code)), (result) => { results.push(result); }));
  await r.host.time.pass(5_000);
  assert.equal((results[0] as { _tag: string })._tag, "Success");
  assert.deepEqual(r.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
  releases[1]!();
});

test("an updated lock without permission does not stop waiting for another workspace", async () => {
  const g = grant();
  const owner = elsewhere();
  let ownKey = "";
  const r = await rig((me) => {
    ownKey = me.id;
    return Object.fromEntries(["ws", "w2"].map((ws) => [
      ws, genesis(ws, owner, false, [], g.keys, ME, [{ id: "aa".repeat(32), sub: "s1", kind: "app", label: "owner", sign_key: owner.id }]),
    ]));
  });
  for (const ws of ["ws", "w2"]) await r.watch({ topic: "lock", workspace: ws });
  const releases = ["ws", "w2"].map((ws) => {
    const body = ws === "ws" ? { sub: "s3", email: "s3@x.com", role: "member" } : { id: ME, sub: "s1", kind: "app", label: "this", sign_key: ownKey };
    const added = next(ws, r.cloud.head(ws), r.host.nowMs() / 1000, ws === "ws" ? "member" : "device", body);
    const signed: Entry = { ...added, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(signedBytes(entryHash(added))) } };
    r.cloud.chains.set(ws, [...r.cloud.chains.get(ws)!, signed]);
    const release = r.host.hold(`/v1/workspaces/${ws}/lock?after=0`);
    const topic = { topic: "workspace", workspace: ws };
    r.core.inner.data.set(topic, { ...(r.core.inner.data.shared(topic) as object), lock: r.cloud.head(ws) });
    return release;
  });
  await r.host.time.pass(500);
  const [trusted, phone] = await pipe();
  r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, trusted));
  const answers: unknown[] = [];
  r.core.inner.runner.fork(Effect.ignore(Effect.andThen(
    phone.send({ t: "hello", v: 1, workspaces: ["ws", "w2"].map((ws) => ({ ws, credential: g.credential(ws, PHONE, "s1") })), kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }),
    Effect.map(phone.next(), (answer) => { answers.push(answer); }),
  )));
  await r.host.time.pass(500);
  releases[0]!();
  await r.host.time.pass(2_000);
  assert.deepEqual(answers, []);
  releases[1]!();
  await r.host.time.pass(2_000);
  assert.deepEqual(answers, [{ t: "code", workspaces: ["w2"] }]);
});

test("the owner approves a member's first device that signs, not a later one: that one the member approves from a device of their own", async () => {
  // One the owner (or an admin) puts in for a person who has one of their own already would be no one's, signing
  // nothing (lock-check.ts Device `own`): this device offers no code for it.
  const m = await met(undefined, [{ id: "ee".repeat(32), sub: "s2", kind: "app", label: "laptop", sign_key: "ed25519:" + "22".repeat(32) }]);
  assert.deepEqual(await m.hello(), { ok: { t: "no", error: "not_here" } });
  assert.deepEqual((await m.prompts()).pairing, []);
  assert.deepEqual(m.cloud.posted, []);
  // Their web page only (it signs nothing): the first that signs is still the owner's to approve.
  const n = await met(undefined, [{ id: "ee".repeat(32), sub: "s2", kind: "web", label: "Chrome", exp: 1000 + 86400 }]);
  assert.deepEqual(await n.hello(), { ok: { t: "code", workspaces: ["ws"] } });
});

test("someone made a member after the lock was turned on: an owner's device shows a code, and the code typed makes them a member as it signs their device in", async () => {
  // In the workspace at the cloud, in no entry of the lock: their credential is all that says so.
  const m = await met();
  assert.deepEqual(await m.hello(m.g.credential("ws", PHONE, "s3")), { ok: { t: "code", workspaces: ["ws"] } });
  const shown = (await m.prompts()).pairing;
  assert.deepEqual(shown.map((p: { name: string; email: string; device: string }) => [p.name, p.email, p.device]), [["s3", "s3@x.com", PHONE]]);
  assert.equal(shown[0].deviceText, "Pixel 8（还没加入「W」的安全模式，批准后以成员身份加入）", "who gives the code is told it lets someone new in");
  assert.equal(m.cloud.posted.length, 0, "nothing signed before the code is typed");
  const done = await m.prove(shown[0].code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.deepEqual(m.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "member", undefined], ["ws", "device", PHONE]]);
  const chain = m.cloud.chains.get("ws")!;
  assert.deepEqual(chain.at(-2)!.body, { sub: "s3", email: "s3@x.com", role: "member" });
  assert.deepEqual(chain.at(-1)!.body, { id: PHONE, sub: "s3", kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) });
  // As the stations take it: theirs, and a device of their own that signs (the next they approve themselves).
  const lock = checkLock(chain, m.host.nowMs() / 1000);
  assert.equal(lock.members.get("s3"), "member");
  assert.equal(lock.devices.get(PHONE)?.own, true);
  assert.ok(lock.signed.has("s3"));
});

test("their code typed wrong, or turned away: not made a member either", async () => {
  const m = await met();
  await m.hello(m.g.credential("ws", PHONE, "s3"));
  const code = (await m.prompts()).pairing[0].code;
  assert.deepEqual(await m.prove(code === "222222" ? "333333" : "222222"), { ok: { left: PAIR_TRIES - 1 } });
  await m.ask("lockPrompt.deny", { device: PHONE });
  assert.deepEqual(await m.run(m.phone.next()), { ok: { t: "no", error: "denied" } });
  assert.deepEqual(m.cloud.posted, []);
});

test("made a member by a person approving them, the lock says member whatever the cloud calls them: it lowers roles and raises none", async () => {
  const m = await met();
  assert.deepEqual(await m.hello(m.g.credential("ws", PHONE, "s3", 4102444800, "admin")), { ok: { t: "code", workspaces: ["ws"] } });
  const done = await m.prove((await m.prompts()).pairing[0].code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.equal(checkLock(m.cloud.chains.get("ws")!, m.host.nowMs() / 1000).members.get("s3"), "member");
});

test("the lock has heard of them by the time the code is typed (another device got there first): only their device is signed", async () => {
  const m = await met();
  await m.hello(m.g.credential("ws", PHONE, "s3"));
  const code = (await m.prompts()).pairing[0].code;
  const chain = m.cloud.chains.get("ws")!;
  const signer = Effect.runSync(Signer.make(m.host));
  m.cloud.chains.set("ws", [...chain, signer.sign(next("ws", m.cloud.head("ws"), m.host.nowMs() / 1000, "member", { sub: "s3", email: "s3@x.com", role: "admin" }))]);
  const done = await m.prove(code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.deepEqual(m.cloud.posted.map((p) => [p.kind, p.id]), [["device", PHONE]]);
  assert.equal(checkLock(m.cloud.chains.get("ws")!, m.host.nowMs() / 1000).members.get("s3"), "admin", "left as they are");
});

test("their being made a member refused: their device is not signed in, and the new device is told why", async () => {
  const m = await met();
  await m.hello(m.g.credential("ws", PHONE, "s3"));
  const code = (await m.prompts()).pairing[0].code;
  stationReplies(m.host, (req) => (req.method === "POST" && req.url.includes("/lock") ? new Status(409, { error: "lock_refused" }) : m.cloud.reply(req)));
  const done = await m.prove(code);
  assert.ok("err" in done && done.err.code === "pair_unsigned", JSON.stringify(done));
  assert.deepEqual(m.cloud.posted, []);
  assert.equal(m.cloud.chains.get("ws")!.length, 1);
});

test("someone the lock has not heard of: a member's device shows no code, nor does a credential for no one", async () => {
  // A device of an ordinary member's, that signs: it approves only its own person's.
  const g = grant();
  const owner = elsewhere();
  const r = await rig((me) => ({ ws: genesis("ws", owner, false, [], g.keys, ME, [{ id: "aa".repeat(32), sub: "s1", kind: "app", label: "theirs", sign_key: owner.id }, { id: ME, sub: "s2", kind: "app", label: "this", sign_key: me.id }]) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const asks = async (credential: string) => {
    const [trusted, phone] = await pipe();
    r.core.inner.runner.fork(serveTrusted(r.core.inner, PHONE, ME, trusted));
    await Effect.runPromise(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }));
    const out: unknown[] = [];
    r.core.inner.runner.fork(Effect.map(phone.next(), (x) => out.push(x)));
    await r.host.time.passUntil(5000, () => out.length !== 0);
    return out[0];
  };
  assert.deepEqual(await asks(g.credential("ws", PHONE, "s3")), { t: "no", error: "not_here" });
  assert.deepEqual((await prompts()).pairing, []);

  const m = await met();
  assert.deepEqual(await m.hello(m.g.credential("ws", PHONE, "")), { ok: { t: "no", error: "not_here" } });
  assert.deepEqual(m.cloud.posted, []);
});

test("typed wrong: tries left said, the right one still signs it in; PAIR_TRIES wrong ones, nothing", async () => {
  const m = await met();
  await m.hello();
  const code = (await m.prompts()).pairing[0].code;
  const wrong = code === "222222" ? "333333" : "222222";
  assert.deepEqual(await m.prove(wrong), { ok: { left: PAIR_TRIES - 1 } });
  const done = await m.prove(code);
  assert.ok("ok" in done && "approved" in done.ok);

  const n = await met();
  await n.hello();
  const theirs = (await n.prompts()).pairing[0].code;
  const bad = theirs === "222222" ? "333333" : "222222";
  for (let i = 1; i < PAIR_TRIES; i++) assert.deepEqual(await n.prove(bad), { ok: { left: PAIR_TRIES - i } });
  assert.ok("err" in (await n.prove(bad)), "out of tries");
  assert.deepEqual(n.cloud.posted, []);
  assert.deepEqual((await n.prompts()).pairing, []);
});

test("turned away on the trusted device, or a credential for another device: nothing signed", async () => {
  const m = await met();
  await m.hello();
  await m.ask("lockPrompt.deny", { device: PHONE });
  assert.deepEqual(await m.run(m.phone.next()), { ok: { t: "no", error: "denied" } });
  assert.deepEqual(m.cloud.posted, []);

  const n = await met();
  assert.deepEqual(await n.hello(n.g.credential("ws", "ef".repeat(32), "s2")), { ok: { t: "no", error: "not_here" } });
  assert.deepEqual((await n.prompts()).pairing, []);
});

test("its prompt closed on the trusted device (the code read): no longer shown there, and the code typed still signs it in", async () => {
  const m = await met();
  await m.hello();
  const code = (await m.prompts()).pairing[0].code;
  await m.ask("lockPrompt.hide", { device: PHONE });
  assert.deepEqual((await m.prompts()).pairing, [], "no longer shown");
  const done = await m.prove(code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.deepEqual(m.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
});

test("ended on the trusted device, the new device is told why: turned away there, out of tries, the code too old", async () => {
  const why = (r: { ok: unknown } | { err: any }) => ("err" in r ? r.err.code : JSON.stringify(r.ok));
  const denied = await met();
  await denied.hello();
  const code = (await denied.prompts()).pairing[0].code;
  await denied.ask("lockPrompt.deny", { device: PHONE });
  assert.equal(why(await denied.prove(code)), "pair_denied", "turned away, the right code is no use");

  const tried = await met();
  await tried.hello();
  const theirs = (await tried.prompts()).pairing[0].code;
  const bad = theirs === "222222" ? "333333" : "222222";
  for (let i = 1; i < PAIR_TRIES; i++) await tried.prove(bad);
  assert.equal(why(await tried.prove(bad)), "pair_tries");

  const late = await met();
  await late.hello();
  const old = (await late.prompts()).pairing[0].code;
  await late.host.time.pass(PAIR_WAIT_MS + 1_000);
  assert.deepEqual((await late.prompts()).pairing, [], "no longer shown");
  assert.equal(why(await late.prove(old)), "pair_late");
  assert.deepEqual([denied.cloud.posted, tried.cloud.posted, late.cloud.posted], [[], [], []]);
});

test("the code is good until a set time, said where it is shown; wrong codes typed do not put it off", async () => {
  const m = await met();
  const start = m.host.nowMs();
  await m.hello();
  const shown = (await m.prompts()).pairing[0];
  assert.ok(shown.until >= start + PAIR_WAIT_MS && shown.until <= start + PAIR_WAIT_MS + 1_000, String(shown.until - start));
  assert.match(shown.untilText, /\d\d:\d\d/);
  const bad = shown.code === "222222" ? "333333" : "222222";
  await m.host.time.pass(PAIR_WAIT_MS - 60_000);
  assert.deepEqual(await m.prove(bad), { ok: { left: PAIR_TRIES - 1 } });
  await m.host.time.pass(61_000);
  assert.deepEqual((await m.prompts()).pairing, [], "too old, a wrong code typed a minute before or not");
  assert.equal("err" in (await m.prove(shown.code)) ? "ended" : "approved", "ended");
  assert.deepEqual(m.cloud.posted, []);
});

/// Feed the app bridge a native wall clock with sub-millisecond precision.
function useFractionalAppClock(host: { nowMs(): number }) {
  const now = host.nowMs.bind(host);
  const bridge = new BridgeHost(new Bridge({ now: () => now() + 0.439 } as never), "", false);
  host.nowMs = () => bridge.nowMs();
}

test("a trusted device can show a pairing code when its clock has fractional milliseconds", async () => {
  const m = await met();
  useFractionalAppClock(m.host);
  await m.hello();
  const shown = (await m.prompts()).pairing[0];
  assert.match(shown.code, /^[0-9]{6}$/);
  assert.ok(Number.isInteger(shown.until), "the prompt's expiry can be read by the app");
});

test("a new device can show the pairing prompt when its clock has fractional milliseconds", async () => {
  const r = await rig((me) => ({ ws: genesis("ws", me, false) }));
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  useFractionalAppClock(r.host);
  const [, phone] = await pipe();
  keep(r.core.inner, trying(r.core.inner, ["ws"]), PHONE, phone, ["ws"]);
  const shown = await lock();
  assert.equal(shown.me.waiting, true);
  assert.equal(shown.me.pair.state, "code");
  assert.ok(Number.isInteger(shown.me.pair.until), "the waiting page's expiry can be read by the app");
});

test("the new device hears its trusted device end it while nothing is typed, and says why at once", async () => {
  const mine = (m: { core: { inner: any } }) => pairs.mine(m.core.inner, "ws");
  // turned away there
  const denied = await met();
  await denied.hello();
  const y = trying(denied.core.inner, ["ws"]);
  keep(denied.core.inner, y, ME, denied.phone, ["ws"]);
  assert.equal(mine(denied).state, "code");
  assert.match(mine(denied).untilText, /\d\d:\d\d/);
  await denied.ask("lockPrompt.deny", { device: PHONE });
  await denied.host.time.pass(10);
  assert.deepEqual([mine(denied).state, mine(denied).error], ["failed", t("core-misc.lock.pairDenied")]);

  // its code too old
  const late = await met();
  await late.hello();
  keep(late.core.inner, trying(late.core.inner, ["ws"]), ME, late.phone, ["ws"]);
  await late.host.time.pass(PAIR_WAIT_MS + 1_000);
  assert.deepEqual([mine(late).state, mine(late).error], ["failed", t("core-misc.lock.pairLate")]);

  // gone without a word; silent past its time (the connection lost, the app put away)
  const r = await met();
  const [gone, goneHere] = await pipe();
  const [, silentHere] = await pipe();
  const two = trying(r.core.inner, ["ws"]);
  keep(r.core.inner, two, "aa".repeat(32), goneHere, ["ws"]);
  keep(r.core.inner, two, "bb".repeat(32), silentHere, ["ws"]);
  gone.close();
  await r.host.time.pass(10);
  assert.deepEqual([mine(r).state, mine(r).devices], ["code", 1], "one still shows a code");
  await r.host.time.pass(PAIR_WAIT_MS + PAIR_GRACE_MS);
  assert.deepEqual([mine(r).state, mine(r).error], ["failed", t("core-misc.lock.pairLate")]);
  assert.equal(mine(r).untilText, undefined);
});

test("a trusted device kept by the new device: the code typed through it still signs it in, a wrong one says what is left", async () => {
  const m = await met();
  await m.hello();
  const code = (await m.prompts()).pairing[0].code;
  const kept = keep(m.core.inner, trying(m.core.inner, ["ws"]), ME, m.phone, ["ws"]);
  const bad = code === "222222" ? "333333" : "222222";
  assert.deepEqual(await m.run(tryOne(m.core.inner, kept, PHONE, bad)), { ok: { left: PAIR_TRIES - 1 } });
  const done = await m.run(tryOne(m.core.inner, kept, PHONE, code));
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
});

test("approved but signed in nowhere (the trusted device's key not read back): no approval, and the new device is told why", async () => {
  const m = await met();
  await m.hello();
  const code = (await m.prompts()).pairing[0].code;
  m.host.secureGet = () => Effect.fail(new HostError("the keystore said no"));
  const done = await m.prove(code);
  assert.ok("err" in done && done.err.code === "pair_unsigned", JSON.stringify(done));
  // What the keystore said is its own: what kind of failure it was is told.
  assert.match(done.err.message, /此设备上的操作失败/);
  assert.deepEqual(m.cloud.posted, []);
});

test("an app in the lock that does not sign (let in before it kept a key) is made one that signs, as a new one is approved", async () => {
  const m = await met({});
  assert.deepEqual(await m.hello(), { ok: { t: "code", workspaces: ["ws"] } });
  const done = await m.prove((await m.prompts()).pairing[0].code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.deepEqual(m.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
  assert.deepEqual(m.cloud.chains.get("ws")!.at(-1)!.body, { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) });
  // One that signs with the key it brings: nothing to approve. Its credential another person's: not here either.
  const same = await met({ sign_key: "ed25519:" + "11".repeat(32) });
  assert.deepEqual(await same.hello(), { ok: { t: "no", error: "not_here" } });
  const theirs = await met({});
  assert.deepEqual(await theirs.hello(theirs.g.credential("ws", PHONE, "s1")), { ok: { t: "no", error: "not_here" } });
  assert.deepEqual([same.cloud.posted, theirs.cloud.posted], [[], []]);
});

test("a web page whose approval ran out is approved again face to face, as a new one is", async () => {
  const m = await met({ kind: "web", exp: 2000 } as never);
  assert.deepEqual(await m.hello(m.g.credential("ws", PHONE, "s2")), { ok: { t: "code", workspaces: ["ws"] } });
  const done = await m.prove((await m.prompts()).pairing[0].code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.deepEqual(m.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
});

test("a new device that dialled someone else cannot prove even the right code to the trusted one", async () => {
  const m = await met();
  await m.hello();
  const code = (await m.prompts()).pairing[0].code;
  // Its idea of the other end is not the trusted device's (a relay between them, a false lock).
  assert.deepEqual(await m.prove(code, "ef".repeat(32)), { ok: { left: PAIR_TRIES - 1 } });
  assert.deepEqual(m.cloud.posted, []);
});

/// A trusted device's core serving a new device's connection (`served`) whose credential is for another device (told
/// it is not here, and the exchange ends), over a stream that says what is done to it: the acknowledgement of what it
/// sent held until `ack` is told; `finishFails`, the stream fails to finish.
async function servedAlone(finishFails: boolean) {
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  r.core.inner.meshNow = () => ({ deviceId: () => ME }) as never;
  const said: string[] = [];
  const acked = Deferred.makeUnsafe<number | null>();
  const hello = utf8(`${JSON.stringify({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", "someone-else", "s2") }], kind: "web", label: "Chrome", sign_key: null })}\n`);
  let heard = false;
  const stream = {
    read: () => (heard ? Effect.never : Effect.sync(() => ((heard = true), hello))),
    write: (b: Uint8Array) => Effect.sync(() => void said.push(`write ${new TextDecoder().decode(b).trim()}`)),
    finish: () => (finishFails ? Effect.andThen(Effect.sync(() => void said.push("finish failed")), Effect.fail(new HostError("gone"))) : Effect.sync(() => void said.push("finish"))),
    stopped: () => Effect.andThen(Effect.sync(() => void said.push("waits")), Effect.tap(Deferred.await(acked), () => Effect.sync(() => void said.push("acknowledged")))),
    reset: (code: number) => void said.push(`reset ${code}`),
  };
  const connection = { remoteId: () => PHONE, acceptBi: () => Effect.succeed(stream), close: (code: number, why: string) => void said.push(`close ${code} ${why}`) };
  served(r.core.inner, connection as never);
  const until = async (f: () => boolean) => {
    await r.host.time.passUntil(500, () => f());
    await r.host.time.pass(10);
  };
  return { said, until, ack: () => Deferred.doneUnsafe(acked, Effect.succeed(null)) };
}

test("the trusted device's last word to a new device is taken before its connection ends: closed only once what it sent is acknowledged; its stream failing to finish, closed at once", async () => {
  const no = `write ${JSON.stringify({ t: "no", error: "not_here" })}`;
  const s = await servedAlone(false);
  await s.until(() => s.said.includes("waits"));
  // (its last word sent, not yet acknowledged: the connection still up)
  assert.deepEqual(s.said, [no, "finish", "waits"]);
  s.ack();
  await s.until(() => s.said.some((x) => x.startsWith("close")));
  assert.deepEqual(s.said, [no, "finish", "waits", "acknowledged", "close 0 done"]);
  const f = await servedAlone(true);
  await f.until(() => f.said.some((x) => x.startsWith("close")));
  assert.deepEqual(f.said, [no, "finish failed", "close 0 done"]);
});

test("a device joins its person's own lock face to face: the code shown on a device on it lets it in, nothing else does", async () => {
  const m = await met();
  const inner = m.core.inner;
  // A lock this device is on, at a cloud of the test's; the new device's key comes in its hello.
  const kept: { entries: Entry[] } = { entries: [] };
  const personal = new PersonalLock({
    host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {},
    cloud: (_s, method, _p, body) => Effect.sync(() => {
      if (method === "GET") return { entries: kept.entries };
      const adding = (body as { entries: Entry[] }).entries;
      kept.entries = adding[0]!.seq === 0 ? adding : [...kept.entries, ...adding];
      return { entries: kept.entries };
    }),
  });
  const sealed = new Map<string, Uint8Array>();
  m.host.secureSet = (k: string, v: Uint8Array) => Effect.sync(() => void sealed.set(k, v));
  const lockedGet = m.host.secureGet;
  m.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => (o.user ? Effect.succeed(sealed.get(k) ?? null) : lockedGet!.call(m.host, k, o));
  inner.adb.personal = () => personal;
  await m.run(personal.signGrant("s1", { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  assert.equal(personal.standing("s1"), "member");

  // A second connection (the rig's first is taken by a workspace's hello elsewhere): asked into the lock.
  const [trusted, phone] = await pipe();
  inner.runner.fork(serveTrusted(inner, PHONE, ME, trusted));
  const KEY = `ed25519:${"11".repeat(32)}`;
  // (an account this device is not on the lock of asked too: only those it can let in to are said)
  let asked = 0;
  const reading = m.host.secureGet!;
  m.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => {
    if (o.user) asked++;
    return reading.call(m.host, k, o);
  };
  const said = await m.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "Pixel 8", sign_key: null, personal: { subs: ["s1", "someone-else"], key: KEY } }), phone.next()));
  assert.deepEqual(said, { ok: { t: "code", workspaces: ["person:s1"] } });
  assert.equal(asked, 1, "the person is asked as the code is shown");
  const shown = (await m.prompts()).pairing.find((p: { device: string }) => p.device === PHONE);
  assert.match(shown.code, /^[0-9]{6}$/);
  const met2 = { id: ME, d: phone, workspaces: ["person:s1"] };
  const wrong = shown.code === "000000" ? "000001" : "000000";
  assert.deepEqual(await m.run(tryOne(inner, met2, PHONE, wrong)), { ok: { left: PAIR_TRIES - 1 } });
  assert.equal(personal.chain("s1")!.devices.has(KEY), false, "a wrong code lets nobody in");
  const right = await m.run(tryOne(inner, met2, PHONE, shown.code)) as { ok: { approved: { chains: Record<string, Entry[]> } } };
  assert.equal(personal.chain("s1")!.devices.has(KEY), true);
  assert.equal(asked, 1, "and not again as it is let in");
  assert.equal(checkChain(right.ok.approved.chains.s1!, "s1")!.devices.has(KEY), true, "it brings the whole lock to pin");
});

test("a new device asking into its person's own lock makes the key it signs the workspaces' locks with: without one, the device that approves it puts it in none", async () => {
  const s = await started(undefined, 0, undefined, (x) => void (x.host.appKeys = true));
  const inner = s.core.inner;
  inner.mesh = () => withoutMesh(PHONE);
  inner.adb.personal = () => new PersonalLock({ host: s.host, runner: inner.runner, device: () => Effect.succeed(PHONE), label: () => "new", changed: () => {}, cloud: () => Effect.succeed({ entries: [] }) });
  assert.equal(Effect.runSync(Signer.load(s.host)), null, "a device new to every lock keeps no such key");
  const out: unknown[] = [];
  inner.runner.fork(Effect.map(Effect.result(personalBegin(inner, ["s1"])), (r) => out.push(r)));
  await s.host.time.passUntil(1000, () => out.length !== 0);
  assert.equal((out[0] as { _tag: string })?._tag, "Success", JSON.stringify(out));
  const made = Effect.runSync(Signer.load(s.host));
  assert.ok(made, "made as it asks");
  assert.equal(signerOf(inner), made.id, "and what its hello says (sign_key)");
});

test("a device not on the lock shows no code for it, and someone else's lock is not asked here", async () => {
  const m = await met();
  const inner = m.core.inner;
  const none = new PersonalLock({ host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {}, cloud: () => Effect.succeed({ entries: [] }) });
  inner.adb.personal = () => none;
  const [trusted, phone] = await pipe();
  inner.runner.fork(serveTrusted(inner, PHONE, ME, trusted));
  const said = await m.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "x", sign_key: null, personal: { subs: ["s1"], key: `ed25519:${"11".repeat(32)}` } }), phone.next()));
  assert.deepEqual(said, { ok: { t: "no", error: "not_here" } });
});

test("a device on its person's own lock binds it in the workspace's once every station there knows such an entry", async () => {
  const m = await met();
  const inner = m.core.inner;
  const kept: { entries: Entry[] } = { entries: [] };
  const personal = new PersonalLock({
    host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {},
    cloud: (_s, method, _p, body) => Effect.sync(() => {
      if (method === "GET") return { entries: kept.entries };
      kept.entries = (body as { entries: Entry[] }).entries;
      return { entries: kept.entries };
    }),
  });
  const sealed = new Map<string, Uint8Array>();
  m.host.secureSet = (k: string, v: Uint8Array) => Effect.sync(() => void sealed.set(k, v));
  const lockedGet = m.host.secureGet;
  m.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => (o.user ? Effect.succeed(sealed.get(k) ?? null) : lockedGet!.call(m.host, k, o));
  inner.adb.personal = () => personal;
  await m.run(personal.signGrant("s1", { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  const root = personal.root("s1")!;
  const persons = () => fold(held(inner, "ws")!.entries).persons.get("s1");
  // No stations in this lock answer otherwise than the rig does: written, as nothing refuses it.
  await m.run(read(inner, "ws"));
  await m.run(bindPerson(inner, "ws"));
  await m.run(read(inner, "ws"));
  assert.equal(persons(), root);
  assert.equal(onBoundPerson(inner, "ws"), true);
  // Its hello brings the person's own lock, though it is in the workspace's lock too.
  assert.deepEqual(inner.cloudSync.carryPerson?.("ws"), personal.entries("s1"));
  // Bound: not written again.
  const length = held(inner, "ws")!.entries.length;
  await m.run(bindPerson(inner, "ws"));
  await m.run(read(inner, "ws"));
  assert.equal(held(inner, "ws")!.entries.length, length);
});

test("an app device of theirs off the person's own lock keeps it from being bound; bound, their app devices in the workspace's lock are kept to those on it, and one taken off it is told to join it", async () => {
  const OLD = "77".repeat(32), NEW = "88".repeat(32), WEB = "99".repeat(32);
  const OLD_KEY = "ed25519:" + "55".repeat(32), NEW_KEY = "ed25519:" + "44".repeat(32);
  const m = await met(undefined, [
    { id: OLD, sub: "s1", kind: "app", label: "old", sign_key: "ed25519:" + "22".repeat(32) },
    { id: WEB, sub: "s1", kind: "web", label: "web", exp: 2_000_000_000 },
  ]);
  const inner = m.core.inner;
  const kept: { entries: Entry[] } = { entries: [] };
  const personal = new PersonalLock({
    host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {},
    cloud: (_s, method, _p, body) => Effect.sync(() => {
      if (method === "GET") return { entries: kept.entries };
      kept.entries = (body as { entries: Entry[] }).entries;
      return { entries: kept.entries };
    }),
  });
  const sealed = new Map<string, Uint8Array>();
  m.host.secureSet = (k: string, v: Uint8Array) => Effect.sync(() => void sealed.set(k, v));
  const lockedGet = m.host.secureGet;
  m.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => (o.user ? Effect.succeed(sealed.get(k) ?? null) : lockedGet!.call(m.host, k, o));
  inner.adb.personal = () => personal;
  await m.run(personal.signGrant("s1", { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  const devices = () => [...fold(held(inner, "ws")!.entries).devices.keys()].sort();
  const bound = () => fold(held(inner, "ws")!.entries).persons.has("s1");
  await m.run(read(inner, "ws"));
  // The old one, an app device of theirs here, is off their own lock: not bound (the stations would shut it out), and
  // nothing taken out.
  await m.run(bindPerson(inner, "ws"));
  await m.run(read(inner, "ws"));
  assert.equal(bound(), false);
  await m.run(keepToPerson(inner, "ws"));
  assert.deepEqual(devices(), [ME, OLD, WEB].sort());
  // Put on it face to face as well (a web page holds no key of it): bound, and none taken out.
  await m.run(personal.addDevice("s1", { key: OLD_KEY, id: OLD, label: "old" }, "why"));
  await m.run(bindPerson(inner, "ws"));
  await m.run(read(inner, "ws"));
  assert.equal(bound(), true);
  await m.run(keepToPerson(inner, "ws"));
  assert.deepEqual(devices(), [ME, OLD, WEB].sort());
  // One put on the person's lock face to face is put in, with the key it signs with, and kept.
  const newKey = "ed25519:" + "33".repeat(32);
  await m.run(personal.addDevice("s1", { key: NEW_KEY, id: NEW, label: "new" }, "why"));
  await m.run(putOnBound(inner, "s1", { id: NEW, label: "new", signKey: newKey }));
  assert.equal(fold(held(inner, "ws")!.entries).devices.get(NEW)?.sign_key, newKey);
  await m.run(keepToPerson(inner, "ws"));
  assert.deepEqual(devices(), [ME, NEW, OLD, WEB].sort());
  // Taken off the person's lock: out of the workspace's.
  await m.run(personal.removeDevice("s1", NEW_KEY, "why"));
  await m.run(personal.removeDevice("s1", OLD_KEY, "why"));
  await m.run(keepToPerson(inner, "ws"));
  assert.deepEqual(devices(), [ME, WEB].sort());
  // This device taken off it: a station's refusal says to join their own lock, not to be approved in the workspace's,
  // which lets it in no more.
  const mine = [...personal.chain("s1")!.devices.values()].find((d) => d.id === ME)!;
  await m.run(personal.addDevice("s1", { key: "ed25519:" + "66".repeat(32), id: OLD, label: "old" }, "why"));
  await m.run(personal.removeDevice("s1", mine.key, "why"));
  assert.equal(personal.standing("s1"), "outside");
  const said = hooks.lockRefused!(inner, "ws", "st", null);
  assert.equal(said?.code, "lock_unconfirmed");
  assert.equal(said!.message, t("core-misc.lock.offOwnLock", { name: "W" }));
});

test("where they bound a lock of their own, people are shown one thing: a new device's prompt names the workspaces it is let in to, and 移除 on the workspace's page takes a device of theirs off that lock", async () => {
  // (the user, 2026-11-10: nobody is to tell the person's own lock from the workspace's. The prompt said only 它要加入
  // 你的个人锁; a device taken out of the workspace's lock alone was let in still, on their own, and put back)
  const NEW = "88".repeat(32), NEW_KEY = "ed25519:" + "44".repeat(32);
  const m = await met();
  const inner = m.core.inner;
  const kept: { entries: Entry[] } = { entries: [] };
  const personal = new PersonalLock({
    host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {},
    cloud: (_s, method, _p, body) => Effect.sync(() => {
      if (method === "GET") return { entries: kept.entries };
      kept.entries = (body as { entries: Entry[] }).entries;
      return { entries: kept.entries };
    }),
  });
  const sealed = new Map<string, Uint8Array>();
  m.host.secureSet = (k: string, v: Uint8Array) => Effect.sync(() => void sealed.set(k, v));
  const lockedGet = m.host.secureGet;
  m.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => (o.user ? Effect.succeed(sealed.get(k) ?? null) : lockedGet!.call(m.host, k, o));
  inner.adb.personal = () => personal;
  await m.run(personal.signGrant("s1", { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  await m.run(read(inner, "ws"));
  await m.run(bindPerson(inner, "ws"));
  await m.run(read(inner, "ws"));
  assert.ok(fold(held(inner, "ws")!.entries).persons.has("s1"), "bound");

  // A new device of theirs asks (into their own lock, as the page that waits has it ask): the prompt on this one names
  // the workspace, as for one approved into the workspace's lock.
  const asked = await m.run(Effect.andThen(m.phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "33".repeat(32), personal: { subs: ["s1"], key: NEW_KEY } }), m.phone.next()));
  assert.deepEqual(asked, { ok: { t: "code", workspaces: ["person:s1"] } });
  assert.deepEqual((await m.prompts()).pairing.map((p: { workspaces: { id: string; name: string }[] }) => p.workspaces.map((w) => [w.id, w.name])), [[["ws", "W"]]]);

  // One of theirs on that lock and in the workspace's: 移除 there (lock.removeDevice) takes it off their own lock, and
  // out of the workspace's with it.
  await m.run(personal.addDevice("s1", { key: NEW_KEY, id: NEW, label: "new" }, "why"));
  await m.run(putOnBound(inner, "s1", { id: NEW, label: "new", signKey: "ed25519:" + "33".repeat(32) }));
  assert.ok(fold(held(inner, "ws")!.entries).devices.has(NEW));
  await m.ask("lock.removeDevice", { workspace: "ws", device: NEW });
  assert.equal([...personal.chain("s1")!.devices.values()].some((d) => d.id === NEW), false, "off their own lock");
  assert.equal(fold(held(inner, "ws")!.entries).devices.has(NEW), false, "and out of the workspace's");
});

test("a device on the person's own lock that a second workspace bound to it holds as not signing is put in there with the key it signs with in the first", async () => {
  // Safe mode turned on in a second workspace: the person's other devices went into its lock as the draft had them,
  // signing nothing there (no vault, no entries signed), and one they approved since was put in none where they did
  // not sign (the locks' end to end, round 9, 2026-11-10).
  const LAPTOP = "77".repeat(32), LAPTOP_SIGNS = "ed25519:" + "22".repeat(32), LAPTOP_KEY = "ed25519:" + "55".repeat(32);
  const g = grant();
  const m = await rig((me) => ({
    ws: genesis("ws", me, true, [], g.keys, ME, [{ id: LAPTOP, sub: "s1", kind: "app", label: "laptop", sign_key: LAPTOP_SIGNS }]),
    w2: genesis("w2", me, true, [], g.keys, ME, [{ id: LAPTOP, sub: "s1", kind: "app", label: "laptop" }]),
  }));
  await m.watch({ topic: "lock", workspace: "ws" });
  await m.watch({ topic: "lock", workspace: "w2" });
  const inner = m.core.inner;
  const run = async <A>(e: Effect.Effect<A, any>) => {
    const out: unknown[] = [];
    inner.runner.fork(Effect.map(Effect.result(e), (x) => out.push(x)));
    await m.host.time.passUntil(5000, () => out.length !== 0);
  };
  const kept: { entries: Entry[] } = { entries: [] };
  const personal = new PersonalLock({
    host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {},
    cloud: (_s, method, _p, body) => Effect.sync(() => {
      if (method === "GET") return { entries: kept.entries };
      kept.entries = (body as { entries: Entry[] }).entries;
      return { entries: kept.entries };
    }),
  });
  const sealed = new Map<string, Uint8Array>();
  m.host.secureSet = (k: string, v: Uint8Array) => Effect.sync(() => void sealed.set(k, v));
  const lockedGet = m.host.secureGet;
  m.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => (o.user ? Effect.succeed(sealed.get(k) ?? null) : lockedGet!.call(m.host, k, o));
  inner.adb.personal = () => personal;
  const laptopIn = (ws: string) => fold(held(inner, ws)!.entries).devices.get(LAPTOP);
  await run(read(inner, "w2"));
  assert.equal(laptopIn("w2")?.sign_key, undefined, "not signing in the second as it was turned on");
  await run(personal.signGrant("s1", { station: "w2/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  await run(personal.addDevice("s1", { key: LAPTOP_KEY, id: LAPTOP, label: "laptop" }, "why"));
  for (const ws of ["ws", "w2"]) {
    await run(read(inner, ws));
    await run(bindPerson(inner, ws));
    await run(read(inner, ws));
    assert.ok(fold(held(inner, ws)!.entries).persons.has("s1"), `bound in ${ws}`);
  }
  await run(keepToPerson(inner, "w2"));
  assert.equal(laptopIn("w2")?.sign_key, LAPTOP_SIGNS, "put in again with the key it signs with in the first");
  assert.equal(checkLock(held(inner, "w2")!.entries, 2_000).devices.get(LAPTOP)?.sign_key, LAPTOP_SIGNS, "as the lock's rules take it");
  // Its own key in the first stays the only one: nothing written there.
  const length = held(inner, "ws")!.entries.length;
  await run(keepToPerson(inner, "ws"));
  assert.equal(held(inner, "ws")!.entries.length, length);
});

test("a device on the person's own lock that no workspace's lock holds with its key is put in with the one their lock records for it", async () => {
  // A member taken out and added again: the device the owner approved bound their lock, and their second device, on it,
  // was let in by the stations but signed nothing: no workspace's lock held its key (the locks' end to end, round 12,
  // 2026-11-10).
  const LAPTOP = "77".repeat(32), LAPTOP_SIGNS = "ed25519:" + "22".repeat(32), LAPTOP_KEY = "ed25519:" + "55".repeat(32);
  const g = grant();
  const m = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME, []) }));
  await m.watch({ topic: "lock", workspace: "ws" });
  const inner = m.core.inner;
  const run = async <A>(e: Effect.Effect<A, any>) => {
    const out: unknown[] = [];
    inner.runner.fork(Effect.map(Effect.result(e), (x) => out.push(x)));
    await m.host.time.passUntil(5000, () => out.length !== 0);
  };
  const kept: { entries: Entry[] } = { entries: [] };
  const personal = new PersonalLock({
    host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {}, signKey: () => signerOf(inner),
    cloud: (_s, method, _p, body) => Effect.sync(() => {
      if (method === "GET") return { entries: kept.entries };
      kept.entries = (body as { entries: Entry[] }).entries;
      return { entries: kept.entries };
    }),
  });
  const sealed = new Map<string, Uint8Array>();
  m.host.secureSet = (k: string, v: Uint8Array) => Effect.sync(() => void sealed.set(k, v));
  const lockedGet = m.host.secureGet;
  m.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => (o.user ? Effect.succeed(sealed.get(k) ?? null) : lockedGet!.call(m.host, k, o));
  inner.adb.personal = () => personal;
  await run(read(inner, "ws"));
  await run(personal.signGrant("s1", { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  // Put on their lock where no workspace bound it: in no workspace's lock.
  await run(personal.addDevice("s1", { key: LAPTOP_KEY, id: LAPTOP, label: "laptop", sign_key: LAPTOP_SIGNS }, "why"));
  await run(read(inner, "ws"));
  await run(bindPerson(inner, "ws"));
  await run(read(inner, "ws"));
  assert.ok(fold(held(inner, "ws")!.entries).persons.has("s1"), "bound");
  // (the lock read, keepToPerson runs by itself as well: run here to have it done)
  await run(keepToPerson(inner, "ws"));
  assert.equal(fold(held(inner, "ws")!.entries).devices.get(LAPTOP)?.sign_key, LAPTOP_SIGNS, "put in with the key their lock records");
  assert.equal(checkLock(held(inner, "ws")!.entries, 2_000).devices.get(LAPTOP)?.sign_key, LAPTOP_SIGNS, "as the lock's rules take it");
  // Kept: nothing written again.
  const length = held(inner, "ws")!.entries.length;
  await run(keepToPerson(inner, "ws"));
  assert.equal(held(inner, "ws")!.entries.length, length);
  // The laptop signs with another key since, said in this lock (approved here again) and not yet on their chain: the
  // key this lock holds is not written over with the chain's older one.
  const NEWER = "ed25519:" + "23".repeat(32);
  await run(new Lock(inner, "ws", "s1", null).append("device", { id: LAPTOP, sub: "s1", kind: "app", label: "laptop", sign_key: NEWER }));
  await run(read(inner, "ws"));
  const after = held(inner, "ws")!.entries.length;
  await run(keepToPerson(inner, "ws"));
  assert.equal(fold(held(inner, "ws")!.entries).devices.get(LAPTOP)?.sign_key, NEWER, "the newer key kept");
  assert.equal(held(inner, "ws")!.entries.length, after, "nothing written over it");
});

test("a station of the lock that does not say it knows the entry, or does not answer, keeps the person's lock from being bound", async () => {
  const g = grant();
  const A = "aa".repeat(32), B = "bb".repeat(32);
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [{ key: A, name: "a" }, { key: B, name: "b" }], g.keys, ME, []) }));
  const inner = r.core.inner;
  await r.watch({ topic: "lock", workspace: "ws" });
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let out: X | undefined;
    inner.runner.fork(Effect.map(e, (x) => { out = x; done = true; }));
    await r.host.time.passUntil(5000, () => done);
    assert.ok(done, "no answer");
    return out as X;
  };
  const sealed = new Map<string, Uint8Array>();
  r.host.secureSet = (k: string, v: Uint8Array) => Effect.sync(() => void sealed.set(k, v));
  const lockedGet = r.host.secureGet;
  r.host.secureGet = (k: string, o: { user: boolean; reason?: string }) => (o.user ? Effect.succeed(sealed.get(k) ?? null) : lockedGet!.call(r.host, k, o));
  const kept: { entries: Entry[] } = { entries: [] };
  const personal = new PersonalLock({
    host: r.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {},
    cloud: (_s, method, _p, body) => Effect.sync(() => {
      if (method === "POST") kept.entries = (body as { entries: Entry[] }).entries;
      return { entries: kept.entries };
    }),
  });
  inner.adb.personal = () => personal;
  await run(personal.signGrant("s1", { station: "ws/st", request: "p", session: "s", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  const said = new Map<string, Effect.Effect<unknown, any>>();
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { station?: string; toString(): string }, method: string, path: string, ...rest: unknown[]) => {
    const id = addr.toString().split("/")[1]!;
    if (path.startsWith("/lock?after") && said.has(id)) return said.get(id);
    return (original as (...a: unknown[]) => unknown)(addr, method, path, ...rest);
  }) as typeof inner.stations.requests.call;
  const persons = () => fold(held(inner, "ws")!.entries).persons.get("s1");
  await run(read(inner, "ws"));
  const knows = Effect.succeed({ head: null, takes: ["person"] });
  // An older station: it would refuse the entry, and every one after it.
  said.set(A, knows);
  said.set(B, Effect.succeed({ head: null }));
  await run(bindPerson(inner, "ws"));
  await run(read(inner, "ws"));
  assert.equal(persons(), undefined);
  assert.equal(pendingHeld(inner, "ws").length, 0);
  // One that does not answer.
  said.set(B, Effect.fail(new CoreError("offline", "offline")));
  await run(bindPerson(inner, "ws"));
  await run(read(inner, "ws"));
  assert.equal(persons(), undefined);
  // All of them know it: signed (pending here, these stations taking no entry: what is signed waits for one that does).
  said.set(B, knows);
  inner.runner.fork(bindPerson(inner, "ws"));
  await r.host.time.pass(TAKEN_MS + 500);
  assert.deepEqual(pendingHeld(inner, "ws").map((p) => [p.entry.kind, (p.entry.body as { person?: string }).person]), [["person", personal.root("s1")]]);
});
