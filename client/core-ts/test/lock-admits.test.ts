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
import { added, enrolled, held, inForceOf, outOf, read, roster } from "../src/views/lock.ts";
import { hooks } from "../src/core/execute.ts";
import { dialer, ownLogFor, serveTrusted, tryOne } from "../src/views/pair.ts";
import { ME, committed, genesis, grant, pipe, rig } from "./lock-rig.ts";

const A = "aa".repeat(32);
const B = "bb".repeat(32);
const C = "cc".repeat(32);
const D = "dd".repeat(32);
/// The signing key alice's app (her own log's genesis device) signs workspaces' locks with: it may let a newcomer in.
const ALICE_SIGNS = "ed25519:" + "a1".repeat(32);
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
function person(sub: string, n: number, id: string, signKey?: string): Log {
  const k = key(n);
  const g = signed({ v: 1, ws: `person:${sub}`, seq: 0, prev: null, at: T, kind: "genesis", body: { sub, device: { key: k.id, id, label: `${sub}'s app`, ...(signKey !== undefined ? { sign_key: signKey } : {}) } } } as Omit<StationEntry, "sig">, k);
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

/// `root: "alice"`: alice's log (r1) is the root and says those, and s1 as `mine` (`none`: not at all). `view`: the
/// workspace's view's members (the control plane's word of each one's role). `own`: s1's own log, this device on it
/// (`on`), none at all (`none`), or one of another device of theirs this device is not on (`other`).
async function setUp(o: { w2?: "moved" | "chain"; root?: "me" | "alice"; mine?: "owner" | "admin" | "member" | "none"; view?: { sub: string; email: string; role: string }[]; own?: "on" | "none" | "other" } = {}) {
  const g = grant();
  const settings = { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: g.keys };
  const me = person("s1", MINE, ME);
  const bob = person("r2", 6002, key(6102).hex);
  const xena = person("r3", 6004, key(6104).hex);
  const alice = person("r1", 6001, key(6101).hex, ALICE_SIGNS);
  const elsewhere = person("s1", 6111, key(6112).hex);
  const root = o.root === "alice" ? alice : me;
  const bodies: unknown[] = [];
  bodies.push(say(root, "open", { ...settings, email: "a@x.com" }));
  if (o.root === "alice" && o.mine !== "none") bodies.push(say(alice, "member", { sub: "s1", email: "s1@x.com", lock: gOf(me), role: o.mine ?? "owner" }));
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
    if (o.own !== undefined && o.own !== "on") return;
    host.storage.set(`personal-lock-${Buffer.from("s1").toString("hex")}`, new TextEncoder().encode(JSON.stringify(me.chain)));
    host.storage.set("personal-signer-id", new TextEncoder().encode(me.k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, [A, C], [A, C], undefined, o.w2 === "moved" ? [B, D] : [], o.view === undefined ? {} : { members: o.view });
  const inner = r.core.inner;
  const signer = mine! as Signer;
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c[c.length - 1]!), genesis: entryHash(c[0]!) });
  const g0 = r.cloud.chains.get("ws")![0]!;
  const st = { chain: [g0, signer.sign(next("ws", headOf([g0]), 1001, "moved", { root: gOf(root) }))] as Entry[], logs: o.root === "alice" ? [alice, bob, xena] : [bob, xena], bodies, brought: [] as Brought[], silent: false, own: (o.own === "none" ? [] : o.own === "other" ? elsewhere.chain : me.chain) as unknown as Entry[], asked: [] as Asked[] };
  const g2 = o.w2 === "moved" ? r.cloud.chains.get("w2")![0]! : null;
  const st2 = { chain: g2 === null ? [] : [g2, signer.sign(next("w2", headOf([g2]), 1001, "moved", { root: gOf(me) }))] as Entry[], logs: [] as Log[], bodies: bodies2, brought: [] as Brought[], silent: false };
  const answer = (at: string, method: string, path: string, body: unknown, x: Omit<typeof st, "own" | "asked"> = st): Effect.Effect<unknown, CoreError> => {
    st.asked.push({ at, method, path, body: JSON.stringify(body ?? null) });
    const serves = { takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) return Effect.succeed({ head: headOf(x.chain), entries: x.chain, ...serves });
    // (a device the list does not name is given no log and no body: it is told it is left out, `asking`)
    const named = o.mine !== "none" || x !== st;
    if (method === "GET" && path === "/lock/logs") return Effect.succeed({ chains: named ? x.logs.map((l) => ({ genesis: gOf(l), entries: l.chain })) : [] });
    if (method === "GET" && path === "/lock/bodies") return Effect.succeed({ bodies: named ? x.bodies : [], lacking: [] });
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: st.own.length === 0 ? [] : [{ genesis: entryHash(st.own[0]!), entries: st.own }] });
    if (x.silent && method === "POST") return Effect.never;
    if (method === "POST" && path === "/lock/person") {
      const b = body as { chain?: Entry[]; bodies?: unknown[] };
      const chain = b.chain ?? [];
      x.brought.push({ at, length: chain.length, bodies: b.bodies ?? null });
      if (chain.length > st.own.length) st.own = chain;
      // (a body taken against an entry kept that commits to it, as a station takes one)
      const kept = [st.own, ...x.logs.map((l) => l.chain as unknown as Entry[])];
      for (const n of b.bodies ?? []) if (committed(at.split("/")[0]!, kept, n) && !x.bodies.some((y) => bodyHash(y) === bodyHash(n))) x.bodies.push(n);
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
  assert.equal(inner.adb.personal().standing("s1"), o.own === "none" ? "none" : o.own === "other" ? "outside" : "member", "this device's standing on its own lock");
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
  return { r, inner, st, st2, run, ask, said, own, asked, hello, prove, lets, me, prompts, helloApp, proveApp, stated, members, xena, alice, bodies, elsewhere, g };
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

/// The person on this device adds `email` to `ws` as `role` (the cloud's answer: `r9` joined under it, or, `sub` null,
/// added before they have an account).
const addHere = (w: Awaited<ReturnType<typeof setUp>>, role: string, sub: string | null = "r9", email = "r9@x.com") =>
  w.run(added(w.inner, "s1", "ws", role, sub === null ? { joined: [], added: [email], already: [], view: { members: [] } } : { joined: [email], added: [], already: [], view: { members: [{ sub, email, role }] } }));
/// The whole first admission of r9 (NEW, the log it brings): the hello's answer, then, a code shown, the proof's.
async function admitR9(w: Awaited<ReturnType<typeof setUp>>) {
  const log = newcomer();
  const { phone, answer } = await w.helloApp("r9", NEW, log.chain);
  if (answer.t !== "code") return { log, answer, done: null };
  return { log, answer, done: await w.proveApp(phone, NEW) };
}

test("someone's first device where the chain moved: the code shown by an owner's device, then `member` with the log it brought and the role this person gave them here, the person asked once", async () => {
  const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "admin" }] });
  assert.equal((await addHere(w, "admin")).error, undefined, "added here as an admin");
  const log = newcomer();
  const before = w.asked();
  const { phone, answer } = await w.helloApp("r9", NEW, log.chain);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws"] }, "a code shown");
  assert.equal(w.asked(), before, "nobody asked for showing it");
  const done = await w.proveApp(phone, NEW);
  assert.equal(done.error, undefined, done.error?.message);
  assert.deepEqual((done.ok as { approved: { workspaces: string[] } }).approved.workspaces, ["ws"]);
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.deepEqual(w.stated(), [`member r9 admin ${gOf(log).slice(0, 6)}`], "one statement: r9 with their own log, as the admin this person added them as here");
  assert.equal(w.members(), "r2 admin, r3 member, r9 admin, s1 owner");
  assert.equal(inForceOf(w.inner, "ws").f.persons.get("r9"), gOf(log), "bound to the log it brought");
  assert.equal(w.r.cloud.posted.length, 0, "nothing on the chain");
});

/// What this device noted of whom its person added to `ws` (views/lock.ts `lockAdded`): each one's name.
const notedHere = (w: Awaited<ReturnType<typeof setUp>>) => (((w.inner.data.record("lockAdded", "ws") as { notes?: { who: string }[] } | null)?.notes) ?? []).map((n) => n.who);

test("the role at a first admission is never the view's word: one the view calls an owner or an admin whom nobody added on this device is said a member", async () => {
  for (const role of ["owner", "admin"]) {
    const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role }] });
    const { log, answer, done } = await admitR9(w);
    assert.deepEqual(answer, { t: "code", workspaces: ["ws"] }, `the view says ${role}: a code shown`);
    assert.equal(done?.error, undefined, done?.error?.message);
    assert.deepEqual(w.stated(), [`member r9 member ${gOf(log).slice(0, 6)}`], `the view says ${role}: a member`);
  }
});

test("the role at a first admission: what this person chose here as they added them (by sub, or by email before they had an account), used once; one added on another device a member; the view's viewer a viewer", async () => {
  for (const sub of ["r9", null]) {
    const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "admin" }] });
    const before = w.asked();
    assert.equal((await addHere(w, "admin", sub)).error, undefined);
    assert.equal(w.asked(), before, "adding asks nobody");
    assert.equal(w.stated().length, 0, "adding signs nothing");
    assert.equal(notedHere(w).length, 1, `noted on this device (${sub ?? "by email"})`);
    const { log, done } = await admitR9(w);
    assert.equal(done?.error, undefined, done?.error?.message);
    assert.deepEqual(w.stated(), [`member r9 admin ${gOf(log).slice(0, 6)}`], `added here as an admin (${sub ?? "by email"}): an admin`);
    assert.deepEqual(notedHere(w), [], "the note gone once used");
  }
  const other = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "admin" }] });
  const elsewhere = await admitR9(other);
  assert.deepEqual(other.stated(), [`member r9 member ${gOf(elsewhere.log).slice(0, 6)}`], "added as an admin on another device (the view says admin): a member");
  const v = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "viewer" }] });
  const viewer = await admitR9(v);
  assert.equal(viewer.done?.error, undefined, viewer.done?.error?.message);
  assert.deepEqual(v.stated(), [`member r9 viewer ${gOf(viewer.log).slice(0, 6)}`], "the view says viewer: a viewer");
});

test("a note this device's signer may not give (an admin's device, a note saying owner): no code, nobody asked, never an owner; a note it may give (admin) is said", async () => {
  const a = await setUp({ root: "alice", mine: "admin", view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "member" }] });
  a.inner.data.put("lockAdded", "ws", { notes: [{ by: "s1", who: "r9", role: "owner" }] });
  const before = a.asked();
  const { answer } = await admitR9(a);
  assert.deepEqual(answer, { t: "no", error: "not_here" }, "refused before a code is shown");
  assert.equal(a.asked(), before, "nobody asked");
  assert.deepEqual(a.stated(), []);
  const b = await setUp({ root: "alice", mine: "admin", view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "admin" }] });
  assert.equal((await addHere(b, "admin")).error, undefined);
  const { log, done } = await admitR9(b);
  assert.equal(done?.error, undefined, done?.error?.message);
  assert.deepEqual(b.stated(), [`member r9 admin ${gOf(log).slice(0, 6)}`], "an admin gives admin");
});

test("the role at a first admission is the lower of the note and the view: noted an admin, the view's viewer a viewer, the view's member a member", async () => {
  for (const [viewed, said] of [["viewer", "viewer"], ["member", "member"]]) {
    const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: viewed }] });
    assert.equal((await addHere(w, "admin")).error, undefined);
    const { log, done } = await admitR9(w);
    assert.equal(done?.error, undefined, done?.error?.message);
    assert.deepEqual(w.stated(), [`member r9 ${said} ${gOf(log).slice(0, 6)}`], `noted an admin, the view says ${viewed}: a ${said}`);
  }
});

test("a role changed for someone added whose first device has not come: nothing said, nobody asked, the note the new role", async () => {
  // (added here as a member, made an admin here; then on a device that held no note for them)
  for (const first of [true, false]) {
    const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "admin" }] });
    if (first) assert.equal((await addHere(w, "member")).error, undefined);
    const before = w.asked();
    const changed = await w.run(roster(w.inner, "s1", "ws", { member: "r9", role: "admin" }));
    assert.equal(changed.error, undefined, changed.error?.message);
    assert.equal(w.asked(), before, "nobody asked for the change");
    assert.deepEqual(w.stated(), [], "nothing said");
    const { log, done } = await admitR9(w);
    assert.equal(done?.error, undefined, done?.error?.message);
    assert.equal(w.asked() - before, 1, "the person asked once, for the admission");
    assert.deepEqual(w.stated(), [`member r9 admin ${gOf(log).slice(0, 6)}`], `made an admin here (${first ? "added here" : "added elsewhere"}): an admin`);
  }
  const a = await setUp({ root: "alice", mine: "admin", view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "member" }] });
  assert.equal((await addHere(a, "member")).error, undefined);
  const owner = await a.run(roster(a.inner, "s1", "ws", { member: "r9", role: "owner" }));
  assert.equal(owner.error, undefined, owner.error?.message);
  assert.deepEqual((a.inner.data.record("lockAdded", "ws") as { notes: { who: string; role: string }[] }).notes.map((n) => `${n.who} ${n.role}`), ["r9 member"], "an admin makes no owner: the note as it was");
  const { log, done } = await admitR9(a);
  assert.equal(done?.error, undefined, done?.error?.message);
  assert.deepEqual(a.stated(), [`member r9 member ${gOf(log).slice(0, 6)}`], "a member said");
});

test("a note goes as the member is taken out before their first device came", async () => {
  const w = await setUp({ view: [...VIEW, { sub: "r9", email: "r9@x.com", role: "member" }] });
  await addHere(w, "admin");
  assert.deepEqual(notedHere(w), ["r9"]);
  const out = await w.run(roster(w.inner, "s1", "ws", { member: "r9", gone: true }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.deepEqual(notedHere(w), [], "the note gone");
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

/// The new device's side: s1's device (ME) waiting in `ws`, whose list (alice's log the root) does not name s1: given
/// no log, told by station A's refusal it is left out and to ask alice's app (station/src/mesh/serve.ts `leftOf`). It
/// asks with `lock.pair`; alice's app (it signs workspaces' locks, an owner) is dialled, and what it is sent is kept (it
/// answers no: only the hello is looked at here).
async function asking(own: "on" | "none" | "other") {
  const w = await setUp({ root: "alice", mine: "none", own });
  const ALICE_APP = key(6101).hex;
  hooks.lockRefused?.(w.inner, "ws", A, null, { left: { approvers: [ALICE_APP] } });
  w.inner.mesh = () => Effect.succeed({ deviceId: () => ME, lockClaim: () => null, link: () => Effect.fail(CoreError.plainly("mesh", "no station link here")) } as never);
  w.inner.cloudSync.credential = () => Effect.succeed({ credential: "signed-member", issued_at: 1000, expires_at: 4102444800, relay_url: "https://relay.example" });
  const hellos: { workspaces?: { ws: string }[]; log?: Entry[]; personal?: unknown }[] = [];
  const dialled: string[] = [];
  dialer.open = (_inner, id) => Effect.flatMap(Effect.promise(() => pipe()), ([here, there]) => Effect.sync(() => {
    dialled.push(id);
    w.inner.runner.fork(Effect.gen(function* () {
      hellos.push((yield* there.next()) as never);
      yield* there.send({ t: "no", error: "not_here" });
    }));
    return here;
  }));
  /// `lock.pair` asked: its error, if any, once the first hello went or it ended.
  const pair = async () => {
    const was = hellos.length;
    const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.pair", { workspace: "ws" }), catch: (e) => e as CoreError }));
    await w.r.host.time.passUntil(20_000, () => hellos.length > was);
    return { error: out.error, hello: hellos.length > was ? hellos.at(-1)! : null };
  };
  return { ...w, pair, dialled, ALICE_APP };
}

test("the new device whose person has no log of their own: it begins one as it asks, the person asked once for that and not again for the asking, and its hello carries it", async () => {
  const w = await asking("none");
  const before = w.asked();
  const { error, hello } = await w.pair();
  assert.equal(error, undefined, error?.message);
  const personal = w.inner.adb.personal();
  assert.equal(personal.standing("s1"), "member", "a log of s1's own begun, this device on it");
  assert.equal(w.asked() - before, 1, "the person asked once");
  assert.ok(hello !== null, `alice's app dialled (${w.dialled.join(", ")})`);
  assert.deepEqual(hello.workspaces?.map((x) => x.ws), ["ws"], "asking in ws");
  assert.equal(hello.personal, undefined, "not the personal exchange");
  const log = hello.log ?? [];
  assert.equal(log.length > 0 && entryHash(log[0]!), entryHash(personal.entries("s1")[0]!), "its hello carries the log begun");
  assert.equal((log[0]?.body as { sub?: string; device?: { key?: string } } | undefined)?.device?.key, personal.keyId(), "this device's key its genesis's");
});

test("the new device whose person has a log it is not on: nothing asked in the moved workspace, no log begun; once on that log (the personal exchange) it asks there with it, nobody asked", async () => {
  const w = await asking("other");
  const before = w.asked();
  const first = await w.pair();
  assert.ok(first.hello === null || !(first.hello.workspaces ?? []).some((x) => x.ws === "ws"), "not asking in ws");
  const personal = w.inner.adb.personal();
  assert.equal(personal.standing("s1"), "outside", "no log begun");
  assert.equal(w.asked(), before, "nobody asked");
  // (put on the log by a device of theirs on it: the personal exchange, from that device's side)
  const mine = (await w.run(personal.makeKey())).ok!;
  const last = w.elsewhere.chain.at(-1)!;
  // (a new array: a chain once folded is read as it was, personal-lock.ts `checkChain`)
  w.elsewhere.chain = [...w.elsewhere.chain, signed({ v: 1, ws: "person:s1", seq: w.elsewhere.chain.length, prev: stationHash(last), at: T, kind: "device", body: { key: mine, id: ME, label: "this" } } as Omit<StationEntry, "sig">, w.elsewhere.k)];
  w.st.own = w.elsewhere.chain as unknown as Entry[];
  // (as the personal exchange's answer is taken: views/pair.ts `personalProve`)
  const joined = await w.run(personal.joined("s1", w.elsewhere.chain as unknown as Entry[]));
  assert.equal(joined.error, undefined, joined.error?.message);
  assert.equal(personal.standing("s1"), "member", "on the log");
  const asked = w.asked();
  const again = await w.pair();
  assert.equal(again.error, undefined, again.error?.message);
  assert.ok(again.hello !== null, "alice's app dialled");
  assert.deepEqual(again.hello.workspaces?.map((x) => x.ws), ["ws"], "asking in ws now");
  assert.equal(entryHash((again.hello.log ?? [])[0]!), stationHash(w.elsewhere.chain[0]!), "with the log it is on, as it is");
  assert.equal(w.asked(), asked, "nobody asked");
});

test("the new device already on its person's log: no log begun, nobody asked, its hello carries that log", async () => {
  const w = await asking("on");
  const before = w.asked();
  const length = w.inner.adb.personal().entries("s1").length;
  const { error, hello } = await w.pair();
  assert.equal(error, undefined, error?.message);
  assert.ok(hello !== null, "alice's app dialled");
  assert.deepEqual(hello.workspaces?.map((x) => x.ws), ["ws"]);
  assert.equal(entryHash((hello.log ?? [])[0]!), stationHash(w.me.chain[0]!), "the log it is on");
  assert.equal(w.inner.adb.personal().entries("s1").length, length, "nothing signed on it");
  assert.equal(w.asked(), before, "nobody asked");
});
