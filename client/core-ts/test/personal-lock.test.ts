// A person's own lock (src/personal-lock.ts, docs/personal-lock.md): only a device on it writes it, each use of its key
// asks the person, and a phone lends only on a grant signed by a device on the lock it pinned: not on a station's word,
// a signature for something else, a key off the lock, one past its time, or one taken back here.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Deferred, Effect } from "effect";
import { Adb } from "../src/adb.ts";
import { CoreError, HostError } from "../src/error.ts";
import { entryHash, signedBytes, type Entry } from "../src/lock.ts";
import type { Mesh } from "../src/mesh.ts";
import { PersonalLock, checkChain, grantHolds } from "../src/personal-lock.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { hex } from "../src/util.ts";
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
function device(c: ReturnType<typeof cloud>, name: string) {
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
  const lock = new PersonalLock({ host, runner, cloud: c.call, device: () => Effect.succeed(id), label: () => name, changed: () => {} });
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

test("a long pinned lock restores to an empty cloud within its request limit, including after an interruption", async () => {
  const c = cloud();
  let sent = 0, restoreCalls = 0, interruptAfter: number | null = null, oldCloud = false, rateLimitNext = false, rateLimited = 0;
  let replacement: Entry[] | null = null;
  const limited = {
    ...c,
    call: (sub: string, method: string, path: string, value: unknown) => {
      if (method === "POST") {
        if (oldCloud && path.endsWith("/append")) return Effect.fail(new CoreError("not_found", "cloud has no guarded restore"));
        if (new TextEncoder().encode(JSON.stringify(value)).length > (path.endsWith("/append") ? 256 * 1024 : 8192)) return Effect.fail(new CoreError("too_large", "cloud request is too large"));
        if (path.endsWith("/append")) {
          restoreCalls++;
          if (rateLimitNext) { rateLimitNext = false; rateLimited++; return Effect.fail(new CoreError("rate_limited", "rate limited", 429)); }
        }
        if (replacement !== null) { c.kept.entries = replacement; replacement = null; }
        const expected = (value as { expect?: { length: number; head: string | null } }).expect;
        if (expected) assert.equal(path, "/v1/me/personal-lock/append");
        if (expected && (c.kept.entries.length !== expected.length || (c.kept.entries.length ? entryHash(c.kept.entries.at(-1)!) : null) !== expected.head)) return Effect.fail(new CoreError("conflict", "the cloud lock changed"));
        if (interruptAfter !== null && sent++ >= interruptAfter) return Effect.fail(new CoreError("offline", "offline"));
      }
      return c.call(sub, method, path, value);
    },
  };
  const a = device(limited, "a");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const key = await a.runner.run(a.lock.makeKey());
    const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
    assert.ok(seed);
    const pinned = [...c.kept.entries];
    for (let i = 0; i < 90; i++) {
      const unsigned = { v: 1 as const, ws: `person:${SUB}`, seq: pinned.length, prev: entryHash(pinned.at(-1)!), at: 1, kind: "device", body: { key, id: "61".repeat(32), label: `设备${i}${"长".repeat(3000)}` } };
      pinned.push({ ...unsigned, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(unsigned)), seed)) } });
    }
    await a.runner.run(a.lock.joined(SUB, pinned));
    assert.ok(new TextEncoder().encode(JSON.stringify({ entries: pinned })).length > 256 * 1024);
    c.kept.entries = [];
    oldCloud = true;
    await assert.rejects(a.runner.run(a.lock.refresh(SUB)), /guarded restore/);
    assert.deepEqual(c.kept.entries, [], "an old cloud never receives an unguarded restore");
    oldCloud = false;
    await a.runner.run(a.lock.refresh(SUB));
    assert.deepEqual(c.kept.entries, pinned, "the entire verified chain was restored");
    assert.ok(restoreCalls < 120, "restoring a long chain does not exhaust the cloud's per-minute account quota");

    c.kept.entries = [];
    rateLimitNext = true;
    const retry = a.runner.run(a.lock.refresh(SUB));
    for (let i = 0; i < 100 && rateLimited === 0; i++) await a.host.time.pass(10);
    assert.equal(rateLimited, 1);
    await a.host.time.pass(60_000, 1000);
    await retry;
    assert.deepEqual(c.kept.entries, pinned, "a quota response is retried after the cloud's wait");

    c.kept.entries = [];
    sent = 0;
    interruptAfter = 1;
    await assert.rejects(a.runner.run(a.lock.refresh(SUB)), /offline/);
    assert.ok(c.kept.entries.length > 0 && c.kept.entries.length < pinned.length, "the cloud kept the first part");
    interruptAfter = null;
    await a.runner.run(a.lock.refresh(SUB));
    assert.deepEqual(c.kept.entries, pinned, "a retry extends the accepted prefix without losing entries");

    const other = cloud(), b = device(other, "b");
    try {
      await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
      c.kept.entries = [];
      replacement = [...other.kept.entries];
      await assert.rejects(a.runner.run(a.lock.refresh(SUB)), /changed/);
      assert.deepEqual(c.kept.entries, other.kept.entries, "the restore did not replace a concurrently created lock");
    } finally {
      b.runner.shutdown();
    }
  } finally {
    a.runner.shutdown();
  }
});

test("a late local read cannot replace a newer personal lock loaded in parallel", async () => {
  const c = cloud(), a = device(c, "a");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const storageKey = [...a.host.storage.keys()].find((key) => key.startsWith("personal-lock-"))!;
    const old = a.host.storage.get(storageKey)!;
    const ownKey = await a.runner.run(a.lock.makeKey());
    await a.runner.run(a.lock.addDevice(SUB, { key: ownKey, id: "61".repeat(32), label: "new" }, "why"));
    const expected = entryHash(c.kept.entries.at(-1)!);
    const ready = Deferred.makeUnsafe<void>(), read = a.host.storageGet.bind(a.host);
    let first = true;
    a.host.storageGet = (key) => {
      if (key !== storageKey || !first) return read(key);
      first = false;
      return Effect.andThen(Deferred.await(ready), Effect.succeed(old));
    };
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    let finished = false;
    a.runner.fork(Effect.andThen(cold.load(SUB), Effect.sync(() => { finished = true; })));
    await a.host.time.pass(10);
    await a.runner.run(cold.load(SUB));
    Deferred.doneUnsafe(ready, Effect.void);
    await a.host.time.pass(10);
    assert.equal(finished, true);
    assert.equal(cold.chain(SUB)?.hash, expected, "the late old read did not roll the device back");
  } finally { a.runner.shutdown(); }
});

test("a refresh that sees an accepted device before its write returns does not corrupt the pinned lock", async () => {
  const c = cloud(), release = Deferred.makeUnsafe<void>();
  let held = false;
  const delayed = {
    ...c,
    call: (sub: string, method: string, path: string, body: unknown) => {
      const answer = c.call(sub, method, path, body);
      const kind = (body as { entries?: Entry[] } | null)?.entries?.[0]?.kind;
      if (method !== "POST" || kind !== "device") return answer;
      return Effect.flatMap(answer, (result) => Effect.andThen(
        Effect.sync(() => { held = true; }),
        Effect.as(Deferred.await(release), result),
      ));
    },
  };
  const a = device(delayed, "a"), b = device(c, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const bKey = await b.runner.run(b.lock.makeKey());
    const adding = a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "62".repeat(32), label: "b" }, "why"));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true, "the cloud accepted the entry before its response arrives");
    await a.runner.run(a.lock.refresh(SUB));
    Deferred.doneUnsafe(release, Effect.void);
    const joined = await adding;
    assert.deepEqual(joined, c.kept.entries, "the accepted entry is pinned once");
    assert.equal(a.lock.standing(SUB), "member");
    assert.equal(a.lock.chain(SUB)?.devices.has(bKey), true);
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: delayed.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.standing(SUB), "member", "the persisted chain survives restart");
    assert.equal(restarted.chain(SUB)?.hash, entryHash(c.kept.entries.at(-1)!));
    const own = await a.runner.run(restarted.makeKey());
    const next = await a.runner.run(restarted.addDevice(SUB, { key: own, id: "61".repeat(32), label: "a again" }, "why"));
    assert.deepEqual(next, c.kept.entries, "a later append extends the same accepted chain");
    assert.equal(next.length, 3);
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("overlapping refreshes cannot persist an older personal lock after a newer one", async () => {
  const c = cloud(), a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const key = await a.runner.run(a.lock.makeKey());
    const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
    assert.ok(seed);
    const entries = [...c.kept.entries];
    for (let i = 0; i < 2; i++) {
      const unsigned = { v: 1 as const, ws: `person:${SUB}`, seq: entries.length, prev: entryHash(entries.at(-1)!), at: 1, kind: "device", body: { key, id: "61".repeat(32), label: `version ${i}` } };
      entries.push({ ...unsigned, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(unsigned)), seed)) } });
    }
    const set = a.host.storageSet.bind(a.host);
    let held = false;
    a.host.storageSet = (name, value) => {
      if (!name.startsWith("personal-lock-") || held) return set(name, value);
      return Effect.andThen(Effect.sync(() => { held = true; }), Effect.andThen(Deferred.await(release), set(name, value)));
    };
    c.kept.entries = entries.slice(0, 2);
    const older = a.runner.run(a.lock.refresh(SUB));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true, "the first write is still pending");
    c.kept.entries = entries;
    const newer = a.runner.run(a.lock.refresh(SUB));
    await a.host.time.pass(10);
    Deferred.doneUnsafe(release, Effect.void);
    await Promise.all([older, newer]);
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.chain(SUB)?.hash, entryHash(entries.at(-1)!), "restart keeps the newest verified entry");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    a.runner.shutdown();
  }
});

test("a failed personal lock write is retried even when the cloud has not changed", async () => {
  const c = cloud(), a = device(c, "a"), b = device(c, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const bKey = await b.runner.run(b.lock.makeKey());
    const set = a.host.storageSet.bind(a.host);
    let fail = true;
    a.host.storageSet = (name, value) => {
      if (name.startsWith("personal-lock-") && fail) {
        fail = false;
        return Effect.fail(new HostError("storage failed", true));
      }
      return set(name, value);
    };
    await assert.rejects(a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "62".repeat(32), label: "b" }, "why")), /storage failed/);
    assert.equal(c.kept.entries.length, 2, "the cloud had already accepted the entry");
    assert.equal(a.lock.chain(SUB)?.hash, entryHash(c.kept.entries.at(-1)!));
    await a.runner.run(a.lock.refresh(SUB));
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.standing(SUB), "member");
    assert.equal(restarted.chain(SUB)?.hash, entryHash(c.kept.entries.at(-1)!), "the same snapshot is persisted on retry");
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("a late pairing result cannot shorten the same personal lock", async () => {
  const c = cloud(), a = device(c, "a"), b = device(c, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const older = [...c.kept.entries];
    const bKey = await b.runner.run(b.lock.makeKey());
    await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "62".repeat(32), label: "b" }, "why"));
    await a.runner.run(a.lock.joined(SUB, older));
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.chain(SUB)?.hash, entryHash(c.kept.entries.at(-1)!));
    assert.equal(restarted.chain(SUB)?.devices.has(bKey), true);
  } finally {
    a.runner.shutdown();
    b.runner.shutdown();
  }
});

test("an interrupted storage write finishes before a newer personal lock is written", async () => {
  const c = cloud(), a = device(c, "a");
  let finish: (() => void) | undefined;
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const key = await a.runner.run(a.lock.makeKey());
    const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
    assert.ok(seed);
    const entries = [...c.kept.entries];
    for (let i = 0; i < 2; i++) {
      const unsigned = { v: 1 as const, ws: `person:${SUB}`, seq: entries.length, prev: entryHash(entries.at(-1)!), at: 1, kind: "device", body: { key, id: "61".repeat(32), label: `version ${i}` } };
      entries.push({ ...unsigned, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(unsigned)), seed)) } });
    }
    const set = a.host.storageSet.bind(a.host);
    let held = false;
    a.host.storageSet = (name, value) => {
      if (!name.startsWith("personal-lock-") || held) return set(name, value);
      return Effect.tryPromise({
        try: () => new Promise<void>((resolve) => {
          held = true;
          // A host operation can keep writing even after its Effect waiter was interrupted.
          finish = () => { finish = undefined; a.host.storage.set(name, value); resolve(); };
        }),
        catch: (error) => new HostError(String(error)),
      });
    };
    c.kept.entries = entries.slice(0, 2);
    const older = a.runner.fork(a.lock.refresh(SUB));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true);
    a.runner.interrupt(older);
    c.kept.entries = entries;
    const newer = a.runner.run(a.lock.refresh(SUB));
    await a.host.time.pass(10);
    finish!();
    await newer;
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.chain(SUB)?.hash, entryHash(entries.at(-1)!), "the old host write cannot overwrite the newer one");
  } finally {
    finish?.();
    a.runner.shutdown();
  }
});

test("forgetting a personal lock while an append is in flight is not undone by its reply", async () => {
  const c = cloud(), release = Deferred.makeUnsafe<void>();
  let held = false;
  const delayed = {
    ...c,
    call: (sub: string, method: string, path: string, body: unknown) => {
      const answer = c.call(sub, method, path, body);
      const kind = (body as { entries?: Entry[] } | null)?.entries?.[0]?.kind;
      if (method !== "POST" || kind !== "device") return answer;
      return Effect.flatMap(answer, (result) => Effect.andThen(Effect.sync(() => { held = true; }), Effect.as(Deferred.await(release), result)));
    },
  };
  const a = device(delayed, "a"), b = device(c, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const bKey = await b.runner.run(b.lock.makeKey());
    const adding = a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "62".repeat(32), label: "b" }, "why"));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true);
    await a.runner.run(a.lock.forget(SUB, "why"));
    Deferred.doneUnsafe(release, Effect.void);
    await assert.rejects(adding, (error: unknown) => error instanceof CoreError && error.code === "personal_changed");
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.standing(SUB), "none");
    await a.runner.run(restarted.refresh(SUB));
    assert.equal(restarted.standing(SUB), "outside", "the cloud's copy is not pinned without approval");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    a.runner.shutdown();
    b.runner.shutdown();
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
