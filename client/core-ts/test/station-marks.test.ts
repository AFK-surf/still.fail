// The stations' names and marks read of the stations and changed on them (src/views/station-marks.ts): each station's
// newest kept and laid over still.fail cloud's list; a change made on that station alone (refused, said so, while it
// is not reached), written to the cloud too for apps from before; a picture put up in the cloud's store first; a
// station from before (404) changed on the cloud alone.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { Inner } from "../src/core.ts";
import { CoreError } from "../src/error.ts";
import { handlers } from "../src/core/execute.ts";
import { cloudOp, install } from "../src/views/station-marks.ts";
import { keptMarks, overlaid } from "../src/station-marks-kept.ts";

const A = "aa".repeat(32);
const B = "bb".repeat(32);
const PICTURE = "https://app.still.fail/v1/icons/0123456789abcdef0123456789abcdef.png";

/// A device's core as far as the marks need it: its kept records, the workspace as the cloud lists it, what each station
/// answers (none: not reached), and what was forked.
function fakeInner(answers: Record<string, ((method: string, path: string, body: unknown) => Effect.Effect<unknown, CoreError>) | undefined>) {
  const records = new Map<string, unknown>();
  const asked: string[] = [];
  const also: { read: (address: string) => Effect.Effect<void, CoreError>; event: (address: string, name: string, data: unknown) => void }[] = [];
  const enqueued: Effect.Effect<unknown, unknown>[] = [];
  const forked: Effect.Effect<unknown, unknown>[] = [];
  let workspace: unknown = { name: "Team", stations: [{ id: A, name: "studio", emoji: "🦊", online: true }, { id: B, name: "mini", icon: "glyph:server" }] };
  const inner = {
    provider: { kind: "stillfail" },
    data: {
      record: (table: string, key: string) => records.get(`${table}:${key}`),
      put: (table: string, key: string, value: unknown) => void records.set(`${table}:${key}`, value),
      shared: (topic: { workspace: string }) => (topic.workspace === "ws" ? workspace : undefined),
      update: (topic: { workspace: string }, change: (w: unknown) => unknown) => {
        if (topic.workspace === "ws") workspace = change(workspace) ?? workspace;
      },
    },
    stations: {
      also,
      link: (address: string) => (answers[address] ? {} : undefined),
      reachable: (address: string) => answers[address] !== undefined,
      requests: {
        call: (addr: { toString(): string }, method: string, path: string, body: unknown) => {
          asked.push(`${addr} ${method} ${path} ${JSON.stringify(body)}`);
          return answers[addr.toString()]!(method, path, body);
        },
      },
    },
    scheduler: { enqueue: (_a: string, _k: string, _p: unknown, e: Effect.Effect<unknown, unknown>) => void enqueued.push(e) },
    runner: { fork: (e: Effect.Effect<unknown, unknown>) => void forked.push(e) },
  } as unknown as Inner;
  install(inner);
  return { inner, records, asked, also, enqueued, forked, workspace: () => workspace as { stations: Record<string, unknown>[] } };
}

const run = <X>(e: Effect.Effect<X, CoreError>) => Effect.runPromise(Effect.result(e));
const mark = (at: number, name: string, emoji = "", icon = "") => ({ name, emoji, icon, at });

/// The cloud's way, recorded: what it was asked, answering as it would with `icon` its store's address.
function cloudSees(icon = PICTURE) {
  const asked: unknown[] = [];
  const was = cloudOp.run;
  cloudOp.run = ((_inner: Inner, c: { op: { body?: unknown } }) => Effect.suspend(() => {
    asked.push(c.op);
    return Effect.succeed({ stations: [{ id: A, name: "studio", icon }] });
  })) as typeof cloudOp.run;
  return { asked, done: () => void (cloudOp.run = was) };
}

const rename = (inner: Inner, params: Record<string, unknown>, station = A) =>
  run(handlers.stationMark!(inner, { kind: "stationMark", workspace: "ws", station, params: { workspace: "ws", station, account: "s1", ...params } }, (() => {}) as never, ["c", 1] as never, null as never) as Effect.Effect<unknown, CoreError>);

test("the stations' records read as a link opens and as one is told changed: the newest kept, laid over the cloud's list", async () => {
  let a = { marks: { [A]: mark(5, "Studio Mac", "", PICTURE), [B]: mark(3, "mini2") } };
  const f = fakeInner({ [`ws/${A}`]: () => Effect.succeed(a), [`ws/${B}`]: () => Effect.succeed({ marks: { [B]: mark(2, "older") } }) });
  for (const h of f.also) await run(h.read(`ws/${A}`));
  for (const h of f.also) await run(h.read(`ws/${B}`));
  assert.deepEqual(keptMarks(f.inner.data, "ws"), { [A]: mark(5, "Studio Mac", "", PICTURE), [B]: mark(3, "mini2") }, "an older one does not replace it");
  const [sa, sb] = f.workspace().stations;
  assert.deepEqual(sa, { id: A, name: "Studio Mac", icon: PICTURE, online: true }, "the emoji taken away, the rest of the row kept");
  assert.deepEqual(sb, { id: B, name: "mini2" });
  a = { marks: { [A]: mark(9, "Studio", "🐙") } };
  for (const h of f.also) h.event(`ws/${A}`, "stationMarks", { workspace: "ws" });
  for (const h of f.also) h.event(`ws/${A}`, "stationMarks", { workspace: "other" });
  assert.equal(f.enqueued.length, 1, "told of its own workspace's alone");
  await Effect.runPromise(f.enqueued[0] as Effect.Effect<unknown, never>);
  assert.deepEqual(f.workspace().stations[0], { id: A, name: "Studio", emoji: "🐙", online: true });
  // The cloud's list read again: laid over as it is written (sync/cloud.ts), the same object where nothing differs.
  const fresh = { stations: [{ id: A, name: "studio", emoji: "🦊" }] };
  assert.deepEqual(overlaid(fresh, keptMarks(f.inner.data, "ws")), { stations: [{ id: A, name: "Studio", emoji: "🐙" }] });
  const same = { stations: [{ id: A, name: "Studio", emoji: "🐙" }] };
  assert.equal(overlaid(same, keptMarks(f.inner.data, "ws")), same);
});

test("a change goes to its station with all three; the cloud written after for apps from before", async () => {
  const cloud = cloudSees();
  try {
    const f = fakeInner({ [`ws/${A}`]: (_m, _p, body) => Effect.succeed({ ...(body as object), at: 7 }) });
    const done = await rename(f.inner, { icon: "" });
    assert.equal(done._tag, "Success");
    assert.deepEqual(f.asked, [`ws/${A} PUT /station-mark {"name":"studio","emoji":"🦊","icon":""}`], "what was not given, as the list has it");
    assert.deepEqual(f.workspace().stations[0], { id: A, name: "studio", emoji: "🦊", online: true });
    assert.equal(cloud.asked.length, 0, "the cloud not waited for");
    assert.equal(f.forked.length, 1);
    await Effect.runPromise(Effect.ignore(f.forked[0]!));
    assert.equal(cloud.asked.length, 1);
    assert.match(JSON.stringify(cloud.asked[0]), /PATCH.*stations/);
  } finally {
    cloud.done();
  }
});

test("a station not reached is not changed: said so, nothing written anywhere", async () => {
  const cloud = cloudSees();
  try {
    const f = fakeInner({});
    const refused = await rename(f.inner, { icon: "" });
    assert.equal(refused._tag, "Failure");
    assert.equal((refused as { failure: CoreError }).failure.code, "station_offline");
    assert.deepEqual([f.asked, cloud.asked, f.forked.length], [[], [], 0]);
    assert.equal((await rename(f.inner, { name: "x" }, "cc".repeat(32)))._tag, "Failure", "one the workspace does not list");
  } finally {
    cloud.done();
  }
});

test("a picture is put up in the cloud's store first, its address what the station keeps", async () => {
  const cloud = cloudSees(PICTURE);
  try {
    const f = fakeInner({ [`ws/${A}`]: (_m, _p, body) => Effect.succeed({ ...(body as object), at: 8 }) });
    const done = await rename(f.inner, { emoji: "", icon: "data:image/jpeg;base64,AAAA" });
    assert.equal(done._tag, "Success");
    assert.equal(cloud.asked.length, 1, "the cloud first");
    assert.deepEqual(f.asked, [`ws/${A} PUT /station-mark {"name":"studio","emoji":"","icon":"${PICTURE}"}`]);
    assert.equal(f.forked.length, 0, "not written to the cloud again");
  } finally {
    cloud.done();
  }
});

test("a station from before keeps none: the cloud alone; a refusal of the station's said as it is", async () => {
  const cloud = cloudSees();
  try {
    const old = fakeInner({ [`ws/${A}`]: () => Effect.fail(new CoreError("http_404", "no route", 404)) });
    assert.equal((await rename(old.inner, { name: "x" }))._tag, "Success");
    assert.equal(cloud.asked.length, 1);
    assert.equal(old.records.size, 0);
    const refusing = fakeInner({ [`ws/${A}`]: () => Effect.fail(new CoreError("http_403", "only the workspace's owners and admins", 403)) });
    const refused = await rename(refusing.inner, { name: "x" });
    assert.equal(refused._tag, "Failure");
    assert.match((refused as { failure: CoreError }).failure.message, /owners and admins/);
    assert.equal(cloud.asked.length, 1, "the cloud not asked for one refused");
  } finally {
    cloud.done();
  }
});
