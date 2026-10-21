// The forms a page fills in while the core keeps what it has picked and typed (decision_form.rs, slack_tokens.rs,
// connect_flow.rs, profile_flow.rs): an automatic-decision rule, a Slack token form, the Slack connection wizard,
// the add-profile pages. A form is its UI's (by client): what it holds never enters the data kept on the device (keys
// and tokens stay in memory), and goes as its UI does.
import * as brand from "./brand.ts";
import { conform } from "./conform.ts";
import { CoreError } from "./error.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import * as present from "./present.ts";
import type { ClientId, Topic } from "./protocol.ts";
import { topicKey } from "./protocol.ts";
import * as model from "./shapes/model.ts";
import * as providers from "./shapes/providers.ts";
import { qr } from "./qr.ts";
import type { Store, Value, Watch } from "./store.ts";
import { equal, get as getU, isObject } from "./util.ts";
import { ofAddress } from "./workspace.ts";

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

/// The Feishu path's own: an app of one's own (its App ID and Secret, Lark or not, as last verified) or one being made
/// by scanning (`registration`, as it was started: the overview says how it goes), and the connect it became.
const feishuBlank = (): J => ({
  way: "scan", appId: "", appSecret: "", lark: false, identity: null, errors: [], checked: null,
  registration: null, registered: null, tried: null, creating: false, error: null, connect: null,
});

/// What a verification was of: it holds while they stay the same.
const feishuKey = (f: J) => JSON.stringify([str(f.appId).trim(), str(f.appSecret).trim(), f.lark === true]);

const FEISHU_STEPS = ["feishuBind", "feishuWay", "feishuScan", "feishuApp"];

function initial(input: J): J {
  const name = brand.name();
  const resume = typeof get(input, "resume") === "string";
  return {
    // Where the station has the Feishu connect, the platform first (value: a station without it starts at Slack).
    step: resume ? "install" : "platform",
    platform: resume ? "slack" : null,
    feishu: feishuBlank(),
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

/// What the wizard has done beside its own calls: a Feishu bot being made let go of (`cancel`, the station's
/// registration), and the overview changed (`ready`: its bot made, the connect is added without being asked).
export type FlowHooks = { cancel(station: string, registration: string): void; ready(topic: Topic): void };

/// A registration's state as the station follows it (the overview), else as it was started.
function registrationOf(overview: J, f: J): J {
  if (typeof get(f, "registration") !== "string") return null;
  return arr(get(overview, "feishuRegistrations")).find((r) => get(r, "id") === f.registration) ?? f.registered ?? null;
}

/// What the wizard reads besides its own: the model control of the connect being added (choose.ts).
export type PickOf = (topic: Topic) => Value | undefined;

export class ConnectFlows {
  readonly #store: Store;
  readonly #pick: PickOf;
  readonly #clearPick: (station: string, form: string) => void;
  readonly #drafts = new Map<string, FlowDraft>();
  #next = 0;

  readonly #hooks: FlowHooks;

  constructor(store: Store, pick: PickOf, clearPick: (station: string, form: string) => void, hooks: FlowHooks = { cancel: () => {}, ready: () => {} }) {
    this.#store = store;
    this.#pick = pick;
    this.#clearPick = clearPick;
    this.#hooks = hooks;
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
    const watches = [{ topic: "overview", station } as Topic, pickOf(station, form), tokensOf(station, form)].map((s) =>
      this.#store.watch(s, () => {
        this.#store.invalidate(topic);
        if (s.topic === "overview") this.#hooks.ready(topic);
      }),
    );
    this.#drafts.set(key, { owner, generation: ++this.#next, pending: false, value: initial(input), watches });
    this.#store.invalidate(topic);
  }

  drop(topic: Topic, owner: ClientId): void {
    const key = topicKey(topic);
    const d = this.#drafts.get(key);
    if (d && d.owner === owner) {
      this.#letGo(topic, d);
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

  /// Its Feishu bot still waiting to be made by scanning: the station stops waiting for it.
  #letGo(topic: Topic, d: FlowDraft): void {
    const station = topic.station as string;
    let overview: J = null;
    try {
      overview = overviewOf(this.#store, station);
    } catch {
      // Not read: as it was started.
    }
    const r = registrationOf(overview, d.value.feishu);
    if (r !== null && get(r, "state") === "waiting") this.#hooks.cancel(station, str(get(r, "id")));
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
    const platform = get(patch, "platform");
    if (platform !== undefined && platform !== "slack" && platform !== "feishu") throw CoreError.invalid(t("core-misc.connect.not_ready"));
    const feishu = get(patch, "feishu");
    if (feishu !== undefined) {
      if (!isObject(feishu)) throw CoreError.invalid(t("core-misc.params.not_text"));
      for (const field of ["appId", "appSecret"]) if (get(feishu, field) !== undefined && typeof feishu[field] !== "string") throw CoreError.invalid(t("core-misc.params.not_text"));
      if (get(feishu, "lark") !== undefined && typeof feishu.lark !== "boolean") throw CoreError.invalid(t("core-misc.params.not_bool"));
      if (get(feishu, "way") !== undefined && feishu.way !== "scan" && feishu.way !== "app") throw CoreError.invalid(t("core-misc.connect.not_ready"));
      for (const field of ["way", "appId", "appSecret", "lark"]) if (get(feishu, field) !== undefined) d.value.feishu[field] = feishu[field];
    }
    for (const field of ["team", "adding", "settings", "icon", "iconError", "config", "mode", "requireMention", "platform"]) if (get(patch, field) !== undefined) d.value[field] = patch[field];
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
      (step === "platform" && (target === "team" || (target === "feishuBind" && view.platforms.includes("feishu")))) ||
      (step === "feishuBind" && target === "feishuWay" && view.canCreate === true) ||
      (step === "feishuWay" && target === "feishuApp") ||
      ((step === "feishuScan" || step === "feishuApp") && target === "feishuWay") ||
      (step === "team" && (target === "token" || target === "manual")) ||
      (step === "team" && target === "app" && view.chosen !== null) ||
      ((step === "app" || step === "manual") && target === "team") ||
      (step === "bind" && (target === "install" || target === "manual"));
    if (!allowed) throw CoreError.invalid(t("core-misc.connect.not_ready"));
    const d = this.#own(topic, owner);
    if (d.pending) throw CoreError.invalid(t("core-misc.connect.busy"));
    if (step === "feishuScan" && target !== "feishuScan") this.#letGo(topic, d);
    if (step === "platform") d.value.platform = target === "team" ? "slack" : "feishu";
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
    // A station without the Feishu connect (one from before it) says no `feishuRegistrations`: Slack's at once.
    const feishuOffered = Array.isArray(get(overview, "feishuRegistrations"));
    v.platforms = feishuOffered ? ["slack", "feishu"] : ["slack"];
    let step = str(v.step, "team");
    if (step === "platform" && !feishuOffered) step = "team";
    v.step = step;
    const feishu = v.platform === "feishu" && (FEISHU_STEPS.includes(step) || step === "done");
    const mobile = v.mobile === true;
    const title = step === "platform" ? "core-misc.connect.title.platform"
      : step === "feishuBind" ? "core-misc.connect.title.bind"
      : FEISHU_STEPS.includes(step) ? `core-misc.connect.title.${step}`
      : step === "team" && !mobile && teams.length === 0
        ? "core-misc.connect.title.get_token"
        : step === "team" && !mobile && v.adding === true
          ? "core-misc.connect.title.add_token"
          : step === "team"
            ? "core-misc.connect.title.team"
            : ["token", "app", "install", "manual"].includes(step)
              ? `core-misc.connect.title.${step}`
              : "core-misc.connect.title.bind";
    const slackOrder = step === "manual" || (step === "bind" && (v.madeId === null || v.madeId === undefined)) ? ["manual", "bind"] : ["team", "app", "install", "bind"];
    const order = feishu
      ? ["platform", "feishuBind", "feishuWay", step === "feishuApp" ? "feishuApp" : "feishuScan"]
      : feishuOffered && typeof v.resume !== "string" ? ["platform", ...slackOrder] : slackOrder;
    const back =
      step === "platform" ? "close"
        : step === "feishuBind" ? "platform"
        : step === "feishuWay" ? "feishuBind"
        : step === "feishuScan" || step === "feishuApp" ? "feishuWay"
        : step === "team"
        ? feishuOffered && typeof v.resume !== "string" ? "platform" : "close"
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
    v.feishu = feishuView(v.feishu, overview, d.pending);
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
    else if (action === "register" && (step === "feishuWay" || (step === "feishuScan" && v.feishu.failed === true))) [name, p] = ["feishu.register", {}];
    else if (action === "verify" && step === "feishuApp" && v.feishu.canVerify === true) [name, p] = ["feishu.verify", feishuApp(v.feishu)];
    else if (action === "create" && v.canCreate === true && ((step === "feishuApp" && v.feishu.verified === true) || (step === "feishuScan" && get(v.feishu.registration, "state") === "done"))) {
      const app = step === "feishuApp" ? feishuApp(v.feishu) : { registration: get(v.feishu.registration, "id") };
      [name, p] = ["feishu.createConnect", { feishu: app, bind: bindOf(v.pick), mode: v.mode, requireMention: v.requireMention }];
    }
    else if (action === "create" && step === "bind" && v.canCreate === true && verified) {
      let slack: J = { ...tokenInput };
      if (typeof get(v.made, "state") === "string") slack = { appToken: tokenInput.appToken ?? null, install: v.made.state };
      else if (typeof get(v.made, "appId") === "string") slack.appId = v.made.appId;
      [name, p] = ["connect.create", { input: { kind: "slack", mode: v.mode, requireMention: v.requireMention, bind: bindOf(v.pick), slack } }];
    } else throw CoreError.invalid(t("core-misc.connect.not_ready"));
    p.station = station;
    const d = this.#own(topic, owner);
    if (d.pending) throw CoreError.invalid(t("core-misc.connect.working"));
    d.pending = true;
    if (name === "feishu.createConnect") Object.assign(d.value.feishu, { creating: true, error: null });
    if (name === "feishu.register") d.value.feishu.error = null;
    this.#store.invalidate(topic);
    return [d.generation, name, p];
  }

  /// Whose form it is (one known).
  ownerOf(topic: Topic): ClientId {
    const d = this.#drafts.get(topicKey(topic));
    if (!d) throw CoreError.invalid(t("core-misc.connect.closed"));
    return d.owner;
  }

  /// Its bot made by scanning and nothing tried with it yet: the connect is to be added now (once for each bot made).
  ready(topic: Topic): boolean {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.pending || d.value.platform !== "feishu" || d.value.step !== "feishuScan") return false;
    let v: J;
    try {
      v = this.value(topic);
    } catch {
      return false;
    }
    const r = v.feishu.registration;
    if (get(r, "state") !== "done" || v.canCreate !== true || d.value.feishu.tried === get(r, "id")) return false;
    d.value.feishu.tried = get(r, "id");
    return true;
  }

  finish(topic: Topic, generation: number, action: string, result: { ok: J } | { err: CoreError }): boolean {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.generation !== generation) return false;
    d.pending = false;
    if (action === "create") d.value.feishu.creating = false;
    if ("err" in result && d.value.platform === "feishu" && (action === "create" || action === "register")) d.value.feishu.error = result.err.message;
    if ("ok" in result) {
      const r = result.ok;
      if (action === "config") Object.assign(d.value, { team: get(r, "teamId") ?? null, config: "", adding: false, step: "app" });
      else if (action === "make") Object.assign(d.value, { madeId: get(r, "appId") ?? null, iconError: get(r, "iconError") ?? null, step: "install" });
      else if (action === "register") {
        const registered = { id: get(r, "id"), url: get(r, "url"), expiresAt: get(r, "expiresAt"), state: "waiting" };
        Object.assign(d.value.feishu, { registration: get(r, "id") ?? null, registered, tried: null, error: null, connect: null });
        d.value.step = "feishuScan";
      }
      else if (action === "create" && d.value.platform === "feishu" && FEISHU_STEPS.includes(d.value.step)) {
        d.value.feishu.connect = get(r, "id") ?? null;
        d.value.step = "done";
      }
      else if (action === "create") d.value.step = "done";
      else if (action === "verify" && d.value.step === "feishuApp") Object.assign(d.value.feishu, { identity: get(r, "identity") ?? null, errors: arr(get(r, "errors")).filter((e) => typeof e === "string"), checked: feishuKey(d.value.feishu) });
      else if (action === "verify" && get(r, "identity") !== undefined && r.identity !== null && Array.isArray(get(r, "errors")) && r.errors.length === 0) d.value.step = "bind";
    }
    this.#store.invalidate(topic);
    return true;
  }
}

/// What a connect being added runs on, from its model control.
function bindOf(pick: J): J {
  const bind = structuredClone(get(pick, "value") ?? {});
  for (const f of ["model", "effort"]) if (bind[f] === null || bind[f] === undefined) bind[f] = "";
  return bind;
}

/// The last link drawn as a QR code (the view is made again on every change; the link seldom is).
let drawn: [string, ReturnType<typeof qr>] | null = null;
function qrOf(url: string): ReturnType<typeof qr> {
  if (drawn === null || drawn[0] !== url) drawn = [url, qr(url)];
  return drawn[1];
}

/// An app of one's own as the station takes it.
const feishuApp = (f: J): J => ({ appId: str(f.appId).trim(), appSecret: str(f.appSecret).trim(), domain: f.lark === true ? "lark" : "feishu" });

/// The Feishu path as drawn: what is typed and whether it was verified as it is, the bot being made by scanning (its
/// QR code while it waits, where it stands in words), the connect being added and why that failed.
function feishuView(f: J, overview: J, pending: boolean): J {
  const reg = registrationOf(overview, f);
  const state = str(get(reg, "state"));
  const url = str(get(reg, "url"));
  const verified = f.checked === feishuKey(f);
  const errors: string[] = verified ? f.errors : [];
  const stateText =
    reg === null ? null
      : state === "waiting" ? t("core-misc.connect.feishu.waiting")
      : state === "done" ? (f.error === null ? t("core-misc.connect.feishu.made") : t("core-misc.connect.feishu.made_failed"))
      : state === "denied" ? t("core-misc.connect.feishu.denied")
      : state === "expired" ? t("core-misc.connect.feishu.expired")
      : str(get(reg, "error")) !== "" ? t("core-misc.connect.feishu.failed_because", { error: str(get(reg, "error")) })
      : t("core-misc.connect.feishu.failed");
  const out: J = {
    way: f.way === "app" ? "app" : "scan",
    appId: str(f.appId),
    appSecret: str(f.appSecret),
    lark: f.lark === true,
    canVerify: !pending && str(f.appId).trim() !== "" && str(f.appSecret).trim() !== "",
    verified: verified && f.identity !== null && errors.length === 0,
    errors,
    failed: state === "denied" || state === "expired" || state === "failed",
    creating: f.creating === true,
    error: f.error ?? null,
    connect: f.connect ?? null,
  };
  if (verified && f.identity !== null) out.identity = f.identity;
  if (reg !== null) out.registration = reg;
  if (stateText !== null) out.stateText = stateText;
  if (state === "waiting" && url !== "") {
    const code = qrOf(url);
    if (code !== null) out.qr = code;
  }
  return out;
}

// ── the add-profile pages (profile_flow.rs) ──

const usesNames = (u: providers.Uses) => ([[u.claude, "claude"], [u.codex, "codex"], [u.dsh, "dsh"], [u.grok, "grok"], [u.decision, "decision"]] as [boolean, string][]).filter(([on]) => on).map(([, id]) => id);
const usesTextOf = present.usesText;
const runtimeName = format.runtimeLabel;

/// The runtimes a station runs only where its overview's `updates` lists them.
const LISTED = ["dsh", "grok", "cursor", "devin"];

/// The runtimes a station can run: Claude Code and Codex on any; DeepSeek Harness, Grok Build, Cursor and Devin each on one
/// that lists its version (a station from before it does not, and is not offered it).
export function stationRuntimes(overview: J): string[] {
  const listed = (id: string) => arr(get(overview, "updates")).some((u) => get(u, "id") === id);
  return format.RUNTIMES.filter((r) => !LISTED.includes(r) || listed(r));
}

/// A runtime's subscription: the plan as the picker names it, and who is signed in to, as the steps name it.
const PLANS: Record<string, { plan: string; provider: string }> = {
  claude: { plan: "Claude", provider: "Claude" },
  codex: { plan: "ChatGPT", provider: "ChatGPT" },
  grok: { plan: "SuperGrok", provider: "Grok" },
  cursor: { plan: "Cursor", provider: "Cursor" },
  devin: { plan: "Devin", provider: "Devin" },
};
const planOf = (runtime: string) => PLANS[runtime] ?? PLANS.claude!;

function usesOf(source: providers.Source, endpoint: string | null, protocol: string | null, runtimes: string[]): string[] {
  const own = source.endpointRequired ? (endpoint ?? providers.example(source.id)) : null;
  const p = protocol ?? source.protocols?.[0] ?? null;
  const at = providers.endpoints(source, own, source.endpointRequired ? p : null);
  return at !== null ? usesNames(providers.uses(at, source.id)).filter((u) => u === "decision" || runtimes.includes(u)) : [];
}

function tileOf(source: providers.Source, hasKey: boolean, hasPlan: boolean, runtimes: string[]): J {
  const kind = source.legacy === "opencode-go" ? "opencode-go" : source.legacy === "anthropic-api" ? "anthropic-api" : "api-provider";
  // xAI's plan (SuperGrok) runs Grok Build.
  const runtime = source.id === "openai" ? "codex" : source.id === "anthropic" ? "claude" : source.id === "xai" && hasPlan ? "grok" : null;
  // Kimi's plan (Kimi Code signed in to) runs Claude Code, besides what its open platform's key does.
  const planned = source.id === "moonshotai" && hasPlan && runtimes.includes("claude") ? ["claude"] : [];
  const uses = [...planned, ...usesOf(source, null, null, runtimes).filter((u) => !planned.includes(u))];
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

/// The runtimes whose account is their plan, and the only way they run (they take no provider's key): last of the makers.
const PLAN_ALONE = ["cursor", "devin"];

/// Such a runtime's tile (Cursor's, Devin's), named and marked as the runtime.
function planTile(runtime: string): J {
  const uses = [runtime];
  return { id: runtime, name: runtimeName(runtime), group: "labs", mark: runtime, kind: "api-provider", hasKey: false, hasPlan: true, runtime, endpointRequired: false, protocols: [], keyOptional: false, uses, usesText: usesTextOf(uses), regions: [] };
}

/// The picker's groups: every provider the station can take a key for, those with a plan, the variables by hand (for
/// each runtime it can run, `runtimes`). `console`: the station signs OpenCode Go in to the OpenCode Console (its plan); one
/// that lists Kimi Code signs Kimi in to the person's Kimi account (Kimi's plan, as ChatGPT's is OpenAI's: one tile,
/// the open platform's key beside it; Kimi Code has no tile of its own). xAI
/// has a plan (SuperGrok) where the station runs Grok Build; Cursor and Devin, last of the makers, where it runs them.
export function groups(supported: string[] | null, runtimes: string[] = format.RUNTIMES, console = false): J[] {
  const listed = (id: string) => supported !== null && supported.includes(id);
  const out: J[] = [];
  for (const group of providers.GROUPS) {
    const tiles = providers.SOURCES.filter((s) => s.group === group && !providers.isChinaVariant(s.id) && s.id !== "kimi-code").flatMap((s) => {
      const hasKey = s.legacy !== undefined || listed(s.id);
      const hasPlan = s.id === "openai" || s.id === "anthropic" || (s.id === "opencode-go" && console) || (s.id === "moonshotai" && listed("kimi-code")) || (s.id === "xai" && runtimes.includes("grok"));
      return hasKey || hasPlan ? [tileOf(s, hasKey, hasPlan, runtimes)] : [];
    });
    if (group === "labs") for (const r of PLAN_ALONE) if (runtimes.includes(r)) tiles.push(planTile(r));
    if (group === "local") {
      for (const runtime of runtimes) {
        const uses = [runtime];
        tiles.push({ id: `env-${runtime}`, name: t("core-views.flow.env", { runtime: runtimeName(runtime) }), group: "local", kind: "env", hasKey: false, hasPlan: false, runtime, endpointRequired: false, protocols: [], keyOptional: true, uses, usesText: usesTextOf(uses) });
      }
    }
    if (tiles.length > 0) out.push({ id: group, title: t(`core-views.flow.group.${group}`), providers: tiles });
  }
  return out;
}

const consoleOf = (overview: J): boolean => get(overview, "consoleSignIn") === true;

function supportedOf(overview: J): string[] | null {
  const list = get(overview, "apiProviders");
  return Array.isArray(list) ? list.flatMap((p) => (typeof get(p, "id") === "string" ? [p.id] : [])) : null;
}

const findTile = (gs: J[], id: string): J => gs.flatMap((g) => arr(g.providers)).find((p) => p.id === id);
const blank = () => ({ provider: "", method: "", endpoint: "", protocol: "", region: "", key: "", error: null, pending: false });

function profileView(station: string, draft: J, overview: J, manages = false): J {
  const runtimes = stationRuntimes(overview);
  const gs = groups(supportedOf(overview), runtimes, consoleOf(overview));
  const tile = typeof draft.provider === "string" ? findTile(gs, draft.provider) : undefined;
  const method = typeof draft.method === "string" && draft.method !== "" ? draft.method : null;
  const out: J = {
    step: "pick", station, title: t("core-views.flow.pick"), hint: t("core-views.flow.pick_hint"), groups: gs, tile: tile ?? null, method, choices: [], showEndpoint: false,
    endpoint: draft.endpoint ?? null, protocols: [], regions: [], region: null, showKey: false, key: draft.key ?? null, keyLabel: "", canSubmit: false, pending: draft.pending === true,
    submitLabel: "", usesLine: "", error: draft.error ?? null, signIn: null,
  };
  if (tile === undefined) return out;
  const name = str(tile.name);
  out.title = t("core-views.flow.connect", { name });
  out.hint = "";
  const runtime = str(tile.runtime, "claude");
  // OpenCode Go's plan is signed in to with the person's OpenCode account, and runs every runtime its key does; Kimi
  // Code's with a Kimi account, and runs Claude Code (the only one that reads its token again as it is renewed).
  const opencode = tile.id === "opencode-go";
  const kimi = tile.id === "moonshotai";
  if (method === null) {
    const plan = opencode ? "OpenCode Go" : kimi ? "Kimi Code" : planOf(runtime).plan;
    out.step = "method";
    out.choices = [
      { id: "plan", title: t("core-views.flow.plan", { plan }), hint: t(`core-views.flow.plan_hint.${opencode ? "opencode" : kimi ? "kimi" : runtime}`) },
      { id: "key", title: t("core-views.flow.key_card"), hint: t("core-views.flow.key_card_hint", { name }) },
    ];
    return out;
  }
  out.step = "connect";
  const kind = str(tile.kind, "api-provider");
  if (method === "plan") {
    if (opencode) {
      out.signIn = { runtime: "claude", access: "opencode-go", provider: "OpenCode" };
      out.usesLine = t("core-views.flow.uses", { uses: usesTextOf(arr(tile.uses).filter((u: unknown) => u !== "decision")) });
      return out;
    }
    if (kimi) {
      out.signIn = { runtime: "claude", access: "kimi-code", provider: "Kimi" };
      out.usesLine = t("core-views.flow.uses", { uses: runtimeName("claude") });
      return out;
    }
    out.usesLine = t("core-views.flow.uses", { uses: runtimeName(runtime) });
    // Signed in with the runtime's own command: one the station does not have is installed first, the sign-in after.
    const install = present.installView(runtime, arr(get(overview, "updates")), manages);
    if (install !== null && install.state !== "installed") out.install = install;
    else out.signIn = { runtime, provider: planOf(runtime).provider };
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
  const uses = source !== null ? usesOf(source, endpoint !== "" ? endpoint : null, protocol, runtimes) : [];
  out.usesLine = uses.length === 0 ? t("core-views.flow.uses_none") : t("core-views.flow.uses", { uses: usesTextOf(uses) });
  return out;
}

/// `watch`: the station's overview and its workspace (the viewer's role: whether they may install a runtime).
type ProfileDraft = { owner: ClientId; value: J; pending: boolean; watch: Watch[] };

export class ProfileFlows {
  readonly #store: Store;
  readonly #drafts = new Map<string, ProfileDraft>();

  constructor(store: Store) {
    this.#store = store;
  }

  disconnect(owner: ClientId): void {
    for (const [k, d] of [...this.#drafts]) {
      if (d.owner !== owner) continue;
      for (const w of d.watch) w.drop();
      this.#drafts.delete(k);
    }
  }

  value(topic: Topic): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d) return null;
    const station = topic.station as string;
    const role = get(this.#store.value({ topic: "workspace", workspace: ofAddress(station) }), "ok")?.role;
    return profileView(station, d.value, overviewOf(this.#store, station), role === "owner" || role === "admin");
  }

  change(topic: Topic, owner: ClientId, action: string, patch: J): J {
    const station = topic.station as string;
    const key = topicKey(topic);
    const existing = this.#drafts.get(key);
    if (existing && existing.owner !== owner) throw CoreError.invalid(t("core-views.flow.not_yours"));
    if (action === "drop") {
      for (const w of existing?.watch ?? []) w.drop();
      this.#drafts.delete(key);
      this.#store.invalidate(topic);
      return null;
    }
    let d = existing;
    if (!d) {
      const watch = [{ topic: "overview", station }, { topic: "workspace", workspace: ofAddress(station) }].map((t) => this.#store.watch(t, () => this.#store.invalidate(topic)));
      d = { owner, value: blank(), pending: false, watch };
      this.#drafts.set(key, d);
    }
    if (action === "edit") {
      if (d.pending) throw CoreError.invalid(t("core-views.flow.wait"));
      const o = overviewOf(this.#store, station);
      const gs = groups(supportedOf(o), stationRuntimes(o), consoleOf(o));
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
