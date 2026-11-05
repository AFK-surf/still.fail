// Approving a new device face to face (src/pair.ts, src/views/pair.ts): the exchange on its own, then a trusted device's
// core met by a new device over a stream of its own: the code it shows, typed right, signs the new device in; typed
// wrong, it says how many tries are left, and after PAIR_TRIES it signs nothing; turned away, nothing; its prompt
// closed, the code still signs it in; ended there, the new device is told why (not that it typed wrong); a credential
// for another device, nothing; a new device that dialled someone else (its idea of the other end not the trusted one's)
// cannot prove even the right code. The code is good for PAIR_WAIT_MS from when it is shown, wrong ones not putting it
// off; the new device hears its trusted devices end it while nothing is typed (turned away, too old, gone, silent past
// its time) and says why at once. On the test clock, the trusted core's lock at a cloud that keeps chains.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { HostError } from "../src/error.ts";
import { PAIR_ALPN, PAIR_TRIES, pairCode, pairSession, pakeKeys, pakeStart, sameMac, typedCode } from "../src/pair.ts";
import { utf8 } from "../src/util.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import { Bridge, BridgeHost } from "../src/hosts/bridge.ts";
import { t } from "../src/i18n.ts";
import type { Entry } from "../src/lock.ts";
import { PersonalLock, checkChain } from "../src/personal-lock.ts";
import { pairs } from "../src/views/lock.ts";
import { keep, PAIR_GRACE_MS, PAIR_WAIT_MS, served, serveTrusted, streamDuplex, trying, tryOne } from "../src/views/pair.ts";
import { run as runEffect } from "./run.ts";
import { ME, PHONE, genesis, grant, pipe, rig } from "./lock-rig.ts";

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
    for (let i = 0; i < 500 && out.length === 0; i++) await r.host.time.pass(10);
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
  assert.deepEqual(shown[0].workspaces.map((w: { id: string; name: string }) => [w.id, w.name]), [["ws", "W"]]);
  const done = await m.prove(shown[0].code);
  assert.ok("ok" in done && "approved" in done.ok, JSON.stringify(done));
  assert.deepEqual(m.cloud.posted.map((p) => [p.ws, p.kind, p.id]), [["ws", "device", PHONE]]);
  const entry = m.cloud.chains.get("ws")!.at(-1)!;
  assert.deepEqual(entry.body, { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) });
  assert.deepEqual((await m.prompts()).pairing, [], "no longer shown");
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
    for (let i = 0; i < 50 && !f(); i++) await r.host.time.pass(10);
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

test("over iroh: the trusted device takes the new one on its endpoint, and the code typed signs it in", { skip: loadAddon() === null ? "the mesh addon is not built here" : false }, async () => {
  const addon = loadAddon() as any;
  const seen: any[] = [];
  const iroh = nodeIroh({ bind: async (o: any) => { const e = await addon.bind(o); seen.push(e); return e; } })!;
  const trustedEnd = await runEffect(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false, alpns: [PAIR_ALPN] }));
  const newEnd = await runEffect(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false }));
  const socket = (seen[0].sockets() as string[]).find((x) => !x.startsWith("["))!;
  newEnd.addAddr({ id: trustedEnd.id(), ips: [`127.0.0.1:${socket.slice(socket.lastIndexOf(":") + 1)}`] });
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, trustedEnd.id()) }));
  r.core.inner.meshNow = () => ({ deviceId: () => trustedEnd.id() }) as never;
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  // The trusted device's endpoint takes it, as the mesh's does (views/pair.ts `served`).
  void runEffect(trustedEnd.accept!()).then((taken) => taken && served(r.core.inner, taken.connection));
  const connection = await runEffect(newEnd.connect({ id: trustedEnd.id() }, PAIR_ALPN, []));
  const d = streamDuplex(await runEffect(connection.openBi()), () => connection.close(0, "done"));
  await runEffect(d.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", newEnd.id(), "s2") }], kind: "web", label: "Chrome", sign_key: null }));
  const answer = runEffect(d.next());
  for (let i = 0; i < 100 && (await prompts()).pairing.length === 0; i++) await r.host.time.pass(10);
  assert.deepEqual(await answer, { t: "code", workspaces: ["ws"] });
  const code = (await prompts()).pairing[0].code;
  const done: any[] = [];
  r.core.inner.runner.fork(Effect.map(Effect.result(tryOne(r.core.inner, { id: trustedEnd.id(), d, workspaces: ["ws"] }, newEnd.id(), code)), (x) => done.push(x)));
  for (let i = 0; i < 500 && done.length === 0; i++) await r.host.time.pass(10);
  assert.equal(done[0]?._tag, "Success", String(done[0]?.failure?.message));
  const entry = r.cloud.chains.get("ws")!.at(-1)!;
  assert.equal((entry.body as { id: string }).id, newEnd.id());
  assert.equal((entry.body as { kind: string }).kind, "web");
  connection.close(0, "done");
  await runEffect(newEnd.close());
  await runEffect(trustedEnd.close());
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
  const said = await m.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "Pixel 8", sign_key: null, personal: { sub: "s1", key: KEY } }), phone.next()));
  assert.deepEqual(said, { ok: { t: "code", workspaces: ["person:s1"] } });
  const shown = (await m.prompts()).pairing.find((p: { device: string }) => p.device === PHONE);
  assert.match(shown.code, /^[0-9]{6}$/);
  const met2 = { id: ME, d: phone, workspaces: ["person:s1"] };
  const wrong = shown.code === "000000" ? "000001" : "000000";
  assert.deepEqual(await m.run(tryOne(inner, met2, PHONE, wrong)), { ok: { left: PAIR_TRIES - 1 } });
  assert.equal(personal.chain("s1")!.devices.has(KEY), false, "a wrong code lets nobody in");
  const right = await m.run(tryOne(inner, met2, PHONE, shown.code)) as { ok: { approved: { chain: Entry[] } } };
  assert.equal(personal.chain("s1")!.devices.has(KEY), true);
  assert.equal(checkChain(right.ok.approved.chain, "s1")!.devices.has(KEY), true, "it brings the whole lock to pin");
});

test("a device not on the lock shows no code for it, and someone else's lock is not asked here", async () => {
  const m = await met();
  const inner = m.core.inner;
  const none = new PersonalLock({ host: m.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {}, cloud: () => Effect.succeed({ entries: [] }) });
  inner.adb.personal = () => none;
  const [trusted, phone] = await pipe();
  inner.runner.fork(serveTrusted(inner, PHONE, ME, trusted));
  const said = await m.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "x", sign_key: null, personal: { sub: "s1", key: `ed25519:${"11".repeat(32)}` } }), phone.next()));
  assert.deepEqual(said, { ok: { t: "no", error: "not_here" } });
});
