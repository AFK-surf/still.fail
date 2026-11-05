// A person's own lock (src/personal-lock.ts, docs/personal-lock.md): only a device on it writes it, each use of its key
// asks the person, and a phone lends only on a grant signed by a device on the lock it pinned: not on a station's word,
// a signature for something else, a key off the lock, one past its time, or one taken back here.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Adb } from "../src/adb.ts";
import { CoreError, HostError } from "../src/error.ts";
import type { Entry } from "../src/lock.ts";
import type { Mesh } from "../src/mesh.ts";
import { PersonalLock, checkChain, grantHolds } from "../src/personal-lock.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { personalStub } from "./adb-personal-stub.ts";

const SUB = "s1";
const STATION = "ws/st";

/// A cloud that keeps one chain, as cloud/src/personal-lock.ts does.
function cloud() {
  const kept = { entries: [] as Entry[] };
  return {
    kept,
    call: (_sub: string, method: string, _path: string, body: unknown) =>
      Effect.sync(() => {
        if (method === "GET") return { entries: kept.entries };
        const adding = (body as { entries: Entry[] }).entries;
        kept.entries = adding[0]!.seq === 0 ? adding : [...kept.entries.slice(0, adding[0]!.seq), ...adding];
        return { entries: kept.entries };
      }) as Effect.Effect<unknown, CoreError>,
  };
}

/// A device: its host keeps what is sealed with `user: true` apart, each read of it counted, as asking the person.
function device(c: ReturnType<typeof cloud>, id: string) {
  const host = new FakeHost();
  host.appKeys = true;
  // (each device's keys its own: FakeHost's are the same for all)
  host.randomBytes = (b: Uint8Array) => void b.fill(id.charCodeAt(0));
  const sealed = new Map<string, Uint8Array>();
  const asks = { n: 0, refuse: false };
  host.secureSet = (key: string, value: Uint8Array) => Effect.sync(() => void sealed.set(key, value));
  host.secureGet = (key: string, opts: { user: boolean; reason?: string }) => {
    if (opts.user) asks.n++;
    return asks.refuse ? Effect.fail(new HostError("user_cancelled")) : Effect.succeed(sealed.get(key) ?? null);
  };
  host.secureAsk = () => Effect.void;
  const runner = new Runner(host.time.clock);
  const lock = new PersonalLock({ host, runner, cloud: c.call, device: () => Effect.succeed(id), label: () => id, changed: () => {} });
  return { host, runner, lock, asks };
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
    assert.ok(a.asks.n >= 1, "the person was asked");
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
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("a chain holds only as signed by a device on it; a device off it signs no more", async () => {
  const c = cloud();
  const a = device(c, "a");
  const b = device(c, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const bKey = await b.runner.run(b.lock.makeKey("why"));
    await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "b", label: "b" }, "why"));
    assert.equal(a.lock.chain(SUB)!.devices.size, 2);
    assert.notEqual(checkChain(c.kept.entries, SUB), null);
    assert.equal(checkChain(c.kept.entries, "s2"), null, "another person's");
    const tampered = c.kept.entries.map((e, i) => (i === 1 ? { ...e, body: { key: "ed25519:" + "22".repeat(32), id: "x", label: "x" } } : e));
    assert.equal(checkChain(tampered, SUB), null, "an entry changed");
    assert.equal(checkChain(c.kept.entries.slice(1), SUB), null, "no genesis");

    await b.runner.run(b.lock.refresh(SUB));
    assert.equal(b.lock.standing(SUB), "outside", "only the cloud's word that it is on it: not pinned");
    await b.runner.run(b.lock.joined(SUB, c.kept.entries));
    assert.equal(b.lock.standing(SUB), "member");

    const aKey = await a.runner.run(a.lock.makeKey("why"));
    await b.runner.run(b.lock.removeDevice(SUB, aKey, "why"));
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.standing(SUB), "outside", "taken off");
    await assert.rejects(a.runner.run(a.lock.signGrant(SUB, body(), "why")), /./);
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
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
  const adb = new Adb({ ...personalStub(), holds: grantHolds, host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => true, ...env });
  return { host, runner, adb };
}

test("the phone lends on a signed grant alone, and no more once it is taken back", async () => {
  const c = cloud();
  const a = device(c, "a");
  const signed = await a.runner.run(a.lock.signGrant(SUB, body({ exp: 4_000_000_000 }), "why"));
  const p = phone({ personal: a.lock, subOf: () => SUB, sub: () => SUB });
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
