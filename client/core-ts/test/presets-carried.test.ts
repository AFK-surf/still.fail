// A person's presets and starred models carried between a workspace's stations by their own devices
// (src/views/presets.ts, src/presets-kept.ts), on the stations' own code (station/src/api/routes/presets.ts, stars.ts,
// station/src/sessions/presets.ts): two stations that never talk and devices that each reach some of them come to the
// same records by the devices alone; a deletion is not brought back; what was changed with a station away reaches it
// as its link opens; a station from before is read and written the old way and shows nothing twice; someone else's
// preset is read at a press, picked, kept with its station away and copied; a chat opens with what the device holds;
// starred models' union, unstarring and the defaults of a device that never starred.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect } from "effect";
import type { Route } from "../../../station/src/api/admin.ts";
import { routes as presetRoutes } from "../../../station/src/api/routes/presets.ts";
import { routes as starRoutes } from "../../../station/src/api/routes/stars.ts";
import type { Viewer } from "../../../station/src/mesh/credential.ts";
import { Presets, readPresetsFile } from "../../../station/src/sessions/presets.ts";
import { Choose } from "../src/choose.ts";
import type { Inner } from "../src/core.ts";
import { handlers } from "../src/core/execute.ts";
import { CoreError } from "../src/error.ts";
import { GONE_KEPT, type KeptRecord, type PresetRecord, canonical, isGone } from "../src/preset-records.ts";
import { TABLE, heldOf, starredKeys, starsHeld } from "../src/presets-kept.ts";
import { OTHERS_WAIT_MS, PresetViews, carryAll, install, likedKey, whoIn } from "../src/views/presets.ts";
import { overview } from "./station-fixture.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";

const WS = "ws";
const ME = { sub: "s1", email: "a@x.com", name: "阿一" };
const YOU = { sub: "s2", email: "b@x.com", name: "Bo" };
const clock = { now: 1_000 };

type Ask = (method: string, path: string, body: unknown) => Effect.Effect<unknown, CoreError>;
type Rig = { id: string; address: string; presets: Presets; answer: (viewer: Viewer) => Ask; told: string[]; home: string };

/// What the station's routes answer `r`, as the mesh would: its JSON, or its refusal as the core's requests make one.
function served(routes: Route[], viewer: Viewer): Ask {
  return (method, path, body) =>
    Effect.flatMap(
      Effect.promise(async () => {
        for (const route of routes) {
          const m = route.method === method ? route.pattern.exec(path) : null;
          if (m === null) continue;
          const req = { method, path, query: [], headers: {}, body: Buffer.from(body === null || body === undefined ? "" : JSON.stringify(body)), viewer, lang: "en" };
          return await route.handle(req as never, m.slice(1) as never);
        }
        return { status: 404, headers: {}, body: Buffer.from(JSON.stringify({ error: `no route ${method} ${path}` })) };
      }),
      (a) => {
        const text = Buffer.from(a.body as Uint8Array).toString("utf8");
        return a.status >= 400 ? Effect.fail(new CoreError(`http_${a.status}`, (JSON.parse(text) as { error: string }).error, a.status)) : Effect.succeed(JSON.parse(text) as unknown);
      },
    );
}

/// A station of today, on its own code: its presets in a folder of its own, its stars in memory.
function station(id: string): Rig {
  const home = mkdtempSync(join(tmpdir(), "prc-home-"));
  const repos = mkdtempSync(join(tmpdir(), "prc-repos-"));
  const presets = new Presets(() => home, () => clock.now, { station: () => id, workspace: () => WS, stationName: (s) => s });
  const stars = new Map<string, string>();
  const told: string[] = [];
  const routes = [
    ...presetRoutes({ presets, reposDir: () => repos, changed: () => told.push("presets") }),
    ...starRoutes({ kept: { modelStars: (w, s) => stars.get(`${w}/${s}`) ?? null, putModelStars: (w, s, t) => void stars.set(`${w}/${s}`, t) }, told: () => told.push("stars") }),
  ];
  return { id, address: `${WS}/${id}`, presets, told, home, answer: (viewer) => served(routes, viewer) };
}

/// A station from before: GET /presets lists every preset of the workspace (none of `owner`, `rev`, `home`), POST,
/// PUT and DELETE /presets change one; nothing else (`no route`).
function before(id: string): Rig {
  const home = mkdtempSync(join(tmpdir(), "prc-old-"));
  const presets = new Presets(() => home, () => clock.now, { station: () => id, workspace: () => WS });
  const asked: string[] = [];
  const old = (p: Record<string, unknown>) => {
    const { owner: _o, rev: _r, home: _h, ...rest } = p;
    return rest;
  };
  const routes: Route[] = [
    { method: "GET", pattern: /^\/presets$/, handle: async () => ({ status: 200, headers: {}, body: Buffer.from(JSON.stringify({ presets: presets.list(null).map((p) => old(p as never)), candidates: [], clones: [] })) }) },
    ...presetRoutes({ presets, reposDir: () => home }).filter((r) => r.method !== "GET" && !String(r.pattern).includes("kept") && !String(r.pattern).includes("clone")),
  ];
  return {
    id,
    address: `${WS}/${id}`,
    presets,
    home,
    told: asked,
    answer: (viewer) => {
      const ask = served(routes, viewer);
      return (method, path, body) => {
        asked.push(`${method} ${path}`);
        return ask(method, path, body);
      };
    },
  };
}

/// One device of `who`'s, reaching `stations` (those `up`): its kept records, a scheduler and forks run by `settle`.
function device(who: { sub: string; email: string; name: string }, stations: Rig[], live = false) {
  // (the core's fibers on a test's clock: a deadline waits for it, never for the wall's)
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const records = new Map<string, unknown>();
  const up = new Set(stations.map((s) => s.address));
  const queue: Effect.Effect<unknown, unknown>[] = [];
  const lists = new Map<string, unknown>();
  const byAddress = new Map(stations.map((s) => [s.address, s]));
  const viewer = { sub: who.sub, email: who.email, name: who.name, role: "member", workspace: WS, device: "d" } as Viewer;
  // (each request asked, and those to refuse as a station gone away would: `${method} ${address}`)
  const asked: string[] = [];
  const refuse = new Set<string>();
  const call = (address: string, method: string, path: string, body: unknown) => {
    asked.push(`${method} ${address} ${path}`);
    if (refuse.has(`${method} ${address}`)) return Effect.fail(new CoreError("offline", "not reached"));
    return byAddress.get(address)!.answer(viewer)(method, path, body);
  };
  const inner = {
    provider: { kind: "stillfail" },
    data: {
      record: (table: string, key: string) => records.get(`${table}:${key}`),
      put: (table: string, key: string, value: unknown) => void records.set(`${table}:${key}`, value),
      shared: (topic: { workspace?: string }) =>
        topic.workspace === WS ? { name: "W", stations: stations.map((s) => ({ id: s.id, name: s.id.toUpperCase() })), members: [ME, YOU].map((m) => ({ ...m, role: "member" })) } : undefined,
    },
    stations: {
      also: [] as { read: (a: string) => Effect.Effect<void, CoreError>; event: (a: string, n: string, d: unknown) => void }[],
      link: (address: string) => (byAddress.has(address) ? { addr: { toString: () => address } } : undefined),
      reachable: (address: string) => up.has(address),
      requests: { call: (addr: { toString(): string }, method: string, path: string, body: unknown) => call(addr.toString(), method, path, body) },
      presetsShown: (address: string) =>
        void queue.push(Effect.tap(call(address, "GET", "/presets", null), (v) => Effect.sync(() => lists.set(address, v)))),
      perform: (op: { target: { station: string }; method: string; path: string; body: unknown }) => call(op.target.station, op.method, op.path, op.body),
    },
    store: {
      get: (t: { topic: string; station?: string }) => (t.topic === "presets" ? lists.get(t.station!) : undefined),
      value: (t: { topic: string; scope?: string }) =>
        t.topic === "stations" ? { ok: stations.map((s) => ({ id: s.id, name: s.id.toUpperCase(), station: s.address, online: up.has(s.address) })) } : t.topic === "overview" ? { ok: lists.get(`overview`) } : undefined,
      inUse: () => false,
    },
    // (`live`: what is enqueued runs as the core runs it, each a fiber of its own, the test moving the clock on)
    scheduler: { enqueue: (_l: string, _k: string, _p: number, e: Effect.Effect<unknown, unknown>) => void (live ? runner.fork(Effect.ignore(e)) : queue.push(e)) },
    runner: { fork: (e: Effect.Effect<unknown, unknown>) => runner.fork(e) },
    workspaces: { owner: () => who.sub },
    accounts: { list: () => [who] },
    host: { nowMs: () => clock.now },
    router: { owners: [] as unknown[] },
  } as unknown as Inner;
  const views: PresetViews = install(inner);
  /// What is queued run in turn, and what was forked let run (the clock moved on a few milliseconds), until none is left.
  const settle = async () => {
    do {
      while (queue.length > 0) await Effect.runPromise(Effect.ignore(queue.shift()!));
      await host.time.pass(20);
    } while (queue.length > 0);
  };
  const also = () => (inner.stations as unknown as { also: { read: (a: string) => Effect.Effect<void, CoreError>; event: (a: string, n: string, d: unknown) => void }[] }).also;
  return {
    inner,
    host,
    views,
    records,
    asked,
    refuse,
    up,
    lists,
    settle,
    /// Its link to `s` opened: what the sync reads of a station then.
    open: async (s: Rig) => {
      up.add(s.address);
      for (const part of also()) await Effect.runPromise(Effect.ignore(part.read(s.address)));
      await settle();
    },
    away: (s: Rig) => void up.delete(s.address),
    tell: async (s: Rig, name: string, data: unknown = {}) => {
      for (const part of also()) part.event(s.address, name, data);
      await settle();
    },
    call: async (name: "add" | "put" | "delete" | "copy", station: string, params: Record<string, unknown>) => {
      const done = await Effect.runPromise(Effect.result(handlers.presets!(inner, { kind: "presets", name, station, params: { station, ...params } }, (() => {}) as never, ["c", 1] as never, null as never)));
      await settle();
      return done;
    },
    held: () => heldOf(inner.data, WS),
    live: () => Object.values(heldOf(inner.data, WS).records).filter((r): r is PresetRecord => !isGone(r)),
  };
}

const ok = <A>(r: { _tag: string; success?: A; failure?: unknown }): A => {
  assert.equal(r._tag, "Success", JSON.stringify(r.failure));
  return r.success as A;
};
const canon = (rs: KeptRecord[]) => rs.map(canonical).sort().join("\n");
const stationRecords = (s: Rig, who = ME) => s.presets.kept(null, who);

test("two stations that never talk come to the same records by one device; a deletion stays deleted; what changed with one away reaches it as its link opens", async () => {
  const a = station("a");
  const b = station("b");
  const d = device(ME, [a, b]);
  await d.open(a);
  await d.open(b);
  const made = ok(await d.call("add", a.address, { name: "App", dirs: ["/src/app", { path: "/src/lib", station: b.address }], instructions: "test first" })) as { id: string; home: string; rev: number };
  assert.equal(made.home, "a", "made on the page's station");
  assert.equal(made.rev, 1);
  assert.deepEqual(d.live().map((r) => r.id), [made.id], "kept on the device at once");
  assert.equal(canon(stationRecords(a)), canon(d.live()), "carried to a");
  assert.equal(canon(stationRecords(b)), canon(d.live()), "and to b, which never heard of a");

  // Changed with b away: kept here and on a; b brought it as its link opens again.
  d.away(b);
  ok(await d.call("put", a.address, { id: made.id, name: "App 2", dirs: ["/src/app"] }));
  assert.equal(stationRecords(a)[0]!.rev, 2);
  assert.equal(stationRecords(b)[0]!.rev, 1, "b away: not reached");
  await d.open(b);
  assert.equal(canon(stationRecords(b)), canon(stationRecords(a)), "b brought it as its link opened");

  // Deleted: a deletion is a record, and a station that held it live does not bring it back.
  d.away(b);
  ok(await d.call("delete", a.address, { id: made.id }));
  assert.equal(d.live().length, 0);
  const stale = stationRecords(b)[0]!;
  assert.ok(!isGone(stale), "b still holds it live");
  await d.open(b);
  assert.ok(isGone(stationRecords(b)[0]!), "b took the deletion");
  assert.equal(d.live().length, 0, "not brought back");

  // No loop: told again with nothing changed, nothing is brought.
  const putsBefore = a.told.length;
  await d.tell(a, "presets");
  assert.equal(a.told.length, putsBefore, "nothing brought a station that holds it all");
});

test("two devices of one person meet through a station; one of theirs from before is said again as theirs", async () => {
  const a = station("a");
  const phone = device(ME, [a]);
  const laptop = device(ME, [a]);
  await phone.open(a);
  const made = ok(await phone.call("add", a.address, { name: "Infra", dirs: [] })) as { id: string };
  await laptop.open(a);
  assert.deepEqual(laptop.live().map((r) => r.id), [made.id], "the laptop took it of the station");
  ok(await laptop.call("put", a.address, { id: made.id, name: "Infra v2", dirs: [] }));
  await phone.tell(a, "presets");
  assert.equal(phone.live()[0]!.name, "Infra v2");

  // A preset made by an app from before on a station of today (no owner): theirs by their email, said again with
  // their owner and one change more, so that every station comes to hold it as theirs.
  const old = a.presets.add(null, { name: "Old", dirs: [] }, ME.email);
  assert.equal(old.owner, "");
  await phone.tell(a, "presets");
  const taken = phone.held().records[old.id]!;
  assert.deepEqual([taken.owner, taken.rev], [ME.sub, 2]);
  assert.equal(stationRecords(a).find((r) => r.id === old.id)!.owner, ME.sub, "the station holds it as theirs now");
  // Someone else's is not taken.
  a.presets.add(null, { name: "Bo's", dirs: [] }, YOU.email, YOU.sub);
  await phone.tell(a, "presets");
  assert.equal(phone.live().some((r) => r.name === "Bo's"), false);
});

test("a station from before is read and written the old way, never PUT to, and shows nothing twice", async () => {
  const a = station("a");
  const o = before("o");
  const old = o.presets.add(null, { name: "Legacy", dirs: [] }, ME.email);
  o.presets.add(null, { name: "Theirs", dirs: [] }, YOU.email);
  const d = device(ME, [a, o]);
  await d.open(a);
  await d.open(o);
  // (its list read as the new chat's page shows it)
  const shown = async () => {
    d.inner.stations.presetsShown(o.address);
    await d.settle();
  };
  await shown();
  assert.deepEqual(d.held().before, ["o"], "said to be from before");
  assert.ok(!o.told.some((x) => x.startsWith("PUT /presets/kept")), "never PUT to");
  assert.deepEqual(d.live(), [], "nothing taken in before it is changed here");

  // The new chat's page lists it once, as theirs; someone else's on it only at a press.
  const choose = new Choose({ store: d.inner.store, data: d.inner.data, now: () => clock.now, agent: () => null, who: (s) => whoIn(d.inner, s) });
  const listed = () => (choose as unknown as { compute(t: unknown): { ok: { presets: { id: string; name: string; station: string }[] } } }).compute({ topic: "newChat", scope: WS }).ok.presets;
  assert.deepEqual(listed().map((p) => [p.name, p.station]), [["Legacy", o.address]]);

  // Changed here: taken into the device's records (theirs, one change more), carried to a, and written to o the old way.
  ok(await d.call("put", o.address, { id: old.id, name: "Legacy 2", dirs: [] }));
  assert.deepEqual([d.held().records[old.id]!.rev, d.held().records[old.id]!.owner], [2, ME.sub]);
  assert.equal(stationRecords(a).find((r) => r.id === old.id)?.rev, 2, "carried to the station of today");
  assert.ok(o.told.includes(`PUT /presets/${old.id}`), "written to the one from before as before");
  assert.equal(o.presets.get(null, old.id)?.name, "Legacy 2");
  await d.open(o);
  await shown();
  assert.deepEqual(listed().map((p) => p.name), ["Legacy 2"], "shown once: the device's");
  assert.ok(!o.told.some((x) => x.startsWith("PUT /presets/kept")));

  // Deleted here: gone on the device and on the old one; not listed again.
  ok(await d.call("delete", o.address, { id: old.id }));
  assert.ok(o.told.includes(`DELETE /presets/${old.id}`));
  await d.open(o);
  await shown();
  assert.deepEqual(listed(), []);
});

test("others' presets are read at a press; someone else's picked survives its station going away, is copied as one's own, and is not changed from here", async () => {
  const a = station("a");
  const b = station("b");
  const bo = device(YOU, [a]);
  await bo.open(a);
  const theirs = ok(await bo.call("add", a.address, { name: "Bo's review", dirs: ["/src/app"], instructions: "be kind" })) as { id: string };
  const d = device(ME, [a, b]);
  await d.open(a);
  await d.open(b);
  assert.deepEqual(d.live(), [], "not one's own: not kept");
  const others = () => (d.views.compute({ topic: "otherPresets", scope: WS }) as { ok: { reading: boolean; presets: { id: string; whose: string; station: string }[] } }).ok;
  assert.deepEqual(others().presets, [], "nothing read before the press");
  d.views.start({ topic: "otherPresets", scope: WS });
  await d.settle();
  assert.deepEqual(others(), { reading: false, presets: [{ id: theirs.id, name: "Bo's review", whose: "Bo", station: a.address, stationName: "A" }] });

  // Picked for the new chat's page: kept with its content, so that it and what opens a chat hold with a away.
  const choose = new Choose({ store: d.inner.store, data: d.inner.data, now: () => clock.now, agent: () => null, who: (s) => whoIn(d.inner, s), othersFound: (s, id) => d.views.othersFound(s, id) });
  choose.pickNew(WS, { preset: theirs.id, presetStation: a.address });
  d.away(a);
  const fresh = new PresetViews(d.inner);
  const one = fresh.compute({ topic: "preset", scope: WS, id: theirs.id }) as { ok: { name: string; mine: boolean; whose: string } };
  assert.deepEqual([one.ok.name, one.ok.mine, one.ok.whose], ["Bo's review", false, "Bo"], "a core started anew finds it kept with the pick");

  // Not changed from here; copied into one's own: a new id, theirs, one change.
  const refused = await d.call("put", b.address, { id: theirs.id, name: "mine now", dirs: [] });
  assert.equal(refused._tag, "Failure");
  assert.equal((refused as { failure: CoreError }).failure.status, 403, (refused as { failure: CoreError }).failure.message);
  const copy = ok(await d.call("copy", b.address, { id: theirs.id })) as { id: string; owner: string; rev: number; createdBy: string; home: string };
  assert.notEqual(copy.id, theirs.id);
  assert.deepEqual([copy.owner, copy.rev, copy.createdBy, copy.home], [ME.sub, 1, ME.email, "b"]);
  assert.equal(stationRecords(b).find((r) => r.id === copy.id)?.rev, 1, "carried");
});

test("a chat is opened with the preset as the device holds it, whether or not its station was brought it", async () => {
  const a = station("a");
  const b = station("b");
  const d = device(ME, [a, b]);
  await d.open(a);
  d.away(b);
  const made = ok(await d.call("add", a.address, { name: "Both", dirs: ["/src/app", { path: "/src/web", repo: "github.com/acme/web", station: b.address }], instructions: "hi" })) as { id: string };
  const profile = { id: "p1", name: "p1", runtime: "claude", runtimes: ["claude"], access: { kind: "subscription", key: "" }, home: "/h", homeExists: true, model: null, models: ["claude-opus-5-5"], env: [], usedBy: [], loginCommand: "", check: { state: "ok", detail: "", checkedAt: 1 }, quota: { state: "ok", windows: [], detail: null, checkedAt: 1 } };
  const store = { ...(d.inner.store as object), get: (t: { topic: string; station?: string }) => (t.topic === "overview" ? { ...overview, profiles: [profile] } : (d.inner.store as unknown as { get: (t: unknown) => unknown }).get(t)) };
  const choose = new Choose({ store: store as never, data: d.inner.data, now: () => clock.now, agent: () => null, who: (s) => whoIn(d.inner, s) });
  choose.pickNew(WS, { preset: made.id, presetStation: a.address });
  const ask = choose.create(b.address);
  assert.equal(stationRecords(b).length, 0, "b was never brought it");
  assert.equal(ask.preset, undefined, "never by its id: a station of today takes its copy");
  assert.deepEqual(ask.presetCopy, { id: made.id, name: "Both", dirs: [{ path: "/src/app", repo: null, elsewhere: "A" }, { path: "/src/web", repo: "github.com/acme/web" }], instructions: "hi" });
  // A picked one from before (`{id, station}` of before this core) keeps picking the same.
  d.records.set(`choice:ws:${WS}:preset`, { id: made.id, station: "ws/a" });
  assert.equal(choose.create(a.address).presetCopy.id, made.id);
});

test("starred models: two devices' stars from before meet as their union, an unstarring is carried, and a device that never starred shows the defaults until it stars", async () => {
  const a = station("a");
  const phone = device(ME, [a]);
  const laptop = device(ME, [a]);
  phone.records.set(`choice:${likedKey(WS)}`, ["claude-opus-5-5", "gpt-6"]);
  laptop.records.set(`choice:${likedKey(WS)}`, ["gpt-6", "gemini-4"]);
  await phone.open(a);
  await laptop.open(a);
  await phone.tell(a, "stars", { workspace: WS });
  const keys = (d: ReturnType<typeof device>) => starredKeys(starsHeld(d.records.get(`choice:${likedKey(WS)}`))!).sort();
  assert.deepEqual(keys(phone), ["claude-opus-5-5", "gemini-4", "gpt-6"], "the union, key by key");
  assert.deepEqual(keys(laptop), keys(phone));

  // Unstarred on the laptop: carried, and the phone unstars it as it is told.
  const profile = { id: "p1", runtime: "claude", named: [] };
  const store = { ...(laptop.inner.store as object), get: (t: { topic: string }) => (t.topic === "overview" ? { ...overview, profiles: [profile] } : undefined) };
  const carried: string[] = [];
  const choose = new Choose({ store: store as never, data: laptop.inner.data, now: () => clock.now, agent: () => null, starsChanged: (s) => carried.push(s) });
  clock.now += 1000;
  choose.like(a.address, "gpt-6", false);
  assert.deepEqual(carried, [WS], "carried as it is unstarred");
  carryAll(laptop.inner, WS, "stars");
  await laptop.settle();
  await phone.tell(a, "stars", { workspace: WS });
  assert.deepEqual(keys(phone), ["claude-opus-5-5", "gemini-4"]);
  await phone.tell(a, "stars", { workspace: "other" });

  // A device that never starred, the station holding none: nothing kept, the defaults shown; once it stars, kept.
  const b = station("b");
  const fresh = device(ME, [b]);
  await fresh.open(b);
  assert.equal(fresh.records.get(`choice:${likedKey(WS)}`), undefined, "nothing kept: the defaults shown");
  const named = { id: "p1", runtime: "claude", named: ["claude-opus-5-5"] };
  const freshStore = { ...(fresh.inner.store as object), get: (t: { topic: string }) => (t.topic === "overview" ? { ...overview, profiles: [named] } : undefined) };
  const c2 = new Choose({ store: freshStore as never, data: fresh.inner.data, now: () => clock.now, agent: () => null });
  c2.like(b.address, "gpt-6", true);
  assert.deepEqual(starredKeys(starsHeld(fresh.records.get(`choice:${likedKey(WS)}`))!), ["claude-opus-5-5", "gpt-6"], "the defaults kept, then the one starred");
  assert.equal(TABLE, "presetRecords");
});

/// Each station told `presets` (its `told` grew) tells its devices, as its stream would, until none tells any more: the
/// rounds it took, or null where it never came to rest in `most`.
async function toRest(devices: ReturnType<typeof device>[], stations: Rig[], most = 12): Promise<number | null> {
  // (from the first: what they told as the device first carried is told it too)
  const seen = new Map(stations.map((s) => [s, 0]));
  for (let round = 1; round <= most; round++) {
    const telling = stations.filter((s) => s.told.length !== seen.get(s));
    if (telling.length === 0) return round - 1;
    for (const s of telling) seen.set(s, s.told.length);
    for (const s of telling) for (const d of devices) await d.tell(s, "presets");
  }
  return null;
}

test("more deletions than a keeper keeps: device and stations keep the same of each owner's and come to rest", async () => {
  const a = station("a");
  const b = station("b");
  const d = device(ME, [a, b]);
  // (a person who deleted more presets than an owner's are kept: the latest GONE_KEPT of them, and some live)
  const MANY = 520;
  const records: Record<string, KeptRecord> = {};
  for (let i = 0; i < MANY; i++) records[`p-g${i}`] = { id: `p-g${i}`, owner: ME.sub, rev: 2, gone: true, updatedAt: 10_000 + i };
  records["p-live"] = { id: "p-live", name: "Live", dirs: [], instructions: "", createdBy: ME.email, createdAt: 1, updatedAt: 1, owner: ME.sub, rev: 1, home: "a" };
  d.records.set(`${TABLE}:${WS}`, { records, before: [] });
  await d.open(a);
  await d.open(b);
  const rounds = await toRest([d], [a, b]);
  assert.notEqual(rounds, null, "the stations kept telling and the device kept bringing: no rest");
  // At rest: told again, nothing is brought and nothing more is told.
  const before = d.asked.length;
  const told = [a.told.length, b.told.length];
  await d.tell(a, "presets");
  await d.tell(b, "presets");
  assert.deepEqual(d.asked.slice(before).filter((x) => x.startsWith("PUT")), [], "nothing brought at rest");
  assert.deepEqual([a.told.length, b.told.length], told, "nothing more told");
  // Both hold the same deletions, the latest GONE_KEPT of the owner's; the station's file is bounded by owner.
  const goneOf = (rs: KeptRecord[]) => rs.filter(isGone).map((r) => r.id).sort();
  const held = goneOf(Object.values(d.held().records));
  assert.equal(held.length, GONE_KEPT);
  assert.deepEqual(held, Array.from({ length: GONE_KEPT }, (_, i) => `p-g${MANY - GONE_KEPT + i}`).sort(), "the latest");
  assert.deepEqual(goneOf(stationRecords(a)), held);
  assert.deepEqual(goneOf(stationRecords(b)), held);
  // (another owner's, and those of nobody said, are bounded apart: one person's many push out nobody else's)
  a.presets.add(null, { name: "Bo's", dirs: [] }, YOU.email, YOU.sub);
  const bos = a.presets.list(null).find((p) => p.name === "Bo's")!;
  a.presets.delete(null, bos.id, { sub: YOU.sub, email: YOU.email });
  const file = readPresetsFile(a.home, "a");
  assert.equal(file.gone.filter((g) => g.owner === ME.sub).length, GONE_KEPT);
  assert.equal(file.gone.filter((g) => g.owner === YOU.sub).length, 1);
});

test("a preset of nobody said yet, deleted on one station by someone else's app from before, reaches its maker's device and every station", async () => {
  const s1 = station("s1");
  const s2 = station("s2");
  // A's from before on S1; A's new device reads it there and carries it to S2, its PUT to S1 not reaching it.
  const old = s1.presets.add(null, { name: "Old", dirs: [] }, ME.email);
  const d = device(ME, [s1, s2]);
  d.refuse.add(`PUT ${s1.address}`);
  await d.open(s1);
  await d.open(s2);
  d.refuse.clear();
  assert.equal(stationRecords(s2).find((r) => r.id === old.id)?.owner, ME.sub, "S2 holds it as A's");
  assert.equal(s1.presets.get(null, old.id)?.owner, "", "S1 still of nobody said");
  // B's app from before deletes it on S1: a deletion of nobody said.
  s1.presets.delete(null, old.id, { sub: YOU.sub, email: YOU.email });
  // A third person's device, holding nothing of it, changes nothing and brings nothing.
  const c = device({ sub: "s3", email: "c@x.com", name: "C" }, [s1, s2]);
  await c.open(s1);
  await c.open(s2);
  assert.deepEqual(Object.keys(c.held().records), []);
  assert.deepEqual(c.asked.filter((x) => x.startsWith("PUT")), []);
  // A's device, told by S1: holds it deleted as its own, and brings that to both.
  await d.tell(s1, "presets");
  assert.notEqual(await toRest([d, c], [s1, s2]), null);
  const gone = d.held().records[old.id]!;
  assert.ok(isGone(gone), "deleted on A's device");
  assert.equal(gone.owner, ME.sub);
  const at = (s: Rig) => s.presets.kept(null, { sub: ME.sub, email: ME.email }).find((r) => r.id === old.id);
  assert.deepEqual([at(s2)?.owner, at(s2) !== undefined && isGone(at(s2)!)], [ME.sub, true], "and on S2");
  assert.deepEqual([at(s1)?.owner, at(s1) !== undefined && isGone(at(s1)!)], [ME.sub, true], "S1's of nobody replaced by A's");
});

test("others' presets wait for a slow station only so long: the press is let go, what it says later still joins the list", async () => {
  const a = station("a");
  const slow = station("b");
  a.presets.add(null, { name: "Bo's on a", dirs: [] }, YOU.email, YOU.sub);
  slow.presets.add(null, { name: "Bo's on b", dirs: [] }, YOU.email, YOU.sub);
  // (b linked and reached, its answer held until the test lets it go)
  let letGo = () => {};
  const gate = new Promise<void>((resolve) => (letGo = resolve));
  const answer = slow.answer;
  slow.answer = (viewer) => (method, path, body) =>
    path === "/presets/others" ? Effect.flatMap(Effect.promise(() => gate), () => answer(viewer)(method, path, body)) : answer(viewer)(method, path, body);
  const d = device(ME, [a, slow], true);
  const others = () => (d.views.compute({ topic: "otherPresets", scope: WS }) as { ok: { reading: boolean; presets: { name: string }[] } }).ok;
  d.views.start({ topic: "otherPresets", scope: WS });
  await d.host.time.pass(10);
  assert.deepEqual([others().reading, others().presets.map((p) => p.name)], [true, ["Bo's on a"]], "a answered, b still waited for");
  await d.host.time.pass(OTHERS_WAIT_MS);
  assert.deepEqual([others().reading, others().presets.map((p) => p.name)], [false, ["Bo's on a"]], "b no longer holds the press");
  letGo();
  await d.host.time.pass(10);
  assert.deepEqual([others().reading, others().presets.map((p) => p.name).sort()], [false, ["Bo's on a", "Bo's on b"]], "b's joins the list as it comes");
});
