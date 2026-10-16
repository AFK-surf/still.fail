// One station in several workspaces (docs/multi-workspace.md), as the clients show it: which stations of the viewer's
// other workspaces could be added to this one, the workspaces a station is in, and `station.join`, which adds one.
//
// Topics:
//   joinable {workspace}     the stations to pick in 添加 station: those whose home workspace (not one they joined) the
//                            viewer is an owner or admin of, not in this workspace already; from what is held of the
//                            viewer's workspaces only (nothing is asked for it)
//   memberships {station}    the workspaces the station is in (its `GET /workspaces`), with each joined one's folders
//                            (`GET /drive`'s `joined`), for its home workspace's owners and admins: read while a page
//                            shows it, kept by its address
// Calls:
//   station.join {workspace, station, name?}   the station (its address in its home workspace) added to `workspace`:
//                            an enrollment made there, then the station told to join with it, over its home link
//
// What a station's managers pin for a joined workspace (`drive.setRoots` with `workspace`) comes back with the drive as
// the station has it, `joined` with it (heardDrive).
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { encode } from "../ops.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { Priority } from "../sync/scheduler.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";
import { places, type Place } from "./xshare.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

type Of = Extract<Call, { kind: "stationJoin" }>;

/// What is held of a station's workspaces (the `memberships` record, by its address): its `GET /workspaces`, and the
/// folders of each workspace it joined; `old`: a station from before several workspaces (it has no such route).
type Held = { workspaces: J[]; canJoin: boolean; joined: Record<string, J[]> | null } | { old: true };

const RECORD = "memberships";

/// Why a station's workspaces could not be read this run, by core and address.
const failures = new WeakMap<Inner, Map<string, string>>();
const failed = (inner: Inner): Map<string, string> => {
  let m = failures.get(inner);
  if (!m) failures.set(inner, (m = new Map()));
  return m;
};

const manager = (role: string | null) => role === "owner" || role === "admin";

/// A workspace's stations as the cloud lists them there (held), or null while it is not read.
function stationsOf(inner: Inner, workspace: string): J[] | null {
  const v = inner.data.shared({ topic: "workspace", workspace });
  return isObject(v) && Array.isArray(v.stations) ? v.stations : null;
}

/// The name of a station's home workspace, when it is one of the viewer's: the one listing it but not as joined. None
/// where the station's home is this workspace, or one the viewer is not in.
export function homeName(inner: Inner, workspace: string, id: string): string | null {
  for (const p of places(inner)) {
    if (p.id === workspace) continue;
    const s = stationsOf(inner, p.id)?.find((s) => get(s, "id") === id);
    if (s !== undefined && get(s, "joined") !== true) return p.name;
  }
  return null;
}

/// The `joinable` topic.
export function joinable(inner: Inner, workspace: string): J {
  const all = places(inner);
  const here = new Set((stationsOf(inner, workspace) ?? []).map((s) => get(s, "id")));
  const theirs = all.filter((p) => p.id !== workspace && manager(p.role));
  let loading = stationsOf(inner, workspace) === null;
  const items: J[] = [];
  const seen = new Set<string>();
  for (const p of theirs) {
    const stations = stationsOf(inner, p.id);
    if (stations === null) {
      loading = true;
      continue;
    }
    for (const s of stations) {
      const id = str(get(s, "id"));
      // Joined there: its home is another workspace, whose managers add it elsewhere.
      if (id === null || get(s, "joined") === true || here.has(id) || seen.has(id)) continue;
      seen.add(id);
      const online = get(s, "online") === true;
      items.push({
        station: `${p.id}/${id}`,
        id,
        name: str(get(s, "name")) ?? id,
        ...(str(get(s, "emoji")) ? { emoji: get(s, "emoji") } : {}),
        ...(str(get(s, "icon")) ? { icon: get(s, "icon") } : {}),
        workspace: p.id,
        workspaceName: p.name,
        online,
        line: `${p.name} · ${online ? t("core-views.joinable.online") : t("core-views.joinable.offline")}`,
      });
    }
  }
  return { offered: theirs.length > 0, loading, items };
}

/// Whether the viewer manages the station at `address`: an owner or admin of the workspace it is addressed in, which is
/// its home (the cloud does not list it there as joined).
function manages(inner: Inner, address: string, all: Place[] = places(inner)): boolean {
  const at = address.indexOf("/");
  if (at < 0) return false;
  const workspace = address.slice(0, at);
  const id = address.slice(at + 1);
  const s = stationsOf(inner, workspace)?.find((s) => get(s, "id") === id);
  return s !== undefined && get(s, "joined") !== true && manager(all.find((p) => p.id === workspace)?.role ?? null);
}

/// A drive root as the clients show it (DriveRoot).
const root = (r: J) => ({ path: str(get(r, "path")) ?? "", name: str(get(r, "name")) ?? str(get(r, "path")) ?? "", state: str(get(r, "state")) ?? "ok" });

/// The `memberships` topic.
export function memberships(inner: Inner, address: string): J {
  const all = places(inner);
  const none = { manages: false, loading: false, canJoin: false, workspaces: [] };
  if (!manages(inner, address, all)) return none;
  const held = inner.data.record(RECORD, address) as Held | undefined;
  const error = failed(inner).get(address);
  if (held === undefined) return { ...none, manages: true, loading: error === undefined, ...(error !== undefined ? { error } : {}) };
  if ("old" in held) return { ...none, manages: true, error: t("core-misc.join.oldStation") };
  const here = address.slice(0, address.indexOf("/"));
  const workspaces = held.workspaces.flatMap((w) => {
    const workspace = str(get(w, "workspace"));
    if (workspace === null) return [];
    const home = get(w, "home") === true;
    const roots = home ? [] : arr(held.joined?.[workspace]).map(root);
    const line = home
      ? t("core-views.memberships.home")
      : roots.length > 0
        ? t("core-views.memberships.folders", { names: roots.map((r) => r.name).join(t("core-views.list_separator")) })
        : t("core-views.memberships.noFolders");
    return [{
      workspace,
      name: all.find((p) => p.id === workspace)?.name ?? str(get(w, "workspaceName")) ?? workspace,
      stationName: str(get(w, "name")) ?? "",
      home,
      here: workspace === here,
      line,
      roots,
    }];
  });
  // The home one first.
  workspaces.sort((a, b) => Number(b.home) - Number(a.home));
  return { manages: true, loading: false, canJoin: held.canJoin, workspaces, ...(error !== undefined ? { error } : {}) };
}

const invalidate = (inner: Inner, address: string) => inner.store.invalidateAll((t) => t.topic === "memberships" && t.station === address);

/// What the station's admin API says of its workspaces, held; with the folders of those it joined.
function read(inner: Inner, address: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    if (!manages(inner, address)) return;
    const addr = StationAddr.parse(address);
    const answer = yield* Effect.result(inner.stations.requests.call(addr, "GET", "/workspaces", null, { quiet: true }));
    if (answer._tag === "Failure") {
      const e = answer.failure;
      // A station from before several workspaces: it is in its home one alone.
      if (e.status === 404) {
        failed(inner).delete(address);
        inner.data.put(RECORD, address, { old: true });
      } else failed(inner).set(address, e.message);
      invalidate(inner, address);
      return;
    }
    const workspaces = arr(get(answer.success, "workspaces"));
    let joined: Record<string, J[]> | null = null;
    if (workspaces.length > 1) {
      const drive = yield* Effect.result(inner.stations.requests.call(addr, "GET", "/drive", null, { quiet: true }));
      if (drive._tag === "Success" && isObject(get(drive.success, "joined"))) joined = get(drive.success, "joined");
    }
    failed(inner).delete(address);
    inner.data.put(RECORD, address, { workspaces, canJoin: get(answer.success, "canJoin") === true, joined });
    invalidate(inner, address);
  });
}

/// The drive as a station answered a change of its pinned folders: the folders of each workspace it joined, as they
/// are now (`joined`, for its managers), in what is held of its workspaces.
export function heardDrive(inner: Inner, address: string, answer: unknown): void {
  const joined = get(answer, "joined");
  if (!isObject(joined)) return;
  const held = inner.data.record(RECORD, address) as Held | undefined;
  if (held === undefined || "old" in held) return;
  inner.data.put(RECORD, address, { ...held, joined });
  invalidate(inner, address);
}

/// What the station's refusal to join says, in words.
function joinError(e: CoreError): CoreError {
  const m = e.message;
  const as = (key: string, args?: Record<string, unknown>) => new CoreError(e.code, t(key, args), e.status);
  // A station from before several workspaces has no such route.
  if (e.status === 404) return as("core-misc.join.oldStation");
  if (e.status === 403) return as("core-misc.join.notManager");
  if (m.includes("more than one workspace yet")) return as("core-misc.join.oldCloud");
  if (m.includes("locked_workspace")) return as("core-misc.join.lockedTarget");
  if (m.includes("workspace is locked")) return as("core-misc.join.lockedStation");
  if (m.includes("too_many_stations")) return as("core-misc.join.tooMany");
  if (m.includes("enrollment_not_found")) return as("core-misc.join.expired");
  return e.status === undefined ? e : as("core-misc.join.failed", { error: m });
}

/// `station.join`: an enrollment made in the workspace, as the account that reaches it; the station told to join with it,
/// over the link of its home workspace; then the workspaces read again, so the station is listed in the one it joined.
function join(inner: Inner, c: Of, ctx: J): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const addr = yield* Effect.try({ try: () => StationAddr.parse(c.station), catch: (e) => e as CoreError });
    if (addr.workspace === c.workspace) return yield* Effect.fail(CoreError.invalid(t("core-misc.join.same")));
    const sub = inner.workspaces.owner(c.workspace);
    if (sub === null) return yield* Effect.fail(new CoreError("not_found", t("core-misc.account.no_access"), 404));
    const name = c.name ?? inner.cloudSync.nameOf(c.station) ?? addr.station;
    const made = yield* inner.provider.request(sub, "POST", `/v1/workspaces/${encode(c.workspace)}/enrollments`, { name }, ctx);
    const token = str(get(made, "token"));
    if (token === null) return yield* Effect.fail(new CoreError("invalid", t("core-misc.join.noToken")));
    const answer = yield* Effect.mapError(inner.stations.requests.call(addr, "POST", "/workspaces/join", { token }, { ctx }), joinError);
    const held = inner.data.record(RECORD, c.station) as Held | undefined;
    inner.data.put(RECORD, c.station, {
      workspaces: arr(get(answer, "workspaces")),
      canJoin: get(answer, "canJoin") === true,
      joined: held !== undefined && !("old" in held) ? held.joined : null,
    });
    invalidate(inner, c.station);
    // Listed in the workspace it joined (and the folders of the one it joined read with its workspaces).
    yield* inner.cloudSync.refreshAll();
    readSoon(inner, c.station);
    return { joined: get(answer, "joined") ?? null };
  });
}

/// Reads a station's workspaces behind what a page shows (one read at a time for it: the scheduler folds asks).
const readSoon = (inner: Inner, address: string) => inner.scheduler.enqueue(address, `${address} memberships`, Priority.shown, read(inner, address));

export function install(inner: Inner): void {
  handlers.stationJoin = (_inner, call, _progress, _at, ctx) => join(inner, call as Of, ctx);
  // The stations whose workspaces a page shows.
  const live = new Set<string>();
  // What is listed in each workspace changed: which stations could be added, who manages which (one shown that was not
  // known to be managed is read now), a station's home's name in a list.
  inner.data.onChange((topic) => {
    if (topic.topic !== "workspace") return;
    for (const address of live) if (inner.data.record(RECORD, address) === undefined && !failed(inner).has(address) && manages(inner, address)) readSoon(inner, address);
    inner.store.invalidateAll((t) => t.topic === "joinable" || t.topic === "memberships" || t.topic === "stations");
  });
  inner.router.owners.push(owner(inner, live));
}

function owner(inner: Inner, live: Set<string>): Owner {
  return {
    owns: (t: Topic) => t.topic === "joinable" || t.topic === "memberships",
    start: (t: Topic) => {
      if (t.topic !== "memberships") return;
      const address = t.station as string;
      live.add(address);
      // Shown: read now, what is held showing meanwhile.
      readSoon(inner, address);
    },
    stop: (t: Topic) => {
      if (t.topic === "memberships") live.delete(t.station as string);
    },
    compute: (t: Topic) => (t.topic === "joinable" ? { ok: joinable(inner, t.workspace as string) } : { ok: memberships(inner, t.station as string) }),
  };
}
