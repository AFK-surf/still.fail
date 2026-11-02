// What a station can run, put together from its overview (views.rs, its second half): the runtimes a chat can start
// on and their models, what a session can be moved to and who runs it, what is worth a look about a session, an
// account's allowance in a few words.
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import * as jobs from "../jobs.ts";
import * as present from "../present.ts";
import * as model from "../shapes/model.ts";
import * as reasoning from "../shapes/reasoning.ts";
import { arr as arrU, equal, get as getU } from "../util.ts";
import { profileServes } from "./profile-scope.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: J): string | null => (typeof v === "string" ? v : null);

/// The runtimes a chat can run on, in the order they are offered.
export const RUNTIMES = format.RUNTIMES;

const profilesOf = (overview: J): J[] => arr(get(overview, "profiles"));
const runs = (p: J, runtime: string) => arr(get(p, "runtimes")).some((r) => r === runtime);
const sortedSet = (set: Set<string>) => [...set].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

/// The item of `list` whose `id` is `id`, or null.
export function find(list: J, id: J): J {
  if (!Array.isArray(list) || id === undefined || id === null) return null;
  return structuredClone(list.find((item) => equal(get(item, "id"), id)) ?? null);
}

/// The runtimes a chat can start on and their models.
export function runtimes(overview: J): J[] {
  const profiles = profilesOf(overview);
  return RUNTIMES.flatMap((runtime) => {
    const models = new Set<string>();
    for (const p of profiles.filter((p) => runs(p, runtime))) for (const m of arr(get(p, "models"))) if (typeof m === "string") models.add(m);
    return models.size === 0 ? [] : [{ runtime, models: sortedSet(models) }];
  });
}

const LOW_LEFT = 20;
const LOW_DISK = 10;
const LOW_DISK_BYTES = 10 * 1024 ** 3;

/// What is worth a look about a session now, most pressing first.
export function attention(overview: J, session: J, now: number): J[] {
  const out: J[] = [];
  const p = find(get(overview, "profiles"), get(session, "profile"));
  if (p !== null && typeof p === "object") {
    const state = get(get(p, "check"), "state");
    if (state === "login" || state === "failed") {
      const name = str(get(p, "name")) ?? "";
      out.push({ kind: "account", text: state === "login" ? t("core-views.attention.login", { name }) : t("core-views.attention.key_refused", { name }) });
    }
    if (get(get(p, "quota"), "state") === "ok") {
      for (const w of arr(get(get(p, "quota"), "windows"))) {
        const used = typeof get(w, "usedPercent") === "number" ? w.usedPercent : 0;
        const left0 = 100 - used;
        if (left0 > LOW_LEFT) continue;
        const label = format.windowName(str(get(w, "label")) ?? "");
        const left = format.round(Math.max(left0, 0));
        const resets = get(w, "resetsAt");
        const until = typeof resets === "number" && Number.isInteger(resets) ? resets : null;
        out.push({
          kind: "quota",
          text: t("core-views.attention.quota_left", { label, left }),
          more: until !== null ? format.refillsIn(until, now) : null,
          quota: { left, mark: format.windowMark(label)[0], level: left <= 10 ? "red" : "amber", until },
        });
      }
    }
  }
  const disk = get(overview, "disk");
  if (disk !== null && typeof disk === "object" && !Array.isArray(disk)) {
    const free = typeof disk.freeBytes === "number" ? disk.freeBytes : 0;
    const total = typeof disk.totalBytes === "number" ? disk.totalBytes : 0;
    if (total > 0 && ((free / total) * 100 <= LOW_DISK || free <= LOW_DISK_BYTES)) out.push({ kind: "disk", text: t("core-views.attention.disk", { size: format.gb(free) }) });
  }
  return out;
}

/// The profiles a session can run on.
export function runnableOn(overview: J, session: J, now: number): J[] {
  return profilesRunning(overview, str(get(session, "runtime")) ?? "", str(get(session, "model")), str(get(session, "profile")), now);
}

/// A model's spellings, the one it sends first: the one that is its key when a profile has it, else the first.
function spellings(key: string, ids: Set<string>): [string, string[]] {
  const list = sortedSet(ids);
  const sorted = [...list.filter((id) => id === key), ...list.filter((id) => id !== key)];
  return [sorted[0], sorted];
}

/// The models a session can move to, as a model control offers them.
export function choices(overview: J, session: J, now: number): J[] {
  const runtime = str(get(session, "runtime")) ?? "";
  const current = str(get(session, "profile"));
  const byKey = new Map<string, { ids: Set<string>; profiles: J[] }>();
  for (const p of profilesOf(overview).filter((p) => runs(p, runtime))) {
    const seen = new Set<string>();
    for (const m of arr(get(p, "models"))) {
      if (typeof m !== "string") continue;
      const k = model.key(m);
      let offered = byKey.get(k);
      if (!offered) {
        offered = { ids: new Set(), profiles: [] };
        byKey.set(k, offered);
      }
      offered.ids.add(m);
      if (!seen.has(k)) {
        seen.add(k);
        offered.profiles.push(p);
      }
    }
  }
  const keys = sortedSet(new Set(byKey.keys())).sort(model.compareOrder);
  return keys.map((key) => {
    const offered = byKey.get(key)!;
    const [m, ids] = spellings(key, offered.ids);
    return {
      model: m,
      name: model.name(m),
      family: model.family(m),
      ids,
      maker: present.maker(m),
      runtimes: [runtime],
      efforts: { [runtime]: commonEfforts(offered.profiles, runtime, m) },
      accounts: { [runtime]: profileLines(offered.profiles, runtime, m, current, now) },
    };
  });
}

function profileEfforts(profile: J, runtime: string, m: string | null): string[] {
  const catalog = get(get(profile, "check"), "modelEfforts");
  return reasoning.available(runtime, m ?? str(get(profile, "model")), catalog ?? null);
}

function commonEfforts(profiles: J[], runtime: string, m: string | null): string[] {
  return reasoning.common(profiles.map((p) => profileEfforts(p, runtime, m)), runtime);
}

function profilesRunning(overview: J, runtime: string, m: string | null, current: string | null, now: number): J[] {
  const profiles = profilesOf(overview)
    .filter((p) => runs(p, runtime))
    .filter((p) => m === null || arr(get(p, "models")).some((x) => typeof x === "string" && model.same(x, m)));
  return profileLines(profiles, runtime, m, current, now);
}

function profileLines(profiles: J[], runtime: string, m: string | null, current: string | null, now: number): J[] {
  return profiles.map((p) => {
    const id = str(get(p, "id")) ?? "";
    const spent = spentUntil(p);
    const line: J = {
      id,
      name: get(p, "name") ?? id,
      current: id === current,
      spent: spent !== null ? spentView(spent, now) : null,
      efforts: profileEfforts(p, runtime, m),
      kind: get(get(p, "access"), "kind") ?? null,
      runtime: get(p, "runtime") ?? null,
      quota: get(p, "quota") ?? null,
      quotaLine: quotaLine(get(p, "quota")),
    };
    if (typeof get(p, "providerMark") === "string") line.mark = p.providerMark;
    return line;
  });
}

/// The overview as the chats of `workspace` run on it (docs/multi-workspace.md): with the profiles the station says
/// they may (`serves`), else (a station of before it) those whose `workspaces` name it in one it joined (`joined`), every
/// one in its home.
export function servingIn(overview: J, workspace: string, joined: boolean): J {
  const profiles = get(overview, "profiles");
  if (!Array.isArray(profiles)) return overview;
  return { ...overview, profiles: profiles.filter((p) => profileServes(p, workspace, joined)) };
}

/// The models the station can run, each with the runtimes it runs on.
export function models(overview: J, now: number): J[] {
  const on = new Map<string, { runtimes: Set<string>; backs: (number | null)[]; ids: Set<string>; profiles: Map<string, J[]> }>();
  for (const p of profilesOf(overview)) {
    const rts = [...new Set(arr(get(p, "runtimes")).filter((r): r is string => typeof r === "string"))];
    const back = spentUntil(p);
    const keys = new Set<string>();
    for (const m of arr(get(p, "models"))) {
      if (typeof m !== "string") continue;
      const k = model.key(m);
      let entry = on.get(k);
      if (!entry) {
        entry = { runtimes: new Set(), backs: [], ids: new Set(), profiles: new Map() };
        on.set(k, entry);
      }
      for (const r of rts) entry.runtimes.add(r);
      entry.ids.add(m);
      if (!keys.has(k)) {
        keys.add(k);
        entry.backs.push(back);
        for (const r of rts) {
          let profiles = entry.profiles.get(r);
          if (!profiles) {
            profiles = [];
            entry.profiles.set(r, profiles);
          }
          profiles.push(p);
        }
      }
    }
  }
  const order = (r: string) => {
    const i = RUNTIMES.indexOf(r);
    return i < 0 ? Number.MAX_SAFE_INTEGER : i;
  };
  const keys = sortedSet(new Set(on.keys())).sort(model.compareOrder);
  return keys.map((key) => {
    const { runtimes: rs, backs, ids, profiles } = on.get(key)!;
    const [m, spelled] = spellings(key, ids);
    const rts = sortedSet(rs).sort((a, b) => order(a) - order(b));
    const spent = backs.every((b) => b !== null) ? backs.reduce<number>((min, b) => Math.min(min, b as number), Infinity) : null;
    const efforts: Record<string, J> = {};
    const accounts: Record<string, J> = {};
    for (const r of rts) {
      const offered = profiles.get(r) ?? [];
      efforts[r] = commonEfforts(offered, r, m);
      accounts[r] = profileLines(offered, r, m, null, now);
    }
    return { model: m, name: model.name(m), family: model.family(m), ids: spelled, runtimes: rts, maker: present.maker(m), efforts, accounts, spent: spent !== null ? spentView(spent, now) : null };
  });
}

/// Used up until a time (or for no one knows how long).
export function spentView(until: number, now: number): J {
  const at = Number.isFinite(until) ? until : null;
  const back = at !== null ? t("core-views.spent.back", { when: format.timeUntil(at, now) }) : null;
  return { until: at, text: back !== null ? t("core-views.spent.until", { back }) : t("core-views.spent.text"), back };
}

/// When a profile whose quota has a window used up can run again; null when nothing of it is used up.
export function spentUntil(profile: J): number | null {
  const quota = get(profile, "quota");
  if (get(quota, "state") !== "ok") return null;
  const full = arr(get(quota, "windows"))
    .filter((w) => typeof get(w, "usedPercent") === "number" && w.usedPercent >= 100)
    .map((w) => (typeof get(w, "resetsAt") === "number" ? w.resetsAt : Infinity));
  if (full.length === 0) return null;
  return full.reduce((max, at) => Math.max(max, at), 0);
}

/// What is left of an account's allowance, in a few words (shapes: QuotaLine).
export function quotaLine(quota: J): J {
  if (quota === null || typeof quota !== "object" || Array.isArray(quota)) return null;
  const windows = arr(quota.windows);
  if (quota.state !== "ok" || windows.length === 0) {
    const d = str(quota.detail);
    return d ? { text: d } : null;
  }
  const shown = windows
    .map((w) => {
      const label = format.windowName(str(get(w, "label")) ?? "");
      const [left, level] = present.leftLevel(typeof get(w, "usedPercent") === "number" ? w.usedPercent : 0);
      return { label, left, level, order: format.windowMark(label)[1] };
    })
    .sort((a, b) => a.order - b.order);
  let low: (typeof shown)[number] | null = null;
  for (const w of shown) if (w.level !== "ok" && (low === null || w.left < low.left)) low = w;
  if (low !== null) return { text: t("core-logic.choose.quota.low", { label: low.label, left: low.left }), level: low.level };
  return { text: shown.map((w) => `${w.label} ${w.left}%`).join(" · ") };
}

/// A session the station's machine kept, in a line: its runtime, where it ran (the home directory as ~), how long ago.
/// And its parts apart, for a list that groups and filters them (the app's): `where` (that path), `folder` (its last
/// part: the project), `day` (the heading of its day, local: 今天, 昨天, 星期三, 9月20日), `when` (how long ago today, its
/// clock time before), `own` (run by still.fail itself: under its own directory, not a terminal's).
export function machineMeta(session: J, now: number, offsetMin = 0): J {
  if (session === null || typeof session !== "object" || Array.isArray(session)) return session;
  const runtime = format.runtimeLabel(str(session.runtime) ?? "");
  const cwd = str(session.cwd) ?? "";
  const rest = cwd.startsWith("/Users/") ? cwd.slice(7) : cwd.startsWith("/home/") ? cwd.slice(6) : null;
  let short = cwd;
  if (rest !== null) {
    const at = rest.indexOf("/");
    if (at > 0) short = `~${rest.slice(at)}`;
    else if (at < 0 && rest !== "") short = "~";
  }
  let ago: string | null = null;
  if (typeof session.updatedAt === "number") {
    const secs = Math.max(format.round((now - session.updatedAt) / 1000), 0);
    ago = secs < 5 ? t("core-logic.jobs.ago.now") : secs >= 86_400 && secs < 2 * 86_400 ? t("core-logic.jobs.ago.yesterday") : t("core-logic.jobs.ago", { span: jobs.span(secs * 1000) });
  }
  const at = typeof session.updatedAt === "number" ? session.updatedAt : null;
  const today = at !== null && format.localDay(at, offsetMin) === format.localDay(now, offsetMin);
  const parts = cwd.split("/").filter((x) => x !== "");
  return {
    ...session,
    meta: [runtime, short, ago].filter((x) => x !== null).join(" · "),
    where: short,
    folder: short === "~" ? "~" : (parts[parts.length - 1] ?? short),
    day: at === null ? "" : format.dayLabel(at, now, offsetMin),
    when: at === null ? "" : today ? (ago ?? "") : format.clock(at, offsetMin),
    own: cwd.includes("/.stillfail/"),
  };
}

// ── the workspace's models on a station (docs/station-share.md 借用) ──

/// A station of the workspace as `stations` lists it: its address, id, name, whether it is up, and its overview.
type StationOf = { station: string; id: string; name: string; online: boolean; joined: boolean; overview: J; emoji: string | null; icon: string | null };

/// A station as an option names it: its name, and its mark where the workspace gave it one.
const markOf = (s: StationOf | undefined, name: string): J => ({ name: s?.name ?? name, ...(s?.emoji ? { emoji: s.emoji } : {}), ...(s?.icon ? { icon: s.icon } : {}) });

const stationsOf = (stations: J): StationOf[] =>
  arr(stations).flatMap((s) =>
    typeof get(s, "station") === "string" && typeof get(s, "id") === "string"
      ? [{ station: s.station, id: s.id, name: str(get(s, "name")) ?? s.id.slice(0, 8), online: get(s, "online") === true, joined: get(s, "joined") === true, overview: get(s, "overview"), emoji: str(get(s, "emoji")), icon: str(get(s, "icon")) }]
      : [],
  );

/// Each option said where its accounts are: `here` when one of them is the station's own, else `borrowed` from the
/// station that shares them with it (`from`: its name, as `stations` names it).
export function sourced(options: J[], overview: J, stations: J): J[] {
  const byStation = new Map(stationsOf(stations).map((s) => [s.id, s]));
  const byId = new Map(profilesOf(overview).map((p) => [str(get(p, "id")) ?? "", p]));
  return options.map((o) => {
    const ids = Object.values(get(o, "accounts") ?? {}).flatMap((list) => arr(list).map((a) => str(get(a, "id")) ?? ""));
    const hosts = ids.map((id) => {
      const share = get(byId.get(id), "share");
      return get(share, "role") === "user" ? (str(get(share, "host")) ?? "") : null;
    });
    if (hosts.length === 0 || hosts.some((h) => h === null)) return { ...o, availability: "here" };
    const host = hosts[0] as string;
    const station = markOf(byStation.get(host), host.slice(0, 8));
    return { ...o, availability: "borrowed", from: station.name, fromStation: station, fromText: t("core-views.models.borrowed_from", { station: station.name }) };
  });
}

/// The models the workspace's other stations up now offer that `here` does not, each with the profile it would borrow
/// (`borrow`): one of their own (not a copy they borrow themselves), of `runtime` where only it can run. Stations of
/// other workspaces this one joined lend nothing, and one joined lends to none (sharing is within a workspace).
export function borrowable(stations: J, here: string, have: J[], runtime: string | null, now: number): J[] {
  const all = stationsOf(stations);
  const self = all.find((s) => s.station === here);
  if (self === undefined || self.joined) return [];
  const taken = new Set(have.map((o) => model.key(str(get(o, "model")) ?? "")));
  const ownHere = new Set(profilesOf(self.overview).flatMap((p) => (typeof get(get(p, "share"), "id") === "string" ? [p.share.id] : [])));
  const out: J[] = [];
  for (const s of all) {
    if (s.station === here || !s.online || s.joined || get(s.overview, "sharing") !== true) continue;
    for (const p of profilesOf(s.overview)) {
      const share = get(p, "share");
      if (get(share, "role") === "user") continue;
      // Shared with this station already: its copy is on its way (or here, and its models with it).
      if (typeof get(share, "id") === "string" && ownHere.has(share.id)) continue;
      const lone = { ...s.overview, profiles: [p] };
      for (const o of models(lone, now)) {
        if (runtime !== null && !arr(o.runtimes).includes(runtime)) continue;
        const key = model.key(o.model);
        if (taken.has(key)) continue;
        taken.add(key);
        const allow = get(share, "allow");
        const shared = isShared(share);
        const rts: string[] = runtime !== null ? [runtime] : o.runtimes;
        out.push({
          ...o,
          runtimes: rts,
          // Not run here till borrowed: no account of this station's to keep to.
          accounts: Object.fromEntries(rts.map((r) => [r, []])),
          availability: "borrowable",
          from: s.name,
          fromStation: markOf(s, s.name),
          fromText: t("core-views.models.on_station", { station: s.name }),
          borrow: {
            station: s.station,
            stationName: s.name,
            profile: str(get(p, "id")) ?? "",
            profileName: str(get(p, "name")) ?? "",
            subscription: get(get(p, "access"), "kind") === "subscription",
            // Every station may use it already (its copy not here yet): nothing to ask.
            pending: shared && allow === null,
            allow: shared && Array.isArray(allow) ? allow.filter((x: unknown) => typeof x === "string") : [],
          },
        });
      }
    }
  }
  return out.sort((a, b) => model.compareOrder(model.key(a.model), model.key(b.model)));
}

const isShared = (share: J) => typeof get(share, "id") === "string" && get(share, "role") === "host";
