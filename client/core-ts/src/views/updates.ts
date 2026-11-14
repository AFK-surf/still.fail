// The workspace's software and agent runtime updates in one view (`stationUpdates`), and the calls that act across
// its stations (`updates.check`, `updates.update`, `updates.retry`, `updates.repair`, `updates.channel`, `updates.auto`).
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import type { Call } from "../core/calls.ts";
import { handlers } from "../core/execute.ts";
import { CoreError } from "../error.ts";
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import * as ops from "../ops.ts";
import type { SpanContext } from "../trace.ts";
import { arr as arrU, get, isObject } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];

type UpdatesCall = Extract<Call, { kind: "updates" }>;

const KINDS = ["station", "claude", "codex", "agy", "dsh", "grok", "cursor", "devin", "hermes"] as const;

const NAMES: Record<string, string> = {
  station: "Station",
  claude: "Claude Code",
  codex: "Codex",
  agy: "Antigravity CLI",
  dsh: "DeepSeek Harness",
  grok: "Grok Build",
  cursor: "Cursor Agent",
  devin: "Devin CLI",
  hermes: "Hermes Agent",
};

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

function isDesktopNote(note: string | null): boolean {
  if (note === null) return false;
  return note.includes("桌面") || note.toLowerCase().includes("desktop");
}

export type StationUpdateSource = {
  id: string;
  address: string;
  name: string;
  online: boolean;
  version?: string | null;
  joined?: boolean;
  home?: string | null;
  updates?: unknown;
  updating?: boolean;
};

export function stationUpdatesView(stations: StationUpdateSource[], canEdit: boolean, clock: { now: number; offsetMin: number }): J | null {
  if (stations.length === 0) return null;

  const ownStations = stations.filter((s) => !s.joined);
  const byStation: Record<string, J> = {};
  let maxCheckedAt = 0;
  let channel = "stable";
  let channelSet = false;
  let auto = true;
  let autoSet = false;

  const seenKinds = new Set<string>(KINDS);
  for (const s of stations) {
    const list = arr(s.updates);
    for (const u of list) {
      const id = str(get(u, "id"));
      if (id !== null) seenKinds.add(id);
      const checkedAt = get(u, "checkedAt");
      if (typeof checkedAt === "number" && checkedAt > maxCheckedAt) maxCheckedAt = checkedAt;
      if (id === "station" && !s.joined) {
        const ch = str(get(u, "channel"));
        if (ch !== null && (!channelSet || ch === "beta")) {
          channel = ch;
          channelSet = true;
        }
        const a = get(u, "auto");
        if (typeof a === "boolean" && !autoSet) {
          auto = a;
          autoSet = true;
        }
      }
    }
    const badge = stationBadgeOf(s);
    if (badge !== null) {
      byStation[s.address] = badge;
      if (s.id !== s.address) byStation[s.id] = badge;
    }
  }

  const items: J[] = [];
  for (const id of seenKinds) {
    const item = softwareItemOf(id, stations, ownStations.length > 1, channel, auto);
    if (item !== null) items.push(item);
  }

  const checkedText = maxCheckedAt > 0
    ? t("core-views.updates.checked", { when: format.relativeTime(maxCheckedAt, clock.now, clock.offsetMin) })
    : t("core-views.updates.checked", { when: t("core-views.present.profile.never_checked") });

  return {
    canEdit,
    channel,
    auto,
    checkedText,
    items,
    ...(Object.keys(byStation).length > 0 ? { byStation } : {}),
  };
}

function stationBadgeOf(s: StationUpdateSource): J | null {
  const list = arr(s.updates);
  const stationEntry = list.find((u) => get(u, "id") === "station");
  if (get(stationEntry, "state") === "failed") {
    return { updateText: t("core-views.updates.badge.failed"), updateBad: true };
  }
  const failedRuntime = list.find((u) => get(u, "id") !== "station" && get(u, "state") === "failed");
  if (failedRuntime !== undefined) {
    const name = str(get(failedRuntime, "name")) ?? NAMES[str(get(failedRuntime, "id")) ?? ""] ?? "";
    return {
      updateText: name !== "" ? t("core-views.updates.badge.software_failed", { name }) : t("core-views.updates.badge.failed"),
      updateBad: true,
    };
  }
  const repairRuntime = list.find((u) => get(u, "repairable") === true);
  if (repairRuntime !== undefined) {
    const name = str(get(repairRuntime, "name")) ?? NAMES[str(get(repairRuntime, "id")) ?? ""] ?? "Codex";
    return { updateText: t("core-views.updates.badge.repair", { name }), updateBad: true };
  }
  const updatingEntry = (get(stationEntry, "state") === "updating" ? stationEntry : undefined) ?? list.find((u) => get(u, "state") === "updating");
  if (updatingEntry !== undefined || s.updating === true) {
    const pct = get(updatingEntry, "percent");
    const updateText = typeof pct === "number"
      ? t("core-views.updates.badge.updating_percent", { percent: Math.round(pct) })
      : t("core-views.updates.badge.updating");
    return { updateText };
  }
  return null;
}

function softwareItemOf(
  id: string,
  stations: StationUpdateSource[],
  multiOwn: boolean,
  channel: string,
  auto: boolean,
): J | null {
  let name = NAMES[id] ?? id;
  let latest: string | null = null;
  let anyRelevant = id === "station";

  const upToDate: { s: StationUpdateSource; u: J }[] = [];
  const updating: { s: StationUpdateSource; u: J }[] = [];
  const outdated: { s: StationUpdateSource; u: J }[] = [];
  const failed: { s: StationUpdateSource; u: J }[] = [];
  const repair: { s: StationUpdateSource; u: J }[] = [];
  const selfManaged: { s: StationUpdateSource; u: J }[] = [];
  let desktopCount = 0;
  let offlineCount = 0;
  const joinedByHome = new Map<string, number>();
  const notes: string[] = [];

  for (const s of stations) {
    const u = arr(s.updates).find((entry) => get(entry, "id") === id) ?? null;
    const uName = str(get(u, "name"));
    if (uName !== null) name = uName;
    const uLatest = str(get(u, "latest"));
    if (uLatest !== null && latest === null) latest = uLatest;

    const installed = get(u, "installed") === true;
    const state = str(get(u, "state")) ?? "idle";
    const repairable = get(u, "repairable") === true;

    if (s.joined) {
      if (id === "station" || installed) {
        anyRelevant = true;
        const home = str(s.home) ?? "";
        if (home !== "") joinedByHome.set(home, (joinedByHome.get(home) ?? 0) + 1);
      }
      continue;
    }

    if (!s.online && state !== "updating" && !(id === "station" && s.updating === true)) {
      if (id === "station" || installed) {
        anyRelevant = true;
        offlineCount++;
      }
      continue;
    }

    if (id !== "station" && !installed && state !== "updating" && state !== "failed" && !repairable) {
      continue;
    }

    anyRelevant = true;

    if (state === "failed") {
      failed.push({ s, u });
      const msg = str(get(u, "message"));
      if (msg !== null) {
        const ver = str(get(u, "version")) ?? (id === "station" ? str(s.version) : null);
        const label = ver !== null ? t("core-views.by_label", { name: s.name, state: ver }) : s.name;
        notes.push(multiOwn || ver !== null ? t("core-views.named_error", { name: label, error: msg }) : msg);
      }
      continue;
    }

    if (repairable) {
      repair.push({ s, u });
      const note = str(get(u, "note"));
      if (note !== null) {
        const ver = str(get(u, "version"));
        const label = ver !== null ? t("core-views.by_label", { name: s.name, state: ver }) : s.name;
        notes.push(multiOwn || ver !== null ? t("core-views.named_error", { name: label, error: note }) : note);
      }
      continue;
    }

    if (state === "updating" || (id === "station" && s.updating === true)) {
      updating.push({ s, u });
      continue;
    }

    const note = str(get(u, "note"));
    if (get(u, "updatable") === false) {
      if (id === "station" && isDesktopNote(note)) {
        desktopCount++;
      } else {
        selfManaged.push({ s, u });
      }
      continue;
    }

    if (get(u, "newer") === true || get(u, "downgrade") === true) {
      outdated.push({ s, u });
      continue;
    }

    upToDate.push({ s, u });
  }

  if (!anyRelevant) return null;

  const segments: string[] = [];
  if (latest !== null) {
    segments.push(
      id === "station"
        ? t(channel === "beta" ? "core-views.updates.latest_beta" : "core-views.updates.latest_stable", { version: latest })
        : t("core-views.updates.latest", { version: latest }),
    );
  }
  if (upToDate.length > 0) {
    segments.push(t("core-views.updates.up_to_date", { n: upToDate.length }));
  }
  for (const { s, u } of updating) {
    const pct = get(u, "percent");
    const prog = str(get(u, "progress"));
    if (typeof pct === "number" && prog !== null) {
      segments.push(t("core-views.updates.station_updating_percent_detail", { name: s.name, percent: Math.round(pct), progress: prog }));
    } else if (typeof pct === "number") {
      segments.push(t("core-views.updates.station_updating_percent", { name: s.name, percent: Math.round(pct) }));
    } else if (prog !== null) {
      segments.push(t("core-views.updates.station_updating_detail", { name: s.name, progress: prog }));
    } else {
      segments.push(t("core-views.updates.station_updating", { name: s.name }));
    }
  }
  for (const { s, u } of outdated) {
    const ver = str(get(u, "version")) ?? (id === "station" ? str(s.version) : null);
    if (ver !== null) segments.push(t("core-views.updates.station_version", { name: s.name, version: ver }));
  }
  if (desktopCount > 0) {
    segments.push(t("core-views.updates.with_desktop", { n: desktopCount }));
  }
  if (selfManaged.length > 0) {
    if (upToDate.length === 0 && updating.length === 0 && outdated.length === 0 && failed.length === 0 && repair.length === 0 && selfManaged.length === 1) {
      const only = selfManaged[0]!;
      const ver = str(get(only.u, "version")) ?? t("core-views.software.unknown");
      segments.push(t("core-views.updates.self_managed_station", { name: only.s.name, version: ver }));
    } else {
      segments.push(t("core-views.updates.self_managed_n", { n: selfManaged.length }));
    }
  }
  for (const [home, count] of joinedByHome) {
    segments.push(t("core-views.updates.from_workspace", { n: count, workspace: home }));
  }
  if (offlineCount > 0) {
    segments.push(t("core-views.updates.offline", { n: offlineCount }));
  }
  if (segments.length === 0) {
    const firstVer = stations.map((s) => str(get(arr(s.updates).find((u) => get(u, "id") === id), "version")) ?? (id === "station" ? str(s.version) : null)).find((v) => v !== null);
    segments.push(firstVer ?? t("core-views.software.unknown"));
  }

  const item: J = {
    id,
    name,
    state: "idle",
    versionText: segments.join(" · "),
    ...(notes.length > 0 ? { notes } : {}),
    ...(id === "station" ? { channel, auto } : {}),
  };

  if (failed.length > 0) {
    item.state = "failed";
    item.failedText = t("core-views.updates.failed_n", { n: failed.length });
  } else if (repair.length > 0) {
    item.state = "failed";
    item.repairable = true;
    item.primaryButton = true;
    item.failedText = t("core-views.updates.repair_n", { n: repair.length });
  } else if (outdated.length > 0) {
    item.state = "idle";
    item.newer = true;
    item.updatable = true;
    if (latest !== null) item.latest = latest;
    item.statusText = t("core-views.updates.outdated_n", { n: outdated.length });
  } else if (updating.length > 0) {
    item.state = "updating";
    const pcts = updating.map(({ u }) => get(u, "percent")).filter((p): p is number => typeof p === "number");
    if (pcts.length > 0) {
      const avg = Math.round(pcts.reduce((a, b) => a + b, 0) / pcts.length);
      item.percent = avg;
      item.statusText = `${avg}%`;
    } else {
      item.statusText = t("core-views.software.updating");
    }
  } else if (upToDate.length === 0 && (selfManaged.length > 0 || desktopCount > 0)) {
    item.state = "idle";
    item.noButton = true;
    item.statusText = desktopCount > 0 && selfManaged.length === 0 ? "" : t("core-views.updates.self_managed");
  } else if (upToDate.length > 0) {
    item.state = "idle";
    item.statusText = t("core-views.software.latest");
  }

  return item;
}

export function parseUpdatesCall(name: string, rawParams: unknown): UpdatesCall | null {
  const action = name.slice("updates.".length);
  if (action !== "check" && action !== "update" && action !== "retry" && action !== "repair" && action !== "channel" && action !== "auto") {
    return null;
  }
  const params = isObject(rawParams) ? (rawParams as Record<string, unknown>) : {};
  const workspace = typeof params.workspace === "string" ? params.workspace.trim() : "";
  if (workspace === "") throw CoreError.invalid(`${name} requires workspace`);
  return { kind: "updates", name: action, workspace, params };
}

function targetStations(inner: Inner, ws: string, predicate?: (updates: J[]) => boolean): string[] {
  const raw = arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "stations"));
  const all: string[] = [];
  const matched: string[] = [];
  for (const s of raw) {
    const id = str(get(s, "id"));
    if (id === null || get(s, "joined") === true) continue;
    const address = `${ws}/${id}`;
    if (inner.stations.link(address) && !inner.stations.reachable(address)) continue;
    all.push(address);
    if (predicate !== undefined) {
      const updates = arr(inner.data.overviewUpdates(address));
      if (predicate(updates)) matched.push(address);
    }
  }
  return predicate !== undefined && matched.length > 0 ? matched : all;
}

function runUpdatesCall(inner: Inner, c: UpdatesCall, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const id = str(c.params.id) ?? "station";
    let targets: string[];
    let makeOp: (station: string) => ops.Request | null;

    switch (c.name) {
      case "check":
        targets = targetStations(inner, c.workspace);
        makeOp = (station) => ops.request("software.check", { station });
        break;
      case "channel": {
        const ch = c.params.channel === "beta" ? "beta" : "stable";
        targets = targetStations(inner, c.workspace);
        makeOp = (station) => ops.request("software.channel", { station, channel: ch });
        break;
      }
      case "auto": {
        const on = c.params.on === true;
        targets = targetStations(inner, c.workspace);
        makeOp = (station) => ops.request("software.auto", { station, on });
        break;
      }
      case "update":
        targets = targetStations(inner, c.workspace, (updates) =>
          updates.some((u) => get(u, "id") === id && get(u, "updatable") !== false && (get(u, "newer") === true || get(u, "downgrade") === true)),
        );
        makeOp = (station) => ops.request("software.update", { station, id });
        break;
      case "retry":
        targets = targetStations(inner, c.workspace, (updates) =>
          updates.some((u) => get(u, "id") === id && (get(u, "state") === "failed" || get(u, "newer") === true || get(u, "downgrade") === true)),
        );
        makeOp = (station) => ops.request("software.update", { station, id });
        break;
      case "repair":
        targets = targetStations(inner, c.workspace, (updates) =>
          updates.some((u) => get(u, "id") === id && (get(u, "repairable") === true || get(u, "state") === "failed" || get(u, "newer") === true)),
        );
        makeOp = (station) => ops.request("software.update", { station, id, repair: true });
        break;
    }

    let firstError: CoreError | null = null;
    let anyOk = false;
    yield* Effect.forEach(
      targets,
      (station) => {
        const op = makeOp(station);
        if (op === null) return Effect.void;
        return Effect.result(inner.stations.perform(op, ctx)).pipe(
          Effect.tap((r) =>
            Effect.sync(() => {
              if (r._tag === "Success") anyOk = true;
              else if (firstError === null) firstError = r.failure;
            }),
          ),
        );
      },
      { concurrency: "unbounded" },
    );
    if (!anyOk && firstError !== null) return yield* Effect.fail(firstError);
    return { ok: true };
  });
}

export function install(inner: Inner): void {
  handlers.updates = (core, call, _progress, _at, ctx) => runUpdatesCall(core, call as UpdatesCall, ctx);
}
