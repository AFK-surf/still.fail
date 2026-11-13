// What a chat runs on, chosen. A new chat's page (`newChat`): the station it starts on and the model,
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
import { Marks } from "./reactive.ts";
import type { Store, Value } from "./store.ts";
import { arr as arrU, equal, get as getU, isObject } from "./util.ts";
import { borrowable, effortDefault, lends, models, quotaLine, servingIn, sourced, subsetEfforts } from "./views/models.ts";
import { profileServes } from "./views/profile-scope.ts";
import { pendingKeyMade } from "./views/local.ts";
import { work } from "./work.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const TABLE = "choice";
/// How many of the combinations used most a model control's panel keeps nearest what opened it.
const NEAR = 4;
const FIELDS = ["runtime", "model", "effort", "profile", "profiles", "fast", "context"];
/// How a model runs, apart from who runs it: what is set by hand in a control's panel (`Choose`'s `#hand`).
const HOW = ["runtime", "effort", "fast", "context"];

const normProfiles = (v: unknown): string[] | null => {
  if (!Array.isArray(v)) return null;
  const ids = [...new Set(v.filter((x): x is string => typeof x === "string" && x !== ""))];
  return ids.length > 0 ? ids : null;
};

/// The most context picked (views/models.ts `contextSteps`), as a client says it: tokens, as a number or its digits;
/// anything else (null, "") the model's whole window.
const contextOf = (v: J): number | null => {
  const n = typeof v === "string" && /^[0-9]+$/.test(v) ? Number(v) : v;
  return typeof n === "number" && Number.isInteger(n) && n > 0 ? n : null;
};

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

/// A model's whole window as a model control offers it: 完整 · 1M (just 完整 where its window is not known).
const wholeWindow = (option: J): string =>
  typeof get(option, "contextWindow") === "number" ? t("core-logic.choose.context.whole_of", { window: format.compactNumber(option.contextWindow) }) : t("core-logic.choose.context.whole");

function optionOf(options: J[], m: string | null): J {
  if (m === null || m === "") return undefined;
  return options.find((o) => o.model === m) ?? options.find((o) => arr(o.ids).some((i) => i === m));
}

/// Legacy Antigravity ACP tiered model IDs (`gemini-4-carbon-high`, `claude-opus-5-5-medium`, `gpt-oss-120b-medium`)
/// matched against a normalized station's base `agy` options when the tiered ID itself is no longer listed.
function matchTiered(options: J[], m: string | null): { entry: J; effort: string } | null {
  if (m === null || m === "") return null;
  if (optionOf(options, m) !== undefined) return null;
  const split = model.splitAgyTier(m);
  if (split === null) return null;
  const entry = optionOf(options, split.model) ?? options.find((o) => typeof o.model === "string" && model.same(o.model, split.model));
  if (entry === undefined || !arr(entry.runtimes).includes("agy")) return null;
  return { entry, effort: split.effort };
}

function normalizeTieredValue(options: J[], value: J): void {
  if (value.runtime !== "agy" || typeof value.model !== "string") return;
  const tiered = matchTiered(options, value.model);
  if (tiered === null) return;
  value.model = tiered.entry.model;
  if (value.effort === null) {
    const levels = arr(get(get(tiered.entry, "efforts"), "agy"));
    if (levels.includes(tiered.effort)) value.effort = tiered.effort;
  }
}

/// The runtimes a chat can be set to Fast on (Codex on an OpenAI subscription, Claude Code on an Anthropic key: the
/// station's takesFast); the accounts that take it say so with their overview's `fast`.
const fastRuntime = (runtime: unknown): boolean => runtime === "codex" || runtime === "claude";

function choiceAccounts(choice: J): { asked: string[]; multi: boolean } {
  if (isObject(choice) && "profiles" in choice) {
    const ps = normProfiles(choice.profiles);
    if (ps !== null) return { asked: ps, multi: true };
    if (choice.profiles === null && text(get(choice, "profile")) === null) return { asked: [], multi: false };
  }
  const p = text(get(choice, "profile"));
  return { asked: p !== null ? [p] : [], multi: false };
}

function resolveAccounts(accounts: J[], asked: string[], multi: boolean): { profile: string | null; profiles: string[] | null; dropped: boolean } {
  if (asked.length === 0) return { profile: null, profiles: null, dropped: false };
  const matched = accounts.map((a) => a.id).filter((id): id is string => typeof id === "string" && asked.includes(id));
  if (matched.length === 0) return { profile: null, profiles: null, dropped: true };
  if (multi && accounts.length > 1 && matched.length === accounts.length) return { profile: null, profiles: null, dropped: false };
  if (matched.length === 1) return { profile: matched[0]!, profiles: null, dropped: false };
  return { profile: null, profiles: matched, dropped: false };
}

/// A choice as the station has it now.
export type Resolved = { entry: J; runtime: string | null; effort: string | null; fast: boolean | null; context: number | null; profile: string | null; profiles: string[] | null; efforts: J[]; contexts: number[]; accounts: J[] };

export function resolve(options: J[], choice: J, subsets = true): Resolved {
  const rawModel = typeof get(choice, "model") === "string" ? choice.model : null;
  const rawRt = get(choice, "runtime");
  const tiered = rawRt === "agy" || rawRt === undefined || rawRt === "" || rawRt === null ? matchTiered(options, rawModel) : null;
  const entry = (tiered !== null ? tiered.entry : optionOf(options, rawModel)) ?? options[0];
  const runtimes = entry !== undefined ? arr(entry.runtimes) : [];
  const rt = runtimes.find((r) => equal(r, get(choice, "runtime"))) ?? runtimes[0];
  const runtime = typeof rt === "string" ? rt : null;
  const at = (field: string) => (entry !== undefined && runtime !== null ? arr(get(get(entry, field), runtime)) : []);
  let efforts = at("efforts");
  const accounts = at("accounts");
  const { asked, multi } = choiceAccounts(choice);
  let { profile, profiles } = resolveAccounts(accounts, asked, multi);
  if (!subsets && profiles !== null) {
    profile = profiles[0] ?? null;
    profiles = null;
  }
  if (profile !== null) {
    const levels = get(accounts.find((a) => a.id === profile), "efforts");
    if (Array.isArray(levels)) efforts = levels;
  } else if (profiles !== null && runtime !== null) {
    const subset = accounts.filter((a) => profiles.includes(a.id));
    if (subset.length > 0) efforts = subsetEfforts(subset, runtime);
  }
  const e = text(get(choice, "effort")) ?? (tiered !== null && runtime === "agy" ? tiered.effort : null);
  const effort = e !== null && efforts.some((x) => x === e) ? e : null;
  const fast = typeof get(choice, "fast") === "boolean" && fastRuntime(runtime) ? choice.fast : null;
  const contexts = at("contexts").filter((n): n is number => typeof n === "number");
  const c = contextOf(get(choice, "context"));
  const context = c !== null && contexts.includes(c) ? c : null;
  return { entry: entry === undefined ? null : entry, runtime, effort, fast, context, profile, profiles, efforts, contexts, accounts };
}

function picked(r: Resolved): J {
  return {
    model: r.entry !== null ? r.entry.model : null,
    runtime: r.runtime ?? "claude",
    effort: r.effort,
    fast: r.fast,
    context: r.context,
    profile: r.profile,
    ...(r.profiles !== null ? { profiles: r.profiles } : {}),
  };
}

/// The account a control on `value` names (PickAccount; none where it names none) and what it is made of: the one it is
/// kept to (`kept`, its id, or `keptProfiles` when kept to several), its window running low (`low`). It is the one kept
/// to, as `option` (the model it runs, its accounts) has it, else the one it is on now (`current`, a chat's); `quiet`,
/// a new chat's, which names the station's pick only where it runs low, and no account's allowance.
function named(value: J, option: J, current: J, quiet: boolean): { kept: string | null; keptProfiles: string[] | null; low: J; account: J } {
  const rawProfiles = normProfiles(get(value, "profiles"));
  const kept = text(get(value, "profile")) ?? (rawProfiles !== null && rawProfiles.length === 1 ? rawProfiles[0]! : null);
  const keptProfiles = kept === null && rawProfiles !== null && rawProfiles.length > 1 ? rawProfiles : null;
  const offered = option !== undefined && option !== null ? arr(get(get(option, "accounts"), typeof value.runtime === "string" ? value.runtime : "")) : [];
  if (keptProfiles !== null) {
    const subset = offered.filter((a) => keptProfiles.includes(a.id));
    const shown = current !== null && keptProfiles.includes(current.id) ? current : null;
    const levels = subset.map((a) => get(quotaLine(get(a, "quota")), "level") ?? null);
    const low = shown !== null ? (get(quotaLine(get(shown, "quota")), "level") ?? null) : levels.length > 0 && levels.every((l) => l !== null) ? levels[0] : null;
    const txt =
      shown !== null && typeof shown.name === "string" && shown.name !== ""
        ? t("core-logic.choose.account.count_on", { n: keptProfiles.length, name: shown.name })
        : t("core-logic.choose.account.count", { n: keptProfiles.length });
    return { kept: null, keptProfiles, low, account: { text: txt, auto: false, level: low, profile: quiet ? null : shown } };
  }
  let shown: J = null;
  if (kept !== null) shown = offered.find((a) => a.id === kept) ?? null;
  if (shown === null) shown = current;
  const low = shown !== null ? (get(quotaLine(get(shown, "quota")), "level") ?? null) : null;
  if (quiet && kept === null && low === null) return { kept, keptProfiles: null, low, account: null };
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
  return { kept, keptProfiles: null, low, account: { text: txt, auto: kept === null, level: low, profile: quiet ? null : shown } };
}

/// Whether what a new chat or a chat runs on now (`value`) runs Fast: as it is set, else as its account does (the one
/// kept to, else the one it is on, `current`), as the station's overview says.
function runsFast(overview: J, value: J, current: J): boolean {
  if (!fastRuntime(value.runtime)) return false;
  if (typeof value.fast === "boolean") return value.fast;
  const vProfiles = normProfiles(get(value, "profiles"));
  const vCurrent = typeof get(current, "id") === "string" && (vProfiles === null || vProfiles.includes(current.id)) ? current.id : null;
  const id = text(get(value, "profile")) ?? vCurrent ?? (vProfiles !== null ? (vProfiles[0] ?? null) : null);
  return arr(get(overview, "profiles")).some((p) => id !== null && p.id === id && p.fast === true);
}

const comboFast = (v: J): boolean | null => fastRuntime(get(v, "runtime")) && typeof get(v, "fast") === "boolean" ? v.fast : null;

/// Whether `a` and `b` are the same combination used here (`ws:<scope>:frequent`): the same model, runtime, how hard it
/// thinks, how fast and how much context (none, an entry kept before context was: its model's whole window).
export function sameCombo(a: J, b: J): boolean {
  return ["model", "runtime", "effort"].every((f) => text(get(a, f)) === text(get(b, f))) && comboFast(a) === comboFast(b) && contextOf(get(a, "context")) === contextOf(get(b, "context"));
}

/// A combination used here, kept by what it is (sameCombo). Usage stays bounded on the device; ties favour the most
/// recently started chat.
export function recordCombo(history: J[], choice: J, now: number): J[] {
  const same = (v: J) => sameCombo(v, choice);
  const found = history.find(same);
  const count = (typeof get(found, "count") === "number" ? found.count : 0) + 1;
  const out = history.filter((v) => !same(v));
  out.push({ model: get(choice, "model") ?? null, runtime: get(choice, "runtime") ?? null, effort: text(get(choice, "effort")), fast: comboFast(choice), context: contextOf(get(choice, "context")), count, last: now });
  out.sort((a, b) => (typeof b.last === "number" ? b.last : 0) - (typeof a.last === "number" ? a.last : 0));
  return out.slice(0, 64);
}

/// The combinations used most here (a configuration each: model, runtime, how hard it thinks, how fast, how much
/// context; the same model run two ways is two), the most first, then the most recently used, at most `NEAR`. Only
/// exact, still runnable ones are offered: never silently change a remembered depth, runtime or context; one only
/// another station has (borrowable) is left out. `fixed`: the runtime the control cannot leave, only its own offered
/// and none said by it. `selected`: `current` is exactly it.
export function frequentCombos(history: J[], options: J[], current: Resolved, fixed: string | null = null, showRuntime = false): J[] {
  const sorted = [...history].sort(
    (a, b) => (typeof b.count === "number" ? b.count : -1) - (typeof a.count === "number" ? a.count : -1) || (typeof b.last === "number" ? b.last : 0) - (typeof a.last === "number" ? a.last : 0),
  );
  const seen = new Set<string>();
  const out: J[] = [];
  for (const v of sorted) {
    if (out.length >= NEAR) break;
    const rawModel = typeof get(v, "model") === "string" ? v.model : null;
    const runtime = get(v, "runtime");
    const tiered = runtime === "agy" ? matchTiered(options, rawModel) : null;
    const entry = tiered !== null ? tiered.entry : optionOf(options, rawModel);
    if (entry === undefined || entry.availability === "borrowable") continue;
    if (typeof runtime !== "string" || !arr(entry.runtimes).some((r) => r === runtime)) continue;
    if (fixed !== null && runtime !== fixed) continue;
    const effort =
      text(get(v, "effort")) ??
      (tiered !== null && arr(get(get(entry, "efforts"), "agy")).includes(tiered.effort) ? tiered.effort : null);
    const fast = comboFast(v);
    const context = contextOf(get(v, "context"));
    const r = resolve(options, { model: entry.model, runtime, effort, fast, context, profile: current.profile, profiles: current.profiles });
    if (r.effort !== effort || r.context !== context) continue;
    const m = typeof entry.model === "string" ? entry.model : null;
    if (m === null) continue;
    const key = JSON.stringify([m, runtime, effort, fast, context]);
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
    // how it runs in words, after its name: the runtime where it can be another or the station runs several (its short
    // name, format.runtimeShort), the effort, the speed, the context
    const runtimeShown = arr(entry.runtimes).length > 1 || (showRuntime && fixed === null);
    const parts = [fixed === null && runtimeShown ? format.runtimeShort(runtime) : null, effortText, speedText, context === null ? null : format.compactNumber(context)].filter((x): x is string => x !== null);
    const selected = current.entry !== null && current.entry.model === m && current.runtime === runtime && current.effort === effort && current.fast === fast && current.context === context;
    out.push({ model: m, runtime, effort, fast, context, ...(speedText === null ? {} : { speedText }), label, text: parts.join(" · "), name, ...(runtimeText === null ? {} : { runtimeText }), effortText, selected });
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
  /// What its pages read of what is chosen here (drafts, choices, what is being added): made again as it changes.
  readonly #chosen = new Marks();
  readonly #drafts = new Map<string, Record<string, J>>();
  readonly #adding = new Map<string, J>();
  /// What was set by hand in a control's panel since it opened (a `pick.save` of how it runs with no model: how hard
  /// it thinks, its runtime, how fast, how much context), by its topic's key: what a model never run here would run
  /// with picked in that panel next (`#pick`'s `usual`). One that has run here is picked as it last ran whatever was
  /// set since: a model used most is the model with how it runs (the user, 2026-11-10: 「常用模型按理说是包括思考深度
  /// 的，这样随便切会让常用模型的配置失效」, of every model picked taking what was set by hand).
  readonly #hand = new Map<string, Record<string, J>>();
  /// What `#hand` held before the last save asked of the station, put back if that fails (`unsaved`).
  readonly #handWas = new Map<string, Record<string, J> | null>();
  readonly #saving = new Map<string, number>();
  /// The key each scope's next new chat is to be made under (`next`), until one is made under it.
  readonly #next = new Map<string, string>();

  constructor(env: ChooseEnv) {
    this.#env = env;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "newChat" || topic.topic === "pick";
  }

  stop(topic: Topic): void {
    this.#drafts.delete(topicKey(topic));
    this.#hand.delete(topicKey(topic));
    this.#handWas.delete(topicKey(topic));
  }

  compute(topic: Topic): Value | undefined {
    this.#chosen.read();
    try {
      if (topic.topic === "newChat") return { ok: this.#newChat(topic.scope as string) };
      return this.#pick(topic, topic.station as string, topic.of as string);
    } catch (e) {
      if (!(e instanceof CoreError)) throw e;
      return { err: e };
    }
  }

  #changed(): void {
    this.#chosen.touch();
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
    for (const f of FIELDS) {
      kept[f] =
        f === "fast"
          ? (typeof get(choice, f) === "boolean" ? choice[f] : null)
          : f === "context"
            ? contextOf(get(choice, f))
            : f === "profiles"
              ? normProfiles(get(choice, f))
              : typeof get(choice, f) === "string"
                ? choice[f]
                : "";
    }
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

  /// The scope's stations up now, each its row (StationRow); an error (null: not known yet; a string: why it failed).
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
    const station = held ?? online[0];
    view.down = held !== undefined && held.online !== true;
    view.stations = view.down ? [...online, station] : online;
    if (station === undefined) return view;
    const id = typeof station.id === "string" ? station.id : "";
    const name = typeof station.name === "string" ? station.name : "";
    const addr = typeof station.station === "string" ? station.station : "";
    // The stations are held as a list has them (StationRow; the page is sent what it names them by, NewChatStation);
    // what it runs is worked out from the one it starts on alone: its page's overview, the models it serves this
    // workspace (not every station's, by the minute).
    const page: J = this.#env.store.get({ topic: "station", scope, station: addr });
    const overview = isObject(get(page, "overview")) ? page.overview : null;
    const raw: J = this.#env.store.get({ topic: "overview", station: addr });
    const served = servingIn(raw, scope, station.joined === true);
    const options = overview !== null ? models(served, this.#env.now()) : [];
    const r = resolve(options, this.#choice(scope, id), raw !== undefined ? get(raw, "accountSubsets") === true : overview === null || get(overview, "accountSubsets") === true);
    view.frequent = frequentCombos(arr(this.#record(`ws:${scope}:frequent`)), options, r);
    // A station this workspace joined runs its chats on the profiles open to it: with some, but
    // none open, one is turned on rather than added.
    const joined = station.joined === true;
    const all = overview !== null ? arr(overview.profiles) : [];
    const profiles = overview !== null ? arr(servingIn(overview, scope, joined).profiles) : all;
    view.waiting = overview === null;
    // No profile of its own, but another station of the workspace has models it could borrow: its model control
    // offers them (borrowed before the chat is made) rather than only adding a profile. Only whether one does: each
    // other station up's overview walked for a profile it would lend, none of their models made (lends).
    const lends = overview !== null && profiles.length === 0 && !joined && this.#lends(scope, addr);
    const disabled = all.some((p) => get(p, "enabled") === false && profileServes(p, scope, joined));
    view.blocked = overview !== null && profiles.length === 0 ? (lends ? null : disabled ? "disabled" : joined && all.length > 0 ? "shared" : "profile") : overview !== null && options.length === 0 ? "models" : null;
    // This workspace's name: as it is held, else as an account's `/v1/me` lists it.
    const here = get(this.#env.data.shared({ topic: "workspace", workspace: scope }), "name")
      ?? this.#env.data.mes().flatMap(([, me]) => arr(get(me, "workspaces"))).find((w) => get(w, "id") === scope)?.name;
    const notShared = () => typeof station.home === "string" && station.home !== ""
      ? t("core-logic.choose.problem.not_shared", { name, home: station.home, workspace: typeof here === "string" ? here : "" })
      : t("core-logic.choose.problem.not_shared_elsewhere", { name, workspace: typeof here === "string" ? here : "" });
    view.problem = overview === null ? t("core-logic.choose.problem.loading", { name })
      : lends ? t("core-logic.choose.problem.borrow_only", { name })
      : view.blocked === "disabled" ? t("core-logic.choose.problem.disabled_profiles", { name })
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
    // Its model control as the page draws it closed (none while its profiles are read: the page shows it in its
    // bones); its panel is the `pick` topic, asked as it opens.
    // Its control runs on the station's models of every profile it has enabled (`#onStation`, as `pick` of `new` has
    // always made them), the page on those serving this workspace (`servingIn`): the same list, made once, unless a
    // profile enabled there does not serve it (its `serves` false; or, on a station from before `serves`, one this
    // workspace joined whose profile's `workspaces` do not name it); then the control's are made apart, as before.
    const servesAll = arr(get(served, "profiles")).length === arr(get(raw, "profiles")).filter((p) => get(p, "enabled") !== false).length;
    view.pick = overview !== null ? this.#face(addr, servesAll ? options : models(raw, this.#env.now())) : null;
    // The workspace's presets, every station's up now (each as it was read last), to pick from where the page's
    // control opens (its menu: each by its name and station's); the one picked whichever station it is of. Held with
    // the page, which has each station's read as it shows: the menu finds them read, never waits on a station.
    const listed = this.#workspacePresets(online);
    view.presets = listed.map(({ p, station: at, stationName }) => ({ id: text(get(p, "id")) ?? "", name: text(get(p, "name")) ?? "", station: at, stationName }));
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
    const subsets = overview === undefined || get(overview, "accountSubsets") === true;
    return [options, resolve(options, this.#choice(ofAddress(addr), stationId(addr)), subsets)];
  }

  /// A new chat's model control as its page draws it closed (NewChatPick), on `station` of `options` (its models as
  /// `#onStation` makes them: of every profile enabled there): what it runs on now and how
  /// (the model's name, maker and runtimes; whether it says how hard it thinks, Fast; the account kept to), worked out
  /// of that station alone, as `#pick` works out the same of it (`#now`'s, `named`, `runsFast`). Its panel is the `pick`
  /// topic, asked as it opens: every option annotated, the workspace's other stations' models after them, made for
  /// the panel, never for the page. None while the station's overview is not read (`pick`'s none).
  #face(station: string, options: J[]): J {
    const overview = this.#env.store.get({ topic: "overview", station });
    if (overview === undefined) return null;
    const r = resolve(options, this.#choice(ofAddress(station), stationId(station)), get(overview, "accountSubsets") === true);
    const value = picked(r);
    const multiRuntime = new Set(options.flatMap((o) => arr(o.runtimes))).size > 1;
    return {
      value,
      valueOption: r.entry,
      efforts: r.efforts,
      account: named(value, r.entry, null, true).account,
      fastText: runsFast(overview, value, null) ? "Fast" : null,
      ...(multiRuntime ? { showRuntime: true } : {}),
    };
  }

  /// Whether another station of `scope` up now would lend station `here` a model (views/models.ts `lends`): a yes or no
  /// of the scope's stations' rows and the overviews of those up, as they are kept, none of their models made.
  #lends(scope: string, here: string): boolean {
    const v = this.#env.store.value({ topic: "stations", scope });
    return lends(v !== undefined && "ok" in v ? v.ok : [], here, (station) => this.#env.store.get({ topic: "overview", station }));
  }

  /// The presets of the scope's stations `online` (their addresses' `presets` topics), as each station said them last,
  /// with the station each is of.
  #workspacePresets(online: J[]): { p: J; station: string; stationName: string }[] {
    const out: { p: J; station: string; stationName: string }[] = [];
    for (const s of online) {
      const at = typeof s.station === "string" ? s.station : "";
      if (at === "") continue;
      const topic: Topic = { topic: "presets", station: at };
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
    if (typeof preset === "string") {
      const presetStation = text(get(params, "presetStation")) ?? "";
      this.#env.data.put(TABLE, `ws:${scope}:preset`, { id: preset, station: presetStation }, false);
      if (preset !== "" && station === null && !FIELDS.some((f) => get(params, f) !== undefined)) {
        const found = this.#online(scope);
        const online = Array.isArray(found) ? found[0] : [];
        const picked = this.#picked(scope, this.#workspacePresets(online));
        if (picked !== undefined) {
          const p = picked.p;
          const pm = get(p, "model");
          const wantModel = isObject(pm) ? text(get(pm, "model")) : null;
          const pickBest = (pool: J[]): string | null => {
            if (pool.length === 0) return null;
            const compatible =
              wantModel !== null
                ? pool.filter((s) => typeof s.station === "string" && optionOf(this.#onStation(s.station)[0], wantModel) !== undefined)
                : pool;
            const list = compatible.length > 0 ? compatible : pool;
            const sorted = [...list].sort((a, b) => {
              const ra = typeof get(get(get(a, "overview"), "counts"), "running") === "number" ? a.overview.counts.running : 0;
              const rb = typeof get(get(get(b, "overview"), "counts"), "running") === "number" ? b.overview.counts.running : 0;
              return ra - rb;
            });
            const best = sorted[0];
            return best !== undefined && typeof best.id === "string" ? best.id : null;
          };
          let targetStationId: string | null = null;
          const singleStation = text(get(p, "station"));
          const subsetStations = Array.isArray(get(p, "stations"))
            ? get(p, "stations").filter((x: unknown): x is string => typeof x === "string" && x !== "")
            : [];
          if (singleStation !== null) {
            const match = online.find((s) => s.id === singleStation || s.station === singleStation);
            targetStationId = match !== undefined && typeof match.id === "string" ? match.id : stationId(singleStation);
          } else if (subsetStations.length > 0) {
            const pool = online.filter((s) => subsetStations.includes(s.id) || subsetStations.includes(s.station));
            targetStationId = pickBest(pool);
          } else if (get(p, "autoStation") === true) {
            targetStationId = pickBest(online);
          }
          if (targetStationId !== null && targetStationId !== "") {
            this.#keepStation(scope, targetStationId);
          }
          if (isObject(pm) && wantModel !== null) {
            const id = targetStationId ?? this.#shown(scope);
            const addr = address(scope, id);
            const [options, now] = this.#onStation(addr);
            const next: J = {
              runtime: now.runtime,
              model: now.entry !== null ? now.entry.model : null,
              effort: now.effort,
              fast: now.fast,
              context: now.context,
              profile: now.profile,
              profiles: now.profiles,
            };
            const runs = arr(get(optionOf(options, wantModel), "runtimes"));
            const rt = text(get(pm, "runtime"));
            if (rt !== null) {
              next.runtime = rt;
            } else if (!runs.some((r) => equal(r, next.runtime))) {
              next.runtime = runs[0] ?? next.runtime;
            }
            next.model = wantModel;
            next.effort = text(get(pm, "effort"));
            if (typeof get(pm, "fast") === "boolean") next.fast = pm.fast;
            if (get(pm, "context") !== undefined) next.context = contextOf(pm.context);
            if (get(pm, "profile") !== undefined) next.profile = text(pm.profile) ?? "";
            if (get(pm, "profiles") !== undefined) next.profiles = normProfiles(pm.profiles);
            this.#keepChoice(scope, id, next);
          }
        }
      }
    }
    if (FIELDS.some((f) => get(params, f) !== undefined)) {
      const id = station ?? this.#shown(scope);
      const addr = address(scope, id);
      const ps = normProfiles(get(params, "profiles"));
      if (ps !== null && ps.length > 1) {
        const ov = this.#env.store.get({ topic: "overview", station: addr });
        if (ov !== undefined && get(ov, "accountSubsets") !== true) throw CoreError.invalid(t("core-logic.choose.error.station_account_subsets"));
      }
      const [options, now] = this.#onStation(addr);
      const next: J = { runtime: now.runtime, model: now.entry !== null ? now.entry.model : null, effort: now.effort, fast: now.fast, context: now.context, profile: now.profile, profiles: now.profiles };
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
      if (get(params, "profiles") !== undefined && get(params, "profile") === undefined) next.profile = "";
      if (get(params, "profile") !== undefined && get(params, "profiles") === undefined) next.profiles = null;
      for (const field of ["effort", "profile", "profiles", "fast", "context"]) if (get(params, field) !== undefined) next[field] = params[field];
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
    else if (r.profiles !== null && r.profiles.length > 1) ask.profiles = r.profiles;
    if (r.fast !== null) ask.fast = r.fast;
    if (r.context !== null) ask.context = r.context;
    // The preset picked: by its id where it is this station's, else all of it as its station said it (its folders
    // that station's).
    const scope = ofAddress(station);
    const online = (() => {
      const v = this.#env.store.value({ topic: "stations", scope });
      return v !== undefined && "ok" in v ? arr(v.ok) : [];
    })();
    const picked = this.#picked(scope, this.#workspacePresets(online));
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
        if (o.form === "preset") {
          const [options, base] = this.#onStation(station);
          const saved = this.#adding.get(`${station}\u0001preset`);
          const r = saved !== undefined ? resolve(options, saved, get(ov, "accountSubsets") === true) : base;
          return [options, saved !== undefined ? picked(r) : { ...picked(r), model: null }, null, false, true, 0];
        }
        const options = models(ov, now);
        const r = resolve(options, this.#adding.get(`${station}\u0001${o.form}`) ?? {}, get(ov, "accountSubsets") === true);
        return [options, picked(r), null, false, false, 0];
      }
      case "connect": {
        const ov = overview();
        if (ov === undefined) return undefined;
        const connect = arr(get(ov, "connects")).find((c) => c.id === o.id);
        if (connect === undefined) throw new CoreError("http_404", t("core-logic.choose.error.no_connect"), 404);
        const bind = connect.bind;
        // (a station from before keeps a connect on the runtime it was made with)
        const switchable = get(ov, "connectRuntimeChange") === true;
        const options = models(ov, now).filter((m) => switchable || arr(m.runtimes).some((r) => equal(r, get(bind, "runtime"))));
        const bProfiles = normProfiles(get(bind, "profiles"));
        const bProfile = bProfiles !== null && bProfiles.length === 1 ? bProfiles[0]! : text(get(bind, "profile"));
        const bMulti = bProfile === null && bProfiles !== null && bProfiles.length > 1 ? bProfiles : null;
        const value: J = { model: text(get(bind, "model")), runtime: get(bind, "runtime") ?? null, effort: text(get(bind, "effort")), profile: bProfile, ...(bMulti !== null ? { profiles: bMulti } : {}) };
        normalizeTieredValue(options, value);
        return [options, value, null, !switchable, false, 0];
      }
      case "session": {
        const agent = this.#env.agent(station, o.key);
        if (agent === null || agent === undefined) return undefined;
        const s = agent.session;
        const sProfiles = normProfiles(get(s, "profiles"));
        const pinned = get(s, "profilePinned") === true;
        const sProfile = pinned ? text(get(s, "profile")) : sProfiles !== null && sProfiles.length === 1 ? sProfiles[0]! : null;
        const sMulti = sProfile === null && sProfiles !== null && sProfiles.length > 1 ? sProfiles : null;
        const value: J = {
          model: text(get(s, "model")),
          runtime: get(s, "runtime") ?? null,
          effort: text(get(s, "effort")),
          fast: get(s, "fast") ?? null,
          context: contextOf(get(s, "context")),
          profile: sProfile,
          ...(sMulti !== null ? { profiles: sMulti } : {}),
        };
        const current = isObject(agent.account) ? agent.account : null;
        const ov = overview();
        const switchable = get(ov, "sessionRuntimeChange") === true;
        const scope = ofAddress(station);
        const stationView = arr(this.#env.store.get({ topic: "stations", scope })).find((s) => s.id === stationId(station));
        const available = servingIn(ov, scope, get(stationView, "joined") === true);
        const list = switchable ? models(available, now) : arr(agent.choices);
        normalizeTieredValue(list, value);
        return [list, value, current, !switchable, false, arr(agent.profiles).length];
      }
    }
  }

  /// What a station's own options are, said where their accounts are, and the models the workspace's other stations
  /// could lend it after them (of `runtime` alone where it cannot change).
  #withWorkspace(station: string, own: J[], runtime: string | null): J[] {
    // (every station's models: the core's own whole list, views.ts `stationsWhole`)
    const stations = this.#env.store.get({ topic: "stationsWhole", scope: ofAddress(station) });
    const overview = this.#env.store.get({ topic: "overview", station });
    return [...sourced(own, overview, stations), ...borrowable(stations, station, own, runtime, this.#env.now())];
  }

  /// Whether the viewer may have another station share a profile with this one (managers).
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
    const isPreset = o.kind === "connectNew" && o.form === "preset";
    const draft = this.#drafts.get(topicKey(topic)) ?? {};
    const pickedOf = (field: string) => text(field in draft ? draft[field] : get(value, field));
    const m = pickedOf("model") ?? (isPreset ? (text(get(this.#onStation(station)[1].entry, "model")) ?? text(get(options[0], "model"))) : null);
    const runtime = pickedOf("runtime");
    const nonePicked = "profiles" in draft && Array.isArray(draft.profiles) && normProfiles(draft.profiles) === null;
    const draftedAccounts = (): { asked: string[]; multi: boolean } => {
      if ("profiles" in draft) {
        const ps = normProfiles(draft.profiles);
        return ps !== null ? { asked: ps, multi: true } : { asked: [], multi: false };
      }
      if ("profile" in draft) {
        const p = text(draft.profile);
        return p !== null ? { asked: [p], multi: false } : { asked: [], multi: false };
      }
      return choiceAccounts(value);
    };
    const { asked, multi } = draftedAccounts();
    const option = optionOf(options, m);
    const valueOption = optionOf(options, typeof value.model === "string" ? value.model : null);
    const runtimes = option !== undefined ? arr(option.runtimes) : [];
    const on = fixed ? value.runtime : (runtimes.find((r) => r === runtime) ?? runtimes[0] ?? value.runtime);
    const onName = typeof on === "string" ? on : "";
    const rawAccounts = option !== undefined ? arr(get(get(option, "accounts"), onName)) : [];
    const accounts = rawAccounts.map((a) => {
      const isCurrent = current !== null && on === value.runtime && a.id === current.id;
      if (isCurrent) return a.current === true ? a : { ...a, current: true };
      if (a.current !== undefined) {
        const copy = { ...a };
        delete copy.current;
        return copy;
      }
      return a;
    });
    let efforts: J[] = option !== undefined ? arr(get(get(option, "efforts"), onName)) : fixed || o.kind === "session" ? format.efforts(onName) : [];
    const account = (id: string | null) => (id === null ? undefined : accounts.find((a) => a.id === id));
    const { profile, profiles, dropped } = resolveAccounts(accounts, asked, multi);
    if (profile !== null) {
      const levels = get(accounts.find((a) => a.id === profile), "efforts");
      if (Array.isArray(levels)) efforts = levels;
    } else if (profiles !== null && onName !== "") {
      const subset = accounts.filter((a) => profiles.includes(a.id));
      if (subset.length > 0) efforts = subsetEfforts(subset, onName);
    }
    const e = pickedOf("effort");
    const effort = e !== null && efforts.some((x) => x === e) ? e : null;
    // How much less context than its whole window it can be kept to: a new chat's and a chat's (a connect's sessions
    // are made by the station, as it is set).
    const contexts: number[] = option !== undefined && (o.kind === "new" || o.kind === "session" || isPreset)
      ? arr(get(get(option, "contexts"), onName)).filter((n): n is number => typeof n === "number")
      : [];
    const cPicked = contextOf("context" in draft ? draft.context : get(value, "context"));
    const context = cPicked !== null && contexts.includes(cPicked) ? cPicked : null;
    const nextModel = option !== undefined && (valueOption === undefined || valueOption.model !== option.model) ? option.model : (value.model ?? null);
    const overview = this.#env.store.get({ topic: "overview", station });
    const allowedIds: string[] | null = profiles ?? (profile !== null ? [profile] : null);
    const fastAvailable =
      fastRuntime(onName) &&
      (o.kind === "new" || o.kind === "session" || isPreset) &&
      arr(get(overview, "profiles")).some((p) => typeof p.fast === "boolean" && (allowedIds === null || allowedIds.includes(p.id)) && accounts.some((a) => a.id === p.id));
    // How fast it runs where none is picked: its account's own (the one drafted, else the one it is on), said as what
    // it is rather than as 跟随订阅 (2026-11-02 用户「谁知道订阅是什么，应该直接显示具体值」).
    const currentInPool = typeof get(current, "id") === "string" && (allowedIds === null || allowedIds.includes(current.id)) ? current.id : null;
    const planFastOf = profile ?? currentInPool ?? (profiles !== null ? (profiles[0] ?? null) : null);
    const fastPlan = arr(get(overview, "profiles")).some((p) => planFastOf !== null && p.id === planFastOf && p.fast === true);
    const fastRaw = "fast" in draft ? draft.fast : get(value, "fast");
    const fast = typeof fastRaw === "boolean" && fastRuntime(onName) ? fastRaw : null;
    const speedText = (f: boolean | null) => (f === true ? "Fast" : f === false ? t("core-logic.choose.speed.standard") : t("core-logic.choose.speed.plan"));
    const next = { model: nextModel, runtime: on ?? null, effort, profile, ...(profiles !== null ? { profiles } : {}), fast, context };
    const changed = !nonePicked && FIELDS.some((f) => !equal((next as J)[f] ?? null, value[f] ?? null));
    const { kept, keptProfiles, low, account: accountView } = named(value, valueOption, current, quiet);
    const effectiveFast = (o.kind === "new" || o.kind === "session" || isPreset) && value.model !== null && runsFast(overview, value, current);
    const drafted = account(profile);
    const who = nonePicked
      ? t("core-logic.choose.account.none")
      : drafted !== undefined && typeof drafted.name === "string"
        ? drafted.name.split("@")[0]
        : profiles !== null
          ? t("core-logic.choose.account.count", { n: profiles.length })
          : t("core-logic.choose.account.all");
    const subsetLevels = profiles !== null ? accounts.filter((a) => profiles.includes(a.id)).map((a) => get(quotaLine(get(a, "quota")), "level") ?? null) : [];
    const subsetLow = subsetLevels.length > 0 && subsetLevels.every((l) => l !== null) ? subsetLevels[0] : null;
    const whoLevel = nonePicked || dropped ? "amber" : profile === null && profiles === null && kept === null && keptProfiles === null ? low : profiles !== null ? subsetLow : null;
    const currentName = typeof get(current, "name") === "string" ? current.name : "";
    const autoNote = nonePicked
      ? t("core-logic.choose.account.pick_one")
      : profiles !== null
        ? t("core-logic.choose.account.subset_note")
        : current !== null && profile === null && kept === null && keptProfiles === null && on === value.runtime
          ? t("core-logic.choose.account.now", { name: currentName })
          : t("core-logic.choose.account.auto_note");
    // A chat's account picked again now (`pick.repick`), beside 全选: when at least two checked accounts can take it.
    const repick = !nonePicked && current !== null && profile === null && Math.max(runnable, accounts.length) > 1 && on === value.runtime ? t("core-logic.choose.account.repick") : null;
    const optionName = option !== undefined && typeof option.name === "string" ? option.name : null;
    const nameOf = (x: string | null): string | null => {
      if (x === null) return null;
      if (x === value.model) return model.name(x);
      const found = optionOf(options, x);
      return found !== undefined && typeof found.name === "string" ? found.name : x;
    };
    const accountText = (id: string | null) => (id === null ? t("core-logic.choose.account.auto") : (account(id)?.name ?? id));
    const onCurrent = !nonePicked && current !== null && accounts.some((a) => equal(a.id, current.id)) && (profiles === null || profiles.includes(current.id));
    const movesOff = !nonePicked && profile === null && kept === null && m !== null && current !== null && !onCurrent;
    const modelName = nameOf(m);
    const effortText = effort ?? t("core-logic.choose.default_effort");
    const chosenText = nonePicked ? t("core-logic.choose.account.none") : profile !== null ? accountText(profile) : profiles !== null ? t("core-logic.choose.account.count", { n: profiles.length }) : t("core-logic.choose.account.auto");
    const was = [
      nameOf(typeof value.model === "string" ? value.model : null) ?? t("core-logic.format.default_model"),
      text(get(value, "effort")) ?? t("core-logic.choose.default_effort"),
      kept !== null
        ? currentName
        : keptProfiles !== null
          ? currentName !== ""
            ? t("core-logic.choose.account.count_on", { n: keptProfiles.length, name: currentName })
            : t("core-logic.choose.account.count", { n: keptProfiles.length })
          : t("core-logic.choose.account.auto_on", { name: currentName }),
    ];
    const becomes = [
      modelName ?? t("core-logic.format.default_model"),
      effortText,
      profile !== null
        ? chosenText
        : profiles !== null
          ? onCurrent && currentName !== ""
            ? t("core-logic.choose.account.count_on", { n: profiles.length, name: currentName })
            : chosenText
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
    const droppedAccount = asked.length > 1 ? t("core-logic.choose.account.count", { n: asked.length }) : accountText(asked[0] ?? null);
    const force = dropped
      ? t("core-logic.choose.force.dropped", { account: droppedAccount, model: modelName ?? "" })
      : movesOff
        ? t("core-logic.choose.force.moves_off", { account: currentName, model: modelName ?? "" })
        : null;
    const borrow = option !== undefined && option.availability === "borrowable" ? this.#borrowView(station, option) : null;
    // Each model as it would run picked in the panel (`usual`: what it last ran with here, the one picked as it is
    // drafted now).
    const scope = ofAddress(station);
    const history = arr(this.#record(`ws:${scope}:frequent`));
    const rawLikedKeys = this.#liked(scope, station);
    const optionKeys = new Set(options.map((opt: J) => model.key(String(opt.model ?? ""))));
    const agyOptionKeys = new Set(options.filter((opt: J) => arr(opt.runtimes).includes("agy")).map((opt: J) => model.key(String(opt.model ?? ""))));
    const likedKeys: string[] = [];
    for (const k of rawLikedKeys) {
      const split = !optionKeys.has(k) ? model.splitAgyTier(k) : null;
      const nk = split !== null && agyOptionKeys.has(model.key(split.model)) ? model.key(split.model) : k;
      if (!likedKeys.includes(nk)) likedKeys.push(nk);
    }
    const hand = this.#hand.get(topicKey(topic));
    // What a model never run here takes of what was set by hand in the panel: a runtime among those it runs on, how
    // hard it thinks among that runtime's levels, how fast and how much context where that runtime has them; none,
    // nothing of it.
    const byHand = (opt: J): J => {
      if (hand === undefined) return undefined;
      const rts = arr(opt.runtimes);
      const rt = !fixed && rts.some((r) => r === hand.runtime) ? hand.runtime : null;
      const at = fixed ? value.runtime : (rt ?? rts[0]);
      const has = (field: string) => (typeof at === "string" ? arr(get(get(opt, field), at)) : []);
      const e = text(hand.effort);
      const c = contextOf(hand.context);
      const took = {
        runtime: rt,
        effort: e !== null && has("efforts").some((x) => x === e) ? e : null,
        fast: typeof hand.fast === "boolean" && fastRuntime(at) ? hand.fast : null,
        context: c !== null && (o.kind === "new" || o.kind === "session" || isPreset) && has("contexts").some((n) => n === c) ? c : null,
      };
      return took.runtime === null && took.effort === null && took.fast === null && took.context === null ? undefined : took;
    };
    const multiRuntime = !fixed && new Set(options.flatMap((opt: J) => arr(opt.runtimes))).size > 1;
    work.annotated += options.length;
    const annotated = options.map((opt: J) => {
      const id = typeof opt.model === "string" ? opt.model : "";
      const ran = id === m ? { runtime: on ?? null, effort, fast, context } : (this.#usual(scope, id, history) ?? byHand(opt));
      const r = ran === undefined ? null : resolve(options, { model: id, runtime: fixed ? value.runtime : ran.runtime, effort: ran.effort, fast: ran.fast, context: ran.context });
      const rts = arr(opt.runtimes);
      const parts: string[] = [];
      if (r !== null) {
        if (!fixed && rts.length > 1 && r.runtime !== null) {
          const other = rts.find((x) => x !== r.runtime);
          parts.push(rts.length === 2 && typeof other === "string" ? `${format.runtimeShort(r.runtime)} / ${format.runtimeShort(other)}` : `${format.runtimeShort(r.runtime)} +${rts.length - 1}`);
        } else if (multiRuntime && r.runtime !== null) {
          parts.push(format.runtimeShort(r.runtime));
        }
        if (r.effort !== null) parts.push(format.effortLabel(r.effort));
        if (r.fast === true) parts.push("Fast");
        if (r.context !== null && (o.kind === "new" || o.kind === "session" || isPreset)) parts.push(format.compactNumber(r.context));
      } else if (!fixed && rts.length > 1) {
        parts.push(rts.map((rt) => format.runtimeShort(String(rt))).join(" · "));
      } else if (multiRuntime && rts.length === 1) {
        parts.push(format.runtimeShort(String(rts[0])));
      }
      const usual = r === null ? null : { runtime: r.runtime, effort: r.effort, fast: r.fast, context: o.kind === "new" || o.kind === "session" || isPreset ? r.context : null };
      return { ...opt, usual, usualText: parts.length > 0 ? parts.join(" · ") : null, liked: likedKeys.includes(model.key(id)) };
    });
    // Two things, apart (the user, 2026-11-10: 「收藏跟常用不一样」「常用包括了思考深度和速度还有上下文长度」「是一种
    // 配置」): the configurations new chats here started on most (`combos`: a model with how it runs, the same model
    // run two ways two of them, starred or not), a chat's or a new chat's, of its runtime alone where that is fixed;
    // and the starred models (`liked`), in the order they were starred, every one of them, one of those used most or
    // not. Then every model, by its maker (`makers`).
    const draftNow: Resolved = { entry: value.model !== null || "model" in draft ? (option ?? null) : null, runtime: typeof on === "string" ? on : null, effort, fast, context, profile, profiles, efforts, contexts, accounts };
    const combos = o.kind === "new" || o.kind === "session" || isPreset
      ? frequentCombos(history, options, draftNow, fixed && typeof value.runtime === "string" ? value.runtime : null, multiRuntime).map((c: J) => ({
          model: c.model,
          runtime: c.runtime,
          effort: c.effort,
          fast: c.fast,
          context: c.context,
          name: c.name,
          text: c.text,
          selected: c.selected,
        }))
      : [];
    const liked = likedKeys.flatMap((k) => {
      const found = annotated.find((x: J) => model.key(x.model) === k);
      return found !== undefined ? [found.model] : [];
    });
    const makers = this.#makers(annotated);
    let saveText = changed ? t("core-logic.choose.save", { model: modelName ?? t("core-logic.format.default_model"), effort: effortText, account: chosenText }) : t("core-logic.choose.save.unchanged");
    if (changed && fastAvailable) saveText = `${saveText} · ${speedText(fast)}`;
    return {
      ok: {
        fastAvailable,
        effortDefault: (() => {
          const level = effortDefault(overview, onName, option !== undefined ? (option.model ?? null) : null, allowedIds);
          return level !== null && efforts.some((x) => x === level) ? level : null;
        })(),
        fastPlan,
        fastText: effectiveFast ? "Fast" : null,
        options: annotated,
        combos,
        liked,
        makers,
        runtimeFixed: fixed,
        ...(multiRuntime ? { showRuntime: true } : {}),
        value,
        valueOption: valueOption ?? null,
        account: accountView,
        draft: { model: m, runtime: on ?? null, effort, profile, ...(nonePicked ? { profiles: [] } : profiles !== null ? { profiles } : {}), fast, context },
        option: option !== undefined ? (option.model ?? null) : null,
        runtimes: !fixed && runtimes.length > 1 ? runtimes : [],
        efforts,
        // The most context it can be kept to, each said ("" its whole window, first), and the one picked.
        contexts: contexts.length === 0 ? [] : [{ id: "", text: wholeWindow(option) }, ...contexts.map((n) => ({ id: String(n), text: format.compactNumber(n) }))],
        contextNow: context === null ? "" : String(context),
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
        accountNote: nonePicked ? t("core-logic.choose.account.pick_one") : profile !== null ? t("core-logic.choose.account.fixed") : profiles !== null ? t("core-logic.choose.account.subset_note") : t("core-logic.choose.account.auto_note"),
        accountWarn: nonePicked || dropped || movesOff,
        saveText,
        next,
        borrow,
      },
    };
  }

  /// The makers of `options` (their `maker`; none, 其他), in the order their models come (the newest of Claude's first,
  /// format.ts's order), each with how many of them it makes: what the panel lists all of them by (2026-11-02 用户
  /// 「分组应该是模型厂商，而不是供应商」).
  #makers(options: J[]): J[] {
    const out = new Map<string, J>();
    for (const o of options) {
      const id = typeof get(o.maker, "id") === "string" ? o.maker.id : "";
      const had = out.get(id);
      if (had !== undefined) had.count += 1;
      else out.set(id, { id, title: id === "" ? t("core-logic.choose.maker.other") : String(get(o.maker, "name") ?? id), count: 1 });
    }
    // (none known last)
    return [...out.values()].sort((a, b) => Number(a.id === "") - Number(b.id === ""));
  }

  /// The models starred in `scope` (`ws:<scope>:liked`, kept on this device), by key, the first starred first. None ever
  /// starred here: those the workspace's profiles name in config.json, ticked on before every model a profile's check
  /// found ran (2026-11-02 用户「以前的模型选择变成已经点过的勾」), kept once one is starred or unstarred.
  #liked(scope: string, station: string | null = null): string[] {
    const kept = this.#record(`ws:${scope}:liked`);
    if (kept !== undefined) return arr(kept).filter((k): k is string => typeof k === "string");
    const out: string[] = [];
    // (the control's own station's overview first, then the workspace's others as `stationsWhole` has them)
    const overviews = [station !== null ? this.#env.store.get({ topic: "overview", station }) : undefined, ...arr(this.#env.store.get({ topic: "stationsWhole", scope })).map((s) => get(s, "overview"))];
    for (const ov of overviews) {
      for (const p of arr(get(ov, "profiles"))) {
        // (a station of before `named`: what it ran was what was ticked on)
        const named = Array.isArray(get(p, "named")) ? p.named : arr(get(p, "models"));
        for (const m of named) if (typeof m === "string" && !out.includes(model.key(m))) out.push(model.key(m));
      }
    }
    return out;
  }

  /// `pick.like`: model `model` starred (`liked`) or not in the workspace of the control's station: listed in every
  /// model control's panel there, after the combinations used most.
  like(station: string, m: string, liked: boolean): void {
    if (m === "") throw CoreError.invalid(t("core-misc.params.missing", { field: "model" }));
    const scope = ofAddress(station);
    const key = model.key(m);
    const now = this.#liked(scope, station).filter((k) => {
      if (k === key) return false;
      const split = model.splitAgyTier(k);
      return split === null || model.key(split.model) !== key;
    });
    if (liked) now.push(key);
    this.#env.data.put(TABLE, `ws:${scope}:liked`, now, false);
    this.#changed();
  }

  /// `pick.forget`: the combination `choice` (its model, runtime, effort, fast, context) no longer among those used most
  /// in the workspace of the control's station (the user, 2026-11-10: 「常用模型应该是一种特定配置，并且可以删掉，跟模型
  /// 没有关系」): its entry taken out, nothing else (how the model last ran, the starred, stay); a new chat on it later
  /// counts it again from one.
  forget(station: string, choice: J): void {
    if (text(get(choice, "model")) === null) throw CoreError.invalid(t("core-misc.params.missing", { field: "model" }));
    const key = `ws:${ofAddress(station)}:frequent`;
    const history = arr(this.#record(key));
    const overview = this.#env.store.get({ topic: "overview", station });
    const opts = overview !== undefined ? models(overview, this.#env.now()) : [];
    const normEntry = (v: J): J => {
      if (get(v, "runtime") !== "agy" || typeof get(v, "model") !== "string") return v;
      const tiered = matchTiered(opts, v.model);
      if (tiered === null) return v;
      const eff = text(get(v, "effort")) ?? (arr(get(get(tiered.entry, "efforts"), "agy")).includes(tiered.effort) ? tiered.effort : null);
      return { ...v, model: tiered.entry.model, effort: eff };
    };
    const left = history.filter((v) => !sameCombo(v, choice) && !sameCombo(normEntry(v), choice));
    if (left.length === history.length) return;
    this.#env.data.put(TABLE, key, left, false);
    this.#changed();
  }

  /// `pick.set`: picks in a control's panel. `open`: from what it runs on now again (`open: false` drops an incomplete
  /// zero-account draft back to the saved accounts); `clear`: starts over too.
  set(station: string, oName: string, params: J): void {
    const o = of(oName);
    const key = topicKey({ topic: "pick", station, of: oName });
    if (get(params, "clear") === true && o.kind === "connectNew") this.#adding.delete(`${station}\u0001${o.form}`);
    if (get(params, "open") === true || get(params, "clear") === true) {
      this.#drafts.delete(key);
      this.#hand.delete(key);
      this.#handWas.delete(key);
    } else if (get(params, "open") === false || (get(params, "model") !== undefined && get(params, "profiles") === undefined && get(params, "profile") === undefined)) {
      const cur = this.#drafts.get(key);
      if (cur !== undefined && Array.isArray(cur.profiles) && normProfiles(cur.profiles) === null) {
        delete cur.profiles;
        delete cur.profile;
        if (Object.keys(cur).length === 0) this.#drafts.delete(key);
      }
    }
    const fields = FIELDS.filter((f) => get(params, f) !== undefined);
    if (fields.length > 0) {
      const draft = this.#drafts.get(key) ?? {};
      if (get(params, "profiles") !== undefined && get(params, "profile") === undefined) delete draft.profile;
      if (get(params, "profile") !== undefined && get(params, "profiles") === undefined) delete draft.profiles;
      for (const f of fields) draft[f] = params[f];
      this.#drafts.set(key, draft);
    }
    this.#changed();
  }

  /// What model `model` last ran with here (`ws:<scope>:usual:<model>`, kept as it is saved and as a new chat starts on
  /// it), else as the newest new chat on it started; none, never used here.
  #usual(scope: string, m: string, history: J[]): J {
    const kept = this.#record(`ws:${scope}:usual:${m}`);
    if (isObject(kept)) return kept;
    let newest: J;
    for (const h of history) {
      const hm = get(h, "model");
      const split = get(h, "runtime") === "agy" && typeof hm === "string" && hm !== m ? model.splitAgyTier(hm) : null;
      if ((hm === m || (split !== null && split.model === m)) && (newest === undefined || (h.last ?? 0) > (newest.last ?? 0))) {
        newest = split !== null && text(get(h, "effort")) === null ? { ...h, effort: split.effort } : h;
      }
    }
    return newest === undefined ? undefined : { runtime: newest.runtime ?? null, effort: text(newest.effort), fast: comboFast(newest), context: null };
  }

  #keepUsual(scope: string, choice: J): void {
    const model = text(get(choice, "model"));
    if (model === null) return;
    this.#env.data.put(TABLE, `ws:${scope}:usual:${model}`, { runtime: get(choice, "runtime") ?? null, effort: text(get(choice, "effort")), fast: typeof get(choice, "fast") === "boolean" ? choice.fast : null, context: contextOf(get(choice, "context")) }, false);
  }

  /// `pick.save`: what the panel picked, made what it runs on; with picks of its own (a frequent combination's), those
  /// picked first.
  save(station: string, oName: string, params: J = {}): Saved {
    const o = of(oName);
    const key = topicKey({ topic: "pick", station, of: oName });
    if (FIELDS.some((f) => get(params, f) !== undefined)) {
      if (get(params, "profiles") === undefined && get(params, "profile") === undefined) {
        const cur = this.#drafts.get(key);
        if (cur !== undefined && Array.isArray(cur.profiles) && normProfiles(cur.profiles) === null) {
          delete cur.profiles;
          delete cur.profile;
          if (Object.keys(cur).length === 0) this.#drafts.delete(key);
        }
      }
      this.set(station, oName, Object.fromEntries(FIELDS.filter((f) => get(params, f) !== undefined).map((f) => [f, params[f]])));
    }
    const topic: Topic = { topic: "pick", station, of: oName };
    const view = this.#pick(topic, station, oName);
    if (view === undefined) throw CoreError.invalid(t("core-logic.choose.error.no_options_yet"));
    if ("err" in view) throw view.err;
    const v = view.ok as J;
    if (Array.isArray(get(v.draft, "profiles")) && v.draft.profiles.length === 0) {
      return { done: { saved: false } };
    }
    const next = v.next;
    const overview = this.#env.store.get({ topic: "overview", station });
    if (Array.isArray(next.profiles) && next.profiles.length > 1 && overview !== undefined && get(overview, "accountSubsets") !== true) {
      this.unsaved(station, oName);
      throw CoreError.invalid(t("core-logic.choose.error.station_account_subsets"));
    }
    // Not run here till its account is borrowed (`pick.borrow`).
    if (v.borrow !== null && v.borrow !== undefined) throw CoreError.invalid(t("core-logic.choose.borrow.first"));
    // How it runs set with no model: set by hand in the panel, kept for the model picked in it next (`#hand`); set
    // to what it already was, still set.
    const set = get(params, "model") === undefined ? HOW.filter((f) => get(params, f) !== undefined) : [];
    if (set.length > 0) {
      const was = this.#hand.get(key);
      this.#handWas.set(key, was ?? null);
      this.#hand.set(key, { ...was, ...Object.fromEntries(set.map((f) => [f, params[f]])) });
    } else {
      this.#handWas.delete(key);
    }
    const inFlight = (this.#saving.get(key) ?? 0) > 0;
    if ((!inFlight && v.changed !== true) || v.option === null) {
      this.#drafts.delete(key);
      this.#env.store.invalidate(topic);
      return { done: { saved: false } };
    }
    const textOf = (field: string) => (typeof next[field] === "string" ? next[field] : "");
    if (o.kind === "new" || o.kind === "session" || (o.kind === "connectNew" && o.form === "preset")) this.#keepUsual(ofAddress(station), next);
    let saved: Saved;
    switch (o.kind) {
      case "new":
        this.pickNew(ofAddress(station), {
          station: stationId(station),
          model: next.model,
          runtime: next.runtime,
          effort: textOf("effort"),
          profile: textOf("profile"),
          profiles: next.profiles ?? null,
          fast: next.fast,
          context: next.context,
        });
        saved = { done: { saved: true } };
        break;
      case "connectNew":
        this.#adding.set(`${station}\u0001${o.form}`, next);
        saved = { done: { saved: true } };
        break;
      case "session": {
        const params: J = { station, key: o.key, model: next.model, effort: next.effort, profile: next.profile };
        if (Array.isArray(next.profiles) && next.profiles.length > 1) params.profiles = next.profiles;
        if (next.runtime !== v.value.runtime) params.runtime = next.runtime;
        if (v.fastAvailable === true) params.fast = next.fast;
        if (arr(v.contexts).length > 0) params.context = next.context;
        const op = ops.request("session.settings", params);
        if (op === null) throw CoreError.invalid("session.settings");
        saved = { op };
        break;
      }
      case "connect": {
        const bind: J = { model: next.model, effort: textOf("effort"), profile: next.profile };
        if (Array.isArray(next.profiles) && next.profiles.length > 1) bind.profiles = next.profiles;
        if (next.runtime !== v.value.runtime) bind.runtime = next.runtime;
        const op = ops.request("connect.put", { station, id: o.id, input: { bind } });
        if (op === null) throw CoreError.invalid("connect.put");
        saved = { op };
        break;
      }
    }
    // (one asked of the station: what was picked shown until it is answered, the panel open as it is; dropped if it
    // fails, `unsaved`)
    if ("done" in saved) this.#drafts.delete(key);
    else this.#saving.set(key, (this.#saving.get(key) ?? 0) + 1);
    this.#changed();
    return saved;
  }

  /// A pick asked of the station that failed: the panel back to what it runs on.
  unsaved(station: string, oName: string): void {
    const key = topicKey({ topic: "pick", station, of: oName });
    if ((this.#saving.get(key) ?? 0) > 1) return;
    this.#drafts.delete(key);
    // (what was set by hand as it was before what failed)
    const was = this.#handWas.get(key);
    if (was !== undefined) {
      if (was === null) this.#hand.delete(key);
      else this.#hand.set(key, was);
      this.#handWas.delete(key);
    }
    this.#changed();
  }

  settled(station: string, oName: string): void {
    const key = topicKey({ topic: "pick", station, of: oName });
    const n = (this.#saving.get(key) ?? 0) - 1;
    if (n > 0) this.#saving.set(key, n);
    else this.#saving.delete(key);
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
    const subset = normProfiles(get(v.draft, "profiles"));
    const overview = this.#env.store.get({ topic: "overview", station });
    if (subset !== null && subset.length > 1 && overview !== undefined && get(overview, "accountSubsets") !== true) {
      throw CoreError.invalid(t("core-logic.choose.error.station_account_subsets"));
    }
    const repickParams: J =
      subset !== null && subset.length > 1
        ? { station, key: o.key, profiles: subset, repick: true }
        : { station, key: o.key, profile: null, repick: true };
    const op = ops.request("session.settings", repickParams);
    if (op === null) throw CoreError.invalid("session.settings");
    const agent = this.#env.agent(station, o.key);
    const was = get(get(agent, "account"), "id");
    const names = new Map(
      [...arr(get(agent, "profiles")), ...arr(v.accounts)].map((p) => [p.id, typeof p.name === "string" ? p.name : p.id]),
    );
    const draft = this.#drafts.get(topicKey(topic));
    if (draft !== undefined && subset === null) {
      if (v.value.profile === null && get(v.value, "profiles") === undefined) {
        delete draft.profile;
        delete draft.profiles;
      } else {
        draft.profile = null;
        draft.profiles = null;
      }
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

  /// What a connect being added will run on.
  adding(station: string, form: string): J {
    return this.#adding.get(`${station}\u0001${form}`);
  }
}

export { Effect };
