import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { Adb, GRANTS_KEY, ON_KEY, REVOKED_KEY } from "../src/adb.ts";
import { HostError } from "../src/error.ts";
import { canonical } from "../src/lock.ts";
import type { Mesh } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost, flush } from "../src/testing.ts";
import { hex, sha256, utf8 } from "../src/util.ts";
import { personalStub, takeAll } from "./adb-personal-stub.ts";

function phoneWith(host: FakeHost, listed?: unknown[], overrideLink?: unknown) {
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const link = {
    adb: (_head: unknown, ask: { op: string; request: string }) => {
      let sent = false;
      const answer = ask.op === "grants" && listed !== undefined ? { grants: listed, signs: true } : { request: { id: ask.request, status: "ended" } };
      const bytes = new TextEncoder().encode(JSON.stringify(answer));
      return Effect.succeed({ status: 200, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } });
    },
  };
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(overrideLink ?? link) } as unknown as Mesh;
  const adb = new Adb({ ...personalStub(), host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => true });
  takeAll(adb);
  return { runner, adb };
}

const liveGrant = (host: FakeHost, id: string) => ({ id, chat: id, session: id, reason: "debug", status: "granted", exp: Math.floor(host.nowMs() / 1000) + 3600, at: 1 });

/// Copy only the bytes that survived, not shared in-memory state: as after the app process is gone.
function restartedHost(old: FakeHost): FakeHost {
  const host = new FakeHost();
  for (const [key, value] of old.storage) host.storage.set(key, value.slice());
  return host;
}

test("expired grant identities are kept without their old details until a complete station read", async () => {
  const host = new FakeHost();
  const p = phoneWith(host, []);
  try {
    await flush();
    p.adb.heard("ws/st", { ...liveGrant(host, "old"), exp: Math.floor(host.nowMs() / 1000) - 1, reason: "x".repeat(16_384) });
    await flush();
    assert.deepEqual(p.adb.grants(), [], "an expired row is not presented as a live grant");
    assert.deepEqual(p.adb.wanted(), [], "the retained identity cannot lend");
    const saved = JSON.parse(new TextDecoder().decode(host.storage.get(GRANTS_KEY)!));
    assert.deepEqual(saved, { "ws/st": [{ id: "old", status: "granted", exp: 0 }] }, "only the expired request identity is kept");
    await p.runner.run(p.adb.readGrants("ws/st"));
    await flush();
    const after = JSON.parse(new TextDecoder().decode(host.storage.get(GRANTS_KEY)!));
    assert.equal(after["ws/st"][0].id, "old", "the grant cache keeps the ended identity too");
    assert.equal(after["ws/st"][0].exp, 0, "the marker cannot lend");
    assert.equal(after["ws/st"][0].reason, undefined, "old grant details are not retained");
    assert.ok(host.storage.has(REVOKED_KEY), "the missing request has a durable denial");
  } finally { await p.runner.shutdown(); }
});

test("a remote take-back survives an earlier grant snapshot finishing last", async () => {
  const host = new FakeHost(), set = host.storageSet.bind(host), release = Deferred.makeUnsafe<void>();
  const reached = Promise.withResolvers<void>(), cleared = Promise.withResolvers<void>();
  host.store(ON_KEY, true);
  const p = phoneWith(host);
  let restarted: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    let first = true;
    host.storageSet = (key, value) => {
      if (key !== GRANTS_KEY) return set(key, value);
      if (first) {
        first = false;
        return Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), set(key, value)));
      }
      return Effect.andThen(set(key, value), Effect.sync(() => cleared.resolve()));
    };
    p.adb.heard("ws/st", liveGrant(host, "p1"));
    await reached.promise;
    p.adb.heard("ws/st", { id: "p1", status: "ended" });
    await flush();
    // Without serialization the newer empty snapshot can finish before the delayed older one.
    Deferred.doneUnsafe(release, Effect.void);
    await cleared.promise;
    await flush();
    const saved = JSON.parse(new TextDecoder().decode(host.storage.get(GRANTS_KEY)!));
    assert.equal(saved["ws/st"][0].exp, 0, "the older live snapshot does not finish last");
    await p.runner.shutdown();
    restarted = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(restarted.adb.wanted(), [], "the ended grant cannot lend after an offline process restart");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    host.storageSet = set;
    await p.runner.shutdown();
    if (restarted) await restarted.runner.shutdown();
  }
});

test("a station cannot forge a locally saved terminal marker on a live grant", async () => {
  const host = new FakeHost();
  host.store(ON_KEY, true);
  const p = phoneWith(host);
  let cold: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    p.adb.heard("ws/st", { ...liveGrant(host, "p1"), "\u0000stillfail-remote-end-v1": true });
    await flush();
    assert.deepEqual(p.adb.wanted(), ["ws/st"]);
    cold = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(cold.adb.wanted(), ["ws/st"], "station data is not restored as a local take-back");
  } finally {
    await p.runner.shutdown();
    if (cold) await cold.runner.shutdown();
  }
});

test("a saved terminal marker wins over a grant heard while the cache is loading", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), release = Deferred.makeUnsafe<void>();
  const reached = Promise.withResolvers<void>();
  host.store(ON_KEY, true);
  host.store(GRANTS_KEY, { "ws/st": [{ id: "p1", status: "granted", exp: 0, "\u0000stillfail-remote-end-v1": true }] });
  host.storageGet = (key) => key === GRANTS_KEY
    ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host);
  try {
    await reached.promise;
    p.adb.heard("ws/st", liveGrant(host, "p1"));
    Deferred.doneUnsafe(release, Effect.void);
    await flush();
    assert.deepEqual(p.adb.wanted(), [], "loading cannot let an earlier terminal record be replaced by a replay");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    await p.runner.shutdown();
  }
});

test("a remote take-back survives a failed grant-cache removal when its denial was saved", async () => {
  const host = new FakeHost(), set = host.storageSet.bind(host);
  host.store(ON_KEY, true);
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
  const p = phoneWith(host);
  let restarted: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    assert.deepEqual(p.adb.wanted(), ["ws/st"]);
    host.storageSet = (key, value) => key === GRANTS_KEY ? Effect.fail(new HostError("grant cache save failed", true)) : set(key, value);
    p.adb.heard("ws/st", { id: "p1", status: "ended" });
    await flush();
    await p.runner.shutdown();
    restarted = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(restarted.adb.wanted(), [], "a saved take-back overrides the stale cached grant");
  } finally {
    host.storageSet = set;
    await p.runner.shutdown();
    if (restarted) await restarted.runner.shutdown();
  }
});

test("a whole station read persists a missing grant even if its cache removal fails", async () => {
  const host = new FakeHost(), set = host.storageSet.bind(host);
  host.store(ON_KEY, true);
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
  const p = phoneWith(host, []);
  let restarted: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    assert.deepEqual(p.adb.wanted(), ["ws/st"]);
    host.storageSet = (key, value) => key === GRANTS_KEY ? Effect.fail(new HostError("grant cache save failed", true)) : set(key, value);
    await p.runner.run(p.adb.readGrants("ws/st"));
    await flush();
    await p.runner.shutdown();
    restarted = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(restarted.adb.wanted(), [], "the older saved grant cannot return while offline");
  } finally {
    host.storageSet = set;
    await p.runner.shutdown();
    if (restarted) await restarted.runner.shutdown();
  }
});

test("a station read waits for the old grant cache before recording missing grants", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), set = host.storageSet.bind(host);
  const reached = Promise.withResolvers<void>(), release = Deferred.makeUnsafe<void>();
  host.store(ON_KEY, true);
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
  host.storageGet = (key) => key === GRANTS_KEY
    ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host, []);
  let restarted: ReturnType<typeof phoneWith> | undefined;
  try {
    await reached.promise;
    host.storageSet = (key, value) => key === GRANTS_KEY ? Effect.fail(new HostError("grant cache save failed", true)) : set(key, value);
    let complete = false;
    const reading = p.runner.run(p.adb.readGrants("ws/st")).then(() => { complete = true; });
    await flush();
    assert.equal(complete, false, "the station's empty list cannot run ahead of the local read");
    Deferred.doneUnsafe(release, Effect.void);
    await reading;
    await flush();
    await p.runner.shutdown();
    restarted = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(restarted.adb.wanted(), [], "the omitted cached grant was recorded as ended");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    host.storageGet = read;
    host.storageSet = set;
    await p.runner.shutdown();
    if (restarted) await restarted.runner.shutdown();
  }
});

test("an unreadable grant cache cannot make a station's empty list erase an unknown take-back", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), set = host.storageSet.bind(host);
  host.store(ON_KEY, true);
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
  host.storageGet = (key) => key === GRANTS_KEY ? Effect.fail(new HostError("grant cache unreadable", true)) : read(key);
  host.storageSet = (key, value) => key === GRANTS_KEY ? Effect.fail(new HostError("grant cache unwritable", true)) : set(key, value);
  const p = phoneWith(host, []);
  let restarted: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    assert.equal(p.adb.value().known, false, "an unreadable cache is not an empty cache");
    assert.equal(p.adb.value().revocationsError, true);
    await assert.rejects(p.runner.run(p.adb.readGrants("ws/st")));
    host.storageGet = read;
    await p.runner.run(p.adb.run({ kind: "retryRevocations" }));
    await p.runner.run(p.adb.readGrants("ws/st"));
    await flush();
    await p.runner.shutdown();
    restarted = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(restarted.adb.wanted(), [], "the later successful read lets the missing grant be remembered");
  } finally {
    host.storageGet = read;
    host.storageSet = set;
    await p.runner.shutdown();
    if (restarted) await restarted.runner.shutdown();
  }
});

test("a pending cache read does not keep a closing core alive", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), release = Deferred.makeUnsafe<void>();
  const reached = Promise.withResolvers<void>();
  host.storageGet = (key) => key === GRANTS_KEY
    ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host);
  try {
    await reached.promise;
    p.adb.heard("ws/st", { id: "p1", status: "ended" });
    await flush();
    let closed = false;
    const closing = p.runner.shutdown().then(() => { closed = true; });
    await flush();
    assert.equal(closed, true, "waiting for a cache read must be interruptible when the core closes");
    await closing;
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    host.storageGet = read;
    await p.runner.shutdown();
  }
});

test("a grant heard during the cache read preserves unrelated saved grants", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), release = Deferred.makeUnsafe<void>();
  const reached = Promise.withResolvers<void>();
  host.store(ON_KEY, true);
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "old"), liveGrant(host, "unrelated")] });
  host.storageGet = (key) => key === GRANTS_KEY
    ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host);
  let cold: ReturnType<typeof phoneWith> | undefined;
  try {
    await reached.promise;
    p.adb.heard("ws/st", { id: "old", status: "ended" });
    p.adb.heard("ws/st", liveGrant(host, "new"));
    Deferred.doneUnsafe(release, Effect.void);
    await flush();
    await p.runner.shutdown();
    cold = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(cold.adb.grants().map((g) => g.id).sort(), ["new", "unrelated"]);
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    host.storageGet = read;
    await p.runner.shutdown();
    if (cold) await cold.runner.shutdown();
  }
});

for (const corrupt of ["invalid json", "invalid rows"] as const) {
  test(`a ${corrupt} grant cache pauses lending until it can be read`, async () => {
    const host = new FakeHost(), read = host.storageGet.bind(host);
    host.store(ON_KEY, true);
    host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
    host.storageGet = (key) => key === GRANTS_KEY
      ? Effect.succeed(new TextEncoder().encode(corrupt === "invalid json" ? "invalid" : '{"ws/st":[{"id":"p1"}]}')) : read(key);
    const p = phoneWith(host);
    try {
      await flush();
      assert.equal(p.adb.value().known, false);
      assert.equal(p.adb.value().revocationsError, true);
      assert.deepEqual(p.adb.wanted(), []);
      host.storageGet = read;
      await p.runner.run(p.adb.run({ kind: "retryRevocations" }));
      assert.deepEqual(p.adb.wanted(), ["ws/st"]);
    } finally { host.storageGet = read; await p.runner.shutdown(); }
  });
}

test("a failed remote denial pauses lending until it is saved, without denying another station's request", async () => {
  const host = new FakeHost(), set = host.storageSet.bind(host);
  host.store(ON_KEY, true);
  const p = phoneWith(host);
  let restarted: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    p.adb.heard("ws/st", liveGrant(host, "same"));
    p.adb.heard("ws/other", liveGrant(host, "same"));
    await flush();
    host.storageSet = (key, value) => key === REVOKED_KEY ? Effect.fail(new HostError("denial save failed", true)) : set(key, value);
    p.adb.heard("ws/st", { id: "same", status: "ended" });
    await flush();
    assert.deepEqual(p.adb.wanted(), [], "a denial that could not be saved pauses all lending");
    assert.equal(p.adb.value().revocationsError, true);
    host.storageSet = set;
    await p.runner.run(p.adb.run({ kind: "retryRevocations" }));
    p.adb.heard("ws/st", liveGrant(host, "same"));
    await flush();
    assert.deepEqual(p.adb.wanted(), ["ws/other"], "the ended id cannot be replayed, but the other station's id is independent");
    await p.runner.shutdown();
    restarted = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(restarted.adb.wanted(), ["ws/other"]);
  } finally {
    host.storageSet = set;
    await p.runner.shutdown();
    if (restarted) await restarted.runner.shutdown();
  }
});

test("overlapping cores save one ordered view of grants on their shared host", async () => {
  const host = new FakeHost(), set = host.storageSet.bind(host), release = Deferred.makeUnsafe<void>();
  const reached = Promise.withResolvers<void>();
  host.store(ON_KEY, true);
  const a = phoneWith(host), b = phoneWith(host);
  let restarted: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    let first = true;
    host.storageSet = (key, value) => {
      if (key !== GRANTS_KEY || !first) return set(key, value);
      first = false;
      return Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), set(key, value)));
    };
    a.adb.heard("ws/a", liveGrant(host, "p1"));
    await reached.promise;
    b.adb.heard("ws/b", liveGrant(host, "p2"));
    Deferred.doneUnsafe(release, Effect.void);
    await flush();
    await Promise.all([a.runner.shutdown(), b.runner.shutdown()]);
    restarted = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(restarted.adb.wanted().sort(), ["ws/a", "ws/b"], "neither core overwrites the other's grant");
  } finally {
    Deferred.doneUnsafe(release, Effect.void);
    host.storageSet = set;
    await Promise.all([a.runner.shutdown(), b.runner.shutdown()]);
    if (restarted) await restarted.runner.shutdown();
  }
});

test("overlapping station reads cannot mistake a newer grant for an ended one", async () => {
  const host = new FakeHost(), reached = Promise.withResolvers<void>();
  const release = Promise.withResolvers<unknown>();
  host.store(ON_KEY, true);
  const response = (grants: unknown[]) => {
    let sent = false;
    const bytes = new TextEncoder().encode(JSON.stringify({ grants, signs: true }));
    return { status: 200, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } };
  };
  let calls = 0;
  const link = { adb: () => Effect.suspend(() => {
    calls++;
    if (calls === 1) { reached.resolve(); return Effect.promise(() => release.promise); }
    return Effect.succeed(response([liveGrant(host, "new")]));
  }) };
  const a = phoneWith(host, undefined, link), b = phoneWith(host, undefined, link);
  let cold: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    const first = a.runner.run(a.adb.readGrants("ws/st"));
    await reached.promise;
    const second = b.runner.run(b.adb.readGrants("ws/st"));
    await flush();
    release.resolve(response([]));
    await Promise.all([first, second]);
    await flush();
    assert.deepEqual(a.adb.grants().map((g) => g.id), ["new"], "the older empty reply cannot erase a newer grant");
    await Promise.all([a.runner.shutdown(), b.runner.shutdown()]);
    cold = phoneWith(restartedHost(host));
    await flush();
    assert.deepEqual(cold.adb.wanted(), ["ws/st"], "a valid grant was not permanently marked ended");
  } finally {
    release.resolve(response([]));
    await Promise.all([a.runner.shutdown(), b.runner.shutdown()]);
    if (cold) await cold.runner.shutdown();
  }
});

test("a station read that never answers does not block the next one forever", async () => {
  const host = new FakeHost(), reached = Promise.withResolvers<void>();
  const never = Promise.withResolvers<unknown>();
  host.store(ON_KEY, true);
  let calls = 0;
  const link = { adb: () => Effect.suspend(() => {
    calls++;
    if (calls === 1) { reached.resolve(); return Effect.promise(() => never.promise); }
    let sent = false;
    const bytes = new TextEncoder().encode(JSON.stringify({ grants: [liveGrant(host, "new")], signs: true }));
    return Effect.succeed({ status: 200, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } });
  }) };
  const p = phoneWith(host, undefined, link);
  try {
    await flush();
    const first = p.runner.run(p.adb.readGrants("ws/st"));
    await reached.promise;
    const second = p.runner.run(p.adb.readGrants("ws/st"));
    await flush();
    await host.time.pass(60_001, 1_000);
    await Promise.all([first, second]);
    assert.deepEqual(p.adb.wanted(), ["ws/st"]);
  } finally { never.resolve(null); await p.runner.shutdown(); }
});

test("a malformed station list cannot be mistaken for an empty one", async () => {
  const host = new FakeHost();
  host.store(ON_KEY, true);
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
  const p = phoneWith(host, [{ id: "p1" }]);
  try {
    await flush();
    await p.runner.run(p.adb.readGrants("ws/st"));
    assert.deepEqual(p.adb.wanted(), ["ws/st"]);
  } finally { await p.runner.shutdown(); }
});

test("a phone waits for saved revocations before lending after restart", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  host.store(REVOKED_KEY, { p1: Math.floor(host.nowMs() / 1000) + 3600 });
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
  host.store(ON_KEY, true);
  host.storageGet = (key) => key === REVOKED_KEY ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host);
  try {
    await reached.promise;
    await flush();
    assert.deepEqual(p.adb.wanted(), [], "a grant cannot lend while its revocations are still loading");
    assert.equal(p.adb.value().known, false);
    Deferred.doneUnsafe(release, Effect.void);
    await flush();
    assert.deepEqual(p.adb.wanted(), [], "the saved revocation remains effective");
  } finally { Deferred.doneUnsafe(release, Effect.void); p.runner.shutdown(); }
});

for (const corrupt of ["failed", "invalid json", "invalid value", "invalid chat metadata", "invalid remote metadata"] as const) {
  test(`a ${corrupt} revocation read cannot silently permit lending`, async () => {
    const host = new FakeHost(), read = host.storageGet.bind(host);
    host.store(ON_KEY, false);
    host.storageGet = (key) => key === REVOKED_KEY
      ? corrupt === "failed" ? Effect.fail(new HostError("revocations unreadable", true))
        : Effect.succeed(new TextEncoder().encode(corrupt === "invalid json" ? "invalid" : corrupt === "invalid chat metadata" ? JSON.stringify({ "\u0000stillfail-chats-v1": { bad: [] } }) : corrupt === "invalid remote metadata" ? JSON.stringify({ "\u0000stillfail-remote-ends-v1": { bad: 42 } }) : '{"p1":"not a deadline"}'))
      : read(key);
    const p = phoneWith(host);
    try {
      p.adb.heard("ws/st", liveGrant(host, "p1"));
      await flush();
      assert.deepEqual(p.adb.wanted(), []);
      assert.equal(p.adb.value().known, false);
      assert.equal(p.adb.value().revocationsError, true);
      host.storageGet = read;
      await p.runner.run(p.adb.run({ kind: "retryRevocations" }));
      assert.equal(p.adb.value().revocationsError, false);
      assert.equal(p.adb.value().on, false, "retrying does not turn sharing on");
      assert.deepEqual(p.adb.wanted(), ["ws/st"], "a successful retry resumes an unrevoked grant");
    } finally { host.storageGet = read; p.runner.shutdown(); }
  });
}

test("two overlapping revocations cannot save an older snapshot last", async () => {
  const host = new FakeHost(), set = host.storageSet.bind(host), release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  let first = true;
  host.storageSet = (key, value) => {
    if (key !== REVOKED_KEY || !first) return set(key, value);
    first = false;
    return Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), set(key, value)));
  };
  const p = phoneWith(host);
  try {
    await flush();
    p.adb.heard("ws/st", liveGrant(host, "p1"));
    p.adb.heard("ws/st", liveGrant(host, "p2"));
    const one = p.runner.run(p.adb.run({ kind: "revoke", station: "ws/st", request: "p1" }));
    await reached.promise;
    const two = p.runner.run(p.adb.run({ kind: "revoke", station: "ws/st", request: "p2" }));
    await flush();
    Deferred.doneUnsafe(release, Effect.void);
    await Promise.all([one, two]);
    await flush();
    const saved = JSON.parse(new TextDecoder().decode(host.storage.get(REVOKED_KEY)!)) as Record<string, number>;
    assert.ok(Object.hasOwn(saved, "p1"));
    assert.ok(Object.hasOwn(saved, "p2"), "the second revocation is not lost to the delayed first save");
  } finally { Deferred.doneUnsafe(release, Effect.void); host.storageSet = set; p.runner.shutdown(); }
});

test("a take-back made during a delayed read cannot restore an older local approval", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  const signed = { body: { nonce: 1 }, sig: { key: "k", sig: "s" } };
  const fingerprint = hex(sha256(utf8(canonical(signed))));
  const scope = JSON.stringify(["ws/st", "chat"]);
  host.store(REVOKED_KEY, { "\u0000stillfail-chats-v1": { [scope]: { [fingerprint]: Math.floor(host.nowMs() / 1000) + 3600 } } });
  host.storageGet = (key) => key === REVOKED_KEY ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host);
  try {
    await reached.promise;
    p.adb.heard("ws/st", { ...liveGrant(host, "p1"), chat: "chat", signed });
    const taken = p.runner.run(p.adb.run({ kind: "revoke", station: "ws/st", request: "p1", chat: "chat" }));
    Deferred.doneUnsafe(release, Effect.void);
    await taken;
    assert.deepEqual(p.adb.wanted(), [], "the delayed older allowance cannot undo the new take-back");
    const kept = JSON.parse(new TextDecoder().decode(host.storage.get(REVOKED_KEY)!));
    assert.deepEqual(kept["\u0000stillfail-chats-v1"][scope], {});
  } finally { Deferred.doneUnsafe(release, Effect.void); host.storageGet = read; p.runner.shutdown(); }
});

test("a revoke made while saved revocations are loading keeps both", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  host.store(REVOKED_KEY, { p1: 1 });
  host.storageGet = (key) => key === REVOKED_KEY ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host);
  try {
    await reached.promise;
    p.adb.heard("ws/st", liveGrant(host, "p1"));
    p.adb.heard("ws/st", liveGrant(host, "p2"));
    const taken = p.runner.run(p.adb.run({ kind: "revoke", station: "ws/st", request: "p2" }));
    Deferred.doneUnsafe(release, Effect.void);
    await taken;
    assert.deepEqual(p.adb.wanted(), []);
    const saved = JSON.parse(new TextDecoder().decode(host.storage.get(REVOKED_KEY)!)) as Record<string, number>;
    assert.ok(Object.hasOwn(saved, "p1") && Object.hasOwn(saved, "p2"));
  } finally { Deferred.doneUnsafe(release, Effect.void); host.storageGet = read; await p.runner.shutdown(); }
});

for (const committed of [false, true]) {
  test(`a revocation save failure ${committed ? "after" : "before"} writing pauses lending until retry`, async () => {
    const host = new FakeHost(), set = host.storageSet.bind(host);
    host.store(ON_KEY, true);
    const p = phoneWith(host);
    try {
      await flush();
      p.adb.heard("ws/st", liveGrant(host, "p1"));
      // This unrelated chat has a binding attested by its signer. Unbound old grants are conservatively paused by any
      // take-back at the same station and are covered separately by personal-lock.test.ts.
      p.adb.heard("ws/st", { ...liveGrant(host, "p2"), signed: { body: { chatBound: true }, sig: { key: "k", sig: "s" } } });
      assert.deepEqual(p.adb.wanted(), ["ws/st"]);
      host.storageSet = (key, value) => key !== REVOKED_KEY ? set(key, value) : committed
        ? Effect.andThen(set(key, value), Effect.fail(new HostError("save failed", true)))
        : Effect.fail(new HostError("save failed", true));
      await assert.rejects(p.runner.run(p.adb.run({ kind: "revoke", station: "ws/st", request: "p1", chat: "p1" })));
      assert.deepEqual(p.adb.wanted(), [], "no grant lends while the local save is uncertain");
      assert.equal(p.adb.value().revocationsError, true);
      host.storageSet = set;
      await p.runner.run(p.adb.run({ kind: "retryRevocations" }));
      assert.equal(p.adb.value().on, true, "retry preserves the switch");
      assert.equal(p.adb.value().revocationsError, false);
      assert.deepEqual(p.adb.wanted(), ["ws/st"], "the other, unrevoked grant can lend again");
      p.adb.heard("ws/st", { ...liveGrant(host, "p2"), status: "ended" });
      assert.deepEqual(p.adb.wanted(), [], "the taken-back grant stays denied");
    } finally { host.storageSet = set; await p.runner.shutdown(); }
  });
}

test("a core reopened while a detached revoke is saving shares its pending denials", async () => {
  const host = new FakeHost(), set = host.storageSet.bind(host), release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  host.store(ON_KEY, true);
  let first = true;
  host.storageSet = (key, value) => {
    if (key !== REVOKED_KEY || !first) return set(key, value);
    first = false;
    return Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), set(key, value)));
  };
  const a = phoneWith(host);
  let b: ReturnType<typeof phoneWith> | undefined;
  try {
    await flush();
    a.adb.heard("ws/st", liveGrant(host, "p1"));
    const one = a.runner.run(a.adb.run({ kind: "revoke", station: "ws/st", request: "p1" }));
    await reached.promise;
    await a.runner.shutdown();
    b = phoneWith(host);
    b.adb.heard("ws/st", liveGrant(host, "p1"));
    b.adb.heard("ws/st", liveGrant(host, "p2"));
    assert.deepEqual(b.adb.wanted(), [], "a new core cannot lend while the older write is pending");
    const two = b.runner.run(b.adb.run({ kind: "revoke", station: "ws/st", request: "p2" }));
    Deferred.doneUnsafe(release, Effect.void);
    await Promise.all([one, two]);
    assert.deepEqual(b.adb.wanted(), []);
    const saved = JSON.parse(new TextDecoder().decode(host.storage.get(REVOKED_KEY)!)) as Record<string, number>;
    assert.ok(Object.hasOwn(saved, "p1") && Object.hasOwn(saved, "p2"));
  } finally { Deferred.doneUnsafe(release, Effect.void); host.storageSet = set; await a.runner.shutdown(); if (b) await b.runner.shutdown(); }
});

test("a phone upgrading from before the switch waits for revocations before restoring sharing", async () => {
  const host = new FakeHost(), read = host.storageGet.bind(host), release = Deferred.makeUnsafe<void>(), reached = Promise.withResolvers<void>();
  host.store(GRANTS_KEY, { "ws/st": [liveGrant(host, "p1")] });
  host.storageGet = (key) => key === REVOKED_KEY ? Effect.andThen(Effect.sync(() => reached.resolve()), Effect.andThen(Deferred.await(release), read(key))) : read(key);
  const p = phoneWith(host);
  try {
    await reached.promise;
    await flush();
    assert.equal(p.adb.value().on, false);
    Deferred.doneUnsafe(release, Effect.void);
    await flush();
    assert.equal(p.adb.value().on, true, "a live unrevoked grant preserves the former sharing state");
    assert.deepEqual(p.adb.wanted(), ["ws/st"]);
  } finally { Deferred.doneUnsafe(release, Effect.void); host.storageGet = read; await p.runner.shutdown(); }
});

test("taking back a chat takes back every grant behind its one row", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const requests: string[] = [];
  const link = {
    adb: (_head: unknown, ask: { op: string; request: string }) => Effect.sync(() => {
      assert.equal(ask.op, "revoke");
      requests.push(ask.request);
      let sent = false;
      const bytes = new TextEncoder().encode(JSON.stringify({ request: { id: ask.request, status: "ended" } }));
      return { status: 200, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } };
    }),
  };
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(link) } as unknown as Mesh;
  const adb = new Adb({ ...personalStub(), host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => false });
  takeAll(adb);
  const exp = Math.floor(host.nowMs() / 1000) + 3600;
  const grant = (id: string, chat: string) => ({ id, chat, session: id, reason: "debug", status: "granted", exp, at: 1 });
  try {
    adb.heard("ws/st", grant("p1", "chat-a"));
    adb.heard("ws/st", grant("p2", "chat-a"));
    adb.heard("ws/st", grant("p3", "chat-b"));
    adb.heard("ws/other", grant("p4", "chat-a"));
    // An older cached grant may know its session but not the chat address yet.
    const older = (id: string) => ({ id, session: "older-session", reason: "debug", status: "granted", exp, at: 1 });
    adb.heard("ws/st", older("old1"));
    adb.heard("ws/st", older("old2"));
    assert.equal(adb.grants().length, 4);
    await runner.run(adb.run({ kind: "revoke", station: "ws/st", request: "p2", chat: "chat-a" }));
    assert.deepEqual(requests, ["p1", "p2"]);
    await runner.run(adb.run({ kind: "revoke", station: "ws/st", request: "old1" }));
    assert.deepEqual(requests, ["p1", "p2", "old1", "old2"]);
    assert.deepEqual(adb.grants().map((g) => g.id).sort(), ["p3", "p4"]);
  } finally {
    runner.shutdown();
  }
});

test("a late whole read does not bring back a grant already taken back", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  let started!: () => void;
  const asked = new Promise<void>((resolve) => { started = resolve; });
  let answer!: (value: unknown) => void;
  const waiting = new Promise<unknown>((resolve) => { answer = resolve; });
  const link = { adb: () => Effect.promise(() => { started(); return waiting; }) };
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(link) } as unknown as Mesh;
  const adb = new Adb({ ...personalStub(), host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => false });
  takeAll(adb);
  const grant = { id: "p1", chat: "chat-a", session: "s1", reason: "debug", status: "granted", exp: Math.floor(host.nowMs() / 1000) + 3600, at: 1 };
  try {
    adb.heard("ws/st", grant);
    const read = runner.run(adb.readGrants("ws/st"));
    await asked;
    adb.heard("ws/st", { ...grant, status: "ended" });
    let sent = false;
    const bytes = new TextEncoder().encode(JSON.stringify({ grants: [grant] }));
    answer({ status: 200, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } });
    await read;
    assert.deepEqual(adb.grants(), []);
  } finally {
    runner.shutdown();
  }
});
