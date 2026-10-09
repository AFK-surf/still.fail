// The forms a page fills in while the core keeps what it has picked and typed (decision_form.rs, slack_tokens.rs,
// connect_flow.rs, profile_flow.rs): an automatic-decision rule, a Slack token form, the Slack connection wizard,
// the add-profile pages. A form is its UI's (by client): what it holds never enters the data kept on the device (keys
// and tokens stay in memory), and goes as its UI does.
import * as brand from "./brand.ts";
import { conform } from "./conform.ts";
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import * as present from "./present.ts";
import type { ClientId, Topic } from "./protocol.ts";
import { topicKey } from "./protocol.ts";
import * as model from "./shapes/model.ts";
import * as providers from "./shapes/providers.ts";
import type { Store, Value, Watch } from "./store.ts";
import { equal, get as getU, isObject } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const get = (v: unknown, k: string): J => getU(v, k);
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: J, or = ""): string => (typeof v === "string" ? v : or);

function overviewOf(store: Store, station: string): J {
  const v = store.value({ topic: "overview", station });
  if (v !== undefined && "err" in v) throw v.err;
  return v === undefined ? null : v.ok;
}

// ── an automatic-decision rule (decision_form.rs) ──

type DecisionDraft = { owner: ClientId; value: J; pickedModel: string | null; pending: boolean; watch: Watch };

/// The model control, with only verified decision candidates.
function modelPick(overview: J, value: J, pickedModel: string | null): J {
  const options = arr(get(get(overview, "automaticDecisions"), "models"))
    .filter((m) => typeof get(m, "id") === "string")
    .map((m) => ({ model: m.id, name: m.name ?? null, ids: [m.id], family: model.family(m.id), maker: present.maker(m.id), runtimes: [], efforts: {}, accounts: {} }))
    .sort((a, b) => model.compareOrder(a.model, b.model));
  const m = str(value.model);
  const picked = pickedModel ?? m;
  const chosen = options.find((o) => o.model === m);
  return {
    options,
    runtimeFixed: true,
    value: { model: m, runtime: "codex" },
    valueOption: chosen ?? null,
    draft: { model: picked, runtime: "codex" },
    option: picked,
    changed: picked !== m,
    runtimes: [],
    efforts: [],
    accounts: [],
    who: "",
    autoNote: "",
    was: [],
    becomes: [],
    modelText: chosen !== undefined ? chosen.name : m,
    accountText: "",
    accountNote: "",
    accountWarn: false,
    saveText: "",
  };
}

export class DecisionForms {
  readonly #store: Store;
  readonly #drafts = new Map<string, DecisionDraft>();

  constructor(store: Store) {
    this.#store = store;
  }

  disconnect(owner: ClientId): void {
    for (const [k, d] of [...this.#drafts]) {
      if (d.owner !== owner) continue;
      d.watch.drop();
      this.#drafts.delete(k);
    }
  }

  #saved(station: string): J {
    return get(get(get(overviewOf(this.#store, station), "automaticDecisions"), "settings"), "completion");
  }

  value(topic: Topic): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d) return null;
    const station = topic.station as string;
    if (!d.pending && d.value.dirty !== true) {
      const saved = this.#saved(station);
      if (isObject(saved)) {
        d.value.enabled = saved.enabled === true;
        d.value.model = str(saved.model);
      }
    }
    const value = structuredClone(d.value);
    value.pick = modelPick(overviewOf(this.#store, station), d.value, d.pickedModel);
    return value;
  }

  change(topic: Topic, owner: ClientId, action: string, patch: J): J {
    const station = topic.station as string;
    const key = topicKey(topic);
    if (action === "edit") this.value(topic);
    const existing = this.#drafts.get(key);
    if (existing && existing.owner !== owner) throw CoreError.invalid(t("core-misc.decisionForm.notYours"));
    if (action === "drop") {
      existing?.watch.drop();
      this.#drafts.delete(key);
      this.#store.invalidate(topic);
      return null;
    }
    let d = existing;
    if (!d) {
      const saved = this.#saved(station);
      const value = { enabled: get(saved, "enabled") === true, model: str(get(saved, "model")), dirty: false, pending: false };
      const watch = this.#store.watch({ topic: "overview", station }, () => this.#store.invalidate(topic));
      d = { owner, value, pickedModel: null, pending: false, watch };
      this.#drafts.set(key, d);
    }
    if (action === "edit") {
      if (d.pending) throw CoreError.invalid(t("core-misc.decisionForm.wait"));
      if (isObject(patch)) {
        if (patch.pickOpen === true) d.pickedModel = str(d.value.model);
        if (typeof patch.pickModel === "string") {
          const models = arr(get(get(overviewOf(this.#store, station), "automaticDecisions"), "models"));
          if (!models.some((m) => get(m, "id") === patch.pickModel)) throw CoreError.invalid(t("core-misc.decisionForm.modelGone"));
          d.pickedModel = patch.pickModel;
        }
        if (patch.pickConfirm === true && d.pickedModel !== null) {
          d.value.model = d.pickedModel;
          d.pickedModel = null;
        }
        for (const [k, v] of Object.entries(patch)) if (k === "enabled" || k === "model") d.value[k] = v;
        const saved = this.#saved(station);
        d.value.dirty = (d.value.enabled === true) !== (get(saved, "enabled") === true) || str(d.value.model) !== str(get(saved, "model"));
      }
    }
    this.#store.invalidate(topic);
    return structuredClone(d.value);
  }

  begin(topic: Topic, owner: ClientId): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.owner !== owner) throw CoreError.invalid(t("core-misc.decisionForm.closed"));
    if (d.pending) throw CoreError.invalid(t("core-misc.policy.saving"));
    const m = str(d.value.model) === "" ? null : d.value.model;
    if (d.value.enabled === true && m === null) throw CoreError.invalid(t("core-misc.decisionForm.pickModel"));
    d.pending = true;
    d.value.pending = true;
    this.#store.invalidate(topic);
    return { completion: { enabled: d.value.enabled ?? null, model: m } };
  }

  finish(topic: Topic, owner: ClientId, ok: boolean): void {
    const d = this.#drafts.get(topicKey(topic));
    if (d && d.owner === owner) {
      d.pending = false;
      d.value.pending = false;
      if (ok) d.value.dirty = false;
    }
    this.#store.invalidate(topic);
  }
}

// ── the archive policy, as one page edits it ──

type PolicyOption = { key: string; id: string | null; name: string; rubric: string; archive: boolean };
type PolicyDraft = { owner: ClientId; policy: string; options: PolicyOption[]; next: number; dirty: boolean; pending: boolean; watch: Watch };

/// The station's policy as it is now (its overview's), for a draft to start from and to tell whether it changed.
function savedPolicy(store: Store, station: string): { policy: string; options: Omit<PolicyOption, "key">[] } | null {
  const p = get(get(overviewOf(store, station), "automaticDecisions"), "policy");
  if (!isObject(p)) return null;
  return {
    policy: str(get(p, "text")),
    options: arr(get(p, "options")).map((o) => ({ id: str(get(o, "id")) || null, name: str(get(o, "name")), rubric: str(get(o, "rubric")), archive: get(o, "archive") === true })),
  };
}

const sameOptions = (a: Omit<PolicyOption, "key">[], b: Omit<PolicyOption, "key">[]) =>
  a.length === b.length && a.every((o, i) => o.id === b[i]!.id && o.name === b[i]!.name && o.rubric === b[i]!.rubric && o.archive === b[i]!.archive);

export class PolicyForms {
  readonly #store: Store;
  readonly #drafts = new Map<string, PolicyDraft>();

  constructor(store: Store) {
    this.#store = store;
  }

  disconnect(owner: ClientId): void {
    for (const [k, d] of [...this.#drafts]) {
      if (d.owner !== owner) continue;
      d.watch.drop();
      this.#drafts.delete(k);
    }
  }

  value(topic: Topic): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d) return null;
    // Not edited: follows the station's (changed elsewhere, by a person or an agent).
    if (!d.dirty && !d.pending) this.#reset(d, topic.station as string);
    return { policy: d.policy, options: d.options.map((o) => ({ ...o })), dirty: d.dirty, pending: d.pending };
  }

  #reset(d: PolicyDraft, station: string): void {
    const saved = savedPolicy(this.#store, station);
    if (!saved) return;
    d.policy = saved.policy;
    if (!sameOptions(d.options, saved.options)) d.options = saved.options.map((o) => ({ ...o, key: `o${d.next++}` }));
  }

  change(topic: Topic, owner: ClientId, action: string, patch: J): J {
    const station = topic.station as string;
    const key = topicKey(topic);
    const existing = this.#drafts.get(key);
    if (existing && existing.owner !== owner) throw CoreError.invalid(t("core-misc.policy.notYours"));
    if (action === "drop") {
      existing?.watch.drop();
      this.#drafts.delete(key);
      this.#store.invalidate(topic);
      return null;
    }
    let d = existing;
    if (!d) {
      const watch = this.#store.watch({ topic: "overview", station }, () => this.#store.invalidate(topic));
      d = { owner, policy: "", options: [], next: 0, dirty: false, pending: false, watch };
      this.#reset(d, station);
      this.#drafts.set(key, d);
    }
    if (action === "edit" && isObject(patch)) {
      if (d.pending) throw CoreError.invalid(t("core-misc.policy.saving"));
      if (patch.reset === true) {
        d.dirty = false;
        this.#reset(d, station);
      } else {
        this.#edit(d, patch);
        const saved = savedPolicy(this.#store, station);
        d.dirty = saved === null || saved.policy !== d.policy || !sameOptions(d.options, saved.options);
      }
    }
    this.#store.invalidate(topic);
    return this.value(topic);
  }

  #edit(d: PolicyDraft, patch: J): void {
    if (typeof patch.policy === "string") d.policy = patch.policy;
    const at = (k: unknown) => {
      const i = d.options.findIndex((o) => o.key === k);
      if (i < 0) throw CoreError.invalid(t("core-misc.policy.noOption"));
      return i;
    };
    if (typeof patch.add === "boolean") d.options.push({ key: `o${d.next++}`, id: null, name: "", rubric: "", archive: patch.add });
    if (typeof patch.remove === "string") d.options.splice(at(patch.remove), 1);
    if (typeof patch.option === "string") {
      const o = d.options[at(patch.option)]!;
      if (typeof patch.name === "string") o.name = patch.name;
      if (typeof patch.rubric === "string") o.rubric = patch.rubric;
      if (typeof patch.archive === "boolean") {
        // Moved to the other group: at its end.
        if (o.archive !== patch.archive) {
          d.options.splice(at(patch.option), 1);
          o.archive = patch.archive;
          d.options.push(o);
        }
      }
    }
  }

  begin(topic: Topic, owner: ClientId): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.owner !== owner) throw CoreError.invalid(t("core-misc.policy.closed"));
    if (d.pending) throw CoreError.invalid(t("core-misc.policy.saving"));
    d.pending = true;
    this.#store.invalidate(topic);
    return {
      policy: d.policy,
      options: d.options.map((o) => ({ ...(o.id !== null ? { id: o.id } : {}), name: o.name, rubric: o.rubric, archive: o.archive })),
    };
  }

  finish(topic: Topic, owner: ClientId, ok: boolean): void {
    const d = this.#drafts.get(topicKey(topic));
    if (d && d.owner === owner) {
      d.pending = false;
      if (ok) d.dirty = false;
    }
    this.#store.invalidate(topic);
  }
}

// ── a Slack token form (slack_tokens.rs) ──

type TokenDraft = { owner: ClientId; revision: number; checking: boolean; input: J; verified: J; errors: string[] };

function tokensShown(d: TokenDraft): J {
  const has = (f: string) => typeof d.input[f] === "string" && d.input[f] !== "";
  return {
    appToken: str(d.input.appToken),
    botToken: str(d.input.botToken),
    verified: d.verified,
    errors: [...d.errors],
    ready: has("appToken") || (!has("install") && has("botToken")) || has("connect"),
  };
}

export class Tokens {
  readonly #drafts = new Map<string, TokenDraft>();
  #next = 0;

  edit(topic: Topic, owner: ClientId, patch: J): J {
    const key = topicKey(topic);
    let d = this.#drafts.get(key);
    if (!d) {
      d = { owner, revision: 0, checking: false, input: { appToken: "", botToken: "", connect: null, install: null }, verified: null, errors: [] };
      this.#drafts.set(key, d);
    }
    if (d.owner !== owner) throw CoreError.invalid(t("core-misc.token.not_yours"));
    const old = d.input;
    const next = { ...old };
    for (const field of ["appToken", "botToken", "connect", "install"]) {
      const v = get(patch, field);
      if (v === undefined) continue;
      if (v !== null && typeof v !== "string") throw CoreError.invalid(t("core-misc.token.not_text"));
      next[field] = v;
    }
    d.input = next;
    if (d.revision === 0 || !equal(next, old) || get(patch, "clear") === true) {
      d.revision = ++this.#next;
      d.checking = false;
      d.verified = null;
      d.errors = [];
    }
    return tokensShown(d);
  }

  value(topic: Topic): J {
    const d = this.#drafts.get(topicKey(topic));
    return d ? tokensShown(d) : { appToken: "", botToken: "", verified: null, errors: [], ready: false };
  }

  input(topic: Topic, owner: ClientId): [J, boolean] {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.owner !== owner) throw CoreError.invalid(t("core-misc.token.closed"));
    return [structuredClone(d.input), d.verified !== null];
  }

  begin(topic: Topic, owner: ClientId): [number, J, boolean] {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.owner !== owner) throw CoreError.invalid(t("core-misc.token.closed"));
    if (d.checking) throw CoreError.invalid(t("core-misc.token.checking"));
    const verified = d.verified !== null;
    d.checking = !verified;
    return [d.revision, structuredClone(d.input), verified];
  }

  finish(topic: Topic, revision: number, answer: { ok: J } | { err: CoreError }): boolean {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.revision !== revision) return false;
    d.checking = false;
    if ("ok" in answer) {
      d.errors = arr(get(answer.ok, "errors")).filter((e): e is string => typeof e === "string");
      d.verified = d.errors.length === 0 ? (get(answer.ok, "identity") ?? null) : null;
    } else {
      d.errors = [answer.err.message];
      d.verified = null;
    }
    return "ok" in answer && d.errors.length === 0 && d.verified !== null;
  }

  drop(topic: Topic, owner: ClientId): void {
    const key = topicKey(topic);
    if (this.#drafts.get(key)?.owner === owner) this.#drafts.delete(key);
  }

  disconnect(owner: ClientId): string[] {
    const removed: string[] = [];
    for (const [k, d] of [...this.#drafts]) {
      if (d.owner !== owner) continue;
      this.#drafts.delete(k);
      removed.push(k);
    }
    return removed;
  }
}

// ── the Slack connection wizard (connect_flow.rs) ──

export const pickOf = (station: string, form: string): Topic => ({ topic: "pick", station, of: `connect-new:${form}` });
export const tokensOf = (station: string, form: string): Topic => ({ topic: "slackTokens", station, form });

function initial(input: J): J {
  const name = brand.name();
  return {
    step: typeof get(input, "resume") === "string" ? "install" : "team",
    resume: get(input, "resume") ?? null,
    mobile: get(input, "mobile") === true,
    team: null,
    adding: false,
    settings: {
      name,
      displayName: name,
      description: `Coding agent in your threads (${name})`,
      longDescription: "",
      backgroundColor: "#F3E3D3",
      groups: { base: true, public: true, dm: true, customize: true, files: true, reactions: true, channels: true, people: true, extras: true, canvases: true, lists: true, topics: true, usergroups: true, search: true, connect: true, more: true },
    },
    icon: null,
    iconError: null,
    madeId: get(input, "resume") ?? null,
    config: "",
    mode: "multi-session",
    requireMention: true,
  };
}

type FlowDraft = { owner: ClientId; generation: number; pending: boolean; value: J; watches: Watch[] };

/// What the wizard reads besides its own: the model control of the connect being added (choose.ts).
export type PickOf = (topic: Topic) => Value | undefined;

export class ConnectFlows {
  readonly #store: Store;
  readonly #pick: PickOf;
  readonly #clearPick: (station: string, form: string) => void;
  readonly #drafts = new Map<string, FlowDraft>();
  #next = 0;

  constructor(store: Store, pick: PickOf, clearPick: (station: string, form: string) => void) {
    this.#store = store;
    this.#pick = pick;
    this.#clearPick = clearPick;
  }

  open(topic: Topic, owner: ClientId, input: J): void {
    const key = topicKey(topic);
    const d = this.#drafts.get(key);
    if (d) {
      if (d.owner !== owner) throw CoreError.invalid(t("core-misc.connect.not_yours"));
      return;
    }
    const station = topic.station as string;
    const form = topic.form as string;
    const watches = [{ topic: "overview", station } as Topic, pickOf(station, form), tokensOf(station, form)].map((s) => this.#store.watch(s, () => this.#store.invalidate(topic)));
    this.#drafts.set(key, { owner, generation: ++this.#next, pending: false, value: initial(input), watches });
    this.#store.invalidate(topic);
  }

  drop(topic: Topic, owner: ClientId): void {
    const key = topicKey(topic);
    const d = this.#drafts.get(key);
    if (d && d.owner === owner) {
      this.#drafts.delete(key);
      for (const w of d.watches) w.drop();
      this.#clearPick(topic.station as string, topic.form as string);
    }
    this.#store.invalidate(topic);
  }

  disconnect(owner: ClientId): Topic[] {
    const gone: Topic[] = [];
    for (const [k, d] of [...this.#drafts]) {
      if (d.owner !== owner) continue;
      const topic = JSON.parse(k) as Topic;
      gone.push(topic);
      this.drop(topic, owner);
    }
    return gone;
  }

  #own(topic: Topic, owner: ClientId): FlowDraft {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.owner !== owner) throw CoreError.invalid(t("core-misc.connect.closed"));
    return d;
  }

  edit(topic: Topic, owner: ClientId, patch: J): void {
    const d = this.#own(topic, owner);
    if (d.pending) throw CoreError.invalid(t("core-misc.connect.busy"));
    if (get(patch, "settings") !== undefined) {
      const checked = conform("ConnectAppSettings", patch.settings);
      if ("error" in checked) throw CoreError.invalid(t("core-misc.connect.bad_settings", { error: checked.error }));
    }
    for (const field of ["team", "icon", "iconError"]) {
      const v = get(patch, field);
      if (v !== undefined && v !== null && typeof v !== "string") throw CoreError.invalid(t("core-misc.params.not_text"));
    }
    if (get(patch, "config") !== undefined && typeof patch.config !== "string") throw CoreError.invalid(t("core-misc.connect.config_not_text"));
    for (const field of ["adding", "requireMention"]) if (get(patch, field) !== undefined && typeof patch[field] !== "boolean") throw CoreError.invalid(t("core-misc.params.not_bool"));
    if (get(patch, "mode") !== undefined && patch.mode !== "single-session" && patch.mode !== "multi-session") throw CoreError.invalid(t("core-misc.connect.no_such_mode"));
    for (const field of ["team", "adding", "settings", "icon", "iconError", "config", "mode", "requireMention"]) if (get(patch, field) !== undefined) d.value[field] = patch[field];
    if (typeof get(patch, "config") === "string") d.value.config = patch.config.trim();
    this.#store.invalidate(topic);
  }

  go(topic: Topic, owner: ClientId, to: string): J {
    const view = this.value(topic);
    const target = to === "back" ? str(view.back, "close") : to;
    if (target === "close") return { close: true };
    const step = str(view.step, "team");
    const allowed =
      to === "back" ||
      (step === "team" && (target === "token" || target === "manual")) ||
      (step === "team" && target === "app" && view.chosen !== null) ||
      ((step === "app" || step === "manual") && target === "team") ||
      (step === "bind" && (target === "install" || target === "manual"));
    if (!allowed) throw CoreError.invalid(t("core-misc.connect.not_ready"));
    const d = this.#own(topic, owner);
    if (d.pending) throw CoreError.invalid(t("core-misc.connect.busy"));
    d.value.step = target;
    this.#store.invalidate(topic);
    return {};
  }

  value(topic: Topic): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d) throw CoreError.invalid(t("core-misc.connect.closed"));
    const v = structuredClone(d.value);
    const station = topic.station as string;
    const form = topic.form as string;
    const overview = this.#store.get({ topic: "overview", station }) as J;
    const teams = arr(get(overview, "slackTeams"));
    const chosen = teams.find((x) => equal(get(x, "teamId"), v.team)) ?? (teams.length === 1 ? teams[0] : undefined) ?? null;
    const made = arr(get(overview, "slackApps")).find((a) => equal(get(a, "appId"), v.madeId)) ?? null;
    const p = this.#pick(pickOf(station, form));
    if (p !== undefined && "err" in p) throw p.err;
    const picked = p !== undefined ? p.ok : null;
    const step = str(v.step, "team");
    const mobile = v.mobile === true;
    const title =
      step === "team" && !mobile && teams.length === 0
        ? "core-misc.connect.title.get_token"
        : step === "team" && !mobile && v.adding === true
          ? "core-misc.connect.title.add_token"
          : step === "team"
            ? "core-misc.connect.title.team"
            : ["token", "app", "install", "manual"].includes(step)
              ? `core-misc.connect.title.${step}`
              : "core-misc.connect.title.bind";
    const order = step === "manual" || (step === "bind" && (v.madeId === null || v.madeId === undefined)) ? ["manual", "bind"] : ["team", "app", "install", "bind"];
    const back =
      step === "team"
        ? "close"
        : step === "token" || step === "app" || step === "manual"
          ? "team"
          : step === "install" && typeof v.resume === "string"
            ? "close"
            : step === "install"
              ? "app"
              : typeof v.madeId === "string"
                ? "install"
                : "manual";
    v.title = t(title);
    v.back = back;
    v.number = order.indexOf(step) >= 0 ? order.indexOf(step) + 1 : 1;
    v.total = order.length;
    v.gettingToken = step === "team" && !mobile && (teams.length === 0 || v.adding === true);
    v.noProfile = (v.resume === null || v.resume === undefined) && Array.isArray(get(overview, "profiles")) && overview.profiles.length === 0;
    v.configReady = typeof v.config === "string" && v.config.startsWith("xoxe-1-") && v.config.length > 20;
    v.configError = typeof v.config === "string" && v.config.startsWith("xoxe.xoxp-") ? t("core-misc.connect.access_token") : null;
    v.canMake = chosen !== null && typeof get(v.settings, "name") === "string" && v.settings.name.trim() !== "";
    v.canCreate = picked !== null && get(picked, "valueOption") !== null && get(picked, "valueOption") !== undefined;
    v.teams = teams;
    v.chosen = chosen;
    v.made = made;
    v.pick = picked;
    return v;
  }

  /// Captures one operation: its answer can advance only this instance of the form.
  begin(topic: Topic, owner: ClientId, action: string, tokenInput: J, verified: boolean): [number, string, J] {
    const v = this.value(topic);
    const station = topic.station as string;
    const step = str(v.step);
    let name: string;
    let p: J;
    if (action === "config" && (step === "token" || v.gettingToken === true) && v.configReady === true) [name, p] = ["slack.addConfigToken", { refreshToken: v.config }];
    else if (action === "make" && step === "app" && v.canMake === true) [name, p] = ["slack.makeApp", { team: get(v.chosen, "teamId") ?? null, settings: v.settings, icon: v.icon ?? null }];
    else if (action === "verify" && (step === "install" || step === "manual")) [name, p] = ["slack.verify", { ...tokenInput, install: get(v.made, "state") ?? null }];
    else if (action === "create" && step === "bind" && v.canCreate === true && verified) {
      let slack: J = { ...tokenInput };
      if (typeof get(v.made, "state") === "string") slack = { appToken: tokenInput.appToken ?? null, install: v.made.state };
      else if (typeof get(v.made, "appId") === "string") slack.appId = v.made.appId;
      const bind = structuredClone(get(v.pick, "value") ?? {});
      for (const f of ["model", "effort"]) if (bind[f] === null || bind[f] === undefined) bind[f] = "";
      [name, p] = ["connect.create", { input: { kind: "slack", mode: v.mode, requireMention: v.requireMention, bind, slack } }];
    } else throw CoreError.invalid(t("core-misc.connect.not_ready"));
    p.station = station;
    const d = this.#own(topic, owner);
    if (d.pending) throw CoreError.invalid(t("core-misc.connect.working"));
    d.pending = true;
    return [d.generation, name, p];
  }

  finish(topic: Topic, generation: number, action: string, result: { ok: J } | { err: CoreError }): boolean {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.generation !== generation) return false;
    d.pending = false;
    if ("ok" in result) {
      const r = result.ok;
      if (action === "config") Object.assign(d.value, { team: get(r, "teamId") ?? null, config: "", adding: false, step: "app" });
      else if (action === "make") Object.assign(d.value, { madeId: get(r, "appId") ?? null, iconError: get(r, "iconError") ?? null, step: "install" });
      else if (action === "create") d.value.step = "done";
      else if (action === "verify" && get(r, "identity") !== undefined && r.identity !== null && Array.isArray(get(r, "errors")) && r.errors.length === 0) d.value.step = "bind";
    }
    this.#store.invalidate(topic);
    return true;
  }
}

// ── the add-profile pages (profile_flow.rs) ──

const usesNames = (u: providers.Uses) => ([[u.claude, "claude"], [u.codex, "codex"], [u.decision, "decision"]] as [boolean, string][]).filter(([on]) => on).map(([, id]) => id);
const usesTextOf = (ids: string[]) => ids.map((u) => (u === "claude" ? t("core-views.present.uses.claude") : u === "codex" ? t("core-views.present.uses.codex") : t("core-views.present.uses.decision"))).join(" · ");
const runtimeName = (r: string) => (r === "claude" ? "Claude Code" : "Codex");

function usesOf(source: providers.Source, endpoint: string | null, protocol: string | null): string[] {
  const own = source.endpointRequired ? (endpoint ?? providers.example(source.id)) : null;
  const p = protocol ?? source.protocols?.[0] ?? null;
  const at = providers.endpoints(source, own, source.endpointRequired ? p : null);
  return at !== null ? usesNames(providers.uses(at)) : [];
}

function tileOf(source: providers.Source, hasKey: boolean, hasPlan: boolean): J {
  const kind = source.legacy === "opencode-go" ? "opencode-go" : source.legacy === "anthropic-api" ? "anthropic-api" : "api-provider";
  const runtime = source.id === "openai" ? "codex" : source.id === "anthropic" ? "claude" : null;
  const uses = usesOf(source, null, null);
  const cn = providers.chinaOf(source.id);
  return {
    id: source.id,
    name: source.name,
    group: source.group,
    mark: source.mark,
    kind,
    hasKey,
    hasPlan,
    runtime,
    endpointRequired: source.endpointRequired === true,
    endpointExample: providers.example(source.id),
    protocols: source.protocols ?? [],
    keyOptional: source.keyOptional === true,
    uses,
    usesText: usesTextOf(uses),
    regions: cn !== null ? [{ id: source.id, label: t("core-views.flow.region.global") }, { id: cn, label: t("core-views.flow.region.china") }] : [],
  };
}

/// The picker's groups: every provider the station can take a key for, those with a plan, the variables by hand.
export function groups(supported: string[] | null): J[] {
  const listed = (id: string) => supported !== null && supported.includes(id);
  const out: J[] = [];
  for (const group of providers.GROUPS) {
    const tiles = providers.SOURCES.filter((s) => s.group === group && !providers.isChinaVariant(s.id)).flatMap((s) => {
      const hasKey = s.legacy !== undefined || listed(s.id);
      const hasPlan = s.id === "openai" || s.id === "anthropic";
      return hasKey || hasPlan ? [tileOf(s, hasKey, hasPlan)] : [];
    });
    if (group === "local") {
      for (const runtime of ["claude", "codex"]) {
        const uses = [runtime];
        tiles.push({ id: `env-${runtime}`, name: t("core-views.flow.env", { runtime: runtimeName(runtime) }), group: "local", kind: "env", hasKey: false, hasPlan: false, runtime, endpointRequired: false, protocols: [], keyOptional: true, uses, usesText: usesTextOf(uses) });
      }
    }
    if (tiles.length > 0) out.push({ id: group, title: t(`core-views.flow.group.${group}`), providers: tiles });
  }
  return out;
}

function supportedOf(overview: J): string[] | null {
  const list = get(overview, "apiProviders");
  return Array.isArray(list) ? list.flatMap((p) => (typeof get(p, "id") === "string" ? [p.id] : [])) : null;
}

const findTile = (gs: J[], id: string): J => gs.flatMap((g) => arr(g.providers)).find((p) => p.id === id);
const blank = () => ({ provider: "", method: "", endpoint: "", protocol: "", region: "", key: "", error: null, pending: false });

function profileView(station: string, draft: J, overview: J): J {
  const gs = groups(supportedOf(overview));
  const tile = typeof draft.provider === "string" ? findTile(gs, draft.provider) : undefined;
  const method = typeof draft.method === "string" && draft.method !== "" ? draft.method : null;
  const out: J = {
    step: "pick", station, title: t("core-views.flow.pick"), hint: t("core-views.flow.pick_hint"), groups: gs, tile: tile ?? null, method, choices: [], showEndpoint: false,
    endpoint: draft.endpoint ?? null, protocols: [], regions: [], region: null, showKey: false, key: draft.key ?? null, keyLabel: "", canSubmit: false, pending: draft.pending === true,
    submitLabel: "", usesLine: "", error: draft.error ?? null,
  };
  if (tile === undefined) return out;
  const name = str(tile.name);
  out.title = t("core-views.flow.connect", { name });
  out.hint = "";
  const runtime = str(tile.runtime, "claude");
  if (method === null) {
    const plan = runtime === "claude" ? "Claude" : "ChatGPT";
    out.step = "method";
    out.choices = [
      { id: "plan", title: t("core-views.flow.plan", { plan }), hint: t(`core-views.flow.plan_hint.${runtime}`) },
      { id: "key", title: t("core-views.flow.key_card"), hint: t("core-views.flow.key_card_hint", { name }) },
    ];
    return out;
  }
  out.step = "connect";
  const kind = str(tile.kind, "api-provider");
  if (method === "plan") {
    out.usesLine = t("core-views.flow.uses", { uses: runtimeName(runtime) });
    return out;
  }
  if (kind === "env") {
    out.usesLine = t("core-views.flow.uses", { uses: runtimeName(runtime) });
    out.canSubmit = draft.pending !== true;
    out.submitLabel = t("core-views.flow.add");
    return out;
  }
  const regions: string[] = arr(tile.regions).flatMap((r) => (typeof r.id === "string" ? [r.id] : []));
  const region = regions.length > 0 ? (typeof draft.region === "string" && regions.includes(draft.region) ? draft.region : regions[0]) : null;
  if (region !== null) {
    out.regions = tile.regions;
    out.region = region;
  }
  const sourceId = region ?? str(tile.id);
  const own = tile.endpointRequired === true;
  const protocols: string[] = arr(tile.protocols).filter((p): p is string => typeof p === "string");
  const protocol = own ? (typeof draft.protocol === "string" && protocols.includes(draft.protocol) ? draft.protocol : (protocols[0] ?? null)) : null;
  const endpoint = str(draft.endpoint).trim();
  const keyOptional = tile.keyOptional === true;
  out.showEndpoint = own;
  out.endpointHint = own && typeof tile.endpointExample === "string" ? t("core-views.flow.endpoint_hint", { example: tile.endpointExample }) : null;
  if (own && protocols.length > 1) out.protocols = protocols.map((p) => ({ id: p, label: t(`core-views.flow.protocol.${p}`) }));
  out.protocol = protocol;
  out.showKey = true;
  out.keyLabel = keyOptional ? t("core-views.flow.key_optional") : t("core-views.flow.key");
  out.keyHint = t("core-views.flow.key_notice");
  const keyOk = keyOptional || str(draft.key).trim() !== "";
  const endpointOk = !own || providers.cleanEndpoint(endpoint) !== null;
  out.canSubmit = draft.pending !== true && keyOk && endpointOk;
  const source = providers.find(sourceId);
  const untried = source !== null && !!source.decision && !source.chat && !source.responses && !source.anthropic;
  out.submitLabel = untried ? t("core-views.flow.add") : t("core-views.flow.verify_add");
  const uses = source !== null ? usesOf(source, endpoint !== "" ? endpoint : null, protocol) : [];
  out.usesLine = uses.length === 0 ? t("core-views.flow.uses_none") : t("core-views.flow.uses", { uses: usesTextOf(uses) });
  return out;
}

type ProfileDraft = { owner: ClientId; value: J; pending: boolean; watch: Watch };

export class ProfileFlows {
  readonly #store: Store;
  readonly #drafts = new Map<string, ProfileDraft>();

  constructor(store: Store) {
    this.#store = store;
  }

  disconnect(owner: ClientId): void {
    for (const [k, d] of [...this.#drafts]) {
      if (d.owner !== owner) continue;
      d.watch.drop();
      this.#drafts.delete(k);
    }
  }

  value(topic: Topic): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d) return null;
    const station = topic.station as string;
    return profileView(station, d.value, overviewOf(this.#store, station));
  }

  change(topic: Topic, owner: ClientId, action: string, patch: J): J {
    const station = topic.station as string;
    const key = topicKey(topic);
    const existing = this.#drafts.get(key);
    if (existing && existing.owner !== owner) throw CoreError.invalid(t("core-views.flow.not_yours"));
    if (action === "drop") {
      existing?.watch.drop();
      this.#drafts.delete(key);
      this.#store.invalidate(topic);
      return null;
    }
    let d = existing;
    if (!d) {
      const watch = this.#store.watch({ topic: "overview", station }, () => this.#store.invalidate(topic));
      d = { owner, value: blank(), pending: false, watch };
      this.#drafts.set(key, d);
    }
    if (action === "edit") {
      if (d.pending) throw CoreError.invalid(t("core-views.flow.wait"));
      const gs = groups(supportedOf(overviewOf(this.#store, station)));
      if (!isObject(patch)) return null;
      if (typeof patch.provider === "string") {
        if (patch.provider === "") d.value = blank();
        else {
          const tile = findTile(gs, patch.provider);
          if (tile === undefined) throw CoreError.invalid(t("core-views.flow.unknown_provider"));
          const method = tile.hasKey === true && tile.hasPlan === true ? "" : tile.hasPlan === true ? "plan" : "key";
          d.value = { ...blank(), provider: patch.provider, method };
        }
      }
      if (typeof patch.method === "string") {
        if (!["", "plan", "key"].includes(patch.method)) throw CoreError.invalid(t("core-views.flow.unknown_provider"));
        d.value.method = patch.method;
      }
      if (patch.back === true) {
        const tile = typeof d.value.provider === "string" ? findTile(gs, d.value.provider) : undefined;
        const both = tile !== undefined && tile.hasKey === true && tile.hasPlan === true;
        if (both && typeof d.value.method === "string" && d.value.method !== "") d.value.method = "";
        else d.value = blank();
      }
      for (const field of ["endpoint", "protocol", "region", "key"]) {
        if (typeof patch[field] === "string") {
          d.value[field] = patch[field];
          d.value.error = null;
        }
      }
    }
    this.#store.invalidate(topic);
    return null;
  }

  /// The `profile.add` input of a draft ready to be submitted; the page waits meanwhile.
  begin(topic: Topic, owner: ClientId): J {
    const station = topic.station as string;
    const overview = overviewOf(this.#store, station);
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.owner !== owner) throw CoreError.invalid(t("core-views.flow.closed"));
    if (d.pending) throw CoreError.invalid(t("core-views.flow.wait"));
    const shown = profileView(station, d.value, overview);
    if (shown.step !== "connect" || shown.canSubmit !== true) throw CoreError.invalid(t("core-views.flow.incomplete"));
    const tile = shown.tile;
    const kind = str(tile.kind, "api-provider");
    let input: J;
    if (kind === "env") input = { runtime: tile.runtime ?? null, access: { kind: "env" } };
    else {
      const access: J = { kind };
      const k = str(d.value.key).trim();
      if (k !== "") access.key = k;
      if (kind === "api-provider") {
        access.provider = typeof shown.region === "string" ? shown.region : (tile.id ?? null);
        if (shown.showEndpoint === true) {
          access.endpoint = str(d.value.endpoint).trim();
          if (typeof shown.protocol === "string") access.protocol = shown.protocol;
        }
      }
      input = { access };
    }
    d.pending = true;
    d.value.pending = true;
    d.value.error = null;
    this.#store.invalidate(topic);
    return input;
  }

  finish(topic: Topic, owner: ClientId, error: CoreError | null): void {
    const d = this.#drafts.get(topicKey(topic));
    if (d && d.owner === owner) {
      d.pending = false;
      d.value.pending = false;
      if (error !== null) d.value.error = error.message;
    }
    this.#store.invalidate(topic);
  }
}
