// A person's presets and the models they starred, the same on all their devices and every station of the workspace,
// carried by their own devices (the user, 2026-11-14: 「预设同步用户自己客户端同步」「预设和模型收藏会在整个 workspace
// 同步」). The device keeps its person's records (presets-kept.ts, in the workspace's database), each made, changed or
// deleted here at once (a change one `rev` more, a deletion a record of its own) and carried: as a station's link opens,
// as it tells `presets` (or `stars`, its person's alone), and as something changes here, the device reads the station's
// (GET /presets/kept, GET /stars), keeps the newer of each by the one rule (preset-records.ts) and brings it only what
// it lacks or holds older (PUT /presets/kept, PUT /stars), so nothing goes round. Never on a timer: what failed is
// brought at the next of those. Stations never bring them level with each other.
//
// A station from before (its GET /presets/kept answers `no route`) is read as before (GET /presets, its link's
// `presets`) and never PUT to (it would take PUT /presets/kept for PUT /presets/:id): what it lists that its person
// made (by their email) is theirs, shown, and taken into the device's records once they change it here; what the device
// holds of an id wins over what it lists. So that its agents and apps from before do not go stale, a change of one it
// lists is written to it the old way too (PUT, DELETE /presets/:id), and one made with it as the page's station is made
// on it as before (POST /presets) and taken in as theirs. All of that goes once the floor (OLDEST_STATION) rises past
// the stations that serve /presets/kept.
//
// People see their own presets by default; others' after a press (the user, 2026-11-14: 「用户默认只能看到自己的预设，
// 想要查看别人的预设需要额外操作」; a default, not a permission): the `otherPresets` topic, read of the stations
// reachable as it is shown (GET /presets/others; of one from before, its list without one's own), the newer of each id,
// kept in memory alone (but for one picked for the new chat's page: choose.ts keeps its content with the pick). Another
// person's preset is looked at (`preset`), opened a chat with and copied into one's own (`preset.copy`); never changed
// or deleted from here (each person's are carried by their own devices alone; the lead, 2026-11-14).
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import type { Call } from "../core/calls.ts";
import { type Handler, handlers } from "../core/execute.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import * as ops from "../ops.ts";
import { type KeptRecord, type PresetRecord, RecordRefusal, type Stars, canonical, isGone, mergeStars, newerRecord, recordOf, starsOf } from "../preset-records.ts";
import {
  type Held,
  TABLE,
  type Who,
  adopted,
  fromBefore,
  heldOf,
  lacking,
  presetId,
  recordsOf,
  starsHeld,
  starsLacking,
  taken,
  theirs,
  turns,
} from "../presets-kept.ts";
import type { Topic } from "../protocol.ts";
import { Marks } from "../reactive.ts";
import { StationAddr } from "../station/addr.ts";
import type { Value } from "../store.ts";
import { Priority } from "../sync/scheduler.ts";
import { arr as arrU, get, isObject } from "../util.ts";
import { ofAddress } from "../workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];

type Of = Extract<Call, { kind: "presets" }>;

const stationId = (address: string) => address.slice(address.lastIndexOf("/") + 1);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// Whether a station's refusal says it has no such route: a station from before it (station/requests.ts).
export const fromBeforeRoute = (e: CoreError) => e.status === 404 && e.message.startsWith("no route ");

/// The `choice` record the stars are kept in.
export const likedKey = (ws: string) => `ws:${ws}:liked`;

/// Who the device is in `ws`: the account that reaches it, its sub and email; null while none does.
export function whoIn(inner: Inner, ws: string): Who | null {
  const sub = inner.workspaces.owner(ws);
  if (sub === null || sub === "") return null;
  return { sub, email: inner.accounts.list().find((a) => a.sub === sub)?.email ?? "" };
}

/// The stations of `ws` as its view lists them: id, name, address.
function stationsOf(inner: Inner, ws: string): { id: string; name: string; address: string }[] {
  return arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "stations")).flatMap((s: J) =>
    typeof get(s, "id") === "string" ? [{ id: s.id as string, name: typeof s.name === "string" ? s.name : "", address: `${ws}/${s.id}` }] : [],
  );
}

/// Whose a record is as people read it: the member's name where the workspace's members say it, else their email.
export function whoseOf(inner: Inner, ws: string, r: PresetRecord): string {
  const members = arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "members"));
  const by = members.find((m: J) => (r.owner !== "" && get(m, "sub") === r.owner) || (r.createdBy !== "" && typeof get(m, "email") === "string" && m.email.toLowerCase() === r.createdBy.toLowerCase()));
  return str(get(by, "name")) ?? str(get(by, "email")) ?? r.createdBy;
}

const ask = (inner: Inner, address: string, method: string, path: string, body: unknown = null) =>
  inner.stations.requests.call(inner.stations.link(address)?.addr ?? StationAddr.parse(address), method, path, body, { quiet: true });

/// Whether station `address` is worth asking now.
const reached = (inner: Inner, address: string) => inner.provider.kind === "stillfail" && inner.stations.link(address) !== undefined && inner.stations.reachable(address);

function write(inner: Inner, ws: string, held: Held): void {
  inner.data.put(TABLE, ws, held);
}

/// Station `id` of `ws` said to be from before (or not): kept beside the records, where it changed.
function markBefore(inner: Inner, ws: string, id: string, before: boolean): void {
  const held = heldOf(inner.data, ws);
  if (held.before.includes(id) === before) return;
  write(inner, ws, { ...held, before: before ? [...held.before, id] : held.before.filter((x) => x !== id) });
}

/// `given` taken into what is kept of `ws` where newer (read anew: nothing waits between this read and its write).
function take(inner: Inner, ws: string, given: readonly KeptRecord[], who: Who): void {
  const held = heldOf(inner.data, ws);
  const records = taken(held.records, given, who);
  if (records !== held.records) write(inner, ws, { ...held, records });
}

/// The person's records carried to station `address`: its own read and the newer of each kept, then brought what it
/// lacks or holds older, in turns. A station from before is said so and read as before.
export function carry(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (!reached(inner, address)) return;
    const ws = ofAddress(address);
    const who = whoIn(inner, ws);
    if (who === null) return;
    const said = yield* Effect.result(ask(inner, address, "GET", "/presets/kept"));
    if (said._tag === "Failure") {
      if (fromBeforeRoute(said.failure)) {
        markBefore(inner, ws, stationId(address), true);
        // (its list read as before: what it lists of theirs is shown)
        inner.stations.presetsShown(address);
      }
      return;
    }
    markBefore(inner, ws, stationId(address), false);
    const there = recordsOf(get(said.success, "records"));
    take(inner, ws, there, who);
    const byId = new Map(there.map((r) => [r.id, r]));
    for (const part of turns(lacking(heldOf(inner.data, ws).records, byId, who))) {
      const put = yield* Effect.result(ask(inner, address, "PUT", "/presets/kept", { records: part }));
      // (one not taken now is brought at the next carry)
      if (put._tag === "Failure") return;
      take(inner, ws, recordsOf(get(put.success, "records")), who);
    }
  });
}

/// The person's starred models carried to station `address`, as their records are.
export function carryStars(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (!reached(inner, address)) return;
    const ws = ofAddress(address);
    if (whoIn(inner, ws) === null) return;
    const said = yield* Effect.result(ask(inner, address, "GET", "/stars"));
    if (said._tag === "Failure") return;
    const there = starsSaid(get(said.success, "stars"));
    keepStars(inner, ws, there);
    const held = starsHeld(inner.data.record("choice", likedKey(ws)));
    if (held === null) return;
    const bring = starsLacking(held, there);
    if (Object.keys(bring).length === 0) return;
    const put = yield* Effect.result(ask(inner, address, "PUT", "/stars", { stars: bring }));
    if (put._tag === "Success") keepStars(inner, ws, starsSaid(get(put.success, "stars")));
  });
}

const starsSaid = (raw: unknown): Stars => {
  try {
    return starsOf(raw ?? {});
  } catch {
    return {};
  }
};

/// `given` merged into the stars kept of `ws`: none kept and none given stays none (the defaults shown, choose.ts).
function keepStars(inner: Inner, ws: string, given: Stars): void {
  const held = starsHeld(inner.data.record("choice", likedKey(ws)));
  if (held === null && Object.keys(given).length === 0) return;
  const raw = inner.data.record("choice", likedKey(ws));
  const merged = mergeStars(held ?? {}, given);
  if (held !== null && !Array.isArray(raw) && canonical(merged) === canonical(held)) return;
  inner.data.put("choice", likedKey(ws), merged, false);
}

/// Everything of the person's carried to every station of `ws` reached now (a change made here).
export function carryAll(inner: Inner, ws: string, what: "presets" | "stars"): void {
  for (const s of stationsOf(inner, ws)) {
    if (!reached(inner, s.address)) continue;
    inner.scheduler.enqueue(s.address, `${what}/${s.address}`, Priority.background, Effect.ignore(what === "presets" ? carry(inner, s.address) : carryStars(inner, s.address)));
  }
}

// ── what is shown ──

/// What a station from before lists, as the link last read it (its `presets`).
const listedBefore = (inner: Inner, address: string): unknown[] => arr(get(inner.store.get({ topic: "presets", station: address }), "presets"));

/// A preset of the person's: the device's record of `id` where it holds one (a deleted one: none), else one a station
/// from before of `ws` lists that they made (`at`: that station's address, the one asked first where it lists it).
export function ownRecord(inner: Inner, ws: string, id: string, who: Who, held: Held = heldOf(inner.data, ws), at: string | null = null): { r: PresetRecord; before: string | null } | null {
  const kept = held.records[id];
  if (kept !== undefined) return isGone(kept) ? null : { r: kept, before: null };
  const order = at !== null && held.before.includes(stationId(at)) ? [stationId(at), ...held.before.filter((x) => x !== stationId(at))] : held.before;
  for (const sid of order) {
    const address = `${ws}/${sid}`;
    const p = listedBefore(inner, address).find((x) => get(x, "id") === id);
    const r = p === undefined ? null : fromBefore(p, address);
    if (r !== null && theirs(r, who)) return { r, before: address };
  }
  return null;
}

/// The stations of `ws` from before that list `id`.
function listing(inner: Inner, ws: string, held: Held, id: string): string[] {
  return held.before.map((sid) => `${ws}/${sid}`).filter((a) => listedBefore(inner, a).some((x) => get(x, "id") === id));
}

/// What others' presets were read of each station of a workspace, while the `otherPresets` topic is shown or since.
type OthersRead = { at: Map<string, PresetRecord[]>; reading: Set<string> };

export class PresetViews implements Owner {
  readonly #inner: Inner;
  readonly #marks = new Marks();
  readonly #others = new Map<string, OthersRead>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "otherPresets" || topic.topic === "preset";
  }

  start(topic: Topic): void {
    if (topic.topic === "otherPresets") this.readOthers(topic.scope as string);
  }

  compute(topic: Topic): Value | undefined {
    this.#marks.read(String(topic.scope));
    const ws = String(topic.scope);
    try {
      if (topic.topic === "otherPresets") return { ok: this.#othersView(ws) };
      return this.#one(ws, String(topic.id));
    } catch (e) {
      if (!(e instanceof CoreError)) throw e;
      return { err: e };
    }
  }

  /// Others' presets read again of every station of `ws` reached now, each as it answers.
  readOthers(ws: string): void {
    const inner = this.#inner;
    const read = this.#others.get(ws) ?? { at: new Map(), reading: new Set() };
    this.#others.set(ws, read);
    for (const s of stationsOf(inner, ws)) {
      if (!reached(inner, s.address)) continue;
      read.reading.add(s.address);
      inner.scheduler.enqueue(s.address, `otherPresets/${s.address}`, Priority.shown, Effect.ensuring(Effect.ignore(this.#readOthersOf(ws, s.address)), Effect.sync(() => {
        read.reading.delete(s.address);
        this.#marks.touch(ws);
      })));
    }
    this.#marks.touch(ws);
  }

  #readOthersOf(ws: string, address: string): Effect.Effect<void, CoreError> {
    const self = this;
    const inner = this.#inner;
    return Effect.gen(function* () {
      const who = whoIn(inner, ws);
      if (who === null) return;
      const said = yield* Effect.result(ask(inner, address, "GET", "/presets/others"));
      let found: PresetRecord[];
      if (said._tag === "Success") found = recordsOf(get(said.success, "records")).filter((r): r is PresetRecord => !isGone(r) && !theirs(r, who));
      else if (fromBeforeRoute(said.failure)) {
        const listed = yield* Effect.result(ask(inner, address, "GET", "/presets"));
        if (listed._tag === "Failure") return;
        found = arr(get(listed.success, "presets")).flatMap((p) => fromBefore(p, address) ?? []).filter((r) => !theirs(r, who));
      } else return;
      self.#others.get(ws)?.at.set(address, found);
      self.#refreshPicked(ws, found);
    });
  }

  /// A preset of someone else's picked for the new chat's page, kept with its content as read then: as read now.
  #refreshPicked(ws: string, found: PresetRecord[]): void {
    const key = `ws:${ws}:preset`;
    const kept = this.#inner.data.record("choice", key);
    const was = get(kept, "record");
    if (!isObject(kept) || !isObject(was)) return;
    const now = found.find((r) => r.id === (was as J).id);
    if (now === undefined || canonical(now) === canonical(was) || newerRecord(was as unknown as PresetRecord, now) !== now) return;
    this.#inner.data.put("choice", key, { ...kept, record: now }, false);
  }

  /// Someone else's preset `id` as last read of `ws`'s stations (the newer of each station's): undefined for none.
  othersFound(ws: string, id: string): PresetRecord | undefined {
    let out: PresetRecord | undefined;
    for (const list of this.#others.get(ws)?.at.values() ?? []) {
      for (const r of list) if (r.id === id) out = out === undefined ? r : newerRecord(out, r);
    }
    return out;
  }

  /// The `otherPresets` topic: the newer of each id read, none the device holds of its own, by when they were made.
  #othersView(ws: string): J {
    const inner = this.#inner;
    const read = this.#others.get(ws);
    const held = heldOf(inner.data, ws);
    const all = new Map<string, PresetRecord>();
    for (const list of read?.at.values() ?? []) {
      for (const r of list) {
        if (held.records[r.id] !== undefined) continue;
        const was = all.get(r.id);
        all.set(r.id, was === undefined ? r : newerRecord(was, r));
      }
    }
    const names = new Map(stationsOf(inner, ws).map((s) => [s.id, s.name]));
    const presets = [...all.values()]
      .sort((a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : 1))
      .map((r) => ({ id: r.id, name: r.name, whose: whoseOf(inner, ws, r), station: `${ws}/${r.home}`, stationName: names.get(r.home) ?? "" }));
    return { reading: (read?.reading.size ?? 0) > 0, presets };
  }

  /// The `preset` topic: one preset whole, the person's own (from the device) or someone else's (as last read, or as
  /// picked), as a page shows and edits it.
  #one(ws: string, id: string): Value | undefined {
    const inner = this.#inner;
    const who = whoIn(inner, ws);
    if (who === null) return undefined;
    const own = ownRecord(inner, ws, id, who);
    const picked = get(inner.data.record("choice", `ws:${ws}:preset`), "record");
    const r = own?.r ?? this.othersFound(ws, id) ?? (isObject(picked) && picked.id === id ? (picked as unknown as PresetRecord) : undefined);
    if (r === undefined) {
      if ((this.#others.get(ws)?.reading.size ?? 0) > 0) return undefined;
      return { err: new CoreError("http_404", t("core-misc.presets.none")) };
    }
    const names = new Map(stationsOf(inner, ws).map((s) => [s.address, s.name]));
    const nameOf = (address: string) => names.get(address) ?? stationId(address);
    return {
      ok: {
        id: r.id,
        name: r.name,
        dirs: r.dirs.map((d) => ({ path: d.path, repo: d.repo ?? "", station: d.station, stationName: nameOf(d.station) })),
        instructions: r.instructions,
        autoStation: r.autoStation === true,
        station: r.station ?? "",
        stations: r.stations ?? [],
        ...(r.model ? { model: r.model } : {}),
        mine: own !== null,
        whose: whoseOf(inner, ws, r),
        home: `${ws}/${r.home}`,
        homeName: nameOf(`${ws}/${r.home}`),
      },
    };
  }

  /// What the device holds changed: the topics made again.
  changed(ws: string): void {
    this.#marks.touch(ws);
  }
}

// ── the calls ──

/// A preset's folders as the app gives them (`dirs`): one of station `address`'s by its path (its repository as that
/// station offers it, or as the preset named it), another station's with its `station` (its address).
function dirsGiven(inner: Inner, address: string, given: unknown, was: PresetRecord | null): unknown[] {
  if (!Array.isArray(given)) throw CoreError.invalid(t("core-misc.params.missing", { field: "dirs" }));
  const offered = arr(get(inner.store.get({ topic: "presets", station: address }), "candidates"));
  return given.map((d) => {
    const path = typeof d === "string" ? d : str(get(d, "path"));
    const at = typeof d === "string" ? address : (str(get(d, "station")) ?? address);
    const repoSaid = typeof d === "string" ? undefined : get(d, "repo");
    const repo =
      typeof repoSaid === "string" && repoSaid !== ""
        ? repoSaid
        : (was?.dirs.find((x) => x.path === path && x.station === at)?.repo ?? str(get(offered.find((o) => get(o, "path") === path), "repo")) ?? null);
    return { path, repo, station: at };
  });
}

/// A record made of what a call gives (`p`) over `base` (what of it stays), checked as both sides check one.
function made(base: Record<string, unknown>, p: Record<string, unknown>, dirs: unknown[]): PresetRecord {
  const raw: Record<string, unknown> = { ...base, name: p.name, dirs, instructions: typeof p.instructions === "string" ? p.instructions : "" };
  delete raw.autoStation;
  delete raw.station;
  delete raw.stations;
  if (p.autoStation === true) raw.autoStation = true;
  if (Array.isArray(p.stations)) raw.stations = p.stations;
  if ("model" in p) raw.model = p.model;
  else delete raw.model;
  try {
    const r = recordOf(raw);
    if (isGone(r)) throw new RecordRefusal("a preset");
    return r;
  } catch (e) {
    throw CoreError.invalid(e instanceof Error ? e.message : String(e));
  }
}

/// A change of a preset a station from before lists, written there the old way too, as an app from before would (its
/// own folders by their paths, another station's with its `station`): best effort, for its agents and apps from
/// before. Goes once the floor rises past the stations that serve /presets/kept.
function writeBefore(inner: Inner, ws: string, held: Held, r: KeptRecord): void {
  const names = new Map(stationsOf(inner, ws).map((s) => [s.address, s.name]));
  for (const address of listing(inner, ws, held, r.id)) {
    const op = isGone(r)
      ? ops.request("preset.delete", { station: address, id: r.id })
      : ops.request("preset.put", {
          station: address,
          id: r.id,
          name: r.name,
          dirs: r.dirs.map((d) => (d.station === address ? { path: d.path, repo: d.repo } : { path: d.path, repo: d.repo, station: d.station, stationName: names.get(d.station) ?? "" })),
          instructions: r.instructions,
          ...(r.autoStation ? { autoStation: true } : {}),
          ...(r.station ? { stations: [r.station] } : r.stations ? { stations: r.stations } : {}),
          ...(r.model ? { model: r.model } : {}),
        });
    if (op !== null) inner.runner.fork(Effect.ignore(inner.stations.perform(op, null)), { log: "Unhandled", message: "a preset's change written to a station from before" });
  }
}

/// The record answered to the app: what it was made as (its `id` among it).
const answered = (r: PresetRecord) => ({ ...r });

function run(inner: Inner, views: PresetViews, c: Of, progress: Parameters<Handler>[2], at: Parameters<Handler>[3], ctx: Parameters<Handler>[4]): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const address = c.station;
    const ws = ofAddress(address);
    const who = whoIn(inner, ws);
    if (who === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.presets.signedOut")));
    const now = inner.host.nowMs();
    const p = c.params;
    const held = heldOf(inner.data, ws);
    const keep = (r: KeptRecord) => {
      const now_ = heldOf(inner.data, ws);
      write(inner, ws, { ...now_, records: { ...now_.records, [r.id]: r } });
      views.changed(ws);
      carryAll(inner, ws, "presets");
    };
    switch (c.name) {
      case "add": {
        // (on a station from before as the page's: made there as before, and taken in as theirs)
        if (held.before.includes(stationId(address))) {
          const op = ops.request("preset.add", p);
          if (op === null) return yield* Effect.fail(CoreError.invalid("preset.add"));
          const said = yield* handlers.op!(inner, { kind: "op", op }, progress, at, ctx);
          const r = fromBefore(said, address);
          if (r !== null) keep({ ...r, owner: who.sub });
          return said;
        }
        const r = made({ id: presetId(), createdBy: who.email, createdAt: now, updatedAt: now, owner: who.sub, rev: 1, home: stationId(address) }, p, dirsGiven(inner, address, p.dirs, null));
        keep(r);
        return answered(r);
      }
      case "put": {
        const id = typeof p.id === "string" ? p.id : "";
        const own = ownRecord(inner, ws, id, who, held, address);
        if (own === null) return yield* Effect.fail(views.othersFound(ws, id) !== undefined ? new CoreError("http_403", t("core-misc.presets.notYours")) : new CoreError("http_404", t("core-misc.presets.none")));
        const base = adopted(own.r, who) as PresetRecord;
        const r = made({ ...base, updatedAt: now, owner: who.sub, rev: own.r.rev + 1 }, p, dirsGiven(inner, address, p.dirs, own.r));
        keep(r);
        writeBefore(inner, ws, held, r);
        return answered(r);
      }
      case "delete": {
        const id = typeof p.id === "string" ? p.id : "";
        const own = ownRecord(inner, ws, id, who, held, address);
        if (own === null) return yield* Effect.fail(views.othersFound(ws, id) !== undefined ? new CoreError("http_403", t("core-misc.presets.notYours")) : new CoreError("http_404", t("core-misc.presets.none")));
        const gone: KeptRecord = { id, owner: who.sub, rev: own.r.rev + 1, gone: true, updatedAt: now };
        keep(gone);
        writeBefore(inner, ws, held, gone);
        return { ok: true };
      }
      case "copy": {
        const id = typeof p.id === "string" ? p.id : "";
        const picked = get(inner.data.record("choice", `ws:${ws}:preset`), "record");
        const from = ownRecord(inner, ws, id, who, held)?.r ?? views.othersFound(ws, id) ?? (isObject(picked) && picked.id === id ? (picked as unknown as PresetRecord) : undefined);
        if (from === undefined) return yield* Effect.fail(new CoreError("http_404", t("core-misc.presets.none")));
        const name = typeof p.name === "string" && p.name.trim() !== "" ? p.name : from.name;
        const r = made(
          { ...from, id: presetId(), createdBy: who.email, createdAt: now, updatedAt: now, owner: who.sub, rev: 1, home: stationId(address) },
          { ...from, name, ...(from.station ? { stations: [from.station] } : {}) },
          from.dirs,
        );
        keep(r);
        return answered(r);
      }
    }
  });
}

export function install(inner: Inner): PresetViews {
  const views = new PresetViews(inner);
  inner.router.owners.push(views);
  handlers.presets = (core, call, progress, at, ctx) => run(core, views, call as Of, progress, at, ctx);
  inner.stations.also.push({
    read: (address) => Effect.andThen(Effect.ignore(carry(inner, address)), Effect.ignore(carryStars(inner, address))),
    event: (address, name, data) => {
      const ws = ofAddress(address);
      if (name === "presets") {
        inner.scheduler.enqueue(address, `presets/${address}`, Priority.background, Effect.ignore(carry(inner, address)));
        if (inner.store.inUse({ topic: "otherPresets", scope: ws })) views.readOthers(ws);
      }
      if (name === "stars" && get(data, "workspace") === ws) inner.scheduler.enqueue(address, `stars/${address}`, Priority.background, Effect.ignore(carryStars(inner, address)));
    },
    // (read again after an absence: what it was told meanwhile is not said again)
    resume: true,
  });
  return views;
}
