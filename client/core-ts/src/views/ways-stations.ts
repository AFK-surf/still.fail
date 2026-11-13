// A workspace's ways as its stations keep them (station/src/mesh/ways.ts; the root AGENTS.md, The cloud is the account
// system): its own relays (each with who added it) and the ways its devices do not take. Read from each of its stations
// as its link opens and as it tells them changed (`ways` on its event stream), the newest kept on the device (`ways`,
// by the workspace's id), which the mesh and the 连接方式 view go by before `/v1/me` (sync/cloud.ts workspaceRelays).
// Changed from the app (`workspace.setRelays`, `workspace.setWay`) on a station of the workspace, which tells the others;
// where none of its stations keeps them yet (all from before), on still.fail cloud as before.
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import type { Call } from "../core/calls.ts";
import { type Handler, execute, handlers } from "../core/execute.ts";
import { CoreError } from "../error.ts";
import * as ops from "../ops.ts";
import { Priority } from "../sync/scheduler.ts";
import { StationAddr } from "../station/addr.ts";
import type { SpanContext } from "../trace.ts";
import { ofAddress } from "../workspace.ts";
import { arr, get, isObject } from "../util.ts";

/// A relay of the workspace's own, and who added it where that is known.
export type OwnRelay = { url: string; by?: string };
/// What a station keeps of a workspace's ways (`at`, `station`: which of two is the newer; `at` 0, as the cloud kept them).
export type KeptWays = { relays: OwnRelay[]; off: string[]; at: number; station: string };

type Of = Extract<Call, { kind: "ways" }>;

/// How the cloud is written where no station keeps the ways: as the app's own call went before, execute's cloud op
/// (`handlers.op` is a station's, which took the cloud's path for a station's address and threw; a test puts its own
/// here).
export const cloudOp: { run: Handler } = { run: (inner, call, progress, at, ctx) => execute(inner, call, progress, at, ctx) };

/// What a station answered as kept ways; null when it is none.
export function keptOf(raw: unknown): KeptWays | null {
  if (!isObject(raw) || !Array.isArray(raw.relays) || typeof raw.at !== "number" || typeof raw.station !== "string") return null;
  const relays = raw.relays.flatMap((r): OwnRelay[] => (isObject(r) && typeof r.url === "string" ? [typeof r.by === "string" && r.by !== "" ? { url: r.url, by: r.by } : { url: r.url }] : []));
  const off = Array.isArray(raw.off) ? raw.off.filter((w): w is string => typeof w === "string") : [];
  return { relays, off, at: raw.at, station: raw.station };
}

const newer = (a: KeptWays, b: KeptWays) => a.at > b.at || (a.at === b.at && a.station > b.station);

/// The ways kept on the device for `ws`; null where none of its stations told them yet.
export function keptWays(inner: Inner, ws: string): KeptWays | null {
  return keptOf(inner.data.record("ways", ws));
}

/// `said`, kept where it is newer than what is (one of `at` 0 is as the cloud kept them: kept only where none is).
function keep(inner: Inner, ws: string, said: KeptWays): void {
  const was = keptWays(inner, ws);
  if (was !== null && !newer(said, was)) return;
  inner.data.put("ways", ws, said);
}

const ask = (inner: Inner, address: string, method: string, body: unknown = null) =>
  inner.stations.requests.call(StationAddr.parse(address), method, "/ways", body, { quiet: true });

/// A station's ways read and kept; one from before keeps none (404): nothing.
function readStation(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (inner.provider.kind !== "stillfail" || !inner.stations.link(address) || !inner.stations.reachable(address)) return;
    const said = yield* Effect.result(ask(inner, address, "GET"));
    if (said._tag === "Failure") return;
    const kept = keptOf(said.success);
    if (kept !== null) keep(inner, ofAddress(address), kept);
  });
}

/// The workspace's stations this device reaches now, by address.
function reached(inner: Inner, ws: string): string[] {
  const stations = arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "stations")) ?? [];
  return stations.flatMap((s) => {
    const id = get(s, "id");
    if (typeof id !== "string") return [];
    const address = `${ws}/${id}`;
    return inner.stations.link(address) && inner.stations.reachable(address) ? [address] : [];
  });
}

/// A change of the ways made on a station of the workspace that keeps them (the first that does); on still.fail cloud
/// where none does (all from before, or none reached: the cloud's is what such stations and devices go by).
function run(inner: Inner, c: Of, progress: Parameters<Handler>[2], at: Parameters<Handler>[3], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const body = c.name === "setRelays" ? { relays: Array.isArray(c.params.relays) ? c.params.relays : [] } : { way: c.params.way, on: c.params.on };
    // A station that did not answer (its link went down meanwhile): the next one asked; none answering, said so, as a
    // change made on the cloud alone would not reach the stations that keep the ways.
    let lost: CoreError | null = null;
    for (const address of reached(inner, c.workspace)) {
      const said = yield* Effect.result(ask(inner, address, "POST", body));
      if (said._tag === "Success") {
        const kept = keptOf(said.success);
        if (kept !== null) keep(inner, c.workspace, kept);
        return said.success;
      }
      const status = said.failure.status;
      // Refused for what was asked (not a relay's URL, the last relay off, a read-only member): said as it is.
      if (status !== undefined && status >= 400 && status < 500 && status !== 404) return yield* Effect.fail(said.failure);
      if (status !== 404) lost = said.failure;
    }
    if (lost !== null) return yield* Effect.fail(lost);
    const op = ops.request(`workspace.${c.name}`, c.params);
    if (op === null) return yield* Effect.fail(CoreError.invalid("no way to change the workspace's ways"));
    return yield* cloudOp.run(inner, { kind: "op", op }, progress, at, ctx);
  });
}

export function install(inner: Inner): void {
  handlers.ways = (core, call, progress, at, ctx) => run(core, call as Of, progress, at, ctx);
  inner.stations.also.push({
    read: (address) => readStation(inner, address),
    event: (address, name, data) => {
      const ws = ofAddress(address);
      if (name === "ways" && get(data, "workspace") === ws) inner.scheduler.enqueue(address, `ways/${address}`, Priority.background, Effect.ignore(readStation(inner, address)));
    },
    // (not read again after an absence: a stream that came back says each change it missed, `ways` among them)
  });
}
