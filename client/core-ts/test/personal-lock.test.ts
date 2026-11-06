// A person's own lock (src/personal-lock.ts, docs/personal-lock.md): only a device on it writes it, each use of its key
// asks the person, and a phone lends only on a grant signed by a device on the lock it pinned: not on a station's word,
// a signature for something else, a key off the lock, one past its time, or one taken back here.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Deferred, Effect } from "effect";
import { Adb, GRANTS_KEY } from "../src/adb.ts";
import { Core } from "../src/core.ts";
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
    if (!sealed.has(key)) return Effect.succeed(null);
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
    await b.runner.run(b.lock.joined(SUB, c.kept.entries, b.lock.joinGeneration(SUB)));
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

for (const entry of ["open", "sign"] as const) {
  for (const observed of [false, true]) {
    test(`automatic ${entry} cannot replace a concurrently created lock${observed ? " it has heard" : " it has not heard"}`, async () => {
      const c = cloud(), original = c.call;
      c.call = (sub, method, path, value) => {
        if (method === "POST" && path.endsWith("/append")) {
          const expect = (value as { expect?: { length: number; head: string | null } }).expect;
          if (!expect || expect.length !== c.kept.entries.length || expect.head !== (c.kept.entries.length ? entryHash(c.kept.entries.at(-1)!) : null)) {
            return Effect.fail(new CoreError("lock_refused", "the cloud lock changed", 409));
          }
        }
        return original(sub, method, path, value);
      };
      const a = device(c, "a"), b = device(c, "b");
      const release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
      a.host.secureAsk = () => Effect.andThen(Effect.sync(() => reached.resolve()), Deferred.await(release));
      try {
        const starting = entry === "open" ? a.runner.run(a.lock.open(SUB, "why")) : a.runner.run(a.lock.signGrant(SUB, body(), "why"));
        await reached.promise;
        await b.runner.run(b.lock.open(SUB, "why"));
        const existing = [...c.kept.entries];
        if (observed) {
          await a.runner.run(a.lock.refresh(SUB));
          assert.equal(a.lock.standing(SUB), "outside");
        }
        Deferred.doneUnsafe(release, Effect.void);
        await assert.rejects(starting, /./, "the earlier empty read cannot authorize replacing the new lock");
        assert.deepEqual(c.kept.entries, existing, "the other device's lock remains in the cloud");
        assert.notEqual(a.lock.standing(SUB), "member");
      } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); b.runner.shutdown(); }
    });
  }
}

test("automatic creation fails closed against a cloud without guarded creation", async () => {
  const c = cloud(), original = c.call;
  let guarded = false;
  c.call = (sub, method, path, value) => {
    if (method === "POST" && path.endsWith("/append") && !guarded) return Effect.fail(new CoreError("not_found", "cloud has no guarded route", 404));
    return original(sub, method, path, value);
  };
  const a = device(c, "a");
  try {
    await assert.rejects(a.runner.run(a.lock.open(SUB, "why")), /guarded route/);
    assert.deepEqual(c.kept.entries, [], "it does not fall back to an unguarded reset");
    guarded = true;
    await a.runner.run(a.lock.open(SUB, "why"));
    assert.equal(a.lock.standing(SUB), "member");
  } finally { a.runner.shutdown(); }
});

test("a first lock accepted by the cloud but not acknowledged can be recovered after restart", async () => {
  const c = cloud(), original = c.call;
  let loseReply = true;
  c.call = (sub, method, path, value) => {
    const result = original(sub, method, path, value);
    return method === "POST" && path.endsWith("/append") && loseReply
      ? Effect.andThen(result, Effect.fail(new CoreError("offline", "reply lost")))
      : result;
  };
  const a = device(c, "a");
  try {
    await assert.rejects(a.runner.run(a.lock.open(SUB, "why")), /reply lost/);
    assert.equal(c.kept.entries.length, 1, "the cloud committed before the response was lost");
    const offline = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await assert.rejects(a.runner.run(offline.signGrant(SUB, body(), "why")), /offline/, "the unsigned local candidate is not taken as a confirmed lock");
    loseReply = false;
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.refresh(SUB));
    assert.equal(cold.standing(SUB), "member", "only the exact locally signed genesis is recovered");
    assert.equal(cold.chain(SUB)?.hash, entryHash(c.kept.entries[0]!));
    assert.equal([...a.host.storage.keys()].some((key) => key.startsWith("personal-first-")), false, "the confirmed candidate is removed");
  } finally { a.runner.shutdown(); }
});

test("an unacknowledged first lock does not trust a different cloud lock after restart", async () => {
  const c = cloud(), original = c.call;
  c.call = (sub, method, path, value) => method === "POST" && path.endsWith("/append")
    ? Effect.fail(new CoreError("offline", "before sending"))
    : original(sub, method, path, value);
  const a = device(c, "a"), other = cloud(), b = device(other, "b");
  try {
    await assert.rejects(a.runner.run(a.lock.open(SUB, "why")), /before sending/);
    await b.runner.run(b.lock.open(SUB, "why"));
    c.kept.entries = [...other.kept.entries];
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.refresh(SUB));
    assert.equal(cold.standing(SUB), "outside");
    assert.equal(cold.chain(SUB)?.hash, null, "another genesis was never pinned");
    await assert.rejects(a.runner.run(cold.signGrant(SUB, body(), "why")));
  } finally { a.runner.shutdown(); b.runner.shutdown(); }
});

test("recovering a first lock also keeps a later removal of this device", async () => {
  const c = cloud(), original = c.call;
  let loseReply = true;
  c.call = (sub, method, path, value) => {
    const result = original(sub, method, path, value);
    return method === "POST" && path.endsWith("/append") && loseReply
      ? Effect.andThen(result, Effect.fail(new CoreError("offline", "reply lost")))
      : result;
  };
  const a = device(c, "a"), b = device(c, "b");
  try {
    await assert.rejects(a.runner.run(a.lock.open(SUB, "why")), /reply lost/);
    const first = c.kept.entries[0]!;
    const aSeed = (await a.runner.run(a.host.secureGet!("personal-signer", { user: true })))!;
    const bKey = await b.runner.run(b.lock.makeKey());
    const bSeed = (await b.runner.run(b.host.secureGet!("personal-signer", { user: true })))!;
    const next = { v: 1 as const, ws: `person:${SUB}`, seq: 1, prev: entryHash(first), at: 1, kind: "device", body: { key: bKey, id: "62".repeat(32), label: "b" } };
    const added: Entry = { ...next, sig: { key: first.sig.key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(next)), aSeed)) } };
    const remove = { v: 1 as const, ws: `person:${SUB}`, seq: 2, prev: entryHash(added), at: 1, kind: "device.remove", body: { key: first.sig.key } };
    const removed: Entry = { ...remove, sig: { key: bKey, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(remove)), bSeed)) } };
    c.kept.entries = [first, added, removed];
    loseReply = false;
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.refresh(SUB));
    assert.equal(cold.chain(SUB)?.hash, entryHash(removed), "the verified newer chain is kept whole");
    assert.equal(cold.standing(SUB), "outside", "the later removal still takes effect");
    await assert.rejects(a.runner.run(cold.signGrant(SUB, body(), "why")));
  } finally { a.runner.shutdown(); b.runner.shutdown(); }
});

for (const afterWrite of [false, true]) {
  test(`a first lock is not sent if its recovery record ${afterWrite ? "was written before failing" : "could not be written"}`, async () => {
    const c = cloud(), a = device(c, "a"), set = a.host.storageSet.bind(a.host);
    try {
      a.host.storageSet = (key, value) => {
        if (!key.startsWith("personal-first-")) return set(key, value);
        const failure = Effect.fail(new HostError("first save failed", true));
        return afterWrite ? Effect.andThen(set(key, value), failure) : failure;
      };
      await assert.rejects(a.runner.run(a.lock.open(SUB, "why")), /first save failed/);
      assert.deepEqual(c.kept.entries, [], "no genesis is posted before its recovery record is saved");
      const stored = [...a.host.storage.entries()].find(([key]) => key.startsWith("personal-first-"))?.[1];
      a.host.storageSet = set;
      const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
      await a.runner.run(cold.open(SUB, "why"));
      assert.equal(cold.standing(SUB), "member");
      if (stored) assert.equal(entryHash((JSON.parse(new TextDecoder().decode(stored)) as Entry[])[0]!), entryHash(c.kept.entries[0]!), "a record that was actually written is reused");
    } finally { a.host.storageSet = set; a.runner.shutdown(); }
  });
}

test("a first-lock recovery record signed by a different device cannot be loaded", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    a.host.store(`personal-first-${hex(new TextEncoder().encode(SUB))}`, other.kept.entries);
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await assert.rejects(a.runner.run(cold.load(SUB)), /./);
    assert.equal(cold.loaded(SUB), false);
  } finally { a.runner.shutdown(); b.runner.shutdown(); }
});

test("an unpinned lock already seen is not erased by an earlier empty reply or offline restart", async () => {
  const c = cloud(), a = device(c, "a"), b = device(c, "b");
  const release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  try {
    await b.runner.run(b.lock.open(SUB, "why"));
    let first = true;
    const call = (sub: string, method: string, path: string, value: unknown) => {
      if (method === "GET" && first) {
        first = false;
        return Effect.andThen(Effect.sync(() => reached.resolve()), Effect.as(Deferred.await(release), { entries: [] }));
      }
      return c.call(sub, method, path, value);
    };
    const lock = new PersonalLock({ host: a.host, runner: a.runner, cloud: call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    const earlier = a.runner.run(lock.refresh(SUB));
    await reached.promise;
    await a.runner.run(lock.refresh(SUB));
    assert.equal(lock.standing(SUB), "outside");
    Deferred.doneUnsafe(release, Effect.void);
    await earlier;
    assert.equal(lock.standing(SUB), "outside");
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.standing(SUB), "outside");
    await assert.rejects(a.runner.run(cold.signGrant(SUB, body(), "why")));
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); b.runner.shutdown(); }
});

test("a restart cannot accept a different lock first heard while its confirmation waits", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  const release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    const read = a.host.secureGet!;
    a.host.secureGet = (key, options) => key === "personal-signer"
      ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key, options)))
      : read(key, options);
    const restarting = a.runner.run(a.lock.restart(SUB, "why"));
    await reached.promise;
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    Deferred.doneUnsafe(release, Effect.void);
    await assert.rejects(restarting, /./);
    assert.deepEqual(c.kept.entries, other.kept.entries);
    assert.equal(a.lock.standing(SUB), "replaced");
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); b.runner.shutdown(); }
});

test("an earlier cloud reply cannot clear a replacement already observed", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  const release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  const call = c.call;
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const old = [...c.kept.entries];
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = [...other.kept.entries];
    let first = true;
    const delayed = (sub: string, method: string, path: string, value: unknown) => {
      if (method === "GET" && first) {
        first = false;
        return Effect.andThen(Effect.sync(() => reached.resolve()), Effect.as(Deferred.await(release), { entries: old }));
      }
      return call(sub, method, path, value);
    };
    const lock = new PersonalLock({ host: a.host, runner: a.runner, cloud: delayed, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    const earlier = a.runner.run(lock.refresh(SUB));
    await reached.promise;
    const pairing = lock.joinGeneration(SUB);
    await a.runner.run(lock.refresh(SUB));
    assert.equal(lock.standing(SUB), "replaced");
    await assert.rejects(a.runner.run(lock.joined(SUB, old, pairing)), /./, "a pairing started before the observation cannot clear it");
    Deferred.doneUnsafe(release, Effect.void);
    await earlier;
    assert.equal(lock.standing(SUB), "replaced", "a stale reply cannot restore signing");
    await assert.rejects(a.runner.run(lock.signGrants(SUB, [body()], "why")));
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); b.runner.shutdown(); }
});

test("a seen replacement stays known after restart even when the cloud is offline", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  try {
    const signed = await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const old = [...c.kept.entries];
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.standing(SUB), "replaced");
    c.kept.entries = [];
    await a.runner.run(a.lock.refresh(SUB));
    assert.deepEqual(c.kept.entries, [], "an empty reply does not restore over a known replacement");
    c.kept.entries = [null as unknown as Entry];
    await a.runner.run(a.lock.refresh(SUB));
    assert.equal(a.lock.standing(SUB), "replaced", "invalid data cannot clear it either");
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.standing(SUB), "replaced", "the known replacement survives a restart");
    assert.equal(cold.chain(SUB)?.hash, entryHash(old.at(-1)!), "the trusted chain stays pinned");
    assert.equal(grantHolds(grantOf(signed), STATION, SUB, cold.chain(SUB)!.devices, NOW), 2_000_000_000, "existing signatures are checked against that chain");
    await assert.rejects(a.runner.run(cold.signGrant(SUB, body(), "why")));
    await assert.rejects(a.runner.run(cold.signGrants(SUB, [body()], "why")));
  } finally { a.runner.shutdown(); b.runner.shutdown(); }
});

test("a restore already in flight cannot clear a replacement heard while it waits", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  const release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = [];
    const call = (sub: string, method: string, path: string, value: unknown) => {
      if (method === "POST" && path.endsWith("/append")) {
        return Effect.andThen(Effect.sync(() => reached.resolve()), Effect.as(Deferred.await(release), {}));
      }
      return c.call(sub, method, path, value);
    };
    const lock = new PersonalLock({ host: a.host, runner: a.runner, cloud: call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    const restoring = a.runner.run(lock.refresh(SUB));
    await reached.promise;
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(lock.refresh(SUB));
    assert.equal(lock.standing(SUB), "replaced");
    Deferred.doneUnsafe(release, Effect.void);
    await restoring;
    assert.equal(lock.standing(SUB), "replaced", "the earlier restore cannot clear the new observation");
    await assert.rejects(a.runner.run(lock.signGrants(SUB, [body()], "why")));
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.standing(SUB), "replaced", "the observation remains on disk as well");
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); b.runner.shutdown(); }
});

for (const action of ["join", "restart"] as const) {
  test(`an explicit ${action} accepts a known replacement and keeps that choice after restart`, async () => {
    const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
    try {
      await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
      await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
      if (action === "join") {
        const key = await a.runner.run(a.lock.makeKey());
        await b.runner.run(b.lock.addDevice(SUB, { key, id: "61".repeat(32), label: "a" }, "why"));
      }
      c.kept.entries = [...other.kept.entries];
      await a.runner.run(a.lock.refresh(SUB));
      assert.equal(a.lock.standing(SUB), "replaced");
      if (action === "join") await a.runner.run(a.lock.joined(SUB, c.kept.entries, a.lock.joinGeneration(SUB)));
      else await a.runner.run(a.lock.restart(SUB, "why"));
      assert.equal(a.lock.standing(SUB), "member");
      assert.equal([...a.host.storage.keys()].some((key) => key.startsWith("personal-replaced-")), false);
      const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
      await a.runner.run(cold.load(SUB));
      assert.equal(cold.standing(SUB), "member", "the accepted chain remains pinned on a fresh core");
    } finally { a.runner.shutdown(); b.runner.shutdown(); }
  });
}

for (const action of ["join", "restart"] as const) {
  test(`a failed replacement cleanup after ${action} blocks lending and can be retried offline`, async () => {
    const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b"), remove = a.host.storageDelete.bind(a.host);
    let p: ReturnType<typeof phone> | null = null;
    try {
      const oldGrant = await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
      await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
      let grant = oldGrant;
      if (action === "join") {
        const key = await a.runner.run(a.lock.makeKey());
        await b.runner.run(b.lock.addDevice(SUB, { key, id: "61".repeat(32), label: "a" }, "why"));
        grant = await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
      }
      c.kept.entries = [...other.kept.entries];
      await a.runner.run(a.lock.refresh(SUB));
      a.host.storageDelete = (key) => key.startsWith("personal-replaced-") ? Effect.fail(new HostError("replacement removal failed", true)) : remove(key);
      const result = action === "join" ? a.lock.joined(SUB, c.kept.entries, a.lock.joinGeneration(SUB)) : a.lock.restart(SUB, "why");
      await assert.rejects(a.runner.run(result), /replacement removal failed/);
      assert.equal(a.lock.ready(SUB), false, "an incomplete confirmation cannot lend or sign");
      p = phone({ personal: a.lock, subOf: () => SUB, subs: () => [{ sub: SUB, email: "a@x" }] });
      p.adb.heard(STATION, grantOf(grant));
      assert.deepEqual(p.adb.wanted(), []);
      a.host.storageDelete = remove;
      const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
      await a.runner.run(cold.load(SUB));
      assert.equal(cold.ready(SUB), false, "restart preserves the incomplete confirmation");
      await a.runner.run(cold.open(SUB, "why"));
      assert.equal(cold.ready(SUB), true, "cleanup retries without the cloud");
      assert.equal(cold.standing(SUB), "member");
    } finally { a.host.storageDelete = remove; p?.runner.shutdown(); a.runner.shutdown(); b.runner.shutdown(); }
  });
}

test("a pairing on the old lock cannot clear an observed different lock", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const old = [...c.kept.entries];
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    await assert.rejects(a.runner.run(a.lock.joined(SUB, old, a.lock.joinGeneration(SUB))), /./);
    assert.equal(a.lock.standing(SUB), "replaced");
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.standing(SUB), "replaced");
  } finally { a.runner.shutdown(); b.runner.shutdown(); }
});

test("joining an older prefix cannot discard a removal already seen on the replacement", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const aKey = await a.runner.run(a.lock.makeKey());
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.addDevice(SUB, { key: aKey, id: "61".repeat(32), label: "a" }, "why"));
    const oldProof = [...other.kept.entries];
    await b.runner.run(b.lock.removeDevice(SUB, aKey, "why"));
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    await assert.rejects(a.runner.run(a.lock.joined(SUB, oldProof, a.lock.joinGeneration(SUB))), /./);
    assert.equal(a.lock.standing(SUB), "replaced");
    assert.notEqual(a.lock.chain(SUB)?.hash, entryHash(oldProof.at(-1)!));
  } finally { a.runner.shutdown(); b.runner.shutdown(); }
});

test("a later stale cloud read cannot discard a removal already seen on a replacement", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const key = await a.runner.run(a.lock.makeKey());
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.addDevice(SUB, { key, id: "61".repeat(32), label: "a" }, "why"));
    const older = [...other.kept.entries];
    await b.runner.run(b.lock.removeDevice(SUB, key, "why"));
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    c.kept.entries = older;
    await a.runner.run(a.lock.refresh(SUB));
    await assert.rejects(a.runner.run(a.lock.joined(SUB, older, a.lock.joinGeneration(SUB))), /./);
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    await assert.rejects(a.runner.run(cold.joined(SUB, older, cold.joinGeneration(SUB))), /./, "the later removal is also kept across restart");
  } finally { a.runner.shutdown(); b.runner.shutdown(); }
});

for (const afterWrite of [false, true]) {
  test(`an interrupted join ${afterWrite ? "after" : "before"} writing its pin resumes from the confirmed proof offline`, async () => {
    const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b"), set = a.host.storageSet.bind(a.host);
    try {
      await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
      await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
      const key = await a.runner.run(a.lock.makeKey());
      await b.runner.run(b.lock.addDevice(SUB, { key, id: "61".repeat(32), label: "a" }, "why"));
      c.kept.entries = [...other.kept.entries];
      await a.runner.run(a.lock.refresh(SUB));
      a.host.storageSet = (name, value) => {
        if (!name.startsWith("personal-lock-")) return set(name, value);
        const failure = Effect.fail(new HostError("pin save failed", true));
        return afterWrite ? Effect.andThen(set(name, value), failure) : failure;
      };
      await assert.rejects(a.runner.run(a.lock.joined(SUB, c.kept.entries, a.lock.joinGeneration(SUB))), /pin save failed/);
      assert.equal(a.lock.ready(SUB), false);
      a.host.storageSet = set;
      const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
      await a.runner.run(cold.load(SUB));
      assert.equal(cold.ready(SUB), false);
      await a.runner.run(cold.open(SUB, "why"));
      assert.equal(cold.ready(SUB), true);
      assert.equal(cold.standing(SUB), "member");
      assert.equal(cold.chain(SUB)?.hash, entryHash(other.kept.entries.at(-1)!));
    } finally { a.host.storageSet = set; a.runner.shutdown(); b.runner.shutdown(); }
  });
}

for (const afterWrite of [false, true]) {
  test(`a restart is not sent when its confirmation record ${afterWrite ? "was written before failing" : "could not be written"}`, async () => {
    const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b"), set = a.host.storageSet.bind(a.host);
    try {
      await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
      await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
      c.kept.entries = [...other.kept.entries];
      await a.runner.run(a.lock.refresh(SUB));
      a.host.storageSet = (name, value) => {
        if (!name.startsWith("personal-accepting-")) return set(name, value);
        const failure = Effect.fail(new HostError("confirmation save failed", true));
        return afterWrite ? Effect.andThen(set(name, value), failure) : failure;
      };
      await assert.rejects(a.runner.run(a.lock.restart(SUB, "why")), /confirmation save failed/);
      assert.deepEqual(c.kept.entries, other.kept.entries, "the old cloud chain was not replaced");
      assert.equal(a.lock.ready(SUB), false);
      a.host.storageSet = set;
      if (afterWrite) {
        const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
        await a.runner.run(cold.load(SUB));
        assert.equal(cold.ready(SUB), false);
        await a.runner.run(cold.open(SUB, "why"));
        assert.equal(cold.standing(SUB), "member", "the saved choice is retried against the same cloud chain");
      }
    } finally { a.host.storageSet = set; a.runner.shutdown(); b.runner.shutdown(); }
  });
}

test("a confirmation whose final record cannot be removed remains pending across restart", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b"), remove = a.host.storageDelete.bind(a.host);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    const key = await a.runner.run(a.lock.makeKey());
    await b.runner.run(b.lock.addDevice(SUB, { key, id: "61".repeat(32), label: "a" }, "why"));
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    a.host.storageDelete = (name) => name.startsWith("personal-accepting-") ? Effect.fail(new HostError("confirmation removal failed", true)) : remove(name);
    await assert.rejects(a.runner.run(a.lock.joined(SUB, c.kept.entries, a.lock.joinGeneration(SUB))), /confirmation removal failed/);
    assert.equal(a.lock.ready(SUB), false);
    a.host.storageDelete = remove;
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.ready(SUB), false);
    await a.runner.run(cold.open(SUB, "why"));
    assert.equal(cold.ready(SUB), true);
    assert.equal(cold.standing(SUB), "member");
  } finally { a.host.storageDelete = remove; a.runner.shutdown(); b.runner.shutdown(); }
});

for (const committed of [false, true]) {
  test(`a restart whose reply was lost ${committed ? "after" : "before"} the cloud commit resumes its exact choice`, async () => {
    const c = cloud(), other = cloud(), call = c.call;
    let loseReply = false;
    c.call = (sub, method, path, value) => Effect.suspend(() => {
      if (method === "POST" && path.endsWith("/append")) {
        const expect = (value as { expect: { length: number; head: string | null } }).expect;
        if (expect.length !== c.kept.entries.length || expect.head !== (c.kept.entries.length ? entryHash(c.kept.entries.at(-1)!) : null)) {
          return Effect.fail(new CoreError("lock_refused", "the cloud lock changed", 409));
        }
        if (loseReply) {
          loseReply = false;
          const failure = Effect.fail(new CoreError("offline", "reply lost"));
          return committed ? Effect.andThen(call(sub, method, path, value), failure) : failure;
        }
      }
      return call(sub, method, path, value);
    });
    const a = device(c, "a"), b = device(other, "b");
    try {
      await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
      await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
      c.kept.entries = [...other.kept.entries];
      await a.runner.run(a.lock.refresh(SUB));
      await a.host.time.pass(1_000);
      loseReply = true;
      await assert.rejects(a.runner.run(a.lock.restart(SUB, "why")), /reply lost/);
      const saved = [...a.host.storage.entries()].find(([key]) => key.startsWith("personal-accepting-"))![1];
      const target = (JSON.parse(new TextDecoder().decode(saved)) as { target: Entry[] }).target;
      const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
      await a.runner.run(cold.load(SUB));
      assert.equal(cold.ready(SUB), false);
      await a.runner.run(cold.open(SUB, "why"));
      assert.equal(cold.standing(SUB), "member");
      assert.equal(cold.chain(SUB)?.hash, entryHash(target[0]!));
      assert.equal(entryHash(c.kept.entries[0]!), entryHash(target[0]!));
    } finally { a.runner.shutdown(); b.runner.shutdown(); }
  });
}

test("a restart cannot overwrite a different cloud lock created before its guarded write", async () => {
  const c = cloud(), other = cloud(), newest = cloud(), call = c.call;
  let race = false;
  c.call = (sub, method, path, value) => Effect.suspend(() => {
    if (method === "POST" && path.endsWith("/append")) {
      if (race) { race = false; c.kept.entries = [...newest.kept.entries]; }
      const expect = (value as { expect: { length: number; head: string | null } }).expect;
      if (expect.length !== c.kept.entries.length || expect.head !== (c.kept.entries.length ? entryHash(c.kept.entries.at(-1)!) : null)) {
        return Effect.fail(new CoreError("lock_refused", "the cloud lock changed", 409));
      }
    }
    return call(sub, method, path, value);
  });
  const a = device(c, "a"), b = device(other, "b"), d = device(newest, "d");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    await d.runner.run(d.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    const old = a.lock.chain(SUB)?.hash;
    await a.host.time.pass(1_000);
    race = true;
    await assert.rejects(a.runner.run(a.lock.restart(SUB, "why")), /cloud lock changed/);
    assert.deepEqual(c.kept.entries, newest.kept.entries);
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    await assert.rejects(a.runner.run(cold.open(SUB, "why")), /./);
    assert.equal(cold.standing(SUB), "replaced");
    assert.equal(cold.chain(SUB)?.hash, old, "the previously pinned chain was not replaced by an unconfirmed one");
    assert.equal(cold.ready(SUB), true, "the newer observation remains available for a new decision");
  } finally { a.runner.shutdown(); b.runner.shutdown(); d.runner.shutdown(); }
});

test("an interrupted forget cannot resume the confirmation it was meant to discard", async () => {
  const c = cloud(), call = c.call;
  let loseReply = false;
  c.call = (sub, method, path, value) => method === "POST" && path.endsWith("/append") && loseReply
    ? Effect.andThen(call(sub, method, path, value), Effect.fail(new CoreError("offline", "reply lost")))
    : call(sub, method, path, value);
  const a = device(c, "a"), remove = a.host.storageDelete.bind(a.host);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await a.host.time.pass(1_000);
    loseReply = true;
    await assert.rejects(a.runner.run(a.lock.restart(SUB, "why")), /reply lost/);
    a.host.storageDelete = (name) => name.startsWith("personal-accepting-") ? Effect.fail(new HostError("forget cleanup failed", true)) : remove(name);
    await assert.rejects(a.runner.run(a.lock.forget(SUB, "why")), /forget cleanup failed/);
    assert.equal(a.lock.ready(SUB), false);
    a.host.storageDelete = remove;
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: () => Effect.fail(new CoreError("offline", "offline")), device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.ready(SUB), false);
    await a.runner.run(cold.open(SUB, "why"));
    assert.equal(cold.standing(SUB), "none", "retry finishes forgetting rather than recovering the old confirmation");
    assert.equal(cold.chain(SUB)?.hash, null);
  } finally { a.host.storageDelete = remove; a.runner.shutdown(); }
});

test("a replacement that could not be saved blocks lending until an offline retry saves it", async () => {
  const c = cloud(), other = cloud(), request = c.call;
  let offline = false;
  c.call = (sub, method, path, value) => offline ? Effect.fail(new CoreError("offline", "offline")) : request(sub, method, path, value);
  const a = device(c, "a"), b = device(other, "b"), set = a.host.storageSet.bind(a.host);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = [...other.kept.entries];
    a.host.storageSet = (key, value) => key.startsWith("personal-replaced-") ? Effect.fail(new HostError("replacement save failed", true)) : set(key, value);
    await assert.rejects(a.runner.run(a.lock.refresh(SUB)), /replacement save failed/);
    assert.equal(a.lock.standing(SUB), "replaced");
    assert.equal(a.lock.ready(SUB), false);
    await assert.rejects(a.runner.run(a.lock.signGrants(SUB, [body()], "why")));
    a.host.storageSet = set;
    offline = true;
    await a.runner.run(a.lock.open(SUB, "why"));
    assert.equal(a.lock.ready(SUB), true, "the local retry does not need the cloud");
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.standing(SUB), "replaced");
  } finally { a.host.storageSet = set; a.runner.shutdown(); b.runner.shutdown(); }
});

test("a failed removal of a replacement cannot silently restore signing after forget or restart", async () => {
  const c = cloud(), other = cloud(), a = device(c, "a"), b = device(other, "b"), remove = a.host.storageDelete.bind(a.host);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    c.kept.entries = [...other.kept.entries];
    await a.runner.run(a.lock.refresh(SUB));
    a.host.storageDelete = (key) => key.startsWith("personal-replaced-") ? Effect.fail(new HostError("replacement removal failed", true)) : remove(key);
    await assert.rejects(a.runner.run(a.lock.forget(SUB, "why")), /replacement removal failed/);
    assert.equal(a.lock.ready(SUB), false);
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.standing(SUB), "outside", "the remaining observation prevents an automatic new lock");
    await assert.rejects(a.runner.run(cold.signGrant(SUB, body(), "why")));
    a.host.storageDelete = remove;
    await a.runner.run(a.lock.forget(SUB, "why"));
    assert.equal(a.lock.standing(SUB), "none", "an explicit retry completes the forget");
  } finally { a.host.storageDelete = remove; a.runner.shutdown(); b.runner.shutdown(); }
});

for (const problem of ["chain read", "chain contents", "chain empty", "identity read", "identity contents", "replacement read", "replacement contents", "first read", "first contents", "acceptance read", "acceptance contents"] as const) {
  test(`a failed or corrupt ${problem} cannot be treated as an absent personal lock`, async () => {
    const c = cloud(), a = device(c, "a");
    const read = a.host.storageGet.bind(a.host);
    try {
      await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
      const pinKey = [...a.host.storage.keys()].find((key) => key.startsWith("personal-lock-"))!;
      const pinned = a.host.storage.get(pinKey)!;
      c.kept.entries = [];
      a.host.storageGet = (key) => {
        if (key === pinKey && problem === "chain read" || key === "personal-signer-id" && problem === "identity read" || key.startsWith("personal-replaced-") && problem === "replacement read" || key.startsWith("personal-first-") && problem === "first read" || key.startsWith("personal-accepting-") && problem === "acceptance read") return Effect.fail(new HostError("storage read failed", true));
        if (key === pinKey && (problem === "chain contents" || problem === "chain empty") || key === "personal-signer-id" && problem === "identity contents" || key.startsWith("personal-replaced-") && problem === "replacement contents" || key.startsWith("personal-first-") && problem === "first contents" || key.startsWith("personal-accepting-") && problem === "acceptance contents") return Effect.succeed(new TextEncoder().encode(problem === "chain empty" ? "[]" : "invalid"));
        return read(key);
      };
      const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
      await assert.rejects(a.runner.run(cold.signGrant(SUB, body(), "why")), /./);
      await assert.rejects(a.runner.run(cold.open(SUB, "why")), /./);
      assert.equal(cold.loaded(SUB), false, "a failed read can be retried");
      assert.deepEqual(c.kept.entries, [], "no new genesis replaced an unreadable lock");
      assert.deepEqual(a.host.storage.get(pinKey), pinned, "the old pin was not overwritten");
    } finally { a.host.storageGet = read; a.runner.shutdown(); }
  });
}

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
    await a.runner.run(a.lock.joined(SUB, pinned, a.lock.joinGeneration(SUB)));
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

test("forgetting while the initial personal lock load waits for its key cannot restore the old lock", async () => {
  const c = cloud(), a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const read = a.host.storageGet.bind(a.host);
    let held = false;
    a.host.storageGet = (key) => key === "personal-signer-id"
      ? Effect.andThen(Effect.sync(() => { held = true; }), Effect.andThen(Deferred.await(release), read(key)))
      : read(key);
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    const loading = a.runner.run(cold.load(SUB));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true, "the old chain was read before the key read was held");
    await a.runner.run(cold.forget(SUB, "why"));
    Deferred.doneUnsafe(release, Effect.void);
    await loading;
    assert.equal(cold.standing(SUB), "none", "the completed forget remains in effect in memory");
    assert.equal(cold.chain(SUB)?.hash, null);
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.standing(SUB), "none", "the chain is also absent after restart");
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); }
});

test("a late initial load cannot overwrite a different personal lock already joined", async () => {
  const c = cloud(), a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const storageKey = [...a.host.storage.keys()].find((key) => key.startsWith("personal-lock-"))!;
    const old = a.host.storage.get(storageKey)!;
    await a.host.time.pass(1_000);
    await a.runner.run(a.lock.restart(SUB, "why"));
    const newer = [...c.kept.entries];
    assert.notEqual(entryHash(newer[0]!), entryHash(JSON.parse(new TextDecoder().decode(old))[0]));
    a.host.storage.set(storageKey, old);
    const read = a.host.storageGet.bind(a.host);
    let held = false;
    a.host.storageGet = (key) => {
      if (key !== "personal-signer-id" || held) return read(key);
      held = true;
      return Effect.andThen(Deferred.await(release), read(key));
    };
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    const loading = a.runner.run(cold.load(SUB));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true);
    await a.runner.run(cold.makeKey());
    await a.runner.run(cold.joined(SUB, newer, cold.joinGeneration(SUB)));
    Deferred.doneUnsafe(release, Effect.void);
    await loading;
    assert.equal(cold.standing(SUB), "member");
    assert.equal(cold.chain(SUB)?.hash, entryHash(newer.at(-1)!), "memory keeps the joined lock");
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.chain(SUB)?.hash, entryHash(newer.at(-1)!), "storage agrees after restart");
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); }
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

test("closing a core waits for its personal lock write before the next core starts", async () => {
  const c = cloud(), a = device(c, "a"), b = device(c, "b"), release = Deferred.makeUnsafe<void>();
  let first: Core | null = null, second: Core | null = null;
  const set = a.host.storageSet.bind(a.host);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const storageKey = [...a.host.storage.keys()].find((key) => key.startsWith("personal-lock-"))!;
    const genesis = a.host.storage.get(storageKey)!;
    const bKey = await b.runner.run(b.lock.makeKey());
    await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "62".repeat(32), label: "b" }, "why"));
    const older = [...c.kept.entries];
    await a.runner.run(a.lock.removeDevice(SUB, bKey, "why"));
    const newest = [...c.kept.entries];
    a.host.storage.set(storageKey, genesis);
    c.kept.entries = older.slice(0, 1);
    a.host.store("accounts", [{ sub: SUB, email: "a@x", name: "a", picture: "", access: "a", refresh: "r", access_expires: 4_000_000_000 }]);
    const start = async () => {
      const core = await Core.create(a.host, { clock: a.host.time.clock, sample: 0 });
      core.inner.provider.request = c.call;
      core.inner.mesh = () => Effect.succeed({ deviceId: () => "61".repeat(32) } as never);
      await core.inner.runner.run(core.inner.adb.personal().load(SUB));
      return core;
    };
    first = await start();
    let held = false, oldFinished = false, closed = false;
    a.host.storageSet = (name, value) => {
      if (name !== storageKey || held) return set(name, value);
      return Effect.andThen(Effect.sync(() => { held = true; }), Effect.andThen(Deferred.await(release), set(name, value)));
    };
    c.kept.entries = older;
    first.inner.runner.fork(Effect.ensuring(Effect.ignore(first.inner.adb.personal().refresh(SUB)), Effect.sync(() => { oldFinished = true; })));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true, "the old core has a verified lock write in flight");
    const closing = first.close().then(() => { closed = true; });
    await a.host.time.pass(100);
    const closedBeforeWrite = closed;
    if (closedBeforeWrite) {
      second = await start();
      c.kept.entries = newest;
      await second.inner.runner.run(second.inner.adb.personal().refresh(SUB));
    }
    Deferred.doneUnsafe(release, Effect.void);
    await closing;
    for (let i = 0; i < 100 && !oldFinished; i++) await a.host.time.pass(10);
    assert.equal(oldFinished, true);
    if (second === null) {
      second = await start();
      c.kept.entries = newest;
      await second.inner.runner.run(second.inner.adb.personal().refresh(SUB));
    }
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.chain(SUB)?.hash, entryHash(newest.at(-1)!), "the old core cannot overwrite the new core's revocation");
    assert.equal(closedBeforeWrite, false, "close waits for an in-flight personal lock write");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    a.host.storageSet = set;
    first?.inner.runner.shutdown();
    second?.inner.runner.shutdown();
    a.runner.shutdown();
    b.runner.shutdown();
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
    await a.runner.run(a.lock.joined(SUB, older, a.lock.joinGeneration(SUB)));
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

test("forgetting while the first personal genesis is being accepted is not undone by its reply", async () => {
  const c = cloud(), release = Deferred.makeUnsafe<void>();
  let held = false;
  const delayed = {
    ...c,
    call: (sub: string, method: string, path: string, body: unknown) => {
      const answer = c.call(sub, method, path, body);
      const kind = (body as { entries?: Entry[] } | null)?.entries?.[0]?.kind;
      if (method !== "POST" || kind !== "genesis") return answer;
      return Effect.flatMap(answer, (result) => Effect.andThen(Effect.sync(() => { held = true; }), Effect.as(Deferred.await(release), result)));
    },
  };
  const a = device(delayed, "a");
  try {
    const opening = a.runner.run(a.lock.open(SUB, "why"));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true, "the cloud accepted the first genesis before its reply arrived");
    assert.equal(c.kept.entries.length, 1);
    assert.equal([...a.host.storage.keys()].some((key) => key.startsWith("personal-first-")), true, "the unacknowledged genesis was saved");
    await a.runner.run(a.lock.forget(SUB, "why"));
    assert.equal([...a.host.storage.keys()].some((key) => key.startsWith("personal-first-")), false, "forgetting removes it");
    Deferred.doneUnsafe(release, Effect.void);
    await assert.rejects(opening, (error: unknown) => error instanceof CoreError && error.code === "personal_changed");
    assert.equal(a.lock.chain(SUB)?.hash, null);
    assert.equal(a.lock.standing(SUB), "none");
    assert.equal(c.kept.entries.length, 1, "forgetting locally does not pretend the cloud write was undone");
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.standing(SUB), "none");
    await a.runner.run(restarted.refresh(SUB));
    assert.equal(restarted.standing(SUB), "outside");
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); }
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

test("two accounts opening together use the same device signing key after restart", async () => {
  const clouds = new Map([["s1", cloud()], ["s2", cloud()]]);
  const c = cloud();
  c.call = (sub, method, path, body) => clouds.get(sub)!.call(sub, method, path, body);
  const a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  const p = phone({ personal: a.lock, subs: () => [{ sub: "s1", email: "a@x" }, { sub: "s2", email: "b@x" }] });
  let made = 0, entered = 0;
  a.host.randomBytes = (bytes) => { bytes.fill(++made); };
  const secureSet = a.host.secureSet!;
  a.host.secureSet = (key, value, options) => {
    entered++;
    return entered === 1 ? Effect.andThen(Deferred.await(release), secureSet(key, value, options)) : secureSet(key, value, options);
  };
  try {
    const first = p.runner.run(p.adb.run({ kind: "personalOpen", sub: "s1" }));
    for (let i = 0; i < 100 && entered === 0; i++) await p.host.time.pass(10);
    assert.equal(entered, 1, "the first open is held before writing its device seed");
    const second = p.runner.run(p.adb.run({ kind: "personalOpen", sub: "s2" }));
    for (let i = 0; i < 100 && entered < 2; i++) await p.host.time.pass(10);
    Deferred.doneUnsafe(release, Effect.void);
    await Promise.all([first, second]);
    const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
    assert.ok(seed);
    const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
    const storedId = await a.runner.run(a.host.storageGet("personal-signer-id"));
    assert.equal(new TextDecoder().decode(storedId!), id, "the persisted public id belongs to the persisted seed");
    for (const sub of ["s1", "s2"]) {
      assert.notEqual(checkChain(clouds.get(sub)!.kept.entries, sub), null);
      assert.equal(a.lock.chain(sub)?.devices.has(id), true, `${sub}'s lock uses the device's actual key`);
    }
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    for (const sub of ["s1", "s2"]) {
      await a.runner.run(cold.load(sub));
      assert.equal(cold.standing(sub), "member");
      const signed = await a.runner.run(cold.signGrant(sub, body(), "why"));
      assert.equal(grantHolds(grantOf(signed), STATION, sub, cold.chain(sub)!.devices, NOW), 2_000_000_000, `${sub}'s signature verifies after restart`);
    }
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    p.runner.shutdown();
    a.runner.shutdown();
  }
});

test("overlapping personal locks on the same host cannot create two device keys", async () => {
  const clouds = new Map([["s1", cloud()], ["s2", cloud()]]);
  const c = cloud();
  c.call = (sub, method, path, body) => clouds.get(sub)!.call(sub, method, path, body);
  const a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  const next = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
  const p = phone({ personal: a.lock, subs: () => [{ sub: "s1", email: "a@x" }] });
  const q = phone({ personal: next, subs: () => [{ sub: "s2", email: "b@x" }] });
  const seal = a.host.secureSet!;
  let seeds = 0, entered = 0;
  a.host.randomBytes = (bytes) => { bytes.fill(++seeds); };
  a.host.secureSet = (key, value, options) => {
    entered++;
    return entered === 1 ? Effect.andThen(Deferred.await(release), seal(key, value, options)) : seal(key, value, options);
  };
  try {
    const first = p.runner.run(p.adb.run({ kind: "personalOpen", sub: "s1" }));
    for (let i = 0; i < 100 && entered === 0; i++) await p.host.time.pass(10);
    assert.equal(entered, 1);
    const second = q.runner.run(q.adb.run({ kind: "personalOpen", sub: "s2" }));
    for (let i = 0; i < 100 && entered < 2; i++) await q.host.time.pass(10);
    Deferred.doneUnsafe(release, Effect.void);
    await Promise.all([first, second]);
    const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
    assert.ok(seed);
    const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
    assert.equal(checkChain(clouds.get("s1")!.kept.entries, "s1")?.devices.has(id), true);
    assert.equal(checkChain(clouds.get("s2")!.kept.entries, "s2")?.devices.has(id), true, "both cores used the device's one persisted key");
  } finally { Deferred.doneUnsafe(release, Effect.void); p.runner.shutdown(); q.runner.shutdown(); a.runner.shutdown(); }
});

test("two cores using the same device host create one signing key", async () => {
  const clouds = new Map([["s1", cloud()], ["s2", cloud()]]);
  const c = cloud();
  c.call = (sub, method, path, body) => clouds.get(sub)!.call(sub, method, path, body);
  const a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  a.host.store("accounts", ["s1", "s2"].map((sub) => ({
    sub, email: `${sub}@x`, name: sub, picture: "", access: sub, refresh: "refresh", access_expires: 4_000_000_000,
  })));
  const seal = a.host.secureSet!;
  let seeds = 0, entered = 0;
  a.host.secureSet = (key, value, options) => {
    entered++;
    return entered === 1 ? Effect.andThen(Deferred.await(release), seal(key, value, options)) : seal(key, value, options);
  };
  const first = await Core.create(a.host, { clock: a.host.time.clock, sample: 0 });
  const second = await Core.create(a.host, { clock: a.host.time.clock, sample: 0 });
  try {
    // Core.make wraps the same device host separately for each core.
    assert.notEqual(first.inner.host, second.inner.host);
    for (const core of [first, second]) {
      core.inner.provider.request = c.call;
      core.inner.mesh = () => Effect.succeed({ deviceId: () => "61".repeat(32) } as never);
    }
    a.host.randomBytes = (bytes) => { bytes.fill(++seeds); };
    const openingFirst = first.inner.runner.run(first.inner.adb.run({ kind: "personalOpen", sub: "s1" }));
    for (let i = 0; i < 100 && entered === 0; i++) await a.host.time.pass(10);
    assert.equal(entered, 1, "the first core waits before sealing its seed");
    const openingSecond = second.inner.runner.run(second.inner.adb.run({ kind: "personalOpen", sub: "s2" }));
    for (let i = 0; i < 100 && entered < 2; i++) await a.host.time.pass(10);
    Deferred.doneUnsafe(release, Effect.void);
    await Promise.all([openingFirst, openingSecond]);
    const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
    assert.ok(seed);
    const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
    assert.equal(new TextDecoder().decode((await a.runner.run(a.host.storageGet("personal-signer-id")))!), id);
    for (const sub of ["s1", "s2"]) {
      assert.equal(checkChain(clouds.get(sub)!.kept.entries, sub)?.devices.has(id), true, `${sub}'s chain has the persisted device key`);
    }
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    for (const sub of ["s1", "s2"]) {
      await a.runner.run(restarted.load(sub));
      const signed = await a.runner.run(restarted.signGrant(sub, body(), "why"));
      assert.equal(grantHolds(grantOf(signed), STATION, sub, restarted.chain(sub)!.devices, NOW), 2_000_000_000);
    }
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    first.inner.runner.shutdown();
    second.inner.runner.shutdown();
    a.runner.shutdown();
  }
});

for (const afterWrite of [false, true]) {
 for (const restartFirst of [false, true]) {
  test(`a signer id write that fails ${afterWrite ? "after" : "before"} saving does not replace the sealed key ${restartFirst ? "after restart" : "on retry"}`, async () => {
    const clouds = new Map([["s1", cloud()], ["s2", cloud()]]);
    const c = cloud();
    c.call = (sub, method, path, value) => clouds.get(sub)!.call(sub, method, path, value);
    const a = device(c, "a");
    const p = phone({ personal: a.lock, subs: () => [{ sub: "s1", email: "a@x" }, { sub: "s2", email: "b@x" }] });
    let resumed = p;
    const set = a.host.storageSet.bind(a.host), seal = a.host.secureSet!;
    let fail = true, seals = 0, seeds = 0;
    a.host.randomBytes = (bytes) => { bytes.fill(++seeds); };
    a.host.secureSet = (key, value, options) => { seals++; return seal(key, value, options); };
    a.host.storageSet = (key, value) => {
      if (key !== "personal-signer-id" || !fail) return set(key, value);
      fail = false;
      const failure = Effect.fail(new HostError("signer id write failed", true));
      return afterWrite ? Effect.andThen(set(key, value), failure) : failure;
    };
    try {
      await assert.rejects(p.runner.run(p.adb.run({ kind: "personalOpen", sub: "s1" })), /signer id write failed/);
      if (restartFirst) {
        const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
        resumed = phone({ personal: restarted, subs: () => [{ sub: "s1", email: "a@x" }, { sub: "s2", email: "b@x" }] });
      }
      await resumed.runner.run(resumed.adb.run({ kind: "personalOpen", sub: "s2" }));
      await resumed.runner.run(resumed.adb.run({ kind: "personalOpen", sub: "s1" }));
      assert.equal(seals, 1, "a reported error does not overwrite the seed on retry");
      const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
      assert.ok(seed);
      const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
      const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
      for (const sub of ["s1", "s2"]) {
        await a.runner.run(cold.load(sub));
        assert.equal(cold.chain(sub)?.devices.has(id), true);
        const signed = await a.runner.run(cold.signGrant(sub, body(), "why"));
        assert.equal(grantHolds(grantOf(signed), STATION, sub, cold.chain(sub)!.devices, NOW), 2_000_000_000);
      }
    } finally { if (resumed !== p) resumed.runner.shutdown(); p.runner.shutdown(); a.runner.shutdown(); }
  });
 }
}

test("opening while an existing signer id is still loading keeps the sealed key", async () => {
  const c = cloud(), a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  try {
    const id = await a.runner.run(a.lock.makeKey());
    const stored = await a.runner.run(a.host.storageGet("personal-signer-id"));
    const get = a.host.storageGet.bind(a.host), seal = a.host.secureSet!;
    let held = false, seals = 0;
    a.host.storageGet = (key) => {
      if (key !== "personal-signer-id" || held) return get(key);
      held = true;
      return Effect.andThen(Deferred.await(release), Effect.succeed(stored));
    };
    a.host.secureSet = (key, value, options) => { seals++; return seal(key, value, options); };
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    const loading = a.runner.run(cold.load(SUB));
    for (let i = 0; i < 100 && !held; i++) await a.host.time.pass(10);
    assert.equal(held, true);
    await a.runner.run(cold.begin(SUB, "why"));
    Deferred.doneUnsafe(release, Effect.void);
    await loading;
    assert.equal(seals, 0, "the still-loading identity does not cause another seed to be made");
    assert.equal(cold.chain(SUB)?.devices.has(id), true);
    assert.notEqual(checkChain(c.kept.entries, SUB), null);
  } finally { Deferred.doneUnsafe(release, Effect.void); a.runner.shutdown(); }
});

test("an already-used sealed key is recovered when its public id is missing", async () => {
  const clouds = new Map([["s1", cloud()], ["s2", cloud()]]);
  const c = cloud();
  c.call = (sub, method, path, body) => clouds.get(sub)!.call(sub, method, path, body);
  const a = device(c, "a");
  try {
    const signed = await a.runner.run(a.lock.signGrant("s1", body(), "why"));
    const id = signed.sig.key;
    await a.runner.run(a.host.storageDelete("personal-signer-id"));
    const seal = a.host.secureSet!;
    let seals = 0;
    a.host.secureSet = (key, value, options) => { seals++; return seal(key, value, options); };
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    const p = phone({ personal: cold, subs: () => [{ sub: "s1", email: "a@x" }, { sub: "s2", email: "b@x" }] });
    try {
      a.asks.refuse = true;
      await assert.rejects(p.runner.run(p.adb.run({ kind: "personalOpen", sub: "s2" })));
      assert.equal(seals, 0, "refusing recovery does not replace the existing key");
      assert.equal(clouds.get("s2")!.kept.entries.length, 0);
      a.asks.refuse = false;
      await p.runner.run(p.adb.run({ kind: "personalOpen", sub: "s2" }));
      await a.runner.run(cold.load("s1"));
      assert.equal(cold.chain("s1")?.devices.has(id), true);
      assert.equal(cold.chain("s2")?.devices.has(id), true);
      const next = await a.runner.run(cold.signGrant("s2", body(), "why"));
      assert.equal(grantHolds(grantOf(next), STATION, "s2", cold.chain("s2")!.devices, NOW), 2_000_000_000);
      assert.equal(seals, 0, "recovery used the key that signed the existing lock");
    } finally { p.runner.shutdown(); }
  } finally { a.runner.shutdown(); }
});

test("interrupting one account's first key write does not let another replace the seed", async () => {
  const clouds = new Map([["s1", cloud()], ["s2", cloud()]]);
  const c = cloud();
  c.call = (sub, method, path, body) => clouds.get(sub)!.call(sub, method, path, body);
  const a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  const p = phone({ personal: a.lock, subs: () => [{ sub: "s1", email: "a@x" }, { sub: "s2", email: "b@x" }] });
  const seal = a.host.secureSet!;
  let held = false, seals = 0, seeds = 0;
  a.host.randomBytes = (bytes) => { bytes.fill(++seeds); };
  a.host.secureSet = (key, value, options) => {
    seals++;
    return Effect.andThen(Effect.sync(() => { held = true; }), Effect.andThen(Deferred.await(release), seal(key, value, options)));
  };
  try {
    const first = p.runner.fork(Effect.ignore(p.adb.run({ kind: "personalOpen", sub: "s1" })));
    for (let i = 0; i < 100 && !held; i++) await p.host.time.pass(10);
    assert.equal(held, true);
    const second = p.runner.run(p.adb.run({ kind: "personalOpen", sub: "s2" }));
    p.runner.interrupt(first);
    Deferred.doneUnsafe(release, Effect.void);
    await second;
    assert.equal(seals, 1);
    const seed = await a.runner.run(a.host.secureGet!("personal-signer", { user: true }));
    assert.ok(seed);
    const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load("s2"));
    assert.equal(cold.chain("s2")?.devices.has(id), true);
    const signed = await a.runner.run(cold.signGrant("s2", body(), "why"));
    assert.equal(grantHolds(grantOf(signed), STATION, "s2", cold.chain("s2")!.devices, NOW), 2_000_000_000);
    const firstChain = clouds.get("s1")!.kept.entries;
    if (firstChain.length > 0) assert.equal(checkChain(firstChain, "s1")?.devices.has(id), true);
  } finally { Deferred.doneUnsafe(release, Effect.void); p.runner.shutdown(); a.runner.shutdown(); }
});

test("a sealed seed that differs from the saved signer id cannot sign", async () => {
  const c = cloud(), a = device(c, "a");
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const before = a.lock.chain(SUB)?.hash;
    const get = a.host.secureGet!;
    a.host.secureGet = (key, options) => key === "personal-signer" && options.user
      ? Effect.succeed(new Uint8Array(32).fill(77)) : get(key, options);
    await assert.rejects(a.runner.run(a.lock.signGrant(SUB, body(), "why")), (error: unknown) => error instanceof CoreError && error.code === "personal_key_mismatch");
    assert.equal(a.lock.chain(SUB)?.hash, before);
    assert.equal(c.kept.entries.length, 1, "the mismatch cannot add an entry either");
    await assert.rejects(a.runner.run(a.lock.addDevice(SUB, { key: `ed25519:${"11".repeat(32)}`, id: "11".repeat(32), label: "x" }, "why")), (error: unknown) => error instanceof CoreError && error.code === "personal_key_mismatch");
  } finally { a.runner.shutdown(); }
});

test("a failed revocation write keeps the newest chain and suspends its authorizations until saved", async () => {
  const c = cloud();
  const request = c.call;
  let offline = false;
  c.call = (sub, method, path, body) => offline ? Effect.fail(new CoreError("offline", "offline")) : request(sub, method, path, body);
  const a = device(c, "a"), b = device(c, "b"), removed = device(cloud(), "c");
  const p = phone({ personal: a.lock, subOf: () => SUB, subs: () => [{ sub: SUB, email: "a@x" }] });
  const set = a.host.storageSet.bind(a.host);
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const bKey = await b.runner.run(b.lock.makeKey());
    const removedKey = await removed.runner.run(removed.lock.makeKey());
    await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "62".repeat(32), label: "b" }, "why"));
    await a.runner.run(a.lock.addDevice(SUB, { key: removedKey, id: "63".repeat(32), label: "c" }, "why"));
    await b.runner.run(b.lock.load(SUB));
    await b.runner.run(b.lock.joined(SUB, c.kept.entries, b.lock.joinGeneration(SUB)));
    const oldHead = a.lock.chain(SUB)!.hash;
    await b.runner.run(b.lock.removeDevice(SUB, removedKey, "why"));
    const signed = await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    p.adb.heard(STATION, grantOf(signed));
    a.host.storageSet = (key, value) => key.startsWith("personal-lock-")
      ? Effect.fail(new HostError("storage failed", true)) : set(key, value);
    await assert.rejects(a.runner.run(a.lock.refresh(SUB)), /storage failed/);
    assert.equal(a.lock.chain(SUB)?.hash, entryHash(c.kept.entries.at(-1)!), "the verified revocation remains in memory");
    assert.equal(a.lock.chain(SUB)?.devices.has(removedKey), false);
    assert.equal(a.lock.view(SUB).pending, true, "the account reports that the newer chain is not saved");
    assert.deepEqual(p.adb.wanted(), [], "even a remaining key's grant cannot start lending while saving failed");
    await assert.rejects(a.runner.run(a.lock.signGrant(SUB, body(), "why")), /storage|保存|saved/i);
    const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(cold.load(SUB));
    assert.equal(cold.chain(SUB)?.hash, oldHead, "a process that stops before a failed write has only the older saved chain");
    assert.equal(cold.chain(SUB)?.devices.has(removedKey), true, "offline restart cannot know the unsaved revocation");
    a.host.storageSet = set;
    offline = true;
    await p.runner.run(p.adb.run({ kind: "personalOpen", sub: SUB }));
    offline = false;
    assert.equal(a.lock.view(SUB).pending, false);
    assert.deepEqual(p.adb.wanted(), [STATION]);
    const again = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(again.load(SUB));
    assert.equal(again.chain(SUB)?.devices.has(removedKey), false, "retry persisted the revocation for restart");
  } finally {
    a.host.storageSet = set;
    p.runner.shutdown();
    a.runner.shutdown();
    b.runner.shutdown();
    removed.runner.shutdown();
  }
});

test("a live phone offer closes on an unsaved revocation and resumes after it is saved", async () => {
  const c = cloud(), a = device(c, "a"), b = device(c, "b"), removed = device(cloud(), "c");
  const set = a.host.storageSet.bind(a.host);
  let notify = () => {}, opened = 0, closed = 0;
  const link = {
    adb: () => Effect.sync(() => {
      opened++;
      return { status: 200, cancel: () => { closed++; }, body: { take: Effect.never } };
    }),
    accept: () => Effect.never,
    conn: { closed: () => Effect.never },
    closed: () => null,
  };
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(link), replaced: () => Effect.never } as unknown as Mesh;
  const lock = new PersonalLock({ host: a.host, runner: a.runner, cloud: c.call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => notify() });
  const p = phone({ personal: lock, mesh: () => Effect.succeed(mesh), subOf: () => SUB, subs: () => [{ sub: SUB, email: "a@x" }] });
  notify = () => p.adb.personalChanged();
  try {
    await a.runner.run(a.lock.signGrant(SUB, body(), "why"));
    const bKey = await b.runner.run(b.lock.makeKey());
    const removedKey = await removed.runner.run(removed.lock.makeKey());
    await a.runner.run(a.lock.addDevice(SUB, { key: bKey, id: "62".repeat(32), label: "b" }, "why"));
    await a.runner.run(a.lock.addDevice(SUB, { key: removedKey, id: "63".repeat(32), label: "c" }, "why"));
    await b.runner.run(b.lock.load(SUB));
    await b.runner.run(b.lock.joined(SUB, c.kept.entries, b.lock.joinGeneration(SUB)));
    await a.runner.run(lock.load(SUB));
    const signed = await b.runner.run(b.lock.signGrant(SUB, body(), "why"));
    await p.host.settle();
    await p.runner.run(p.adb.run({ kind: "on", on: true }));
    await p.runner.run(p.adb.run({ kind: "ports", ports: { connect: 5555, pair: null, device: "phone", android: "test", package: "test" } }));
    p.adb.heard(STATION, grantOf(signed));
    for (let i = 0; i < 100 && opened === 0; i++) await p.host.time.pass(10);
    assert.equal(opened, 1, "the grant opened a live station offer stream");
    await b.runner.run(b.lock.removeDevice(SUB, removedKey, "why"));
    a.host.storageSet = (key, value) => key.startsWith("personal-lock-")
      ? Effect.fail(new HostError("storage failed", true)) : set(key, value);
    await assert.rejects(a.runner.run(lock.refresh(SUB)), /storage failed/);
    for (let i = 0; i < 100 && closed === 0; i++) await p.host.time.pass(10);
    assert.equal(closed, 1, "the already-open offer stream was cancelled");
    assert.deepEqual(p.adb.wanted(), []);
    a.host.storageSet = set;
    await a.runner.run(lock.refresh(SUB));
    for (let i = 0; i < 100 && opened < 2; i++) await p.host.time.pass(10);
    assert.equal(opened, 2, "the still-valid grant offers the phone again after the save");
  } finally {
    a.host.storageSet = set;
    p.runner.shutdown();
    a.runner.shutdown();
    b.runner.shutdown();
    removed.runner.shutdown();
  }
});

test("a phone's startup refresh cannot lend after its pending load is forgotten", async () => {
  const c = cloud(), a = device(c, "a"), release = Deferred.makeUnsafe<void>();
  let fetched = false, held = false;
  const call = (sub: string, method: string, path: string, body: unknown) => Effect.map(c.call(sub, method, path, body), (answer) => {
    if (method === "GET") fetched = true;
    return answer;
  });
  const cold = new PersonalLock({ host: a.host, runner: a.runner, cloud: call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
  const p = phone({ personal: cold, subOf: () => SUB, subs: () => [{ sub: SUB, email: "a@x" }] });
  try {
    const signed = await a.runner.run(a.lock.signGrant(SUB, body({ exp: 4_000_000_000 }), "why"));
    const read = a.host.storageGet.bind(a.host);
    a.host.storageGet = (key) => key === "personal-signer-id"
      ? Effect.andThen(Effect.sync(() => { held = true; }), Effect.andThen(Deferred.await(release), read(key)))
      : read(key);
    p.adb.heard(STATION, { ...grantOf(signed), exp: 4_000_000_000 });
    p.adb.accountsKnown();
    for (let i = 0; i < 100 && !held; i++) await p.host.time.pass(10);
    assert.equal(held, true, "the startup refresh read the chain and waits for the key");
    await p.runner.run(p.adb.run({ kind: "personalForget", sub: SUB }));
    Deferred.doneUnsafe(release, Effect.void);
    for (let i = 0; i < 100 && !fetched; i++) await p.host.time.pass(10);
    await p.host.time.pass(10);
    assert.equal(fetched, true);
    assert.equal(cold.chain(SUB)?.hash, null);
    assert.equal(cold.standing(SUB), "outside", "the cloud's lock was heard but not pinned again");
    assert.deepEqual(p.adb.wanted(), [], "the previously signed grant cannot lend from a forgotten lock");
    const restarted = new PersonalLock({ host: a.host, runner: a.runner, cloud: call, device: () => Effect.succeed("61".repeat(32)), label: () => "a", changed: () => {} });
    await a.runner.run(restarted.load(SUB));
    assert.equal(restarted.standing(SUB), "outside", "the unpinned cloud lock heard after forgetting remains known");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    p.runner.shutdown();
    a.runner.shutdown();
  }
});

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
  const old = (id: string, chat: string) => ({ id, session: `s-${id}`, chat, scope: id === "g3" ? "chat" : "hour", status: "granted", exp: id === "g2" ? Math.floor(host.nowMs() / 1000) + 900 : 4_000_000_000, at: 1 });
  const link = {
    adb: (_h: unknown, ask: Record<string, unknown>) => Effect.sync(() => {
      said.push(ask);
      if (ask.op === "grants") return answer({ grants: [old("g1", "c1"), old("g2", "c2"), old("g3", "c3")], signs: true });
      return answer({ request: { ...old(ask.request as string, `c${(ask.request as string).slice(1)}`), signed: ask.signed } });
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
    assert.equal((adb.value() as { toConfirm: number }).toConfirm, 3);
    const before = a.asks.n;
    await runner.run(adb.run({ kind: "personalConfirm" }));
    assert.equal(a.asks.n, before + 1, "asked once for all three");
    const signatures = said.filter((x) => x.op === "sign");
    assert.equal(signatures.length, 3);
    const expiry = (x: Record<string, unknown>) => (x.signed as { body: { exp: number } }).body.exp;
    const now = Math.floor(host.nowMs() / 1000);
    assert.equal(expiry(signatures[0]!), now + 3600, "an old hour grant cannot last longer than an hour from confirmation");
    assert.equal(expiry(signatures[1]!), now + 900, "confirmation never extends an earlier expiry");
    assert.equal(expiry(signatures[2]!), now + 30 * 86400, "a chat grant lasts at most thirty days from confirmation");
    assert.equal(adb.grants().find((g) => g.id === "g1").exp, now + 3600, "the visible expiry is the one signed");
    await host.settle();
    const kept = JSON.parse(new TextDecoder().decode(host.storage.get(GRANTS_KEY)!)) as Record<string, { id: string; exp: number }[]>;
    assert.equal(kept[STATION]!.find((g) => g.id === "g1")!.exp, now + 3600, "the saved expiry cannot outlast the signature");
    assert.deepEqual(adb.wanted(), [STATION]);
    assert.equal((adb.value() as { toConfirm: number }).toConfirm, 0);
  } finally {
    runner.shutdown();
    a.runner.shutdown();
  }
});
