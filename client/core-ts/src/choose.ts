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
import { models, quotaLine } from "./views/models.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const TABLE = "choice";
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

/// Usage stays bounded on the device; ties favour the most recently started chat.
export function recordCombo(history: J[], choice: J, now: number): J[] {
  const same = (v: J) => ["model", "runtime", "effort"].every((f) => text(get(v, f)) === text(get(choice, f)));
  const found = history.find(same);
  const count = (typeof get(found, "count") === "number" ? found.count : 0) + 1;
  const out = history.filter((v) => !same(v));
  out.push({ model: get(choice, "model") ?? null, runtime: get(choice, "runtime") ?? null, effort: text(get(choice, "effort")), count, last: now });
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
    const r = resolve(options, { model: entry.model, runtime, effort, profile: current.profile });
    if (r.effort !== effort) continue;
    const m = typeof entry.model === "string" ? entry.model : null;
    if (m === null) continue;
    const key = JSON.stringify([m, runtime, effort]);
    if (seen.has(key)) continue;
    seen.add(key);
    const depth = effort ?? t("core-logic.choose.default_effort");
    const name = typeof entry.name === "string" ? entry.name : m;
    const label = arr(entry.runtimes).length > 1 ? `${name} · ${format.runtimeLabel(runtime)} · ${depth}` : `${name} · ${depth}`;
    const selected = current.entry !== null && current.entry.model === m && current.runtime === runtime && current.effort === effort;
    out.push({ model: m, runtime, effort, label, selected });
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
      sources =
        o?.kind === "session"
          ? [{ topic: "session", station, key: o.key }, { topic: "sessions", station }, { topic: "chatRows", station }, overview]
          : [overview];
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

  #newChat(scope: string): J {
    const kept = this.#kept(scope);
    const view: J = { kept, any: false, efforts: [], accounts: [], pickAccount: false, waiting: false, frequent: [] };
    const found = this.#online(scope);
    if (!Array.isArray(found)) {
      view.error = found.error;
      return view;
    }
    const [online, any] = found;
    view.any = any;
    const station = structuredClone(online.find((s) => s.id === kept) ?? online[0]);
    view.stations = online;
    if (station === undefined) return view;
    const id = typeof station.id === "string" ? station.id : "";
    const name = typeof station.name === "string" ? station.name : "";
    const options = arr(station.models);
    const r = resolve(options, this.#choice(scope, id));
    view.frequent = frequentCombos(arr(this.#record(`ws:${scope}:frequent`)), options, r);
    const overview = isObject(station.overview) ? station.overview : null;
    const profiles = overview !== null ? arr(overview.profiles) : [];
    view.waiting = overview === null;
    view.blocked = overview !== null && profiles.length === 0 ? "profile" : overview !== null && options.length === 0 ? "models" : null;
    view.problem = overview === null ? t("core-logic.choose.problem.loading", { name }) : profiles.length > 0 && options.length === 0 ? t("core-logic.choose.problem.no_models") : null;
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
    view.station = station;
    return view;
  }

  #onStation(addr: string): [J[], Resolved] {
    const overview = this.#env.store.get({ topic: "overview", station: addr });
    const options = models(overview, this.#env.now());
    return [options, resolve(options, this.#choice(ofAddress(addr), stationId(addr)))];
  }

  /// `newChat.pick`: the station a scope's new chat starts on, and what it runs there.
  pickNew(scope: string, params: J): void {
    const station = text(get(params, "station"));
    if (station !== null) this.#keepStation(scope, station);
    if (FIELDS.some((f) => get(params, f) !== undefined)) {
      let id: string;
      if (station !== null) id = station;
      else {
        const kept = this.#kept(scope);
        const found = this.#online(scope);
        if (!Array.isArray(found)) throw CoreError.invalid(t("core-logic.choose.error.no_stations_yet"));
        const current = found[0].find((s) => s.id === kept) ?? found[0][0];
        if (current === undefined) throw CoreError.invalid(t("core-logic.choose.error.none_online"));
        id = typeof current.id === "string" ? current.id : "";
      }
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
    this.#keepStation(ofAddress(station), stationId(station));
    this.#changed();
    return ask;
  }

  /// A new chat accepted by the core.
  used(station: string, choice: J): void {
    const key = `ws:${ofAddress(station)}:frequent`;
    this.#env.data.put(TABLE, key, recordCombo(arr(this.#record(key)), choice, this.#env.now()), false);
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

  #now(station: string, o: Of): [J[], J, J, boolean, boolean] | undefined {
    const overview = () => this.#env.store.get({ topic: "overview", station });
    const now = this.#env.now();
    switch (o.kind) {
      case "new": {
        const [options, r] = this.#onStation(station);
        if (overview() === undefined) return undefined;
        return [options, picked(r), null, false, true];
      }
      case "connectNew": {
        const ov = overview();
        if (ov === undefined) return undefined;
        const options = models(ov, now);
        const r = resolve(options, this.#adding.get(`${station}\u0001${o.form}`) ?? {});
        return [options, picked(r), null, false, false];
      }
      case "connect": {
        const ov = overview();
        if (ov === undefined) return undefined;
        const connect = arr(get(ov, "connects")).find((c) => c.id === o.id);
        if (connect === undefined) throw new CoreError("http_404", t("core-logic.choose.error.no_connect"), 404);
        const bind = connect.bind;
        const options = models(ov, now).filter((m) => arr(m.runtimes).some((r) => equal(r, get(bind, "runtime"))));
        return [options, { model: text(get(bind, "model")), runtime: get(bind, "runtime") ?? null, effort: text(get(bind, "effort")), profile: text(get(bind, "profile")) }, null, true, false];
      }
      case "session": {
        const agent = this.#env.agent(station, o.key);
        if (agent === null || agent === undefined) return undefined;
        const s = agent.session;
        const pinned = get(s, "profilePinned") === true;
        const value = { model: text(get(s, "model")), runtime: get(s, "runtime") ?? null, effort: text(get(s, "effort")), fast: get(s, "fast") ?? null, profile: pinned ? text(get(s, "profile")) : null };
        const current = isObject(agent.account) ? agent.account : null;
        return [arr(agent.choices), value, current, true, false];
      }
    }
  }

  #pick(topic: Topic, station: string, oName: string): Value | undefined {
    const o = of(oName);
    const now = this.#now(station, o);
    if (now === undefined) return undefined;
    const [options, value, current, fixed, quiet] = now;
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
    let saveText = changed ? t("core-logic.choose.save", { model: modelName ?? t("core-logic.format.default_model"), effort: effortText, account: chosenText }) : t("core-logic.choose.save.unchanged");
    if (changed && fastAvailable) saveText = `${saveText} · ${speedText(fast)}`;
    return {
      ok: {
        fastAvailable,
        fastText: effectiveFast ? "Fast" : null,
        options,
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

  /// `pick.save`: what the panel picked, made what it runs on.
  save(station: string, oName: string): Saved {
    const o = of(oName);
    const topic: Topic = { topic: "pick", station, of: oName };
    const view = this.#pick(topic, station, oName);
    if (view === undefined) throw CoreError.invalid(t("core-logic.choose.error.no_options_yet"));
    if ("err" in view) throw view.err;
    const v = view.ok as J;
    const next = v.next;
    if (v.changed !== true || v.option === null) {
      this.#drafts.delete(topicKey(topic));
      this.#env.store.invalidate(topic);
      return { done: { saved: false } };
    }
    const textOf = (field: string) => (typeof next[field] === "string" ? next[field] : "");
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
    this.#drafts.delete(topicKey(topic));
    this.#changed();
    return saved;
  }

  /// What a connect being added will run on (connect_flow.rs).
  adding(station: string, form: string): J {
    return this.#adding.get(`${station}\u0001${form}`);
  }
}

export { Effect };
