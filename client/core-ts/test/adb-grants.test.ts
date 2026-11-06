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

function phoneWith(host: FakeHost) {
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const link = {
    adb: (_head: unknown, ask: { request: string }) => {
      let sent = false;
      const bytes = new TextEncoder().encode(JSON.stringify({ request: { id: ask.request, status: "ended" } }));
      return Effect.succeed({ status: 200, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } });
    },
  };
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(link) } as unknown as Mesh;
  const adb = new Adb({ ...personalStub(), host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => true });
  takeAll(adb);
  return { runner, adb };
}

const liveGrant = (host: FakeHost, id: string) => ({ id, chat: id, session: id, reason: "debug", status: "granted", exp: Math.floor(host.nowMs() / 1000) + 3600, at: 1 });

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

for (const corrupt of ["failed", "invalid json", "invalid value", "invalid chat metadata"] as const) {
  test(`a ${corrupt} revocation read cannot silently permit lending`, async () => {
    const host = new FakeHost(), read = host.storageGet.bind(host);
    host.store(ON_KEY, false);
    host.storageGet = (key) => key === REVOKED_KEY
      ? corrupt === "failed" ? Effect.fail(new HostError("revocations unreadable", true))
        : Effect.succeed(new TextEncoder().encode(corrupt === "invalid json" ? "invalid" : corrupt === "invalid chat metadata" ? JSON.stringify({ "\u0000stillfail-chats-v1": { bad: [] } }) : '{"p1":"not a deadline"}'))
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
