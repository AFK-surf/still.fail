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
import { added, enrolled, held, inForceOf, outOf, read } from "../src/views/lock.ts";
import { hooks } from "../src/core/execute.ts";
import { ownLogFor, serveTrusted, tryOne } from "../src/views/pair.ts";
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

/// `root: "alice"`: alice's log (r1) is the root and says those, and s1 as `mine`. `view`: the workspace's view's members
/// (the control plane's word of each one's role).
async function setUp(o: { w2?: "moved" | "chain"; root?: "me" | "alice"; mine?: "owner" | "admin" | "member"; view?: { sub: string; email: string; role: string }[] } = {}) {
  const g = grant();
  const settings = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: g.keys };
  const me = person("s1", MINE, ME);
  const bob = person("r2", 6002, key(6102).hex);
  const xena = person("r3", 6004, key(6104).hex);
  const alice = person("r1", 6001, key(6101).hex);
  const root = o.root === "alice" ? alice : me;
  const bodies: unknown[] = [];
  bodies.push(say(root, "open", { ...settings, email: "a@x.com" }));
  if (o.root === "alice") bodies.push(say(alice, "member", { sub: "s1", email: "s1@x.com", lock: gOf(me), role: o.mine ?? "owner" }));
  bodies.push(say(root, "member", { sub: "r2", email: "b@x.com", lock: gOf(bob), role: "admin" }));
  bodies.push(say(root, "station", { key: A }));
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
  }, [A, C], [A, C], undefined, o.w2 === "moved" ? [B, D] : [], o.view === undefined ? {} : { members: o.view });
  const inner = r.core.inner;
  const signer = mine! as Signer;
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c[c.length - 1]!), genesis: entryHash(c[0]!) });
  const g0 = r.cloud.chains.get("ws")![0]!;
  const st = { chain: [g0, signer.sign(next("ws", headOf([g0]), 1001, "moved", { root: gOf(root) }))] as Entry[], logs: o.root === "alice" ? [alice, bob, xena] : [bob, xena], bodies, brought: [] as Brought[], silent: false, own: me.chain as unknown as Entry[], asked: [] as Asked[] };
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
  /// Someone's first device asking (`id` its base key; an app, with `log` the log of its own it brings) as `sub`.
  const helloApp = async (sub: string, id: string, log: StationEntry[] | null) => {
    const [trusted, phone] = await pipe();
    inner.runner.fork(serveTrusted(inner, id, ME, trusted));
    const first = await run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", id, sub) }], kind: "app", label: "Pixel", sign_key: "ed25519:" + "11".repeat(32), ...(log !== null ? { log } : {}) }), phone.next()));
    return { phone, answer: first.ok as { t: string; workspaces?: string[]; error?: string } };
  };
  const proveApp = async (phone: Awaited<ReturnType<typeof helloApp>>["phone"], id: string) => {
    const code = ((await prompts()).pairing as { device: string; code: string }[]).find((p) => p.device === id)!.code;
    return run(tryOne(inner, { id: ME, d: phone, workspaces: ["ws"] }, id, code));
  };
  /// The bodies of this device's statements past what s1's log said before: kind, whom, role, log.
  const stated = () => own().filter((e) => e.kind === "ws").map((e) => {
    const h = (e.body as { h: string }).h;
    const b = [...st.bodies, ...((inner.data.record("lockBodies", "ws") as { bodies?: unknown[] } | null)?.bodies ?? [])].find((x) => bodyHash(x) === h) as Record<string, unknown> | undefined;
    return b === undefined ? "(no body)" : [b.kind, b.sub ?? "", b.role ?? "", typeof b.lock === "string" ? b.lock.slice(0, 6) : ""].join(" ").trim();
  });
  const members = () => [...inForceOf(inner, "ws").f.members].map(([sub, m]) => `${sub} ${m.role}`).sort().join(", ");
  return { r, inner, st, st2, run, ask, said, own, asked, hello, prove, lets, me, prompts, helloApp, proveApp, stated, members, xena, alice, bodies };
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

/// Someone's first device (NEW, its base key) and the log of their own it brings.
const NEW = key(6109).hex;
const newcomer = (sub = "r9", n = 6009, device = NEW) => person(sub, n, device);
const VIEW = [{ sub: "s1", email: "s1@x.com", role: "owner" }, { sub: "r2", email: "b@x.com", role: "admin" }, { sub: "r3", email: "c@x.com", role: "member" }];

test("someone's first device where the chain moved: the code shown by an owner's device, then `member` with the log it brought and the role the view gives, the person asked once", async () => {
  const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "admin" }] });
  const log = newcomer();
  const before = w.asked();
  const { phone, answer } = await w.helloApp("r9", NEW, log.chain);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws"] }, "a code shown");
  assert.equal(w.asked(), before, "nobody asked for showing it");
  const done = await w.proveApp(phone, NEW);
  assert.equal(done.error, undefined, done.error?.message);
  assert.deepEqual((done.ok as { approved: { workspaces: string[] } }).approved.workspaces, ["ws"]);
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.deepEqual(w.stated(), [`member r9 admin ${gOf(log).slice(0, 6)}`], "one statement: r9 with their own log, as the view's admin");
  assert.equal(w.members(), "r2 admin, r3 member, r9 admin, s1 owner");
  assert.equal(inForceOf(w.inner, "ws").f.persons.get("r9"), gOf(log), "bound to the log it brought");
  assert.equal(w.r.cloud.posted.length, 0, "nothing on the chain");
});

test("someone's first device bringing a log not of the credential's person, or one it is not on, or none: no code, nothing signed, nobody asked", async () => {
  const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "member" }] });
  const before = w.asked();
  for (const [why, log] of [["another person's log", newcomer("r8", 6008).chain], ["a log it is not on", newcomer("r9", 6009, key(6110).hex).chain], ["no log", null]] as const) {
    const { answer } = await w.helloApp("r9", NEW, log);
    assert.deepEqual(answer, { t: "no", error: "not_here" }, why);
  }
  assert.equal(w.asked(), before);
  assert.deepEqual(w.stated(), []);
});

test("an admin letting in someone the view calls an owner: no code, refused before the person is asked; a member's device shows none", async () => {
  const a = await setUp({ root: "alice", mine: "admin", view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "owner" }] });
  const before = a.asked();
  assert.deepEqual((await a.helloApp("r9", NEW, newcomer().chain)).answer, { t: "no", error: "not_here" });
  assert.equal(a.asked(), before, "nobody asked");
  assert.deepEqual(a.stated(), []);
  const m = await setUp({ root: "alice", mine: "member", view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "member" }] });
  assert.deepEqual((await m.helloApp("r9", NEW, newcomer().chain)).answer, { t: "no", error: "not_here" });
  assert.deepEqual(m.stated(), []);
});

test("a member the list names under another log (their lock begun anew): the old binding taken out, the member said again with the new log", async () => {
  const w = await setUp({ view: VIEW });
  const log = newcomer("r3", 6014);
  const { phone, answer } = await w.helloApp("r3", NEW, log.chain);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws"] });
  const done = await w.proveApp(phone, NEW);
  assert.equal(done.error, undefined, done.error?.message);
  assert.deepEqual(w.stated(), ["member.remove r3", `member r3 member ${gOf(log).slice(0, 6)}`]);
  assert.equal(inForceOf(w.inner, "ws").f.persons.get("r3"), gOf(log), "bound to the new log");
  assert.equal(w.members(), "r2 admin, r3 member, s1 owner");
});

test("a device on its person's own log brings that log where the chain moved: in its hello to the trusted device, and in its hello to the stations, which take a member's log only so", async () => {
  const w = await setUp();
  const log = await w.run(ownLogFor(w.inner, ["ws"]));
  assert.equal(log.error, undefined, log.error?.message);
  assert.equal(entryHash((log.ok as Entry[])[0]!), stationHash(w.me.chain[0]!), "the log it is on, named as it is");
  const carried = w.inner.cloudSync.carryPerson?.("ws") ?? null;
  assert.ok(carried !== null && entryHash(carried[0]!) === stationHash(w.me.chain[0]!), "carried to the stations");
  assert.equal((await w.run(ownLogFor(w.inner, []))).ok, null, "none where no workspace it waits in moved");
});

test("a person's own new app device (the personal exchange) where the chains moved: put on their own log alone, and so let into every moved workspace of theirs, nothing signed on a chain", async () => {
  const w = await setUp({ w2: "moved" });
  const k = key(7009);
  const id = key(7109).hex;
  const chains = { ws: held(w.inner, "ws")!.entries.length, w2: held(w.inner, "w2")!.entries.length };
  const before = w.asked();
  const [trusted, phone] = await pipe();
  w.inner.runner.fork(serveTrusted(w.inner, id, ME, trusted));
  const first = await w.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "Pixel", sign_key: "ed25519:" + "12".repeat(32), personal: { subs: ["s1"], key: k.id } }), phone.next()));
  assert.deepEqual(first.ok, { t: "code", workspaces: ["person:s1"] });
  const code = ((await w.prompts()).pairing as { device: string; code: string }[]).find((p) => p.device === id)!.code;
  const done = await w.run(tryOne(w.inner, { id: ME, d: phone, workspaces: ["person:s1"] }, id, code));
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.ok(w.own().some((e) => e.kind === "device" && (e.body as { id: string }).id === id), "on s1's own log");
  assert.equal(inForceOf(w.inner, "ws").f.devices.get(id)?.kind, "app", "let into ws");
  assert.equal(inForceOf(w.inner, "w2").f.devices.get(id)?.kind, "app", "and into w2");
  assert.equal(held(w.inner, "ws")!.entries.length, chains.ws, "nothing on ws's chain");
  assert.equal(held(w.inner, "w2")!.entries.length, chains.w2, "nor on w2's");
  assert.equal(w.r.cloud.posted.filter((p) => p.ws === "ws" || p.ws === "w2").length, 0, "nothing sent to the chains' cloud");
});

test("a device whose person was taken out where the chain moved: the refusal's removal and the log entry that commits to it taken, and who took it out and when said", async () => {
  const w = await setUp({ root: "alice", mine: "member" });
  assert.equal(outOf(w.inner, "ws"), null, "in the list: nobody took it out");
  const admit = w.bodies.find((b) => (b as { kind: string; sub?: string }).kind === "member" && (b as { sub: string }).sub === "s1")!;
  const removal = say(w.alice, "member.remove", { sub: "s1", cancels: [bodyHash(admit)!] });
  const out = { bodies: [removal], logs: [{ genesis: gOf(w.alice), entries: w.alice.chain }] };
  hooks.lockRefused?.(w.inner, "ws", A, null, { out });
  await w.r.host.time.pass(100);
  assert.equal(inForceOf(w.inner, "ws").f.members.has("s1"), false, "the list made here no longer names it");
  assert.deepEqual(outOf(w.inner, "ws"), { by: "r1", at: w.alice.chain.at(-1)!.at }, "taken out by alice, at her entry's time");
  const other = await setUp({ root: "alice", mine: "member" });
  hooks.lockRefused?.(other.inner, "ws", A, null, { out: { bodies: [removal], logs: [] } });
  assert.equal(inForceOf(other.inner, "ws").f.members.has("s1"), true, "a body no log kept commits to is not taken");
  assert.equal(outOf(other.inner, "ws"), null);
});
