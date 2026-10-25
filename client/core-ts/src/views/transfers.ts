// Copies (and moves) into a station's drive (docs/drive.md "Copying between stations"): what the core holds of the
// transfers a person asked, on every station of a workspace, and what they do about them. Each runs on the station the
// files go to (station/src/drive/transfers.ts), whatever becomes of this device: the core only asks for it, and shows it
// as its station says it. Held in each station's link's memory (kept, station/memory.ts: there as the app opens again),
// as the stations say them: read when a station's stream opens (GET
// /drive/transfers; a station from before answers 404, and has none), told as they change (`drive-transfers`).
//
// Topic:
//   driveTransfers {workspace}   the person's transfers into the workspace's stations, newest first
// Calls:
//   drive.transfer {from: {station, root, path, names}, to: {station, root, path}, move?, conflicts?}
//                                copies `names` of a folder into another folder, on the same station or another one: the
//                                station they are on grants the one they go to its read of them (POST /drive/grant), and
//                                that one copies them (POST /drive/transfers); answers the transfer as shown
//   drive.transfer.cancel {station, id}, drive.transfer.retry {station, id}
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError } from "../error.ts";
import { bytes } from "../format.ts";
import { t } from "../i18n.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { Priority } from "../sync/scheduler.ts";
import { encode } from "../ops.ts";
import { get, isObject } from "../util.ts";
import { ofAddress } from "../workspace.ts";

type J = any;
type Of = Extract<Call, { kind: "driveTransfer" }>;

/// What the core holds of one station's transfers: `supported` null until read, false for a station from before.
type Held = { supported: boolean | null; transfers: J[] };

const KEY = "driveTransfers";
const heldAt = (inner: Inner, address: string) => inner.stations.link(address)?.memory.get(KEY) as Held | undefined;
const hold = (inner: Inner, address: string, held: Held) => inner.stations.link(address)?.memory.set(KEY, held);

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const stationOf = (address: string) => address.slice(ofAddress(address).length + 1);

const workspaceView = (inner: Inner, ws: string): J => inner.data.shared({ topic: "workspace", workspace: ws });
const stationsOf = (inner: Inner, ws: string): { id: string; name: string }[] => arr(get(workspaceView(inner, ws), "stations")).filter((s) => typeof s?.id === "string");

function invalidate(inner: Inner, ws: string): void {
  inner.store.invalidateAll((topic) => topic.topic === "driveTransfers" && topic.workspace === ws);
}

/// One station's transfer as it says it now: in place (new ones first).
function put(inner: Inner, address: string, transfer: unknown): void {
  const id = str(get(transfer, "id"));
  if (id === null || !isObject(transfer)) return;
  const held = heldAt(inner, address) ?? { supported: true, transfers: [] };
  const at = held.transfers.findIndex((x) => x.id === id);
  const transfers = at >= 0 ? held.transfers.map((x, i) => (i === at ? transfer : x)) : [transfer, ...held.transfers];
  hold(inner, address, { supported: true, transfers });
  invalidate(inner, ofAddress(address));
}

const ask = (inner: Inner, address: string, method: string, path: string, body: unknown = null) =>
  inner.stations.requests.call(StationAddr.parse(address), method, path, body, { quiet: true });

/// A station's transfers, read whole.
function read(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (!inner.stations.link(address) || !inner.stations.reachable(address)) return;
    const got = yield* Effect.result(ask(inner, address, "GET", "/drive/transfers"));
    if (got._tag === "Success") hold(inner, address, { supported: true, transfers: arr(get(got.success, "transfers")).filter(isObject) });
    else if (got.failure.status === 404) hold(inner, address, { supported: false, transfers: [] });
    else return;
    invalidate(inner, ofAddress(address));
  });
}

/// The last part of a path, as a folder is named: its name, or the path itself for a top (`/`, `C:\`).
const folderName = (path: string) => path.split(/[\\/]/).filter(Boolean).at(-1) ?? path;

/// A transfer as the list shows it.
export function shown(x: J, address: string, names: Map<string, string>): J {
  const ws = ofAddress(address);
  const here = stationOf(address);
  const fromId = str(get(x.from, "station")) ?? here;
  const nameOf = (id: string) => names.get(id) ?? str(get(x.from, "stationName")) ?? id;
  const state = str(x.state) ?? "queued";
  const total = num(x.total);
  const copied = num(x.copied);
  const count = num(x.count);
  const fileNames = arr(get(x.from, "names")).filter((n) => typeof n === "string") as string[];
  const toRoot = str(get(x.to, "root")) ?? "";
  const toPath = str(get(x.to, "path")) ?? "";
  const into = toPath !== "" ? folderName(toPath) : folderName(toRoot);
  const active = state === "queued" || state === "walking" || state === "copying";
  const progress = state === "done" ? 1 : total > 0 ? Math.min(1, copied / total) : count > 0 ? Math.min(1, num(x.done) / count) : 0;
  const statusText =
    state === "queued" ? t("core-logic.transfer.queued")
    : state === "walking" ? t("core-logic.transfer.walking")
    : state === "copying" ? t("core-logic.transfer.copying", { copied: bytes(copied), total: bytes(total) })
    : state === "done" ? t(x.move === true ? "core-logic.transfer.moved" : "core-logic.transfer.done", { total: bytes(total) })
    : state === "cancelled" ? t("core-logic.transfer.cancelled")
    : t("core-logic.transfer.failed", { error: str(x.error) ?? "" });
  const first = fileNames[0] ?? "";
  return {
    id: String(x.id),
    station: address,
    stationName: names.get(here) ?? here,
    fromStation: `${ws}/${fromId}`,
    fromStationName: nameOf(fromId),
    fromRoot: str(get(x.from, "root")) ?? "",
    fromPath: str(get(x.from, "path")) ?? "",
    names: fileNames,
    toRoot,
    toPath,
    toText: `${names.get(here) ?? here} › ${into}`,
    title: fileNames.length > 1 ? t("core-logic.transfer.many", { name: first, n: fileNames.length }) : first,
    move: x.move === true,
    state,
    active,
    progress,
    total,
    copied,
    count,
    files: num(x.files),
    ...(str(x.current) !== null ? { current: x.current } : {}),
    statusText,
    ...(str(x.error) !== null ? { error: x.error } : {}),
    createdAt: num(x.createdAt),
    ...(typeof x.endedAt === "number" ? { endedAt: x.endedAt } : {}),
  };
}

/// The `driveTransfers` topic: every station's, newest first.
export function transfersView(inner: Inner, ws: string): J {
  const stations = stationsOf(inner, ws);
  const names = new Map(stations.map((s) => [s.id, s.name]));
  const held = stations.map((s) => [`${ws}/${s.id}`, heldAt(inner, `${ws}/${s.id}`)] as const);
  const transfers = held.flatMap(([address, h]) => (h?.transfers ?? []).map((x) => shown(x, address, names))).sort((a, b) => b.createdAt - a.createdAt);
  return { supported: held.some(([, h]) => h?.supported === true), loaded: held.some(([, h]) => h !== undefined && h.supported !== null), transfers };
}

function owner(inner: Inner): Owner {
  return {
    owns: (topic: Topic) => topic.topic === "driveTransfers",
    start: (topic: Topic) => {
      const ws = topic.workspace as string;
      for (const s of stationsOf(inner, ws)) {
        const address = `${ws}/${s.id}`;
        inner.scheduler.enqueue(address, `${address} driveTransfers`, Priority.shown, read(inner, address));
      }
    },
    compute: (topic: Topic) => ({ ok: transfersView(inner, typeof topic.workspace === "string" ? topic.workspace : "") }),
  };
}

const at = (v: unknown, field: string): J => (isObject(v) ? (v as J)[field] : undefined);
const need = (v: unknown, field: string): string => {
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
  return v;
};

/// A copy asked, a transfer stopped or taken up again.
function run(inner: Inner, c: Of): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const p = c.params;
    const names = (address: string) => new Map(stationsOf(inner, ofAddress(address)).map((s) => [s.id, s.name]));
    if (c.action === "cancel" || c.action === "retry") {
      const station = need(p.station, "station");
      const id = need(p.id, "id");
      const got = yield* ask(inner, station, "POST", `/drive/transfers/${encode(id)}/${c.action}`);
      put(inner, station, get(got, "transfer"));
      return { transfer: shown(get(got, "transfer"), station, names(station)) };
    }
    const from = { station: need(at(p.from, "station"), "from.station"), root: need(at(p.from, "root"), "from.root"), path: str(at(p.from, "path")) ?? "", names: arr(at(p.from, "names")) };
    const to = { station: need(at(p.to, "station"), "to.station"), root: need(at(p.to, "root"), "to.root"), path: str(at(p.to, "path")) ?? "" };
    if (from.names.length === 0 || from.names.some((n) => typeof n !== "string")) return yield* Effect.fail(CoreError.invalid(t("core-misc.params.missing", { field: "from.names" })));
    if (ofAddress(from.station) !== ofAddress(to.station)) return yield* Effect.fail(CoreError.invalid(t("core-logic.transfer.otherWorkspace")));
    const move = p.move === true;
    const conflicts = isObject(p.conflicts) ? p.conflicts : {};
    const same = from.station === to.station;
    // Another station's files: that station grants the one they go to its read of them, for this person.
    const grant = same ? null : str(get(yield* ask(inner, from.station, "POST", "/drive/grant", { root: from.root, path: from.path, names: from.names, move }), "grant"));
    if (!same && grant === null) return yield* Effect.fail(new CoreError("io", t("core-logic.transfer.noGrant")));
    const got = yield* ask(inner, to.station, "POST", "/drive/transfers", {
      from: { ...(same ? {} : { station: stationOf(from.station), grant }), root: from.root, path: from.path, names: from.names },
      to: { root: to.root, path: to.path },
      move,
      conflicts,
    });
    put(inner, to.station, get(got, "transfer"));
    return { transfer: shown(get(got, "transfer"), to.station, names(to.station)) };
  });
}

export function install(inner: Inner): void {
  handlers.driveTransfer = (core, call) => run(core, call as Of);
  inner.stations.also.push({
    read: (address) => read(inner, address),
    event: (address, name, data) => {
      if (name === "drive-transfers" && isObject(get(data, "transfer"))) put(inner, address, get(data, "transfer"));
    },
  });
  inner.router.owners.push(owner(inner));
}
