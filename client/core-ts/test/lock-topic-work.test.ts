// What a make of the `lock` topic costs, counted (2026-11-14: on an owner's Android phone, build 0.1.9172, 9 of 14 slow
// `core.flush` were `lock`, 236–279 ms each, rounds of them a minute; the workspace, 1 member, 8 devices, 5 stations, a
// chain of 32 entries, had not moved, held back by what says nothing). Counted as the rules are called by the core's own
// code (test/rules-counted.ts: each call into rules/js/rules.js by name, the hashes and signatures they ask) and the
// signatures checked in fact (vault/verified.ts `verifies`); the milliseconds in Node are printed, never held. Three
// workspaces of that size on the station's own code (as test/lock-handover.test.ts's): (a) not moved, this device the
// owner's that would move it, held back (its own build under MOVED_FROM_BUILD, `heldBack`); (b) not moved, a member's
// device; (c) moved. What is held: the topic (and what reads the same, `safeMode`, the vaults' topic) made again with
// the same things held calls the rules zero times; a log or an entry changed costs what it changes.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { countRules, since, snapshot } from "./rules-counted.ts";

await countRules();
const { Effect } = await import("effect");
const { entryHash: stationHash, fold: stationFold } = await import("../../../station/src/cloud/lock.ts");
const { Cloud, writeState } = await import("../../../station/src/cloud/state.ts");
const { wall } = await import("../../../station/src/ops/fibers.ts");
const { lockPartRoute, lockRoute } = await import("../../../station/src/mesh/serve.ts");
const { deviceBuildsOf } = await import("../../../station/src/mesh/device-builds.ts");
const { MOVED_FROM_BUILD } = await import("../../../station/src/api/moved-from.ts");
const { Log, bring, dev, ed, signed, viewerOf } = await import("../../../station/test/lock-moved-world.ts");
const { key, signed: simSigned } = await import("../../../station/test/lock-world-sim.ts");
const { HAND_OVER_FROM } = await import("../src/lock-handover.ts");
const { entryHash, next } = await import("../src/lock.ts");
const { httpError } = await import("../src/station/requests.ts");
const { hex, utf8 } = await import("../src/util.ts");
const { ownBuild, setOwnBuild } = await import("../src/station/oldest.ts");
const { handOverState, held, inForceOf, lockSeen, lockView, read, safeMode } = await import("../src/views/lock.ts");
const { verifies } = await import("../src/vault/verified.ts");
const { walked, walkingBy } = await import("../src/work.ts");
const { grant, rig, withoutMesh } = await import("./lock-rig.ts");
const { signIn } = await import("./helpers.ts");
type Entry = import("../src/lock.ts").Entry;
type Signer = import("../src/lock.ts").Signer;
type StationEntry = import("../../../station/src/cloud/lock.ts").Entry;
type CoreError = import("../src/error.ts").CoreError;

const DAY = 86400;
const T0 = HAND_OVER_FROM! + 30 * DAY;
let clock = () => 0;
mock.method(wall, "now", () => clock());
const MINE = 7001;
const seedOf = (n: number) => {
  const s = new Uint8Array(32);
  new DataView(s.buffer).setUint32(28, n);
  return s;
};

/// A workspace of the size seen: `members` people (this device's s1 among them, each other an app device and a log of
/// their own bound and brought), `devices` app devices on the chain (the owner's others past one each), `stations`
/// stations, the chain padded to `chain` entries (a web page of the owner's put on and taken off), every log padded to
/// `log` entries (a device put on and taken off). `role`: s1's (`member`: s0 the owner, its genesis signer).
type Size = { members: number; devices: number; stations: number; chain: number; log: number; role: "owner" | "member" };
const SEEN: Size = { members: 1, devices: 8, stations: 5, chain: 32, log: 40, role: "owner" };

async function setUp(o: Size) {
  const g = grant();
  const base = ed();
  const k = key(MINE);
  const myLog: StationEntry[] = [simSigned({ v: 1, ws: "person:s1", seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub: "s1", device: { key: k.id, id: base.hex, label: "s1's app" } } } as Omit<StationEntry, "sig">, k)];
  const pad = (n: number, put: (i: number) => void, len: () => number) => {
    for (let i = 0; len() < n; i++) put(i);
  };
  // (s1's own log: put on, taken off, so many times)
  pad(o.log, (i) => {
    const d = key(9000 + i);
    const last = myLog.at(-1)!;
    const kind = i % 2 === 0 ? "device" : "device.remove";
    const body = kind === "device" ? { key: d.id, id: key(9500 + i).hex, label: `s1's spare ${i}` } : { key: key(9000 + i - 1).id };
    myLog.push(simSigned({ v: 1, ws: "person:s1", seq: last.seq + 1, prev: stationHash(last), at: 1000, kind, body } as Omit<StationEntry, "sig">, k));
  }, () => myLog.length);
  const owner = o.role === "member" ? new Log("s0") : null;
  const others = Array.from({ length: o.members - 1 }, (_, i) => new Log(`m${i}`));
  const logs = [...(owner ? [owner] : []), ...others];
  for (const l of logs) {
    pad(o.log, (i) => {
      const d = dev();
      if (i % 2 === 0) l.add("device", { key: d.key.id, id: d.base.hex, label: `spare ${i}` });
      else l.add("device.remove", { key: (l.entries.at(-1)!.body as { key: string }).key });
    }, () => l.entries.length);
  }
  const ids = Array.from({ length: o.stations }, () => ed().hex);
  const extra = Array.from({ length: Math.max(0, o.devices - 1 - logs.length) }, () => dev());
  let mine: Signer | null = null;
  let now = 0;
  const appOf = (sub: string, d: { base: { hex: string }; signer: { id: string } }, label = `${sub}'s app`) => ({ id: d.base.hex, sub, kind: "app", label, sign_key: d.signer.id });
  const ownerSub = owner ? "s0" : "s1";
  const r = await rig((signer) => {
    mine = signer;
    const members = [...(owner ? [{ sub: "s0", email: "o@x.com", role: "owner" }] : []), { sub: "s1", email: "a@x.com", role: o.role }, ...others.map((l) => ({ sub: l.sub, email: `${l.sub}@x.com`, role: "member" }))];
    const devices = [...(owner ? [appOf("s0", owner.app)] : []), { id: base.hex, sub: "s1", kind: "app", label: "s1's app", sign_key: signer.id }, ...others.map((l) => appOf(l.sub, l.app))];
    const e = next("ws", null, 1000, "genesis", { owner: ownerSub, origins: ["https://stillfail.test"], rp_id: "stillfail.test", cloud_keys: g.keys, members, devices, passkeys: [], stations: ids.map((key, i) => ({ key, name: `st${i}` })), gateways: [] });
    return { ws: owner ? (signed(e as Omit<StationEntry, "sig">, owner.app.signer) as unknown as Entry) : signer.sign(e) };
  }, (host) => {
    host.advance(T0 * 1000 - host.nowMs());
    signIn(host);
    host.handOverByTests = false;
    now = Math.floor(host.nowMs() / 1000);
    host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(myLog)));
    host.storage.set("personal-signer-id", utf8(k.id));
    host.secure.set("personal-signer", { value: seedOf(MINE), user: true });
  }, ids, ids, undefined, [], o.role === "member" ? { role: "member" } : {});
  clock = () => r.host.nowMs();
  const inner = r.core.inner;
  const signer = mine! as Signer;
  const byOwner = owner ? owner.app.signer : signer;
  const chain: Entry[] = [r.cloud.chains.get("ws")![0]!];
  const after = (by: { id: string; sign?: unknown; signBytes?: unknown }, kind: string, body: unknown): Entry => {
    const last = chain[chain.length - 1]!;
    const e = next("ws", { seq: last.seq, hash: entryHash(last), genesis: entryHash(chain[0]!) }, Math.max(last.at, now), kind, body);
    const s = "signBytes" in by ? (by as Signer).sign(e) : (signed(e as Omit<StationEntry, "sig">, by as never) as unknown as Entry);
    chain.push(s);
    return s;
  };
  after(signer, "person", { sub: "s1", person: stationHash(myLog[0]!) });
  for (const l of logs) after(l.app.signer, "person", { sub: l.sub, person: l.genesis });
  extra.forEach((d, i) => after(byOwner, "device", appOf(ownerSub, d, `${ownerSub}'s device ${i}`)));
  pad(o.chain, (i) => {
    const id = key(8000 + (i >> 1)).hex;
    if (i % 2 === 0) after(byOwner, "device", { id, sub: ownerSub, kind: "web", label: "a browser", exp: now + 10 * DAY });
    else after(byOwner, "device.remove", { id });
  }, () => chain.length);
  r.cloud.chains.set("ws", chain);
  const stations = ids.map((id) => {
    const data = mkdtempSync(join(tmpdir(), "lock-topic-work-"));
    writeState(data, { origin: "https://stillfail.test", station: id, workspace: "ws", workspace_name: "W", name: id.slice(0, 4), relay_url: "", relay_urls: [], grant_keys: g.keys, peers: ids.map((p, i) => ({ id: p, name: `s${i}` })), revocations: [] } as never);
    const c = new Cloud(data, false);
    c.takeLock(chain as unknown as StationEntry[]);
    for (const l of logs) bring(c, l, false, "ws");
    for (const [did, d] of stationFold(chain as unknown as StationEntry[], null).devices) if (d.kind === "app" && did !== base.hex) deviceBuildsOf(c).saw(did, 0, Math.floor(clock() / 1000));
    return c;
  });
  const viewer = viewerOf("s1", { base }, o.role, "ws");
  /// Each station's answers, by path: counted, as this device asks them.
  const asked: string[] = [];
  inner.mesh = () => withoutMesh(base.hex);
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    const at = ids.indexOf(id ?? "");
    if (path.startsWith("/lock") && ws === "ws" && at >= 0) {
      asked.push(`${method} ${path.split("?")[0]}`);
      const [p, q] = path.split("?") as [string, string | undefined];
      const buf = Buffer.from(body === null || body === undefined ? "" : JSON.stringify(body));
      const c = stations[at]!;
      const [status, said] = p === "/lock" ? lockRoute(c, method, q ? [...new URLSearchParams(q)] : [], buf, viewer as never) : lockPartRoute(c, p.slice("/lock/".length), method, buf, viewer as never);
      return status === 200 ? Effect.succeed(said) : Effect.fail(httpError(status, said));
    }
    if (path.startsWith("/lock") && ws !== "ws") return method === "GET" && path === "/lock/person" ? Effect.succeed({ chains: [], serves: ["logs", "builds"], builds: { since: 0, devices: {} } }) : Effect.fail(httpError(404, { error: "no route" }));
    return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: import("effect").Effect.Effect<X, any>): Promise<{ ok?: X; error?: CoreError }> => {
    let out: { ok?: X; error?: CoreError } | null = null;
    inner.runner.fork(Effect.match(e, { onSuccess: (ok) => void (out = { ok }), onFailure: (error) => void (out = { error }) }));
    await r.host.time.passUntil(30_000, () => out !== null);
    assert.ok(out !== null, "no answer");
    await r.host.time.pass(100);
    return out;
  };
  await run(inner.adb.personal().refresh("s1"));
  await run(read(inner, "ws"));
  return { r, inner, chain, after, byOwner, stations, logs, others, owner, run, asked, base };
}
type World = Awaited<ReturnType<typeof setUp>>;

/// A workspace of the size seen in each of (a), (b), (c), as its makes stand once it is read and at rest.
async function scenario(which: "a" | "b" | "c", size: Size = SEEN): Promise<World> {
  const was = ownBuild();
  if (which === "a") setOwnBuild(`0.1.${MOVED_FROM_BUILD - 1}`);
  try {
    const w = await setUp(which === "b" ? { ...size, role: "member" } : size);
    if (which === "c") {
      await w.run(read(w.inner, "ws"));
      await w.run(read(w.inner, "ws"));
      assert.equal(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved", "(c) moved");
      assert.equal(inForceOf(w.inner, "ws").said, "on", "(c) the state in force on");
    } else {
      assert.notEqual(held(w.inner, "ws")?.entries.at(-1)?.kind, "moved", `(${which}) not moved`);
      assert.equal(held(w.inner, "ws")?.entries.length, size.chain, `(${which}) a chain of ${size.chain}`);
    }
    if (which === "a") assert.deepEqual(handOverState(w.inner, "ws"), { held: ["own build"] }, "(a) held back, saying nothing");
    if (which === "b") assert.equal(handOverState(w.inner, "ws"), null, "(b) not this device's to move");
    await w.r.host.time.pass(1000);
    return w;
  } finally {
    setOwnBuild(was);
  }
}

type Cost = { calls: number; hashes: number; sigs: number; verified: number; ms: number; by: Record<string, number> };
/// What `make` costs each time, made `n` times over with nothing changed between (once first, to begin from rest).
function cost(make: () => unknown, n = 10): Cost {
  make();
  const s = snapshot(), v = verifies.count, t0 = performance.now();
  for (let i = 0; i < n; i++) make();
  const ms = (performance.now() - t0) / n;
  const d = since(s);
  const by: Record<string, number> = {};
  for (const [k, x] of Object.entries(d.calls)) by[k] = x / n;
  return { calls: d.total / n, hashes: d.hashes / n, sigs: d.sigs / n, verified: (verifies.count - v) / n, ms: Math.round(ms * 10) / 10, by };
}
const line = (what: string, c: Cost) =>
  `${what.padEnd(34)} rules ${String(c.calls).padStart(4)}  hashes ${String(c.hashes).padStart(6)}  sigs ${String(c.sigs).padStart(5)}  verified ${String(c.verified).padStart(3)}  ${String(c.ms).padStart(6)} ms  ${Object.entries(c.by).map(([k, x]) => `${k}×${x}`).join(" ")}`;

/// The `lock` topic as the app holds it, made again as the store makes it: the count of its makes and the rules' calls
/// they made, for `go` (a change, or a mark with none behind it).
async function topicMakes(w: World, go: () => Promise<void>): Promise<{ makes: number; calls: number; by: Record<string, number> }> {
  const by = new Map<string, typeof walked>();
  await w.r.watch({ topic: "lock", workspace: "ws" });
  await w.r.host.time.pass(1000);
  const s = snapshot();
  walkingBy(by);
  try {
    await go();
    await w.r.host.time.pass(1000);
  } finally {
    walkingBy(null);
  }
  const d = since(s);
  return { makes: by.get("lock")?.recomputes ?? 0, calls: d.total, by: d.calls };
}

const out: string[] = [];
test("measured: a make of the lock topic, safeMode and the vaults' topic, in (a), (b), (c) of the size seen", async () => {
  for (const which of ["a", "b", "c"] as const) {
    const w = await scenario(which);
    out.push(line(`(${which}) lock`, cost(() => lockView(w.inner, "ws"))));
    out.push(line(`(${which}) inForceOf`, cost(() => inForceOf(w.inner, "ws"))));
    out.push(line(`(${which}) handOverState`, cost(() => handOverState(w.inner, "ws"))));
    out.push(line(`(${which}) safeMode`, cost(() => safeMode(w.inner, "ws"))));
    const marked = await topicMakes(w, async () => lockSeen(w.inner).touch("lock ws"));
    out.push(`(${which}) the topic marked, nothing changed: ${marked.makes} make(s), ${marked.calls} rules calls ${JSON.stringify(marked.by)}`);
    const reread = await topicMakes(w, async () => void (await w.run(read(w.inner, "ws"))));
    out.push(`(${which}) the lock read again, the same answers: ${reread.makes} make(s), ${reread.calls} rules calls ${JSON.stringify(reread.by)}; asked ${w.asked.length} so far`);
    w.r.core.close();
  }
  // One thing changed, read as the sync reads it, and the topic made: what of the rules that took, by name.
  for (const which of ["a", "c"] as const) {
    const w = await scenario(which, { ...SEEN, members: 3 });
    await w.r.watch({ topic: "lock", workspace: "ws" });
    await w.r.host.time.pass(1000);
    let s = snapshot();
    const m = w.others[0]!;
    m.add("device", { key: dev().key.id, id: dev().base.hex, label: "one more" });
    for (const c of w.stations) bring(c, m, false, "ws");
    await w.run(read(w.inner, "ws"));
    await w.r.host.time.pass(1000);
    lockView(w.inner, "ws");
    out.push(`(${which}) a member's log one entry longer, read, made: ${JSON.stringify(since(s).calls)}`);
    s = snapshot();
    if (which === "a") {
      w.after(w.byOwner, "device", { id: ed().hex, sub: "s1", kind: "web", label: "one more page", exp: Math.floor(w.r.host.nowMs() / 1000) + 10 * DAY });
      for (const c of w.stations) c.takeLock(w.chain as unknown as StationEntry[]);
      await w.run(read(w.inner, "ws"));
      await w.r.host.time.pass(1000);
      lockView(w.inner, "ws");
      out.push(`(${which}) the chain one entry longer, read, made: ${JSON.stringify(since(s).calls)}`);
    }
    w.r.core.close();
  }
  console.log(`\n${out.join("\n")}\n`);
});

// Made again with the same things held, the topic and what reads the same call the rules not once and check no
// signature: what the rules work out is kept by what it is made of (views/lock.ts `planHere`, `checkedChain`, as
// `inForceOf` keeps the state in force).
for (const which of ["a", "b", "c"] as const) {
  test(`(${which}) the lock topic made again, nothing changed: no rules called, no signature checked`, async () => {
    const w = await scenario(which);
    const made = cost(() => lockView(w.inner, "ws"));
    assert.deepEqual({ calls: made.calls, verified: made.verified }, { calls: 0, verified: 0 }, `a make of lock: ${line("lock", made)}`);
    const safe = cost(() => safeMode(w.inner, "ws"));
    assert.equal(safe.calls, 0, `safeMode: ${line("safeMode", safe)}`);
    const state = cost(() => handOverState(w.inner, "ws"));
    assert.equal(state.calls, 0, `handOverState: ${line("handOverState", state)}`);
    const marked = await topicMakes(w, async () => lockSeen(w.inner).touch("lock ws"));
    assert.equal(marked.makes, 1, "the topic marked is made again");
    assert.equal(marked.calls, 0, `the topic made again calls the rules: ${JSON.stringify(marked.by)}`);
    w.r.core.close();
  });
}

// One thing changed costs what it changes: a member's log one entry longer makes the plan (or the state in force) once
// and checks the chain, unchanged, not again; the chain one entry longer checks it once for the plan.
test("(a), (c) a member's log one entry longer, and (a) the chain one entry longer: what of the rules each costs", async () => {
  for (const which of ["a", "c"] as const) {
    const w = await scenario(which, { ...SEEN, members: 3 });
    await w.r.watch({ topic: "lock", workspace: "ws" });
    await w.r.host.time.pass(1000);
    let s = snapshot();
    const m = w.others[0]!;
    m.add("device", { key: dev().key.id, id: dev().base.hex, label: "one more" });
    for (const c of w.stations) bring(c, m, false, "ws");
    await w.run(read(w.inner, "ws"));
    await w.r.host.time.pass(1000);
    lockView(w.inner, "ws");
    lockView(w.inner, "ws");
    const log = since(s).calls;
    assert.equal(log.fold_held_js ?? 0, 0, `(${which}) the chain, unchanged, checked again: ${JSON.stringify(log)}`);
    assert.equal(log.state4_moved_js ?? 0, 1, `(${which}) the state as if moved (or in force) made once: ${JSON.stringify(log)}`);
    if (which === "a") {
      s = snapshot();
      w.after(w.byOwner, "device", { id: ed().hex, sub: "s1", kind: "web", label: "one more page", exp: Math.floor(w.r.host.nowMs() / 1000) + 10 * DAY });
      for (const c of w.stations) c.takeLock(w.chain as unknown as StationEntry[]);
      await w.run(read(w.inner, "ws"));
      await w.r.host.time.pass(1000);
      lockView(w.inner, "ws");
      lockView(w.inner, "ws");
      const entry = since(s).calls;
      assert.ok((entry.fold_held_js ?? 0) <= 2, `(a) the chain checked once for the handover, once for the vaults: ${JSON.stringify(entry)}`);
      assert.equal(entry.state4_moved_js ?? 0, 1, `(a) the plan made once: ${JSON.stringify(entry)}`);
    }
    w.r.core.close();
  }
});

// A read that brings nothing new (each station's, at every reconnect and every event: `GET /lock`, `/lock/devices`,
// `/lock/person`, `/lock/logs`, `/lock/bodies`, and the stations' heads as the topic is shown) makes the topic not
// again and calls no rules (views/lock.ts `hold`, `readStations`).
for (const which of ["a", "b", "c"] as const) {
  test(`(${which}) the lock read again of every station, the same answers: the topic not made again, no rules called`, async () => {
    const w = await scenario(which);
    await w.run(read(w.inner, "ws"));
    await w.run(w.inner.adb.personal().refresh("s1"));
    await w.r.host.time.pass(1000);
    const asked = w.asked.length;
    const again = await topicMakes(w, async () => {
      await w.run(read(w.inner, "ws"));
      await w.run(w.inner.adb.personal().refresh("s1"));
    });
    const routes = [...new Set(w.asked.slice(asked))].sort();
    assert.ok(routes.includes("GET /lock") && routes.includes("GET /lock/devices") && routes.includes("GET /lock/person"), `read of each: ${routes.join(", ")}`);
    assert.equal(again.makes, 0, `the topic made again ${again.makes} times; rules: ${JSON.stringify(again.by)}`);
    assert.equal(again.calls, 0, `the rules called: ${JSON.stringify(again.by)}`);
    w.r.core.close();
  });
}
