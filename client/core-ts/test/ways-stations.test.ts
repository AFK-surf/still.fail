// A workspace's ways read of its stations and changed on them (src/views/ways-stations.ts; the root AGENTS.md, The cloud
// is the account system): the newest a station tells kept; a change made on the first station that keeps them, a
// refusal said as it is, still.fail cloud asked only where none of its stations keeps them (all from before).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { Inner } from "../src/core.ts";
import { CoreError } from "../src/error.ts";
import { handlers } from "../src/core/execute.ts";
import { cloudOp, install, keptWays } from "../src/views/ways-stations.ts";

const A = "aa".repeat(32);
const B = "bb".repeat(32);

/// A device's core as far as the ways need it: its kept records, the workspace's stations and what each answers.
function fakeInner(answers: Record<string, (method: string, body: unknown) => Effect.Effect<unknown, CoreError>>) {
  const records = new Map<string, unknown>();
  const asked: string[] = [];
  const also: { read: (address: string) => Effect.Effect<void, CoreError>; event: (address: string, name: string, data: unknown) => void }[] = [];
  const enqueued: Effect.Effect<unknown, unknown>[] = [];
  const inner = {
    provider: { kind: "stillfail" },
    data: {
      record: (table: string, key: string) => records.get(`${table}:${key}`),
      put: (table: string, key: string, value: unknown) => void records.set(`${table}:${key}`, value),
      shared: (topic: { workspace: string }) => (topic.workspace === "ws" ? { stations: [{ id: A }, { id: B }] } : undefined),
    },
    stations: {
      also,
      link: (address: string) => (answers[address] ? {} : undefined),
      reachable: (address: string) => answers[address] !== undefined,
      requests: {
        call: (addr: { toString(): string }, method: string, path: string, body: unknown) => {
          asked.push(`${addr} ${method} ${path}`);
          return answers[addr.toString()]!(method, body);
        },
      },
    },
    scheduler: { enqueue: (_a: string, _k: string, _p: unknown, e: Effect.Effect<unknown, unknown>) => void enqueued.push(e) },
  } as unknown as Inner;
  install(inner);
  return { inner, records, asked, also, enqueued };
}

const run = <X>(e: Effect.Effect<X, CoreError>) => Effect.runPromise(Effect.result(e));
const kept = (at: number, station: string, url: string, by?: string) => ({ relays: [by ? { url, by } : { url }], off: [], at, station });

test("each station's ways read as its link opens and as it tells them changed: the newest kept", async () => {
  let a = kept(5, A, "https://one.test", "上海中继");
  const f = fakeInner({ [`ws/${A}`]: () => Effect.succeed(a), [`ws/${B}`]: () => Effect.succeed(kept(3, B, "https://old.test")) });
  for (const h of f.also) await run(h.read(`ws/${A}`));
  for (const h of f.also) await run(h.read(`ws/${B}`));
  assert.deepEqual(keptWays(f.inner, "ws"), a, "an older one does not replace it");
  a = kept(9, A, "https://two.test");
  for (const h of f.also) h.event(`ws/${A}`, "ways", { workspace: "ws" });
  for (const h of f.also) h.event(`ws/${A}`, "ways", { workspace: "other" });
  assert.equal(f.enqueued.length, 1, "told of its own workspace's alone");
  await Effect.runPromise(f.enqueued[0] as Effect.Effect<unknown, never>);
  assert.deepEqual(keptWays(f.inner, "ws")?.relays, [{ url: "https://two.test" }]);
});

test("a change goes to a station that keeps the ways; a refusal is said as it is; the cloud only where none keeps them", async () => {
  const posted: unknown[] = [];
  const keeps = (method: string, body: unknown) => (method === "POST" ? (posted.push(body), Effect.succeed(kept(10, A, "https://pvg.test:8445", "Ana"))) : Effect.succeed(kept(1, A, "https://x.test")));
  const old = () => Effect.fail(new CoreError("http_404", "no route", 404));
  const call = (inner: Inner, name: "setRelays" | "setWay", params: Record<string, unknown>) =>
    run(handlers.ways!(inner, { kind: "ways", name, workspace: "ws", params: { workspace: "ws", account: "s1", ...params } }, (() => {}) as never, ["c", 1] as never, null as never) as Effect.Effect<unknown, CoreError>);

  // B from before, A keeping them: A takes it, and what it answers is kept.
  const f = fakeInner({ [`ws/${A}`]: keeps, [`ws/${B}`]: old });
  const done = await call(f.inner, "setRelays", { relays: ["https://pvg.test:8445"] });
  assert.equal(done._tag, "Success");
  assert.deepEqual(posted, [{ relays: ["https://pvg.test:8445"] }]);
  assert.deepEqual(keptWays(f.inner, "ws")?.relays, [{ url: "https://pvg.test:8445", by: "Ana" }]);

  // Refused for what was asked: said, no other station and no cloud asked.
  const refusing = fakeInner({ [`ws/${A}`]: () => Effect.fail(new CoreError("http_409", "the last relay stays on", 409)), [`ws/${B}`]: keeps });
  const refused = await call(refusing.inner, "setWay", { way: "https://cf.test", on: false });
  assert.equal(refused._tag, "Failure");
  assert.match(String((refused as { failure: CoreError }).failure.message), /last relay/);
  assert.deepEqual(refusing.asked.filter((x) => x.includes("POST")), [`ws/${A} POST /ways`]);

  // None keeps them: still.fail cloud's way, as before.
  const cloudAsked: unknown[] = [];
  const was = cloudOp.run;
  cloudOp.run = ((_inner: Inner, c: { op: unknown }) => (cloudAsked.push(c.op), Effect.succeed({ ok: true }))) as typeof cloudOp.run;
  try {
    const before = fakeInner({ [`ws/${A}`]: old, [`ws/${B}`]: old });
    assert.equal((await call(before.inner, "setWay", { way: "lan", on: false }))._tag, "Success");
    assert.equal(cloudAsked.length, 1);
    assert.match(JSON.stringify(cloudAsked[0]), /\/v1\/workspaces\/ws\/ways/);
  } finally {
    cloudOp.run = was;
  }
});

test("where none keeps them the cloud is written by the cloud's own op, not a station's", async () => {
  // (2026-11-14: it went to `handlers.op`, a station's, which read the cloud's request as a station's address and threw)
  const stationOp = handlers.op;
  let stationAsked = 0;
  handlers.op = (() => (stationAsked++, Effect.die(new Error("a station's op asked for the cloud")))) as typeof handlers.op;
  const ran: string[] = [];
  const was = cloudOp.run;
  cloudOp.run = ((_inner: Inner, c: { kind: string; op: { method: string; path: string } }) => (ran.push(`${c.kind} ${c.op.method} ${c.op.path}`), Effect.succeed({ ok: true }))) as typeof cloudOp.run;
  try {
    const old = () => Effect.fail(new CoreError("http_404", "no route", 404));
    const before = fakeInner({ [`ws/${A}`]: old, [`ws/${B}`]: old });
    const done = await run(handlers.ways!(before.inner, { kind: "ways", name: "setWay", workspace: "ws", params: { workspace: "ws", account: "s1", way: "lan", on: false } }, (() => {}) as never, ["c", 1] as never, null as never) as Effect.Effect<unknown, CoreError>);
    assert.equal(done._tag, "Success");
    assert.deepEqual(ran, ["op PUT /v1/workspaces/ws/ways"]);
    assert.equal(stationAsked, 0);
  } finally {
    handlers.op = stationOp;
    cloudOp.run = was;
  }
});
