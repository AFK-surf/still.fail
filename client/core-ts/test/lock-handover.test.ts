// A workspace's chain handed over to its people's own logs by an owner's own app device (views/lock.ts `handOver`,
// src/lock-handover.ts), end to end on a core whose workspace's stations are the station's own code (station/src
// cloud/state.ts `Cloud`, its routes mesh/serve.ts `lockRoute`, `lockPartRoute`: what they take of entries, logs and
// bodies is what a station takes), the chain not moved until the act moves it. Since 2026-11-14 (the lead's: the chain
// as it moved still says what the logs have not, rules/src/lock/state4.mbt `state4_moved`) it says nothing in anyone's
// log and asks nobody: `moved` alone, signed once the stations of the chain say they read it so and every app device
// the chain lets in runs a build that does, and the state in force after it is the chain's list before (held to the
// fourth round's model's `d4Old`, station/test/lock-roster4-model.ts) at the stations and here, every device let in:
// a member with a device that signs and no log of their own, one with only a web page, one whose app device is on the
// chain and not on their log. No station: pending, carried on by calling it again. Refused for anyone but an owner's own
// device with its log pinned; `unknown_call` without the host's flag.
//
// The world: `ws`, its chain this device's genesis (s1 the owner, this device its app; r2 bob an admin, r3 xena a
// member, each with an app device; stations A and B) and each member's `person` binding to their own log. w2, another
// workspace of s1's, lists station D, which takes nothing of `ws`.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { Effect } from "effect";
import { type Entry as StationEntry, LockRefusal, entryHash as stationHash, fold as stationFold } from "../../../station/src/cloud/lock.ts";
import { Cloud, personChainsOf, writeState } from "../../../station/src/cloud/state.ts";
import { wall } from "../../../station/src/ops/fibers.ts";
import { inLock, inLockBringing, lockPartRoute, lockRoute, movedTooOld, refusalOf, sawBuild } from "../../../station/src/mesh/serve.ts";
import { deviceBuildsOf } from "../../../station/src/mesh/device-builds.ts";
import { buildOf } from "../../../station/src/api/oldest.ts";
import { HAND_OVER_FROM } from "../src/lock-handover.ts";
import { MOVED_FROM_BUILD } from "../../../station/src/api/moved-from.ts";
import { type Dev, type Key, Log, bring, dev, ed, signed, viewerOf } from "../../../station/test/lock-moved-world.ts";
import { d4Diff, d4Old } from "../../../station/test/lock-roster4-model.ts";
import { key, signed as simSigned } from "../../../station/test/lock-world-sim.ts";
import type { CoreError } from "../src/error.ts";
import { type Entry, type Signer, canonical, entryHash, next } from "../src/lock.ts";
import { bodyHash } from "../src/lock-moved.ts";
import { Core } from "../src/core.ts";
import { httpError } from "../src/station/requests.ts";
import { HostWire } from "../src/station/wire.ts";
import { hex, utf8 } from "../src/util.ts";
import { ownBuild, setOwnBuild } from "../src/station/oldest.ts";
import { handOver, handOverState, held, inForceOf, lockView, pendingHeld, read } from "../src/views/lock.ts";
import { serveTrusted, tryOne } from "../src/views/pair.ts";
import { grant, pipe, rig, withoutMesh } from "./lock-rig.ts";
import { signIn } from "./helpers.ts";
import { jsonResponse } from "../src/testing.ts";
import { stationLater } from "./station-fixture.ts";

/// The device's clock as each test begins: thirty days past HAND_OVER_FROM, since when chains are handed over by
/// themselves (a genesis of before counts its fourteen days from then, `mayHandOver`).
const T0 = HAND_OVER_FROM! + 30 * 86400;
/// The stations' clock: the core's (each test's rig sets it).
let clock = () => 0;
mock.method(wall, "now", () => clock());

const MINE = 7001;
const seedOf = (n: number) => {
  const s = new Uint8Array(32);
  new DataView(s.buffer).setUint32(28, n);
  return s;
};
const SETTINGS = (keys: unknown) => ({ origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: keys });

type Asked = { at: string; method: string; path: string; body: string };
type Opts = {
  /// More members of the chain: `ready: false` one with an app device and no log bound (r4); `web` one with only a web
  /// page (r5, an admin); `none` one with no device (r6, a member).
  more?: ("notReady" | "web" | "none")[];
  /// s1's own web page on the chain.
  myWeb?: boolean;
  /// s1 an admin (s0 the owner, its genesis signer); this device on the chain with another signer; s1's log not pinned;
  /// s1 a second owner (`second`: s0 the first, its genesis signer, bound to a log of their own as the others).
  mine?: "admin" | "otherKey" | "unpinned" | "second";
  /// Chains handed over by themselves here (`Host.handOverAuto`; off by default: they are all the same, the device's
  /// clock past HAND_OVER_FROM).
  auto?: boolean;
  /// The device's clock before HAND_OVER_FROM (2026-10-06), where chains are not handed over by themselves.
  early?: boolean;
  /// The genesis's `at` (unix seconds; 1000 by default).
  genesisAt?: number;
  /// With `second`: s0 made an admin by s1 after the bindings (the genesis's person no owner any more).
  firstLowered?: boolean;
  /// The host offers `lock.handOver` (by default).
  flag?: boolean;
  /// bob (r2) an owner, not an admin.
  bobOwner?: boolean;
  /// The workspace's members as the cloud's view says them (none by default).
  view?: { sub: string; email: string; role: string }[];
  /// Members whose log no station keeps (their app device never brought it).
  unbrought?: ("r2" | "r3")[];
  /// s1 bound to no log on the chain (with `second`: s0, the first owner, moves it), with a phone on the chain not on
  /// s1's log (`s1Phone`), so that this device binds nothing on the chain before the move (views/lock.ts `bindPerson`).
  unbound?: boolean;
  /// With `unbound` and `second`: s1 has no log of their own at all (apps from before own logs: none kept here nor by a
  /// station, this device holding no key of its own for one), the chain moved by s0 before this device first reads it (a
  /// device reading an unmoved chain begins its person's lock with nobody asked, views/lock.ts `ownLockFor`).
  noLog?: boolean;
  /// So many more members (m0, m1, …), each with an app device and a log of their own bound and brought.
  crowd?: number;
  /// A third station of the workspace, C.
  third?: boolean;
  /// Stations (by name) whose GET /lock does not say they serve `bodies`, `logs` and `builds`, nor their GET
  /// /lock/person `logs` and `builds` (stations from before), and those not reached at all, from the start.
  old?: string[];
  down?: string[];
  /// Stations that serve `bodies`, `logs` and `builds` but do not say they read a moved chain as it moved (`serves`
  /// without `carried`, on GET /lock and GET /lock/person: a station of the build before this one).
  noCarried?: string[];
  /// Stations whose GET /lock is not answered (reached otherwise: GET /lock/person answers), from the start.
  lockDown?: string[];
  /// The build each member's app device on the chain was seen on by every station, by its person ("" none said, null
  /// never seen); every other one seen on `0.1.0` (an unnumbered build, able) as the stations start.
  builds?: Record<string, string | null>;
  /// D, the station of s1's other workspace, says nothing of the devices' builds on GET /lock/person (one from before).
  dOld?: boolean;
};

async function setUp(o: Opts = {}) {
  const g = grant();
  const base = ed();
  // s1's own log: this device on it by its key there (its seed sealed here), no signer said yet (said in the ask)
  const k = key(MINE);
  const myLog = [simSigned({ v: 1, ws: "person:s1", seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub: "s1", device: { key: k.id, id: base.hex, label: "s1's app" } } } as Omit<StationEntry, "sig">, k)];
  const gMe = stationHash(myLog[0]!);
  const bob = new Log("r2"), xena = new Log("r3"), r4 = new Log("r4"), s0 = dev(), first = new Log("s0");
  const A = ed().hex, B = ed().hex, C = ed().hex, D = ed().hex, WEB = ed(), WEB5 = ed();
  const ours = o.third ? [A, B, C] : [A, B];
  const crowd = Array.from({ length: o.crowd ?? 0 }, (_, i) => new Log(`m${i}`));
  let mine: Signer | null = null;
  let now = 0;
  const other = ed();
  const appOf = (sub: string, d: Dev) => ({ id: d.base.hex, sub, kind: "app", label: `${sub}'s app`, sign_key: d.signer.id });
  const r = await rig((signer) => {
    mine = signer;
    const members = [{ sub: "s1", email: "a@x.com", role: o.mine === "admin" ? "admin" : "owner" }, { sub: "r2", email: "b@x.com", role: o.bobOwner ? "owner" : "admin" }, { sub: "r3", email: "c@x.com", role: "member" }];
    const devices: Record<string, unknown>[] = [{ id: base.hex, sub: "s1", kind: "app", label: "s1's app", sign_key: o.mine === "otherKey" ? other.id : signer.id }, appOf("r2", bob.app), appOf("r3", xena.app)];
    if (o.mine === "admin") members.unshift({ sub: "s0", email: "o@x.com", role: "owner" }), devices.unshift(appOf("s0", s0));
    if (o.mine === "second") members.unshift({ sub: "s0", email: "o@x.com", role: "owner" }), devices.unshift(appOf("s0", first.app));
    if (o.more?.includes("notReady")) members.push({ sub: "r4", email: "d@x.com", role: "member" }), devices.push(appOf("r4", r4.app));
    if (o.more?.includes("web")) members.push({ sub: "r5", email: "e@x.com", role: "admin" });
    if (o.more?.includes("none")) members.push({ sub: "r6", email: "f@x.com", role: "member" });
    for (const l of crowd) members.push({ sub: l.sub, email: `${l.sub}@x.com`, role: "member" }), devices.push(appOf(l.sub, l.app));
    const e = next("ws", null, o.genesisAt ?? 1000, "genesis", { owner: members[0]!.sub, ...SETTINGS(g.keys), members, devices, passkeys: [], stations: ours.map((k, i) => ({ key: k, name: "abc"[i]! })), gateways: [] });
    const by = o.mine === "admin" ? s0.signer : o.mine === "second" ? first.app.signer : o.mine === "otherKey" ? other : null;
    return { ws: by === null ? signer.sign(e) : (signed(e as Omit<StationEntry, "sig">, by) as unknown as Entry) };
  }, (host) => {
    // (the device's clock thirty days past HAND_OVER_FROM, T0 below: chains are handed over by themselves from it)
    // (signed in again then: the account's token runs an hour from when it was signed in)
    if (o.early !== true) host.advance(T0 * 1000 - host.nowMs()), signIn(host);
    host.handOverByTests = o.flag !== false;
    host.handOverAuto = o.auto === true;
    now = Math.floor(host.nowMs() / 1000);
    if (o.mine === "unpinned" || o.noLog === true) return;
    host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(myLog)));
    host.storage.set("personal-signer-id", utf8(k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, ours, ours, undefined, [D], o.view === undefined ? {} : { members: o.view });
  clock = () => r.host.nowMs();
  let inner = r.core.inner;
  const signer = mine! as Signer;
  // The chain: the genesis, each member's binding, by their own device; the extras' web page.
  const chain: Entry[] = [r.cloud.chains.get("ws")![0]!];
  const after = (by: Key | Signer, kind: string, body: unknown): Entry => {
    const last = chain[chain.length - 1]!;
    const e = next("ws", { seq: last.seq, hash: entryHash(last), genesis: entryHash(chain[0]!) }, Math.max(last.at, now), kind, body);
    const s = "signBytes" in by ? by.sign(e) : (signed(e as Omit<StationEntry, "sig">, by) as unknown as Entry);
    chain.push(s);
    // (an app device approved on the chain meanwhile: seen by the stations on an able build, as it would be as it asks)
    if (kind === "device" && (body as { kind?: string }).kind === "app") for (const c of made) deviceBuildsOf(c).saw((body as { id: string }).id, 0, Math.floor(clock() / 1000));
    return s;
  };
  const made: Cloud[] = [];
  if (o.unbound !== true) after(o.mine === "otherKey" ? other : signer, "person", { sub: "s1", person: gMe });
  const s1Phone = dev();
  if (o.unbound === true) after(signer, "device", { id: s1Phone.base.hex, sub: "s1", kind: "app", label: "s1's phone", sign_key: s1Phone.signer.id });
  after(bob.app.signer, "person", { sub: "r2", person: bob.genesis });
  after(xena.app.signer, "person", { sub: "r3", person: xena.genesis });
  if (o.mine === "second") after(first.app.signer, "person", { sub: "s0", person: first.genesis });
  for (const l of crowd) after(l.app.signer, "person", { sub: l.sub, person: l.genesis });
  if (o.firstLowered) after(signer, "member", { sub: "s0", email: "o@x.com", role: "admin" });
  if (o.myWeb) after(signer, "device", { id: WEB.hex, sub: "s1", kind: "web", label: "s1's browser", exp: now + 10 * 86400 });
  if (o.more?.includes("web")) after(o.mine === "admin" ? s0.signer : signer, "device", { id: WEB5.hex, sub: "r5", kind: "web", label: "r5's browser", exp: now + 10 * 86400 });
  if (o.noLog === true) after(first.app.signer, "moved", { root: first.genesis });
  r.cloud.chains.set("ws", chain);
  // Stations A and B, the station's own code, the chain pinned and the members' logs heard
  const station = (id: string): Cloud => {
    const data = mkdtempSync(join(tmpdir(), "lock-handover-"));
    writeState(data, { origin: "https://stillfail.test", station: id, workspace: "ws", workspace_name: "W", name: id.slice(0, 4), relay_url: "", relay_urls: [], grant_keys: g.keys, peers: ours.map((p, i) => ({ id: p, name: `s${i}` })), revocations: [] } as never);
    const c = new Cloud(data, false);
    if (o.noLog === true) c.takeLock(chain.slice(0, -1) as unknown as StationEntry[]), c.takeLock(chain as unknown as StationEntry[], null, true);
    else c.takeLock(chain as unknown as StationEntry[]);
    // (each member's log as their app device brought it to the station, POST /lock/person)
    for (const l of [bob, xena, ...(o.mine === "second" ? [first] : []), ...crowd]) if (!o.unbrought?.includes(l.sub as "r2" | "r3")) bring(c, l, false, "ws");
    // (each member's app device on the chain seen asking on the build `builds` says, this one's own aside: it runs this)
    for (const [did, d] of stationFold(chain as unknown as StationEntry[], null).devices) {
      if (d.kind !== "app" || did === base.hex) continue;
      const b = o.builds?.[d.sub] === undefined ? "0.1.0" : o.builds[d.sub]!;
      if (b !== null) deviceBuildsOf(c).saw(did, buildOf(b), Math.floor(clock() / 1000));
    }
    made.push(c);
    return c;
  };
  const stations: { A: Cloud; B: Cloud; C?: Cloud } = { A: station(A), B: station(B), ...(o.third ? { C: station(C) } : {}) };
  const nameOf = (id: string) => (id === A ? "A" : id === B ? "B" : id === C ? "C" : id === D ? "D" : null);
  const st = { silent: false, down: new Set<string>(o.down ?? []), old: new Set<string>(o.old ?? []), noCarried: new Set<string>(o.noCarried ?? []), lockDown: new Set<string>(o.lockDown ?? []), dOld: o.dOld === true, dSince: Math.floor(clock() / 1000), asked: [] as Asked[], hook: null as null | (() => void) };
  const viewer = viewerOf("s1", { base }, "owner", "ws");
  const route = (c: Cloud, method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (st.silent && method === "POST") return Effect.never;
    const [p, q] = path.split("?") as [string, string | undefined];
    const buf = Buffer.from(body === null || body === undefined ? "" : JSON.stringify(body));
    const [status, said] = p === "/lock" ? lockRoute(c, method, q ? [...new URLSearchParams(q)] : [], buf, viewer as never) : lockPartRoute(c, p.slice("/lock/".length), method, buf, viewer as never);
    // (a station from before: its rules know no `moved`, and it serves none of what a moved chain is made of)
    const from = Object.entries(stations).find(([, x]) => x === c)?.[0] ?? "";
    const out = p === "/lock" && st.old.has(from) && status === 200 ? { ...(said as object), serves: ((said as { serves?: string[] }).serves ?? []).filter((x) => x !== "bodies" && x !== "logs" && x !== "builds" && x !== "carried") }
      : p === "/lock" && st.noCarried.has(from) && status === 200 ? { ...(said as object), serves: ((said as { serves?: string[] }).serves ?? []).filter((x) => x !== "carried") }
      : p === "/lock/person" && method === "GET" && (st.old.has(from) || st.noCarried.has(from)) ? { chains: (said as { chains: unknown }).chains, ...(st.old.has(from) ? {} : { serves: ["logs", "builds"] }) }
      : said;
    // (the first time statements were taken: what the test changes before the `moved`)
    if (status === 200 && p === "/lock/person" && Array.isArray((body as { bodies?: unknown })?.bodies) && st.hook) {
      const h = st.hook;
      st.hook = null;
      h();
    }
    return status === 200 ? Effect.succeed(out) : Effect.fail(httpError(status, out));
  };
  // (this device's mesh, and its requests to the workspace's stations, on a core as it starts: `restart`)
  const install = (inner: typeof r.core.inner) => {
    inner.mesh = () => withoutMesh(base.hex);
    const original = inner.stations.requests.call.bind(inner.stations.requests);
    inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
      const [ws, id] = addr.toString().split("/");
      const n = id === undefined ? null : nameOf(id);
      if (path.startsWith("/lock") && n !== null && (n === "D" || (stations as Record<string, Cloud | undefined>)[n] !== undefined)) {
        const at = `${ws}/${n}`;
        st.asked.push({ at, method, path, body: JSON.stringify(body ?? null) });
        // (D, w2's: its GET /lock/person, keeping no log of s1's, says it serves logs and the devices' builds unless `dOld`)
        if ((id === D || ws !== "ws") && method === "GET" && path === "/lock/person") return Effect.succeed(st.dOld ? { chains: [] } : { chains: [], serves: ["logs", "builds"], builds: { since: st.dSince, devices: {} } });
        if (id === D || ws !== "ws") return method === "POST" ? Effect.succeed({}) : Effect.fail(httpError(404, { error: "no route" }));
        if (st.down.has(at.slice(-1)) || (st.lockDown.has(n) && method === "GET" && /^\/lock(\?|$)/.test(path))) return Effect.fail(httpError(503, { error: "not reached" }));
        return route((stations as Record<string, Cloud | undefined>)[n]!, method, path, body);
      }
      return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
    }) as typeof inner.stations.requests.call;
  };
  install(inner);
  /// The app started anew on the same host (test/vault.test.ts's): its database and secure storage as they were,
  /// nothing of the run before in memory; the lock is read as the sync reads it as it starts.
  const restart = async () => {
    await Effect.runPromise(inner.data.written);
    r.core.close();
    r.host.takeEmitted();
    r.core = await Core.create(r.host, { clock: r.host.time.clock, sample: 0, wire: () => new HostWire(r.host) });
    inner = r.core.inner;
    install(inner);
    await r.host.time.pass(500);
  };
  const run = async <X>(e: Effect.Effect<X, any>): Promise<{ ok?: X; error?: CoreError }> => {
    let out: { ok?: X; error?: CoreError } | null = null;
    inner.runner.fork(Effect.match(e, { onSuccess: (ok) => void (out = { ok }), onFailure: (error) => void (out = { error }) }));
    await r.host.time.passUntil(30_000, () => out !== null);
    assert.ok(out !== null, "no answer");
    await r.host.time.pass(100);
    return out;
  };
  await run(inner.adb.personal().refresh("s1"));
  await run(read(inner, "ws"));
  // (where chains are handed over by themselves and nothing holds it back, it may have moved as it was read)
  assert.ok((held(inner, "ws")?.entries.length ?? 0) >= chain.length, "the chain held");
  const asked = () => r.host.secureAsked.length;
  /// What this device's own log says past what it said before: each statement's kind and whom, its body's `prev`.
  const said = () => inner.adb.personal().entries("s1").slice(myLog.length).filter((e) => e.kind === "ws").map((e) => {
    const h = (e.body as { h: string }).h;
    const b = ((inner.data.record("lockBodies", "ws") as { bodies?: Record<string, unknown>[] } | null)?.bodies ?? []).find((x) => bodyHash(x) === h);
    return b === undefined ? { what: "ws (no body)", prev: null, h } : { what: `${b.kind} ${b.sub ?? (nameOf(String(b.key)) ?? "")}${b.role ? ` ${b.role}` : ""}`.trim(), prev: b.prev as string | null, h };
  });
  const hand = () => run(handOver(inner, "s1", "ws"));
  /// The chain's list as the model's D4 has it, by the station's own fold, rooted in s1's log.
  const d4Chain = (es: readonly Entry[]) => d4Old(stationFold(es as unknown as StationEntry[], null), gMe, Math.floor(r.host.nowMs() / 1000));
  /// Someone's first app device (`d`, with the log of their own `log`) asking this device as `sub`, the code shown here
  /// typed on it: the hello's answer and the proof's.
  const firstApp = async (sub: string, log: Log) => {
    const prompts = await r.watch({ topic: "lockPrompts" });
    const [trusted, phone] = await pipe();
    const id = log.app.base.hex;
    inner.runner.fork(serveTrusted(inner, id, base.hex, trusted));
    const first = await run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", id, sub) }], kind: "app", label: `${sub}'s app`, sign_key: log.app.signer.id, log: log.entries }), phone.next()));
    const answer = first.ok as { t: string };
    if (answer.t !== "code") return { answer, done: null };
    const code = ((await prompts()).pairing as { device: string; code: string }[]).find((p) => p.device === id)!.code;
    return { answer, done: await run(tryOne(inner, { id: base.hex, d: phone, workspaces: ["ws"] }, id, code)) };
  };
  /// An ask of the person's own lock's key for something else: grants signed (none: the ask alone).
  const askGrant = () => run(inner.adb.personal().signGrants("s1", [], "a grant"));
  return { r, get inner() { return inner; }, s1Phone, restart, first, signer, chain, after, stations, st, asked, said, hand, run, d4Chain, gMe, bob, xena, r4, crowd, base, WEB, WEB5, A, B, C, D, viewer, firstApp, g, askGrant, now: () => now };
}

/// A second app device of `log`'s person (`d`) as the product puts it on their own log: a device entry signed by the
/// first device there (personal-lock.ts `#addApproved`), with the key it signs the chain with.
const onLog = (log: Log, d: Dev, label: string) => log.add("device", { key: d.key.id, id: d.base.hex, label, sign_key: d.signer.id });

/// The core's state in force as the model's D4 has one (test/lock-moved-check.ts's reading).
function d4Core(inner: any) {
  const f = inForceOf(inner, "ws");
  const devs = (sub: string, kind: string) => [...f.f.devices.values()].filter((d: any) => d.sub === sub && d.kind === kind);
  return {
    on: f.said === "on" ? "on" : f.said,
    settings: f.settings ? canonical(f.settings) : "-",
    members: new Map([...f.f.members].map(([sub, m]) => [sub, { role: m.role, email: m.email, lock: f.f.persons.get(sub) ?? "none", apps: devs(sub, "app").map((d: any) => d.sign_key).sort(), webs: devs(sub, "web").map((d: any) => d.id).sort() }])),
    stations: [...f.f.stations.keys()].sort(),
  };
}
/// A station's state as the model's D4 has one (its own `locked`), rooted in `root`.
const d4Station = (c: Cloud, root: string, now: number) => d4Old(c.locked(null)!.state!, root, now);
const admitted = (sub: string, d: { base: Key }, role: string) => ({ viewer: viewerOf(sub, d, role, "ws"), exp: 4102444800, iat: 0, sid: "s" });


/// A device of `sub`'s (`k`) at a station's hello, as the mesh makes it: in, or refused with what the refusal tells it
/// (station/src/mesh/serve.ts `refusalOf`: left out, whom to ask, whether the list names an app of `sub`'s).
const hello = (c: Cloud, sub: string, k: Key, role: string): { in: boolean; left?: { approvers: string[]; apps?: boolean } } => {
  const v = viewerOf(sub, { base: k }, role, "ws");
  const said = { lock: { device: k.hex, proof: v.lockDevice.proof } };
  try {
    inLockBringing(c, { viewer: v, exp: 4102444800, iat: 0, sid: "" } as never, role, v.device, said);
    return { in: true };
  } catch (e) {
    if (!(e instanceof LockRefusal)) throw e;
    return { in: false, left: (refusalOf(c, said, v.device, e, undefined, sub) as { left?: { approvers: string[]; apps?: boolean } }).left };
  }
};

/// Nothing said in this device's own log, nobody asked: what every handover here holds.
const silent = (w: Awaited<ReturnType<typeof setUp>>) => {
  assert.equal(w.asked(), 0, "nobody asked");
  assert.deepEqual(w.said(), [], "nothing said in its log");
  assert.deepEqual(w.inner.adb.personal().entries("s1").filter((e) => e.kind === "web"), [], "no web page said in its log");
};
const movedAt = (w: Awaited<ReturnType<typeof setUp>>) => Object.values(w.stations).map((c) => c.chain(null)?.state?.moved ?? null);
/// Each of the stations brought the chain as it stands here (as another keeper's), and the person logs of `logs`.
const takeChain = (w: Awaited<ReturnType<typeof setUp>>, logs: Log[] = []) => {
  for (const c of Object.values(w.stations)) {
    c.takeLock([...w.chain] as unknown as StationEntry[]);
    for (const l of logs) bring(c, l, false, "ws");
  }
};
/// The chain's list before, at A, B and here, every one of `devices` let in by A.
const asTheChain = async (w: Awaited<ReturnType<typeof setUp>>, before: ReturnType<Awaited<ReturnType<typeof setUp>>["d4Chain"]>, devices: [string, { base: Key }, string][]) => {
  await w.run(read(w.inner, "ws"));
  assert.equal(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved", "the chain held moved");
  const now = Math.floor(w.r.host.nowMs() / 1000);
  assert.deepEqual(d4Diff(before, d4Core(w.inner)), [], "the state in force here is the chain's list before (the model's d4Old)");
  for (const [n, c] of Object.entries(w.stations)) assert.deepEqual(d4Diff(before, d4Station(c, w.gMe, now)), [], `${n}'s state is the chain's list before`);
  for (const [sub, d, role] of devices) {
    const a = admitted(sub, d, role);
    assert.equal(inLock(w.stations.A, a as never, role, a.viewer.device).viewer.role, role, `${sub}'s device ${d.base.hex.slice(0, 6)} let in by A`);
  }
};

test("an owner, an admin, a member, two stations: moved, nothing said, nobody asked, the chain's list in force at A, B and here, every device let in", async () => {
  const w = await setUp({ early: true });
  const before = w.d4Chain(w.chain);
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(out.ok, null, "handed over");
  silent(w);
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe]);
  for (const c of Object.values(w.stations)) assert.equal(c.bodies(null).all().size, 0, "no statement, no body");
  // (s1's own app: on its log by its key there, no signer said there yet; the chain's names it with its signer)
  await asTheChain(w, before, [["s1", { base: w.base }, "owner"], ["r2", w.bob.app, "admin"], ["r3", w.xena.app, "member"]]);
  const again = await w.hand();
  assert.equal(again.error, undefined);
  assert.equal(again.ok, null);
  silent(w);
});

test("a member with a device that signs and no log of their own: not waited for, in force by the chain unbound, their device let in", async () => {
  const w = await setUp({ early: true, more: ["notReady"] });
  const before = w.d4Chain(w.chain);
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  silent(w);
  await asTheChain(w, before, [["r4", w.r4.app, "member"]]);
  assert.equal(inForceOf(w.inner, "ws").f.persons.has("r4"), false, "bound to no log");
});

test("a member with only a web page and one with no device: in force by the chain, the page let in until its exp there", async () => {
  const w = await setUp({ early: true, more: ["web", "none"] });
  const before = w.d4Chain(w.chain);
  assert.equal((await w.hand()).error, undefined);
  silent(w);
  await asTheChain(w, before, [["r5", { base: w.WEB5 }, "admin"]]);
  assert.deepEqual([...inForceOf(w.inner, "ws").f.members.keys()].sort(), ["r2", "r3", "r5", "r6", "s1"]);
  w.r.host.advance((10 * DAY + 60) * 1000);
  const page = admitted("r5", { base: w.WEB5 }, "admin");
  assert.throws(() => inLock(w.stations.A, page as never, "admin", page.viewer.device), "out at its exp");
});

test("the owner's own web page on the chain: let in after, nothing said on their log", async () => {
  const w = await setUp({ early: true, myWeb: true });
  assert.equal((await w.hand()).error, undefined);
  silent(w);
  const page = admitted("s1", { base: w.WEB }, "owner");
  assert.equal(inLock(w.stations.A, page as never, "owner", page.viewer.device).viewer.role, "owner", "let in by A");
});

test("no station reachable: the moved pending; a station back and handOver again: moved, nobody asked", async () => {
  const w = await setUp({ early: true });
  w.st.silent = true;
  const out = await w.hand();
  assert.equal(out.error, undefined, out.error?.message);
  assert.ok((out.ok as { pending?: unknown } | null)?.pending, `pending: ${JSON.stringify(out.ok)}`);
  assert.deepEqual(movedAt(w), [null, null], "no moved at a station");
  w.st.silent = false;
  const again = await w.hand();
  assert.equal(again.error, undefined, again.error?.message);
  assert.equal(again.ok, null, `handed over: ${JSON.stringify(again.ok)}`);
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe]);
  silent(w);
});

test("a member bound to a log with a second app device on the chain and not on that log: not waited for, both in force, the phone let in by the chain's signer", async () => {
  const w = await setUp({ early: true });
  const phone = dev();
  w.after(w.bob.app.signer, "device", { id: phone.base.hex, sub: "r2", kind: "app", label: "bob's phone", sign_key: phone.signer.id });
  takeChain(w);
  const before = w.d4Chain(w.chain);
  assert.equal((await w.hand()).error, undefined);
  silent(w);
  await asTheChain(w, before, [["r2", phone, "admin"]]);
  assert.deepEqual(d4Core(w.inner).members.get("r2")?.apps, [w.bob.app.signer.id, phone.signer.id].sort(), "both of bob's apps in force here");
  assert.equal(w.stations.A.locked(null)?.state?.devices.get(phone.base.hex)?.by, "chain", "the phone by the chain as it moved");
});

test("a member bound to a log no station keeps: held back (it would drop their devices), nothing said, nobody asked; once a station keeps it, handed over", async () => {
  const w = await setUp({ early: true, unbrought: ["r2"] });
  const out = await w.hand();
  assert.equal(out.error?.code, "lock_not_ready", out.error?.message);
  assert.equal(out.error?.message, TITLE, "in the page's words of an upgrade not done, nothing named");
  silent(w);
  assert.deepEqual(movedAt(w), [null, null]);
  bring(w.stations.B, w.bob, false, "ws");
  const done = await w.hand();
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe);
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(d4Core(w.inner).members.get("r2")?.apps, [w.bob.app.signer.id], "bob's app in force here");
});

test("a device approved on the chain just before the moved: worked out in the turn, in force after it", async () => {
  const w = await setUp({ early: true });
  const phone = dev();
  w.after(w.bob.app.signer, "device", { id: phone.base.hex, sub: "r2", kind: "app", label: "bob's phone", sign_key: phone.signer.id });
  takeChain(w);
  await w.run(read(w.inner, "ws"));
  assert.equal((await w.hand()).error, undefined);
  assert.equal(w.stations.A.chain(null)?.state?.seq, w.chain.length, "the moved after bob's device");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(d4Core(w.inner).members.get("r2")?.apps, [w.bob.app.signer.id, phone.signer.id].sort());
});

for (const mine of ["admin", "otherKey", "unpinned"] as const) {
  test(`refused, nobody asked, nothing said: ${mine === "admin" ? "not an owner" : mine === "otherKey" ? "not this person's own device by its signer" : "the person's log not pinned"}`, async () => {
    const w = await setUp({ early: true, mine });
    const out = await w.hand();
    assert.equal(out.error?.code, "forbidden", out.error?.message);
    assert.equal(w.asked(), 0);
    assert.equal(w.inner.adb.personal().entries("s1").filter((e) => e.kind === "ws").length, 0);
    assert.equal(w.stations.A.chain(null)?.state?.moved, undefined);
  });
}

test("without the host's flag, the device's clock before HAND_OVER_FROM: lock.handOver is no call", async () => {
  const w = await setUp({ flag: false, early: true });
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.handOver", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(out.error?.code, "unknown_call", out.error?.message);
  assert.equal(w.asked(), 0);
  const on = await setUp({ early: true });
  const ok = await on.run(Effect.tryPromise({ try: () => on.r.ask("lock.handOver", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(ok.error, undefined, ok.error?.message);
  assert.equal(on.stations.A.chain(null)?.state?.moved, on.gMe, "with it: handed over");
});

// An app's own host, which says neither `handOverByTests` nor `handOverAuto` (the hold of 2026-11-14 taken out, what the
// locks' rounds showed a moved workspace doing wrong mended): past HAND_OVER_FROM its chain is handed over by itself as
// the lock is read, nothing said in anyone's log and nobody asked.
test("on a host not made for tests, past HAND_OVER_FROM: handed over by itself as the lock is read, nothing said, nobody asked", async () => {
  const w = await setUp({ flag: false });
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved, nobody calling lock.handOver");
  assert.deepEqual(w.said(), [], "nothing said");
  assert.equal(w.asked(), 0, "nobody asked");
  assert.equal(handOverState(w.inner, "ws"), null, "moved");
});

// A member the chain named unbound, after the move (what an unbound member can do: the lead, 2026-11-14): their first
// app device with a log of its own asks; an owner's device shows the code and says `member` with that log, in the
// role the state gives them (the chain's), one ask of the owner's; they are bound to that log, and what the chain
// carried of theirs stays (it bound them to none: `carry_of`), their web page too until its exp.
test("a member the chain named with only a web page, after the move: their first app device asks, this owner's device shows the code, they come in bound to its log with the chain's role, their web page still in", async () => {
  const view = [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "r2", email: "b@x.com", role: "admin" }, { sub: "r3", email: "c@x.com", role: "member" }, { sub: "r5", email: "e@x.com", role: "admin" }];
  const w = await setUp({ early: true, more: ["web"], view });
  assert.equal((await w.hand()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.equal(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved");
  const r5 = new Log("r5");
  for (const c of Object.values(w.stations)) bring(c, r5, false, "ws");
  const { answer, done } = await w.firstApp("r5", r5);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws"] }, "a code shown");
  assert.equal(done?.error, undefined, done?.error?.message);
  assert.equal(w.asked(), 1, "the owner asked once, for the admit");
  assert.deepEqual(w.said().map((x) => x.what), ["member.remove r5", "member r5 admin"], "said with the role the state gives them");
  await w.run(read(w.inner, "ws"));
  const f = inForceOf(w.inner, "ws").f;
  assert.equal(f.members.get("r5")?.role, "admin", "r5 an admin in force here");
  assert.equal(f.persons.get("r5"), r5.genesis, "bound to the log their app brought");
  const app = admitted("r5", r5.app, "admin");
  assert.equal(inLock(w.stations.A, app as never, "admin", app.viewer.device).viewer.role, "admin", "their app let in by A as an admin");
  const page = admitted("r5", { base: w.WEB5 }, "admin");
  assert.equal(inLock(w.stations.A, page as never, "admin", page.viewer.device).viewer.role, "admin", "their web page still in");
});

/// The workspace's stations meeting: each given what the other keeps of the chain (as another keeper's, so the fork
/// choice decides), of the person logs and of the bodies.
function meet(a: Cloud, b: Cloud) {
  for (const [x, y] of [[a, b], [b, a]] as const) for (const [g, es] of personChainsOf(x).every()) personChainsOf(y).keep(g, es, "ws");
  const ka = a.lockKept(null), kb = b.lockKept(null);
  a.keepLock(kb, null, true);
  b.keepLock(ka, null, true);
  const ba = [...a.bodies(null).all().values()], bb = [...b.bodies(null).all().values()];
  a.takeBodies(null, bb);
  b.takeBodies(null, ba);
}

for (const wins of ["bob", "this device"] as const) {
  test(`two owners hand over at once, each at a station the other's does not reach, then the stations meet: one moved stands (${wins}'s, by the fork choice), one chain and one state in force everywhere, the list the chain had`, async () => {
    const w = await setUp({ early: true, bobOwner: true });
    const [a, b] = [w.stations.A, w.stations.B];
    const phone = dev();
    const head = w.chain.at(-1)!;
    const on = (parent: Entry, by: Key, kind: string, body: unknown): Entry => signed(next("ws", { seq: parent.seq, hash: entryHash(parent), genesis: entryHash(w.chain[0]!) }, Math.max(parent.at, w.now()), kind, body) as Omit<StationEntry, "sig">, by) as unknown as Entry;
    const xenas = on(head, w.xena.app.signer, "device", { id: phone.base.hex, sub: "r3", kind: "app", label: "xena's phone", sign_key: phone.signer.id });
    onLog(w.xena, phone, "xena's phone");
    for (const c of [a, b]) bring(c, w.xena, false, "ws");
    for (const c of [a, b]) deviceBuildsOf(c).saw(phone.base.hex, 0, Math.floor(w.r.host.nowMs() / 1000));
    if (wins === "bob") a.takeLock([...w.chain, xenas] as unknown as StationEntry[]);
    // bob's app hands over at B, which this device does not reach: its `moved` alone
    w.st.down.add("B");
    const bobsAt = wins === "this device" ? on(xenas, w.bob.app.signer, "moved", { root: w.bob.genesis }) : on(head, w.bob.app.signer, "moved", { root: w.bob.genesis });
    b.takeLock([...w.chain, ...(wins === "this device" ? [xenas] : []), bobsAt] as unknown as StationEntry[]);
    assert.equal(b.chain(null)?.state?.moved, w.bob.genesis, "B moved to bob's log");
    const out = await w.hand();
    assert.equal(out.error, undefined, out.error?.message);
    assert.equal(out.ok, null, `handed over at A: ${JSON.stringify(out.ok)}`);
    assert.equal(a.chain(null)?.state?.moved, w.gMe, "A moved to s1's log");
    meet(a, b);
    w.st.down.clear();
    for (let n = 0; n < 3; n++) {
      await w.run(read(w.inner, "ws"));
      await w.run(w.inner.adb.personal().refresh("s1"));
    }
    const root = wins === "bob" ? w.bob.genesis : w.gMe;
    const list = w.d4Chain([...w.chain, xenas]);
    const nowS = Math.floor(w.r.host.nowMs() / 1000);
    // (rooted in bob's log, s1 is an owner by the chain as it moved, bound to their log as it bound them; rooted in
    // s1's, bob too)
    for (const [n, c] of [["A", a], ["B", b]] as const) {
      assert.equal(c.chain(null)?.state?.moved, root, `${n} goes by ${wins}'s moved`);
      assert.deepEqual(d4Diff(list, d4Station(c, root, nowS)), [], `${n}'s state in force is the list the chain had`);
    }
    assert.equal(stationHash(a.lockAfter(-1).at(-1)!), stationHash(b.lockAfter(-1).at(-1)!), "one chain: the same head at both");
    assert.equal(inForceOf(w.inner, "ws").root, root);
    for (const [sub, d, role] of [["s1", { base: w.base }, "owner"], ["r2", w.bob.app, "owner"], ["r3", w.xena.app, "member"]] as const) {
      const x = admitted(sub, d, role);
      for (const c of [a, b]) assert.equal(inLock(c, x as never, role, x.viewer.device).viewer.role, role, `${sub}'s device let in`);
    }
    const mine = (c: Cloud) => c.lockKept(null).filter((e) => e.kind === "moved" && e.sig.key === w.signer.id).length;
    assert.deepEqual([mine(a), mine(b)], [1, 1], "this device's moved signed once");
    assert.ok(!pendingHeld(w.inner, "ws").some((x) => x.entry.kind === "moved"), "no moved pending here");
    silent(w);
    if (wins === "bob") {
      const off = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
      assert.equal(off.error?.code, "lock_root_only", off.error?.message);
    }
  });
}

// Handed over by itself (views/lock.ts `handsOver`, `movedBySelf`): nobody calls `lock.handOver` and nobody is asked;
// the `moved` is signed with no key in hand as the lock is held, once nothing holds it back. On every host from
// HAND_OVER_FROM (the device's clock here past it, no `handOverAuto`): what holds a workspace back is what uses it.
const DAY = 86400;

// No app device but the one that moves the chain holds a handover back (the user, 2026-11-14: a phone of his own he no
// longer used held his workspace for seven days, nothing saying why; 「用户要是有个设备离线不用了要等 7 天？」): one on a
// build under MOVED_FROM_BUILD, or never seen, is told to update by a station of the moved workspace as it next asks
// (station/src/mesh/serve.ts `movedTooOld`). Nor does a member with only a web page; for now more than 200 members
// bound to a log still hold one back.
/// A member's app device asking every station of `ws` with the build `build` (the station's own code: admitted by its
/// lock, its build kept by its id there, serve.ts `sawBuild`).
const asks = (w: Awaited<ReturnType<typeof setUp>>, sub: string, d: { base: Key }, role: string, build: string) => {
  for (const c of Object.values(w.stations)) {
    const a = admitted(sub, d, role);
    sawBuild(c, inLock(c, a as never, role, a.viewer.device).viewer, { "stillfail-build": build });
  }
};
const OLD = MOVED_FROM_BUILD - 1;

test("on: the genesis's person's device hands over by itself as the lock is read, nobody asked, the chain's list in force", async () => {
  const w = await setUp();
  const before = w.d4Chain(w.chain);
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved, nobody calling lock.handOver");
  silent(w);
  assert.equal(handOverState(w.inner, "ws"), null, "moved");
  await asTheChain(w, before, [["r2", w.bob.app, "admin"]]);
});

test("an app device seen on a build under MOVED_FROM_BUILD today: not waited for, moved by itself; that device is told to update at the workspace's stations, and is in once it has", async () => {
  const w = await setUp({ builds: { r2: `0.1.${OLD}` } });
  assert.equal(handOverState(w.inner, "ws"), null, "nothing holds it back");
  assert.equal(lockView(w.inner, "ws").upgrade, undefined, "no line");
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved, the device on the old build not waited for");
  for (const c of Object.values(w.stations)) {
    const a = admitted("r2", w.bob.app, "admin");
    assert.equal(movedTooOld(c, a.viewer as never, OLD), true, "told to update there");
    assert.equal(movedTooOld(c, a.viewer as never, MOVED_FROM_BUILD), false, "in once it has");
  }
  silent(w);
});

// The device that moves the chain is held to the build it says to the stations (views/lock.ts `heldBack`; the lead,
// 2026-11-14): on a release under MOVED_FROM_BUILD it moves nothing, as a
// station of a moved workspace would tell it to update the moment it did (serve.ts `movedTooOld`). Every other app
// device of the chain on an able build here, so this device's own build is all that holds it.
test("this device on a release under MOVED_FROM_BUILD, every other device able: nothing moved, lock.handOver waits; on MOVED_FROM_BUILD: moved by itself", async () => {
  const was = ownBuild();
  try {
    setOwnBuild(`0.1.${OLD}`);
    const w = await setUp();
    assert.deepEqual(handOverState(w.inner, "ws"), { held: ["own build"] });
    assert.equal(lockView(w.inner, "ws").upgrade, undefined, "no line");
    await w.run(read(w.inner, "ws"));
    await w.run(read(w.inner, "ws"));
    assert.deepEqual(movedAt(w), [null, null], "nothing moved");
    const call = await w.hand();
    assert.equal(call.error?.code, "lock_not_ready", "lock.handOver answered as a handover waiting, by tests too");
    setOwnBuild(`0.1.${MOVED_FROM_BUILD}`);
    await w.run(read(w.inner, "ws"));
    await w.run(read(w.inner, "ws"));
    assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved");
    silent(w);
  } finally {
    setOwnBuild(was);
  }
});

test("an app device no station has seen (one not used any more): not waited for, moved at once; it comes back on a build under MOVED_FROM_BUILD: told to update there", async () => {
  const w = await setUp({ builds: { r3: null } });
  assert.equal(handOverState(w.inner, "ws"), null, "nothing holds it back");
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved with no day waited");
  for (const c of Object.values(w.stations)) {
    const a = admitted("r3", w.xena.app, "member");
    assert.equal(movedTooOld(c, a.viewer as never, OLD), true, "too old for the moved workspace");
    assert.equal(movedTooOld(c, a.viewer as never, MOVED_FROM_BUILD), false);
  }
  silent(w);
});

test("a web page that is the only device not able (it said no build): not waited for, moved", async () => {
  const w = await setUp({ myWeb: true });
  for (const c of Object.values(w.stations)) deviceBuildsOf(c).saw(w.WEB.hex, null, Math.floor(w.r.host.nowMs() / 1000));
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved");
});

test("a station of another workspace of theirs that says nothing of builds: not waited for (nothing is written in their log), moved", async () => {
  const w = await setUp({ dOld: true });
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved");
  silent(w);
});

test("for now, 201 members bound to a log: not handed over by itself, no line, nothing said", async () => {
  const w = await setUp({ crowd: 198 });
  assert.deepEqual(handOverState(w.inner, "ws"), { held: ["members"] });
  assert.equal(lockView(w.inner, "ws").upgrade, undefined, "no line");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [null, null]);
  silent(w);
});

// A member with only a web page holds nothing back (the owner, 2026-11-13: 「开了安全模式那就需要 app」, web pages not
// waited for; 2026-11-14: 无感迁移): their page is carried by the chain as it moved until its `exp` (rules `carry_of`),
// nothing said to anyone before or after, and nothing on the owner's page.
test("a member with only a web page: handed over by itself, nobody asked, nothing said to anyone; the page let in by the chain until its exp, then out at both stations, told it names no app of theirs", async () => {
  const w = await setUp({ more: ["web"] });
  assert.equal(handOverState(w.inner, "ws"), null, "nothing holds it back");
  const before = w.d4Chain(w.chain);
  const v = lockView(w.inner, "ws") as Record<string, any>;
  assert.equal(v.upgrade, undefined, "no line");
  assert.deepEqual([v.appText, ...v.members.map((m: Record<string, unknown>) => m.appText)].filter((x) => x !== undefined), [], "nothing said of the member before");
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved");
  silent(w);
  await asTheChain(w, before, [["r5", { base: w.WEB5 }, "admin"]]);
  w.r.host.advance((10 * DAY + 60) * 1000);
  for (const [n, c] of Object.entries(w.stations)) {
    const was = hello(c, "r5", w.WEB5, "admin");
    assert.equal(was.in, false, `out at its exp at ${n}`);
    assert.equal(was.left?.apps, false, `${n} tells the page the list names no app of r5's (so it asks nobody: views/lock.ts \`needsAppIn\`)`);
  }
});

// What the move leaves a member with only a web page to do, once that page ran out (the owner, 2026-11-14: 「开了安全模式那
// 就需要 app」): their first app comes in as a newcomer's, an owner's device showing the code (the owner's one ask), and
// approves their page on their own log (their one ask, an entry of their log: personal-lock.ts `web`), which lets it in
// again at both stations. Nothing else is asked of anyone.
test("a member with only a web page, moved by itself, the page run out: their first app comes in by the owner's one ask, then approves the page by theirs, and it is in again at both stations", async () => {
  const view = [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "r2", email: "b@x.com", role: "admin" }, { sub: "r3", email: "c@x.com", role: "member" }, { sub: "r5", email: "e@x.com", role: "admin" }];
  const w = await setUp({ more: ["web"], view });
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved by itself");
  silent(w);
  w.r.host.advance((10 * DAY + 60) * 1000);
  for (const c of Object.values(w.stations)) assert.equal(hello(c, "r5", w.WEB5, "admin").left?.apps, false, "run out, nobody to approve it there");
  const r5 = new Log("r5");
  for (const c of Object.values(w.stations)) bring(c, r5, false, "ws");
  const { answer, done } = await w.firstApp("r5", r5);
  assert.deepEqual(answer, { t: "code", workspaces: ["ws"] }, "a code shown on the owner's device");
  assert.equal(done?.error, undefined, done?.error?.message);
  assert.equal(w.asked(), 1, "the owner asked once");
  const app = admitted("r5", r5.app, "admin");
  assert.equal(inLock(w.stations.A, app as never, "admin", app.viewer.device).viewer.role, "admin", "their app in");
  const theirs = r5.entries.length;
  const at = Math.floor(w.r.host.nowMs() / 1000);
  r5.add("web", { id: w.WEB5.hex, label: "r5's browser", exp: at + 10 * DAY }, r5.app.key, at);
  assert.equal(r5.entries.length - theirs, 1, "their one ask: one entry on their log");
  for (const [n, c] of Object.entries(w.stations)) {
    bring(c, r5, false, "ws");
    assert.equal(hello(c, "r5", w.WEB5, "admin").in, true, `the page in again at ${n}`);
  }
  assert.equal(w.asked(), 1, "nothing more asked of the owner");
});

test("the switch off (the device's clock before HAND_OVER_FROM): nothing moved", async () => {
  const w = await setUp({ early: true });
  assert.equal(handOverState(w.inner, "ws"), null, "not this device's to hand over by itself");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [null, null]);
});

test("another owner's device: not before 14 days from the genesis, then by itself", async () => {
  const w = await setUp({ mine: "second", genesisAt: T0 - 13 * DAY });
  assert.equal(handOverState(w.inner, "ws"), null, "the first owner's yet");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [null, null], "nothing before 14 days");
  w.r.host.advance((DAY + 60) * 1000);
  assert.deepEqual(handOverState(w.inner, "ws"), { moving: true });
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved to s1's log");
  silent(w);
});

test("another owner's device at once where the genesis's person is no owner any more", async () => {
  const w = await setUp({ mine: "second", genesisAt: T0 - DAY, firstLowered: true });
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe]);
});

test("a workspace of 100 members and 3 stations handed over by itself: nothing said, the chain's list in force at each station and here", async () => {
  const w = await setUp({ crowd: 100, third: true });
  const before = w.d4Chain(w.chain);
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe, w.gMe], "moved at A, B and C");
  silent(w);
  await asTheChain(w, before, []);
});

// The `moved` waits for every station the chain names to have said to this device that it serves `bodies`, `logs`,
// `builds` and `carried` (the lead's decisions, 2026-11-14): one whose rules do not know `moved`, or that reads a moved
// chain otherwise, would let in by another state.
test("a station that does not say it serves what a moved chain is: nothing moved, handOverState names it, lock.handOver says so; it says so: moved", async () => {
  const w = await setUp({ old: ["B"] });
  assert.deepEqual(handOverState(w.inner, "ws"), { stations: [w.B] });
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [null, null], "nothing moved");
  const call = await w.hand();
  assert.equal(call.error?.code, "lock_stations_not_ready", "lock.handOver refuses so");
  assert.match(call.error?.message ?? "", /studio 2/);
  w.st.old.clear();
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved");
  silent(w);
});

test("a station that serves bodies, logs and builds and says nothing of carried: waited for and named; it says so: moved", async () => {
  const w = await setUp({ noCarried: ["B"] });
  assert.deepEqual(handOverState(w.inner, "ws"), { stations: [w.B] });
  const lines = texts(lockView(w.inner, "ws").upgrade);
  assert.equal(lines.length, 1);
  assert.match(lines[0]!, /^等待 station studio 2：请将它更新到最新版本并保持在线/);
  w.st.noCarried.clear();
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved");
});

test("a station whose GET /lock was never answered: the moved waits for it, moved once it is; one that said so before and is asleep now holds nothing up", async () => {
  const w = await setUp({ lockDown: ["B"] });
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(handOverState(w.inner, "ws"), { stations: [w.B] }, "B never said it");
  assert.equal(w.stations.A.chain(null)?.state?.moved, undefined, "nothing moved");
  w.st.lockDown.clear();
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved once B said so");
  const v = await setUp({ early: true });
  v.st.down.add("B");
  assert.deepEqual(handOverState(v.inner, "ws"), null, "the switch off here: not by itself");
  assert.equal((await v.hand()).error, undefined, "B said so before");
  await v.run(read(v.inner, "ws"));
  assert.equal(v.stations.A.chain(null)?.state?.moved, v.gMe, "moved at A, B asleep");
});

test("a station waited for taken out of the chain: no longer waited for, moved", async () => {
  const w = await setUp({ lockDown: ["B"] });
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(handOverState(w.inner, "ws"), { stations: [w.B] });
  w.after(w.signer, "station.remove", { key: w.B });
  takeChain(w);
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.equal(w.stations.A.chain(null)?.state?.moved, w.gMe, "moved at A");
  assert.equal(inForceOf(w.inner, "ws").f.stations.has(w.B), false, "B not in the state in force");
});

test("the app closed while the moved waited for a station: moved as it starts again and reads its lock, nobody asked", async () => {
  const w = await setUp({ lockDown: ["B"] });
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [null, null], "nothing moved yet");
  w.st.lockDown.clear();
  await w.restart();
  await w.run(read(w.inner, "ws"));
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(movedAt(w), [w.gMe, w.gMe], "moved as the core started again read its lock");
  silent(w);
});

// What the pages say of a handover (the owner, 2026-11-14: to people it is 「安全模式的升级」): the owner's device says
// which stations it waits for (the `lock` topic's `upgrade`), a sentence each, and the refusals say the same; never a
// member, a device or a button (nothing waits for a person, nothing asks); a pending `moved` is one row of its own; after
// the move, off and on again are the root's person's alone.
const TITLE = "安全模式有一项升级尚未完成";
/// The sentences of the `lock` topic's `upgrade`, a line each.
const texts = (u: unknown): string[] => ((u as { lines?: { text: string }[] } | undefined)?.lines ?? []).map((l) => l.text);

test("words: a station from before named, the refusal the same; a member not on a log, a device on the chain alone: no line", async () => {
  const v = await setUp({ old: ["B"] });
  const lines = texts(lockView(v.inner, "ws").upgrade);
  assert.equal(lines.length, 1);
  assert.match(lines[0]!, /^等待 station studio 2：请将它更新到最新版本并保持在线；已不再使用的话，请在它的页面上选择「从 workspace 移除」$/);
  const call = await v.hand();
  assert.equal(call.error?.code, "lock_stations_not_ready");
  assert.equal(call.error?.message, lines[0], "the refusal says the line");
  const w = await setUp({ more: ["notReady"], early: true });
  assert.equal(lockView(w.inner, "ws").upgrade, undefined, "the switch off: nothing shown");
  const u = await setUp({ more: ["notReady"], flag: false });
  assert.equal(lockView(u.inner, "ws").upgrade, undefined, "nothing waited for, no button: nothing shown");
});

// A station line says whether this person may update that station from here, as its own page offers its update (an
// owner or admin of its workspace, it online, its software updatable and newer, or its update failed; by its overview as
// the device last holds it), and how its update goes while it does (the owner, 2026-11-14: the page says what the
// upgrade waits for, and updates a station with one press).
const overviewOf = (w: Awaited<ReturnType<typeof setUp>>, station: string, own: Record<string, unknown> | null) =>
  w.inner.data.set({ topic: "overview", station } as never, own === null ? {} : { updates: [{ id: "station", name: "still.fail station", installed: true, ...own }] });

test("words: a station waited for, by its overview: updatable and newer, an owner's press; an admin's too; up to date, failed, a member, offline as the cloud says: as its own page offers", async () => {
  const w = await setUp({ old: ["B"] });
  const at = `ws/${w.B}`;
  const line = () => (lockView(w.inner, "ws").upgrade?.lines as Record<string, unknown>[])[0];
  assert.deepEqual(line(), { text: texts(lockView(w.inner, "ws").upgrade)[0], of: "station", station: at }, "nothing held of its overview: no press");
  overviewOf(w, at, { updatable: true, newer: true, version: "0.1.9000", latest: "0.1.9100" });
  assert.equal(line()?.canUpdate, true, "updatable and newer, this person an owner");
  overviewOf(w, at, { updatable: true, newer: false });
  assert.equal(line()?.canUpdate, undefined, "nothing newer: no press, as its page offers none");
  overviewOf(w, at, { updatable: true, state: "failed", message: "x" });
  assert.equal(line()?.canUpdate, true, "its update failed: pressed again, as its page's 重试");
  overviewOf(w, at, { updatable: false, newer: true });
  assert.equal(line()?.canUpdate, undefined, "not updatable from the pages");
  overviewOf(w, at, { state: "updating", percent: 41.6 });
  assert.deepEqual([line()?.updating, line()?.percent, line()?.canUpdate], [true, 42, undefined], "under way: how much of it, no press");
  overviewOf(w, at, { state: "updating" });
  assert.deepEqual([line()?.updating, line()?.percent], [true, undefined], "under way, how much not said");
  overviewOf(w, at, { updatable: true, newer: true });
  for (const [role, can] of [["admin", true], ["member", undefined]] as const) {
    w.inner.data.set({ topic: "workspace", workspace: "ws" } as never, { ...(w.inner.data.shared({ topic: "workspace", workspace: "ws" } as never) as object), role });
    assert.equal(line()?.canUpdate, can, `the workspace's ${role}`);
  }
  const stations = (w.inner.data.shared({ topic: "workspace", workspace: "ws" } as never) as { stations: Record<string, unknown>[] }).stations;
  w.inner.data.set({ topic: "workspace", workspace: "ws" } as never, { ...(w.inner.data.shared({ topic: "workspace", workspace: "ws" } as never) as object), role: "owner", stations: stations.map((s) => (s.id === w.B ? { ...s, online: false } : s)) });
  assert.equal(line()?.canUpdate, undefined, "offline: no press, as its page shows its software only online");
});

test("words: a handover's moved pending is one row, 完成安全模式的升级", async () => {
  const w = await setUp({ early: true });
  w.st.silent = true;
  const out = await w.hand();
  assert.ok((out.ok as { pending?: unknown } | null)?.pending, JSON.stringify(out.ok));
  const rows = lockView(w.inner, "ws").pending as { text: string }[];
  assert.equal(rows.length, 1, JSON.stringify(rows));
  assert.match(rows[0]!.text, /^完成安全模式的升级：已记下，等 .+ 上线后生效$/);
});

test("words: moved and turned off by the root's person: the page offers turning it on again, which asks and is pending in its own words", async () => {
  const w = await setUp({ early: true });
  assert.equal((await w.hand()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.equal(lockView(w.inner, "ws").rootText, undefined, "the root's person: none");
  const off = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.disable", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(off.error, undefined, off.error?.message);
  await w.run(read(w.inner, "ws"));
  const page = lockView(w.inner, "ws");
  assert.equal(inForceOf(w.inner, "ws").said, "off");
  // (off, the root's log having said no `open`: the settings are still the chain's as it moved, which turning it on
  // again says; found by the moved workspace's round on real stations, 2026-11-14: an `open` with no keys made every
  // credential after it unknown)
  assert.deepEqual(inForceOf(w.inner, "ws").settings, { origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: w.g.keys }, "the chain's settings while off");
  assert.deepEqual({ locked: page.locked, notice: page.notice, onAgainText: page.onAgainText, members: (page.members as unknown[]).length, stations: (page.stations as { protected: boolean }[]).filter((s) => s.protected).length }, { locked: false, notice: true, onAgainText: "重新开启安全模式", members: 3, stations: 2 }, "what the topic says of a moved workspace that is off");
  w.st.silent = true;
  const on = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.open", { workspace: "ws" }), catch: (e) => e as CoreError }));
  assert.equal(on.error, undefined, on.error?.message);
  assert.equal(w.r.host.secureAsked.at(-1)?.reason, "重新开启安全模式");
  const rows = (lockView(w.inner, "ws").pending as { text: string }[]).map((x) => x.text);
  assert.ok(rows.some((x) => /^重新开启安全模式：已记下，等 .+ 上线后生效$/.test(x)), JSON.stringify(rows));
});

// A device the chain as it moved carries, not on its person's log, taken off by its person's own device after the move
// (the owner, 2026-11-14: a lost device can be taken off): one ask, put on their log under a key thrown away and taken
// off by it (personal-lock.ts `removeCarried`), then out at every station and here.
test("a carried app device of this device's person taken off after the move: one ask, out at A, B and here, nothing of it in force", async () => {
  const w = await setUp({ early: true });
  const phone = dev();
  w.after(w.signer, "device", { id: phone.base.hex, sub: "s1", kind: "app", label: "s1's phone", sign_key: phone.signer.id });
  takeChain(w);
  await w.run(read(w.inner, "ws"));
  assert.equal((await w.hand()).error, undefined);
  await w.run(read(w.inner, "ws"));
  assert.equal(inForceOf(w.inner, "ws").f.devices.get(phone.base.hex)?.by, "chain", "carried");
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.removeDevice", { workspace: "ws", device: phone.base.hex }), catch: (e) => e as CoreError }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), 1, "one ask");
  const log = w.inner.adb.personal().entries("s1");
  assert.deepEqual(log.slice(-2).map((e) => e.kind), ["device", "device.remove"], "put on and taken off their log");
  for (const c of Object.values(w.stations)) c.takeLock([...w.chain] as unknown as StationEntry[]);
  await w.run(read(w.inner, "ws"));
  assert.equal(inForceOf(w.inner, "ws").f.devices.has(phone.base.hex), false, "out here");
  for (const [n, c] of Object.entries(w.stations)) {
    assert.equal(c.locked(null)?.state?.devices.has(phone.base.hex), false, `out at ${n}`);
    const p = admitted("s1", phone, "owner");
    assert.throws(() => inLock(c, p as never, "owner", p.viewer.device), `refused by ${n}`);
  }
});

// A member the chain bound to no log, this device theirs (the lead, 2026-11-14: a carried member with no log of their
// own does for themselves what they did before the move): what they do on their own lock with one ask binds them to it in
// that same ask (`bind`, proved by this device's signer the chain names, views/lock.ts `bindsFor`, personal-lock.ts
// `#addBinds`), and so does a change of the list they make (`sayMoved`). s0 moves the chain; s1 is its second owner.
async function unboundMoved(o: Opts = {}) {
  const w = await setUp({ early: true, mine: "second", unbound: true, ...o });
  const phone = w.s1Phone;
  if (o.noLog !== true) {
    w.after(w.first.app.signer, "moved", { root: w.first.genesis });
    for (const c of Object.values(w.stations)) c.takeLock([...w.chain] as unknown as StationEntry[], null, true);
  }
  await w.run(read(w.inner, "ws"));
  const f = inForceOf(w.inner, "ws").f;
  assert.equal(f.persons.has("s1"), false, "s1 bound to no log");
  assert.equal(f.devices.get(w.base.hex)?.by, "chain", "this device carried");
  return { w, phone };
}
const boundAt = (w: Awaited<ReturnType<typeof setUp>>) => [inForceOf(w.inner, "ws").f.persons.get("s1"), ...Object.values(w.stations).map((c) => c.locked()!.state!.persons.get("s1"))];

test("an unbound member takes off a carried phone of theirs: one ask, bound to their own log in it, the phone out here and at both stations", async () => {
  const { w, phone } = await unboundMoved();
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.removeDevice", { workspace: "ws", device: phone.base.hex }), catch: (e) => e as CoreError }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), 1, "one ask");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(boundAt(w), [w.gMe, w.gMe, w.gMe], "bound to their log, here and at A and B");
  assert.equal(inForceOf(w.inner, "ws").f.devices.has(phone.base.hex), false, "the phone out");
  for (const c of Object.values(w.stations)) assert.equal(c.locked()!.state!.devices.has(phone.base.hex), false, "out at the stations");
  assert.ok(inForceOf(w.inner, "ws").f.devices.has(w.base.hex), "this device still in");
});

test("an unbound member takes off their web page the chain carries: one ask, bound in it, the page out", async () => {
  const { w } = await unboundMoved({ myWeb: true });
  assert.equal(inForceOf(w.inner, "ws").f.devices.get(w.WEB.hex)?.by, "chain");
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.removeDevice", { workspace: "ws", device: w.WEB.hex }), catch: (e) => e as CoreError }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), 1, "one ask");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(boundAt(w), [w.gMe, w.gMe, w.gMe]);
  assert.equal(inForceOf(w.inner, "ws").f.devices.has(w.WEB.hex), false, "the page out");
});

test("an unbound owner takes a member out: one ask, bound in it, the member out by their statement", async () => {
  const { w } = await unboundMoved();
  // (the cloud's part of the call, past the lock: it takes the removal)
  stationLater(w.r.host, (req) => (req.method === "DELETE" && new URL(req.url).pathname === "/v1/workspaces/ws/members/r3" ? Promise.resolve(jsonResponse(200, {})) : undefined));
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("workspace.removeMember", { account: "s1", workspace: "ws", member: "r3" }), catch: (e) => e as CoreError }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked(), 1, "one ask");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(boundAt(w), [w.gMe, w.gMe, w.gMe]);
  assert.equal(inForceOf(w.inner, "ws").f.members.has("r3"), false, "r3 out");
  for (const c of Object.values(w.stations)) assert.equal(c.locked()!.state!.members.has("r3"), false, "out at the stations");
});

// A member the chain bound to no log who has no log of their own at all, at their app's first read of the moved chain
// (the lead, 2026-11-14). Whom it stands for: a member with another app on the chain that never said the key of a lock
// of one's own (a stale laptop, or one that seals nothing), while which their app in hand begins none (views/lock.ts
// `ownLockOnce`'s `waiting`) and which holds no move back; and an app not opened since before own logs, which no move
// waits for. An app of today that is let in alone begins its person's log by itself before any
// move (`ownLockOnce`), so this is not that one. What they do for themselves on their own devices begins their log in
// that act's one ask, as views/pair.ts `ownLogFor` begins a newcomer's, binds them to it (`bind`) and then does it
// (personal-lock.ts `seedFor`): nobody else involved, nothing asked more than before the move. (locks-moved.ts round
// 23 holds the first of them on real stations.)
async function noLog(o: Opts = {}) {
  const { w, phone } = await unboundMoved({ noLog: true, ...o });
  assert.equal(w.inner.adb.personal().standing("s1"), "none", "no log of their own");
  return { w, phone, before: w.asked(), reasons: () => w.r.host.secureAsked.map((a) => a.reason) };
}
/// After the act: s1 bound to the log just begun here and at both stations, that log this device's.
const begunAndBound = async (w: Awaited<ReturnType<typeof setUp>>) => {
  const log = w.inner.adb.personal().root("s1");
  assert.ok(log !== null, "their log begun");
  assert.equal(w.inner.adb.personal().standing("s1"), "member", "this device on it");
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(boundAt(w), [log, log, log], "bound to it here and at A and B");
  return log!;
};

test("no log at all: taking off a carried phone of theirs begins their log in the one ask, binds them to it, and takes the phone off here and at both stations", async () => {
  const { w, phone, before, reasons } = await noLog();
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.removeDevice", { workspace: "ws", device: phone.base.hex }), catch: (e) => e as CoreError }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked() - before, 1, `one ask (${JSON.stringify(reasons().slice(before))})`);
  await begunAndBound(w);
  assert.equal(inForceOf(w.inner, "ws").f.devices.has(phone.base.hex), false, "the phone out");
  for (const c of Object.values(w.stations)) assert.equal(c.locked()!.state!.devices.has(phone.base.hex), false, "out at the stations");
  assert.ok(inForceOf(w.inner, "ws").f.devices.has(w.base.hex), "this device still in");
});

test("no log at all: approving their own web page face to face begins their log in the one ask, binds them, and lets the page in at both stations", async () => {
  const { w, before, reasons } = await noLog();
  const page = ed();
  const prompts = await w.r.watch({ topic: "lockPrompts" });
  const [trusted, conn] = await pipe();
  w.inner.runner.fork(serveTrusted(w.inner, page.hex, w.base.hex, trusted));
  const first = await w.run(Effect.andThen(conn.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: w.g.credential("ws", page.hex, "s1") }], kind: "web", label: "Chrome", sign_key: null }), conn.next()));
  assert.deepEqual(first.ok, { t: "code", workspaces: ["ws"] }, "a code shown here, by their own device");
  const code = ((await prompts()).pairing as { device: string; code: string }[]).find((p) => p.device === page.hex)!.code;
  const done = await w.run(tryOne(w.inner, { id: w.base.hex, d: conn, workspaces: ["ws"] }, page.hex, code));
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(w.asked() - before, 1, `one ask (${JSON.stringify(reasons().slice(before))})`);
  await begunAndBound(w);
  for (const c of Object.values(w.stations)) assert.equal(c.locked()!.state!.devices.get(page.hex)?.kind, "web", "the page in at the stations");
});

test("no log at all: approving their own new app face to face (it asks to join their lock) begins their log in the one ask, binds them, and puts it on: in at both stations by its signer", async () => {
  const { w, before, reasons } = await noLog();
  const k = key(7011), id = key(7111).hex, SIGNS = `ed25519:${"13".repeat(32)}`;
  const prompts = await w.r.watch({ topic: "lockPrompts" });
  const [trusted, conn] = await pipe();
  w.inner.runner.fork(serveTrusted(w.inner, id, w.base.hex, trusted));
  const first = await w.run(Effect.andThen(conn.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: w.g.credential("ws", id, "s1") }], kind: "app", label: "Pixel", sign_key: SIGNS, personal: { subs: ["s1"], key: k.id } }), conn.next()));
  assert.deepEqual(first.ok, { t: "code", workspaces: ["person:s1"] }, "a code shown here, by their own device");
  const code = ((await prompts()).pairing as { device: string; code: string }[]).find((p) => p.device === id)!.code;
  const done = await w.run(tryOne(w.inner, { id: w.base.hex, d: conn, workspaces: ["person:s1"] }, id, code));
  assert.equal(done.error, undefined, done.error?.message);
  assert.equal(w.asked() - before, 1, `one ask (${JSON.stringify(reasons().slice(before))})`);
  await begunAndBound(w);
  assert.ok(w.inner.adb.personal().entries("s1").some((e) => e.kind === "device" && (e.body as { id: string }).id === id), "on their log");
  for (const c of Object.values(w.stations)) assert.equal(c.locked()!.state!.devices.get(id)?.sign_key, SIGNS, "in at the stations by its signer");
});

test("no log at all: taking off their web page the chain carries begins their log in the one ask, binds them, and takes the page off", async () => {
  const { w, before, reasons } = await noLog({ myWeb: true });
  assert.equal(inForceOf(w.inner, "ws").f.devices.get(w.WEB.hex)?.by, "chain");
  const out = await w.run(Effect.tryPromise({ try: () => w.r.ask("lock.removeDevice", { workspace: "ws", device: w.WEB.hex }), catch: (e) => e as CoreError }));
  assert.equal(out.error, undefined, out.error?.message);
  assert.equal(w.asked() - before, 1, `one ask (${JSON.stringify(reasons().slice(before))})`);
  await begunAndBound(w);
  for (const c of Object.values(w.stations)) assert.equal(c.locked()!.state!.devices.has(w.WEB.hex), false, "the page out at the stations");
});
