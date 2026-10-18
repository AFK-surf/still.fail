// Approving a new device face to face (src/pair.ts, src/views/pair.ts): the exchange on its own, then a trusted device's
// core met by a new device over a stream of its own: the code it shows, typed right, signs the new device in; typed
// wrong, it says how many tries are left, and after PAIR_TRIES it signs nothing; turned away, nothing; a credential for
// another device, nothing; a new device that dialled someone else (its idea of the other end not the trusted one's)
// cannot prove even the right code. On the test clock, the trusted core's lock at a cloud that keeps chains.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect, Queue } from "effect";
import { PAIR_ALPN, PAIR_TRIES, pairCode, pairSession, pakeKeys, pakeStart, sameMac, typedCode } from "../src/pair.ts";
import { base64url as toB64url, utf8 } from "../src/util.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import { type Duplex, served, serveTrusted, streamDuplex, tryOne } from "../src/views/pair.ts";
import { run as runEffect } from "./run.ts";
import { ME, PHONE, genesis, rig } from "./lock-rig.ts";

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

/// The cloud's grant key, as the lock names it, and credentials it signs.
function grant() {
  const seed = new Uint8Array(32).fill(7);
  const jwk = { kty: "OKP", crv: "Ed25519", kid: "k1", x: toB64url(ed25519.getPublicKey(seed)) };
  const credential = (ws: string, device: string, sub: string, exp = 4102444800) => {
    const head = toB64url(utf8(JSON.stringify({ alg: "EdDSA", typ: "stillfail-member+jwt", kid: "k1" })));
    const body = toB64url(utf8(JSON.stringify({ iss: "stillfail-cloud", sub, email: `${sub}@x.com`, name: sub === "s2" ? "李二" : sub, ws, role: "member", device, exp })));
    return `${head}.${body}.${toB64url(ed25519.sign(utf8(`${head}.${body}`), seed))}`;
  };
  return { keys: { keys: [jwk] }, credential };
}

/// Two ends of a stream of lines.
async function pipe(): Promise<[Duplex, Duplex]> {
  const a = await Effect.runPromise(Queue.unbounded<unknown>());
  const b = await Effect.runPromise(Queue.unbounded<unknown>());
  const end = (mine: Queue.Queue<unknown>, theirs: Queue.Queue<unknown>): Duplex => ({
    send: (m) => Effect.sync(() => void Queue.offerUnsafe(theirs, JSON.parse(JSON.stringify(m)))),
    next: () => Queue.take(mine) as Effect.Effect<any>,
    close: () => void Queue.offerUnsafe(theirs, null),
  });
  return [end(a, b), end(b, a)];
}

async function met() {
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys) }));
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

test("a new device that dialled someone else cannot prove even the right code to the trusted one", async () => {
  const m = await met();
  await m.hello();
  const code = (await m.prompts()).pairing[0].code;
  // Its idea of the other end is not the trusted device's (a relay between them, a false lock).
  assert.deepEqual(await m.prove(code, "ef".repeat(32)), { ok: { left: PAIR_TRIES - 1 } });
  assert.deepEqual(m.cloud.posted, []);
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
