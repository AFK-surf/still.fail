// What a chat runs on, chosen (choose.rs). A new chat's page (`newChat`): the station it starts on and the model,
// runtime, depth and account it runs there, as last picked on this device (records in the data center's `choice`
// table, each workspace's apart). A model control (`pick`): what a chat, a connect or a new chat runs on now, what is
// picked in its panel until saved, and what that means. Profiles a station has not checked since it started are
// checked once as its overview comes in (a sync task, not a subscription's: rule 6).
import { Effect } from "effect";
import type { Data } from "./data.ts";
import { CoreError } from "./error.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import * as ops from "./ops.ts";
import type { Owner } from "./core/routing.ts";
import { topicKey, type Topic } from "./protocol.ts";
import * as model from "./shapes/model.ts";
import type { Store, Value, Watch } from "./store.ts";
import { arr as arrU, equal, get as getU, isObject } from "./util.ts";
import { borrowable, models, quotaLine, servingIn, sourced } from "./views/models.ts";
import { pendingKeyMade } from "./views/local.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const TABLE = "choice";
/// How many of the models used most a model control's panel keeps nearest what opened it.
const NEAR = 4;
const FIELDS = ["runtime", "model", "effort", "profile", "fast"];

/// What a pick's save does: done here, or a request to the station.
export type Saved = { done: J } | { op: ops.Request };

type Of = { kind: "new" } | { kind: "session"; key: string } | { kind: "connect"; id: string } | { kind: "connectNew"; form: string };

function of(o: string): Of {
  const at = o.indexOf(":");
  if (at < 0) {
    if (o === "new") return { kind: "new" };
    if (o === "connect-new") return { kind: "connectNew", form: "" };
  } else {
    const [head, rest] = [o.slice(0, at), o.slice(at + 1)];
    if (head === "connect-new" && rest !== "") return { kind: "connectNew", form: rest };
    if (head === "session" && rest !== "") return { kind: "session", key: rest };
    if (head === "connect" && rest !== "") return { kind: "connect", id: rest };
  }
  throw CoreError.invalid(t("core-logic.choose.error.no_such", { of: o }));
}

const stationId = (address: string) => address.slice(address.lastIndexOf("/") + 1);
const address = (scope: string, id: string) => `${scope}/${id}`;
const text = (v: J): string | null => (typeof v === "string" && v !== "" ? v : null);

function optionOf(options: J[], m: string | null): J {
  if (m === null || m === "") return undefined;
  return options.find((o) => o.model === m) ?? options.find((o) => arr(o.ids).some((i) => i === m));
}

/// A choice as the station has it now.
export type Resolved = { entry: J; runtime: string | null; effort: string | null; fast: boolean | null; profile: string | null; efforts: J[]; accounts: J[] };

export function resolve(options: J[], choice: J): Resolved {
  const entry = optionOf(options, typeof get(choice, "model") === "string" ? choice.model : null) ?? options[0];
  const runtimes = entry !== undefined ? arr(entry.runtimes) : [];
  const rt = runtimes.find((r) => equal(r, get(choice, "runtime"))) ?? runtimes[0];
  const runtime = typeof rt === "string" ? rt : null;
  const at = (field: string) => (entry !== undefined && runtime !== null ? arr(get(get(entry, field), runtime)) : []);
  let efforts = at("efforts");
  const accounts = at("accounts");
  const p = text(get(choice, "profile"));
  const profile = p !== null && accounts.some((a) => a.id === p) ? p : null;
  const levels = profile !== null ? get(accounts.find((a) => a.id === profile), "efforts") : undefined;
  if (Array.isArray(levels)) efforts = levels;
  const e = text(get(choice, "effort"));
  const effort = e !== null && efforts.some((x) => x === e) ? e : null;
  const fast = typeof get(choice, "fast") === "boolean" && runtime === "codex" ? choice.fast : null;
  return { entry: entry === undefined ? null : entry, runtime, effort, fast, profile, efforts, accounts };
}

function picked(r: Resolved): J {
  return { model: r.entry !== null ? r.entry.model : null, runtime: r.runtime ?? "claude", effort: r.effort, fast: r.fast, profile: r.profile };
}

const comboFast = (v: J): boolean | null => get(v, "runtime") === "codex" && typeof get(v, "fast") === "boolean" ? v.fast : null;

/// Usage stays bounded on the device; ties favour the most recently started chat.
export function recordCombo(history: J[], choice: J, now: number): J[] {
  const same = (v: J) => ["model", "runtime", "effort"].every((f) => text(get(v, f)) === text(get(choice, f))) && comboFast(v) === comboFast(choice);
  const found = history.find(same);
  const count = (typeof get(found, "count") === "number" ? found.count : 0) + 1;
  const out = history.filter((v) => !same(v));
  out.push({ model: get(choice, "model") ?? null, runtime: get(choice, "runtime") ?? null, effort: text(get(choice, "effort")), fast: comboFast(choice), count, last: now });
  out.sort((a, b) => (typeof b.last === "number" ? b.last : 0) - (typeof a.last === "number" ? a.last : 0));
  return out.slice(0, 64);
}

/// Only exact, still runnable combinations are offered: never silently change a remembered depth or runtime.
export function frequentCombos(history: J[], options: J[], current: Resolved): J[] {
  const sorted = [...history].sort(
    (a, b) => (typeof b.count === "number" ? b.count : -1) - (typeof a.count === "number" ? a.count : -1) || (typeof b.last === "number" ? b.last : 0) - (typeof a.last === "number" ? a.last : 0),
  );
  const seen = new Set<string>();
  const out: J[] = [];
  for (const v of sorted) {
    if (out.length >= 4) break;
    const entry = optionOf(options, typeof get(v, "model") === "string" ? v.model : null);
    if (entry === undefined) continue;
    const runtime = get(v, "runtime");
    if (typeof runtime !== "string" || !arr(entry.runtimes).some((r) => r === runtime)) continue;
    const effort = text(get(v, "effort"));
    const fast = comboFast(v);
    const r = resolve(options, { model: entry.model, runtime, effort, fast, profile: current.profile });
    if (r.effort !== effort) continue;
    const m = typeof entry.model === "string" ? entry.model : null;
    if (m === null) continue;
    const key = JSON.stringify([m, runtime, effort, fast]);
    if (seen.has(key)) continue;
    seen.add(key);
    // (the effort as the picker says it; none, the runtime's own)
    const effortText = effort === null ? t("core-logic.choose.default_effort") : format.effortLabel(effort);
    const name = typeof entry.name === "string" ? entry.name : m;
    // the runtime only where the model runs on more than one
    const runtimeText = arr(entry.runtimes).length > 1 ? format.runtimeLabel(runtime) : null;
    const speedText = fast === null ? null : fast ? "Fast" : t("core-logic.choose.speed.standard");
    const baseLabel = runtimeText === null ? `${name} · ${effortText}` : `${name} · ${runtimeText} · ${effortText}`;
    const label = speedText === null ? baseLabel : `${baseLabel} · ${speedText}`;
    const selected = current.entry !== null && current.entry.model === m && current.runtime === runtime && current.effort === effort && current.fast === fast;
    out.push({ model: m, runtime, effort, fast, ...(speedText === null ? {} : { speedText }), label, name, ...(runtimeText === null ? {} : { runtimeText }), effortText, selected });
  }
  return out;
}

export type ChooseEnv = {
  store: Store;
  data: Data;
  now: () => number;
  /// An agent as a chat's view has it (views.ts `agent`).
  agent: (station: string, key: string) => J;
};

export class Choose implements Owner {
  readonly #env: ChooseEnv;
  readonly #watches = new Map<string, { topic: Topic; watches: Watch[] }>();
  readonly #drafts = new Map<string, Record<string, J>>();
  readonly #adding = new Map<string, J>();
  /// The key each scope's next new chat is to be made under (`next`), until one is made under it.
  readonly #next = new Map<string, string>();
  /// The presets of each scope's stations, followed while its new chat page is (docs/presets.md): by station address.
  readonly #presets = new Map<string, Map<string, Watch>>();

  constructor(env: ChooseEnv) {
    this.#env = env;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "newChat" || topic.topic === "pick";
  }

  start(topic: Topic): void {
    let sources: Topic[];
    if (topic.topic === "newChat") sources = [{ topic: "stations", scope: topic.scope }];
    else {
      const station = topic.station as string;
      const overview: Topic = { topic: "overview", station };
      let o: Of | null = null;
      try {
        o = of(topic.of as string);
      } catch {
        o = null;
      }
      // The workspace's stations too: what the others have that this one could borrow.
      const stations: Topic = { topic: "stations", scope: ofAddress(station) };
      sources =
        o?.kind === "session"
          ? [{ topic: "session", station, key: o.key }, { topic: "sessions", station }, { topic: "chatRows", station }, overview, stations]
          : [overview, stations];
    }
    const store = this.#env.store;
    const watches = sources.map((s) => store.watch(s, () => store.invalidate(topic)));
    this.#watches.set(topicKey(topic), { topic, watches });
    store.invalidate(topic);
  }

  stop(topic: Topic): void {
    const live = this.#watches.get(topicKey(topic));
    this.#watches.delete(topicKey(topic));
    this.#drafts.delete(topicKey(topic));
    for (const w of live?.watches ?? []) w.drop();
    if (topic.topic === "newChat") {
      for (const w of this.#presets.get(topic.scope as string)?.values() ?? []) w.drop();
      this.#presets.delete(topic.scope as string);
    }
  }

  compute(topic: Topic): Value | undefined {
    try {
      if (topic.topic === "newChat") return { ok: this.#newChat(topic.scope as string) };
      return this.#pick(topic, topic.station as string, topic.of as string);
    } catch (e) {
      return { err: e as CoreError };
    }
  }

  #changed(): void {
    for (const { topic } of this.#watches.values()) this.#env.store.invalidate(topic);
  }

  // ── a new chat ──

  #record(key: string): J {
    return this.#env.data.record(TABLE, key);
  }

  #choice(scope: string, id: string): J {
    return this.#record(`ws:${scope}:station:${id}`) ?? this.#record(`station:${id}`) ?? {};
  }

  #keepChoice(scope: string, id: string, choice: J, key = `ws:${scope}:station:${id}`): void {
    const kept: J = {};
    for (const f of FIELDS) kept[f] = f === "fast" ? (typeof get(choice, f) === "boolean" ? choice[f] : null) : typeof get(choice, f) === "string" ? choice[f] : "";
    this.#env.data.put(TABLE, key, kept, false);
  }

  #kept(scope: string): string {
    const v = this.#record(`ws:${scope}:last`) ?? this.#record(`scope:${scope}`) ?? this.#record("last");
    return typeof v === "string" ? v : "";
  }

  /// The station the scope's new chats last started on (its id; "" for none).
  keptStation(scope: string): string {
    return this.#kept(scope);
  }

  #keepStation(scope: string, id: string): void {
    this.#env.data.put(TABLE, `ws:${scope}:last`, id, false);
  }

  /// The scope's stations up now; an error (null: not known yet; a string: why it failed).
  #online(scope: string): [J[], boolean] | { error: string | null } {
    const v = this.#env.store.value({ topic: "stations", scope });
    if (v === undefined) return { error: null };
    if ("err" in v) return { error: v.err.message };
    const all = arr(v.ok);
    return [all.filter((s) => s.online === true), all.length > 0];
  }

  /// The station the scope's new chats last started on, as listed, up or not.
  #held(scope: string): J {
    const kept = this.#kept(scope);
    const v = this.#env.store.value({ topic: "stations", scope });
    return kept !== "" && v !== undefined && "ok" in v ? arr(v.ok).find((s) => s.id === kept) : undefined;
  }

  #newChat(scope: string): J {
    const kept = this.#kept(scope);
    const view: J = { kept, next: this.#nextKey(scope), any: false, efforts: [], accounts: [], pickAccount: false, waiting: false, frequent: [] };
    const found = this.#online(scope);
    if (!Array.isArray(found)) {
      view.error = found.error;
      return view;
    }
    const [online, any] = found;
    view.any = any;
    // The station a person picked stays picked while it is down, others up or not: it is said to be down (`down`), what
    // was written in it and what it runs as they were; what is sent waits for it (views/calls.ts `stationBack`). Moving
    // to another station up would start the chat where they did not choose. Only one never picked, or no longer the
    // workspace's, gives way to the first up.
    const held = this.#held(scope);
    const station = structuredClone(held ?? online[0]);
    view.down = held !== undefined && held.online !== true;
    view.stations = view.down ? [...online, station] : online;
    if (station === undefined) return view;
    const id = typeof station.id === "string" ? station.id : "";
    const name = typeof station.name === "string" ? station.name : "";
    const options = arr(station.models);
    const r = resolve(options, this.#choice(scope, id));
    view.frequent = frequentCombos(arr(this.#record(`ws:${scope}:frequent`)), options, r);
    const overview = isObject(station.overview) ? station.overview : null;
    // A station this workspace joined runs its chats on the profiles open to it (docs/multi-workspace.md): with some, but
    // none open, one is turned on rather than added.
    const joined = station.joined === true;
    const all = overview !== null ? arr(overview.profiles) : [];
    const profiles = overview !== null ? arr(servingIn(overview, scope, joined).profiles) : all;
    view.waiting = overview === null;
    // No profile of its own, but another station of the workspace has models it could borrow: its model control
    // offers them (borrowed before the chat is made) rather than only adding a profile.
    const lends = overview !== null && profiles.length === 0 && !joined
      && borrowable(this.#env.store.get({ topic: "stations", scope }), typeof station.station === "string" ? station.station : "", [], null, this.#env.now()).length > 0;
    view.blocked = overview !== null && profiles.length === 0 ? (joined && all.length > 0 ? "shared" : lends ? null : "profile") : overview !== null && options.length === 0 ? "models" : null;
    // This workspace's name: as it is held, else as an account's `/v1/me` lists it.
    const here = get(this.#env.data.shared({ topic: "workspace", workspace: scope }), "name")
      ?? this.#env.data.mes().flatMap(([, me]) => arr(get(me, "workspaces"))).find((w) => get(w, "id") === scope)?.name;
    const notShared = () => typeof station.home === "string" && station.home !== ""
      ? t("core-logic.choose.problem.not_shared", { name, home: station.home, workspace: typeof here === "string" ? here : "" })
      : t("core-logic.choose.problem.not_shared_elsewhere", { name, workspace: typeof here === "string" ? here : "" });
    view.problem = overview === null ? t("core-logic.choose.problem.loading", { name })
      : lends ? t("core-logic.choose.problem.borrow_only", { name })
      : view.blocked === "shared" ? notShared()
      : profiles.length > 0 && options.length === 0 ? t("core-logic.choose.problem.no_models") : null;
    if (r.entry !== null && isObject(r.entry.spent)) {
      const n = typeof r.entry.name === "string" ? r.entry.name : "";
      const back = text(r.entry.spent.back);
      view.spent = back !== null ? t("core-logic.choose.spent.back", { name: n, back }) : t("core-logic.choose.spent", { name: n });
    }
    view.pickAccount = r.accounts.length > 1;
    view.model = r.entry;
    view.runtime = r.runtime;
    view.effort = r.effort;
    view.fast = r.fast;
    view.profile = r.profile;
    view.efforts = r.efforts;
    view.accounts = r.accounts;
    const addr = typeof station.station === "string" ? station.station : "";
    const pick = this.#pick({ topic: "pick", station: addr, of: "new" }, addr, "new");
    view.pick = pick !== undefined && "ok" in pick ? pick.ok : null;
    // The workspace's presets, every station's up now (each as it was read last), to pick from where the page's
    // control opens; the one picked whichever station it is of.
    const listed = this.#workspacePresets(scope, online);
    view.presets = listed.map(({ p, station: at, stationName }) => ({ id: text(get(p, "id")) ?? "", name: text(get(p, "name")) ?? "", dirs: arr(get(p, "dirs")).length, station: at, stationName, marks: this.#marks(p, at) }));
    const picked = this.#picked(scope, listed);
    view.preset = picked === undefined ? "" : (text(get(picked.p, "id")) ?? "");
    view.presetStation = picked?.station ?? "";
    view.presetName = picked === undefined ? "" : (text(get(picked.p, "name")) ?? "");
    view.presetMarks = picked === undefined ? [] : this.#marks(picked.p, picked.station);
    view.station = station;
    return view;
  }

  #onStation(addr: string): [J[], Resolved] {
    const overview = this.#env.store.get({ topic: "overview", station: addr });
    const options = models(overview, this.#env.now());
    return [options, resolve(options, this.#choice(ofAddress(addr), stationId(addr)))];
  }

  /// The presets of the scope's stations `online` (their addresses' `presets` topics), followed while its page is: as
  /// each station said them last, with the station each is of.
  #workspacePresets(scope: string, online: J[], follow = true): { p: J; station: string; stationName: string }[] {
    const page: Topic = { topic: "newChat", scope };
    const held = this.#presets.get(scope) ?? new Map<string, Watch>();
    if (follow) this.#presets.set(scope, held);
    const out: { p: J; station: string; stationName: string }[] = [];
    for (const s of online) {
      const at = typeof s.station === "string" ? s.station : "";
      if (at === "") continue;
      const topic: Topic = { topic: "presets", station: at };
      if (follow && !held.has(at)) held.set(at, this.#env.store.watch(topic, () => this.#env.store.invalidate(page)));
      for (const p of arr(get(this.#env.store.get(topic), "presets"))) out.push({ p, station: at, stationName: typeof s.name === "string" ? s.name : "" });
    }
    return out;
  }

  /// What preset `p` of station `at` is shown by: its first folders' marks (each its name, its repository, its own
  /// picture as its station found it), three at most.
  #marks(p: J, at: string): J[] {
    const offered = arr(get(this.#env.store.get({ topic: "presets", station: at }), "candidates"));
    return arr(get(p, "dirs"))
      .slice(0, 3)
      .map((d) => {
        const path = text(get(d, "path")) ?? "";
        const repo = text(get(d, "repo"));
        const found = offered.find((o) => get(o, "path") === path || (repo !== null && get(o, "repo") === repo));
        const name = text(get(found, "name")) ?? path.split("/").filter((x) => x !== "").pop() ?? path;
        const icon = text(get(found, "icon"));
        return { name, repo: repo ?? "", ...(icon !== null ? { icon } : {}) };
      });
  }

  /// The preset the scope's new chats are opened with, as last picked on this device, among those `listed`; none for
  /// none picked, or one no station has (as their presets were read last).
  #picked(scope: string, listed: { p: J; station: string; stationName: string }[]): { p: J; station: string; stationName: string } | undefined {
    const kept = this.#record(`ws:${scope}:preset`);
    if (!isObject(kept) || typeof kept.id !== "string" || kept.id === "") return undefined;
    return listed.find((x) => x.station === kept.station && get(x.p, "id") === kept.id);
  }

  /// The station the scope's new chat page is on: the one picked, up or not, else the first up (its id).
  #shown(scope: string): string {
    const found = this.#online(scope);
    if (!Array.isArray(found)) throw CoreError.invalid(t("core-logic.choose.error.no_stations_yet"));
    const current = this.#held(scope) ?? found[0][0];
    if (current === undefined) throw CoreError.invalid(t("core-logic.choose.error.none_online"));
    return typeof current.id === "string" ? current.id : "";
  }

  /// `newChat.pick`: the station a scope's new chat starts on, and what it runs there.
  pickNew(scope: string, params: J): void {
    const station = text(get(params, "station"));
    if (station !== null) this.#keepStation(scope, station);
    // the preset, whichever station it is of (`presetStation`, its address; "" for none)
    const preset = get(params, "preset");
    if (typeof preset === "string") this.#env.data.put(TABLE, `ws:${scope}:preset`, { id: preset, station: text(get(params, "presetStation")) ?? "" }, false);
    if (FIELDS.some((f) => get(params, f) !== undefined)) {
      const id = station ?? this.#shown(scope);
      const [options, now] = this.#onStation(address(scope, id));
      const next: J = { runtime: now.runtime, model: now.entry !== null ? now.entry.model : null, effort: now.effort, fast: now.fast, profile: now.profile };
      const m = text(get(params, "model"));
      if (m !== null) {
        const runs = arr(get(optionOf(options, m), "runtimes"));
        if (get(params, "runtime") === undefined && !runs.some((r) => equal(r, next.runtime))) {
          next.runtime = runs[0] ?? null;
          next.effort = null;
        }
        next.model = m;
      }
      const rt = text(get(params, "runtime"));
      if (rt !== null) {
        if (next.runtime !== rt) next.effort = null;
        next.runtime = rt;
      }
      for (const field of ["effort", "profile", "fast"]) if (get(params, field) !== undefined) next[field] = params[field];
      this.#keepChoice(scope, id, next);
    }
    this.#changed();
  }

  /// `newChat.create`: what a new chat on `station` is asked to be made with, as picked there.
  create(station: string): J {
    const [, r] = this.#onStation(station);
    if (r.entry === null || r.runtime === null) throw CoreError.invalid(t("core-logic.choose.error.enable_models"));
    const ask: J = { runtime: r.runtime, model: r.entry.model ?? null };
    if (r.effort !== null) ask.effort = r.effort;
    if (r.profile !== null) ask.profile = r.profile;
    if (r.fast !== null) ask.fast = r.fast;
    // The preset picked: by its id where it is this station's, else all of it as its station said it (its folders
    // that station's).
    const scope = ofAddress(station);
    const online = (() => {
      const v = this.#env.store.value({ topic: "stations", scope });
      return v !== undefined && "ok" in v ? arr(v.ok) : [];
    })();
    const picked = this.#picked(scope, this.#workspacePresets(scope, online, false));
    if (picked !== undefined) {
      if (picked.station === station) ask.preset = get(picked.p, "id");
      else {
        // each folder where it is: this station's as they are, another's said to be there (by its name)
        const names = new Map(online.map((s) => [typeof s.station === "string" ? s.station : "", typeof s.name === "string" ? s.name : ""]));
        const dirs = arr(get(picked.p, "dirs")).map((d) => {
          const at = text(get(d, "station")) ?? picked.station;
          const dir: J = { path: get(d, "path"), repo: get(d, "repo") ?? null };
          if (at !== station) dir.elsewhere = text(get(d, "stationName")) ?? names.get(at) ?? at;
          return dir;
        });
        ask.presetCopy = { id: get(picked.p, "id"), name: get(picked.p, "name"), dirs, instructions: get(picked.p, "instructions") ?? "" };
      }
    }
    this.#keepStation(ofAddress(station), stationId(station));
    this.#changed();
    return ask;
  }

  /// The key scope `scope`'s next new chat is to be made under: what its page becomes as its first words are sent,
  /// before the core has made it (`newChat.create` `key`), the same until a chat is made under it.
  #nextKey(scope: string): string {
    let key = this.#next.get(scope);
    if (key === undefined) {
      key = pendingKeyMade();
      this.#next.set(scope, key);
    }
    return key;
  }

  /// A chat made under `key`: its scope's next new chat under another.
  taken(key: string): void {
    for (const [scope, next] of this.#next) if (next === key) this.#next.delete(scope);
    this.#changed();
  }

  /// A new chat accepted by the core.
  used(station: string, choice: J): void {
    const key = `ws:${ofAddress(station)}:frequent`;
    this.#env.data.put(TABLE, key, recordCombo(arr(this.#record(key)), choice, this.#env.now()), false);
    this.#keepUsual(ofAddress(station), choice);
    this.#changed();
  }

  /// `newChat.migrate`: what a client kept before the core did, each taken only where the core keeps nothing yet.
  migrate(params: J): void {
    const choices = get(params, "choices");
    if (isObject(choices)) {
      for (const [id, choice] of Object.entries(choices)) if (isObject(choice) && this.#record(`station:${id}`) === undefined) this.#keepChoice("", id, choice, `station:${id}`);
    }
    const lastIn = get(params, "lastIn");
    if (isObject(lastIn)) {
      for (const [scope, id] of Object.entries(lastIn)) if (typeof id === "string" && this.#record(`scope:${scope}`) === undefined) this.#env.data.put(TABLE, `scope:${scope}`, id, false);
    }
    const last = text(get(params, "last"));
    if (last !== null && this.#record("last") === undefined) this.#env.data.put(TABLE, "last", last, false);
    this.#changed();
  }

  // ── a model control ──

  /// What a control runs on now: its options, its value, the account it is on, whether its runtime is fixed, whether it
  /// names its account only when asked to, and how many accounts could run it (a chat's: its runtime's with its model).
  #now(station: string, o: Of): [J[], J, J, boolean, boolean, number] | undefined {
    const overview = () => this.#env.store.get({ topic: "overview", station });
    const now = this.#env.now();
    switch (o.kind) {
      case "new": {
        const [options, r] = this.#onStation(station);
        if (overview() === undefined) return undefined;
        return [options, picked(r), null, false, true, 0];
      }
      case "connectNew": {
        const ov = overview();
        if (ov === undefined) return undefined;
        const options = models(ov, now);
        const r = resolve(options, this.#adding.get(`${station}\u0001${o.form}`) ?? {});
        return [options, picked(r), null, false, false, 0];
      }
      case "connect": {
        const ov = overview();
        if (ov === undefined) return undefined;
        const connect = arr(get(ov, "connects")).find((c) => c.id === o.id);
        if (connect === undefined) throw new CoreError("http_404", t("core-logic.choose.error.no_connect"), 404);
        const bind = connect.bind;
        const options = models(ov, now).filter((m) => arr(m.runtimes).some((r) => equal(r, get(bind, "runtime"))));
        return [options, { model: text(get(bind, "model")), runtime: get(bind, "runtime") ?? null, effort: text(get(bind, "effort")), profile: text(get(bind, "profile")) }, null, true, false, 0];
      }
      case "session": {
        const agent = this.#env.agent(station, o.key);
        if (agent === null || agent === undefined) return undefined;
        const s = agent.session;
        const pinned = get(s, "profilePinned") === true;
        const value = { model: text(get(s, "model")), runtime: get(s, "runtime") ?? null, effort: text(get(s, "effort")), fast: get(s, "fast") ?? null, profile: pinned ? text(get(s, "profile")) : null };
        const current = isObject(agent.account) ? agent.account : null;
        return [arr(agent.choices), value, current, true, false, arr(agent.profiles).length];
      }
    }
  }

  /// What a station's own options are, said where their accounts are, and the models the workspace's other stations
  /// could lend it after them (of `runtime` alone where it cannot change).
  #withWorkspace(station: string, own: J[], runtime: string | null): J[] {
    const stations = this.#env.store.get({ topic: "stations", scope: ofAddress(station) });
    const overview = this.#env.store.get({ topic: "overview", station });
    return [...sourced(own, overview, stations), ...borrowable(stations, station, own, runtime, this.#env.now())];
  }

  /// Whether the viewer may have another station share a profile with this one (docs/station-share.md: managers).
  #manages(station: string): boolean {
    const role = get(this.#env.data.shared({ topic: "workspace", workspace: ofAddress(station) }), "role");
    return role === "owner" || role === "admin";
  }

  /// What borrowing a model's account says before it is done (the second confirmation, PickBorrow).
  #borrowView(station: string, option: J): J {
    const b = option.borrow;
    const name = typeof option.name === "string" ? option.name : String(option.model);
    const vars = { station: b.stationName, account: b.profileName, model: name };
    const allowed = this.#manages(station);
    return {
      note: t("core-logic.choose.borrow.note", vars),
      title: t("core-logic.choose.borrow.title", vars),
      lines: [
        t("core-logic.choose.borrow.body", vars),
        t(b.subscription ? "core-logic.choose.borrow.subscription" : "core-logic.choose.borrow.key", vars),
        t("core-logic.choose.borrow.environment"),
      ],
      action: t("core-logic.choose.borrow.action"),
      allowed: allowed && b.pending !== true,
      why: b.pending === true ? t("core-logic.choose.borrow.pending", vars) : allowed ? null : t("core-logic.choose.borrow.managers"),
    };
  }

  #pick(topic: Topic, station: string, oName: string): Value | undefined {
    const o = of(oName);
    const now = this.#now(station, o);
    if (now === undefined) return undefined;
    const [own, value, current, fixed, quiet, runnable] = now;
    const options = this.#withWorkspace(station, own, fixed && typeof value.runtime === "string" ? value.runtime : null);
    const draft = this.#drafts.get(topicKey(topic)) ?? {};
    const pickedOf = (field: string) => text(field in draft ? draft[field] : get(value, field));
    const m = pickedOf("model");
    const runtime = pickedOf("runtime");
    const profileDrafted = pickedOf("profile");
    const option = optionOf(options, m);
    const valueOption = optionOf(options, typeof value.model === "string" ? value.model : null);
    const runtimes = option !== undefined ? arr(option.runtimes) : [];
    const on = fixed ? value.runtime : (runtimes.find((r) => r === runtime) ?? runtimes[0] ?? value.runtime);
    const onName = typeof on === "string" ? on : "";
    const accounts = option !== undefined ? arr(get(get(option, "accounts"), onName)) : [];
    let efforts: J[] = option !== undefined ? arr(get(get(option, "efforts"), onName)) : fixed ? format.efforts(onName) : [];
    const account = (id: string | null) => (id === null ? undefined : accounts.find((a) => a.id === id));
    const profile = account(profileDrafted)?.id ?? null;
    const levels = profile !== null ? get(accounts.find((a) => a.id === profile), "efforts") : undefined;
    if (Array.isArray(levels)) efforts = levels;
    const dropped = profileDrafted !== null && profile === null;
    const e = pickedOf("effort");
    const effort = e !== null && efforts.some((x) => x === e) ? e : null;
    const nextModel = option !== undefined && (valueOption === undefined || valueOption.model !== option.model) ? option.model : (value.model ?? null);
    const overview = this.#env.store.get({ topic: "overview", station });
    const fastAvailable =
      onName === "codex" &&
      (o.kind === "new" || o.kind === "session") &&
      arr(get(overview, "profiles")).some((p) => typeof p.fast === "boolean" && (profile === null || p.id === profile) && accounts.some((a) => a.id === p.id));
    const fastRaw = "fast" in draft ? draft.fast : get(value, "fast");
    const fast = typeof fastRaw === "boolean" && onName === "codex" ? fastRaw : null;
    const speedText = (f: boolean | null) => (f === true ? "Fast" : f === false ? t("core-logic.choose.speed.standard") : t("core-logic.choose.speed.plan"));
    const next = { model: nextModel, runtime: on ?? null, effort, profile, fast };
    const changed = FIELDS.some((f) => !equal((next as J)[f], value[f] ?? null));
    const kept = text(get(value, "profile"));
    let shown: J = null;
    if (kept !== null && valueOption !== undefined) shown = arr(get(get(valueOption, "accounts"), typeof value.runtime === "string" ? value.runtime : "")).find((a) => a.id === kept) ?? null;
    if (shown === null) shown = current;
    const effectiveFast =
      value.runtime === "codex" &&
      (o.kind === "new" || o.kind === "session") &&
      (typeof value.fast === "boolean"
        ? value.fast
        : (() => {
            const id = kept ?? (typeof get(current, "id") === "string" ? current.id : null);
            return arr(get(overview, "profiles")).some((p) => id !== null && p.id === id && p.fast === true);
          })());
    const low = shown !== null ? (get(quotaLine(get(shown, "quota")), "level") ?? null) : null;
    const names = !quiet || kept !== null || low !== null;
    let accountView: J = null;
    if (names) {
      const txt =
        kept !== null
          ? shown !== null
            ? typeof shown.name === "string"
              ? shown.name
              : kept
            : kept
          : shown !== null
            ? t("core-logic.choose.account.auto_on", { name: typeof shown.name === "string" ? shown.name : "" })
            : t("core-logic.choose.account.auto");
      accountView = { text: txt, auto: kept === null, level: low, profile: quiet ? null : shown };
    }
    const drafted = account(profile);
    const who = drafted !== undefined && typeof drafted.name === "string" ? drafted.name.split("@")[0] : t("core-logic.choose.account");
    const whoLevel = dropped ? "amber" : profile === null && kept === null ? low : null;
    const currentName = typeof get(current, "name") === "string" ? current.name : "";
    const autoNote = current !== null && kept === null ? t("core-logic.choose.account.now", { name: currentName }) : t("core-logic.choose.account.auto_note");
    // A chat's account picked again now (`pick.repick`), beside 自动: when another could take it.
    const repick = current !== null && runnable > 1 ? t("core-logic.choose.account.repick") : null;
    const optionName = option !== undefined && typeof option.name === "string" ? option.name : null;
    const nameOf = (x: string | null): string | null => {
      if (x === null) return null;
      if (x === value.model) return model.name(x);
      const found = optionOf(options, x);
      return found !== undefined && typeof found.name === "string" ? found.name : x;
    };
    const accountText = (id: string | null) => (id === null ? t("core-logic.choose.account.auto") : (account(id)?.name ?? id));
    const onCurrent = current !== null && accounts.some((a) => equal(a.id, current.id));
    const movesOff = profile === null && kept === null && m !== null && current !== null && !onCurrent;
    const modelName = nameOf(m);
    const effortText = effort ?? t("core-logic.choose.default_effort");
    const chosenText = accountText(profile);
    const was = [
      nameOf(typeof value.model === "string" ? value.model : null) ?? t("core-logic.format.default_model"),
      text(get(value, "effort")) ?? t("core-logic.choose.default_effort"),
      kept !== null ? currentName : t("core-logic.choose.account.auto_on", { name: currentName }),
    ];
    const becomes = [
      modelName ?? t("core-logic.format.default_model"),
      effortText,
      profile !== null
        ? chosenText
        : movesOff
          ? t("core-logic.choose.account.auto_switch")
          : onCurrent
            ? t("core-logic.choose.account.auto_on", { name: currentName })
            : t("core-logic.choose.account.auto"),
    ];
    if (fastAvailable) {
      was.push(speedText(typeof value.fast === "boolean" ? value.fast : null));
      becomes.push(speedText(fast));
    }
    const force = dropped
      ? t("core-logic.choose.force.dropped", { account: accountText(profileDrafted), model: modelName ?? "" })
      : movesOff
        ? t("core-logic.choose.force.moves_off", { account: currentName, model: modelName ?? "" })
        : null;
    const borrow = option !== undefined && option.availability === "borrowable" ? this.#borrowView(station, option) : null;
    // Each model as it would run picked in the panel (`usual`: what it last ran with here, the one picked as it is
    // drafted now) and how often new chats here started on it (`uses`); the few used most, nearest what opened the
    // panel (`near`): a chat's or a new chat's, of the station's own models.
    const scope = ofAddress(station);
    const history = arr(this.#record(`ws:${scope}:frequent`));
    const uses = new Map<string, number>();
    for (const h of history) {
      const found = optionOf(options, text(get(h, "model")));
      if (found !== undefined) uses.set(found.model, (uses.get(found.model) ?? 0) + (typeof h.count === "number" ? h.count : 1));
    }
    const annotated = options.map((opt: J) => {
      const id = typeof opt.model === "string" ? opt.model : "";
      const ran = id === m ? { runtime: on ?? null, effort, fast } : this.#usual(scope, id, history);
      const r = ran === undefined ? null : resolve(options, { model: id, runtime: fixed ? value.runtime : ran.runtime, effort: ran.effort, fast: ran.fast });
      const parts: string[] = [];
      if (r !== null) {
        if (!fixed && arr(opt.runtimes).length > 1 && r.runtime !== null) parts.push(format.runtimeLabel(r.runtime));
        if (r.effort !== null) parts.push(format.effortLabel(r.effort));
        if (r.fast === true) parts.push("Fast");
      }
      const usual = r === null ? null : { runtime: r.runtime, effort: r.effort, fast: r.fast };
      return { ...opt, usual, usualText: parts.length > 0 ? parts.join(" · ") : null, uses: uses.get(id) ?? 0 };
    });
    const near = o.kind === "new" || o.kind === "session"
      ? annotated.filter((x: J) => x.uses > 0 && x.availability !== "borrowable").sort((a: J, b: J) => b.uses - a.uses).slice(0, NEAR).map((x: J) => x.model)
      : [];
    let saveText = changed ? t("core-logic.choose.save", { model: modelName ?? t("core-logic.format.default_model"), effort: effortText, account: chosenText }) : t("core-logic.choose.save.unchanged");
    if (changed && fastAvailable) saveText = `${saveText} · ${speedText(fast)}`;
    return {
      ok: {
        fastAvailable,
        fastText: effectiveFast ? "Fast" : null,
        options: annotated,
        near,
        runtimeFixed: fixed,
        value,
        valueOption: valueOption ?? null,
        account: accountView,
        draft: { model: m, runtime: on ?? null, effort, profile, fast },
        option: option !== undefined ? (option.model ?? null) : null,
        runtimes: !fixed && runtimes.length > 1 ? runtimes : [],
        efforts,
        accounts,
        dropped: dropped ? t("core-logic.choose.dropped", { model: optionName ?? (typeof next.model === "string" ? next.model : "") }) : null,
        who,
        whoLevel,
        autoNote,
        repick,
        changed,
        was,
        becomes,
        force,
        modelText: modelName ?? t("core-logic.choose.pick_model"),
        maker: option !== undefined ? (option.maker ?? null) : null,
        accountText: chosenText,
        accountNote: profile === null ? t("core-logic.choose.account.auto_note") : t("core-logic.choose.account.fixed"),
        accountWarn: dropped || movesOff,
        saveText,
        next,
        borrow,
      },
    };
  }

  /// `pick.set`: picks in a control's panel. `open`: from what it runs on now again; `clear`: starts over too.
  set(station: string, oName: string, params: J): void {
    const o = of(oName);
    const key = topicKey({ topic: "pick", station, of: oName });
    if (get(params, "clear") === true && o.kind === "connectNew") this.#adding.delete(`${station}\u0001${o.form}`);
    if (get(params, "open") === true || get(params, "clear") === true) this.#drafts.delete(key);
    const fields = FIELDS.filter((f) => get(params, f) !== undefined);
    if (fields.length > 0) {
      const draft = this.#drafts.get(key) ?? {};
      for (const f of fields) draft[f] = params[f];
      this.#drafts.set(key, draft);
    }
    this.#changed();
  }

  /// What model `model` last ran with here (`ws:<scope>:usual:<model>`, kept as it is saved and as a new chat starts on
  /// it), else as the newest new chat on it started; none, never used here.
  #usual(scope: string, model: string, history: J[]): J {
    const kept = this.#record(`ws:${scope}:usual:${model}`);
    if (isObject(kept)) return kept;
    let newest: J;
    for (const h of history) if (get(h, "model") === model && (newest === undefined || (h.last ?? 0) > (newest.last ?? 0))) newest = h;
    return newest === undefined ? undefined : { runtime: newest.runtime ?? null, effort: text(newest.effort), fast: comboFast(newest) };
  }

  #keepUsual(scope: string, choice: J): void {
    const model = text(get(choice, "model"));
    if (model === null) return;
    this.#env.data.put(TABLE, `ws:${scope}:usual:${model}`, { runtime: get(choice, "runtime") ?? null, effort: text(get(choice, "effort")), fast: typeof get(choice, "fast") === "boolean" ? choice.fast : null }, false);
  }

  /// `pick.save`: what the panel picked, made what it runs on; with picks of its own (a frequent combination's), those
  /// picked first.
  save(station: string, oName: string, params: J = {}): Saved {
    const o = of(oName);
    if (FIELDS.some((f) => get(params, f) !== undefined)) this.set(station, oName, Object.fromEntries(FIELDS.filter((f) => get(params, f) !== undefined).map((f) => [f, params[f]])));
    const topic: Topic = { topic: "pick", station, of: oName };
    const view = this.#pick(topic, station, oName);
    if (view === undefined) throw CoreError.invalid(t("core-logic.choose.error.no_options_yet"));
    if ("err" in view) throw view.err;
    const v = view.ok as J;
    const next = v.next;
    // Not run here till its account is borrowed (`pick.borrow`).
    if (v.borrow !== null && v.borrow !== undefined) throw CoreError.invalid(t("core-logic.choose.borrow.first"));
    if (v.changed !== true || v.option === null) {
      this.#drafts.delete(topicKey(topic));
      this.#env.store.invalidate(topic);
      return { done: { saved: false } };
    }
    const textOf = (field: string) => (typeof next[field] === "string" ? next[field] : "");
    if (o.kind === "new" || o.kind === "session") this.#keepUsual(ofAddress(station), next);
    let saved: Saved;
    switch (o.kind) {
      case "new":
        this.pickNew(ofAddress(station), { station: stationId(station), model: next.model, runtime: next.runtime, effort: textOf("effort"), profile: textOf("profile"), fast: next.fast });
        saved = { done: { saved: true } };
        break;
      case "connectNew":
        this.#adding.set(`${station}\u0001${o.form}`, next);
        saved = { done: { saved: true } };
        break;
      case "session": {
        const params: J = { station, key: o.key, model: next.model, effort: next.effort, profile: next.profile };
        if (v.fastAvailable === true) params.fast = next.fast;
        const op = ops.request("session.settings", params);
        if (op === null) throw CoreError.invalid("session.settings");
        saved = { op };
        break;
      }
      case "connect": {
        const op = ops.request("connect.put", { station, id: o.id, input: { bind: { model: next.model, effort: textOf("effort"), profile: next.profile } } });
        if (op === null) throw CoreError.invalid("connect.put");
        saved = { op };
        break;
      }
    }
    // (one asked of the station: what was picked shown until it is answered, the panel open as it is; dropped if it
    // fails, `unsaved`)
    if ("done" in saved) this.#drafts.delete(topicKey(topic));
    this.#changed();
    return saved;
  }

  /// A pick asked of the station that failed: the panel back to what it runs on.
  unsaved(station: string, oName: string): void {
    this.#drafts.delete(topicKey({ topic: "pick", station, of: oName }));
    this.#changed();
  }

  /// `pick.repick`: a chat's account given back to the station and picked again now, as a new chat's would be (the
  /// account drafted in its panel gives way; its other picks stay drafted). The request, and what its answer says: the
  /// account picked, the one it was on or another.
  repick(station: string, oName: string): [ops.Request, (answer: J) => J] {
    const o = of(oName);
    const topic: Topic = { topic: "pick", station, of: oName };
    const view = this.#pick(topic, station, oName);
    if (view === undefined) throw CoreError.invalid(t("core-logic.choose.error.no_options_yet"));
    if ("err" in view) throw view.err;
    const v = view.ok as J;
    if (o.kind !== "session" || v.repick === null) throw CoreError.invalid(t("core-logic.choose.repick.none"));
    const op = ops.request("session.settings", { station, key: o.key, profile: null, repick: true });
    if (op === null) throw CoreError.invalid("session.settings");
    const agent = this.#env.agent(station, o.key);
    const was = get(get(agent, "account"), "id");
    const names = new Map(arr(get(agent, "profiles")).map((p) => [p.id, typeof p.name === "string" ? p.name : p.id]));
    const draft = this.#drafts.get(topicKey(topic));
    if (draft !== undefined && "profile" in draft) {
      delete draft.profile;
      this.#changed();
    }
    const said = (answer: J): J => {
      const id = text(get(answer, "profile"));
      // A station from before picking again: given back to it, nothing said.
      if (id === null) return { profile: null, said: null };
      return { profile: id, said: t(id === was ? "core-logic.choose.repick.same" : "core-logic.choose.repick.moved", { name: names.get(id) ?? id }) };
    };
    return [op, said];
  }

  /// `pick.borrow`: the station that has the picked model's account shares its profile with this one (its allow list
  /// with this station added), asked of that station; the copy comes here as any share does, and the model with it.
  borrow(station: string, oName: string): ops.Request {
    const view = this.#pick({ topic: "pick", station, of: oName }, station, oName);
    if (view === undefined) throw CoreError.invalid(t("core-logic.choose.error.no_options_yet"));
    if ("err" in view) throw view.err;
    const v = view.ok as J;
    const option = optionOf(arr(v.options), text(v.option));
    const b = get(option, "borrow");
    if (!isObject(b) || v.borrow === null) throw CoreError.invalid(t("core-logic.choose.borrow.nothing"));
    if (v.borrow.allowed !== true) throw CoreError.invalid(v.borrow.why ?? t("core-logic.choose.borrow.managers"));
    const allow = [...new Set([...arr(b.allow), stationId(station)])];
    const op = ops.request("profile.share", { station: b.station, id: b.profile, on: true, allow });
    if (op === null) throw CoreError.invalid("profile.share");
    return op;
  }

  /// What a connect being added will run on (connect_flow.rs).
  adding(station: string, form: string): J {
    return this.#adding.get(`${station}\u0001${form}`);
  }
}

export { Effect };
