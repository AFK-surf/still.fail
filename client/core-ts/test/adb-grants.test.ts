import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Adb } from "../src/adb.ts";
import type { Mesh } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { personalStub, takeAll } from "./adb-personal-stub.ts";

test("taking back a chat takes back every grant behind its one row", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const requests: string[] = [];
  const link = {
    ask: (_head: unknown, { adb: ask }: { adb: { op: string; request: string } }) => Effect.sync(() => {
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
    await runner.run(adb.run({ kind: "revoke", station: "ws/st", request: "p2" }));
    assert.deepEqual(requests, ["p1", "p2"]);
    await runner.run(adb.run({ kind: "revoke", station: "ws/st", request: "old1" }));
    assert.deepEqual(requests, ["p1", "p2", "old1", "old2"]);
    assert.deepEqual(adb.grants().map((g) => g.id).sort(), ["p3", "p4"]);
  } finally {
    runner.shutdown();
  }
});

test("a station's refusal keeps the code it gives (the app goes by it), its words the message; none, invalid_params", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  let body: unknown = null;
  const link = {
    ask: () => Effect.sync(() => {
      let sent = false;
      const bytes = new TextEncoder().encode(JSON.stringify(body));
      return { status: 422, body: { take: Effect.sync(() => { if (sent) return null; sent = true; return bytes; }) } };
    }),
  };
  const mesh = { deviceId: () => "phone", link: () => Effect.succeed(link) } as unknown as Mesh;
  const adb = new Adb({ ...personalStub(), host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => false });
  takeAll(adb);
  try {
    const failed = () => runner.run(Effect.flip(adb.run({ kind: "revoke", station: "ws/st", request: "p1" })));
    body = { message: "手机不允许 adb 授权", code: "adb_grant_refused" };
    const refused = await failed();
    assert.deepEqual([refused.code, refused.message], ["adb_grant_refused", "手机不允许 adb 授权"]);
    // (a station from before codes, or another failure: no code of its own)
    body = { message: "授权失败：Error: Unknown permission" };
    const other = await failed();
    assert.deepEqual([other.code, other.message], ["invalid_params", "授权失败：Error: Unknown permission"]);
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
  const link = { ask: () => Effect.promise(() => { started(); return waiting; }) };
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

test("a request waiting asks this device to be approved first only where it is off its person's own lock, not where there is none yet", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const mesh = { deviceId: () => "phone", link: () => Effect.never } as unknown as Mesh;
  let standing: "none" | "member" | "outside" | "replaced" = "none";
  const stub = personalStub();
  const personal = { ...stub.personal, standing: () => standing } as unknown as typeof stub.personal;
  const adb = new Adb({ ...stub, personal, host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => false });
  try {
    adb.heard("ws/st", { id: "p1", chat: "chat-a", session: "s1", reason: "debug", status: "pending", at: 1 });
    const joins = () => adb.grants().map((g) => g.join ?? false);
    // No lock yet: allowing it begins the lock (PersonalLock.signGrant), no step before it.
    assert.deepEqual(joins(), [false]);
    standing = "outside";
    assert.deepEqual(joins(), [true]);
    standing = "replaced";
    assert.deepEqual(joins(), [true]);
    standing = "member";
    assert.deepEqual(joins(), [false]);
  } finally {
    runner.shutdown();
  }
});
