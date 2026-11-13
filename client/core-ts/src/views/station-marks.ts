// What each station of a workspace is called and the mark it shows, as the stations keep them (station/src/mesh/
// station-marks.ts; the user, 2026-11-14: a station's name and icon are the station's, one for every workspace it is
// in, changed only while it is up). Read from each of a workspace's stations as its link opens and as it tells them
// changed (`stationMarks` on its event stream), each station's newest kept on the device (`stationMarks`, by the
// workspace's id) and laid over what still.fail cloud lists of it (`overlaid`), so every reader of the workspace's
// stations reads them; one no station keeps a record of is as the cloud lists it.
//
// Changed from the app (`workspace.renameStation`) on that station alone: one not reached is refused, said so (the
// app offers no change of an offline station). The cloud is written too while apps from before read only its list
// (a picture is put up there first: its address is what the station keeps, cloud/src/icons.ts); a station from before
// keeps none (404): the cloud alone, as before.
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import type { Call } from "../core/calls.ts";
import { type Handler, execute, handlers } from "../core/execute.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import * as ops from "../ops.ts";
import { Priority } from "../sync/scheduler.ts";
import { StationAddr } from "../station/addr.ts";
import type { SpanContext } from "../trace.ts";
import { ofAddress } from "../workspace.ts";
import { arr, get, isObject } from "../util.ts";
import { type StationMark, keptMarks, markOf, overlaid } from "../station-marks-kept.ts";

type Of = Extract<Call, { kind: "stationMark" }>;

/// How the cloud is written: as the app's own call went before, execute's cloud op, its answer the cloud's view of the
/// workspace (a test puts its own here).
export const cloudOp: { run: Handler } = { run: (inner, call, progress, at, ctx) => execute(inner, call, progress, at, ctx) };

/// `said` (by station id) kept where newer than what is, and laid over the workspace's view.
function keep(inner: Inner, ws: string, said: Record<string, StationMark>): void {
  const was = keptMarks(inner.data, ws);
  const next = { ...was };
  let changed = false;
  for (const [id, m] of Object.entries(said)) {
    if (was[id] !== undefined && m.at <= was[id]!.at) continue;
    next[id] = m;
    changed = true;
  }
  if (!changed) return;
  inner.data.put("stationMarks", ws, next);
  inner.data.update({ topic: "workspace", workspace: ws }, (w) => overlaid(w, next));
}

const ask = (inner: Inner, address: string, method: string, path: string, body: unknown = null) =>
  inner.stations.requests.call(StationAddr.parse(address), method, path, body, { quiet: true });

/// A station's records read and kept; one from before keeps none (404): nothing.
function readStation(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (inner.provider.kind !== "stillfail" || !inner.stations.link(address) || !inner.stations.reachable(address)) return;
    const said = yield* Effect.result(ask(inner, address, "GET", "/station-marks"));
    if (said._tag === "Failure") return;
    const marks: Record<string, StationMark> = {};
    const raw = get(said.success, "marks");
    if (isObject(raw)) for (const [id, r] of Object.entries(raw)) {
      const m = markOf(r);
      if (m !== null) marks[id] = m;
    }
    keep(inner, ofAddress(address), marks);
  });
}

/// What the workspace's view lists of station `id` now (its records laid over).
function listed(inner: Inner, ws: string, id: string): { name: string; emoji: string; icon: string } | null {
  const s = (arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "stations")) ?? []).find((x) => get(x, "id") === id);
  if (!isObject(s)) return null;
  return { name: typeof s.name === "string" ? s.name : id, emoji: typeof s.emoji === "string" ? s.emoji : "", icon: typeof s.icon === "string" ? s.icon : "" };
}

/// The station's name and mark changed on it; on still.fail cloud too while apps from before read only its list (first
/// where a picture is put up: its address is what the station keeps); on the cloud alone where the station is one from
/// before.
function run(inner: Inner, c: Of, progress: Parameters<Handler>[2], at: Parameters<Handler>[3], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const ws = c.workspace;
    const id = c.station;
    const address = `${ws}/${id}`;
    const cloud = (params: Record<string, unknown>) =>
      Effect.suspend(() => {
        const op = ops.request("workspace.renameStation", params);
        if (op === null) return Effect.fail(CoreError.invalid("no way to rename the station"));
        return cloudOp.run(inner, { kind: "op", op }, progress, at, ctx);
      });
    // (another control plane's stations keep none: Comma's, as before)
    if (inner.provider.kind !== "stillfail") return yield* cloud(c.params);
    const now = listed(inner, ws, id);
    if (now === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.stationMark.unknown")));
    if (!inner.stations.link(address) || !inner.stations.reachable(address)) return yield* Effect.fail(new CoreError("station_offline", t("core-misc.stationMark.offline", { name: now.name })));
    const given = (k: "name" | "emoji" | "icon") => (typeof c.params[k] === "string" ? (c.params[k] as string) : now[k]);
    let icon = given("icon");
    let cloudDone: unknown = undefined;
    // A picture: put up in the cloud's store first (as the cloud's list takes it); the station keeps its address.
    if (icon.startsWith("data:")) {
      cloudDone = yield* cloud(c.params);
      const put = (arr(get(cloudDone, "stations")) ?? []).find((x) => get(x, "id") === id);
      const address_ = get(put, "icon");
      if (typeof address_ !== "string" || address_.startsWith("data:")) return cloudDone;
      icon = address_;
    }
    const said = yield* Effect.result(ask(inner, address, "PUT", "/station-mark", { name: given("name"), emoji: given("emoji"), icon }));
    if (said._tag === "Failure") {
      // One from before keeps none: the cloud alone, as before.
      if (said.failure.status === 404) return cloudDone !== undefined ? cloudDone : yield* cloud(c.params);
      return yield* Effect.fail(said.failure);
    }
    const m = markOf(said.success);
    if (m !== null) keep(inner, ws, { [id]: m });
    // The cloud's list for apps from before, once the station took it; its failure changes nothing here.
    if (cloudDone === undefined) inner.runner.fork(Effect.ignore(cloud({ ...c.params, name: m?.name ?? given("name"), emoji: m?.emoji ?? given("emoji"), icon: m?.icon ?? icon }), { log: "Unhandled", message: "a station's name and mark written to the cloud for apps from before" }));
    return said.success;
  });
}

export function install(inner: Inner): void {
  handlers.stationMark = (core, call, progress, at, ctx) => run(core, call as Of, progress, at, ctx);
  inner.stations.also.push({
    read: (address) => readStation(inner, address),
    event: (address, name, data) => {
      const ws = ofAddress(address);
      if (name === "stationMarks" && get(data, "workspace") === ws) inner.scheduler.enqueue(address, `stationMarks/${address}`, Priority.background, Effect.ignore(readStation(inner, address)));
    },
    // (not read again after an absence: a stream that came back says each change it missed)
  });
}
