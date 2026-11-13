// What lets someone or something into a workspace whose chain moved to its people's own logs, end to end on a core
// (views/pair.ts, views/lock.ts, personal-lock.ts): a web page approved face to face is an entry `web {id, label, exp}`
// of its person's own log, one for every moved workspace it asked in, the person asked once, the chains of those that
// did not move signed as before in the same approval; renewed by a later `web` of the same id, taken off by
// `web.remove`; let in until its `exp`; only its own person's device approves it. Adding a member is the cloud's alone
// there (nothing signed, nobody asked); a station enrolled and confirmed by its code is a statement `station {key}`.
//
// The world (as test/lock-statements.test.ts's): `ws`, its chain the rig's genesis and a `moved` to s1's own log (this
// device on it, its key known here), which says the settings (the cloud's grant keys), bob (r2) an admin and A a station;
// bob's says xena (r3) a member. `w2`: moved the same way (`w2: "moved"`, B its station), or a chain of its own that
// names no station and this device (`w2: "chain"`), or none.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { type Entry as StationEntry, entryHash as stationHash } from "../../../station/src/cloud/lock.ts";
import { key, signed } from "../../../station/test/lock-world-sim.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, type Signer, WEB_DEVICE_SECS, entryHash, next, shortCode } from "../src/lock.ts";
import { bodyHash, inForce, wsTag } from "../src/lock-moved.ts";
import { added, enrolled, held, inForceOf, read } from "../src/views/lock.ts";
import { serveTrusted, tryOne } from "../src/views/pair.ts";
import { ME, genesis, grant, pipe, rig } from "./lock-rig.ts";

const A = "aa".repeat(32);
const B = "bb".repeat(32);
const C = "cc".repeat(32);
const D = "dd".repeat(32);
/// The web page asking: its base key.
const WEB = "ee".repeat(32);
const T = Date.UTC(2026, 9, 6, 9, 0, 0) / 1000;
const MINE = 7001;
const seedOf = (n: number) => {
  const s = new Uint8Array(32);
  new DataView(s.buffer).setUint32(28, n);
  return s;
};

type Log = { sub: string; k: ReturnType<typeof key>; chain: StationEntry[]; said: string | null; said2: string | null; n: number };
function person(sub: string, n: number, id: string): Log {
  const k = key(n);
  const g = signed({ v: 1, ws: `person:${sub}`, seq: 0, prev: null, at: T, kind: "genesis", body: { sub, device: { key: k.id, id, label: `${sub}'s app` } } } as Omit<StationEntry, "sig">, k);
  return { sub, k, chain: [g], said: null, said2: null, n: 0 };
}
const gOf = (l: Log) => stationHash(l.chain[0]!);
function say(l: Log, kind: string, more: Record<string, unknown>, ws: "ws" | "w2" = "ws"): Record<string, unknown> {
  const b = { ws, kind, ...more, prev: ws === "ws" ? l.said : l.said2, salt: (++l.n + 0x5a00 * l.chain.length).toString(16).padStart(32, "0") };
  const h = bodyHash(b)!;
  const last = l.chain[l.chain.length - 1]!;
  l.chain.push(signed({ v: 1, ws: `person:${l.sub}`, seq: l.chain.length, prev: stationHash(last), at: T, kind: "ws", body: { t: wsTag(ws, gOf(l)), h } } as Omit<StationEntry, "sig">, l.k));
  if (ws === "ws") l.said = h;
  else l.said2 = h;
  return b;
}
type Brought = { at: string; length: number; bodies: unknown[] | null };
type Asked = { at: string; method: string; path: string; body: string };

async function setUp(o: { w2?: "moved" | "chain" } = {}) {
  const g = grant();
  const settings = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: g.keys };
  const me = person("s1", MINE, ME);
  const bob = person("r2", 6002, key(6102).hex);
  const xena = person("r3", 6004, key(6104).hex);
  const bodies: unknown[] = [];
  bodies.push(say(me, "open", { ...settings, email: "a@x.com" }));
  bodies.push(say(me, "member", { sub: "r2", email: "b@x.com", lock: gOf(bob), role: "admin" }));
  bodies.push(say(me, "station", { key: A }));
  bodies.push(say(bob, "member", { sub: "r3", email: "c@x.com", lock: gOf(xena), role: "member" }));
  const bodies2: unknown[] = [];
  if (o.w2 === "moved") bodies2.push(say(me, "open", { ...settings, email: "a@x.com" }, "w2"), say(me, "station", { key: B }, "w2"));
  let mine: Signer | null = null;
  const r = await rig((signer) => ((mine = signer), {
    ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME),
    ...(o.w2 === "moved" ? { w2: genesis("w2", signer, true, [{ key: B, name: "b" }], g.keys, ME) } : o.w2 === "chain" ? { w2: genesis("w2", signer, true, [], g.keys, ME) } : {}),
  }), (host) => {
    host.storage.set(`personal-lock-${Buffer.from("s1").toString("hex")}`, new TextEncoder().encode(JSON.stringify(me.chain)));
    host.storage.set("personal-signer-id", new TextEncoder().encode(me.k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, [A, C], [A, C], undefined, o.w2 === "moved" ? [B, D] : []);
  const inner = r.core.inner;
  const signer = mine! as Signer;
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c[c.length - 1]!), genesis: entryHash(c[0]!) });
  const g0 = r.cloud.chains.get("ws")![0]!;
  const st = { chain: [g0, signer.sign(next("ws", headOf([g0]), 1001, "moved", { root: gOf(me) }))] as Entry[], logs: [bob, xena], bodies, brought: [] as Brought[], silent: false, own: me.chain as unknown as Entry[], asked: [] as Asked[] };
  const g2 = o.w2 === "moved" ? r.cloud.chains.get("w2")![0]! : null;
  const st2 = { chain: g2 === null ? [] : [g2, signer.sign(next("w2", headOf([g2]), 1001, "moved", { root: gOf(me) }))] as Entry[], logs: [] as Log[], bodies: bodies2, brought: [] as Brought[], silent: false };
  const answer = (at: string, method: string, path: string, body: unknown, x: Omit<typeof st, "own" | "asked"> = st): Effect.Effect<unknown, CoreError> => {
    st.asked.push({ at, method, path, body: JSON.stringify(body ?? null) });
    const serves = { takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) return Effect.succeed({ head: headOf(x.chain), entries: x.chain, ...serves });
    if (method === "GET" && path === "/lock/logs") return Effect.succeed({ chains: x.logs.map((l) => ({ genesis: gOf(l), entries: l.chain })) });
    if (method === "GET" && path === "/lock/bodies") return Effect.succeed({ bodies: x.bodies, lacking: [] });
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [{ genesis: entryHash(st.own[0]!), entries: st.own }] });
    if (x.silent && method === "POST") return Effect.never;
    if (method === "POST" && path === "/lock/person") {
      const b = body as { chain?: Entry[]; bodies?: unknown[] };
      const chain = b.chain ?? [];
      x.brought.push({ at, length: chain.length, bodies: b.bodies ?? null });
      if (chain.length > st.own.length) st.own = chain;
      for (const n of b.bodies ?? []) if (!x.bodies.some((y) => bodyHash(y) === bodyHash(n))) x.bodies.push(n);
      return Effect.succeed({ genesis: entryHash(chain[0]!), length: chain.length });
    }
    if (method === "POST") return Effect.succeed({ taken: 1, head: headOf(x.chain) });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if ((id === A || id === C) && path.startsWith("/lock")) return answer(`${ws}/${id === A ? "A" : "C"}`, method, path, body);
    if ((id === B || id === D) && path.startsWith("/lock")) return answer(`${ws}/${id === B ? "B" : "D"}`, method, path, body, st2);
    return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>): Promise<{ ok?: X; error?: CoreError }> => {
    let out: { ok?: X; error?: CoreError } | null = null;
    inner.runner.fork(Effect.match(e, { onSuccess: (ok) => void (out = { ok }), onFailure: (error) => void (out = { error }) }));
    await r.host.time.passUntil(20_000, () => out !== null);
    assert.ok(out !== null, "no answer");
    await r.host.time.pass(100);
    return out;
  };
  const ask = (name: string, params: Record<string, unknown>) => run(Effect.tryPromise({ try: () => r.ask(name, params), catch: (e) => e as CoreError }));
  await run(inner.adb.personal().refresh("s1"));
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  if (o.w2 !== undefined) await run(read(inner, "w2"));
  if (o.w2 === "moved") assert.equal(held(inner, "w2")?.entries.at(-1)?.kind, "moved", "w2's chain held moved");
  assert.equal(inner.adb.personal().standing("s1"), "member", "this device on its own lock");
  const prompts = await r.watch({ topic: "lockPrompts" });
  /// What this device's own log says now, past what it said before: each entry's kind and, for a web page's, its id's
  /// first four. (this device said again on it with the key it signs workspaces' locks with, as any act with the seed
  /// in hand does where its entry lacks it: personal-lock.ts `#restate`; left out)
  const own = () => inner.adb.personal().entries("s1").slice(me.chain.length).filter((e) => !(e.kind === "device" && (e.body as { id?: string }).id === ME));
  const said = () => own().map((e) => (e.kind === "web" || e.kind === "web.remove" ? `${e.kind} ${String((e.body as { id: string }).id).slice(0, 4)}` : e.kind));
  const asked = () => r.host.secureAsked.length;
  /// The web page's hello, with credentials for `places` as `sub`, and the trusted device's answer.
  const hello = async (places: string[], sub = "s1") => {
    const [trusted, page] = await pipe();
    inner.runner.fork(serveTrusted(inner, WEB, ME, trusted));
    const first = await run(Effect.andThen(page.send({ t: "hello", v: 1, workspaces: places.map((ws) => ({ ws, credential: g.credential(ws, WEB, sub) })), kind: "web", label: "Chrome", sign_key: null }), page.next()));
    return { page, answer: first.ok as { t: string; workspaces?: string[]; error?: string } };
  };
  /// The code shown here typed on the page: the trusted device's answer.
  const prove = async (page: Awaited<ReturnType<typeof hello>>["page"], where: string[]) => {
    const code = ((await prompts()).pairing as { device: string; code: string }[]).find((p) => p.device === WEB)!.code;
    return run(tryOne(inner, { id: ME, d: page, workspaces: where }, WEB, code));
  };
  /// The web page as the state of `ws` made of s1's own log and the bodies kept lets it in at `ms`.
  const lets = (ws: "ws" | "w2", ms = r.host.nowMs()) => {
    const chains = new Map<string, readonly Entry[]>([[gOf(me), inner.adb.personal().entries("s1")], ...(ws === "ws" ? [bob, xena] : []).map((l) => [gOf(l), l.chain as unknown as Entry[]] as const)]);
    const f = inForce(ws, held(inner, ws)!.entries, chains, ws === "ws" ? st.bodies : st2.bodies, ms).f;
    return f.devices.get(WEB)?.kind === "web";
  };
  return { r, inner, st, st2, run, ask, said, own, asked, hello, prove, lets, me, prompts };
}

test("a web page approved face to face where the chain moved: a `web` entry of the person's own log, the person asked once, let in until its `exp`", async () => {
  const w = await setUp();
  const before = w.asked();
  const { page, answer } = await w.hello(["ws"]);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws"] }, "a code shown for it");
  assert.equal(w.asked(), before, "nobody asked for showing a code");
  const done = await w.prove(page, ["ws"]);
  assert.equal(done.error, undefined, done.error?.message);
  assert.deepEqual((done.ok as { approved: { workspaces: string[] } }).approved.workspaces, ["ws"]);
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.deepEqual(w.said(), ["web eeee"], "one `web` entry on s1's own log, no statement");
  const e = w.own().find((x) => x.kind === "web")!;
  const b = e.body as { id: string; label: string; exp: number };
  assert.deepEqual(Object.keys(b).sort(), ["exp", "id", "label"]);
  assert.equal(b.id, WEB);
  assert.equal(b.label, "Chrome");
  assert.equal(b.exp, e.at + WEB_DEVICE_SECS, "for WEB_DEVICE_SECS from when it was signed");
  assert.ok(w.st.own.some((x) => x.kind === "web") && w.st.brought.every((x) => x.bodies === null), "brought to the stations as a device entry is, no body");
  assert.equal(inForceOf(w.inner, "ws").f.devices.get(WEB)?.kind, "web", "let in by the state in force here");
  assert.equal(w.lets("ws", (b.exp - 1) * 1000), true, "until its exp");
  assert.equal(w.lets("ws", b.exp * 1000), false, "not from its exp on");
});

test("renewed: a later `web` of the same id; taken off: `web.remove`; each asks the person once", async () => {
  const w = await setUp();
  const { page } = await w.hello(["ws"]);
  await w.prove(page, ["ws"]);
  const exp1 = (w.own().find((x) => x.kind === "web")!.body as { exp: number }).exp;
  await w.r.host.time.pass(60_000);
  const before = w.asked();
  const renewed = await w.ask("lock.renew", { workspace: "ws", device: WEB });
  assert.equal(renewed.error, undefined, renewed.error?.message);
  assert.equal(w.asked() - before, 1, "the person asked once to renew");
  assert.deepEqual(w.said(), ["web eeee", "web eeee"]);
  const exp2 = (w.own().filter((x) => x.kind === "web").at(-1)!.body as { exp: number }).exp;
  assert.ok(exp2 > exp1, `a later exp (${exp1} then ${exp2})`);
  const off = await w.ask("lock.removeDevice", { workspace: "ws", device: WEB });
  assert.equal(off.error, undefined, off.error?.message);
  assert.equal(w.asked() - before, 2, "the person asked once to take it off");
  assert.deepEqual(w.said(), ["web eeee", "web eeee", "web.remove eeee"]);
  assert.equal(inForceOf(w.inner, "ws").f.devices.has(WEB), false, "no longer let in");
});

test("a web page asking in two moved workspaces: one `web` entry lets it into both, the person asked once", async () => {
  const w = await setUp({ w2: "moved" });
  const before = w.asked();
  const { page, answer } = await w.hello(["ws", "w2"]);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws", "w2"] });
  const done = await w.prove(page, ["ws", "w2"]);
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(w.asked() - before, 1, "the person asked once, not once a workspace");
  assert.deepEqual(w.said(), ["web eeee"], "one `web` entry");
  assert.equal(inForceOf(w.inner, "ws").f.devices.get(WEB)?.kind, "web");
  assert.equal(inForceOf(w.inner, "w2").f.devices.get(WEB)?.kind, "web");
});

test("a web page asking in a moved workspace and one whose chain did not move: one `web` entry, one chain `device` entry, in the same approval", async () => {
  const w = await setUp({ w2: "chain" });
  const before = w.asked();
  const { page, answer } = await w.hello(["ws", "w2"]);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws", "w2"] });
  const done = await w.prove(page, ["ws", "w2"]);
  assert.equal(done.error, undefined, done.error?.message);
  assert.deepEqual([...(done.ok as { approved: { workspaces: string[] } }).approved.workspaces].sort(), ["w2", "ws"]);
  assert.equal(w.asked() - before, 1, "the person asked once (the chain's signer asks nobody, as before)");
  assert.deepEqual(w.said(), ["web eeee"]);
  assert.deepEqual(w.r.cloud.posted.filter((p) => p.ws === "w2" && p.kind !== "person").map((p) => `${p.kind} ${p.id?.slice(0, 4)}`), ["device eeee"], "w2's chain: its `device` entry (and the person's own log bound there, `bindPerson`, as before)");
  assert.equal(w.r.cloud.posted.filter((p) => p.ws === "ws").length, 0, "nothing on ws's chain");
});

test("someone else's web page (another member's credential): no code where the chain moved, nothing signed, nobody asked", async () => {
  const w = await setUp();
  const before = w.asked();
  const { answer } = await w.hello(["ws"], "r2");
  assert.deepEqual(answer, { t: "no", error: "not_here" });
  assert.equal(w.asked(), before);
  assert.deepEqual(w.said(), []);
});

test("adding a member where the chain moved: the cloud's part alone, nothing signed, nobody asked", async () => {
  const w = await setUp();
  const before = w.asked();
  const answer = { joined: ["d@x.com"], added: ["e@x.com"], already: [], view: { members: [{ sub: "r4", email: "d@x.com", role: "member" }] } };
  const out = await w.run(added(w.inner, "s1", "ws", "admin", answer));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(out.ok, null);
  assert.equal(w.asked(), before, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing on s1's own log");
  assert.equal(w.st.asked.filter((q) => q.method === "POST").length, 0, "nothing brought to a station");
  assert.equal(w.r.cloud.posted.length, 0, "nothing on the chain");
  assert.equal(inForceOf(w.inner, "ws").f.members.has("r4"), false, "not in the list until their first device is let in");
});

test("a station enrolled and confirmed by its code where the chain moved: its commands pin the chain held, then `station {key}` said, the person asked once", async () => {
  const w = await setUp();
  const made = await w.run(enrolled(w.inner, "s1", "ws", { command: "stillfail enroll" }));
  assert.equal(made.error, undefined, made.error?.message);
  const head = entryHash(held(w.inner, "ws")!.entries.at(-1)!);
  assert.equal((made.ok as { lock: string }).lock, head, "the chain's head pinned");
  assert.equal((made.ok as { command: string }).command, `stillfail enroll --lock ${head}`);
  const before = w.asked();
  const wrong = await w.ask("lock.addStation", { workspace: "ws", station: C, code: "XXXX" });
  assert.ok(wrong.error !== undefined, "a wrong code refused");
  assert.equal(w.asked(), before, "nobody asked for a wrong code");
  const out = await w.ask("lock.addStation", { workspace: "ws", station: C, code: shortCode(C) });
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.deepEqual(w.said(), ["ws"], "one statement on s1's own log");
  const h = (w.own().at(-1)!.body as { h: string }).h;
  const body = [...w.st.bodies].find((b) => bodyHash(b) === h) as { kind: string; key: string };
  assert.deepEqual([body.kind, body.key], ["station", C]);
  assert.ok(inForceOf(w.inner, "ws").f.stations.has(C), "C in the list");
  assert.equal(w.r.cloud.posted.length, 0, "nothing on the chain");
});
