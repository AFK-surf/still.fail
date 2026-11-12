// A person's own lock (src/personal-lock.ts): only a device on it writes it, each use of its key
// asks the person, and a phone lends only on a grant signed by a device on the lock it pinned: not on a station's word,
// a signature for something else, a key off the lock, one past its time, or one taken back here.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Adb } from "../src/adb.ts";
import { CoreError, HostError } from "../src/error.ts";
import { generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { type Entry, entryHash, signedBytes } from "../src/lock.ts";
import type { Mesh } from "../src/mesh.ts";
import { PersonalLock, checkChain, grantHolds } from "../src/personal-lock.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { forgetVerifiedHere, keepVerified, verifies } from "../src/vault/verified.ts";
import { personalStub } from "./adb-personal-stub.ts";

const SUB = "s1";
const STATION = "ws/st";

/// A cloud that keeps one chain, as cloud/src/personal-lock.ts does.
function cloud() {
  const kept = { entries: [] as Entry[] };
  // (`limited`: how many writes it answers "too many requests" first; `down`: none answered; `asked`: how many asks)
  const say = { limited: 0, down: false, asked: 0 };
  return {
    kept,
    say,
    call: (_sub: string, method: string, _path: string, body: unknown) =>
      Effect.suspend(() => (say.asked++, say.down) ? Effect.fail(new CoreError("network", "the cloud is down")) : method === "POST" && say.limited-- > 0 ? Effect.fail(new CoreError("rate_limited", "too many", 429)) : Effect.sync(() => {
        if (method === "GET") return { entries: kept.entries };
        const adding = (body as { entries: Entry[] }).entries;
        kept.entries = adding[0]!.seq === 0 ? adding : [...kept.entries.slice(0, adding[0]!.seq), ...adding];
        return { entries: kept.entries };
      })) as Effect.Effect<unknown, CoreError>,
  };
}

/// The person's stations, as station/src/mesh/person-chains.ts keeps their lock: each chain by its first entry, the
/// longer taken where it goes on from the one kept, one at odds refused. `up`: whether any of them is reached.
/// `taking`: what lands on the device once a station took what it was brought and before its answer does (a read made
/// meanwhile, answered first), once.
function stations() {
  const kept = new Map<string, Entry[]>();
  const say = { up: true, read: 0, brought: 0, at: [] as (string | undefined)[], taking: null as (() => Effect.Effect<void, CoreError>) | null };
  const root = (c: Entry[]) => JSON.stringify(c[0]);
  return {
    kept,
    say,
    env: {
      read: (_sub: string, at?: string) => Effect.sync(() => (say.read++, say.at.push(at), say.up ? [...kept.values()] : null)),
      bring: (_sub: string, chain: Entry[]) =>
        Effect.suspend(() => {
          say.brought++;
          if (!say.up) return Effect.succeed(null);
          const had = kept.get(root(chain)) ?? [];
          const [short, long] = had.length <= chain.length ? [had, chain] : [chain, had];
          if (!short.every((e, i) => JSON.stringify(e) === JSON.stringify(long[i]))) return Effect.fail(new CoreError("lock_refused", "at odds with the one kept", 409));
          kept.set(root(chain), long);
          const taking = say.taking;
          say.taking = null;
          return taking === null ? Effect.succeed(1) : Effect.map(taking(), () => 1);
        }),
    },
  };
}

/// A device: its host keeps what is sealed with `user: true` apart, each read of it counted, as asking the person.
/// `at`: its person's stations, where it reads and brings the lock (none: the cloud alone, as a core from before).
function device(c: ReturnType<typeof cloud>, name: string, at?: ReturnType<typeof stations>) {
  const id = name.charCodeAt(0).toString(16).repeat(32);
  const host = new FakeHost();
  host.appKeys = true;
  // (each device's keys its own: FakeHost's are the same for all)
  host.randomBytes = (b: Uint8Array) => void b.fill(name.charCodeAt(0));
  const sealed = new Map<string, Uint8Array>();
  const asks = { n: 0, refuse: false };
  // (asking by itself, as much as a read of what is sealed: each is a prompt on the person's screen)
  host.secureSet = (key: string, value: Uint8Array) => Effect.sync(() => void sealed.set(key, value));
  host.secureGet = (key: string, opts: { user: boolean; reason?: string }) => {
    if (opts.user) asks.n++;
    return asks.refuse ? Effect.fail(new HostError("user_cancelled")) : Effect.succeed(sealed.get(key) ?? null);
  };
  host.secureAsk = () => Effect.sync(() => void asks.n++);
  const runner = new Runner(host.time.clock);
  // (how often it tells its lock changed: each time, the stations that refused it are asked again)
  const told = { n: 0 };
  // (the key it signs workspaces' locks with: none until a test gives it one)
  const signs = { key: null as string | null };
  const lock = new PersonalLock({ host, runner, cloud: c.call, device: () => Effect.succeed(id), label: () => name, changed: () => void told.n++, signKey: () => signs.key, ...(at ? { stations: at.env } : {}) });
  return { host, runner, lock, asks, id, told, signs };
}

const body = (over: Record<string, unknown> = {}) => ({ station: STATION, request: "p1", session: "sess", chat: "chat", scope: "hour" as const, exp: 2_000_000_000, ...over });
const grantOf = (signed: unknown) => ({ id: "p1", session: "sess", chat: "chat", scope: "hour", status: "granted", exp: 2_000_000_000, at: 1, signed });
const NOW = 1_800_000_000;

test("the first signature begins the lock; it asks the person and signs what holds on a device on it", async () => {
  const c = cloud();
  const a = device(c, "a");
  try {
    assert.equal(a.lock.standing(SUB), "none");
    const signed = await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    assert.equal(a.lock.standing(SUB), "member");
    assert.equal(a.asks.n, 1, "the person is asked once, though the key is made and used");
    assert.equal(c.kept.entries.length, 1);
    const { devices } = a.lock.chain(SUB)!;
    assert.equal(grantHolds(grantOf(signed), STATION, SUB, devices, NOW), 2_000_000_000);
    // Each use asks again.
    const before = a.asks.n;
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    assert.equal(a.asks.n, before + 1);
    // Refused at the prompt: nothing is signed.
    a.asks.refuse = true;
    await assert.rejects(a.runner.run(a.lock.signGrant(SUB, body(), "why")));
  } finally {
    a.runner.shutdown();
  }
});

test("an entry the person signs waits out the cloud's too many requests, and is taken once it answers", async () => {
  const c = cloud();
  const a = device(c, "a");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    // The account's budget used up: the next two writes answered 429, then taken.
    c.say.limited = 2;
    const out: unknown[] = [];
    a.runner.fork(Effect.map(Effect.result(a.lock.removeDevice(SUB, "ed25519:" + "22".repeat(32), "why")), (r) => out.push(r)));
    for (let i = 0; i < 40 && out.length === 0; i++) await a.host.time.pass(1000, 100);
    assert.equal((out[0] as { _tag: string })?._tag, "Success", JSON.stringify(out));
    assert.equal(c.say.limited, -1, "tried again until the cloud took it");
    assert.equal(c.kept.entries.at(-1)?.kind, "device.remove");
  } finally {
    a.runner.shutdown();
  }
});

test("a person's devices read and bring their lock at their stations, the cloud not waited on", async () => {
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  const b = device(c, "b", st);
  try {
    // Begun at the stations (the cloud told too, for the devices from before, and not waited on: it is down).
    c.say.down = true;
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    assert.equal(a.lock.standing(SUB), "member");
    assert.deepEqual([...st.kept.values()].map((ch) => ch.length), [1]);
    // A grant is signed on what its own station keeps: the person's other stations are not read first (one offline held
    // a read of them all, and the fingerprint asked after it, until it timed out).
    assert.deepEqual(st.say.at, [STATION]);
    // A device let in, the cloud still down: brought to the stations, and b reads it there.
    const bKey = await b.runner.run(b.lock.makeKey());
    const whole = await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: b.id, label: "b" }, "why"));
    assert.deepEqual([...st.kept.values()].map((ch) => ch.length), [2]);
    await b.runner.run(b.lock.refresh(SUB));
    assert.deepEqual(b.lock.approvers(SUB).map((d) => d.label), ["a"]);
    await b.runner.run(b.lock.joined(SUB, whole));
    assert.equal(b.lock.standing(SUB), "member");
    // b lets another in; a reads that of the stations.
    const other = (n: string) => ({ key: `ed25519:${n.repeat(32)}`, id: n.repeat(32), label: n });
    await b.runner.run(b.lock.addDevice(SUB, other("22"), "why"));
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.entries(SUB).length, 3);
    // a, behind (it did not read since), signs at odds with what the stations keep: refused there, its entry lost its
    // place; the stations read, it is signed again after b's, its seed in hand (personal-lock-signs-again.test.ts).
    await b.runner.run(b.lock.addDevice(SUB, other("33"), "why"));
    const out = await a.runner.run(Effect.result(a.lock.addDevice(SUB, other("44"), "why")));
    assert.equal(out._tag, "Success", JSON.stringify(out));
    assert.deepEqual(a.lock.entries(SUB).slice(3).map((e) => (e.body as { key: string }).key), [other("33").key, other("44").key], "after b's");
    // None of the stations reached: the cloud is what it is read of and brought to, as before.
    c.say.down = false;
    st.say.up = false;
    const asked = c.say.asked;
    await a.runner.run(a.lock.refresh(SUB));
    assert.ok(c.say.asked > asked);
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("a station behind on its person's lock, read alone, is brought it: the lock is not taken for one begun anew elsewhere", async () => {
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const other = (n: string) => ({ key: `ed25519:${n.repeat(32)}`, id: n.repeat(32), label: n });
    await a.runner.run(a.lock.addDevice(SUB, other("22"), "why"));
    assert.equal(a.lock.entries(SUB).length, 2);
    assert.equal(a.lock.standing(SUB), "member");
    // The one station reached now is one that was away as the device was let in: it keeps the lock as far as its first
    // entry. Its link opens, and it alone is read.
    for (const [k, ch] of [...st.kept]) st.kept.set(k, ch.slice(0, 1));
    const brought = st.say.brought;
    await a.runner.run(a.lock.refresh(SUB, STATION));
    assert.equal(a.lock.standing(SUB), "member");
    assert.equal(a.lock.entries(SUB).length, 2);
    // (and it is brought what it lacks, as one that kept none is)
    assert.ok(st.say.brought > brought, "the station behind was brought the lock");
    assert.deepEqual([...st.kept.values()].map((ch) => ch.length), [2]);
    // The cloud behind the same way (it is told each entry and not waited on), and no station reached: read of it, the
    // lock is the one pinned still, and the cloud is brought what it lacks.
    c.kept.entries = c.kept.entries.slice(0, 1);
    st.say.up = false;
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.standing(SUB), "member");
    assert.equal(a.lock.entries(SUB).length, 2);
    assert.equal(c.kept.entries.length, 2);
  } finally {
    a.runner.shutdown();
  }
});

test("a new device refused by every station finds who may let it in of what their refusals told, not the cloud", async () => {
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  const n = device(c, "n", st);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    c.say.down = true;
    // Read once (nothing pinned here, the stations refusing it: none said), then told by a refusal.
    st.say.up = false;
    await n.runner.run(Effect.result(n.lock.refresh(SUB)));
    await n.runner.run(n.lock.heardFrom(SUB, [...st.kept.values()]));
    assert.deepEqual(n.lock.approvers(SUB).map((d) => d.label), ["a"]);
    assert.equal(n.lock.standing(SUB), "outside");
    // Each refusal tells the same again: not told as a change, or the stations would be asked again at once, endlessly.
    const told = n.told.n;
    await n.runner.run(n.lock.heardFrom(SUB, [...st.kept.values()]));
    await n.runner.run(n.lock.heardFrom(SUB, [...st.kept.values()]));
    assert.equal(n.told.n, told);
    // What grew is.
    st.say.up = true;
    await a.runner.run(a.lock.addDevice(SUB, { key: `ed25519:${"22".repeat(32)}`, id: "22".repeat(32), label: "22" }, "why"));
    await n.runner.run(n.lock.heardFrom(SUB, [...st.kept.values()]));
    assert.equal(n.told.n, told + 1);
  } finally {
    a.runner.shutdown();
    n.runner.shutdown();
  }
});

test("a grant holds only for what was signed, by a key on the lock, in its time, for this person", async () => {
  const c = cloud();
  const a = device(c, "a");
  const b = device(cloud(), "b");
  try {
    const signed = await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const stranger = await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    const { devices } = a.lock.chain(SUB)!;
    const holds = (g: unknown, station = STATION, sub = SUB, now = NOW) => grantHolds(g, station, sub, devices, now);
    assert.equal(holds(grantOf(signed)), 2_000_000_000);
    assert.equal(holds(grantOf(undefined)), null, "a station's word alone");
    assert.equal(holds(grantOf(stranger)), null, "a key off the lock (a stolen login's new device)");
    assert.equal(holds({ ...grantOf(signed), id: "p2" }), null, "another request");
    assert.equal(holds({ ...grantOf(signed), session: "other" }), null, "another chat's agent");
    assert.equal(holds({ ...grantOf(signed), chat: "other" }), null, "another chat");
    assert.equal(holds({ ...grantOf(signed), scope: "chat" }), null, "longer than allowed");
    assert.equal(holds(grantOf(signed), "ws/other"), null, "another station");
    assert.equal(holds(grantOf(signed), STATION, "s2"), null, "another person's");
    assert.equal(holds(grantOf(signed), STATION, SUB, 2_000_000_001), null, "past its time");
    const s = signed as { body: { exp: number } };
    assert.equal(holds(grantOf({ ...s, body: { ...s.body, exp: 2_100_000_000 } })), null, "its end moved");
    const t = signed as { sig: { key: string; sig: string } };
    const flipped = (t.sig.sig[0] === "0" ? "1" : "0") + t.sig.sig.slice(1);
    assert.equal(holds(grantOf({ ...t, sig: { ...t.sig, sig: flipped } })), null, "its signature changed, the right one checked before");
    assert.equal(holds(grantOf(signed)), 2_000_000_000, "and the right one still holds");
    // An hour unused or eight hours (2026-11-10): signed as such, held as such, and no other.
    const idle = await a.runner.run(a.lock.signGrant(SUB, body({ scope: "idle" }), "why"));
    assert.equal(holds({ ...grantOf(idle), scope: "idle" }), 2_000_000_000);
    assert.equal(holds({ ...grantOf(idle), scope: "eight" }), null, "another length");
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("a lock's entries and grants checked on this device are not checked again as the app starts", async () => {
  // Each start checked every entry and grant again in Hermes, on the core's one thread, before what the first page waits
  // for (0.1.7684, 2026-11-08).
  const kept = new Map<string, unknown>();
  forgetVerifiedHere();
  keepVerified({ get: (k) => kept.get(k), put: (k, ok) => void kept.set(k, ok) });
  const c = cloud();
  const a = device(c, "a");
  try {
    const before = verifies.count;
    const signed = await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    assert.ok(checkChain([...c.kept.entries], SUB) !== null);
    const { devices } = a.lock.chain(SUB)!;
    assert.equal(grantHolds(grantOf(signed), STATION, SUB, devices, NOW), 2_000_000_000);
    const checked = verifies.count - before;
    assert.ok(checked > 0);
    // the app started anew: what this run found is gone, what is kept answers
    forgetVerifiedHere();
    assert.ok(checkChain([...c.kept.entries], SUB) !== null);
    assert.equal(grantHolds(grantOf(signed), STATION, SUB, devices, NOW), 2_000_000_000);
    assert.equal(verifies.count - before, checked, "checked once");
  } finally {
    keepVerified(null);
    a.runner.shutdown();
  }
});

test("a chain holds only as signed by a device on it; a device off it signs no more", async () => {
  const c = cloud();
  const a = device(c, "a");
  const b = device(c, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const bKey = await b.runner.run(b.lock.makeKey());
    await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "bb".repeat(32), label: "b" }, "why"));
    assert.equal(a.lock.chain(SUB)!.devices.size, 2);
    assert.notEqual(checkChain(c.kept.entries, SUB), null);
    assert.equal(checkChain(c.kept.entries, "s2"), null, "another person's");
    const tampered = c.kept.entries.map((e, i) => (i === 1 ? { ...e, body: { key: "ed25519:" + "22".repeat(32), id: "cc".repeat(32), label: "x" } } : e));
    assert.equal(checkChain(tampered, SUB), null, "an entry changed");
    assert.equal(checkChain(c.kept.entries.slice(1), SUB), null, "no genesis");

    await b.runner.run(b.lock.refresh(SUB));
    assert.equal(b.lock.standing(SUB), "outside", "only the cloud's word that it is on it: not pinned");
    await b.runner.run(b.lock.joined(SUB, c.kept.entries));
    assert.equal(b.lock.standing(SUB), "member");

    const aKey = await a.runner.run(a.lock.makeKey());
    await b.runner.run(b.lock.removeDevice(SUB, aKey, "why"));
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.standing(SUB), "outside", "taken off");
    await assert.rejects(a.runner.run(a.lock.signGrant(SUB, body(), "why")), /./);
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("a chain with web devices and a workspace's commitments is taken as it is; one of today as before", () => {
  // (rules/src/lock/person.mbt: `web {id, label, exp}`, `web.remove {id}`, `ws {t, h}`, signed by a device on the log;
  // nothing signs them yet, every part takes them from the rules' build on)
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const key = `ed25519:${(publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(-32).toString("hex")}`;
  const chain: Entry[] = [];
  const add = (kind: string, body: unknown) => {
    const last = chain[chain.length - 1];
    const e = { v: 1, ws: `person:${SUB}`, seq: chain.length, prev: last ? entryHash(last) : null, at: 1000, kind, body } as Omit<Entry, "sig">;
    chain.push({ ...e, sig: { key, alg: "Ed25519", sig: nodeSign(null, Buffer.from(signedBytes(entryHash(e as Entry))), privateKey).toString("hex") } } as Entry);
  };
  add("genesis", { sub: SUB, device: { key, id: "aa".repeat(32), label: "first" } });
  const today = checkChain([...chain], SUB);
  assert.deepEqual([...today!.devices.keys()], [key]);
  add("web", { id: "bb".repeat(32), label: "a browser", exp: 1000 + 31 * 86400 });
  add("ws", { t: "cc".repeat(32), h: "dd".repeat(32) });
  add("web.remove", { id: "bb".repeat(32) });
  const now = checkChain([...chain], SUB);
  assert.notEqual(now, null, "taken");
  assert.deepEqual([...now!.devices.keys()], [key], "its devices as they were");
  assert.equal(now!.hash, entryHash(chain[3]!));
  add("ws.member", { ws: "w1", sub: "dan", lock: "ee".repeat(32), role: "member" });
  assert.equal(checkChain([...chain], SUB), null, "round three's statements in the clear: refused");
});

test("a lock the cloud says began anew is not followed by itself", async () => {
  const c = cloud();
  const a = device(c, "a");
  const forged = device(cloud(), "x");
  try {
    const signed = await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const theirs = await forged.runner.run(forged.lock.signGrant(SUB, body(), "why"));
    // The cloud hands out a chain of the attacker's own.
    const other = cloud();
    const forger = device(other, "x");
    await forger.runner.run(forger.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = other.kept.entries;
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.standing(SUB), "replaced");
    const { devices } = a.lock.chain(SUB)!;
    assert.equal(grantHolds(grantOf(signed), STATION, SUB, devices, NOW), 2_000_000_000, "what was pinned still holds");
    assert.equal(grantHolds(grantOf(theirs), STATION, SUB, devices, NOW), null, "the new one's signatures do not");
    await assert.rejects(a.runner.run(a.lock.signGrant(SUB, body(), "why")), /./);
    forger.runner.shutdown();
  } finally {
    a.runner.shutdown();
    forged.runner.shutdown();
  }
});

/// A phone's Adb over a station that says what it is told.
function phone(env: Partial<ConstructorParameters<typeof Adb>[0]>) {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const link = { adb: () => Effect.succeed({ status: 200, body: { take: Effect.succeed(null) } }) };
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(link) } as unknown as Mesh;
  const adb = new Adb({ ...personalStub(), host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => true, ...env });
  return { host, runner, adb };
}

test("the phone lends on a signed grant alone, and no more once it is taken back", async () => {
  const c = cloud();
  const a = device(c, "a");
  const signed = await a.runner.run(a.lock.signGrant(SUB, body({ exp: 4_000_000_000 }), "why"));
  const p = phone({ personal: a.lock, subOf: () => SUB, subs: () => [{ sub: SUB, email: "a@x" }] });
  const grant = (id: string, s: unknown) => ({ ...grantOf(s), id, exp: 4_000_000_000 });
  const STATION_ID = STATION;
  try {
    p.adb.heard(STATION_ID, grant("forged", undefined));
    assert.deepEqual(p.adb.wanted(), [], "a station's word alone lends nothing");
    assert.equal(p.adb.grants().find((g) => g.id === "forged")?.held, false, "and it says so");
    p.adb.heard(STATION_ID, grant("p1", signed));
    assert.deepEqual(p.adb.wanted(), [STATION_ID]);
    assert.equal(p.adb.grants().find((g) => g.id === "p1")?.signed, undefined, "the signature is not the page's");
    await p.runner.run(Effect.ignore(p.adb.run({ kind: "revoke", station: STATION_ID, request: "p1" })));
    p.adb.heard(STATION_ID, grant("p1", signed));
    assert.deepEqual(p.adb.wanted(), [], "a station saying it again lends nothing");
  } finally {
    p.runner.shutdown();
    a.runner.shutdown();
  }
});

test("a phone started anew reads the lock it pinned, and lends for its grants before any station is reached", async () => {
  const c = cloud();
  const a = device(c, "a");
  const signed = await a.runner.run(a.lock.signGrant(SUB, body({ exp: 4_000_000_000 }), "why"));
  // The same device's storage, the process gone and back, the cloud out of reach.
  const again = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
  const p = phone({ personal: again, subOf: () => SUB, subs: () => [{ sub: SUB, email: "a@x" }] });
  try {
    p.adb.heard(STATION, { ...grantOf(signed), exp: 4_000_000_000 });
    assert.deepEqual(p.adb.wanted(), [], "not read yet");
    p.adb.accountsKnown();
    await p.host.settle();
    await a.host.settle();
    assert.deepEqual(p.adb.wanted(), [STATION]);
  } finally {
    p.runner.shutdown();
    a.runner.shutdown();
  }
});

test("a lock begun anew, the key there already, asks the person once", async () => {
  const c = cloud();
  const a = device(c, "a");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const before = a.asks.n;
    await a.runner.run(a.lock.restart(SUB, "why"));
    assert.equal(a.asks.n, before + 1);
    assert.equal(c.kept.entries.length, 1);
    assert.equal(a.lock.standing(SUB), "member");
  } finally {
    a.runner.shutdown();
  }
});

test("grants from before signatures are signed at one go, the person asked once, and lend once a station has them", async () => {
  const c = cloud();
  const a = device(c, "a");
  await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
  const said: Record<string, unknown>[] = [];
  const answer = (o: unknown) => {
    let sent = false;
    const bytes = new TextEncoder().encode(JSON.stringify(o));
    return { status: 200, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } };
  };
  const old = (id: string, chat: string) => ({ id, session: `s-${id}`, chat, scope: "hour", status: "granted", exp: 4_000_000_000, at: 1 });
  const link = {
    adb: (_h: unknown, ask: Record<string, unknown>) => Effect.sync(() => {
      said.push(ask);
      if (ask.op === "grants") return answer({ grants: [old("g1", "c1"), old("g2", "c2")], signs: true });
      return answer({ request: { ...old(ask.request as string, ask.request === "g1" ? "c1" : "c2"), signed: ask.signed } });
    }),
  };
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(link) } as unknown as Mesh;
  const adb = new Adb({ ...personalStub(), personal: a.lock, subOf: () => SUB, subs: () => [{ sub: SUB, email: "a@x" }], host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => true });
  try {
    await runner.run(adb.readGrants(STATION));
    assert.deepEqual(adb.wanted(), [], "unsigned: lends nothing yet");
    assert.equal((adb.value() as { toConfirm: number }).toConfirm, 2);
    const before = a.asks.n;
    await runner.run(adb.run({ kind: "personalConfirm" }));
    assert.equal(a.asks.n, before + 1, "asked once for both");
    assert.equal(said.filter((x) => x.op === "sign").length, 2);
    assert.deepEqual(adb.wanted(), [STATION]);
    assert.equal((adb.value() as { toConfirm: number }).toConfirm, 0);
  } finally {
    runner.shutdown();
    a.runner.shutdown();
  }
});

test("each device's entry on its person's lock says the key it signs workspaces' locks with; a device with another says it again, once, the next time its key is in hand", async () => {
  // (a device let in where no workspace bound the person's lock, or before one did, signed nowhere: no workspace's lock
  // held its key, and the person's did not say it; the locks' end to end, round 12, 2026-11-10)
  const c = cloud();
  const a = device(c, "a");
  const b = device(c, "b");
  const A1 = "ed25519:" + "a1".repeat(32), A2 = "ed25519:" + "a2".repeat(32), B1 = "ed25519:" + "b1".repeat(32);
  const C = { key: "ed25519:" + "cc".repeat(32), id: "cc".repeat(32), label: "c" };
  const C1 = "ed25519:" + "c1".repeat(32), C2 = "ed25519:" + "c2".repeat(32);
  // deno-lint-ignore no-explicit-any
  const bodyOf = (e: Entry | undefined) => e?.body as any;
  try {
    a.signs.key = A1;
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    assert.equal(bodyOf(c.kept.entries[0]).device.sign_key, A1, "the genesis says it");
    const bKey = await b.runner.run(b.lock.makeKey());
    await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: b.id, label: "b", sign_key: B1 }, "why"));
    assert.equal(bodyOf(c.kept.entries[1]).sign_key, B1, "and the entry that puts one on");
    assert.deepEqual([...a.lock.signKeys(SUB)], [[a.id, { sign_key: A1, label: "a" }], [b.id, { sign_key: B1, label: "b" }]], "by the device's id");
    // Said again with another: the last one counts. Taken off: none.
    await a.runner.run(a.lock.addDevice(SUB, { ...C, sign_key: C1 }, "why"));
    await a.runner.run(a.lock.addDevice(SUB, { ...C, sign_key: C2 }, "why"));
    assert.equal(a.lock.signKeys(SUB).get(C.id)?.sign_key, C2);
    await a.runner.run(a.lock.removeDevice(SUB, C.key, "why"));
    assert.equal(a.lock.signKeys(SUB).has(C.id), false, "off the lock");
    // One not of the form is none, though the device is on the lock.
    await a.runner.run(a.lock.addDevice(SUB, { ...C, sign_key: "ed25519:" + "CC".repeat(32) }, "why"));
    assert.ok(a.lock.chain(SUB)!.devices.has(C.key));
    assert.equal(a.lock.signKeys(SUB).has(C.id), false, "not of the form");
    // This device signs with another key now: said again on the next act its key is in hand for, the person asked no
    // more than for that act, and not again after.
    a.signs.key = A2;
    const length = c.kept.entries.length;
    const asked = a.asks.n;
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    assert.equal(a.asks.n, asked + 1);
    assert.equal(c.kept.entries.length, length + 1);
    assert.deepEqual([c.kept.entries[length]!.kind, bodyOf(c.kept.entries[length])], ["device", { key: bodyOf(c.kept.entries[0]).device.key, id: a.id, label: "a", sign_key: A2 }]);
    assert.equal(a.lock.signKeys(SUB).get(a.id)?.sign_key, A2);
    assert.notEqual(checkChain(c.kept.entries, SUB), null, "as the rules take it");
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await a.runner.run(a.lock.signGrants(SUB, [body()], "why"));
    assert.equal(c.kept.entries.length, length + 1, "not again");
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("a device that began its person's lock anew while the stations refused it does not take the chain it left, which they keep still, for one begun elsewhere", async () => {
  // (every device lost, the person began again on a new one; let in later, it read the old chain at the stations and
  // warned of a theft, and the lock was never bound; the locks' end to end, round 12, 2026-11-10)
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  const k = device(c, "k", st);
  const z = device(c, "z", st);
  const rootOf = (chain: Entry[]) => JSON.stringify(chain[0]);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const old = a.lock.entries(SUB);
    // The new device, refused by every station, sees the old lock (outside it) and begins anew: to the cloud alone.
    st.say.up = false;
    await k.runner.run(k.lock.refresh(SUB));
    assert.equal(k.lock.standing(SUB), "outside");
    await k.runner.run(k.lock.restart(SUB, "why"));
    const mine = k.lock.entries(SUB);
    assert.equal(rootOf(c.kept.entries), rootOf(mine));
    assert.deepEqual([...st.kept.values()], [old], "the stations keep only the old one");
    // Let in: the stations answer with the old chain alone. Its own lock still, and the stations brought the new one.
    st.say.up = true;
    await k.runner.run(k.lock.refresh(SUB));
    assert.equal(k.lock.standing(SUB), "member");
    assert.deepEqual(st.kept.get(rootOf(mine)), mine, "brought to the stations");
    await k.runner.run(k.lock.heardFrom(SUB, [old]));
    assert.equal(k.lock.standing(SUB), "member", "nor told by a refusal");
    // The core started again over the same storage, a station that keeps only the old chain: the same.
    st.kept.delete(rootOf(mine));
    const again = new PersonalLock({ host: k.host, runner: k.runner, cloud: c.call, device: () => Effect.succeed(k.id), label: () => "k", changed: () => {}, stations: st.env });
    await k.runner.run(again.refresh(SUB));
    assert.equal(again.standing(SUB), "member");
    assert.deepEqual(st.kept.get(rootOf(mine)), mine);
    // A lock another device began anew later is not one this device left: begun elsewhere.
    await z.runner.run(z.lock.restart(SUB, "why"));
    st.kept.delete(rootOf(mine));
    await k.runner.run(again.refresh(SUB));
    assert.equal(again.standing(SUB), "replaced");
  } finally {
    a.runner.shutdown();
    k.runner.shutdown();
    z.runner.shutdown();
  }
});

test("a device that began anew the lock it had pinned, while the stations could not be asked, brings them the new one", async () => {
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const old = a.lock.entries(SUB);
    st.say.up = false;
    // (a minute on: begun again in the same second, the same device's genesis would be the same)
    await a.host.time.pass(60_000);
    await a.runner.run(a.lock.restart(SUB, "why"));
    const mine = a.lock.entries(SUB);
    assert.notDeepEqual(mine, old);
    st.say.up = true;
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.standing(SUB), "member");
    assert.deepEqual(st.kept.get(JSON.stringify(mine[0])), mine);
  } finally {
    a.runner.shutdown();
  }
});

const kinds = (chain: Entry[]) => JSON.stringify(chain.map((e) => [e.seq, e.kind]));

test("an entry a station took, read of it again before its answer came, is on the lock once: the new device takes the lock it is brought", async () => {
  const c = cloud();
  const st = stations();
  const a = device(c, "a", st);
  const n = device(c, "n", st);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    // The station takes the new device's entry; a read of it (told the lock changed on its event stream) is answered
    // and taken before its answer to the entry is (2026-11-12: a real station's run, the new device told it was not
    // let in).
    st.say.taking = () => a.lock.refresh(SUB);
    const nKey = await n.runner.run(n.lock.makeKey());
    const whole = await a.runner.run(a.lock.addDevice(SUB, { key: nKey, id: n.id, label: "n" }, "why"));
    assert.equal(st.say.taking, null, "the read landed while the entry was being brought");
    assert.notEqual(checkChain(whole, SUB), null, `the lock brought to the new device holds: ${kinds(whole)}`);
    assert.equal(kinds(whole), kinds([...st.kept.values()][0]!), "the entry is on it once, as the station keeps it");
    assert.deepEqual(a.lock.entries(SUB), whole);
    assert.equal(a.lock.standing(SUB), "member");
    await n.runner.run(n.lock.joined(SUB, whole));
    assert.equal(n.lock.standing(SUB), "member");
  } finally {
    a.runner.shutdown();
    n.runner.shutdown();
  }
});

// Which of the two entries keeps the place is the rules' fork choice (src/lock-keep.ts), the stations' too: here by its
// second step, a removal winning at equal weight (2026-11-12; before, any other entry at the place refused this one,
// and the case was built of two device entries, whose order is the two signers' tie values).
for (const lost of [true, false])
  test(`an entry a station took, another device's entry heard at its place before its answer came: ${lost ? "refused as a station's 409 is where it loses, the lock pinned holding" : "pinned where it wins by the rules, the other kept aside"}`, async () => {
    const c = cloud();
    const st = stations();
    // (b's stations: another of the person's, that took b's entry where a's station took a's)
    const st2 = stations();
    const a = device(c, "a", st);
    const b = device(c, "b", st2);
    const other = (n: string) => ({ key: `ed25519:${n.repeat(32)}`, id: n.repeat(32), label: n });
    try {
      c.say.down = true;
      await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
      await a.runner.run(a.lock.addDevice(SUB, other("22"), "why"));
      const bKey = await b.runner.run(b.lock.makeKey());
      const whole = await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: b.id, label: "b" }, "why"));
      for (const [k, ch] of st.kept) st2.kept.set(k, ch);
      await b.runner.run(b.lock.joined(SUB, whole));
      // b's entry: the removal of 22 (it wins) where a's is a device put on; else the other way round.
      if (lost) await b.runner.run(b.lock.removeDevice(SUB, other("22").key, "why"));
      else await b.runner.run(b.lock.addDevice(SUB, other("33"), "why"));
      const theirs = [...st2.kept.values()][0]!;
      st.say.taking = () => a.lock.heardFrom(SUB, [theirs]);
      const out = await a.runner.run(Effect.result(lost ? Effect.asVoid(a.lock.addDevice(SUB, other("44"), "why")) : Effect.asVoid(a.lock.removeDevice(SUB, other("22").key, "why"))));
      assert.equal(st.say.taking, null, "the other chain was heard while the entry was being brought");
      const pinned = a.lock.entries(SUB);
      assert.notEqual(checkChain(pinned, SUB), null, `the lock pinned holds: ${kinds(pinned)}`);
      if (lost) {
        assert.deepEqual(pinned, theirs, "the chain heard is the one pinned, the entry that lost its place not on it");
        assert.equal(out._tag === "Failure" && out.failure.code, "lock_refused", JSON.stringify(out));
      } else {
        assert.equal(out._tag, "Success", JSON.stringify(out));
        assert.deepEqual(pinned.slice(0, 3), theirs.slice(0, 3));
        assert.equal(pinned.length, 4, `the entry once: ${kinds(pinned)}`);
        assert.equal(pinned[3]!.kind, "device.remove");
        assert.notEqual(entryHash(pinned[3]!), entryHash(theirs[3]!));
      }
    } finally {
      a.runner.shutdown();
      b.runner.shutdown();
    }
  });
