import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Adb } from "../src/adb.ts";
import type { Mesh } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";

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
  const adb = new Adb({ host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => false });
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
  const adb = new Adb({ host, runner, store, mesh: () => Effect.succeed(mesh), credentials: () => (() => Effect.succeed({} as never)), relays: () => [], lends: () => false });
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
