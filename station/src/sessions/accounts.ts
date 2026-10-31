// Which account a session runs on (the Rust station's hub.rs: run_on, spend, pick, health_of, model_efforts, configure): the
// pool's choice among the station's profiles, kept while usable, moved off one whose allowance ran out, and changed by
// hand (profile, model, effort, fast). How profiles are doing comes from outside (the accounts module's checks and
// allowances: `setHealth`); which ran into their allowance lately is kept here.
import type { Clock } from "effect";
import { log } from "../ops/log.ts";
import { tr, type Lang, stationLang } from "../ops/i18n.ts";
import type { Store } from "../store/store.ts";
import { type HubConfig, type Profile, runs, runtimeNamed, runtimeTitle, sameModel, spelling } from "./config.ts";
import { availableEfforts, cheapToLeave, commonEfforts, type ProfileHealth, pickProfile, serves, urgency, usable, windowsOf } from "./pool.ts";
import type { RuntimeKind } from "../agents/runtime.ts";
import { billedPerUse } from "../agents/profiles.ts";

/// How long a profile a turn ran into the allowance of is passed over when its allowance is not read again.
const SPENT_FOR_MS = 60 * 60 * 1000;
/// Where models are compacted is learnt from the calls of this long, and learnt again this often.
const COMPACTIONS_OVER_MS = 7 * 24 * 60 * 60 * 1000;
const COMPACTIONS_EVERY_MS = 60 * 60 * 1000;
/// How many of a session's last calls say whether it compacted lately.
const CALLS_LOOKED_AT = 200;

/// How a session runs from its next turn on. A field left out: unchanged; null: back to the default. `repick`: back to the
/// station's choice (no profile given), its account picked again now, as a new session's would be (`Accounts.repick`).
export type SessionChange = { profile?: string | null; model?: string | null; effort?: string | null; fast?: boolean | null; repick?: boolean; afresh?: boolean | null };

/// A profile as a session's runtime starts on it, with its spelling of the session's model.
export type RunOn = Profile & { spelling(model: string): string | null };

const withSpelling = (p: Profile): RunOn => ({ ...p, spelling: (model: string) => spelling(p, model) });

export type AccountsDeps = {
  config(): HubConfig;
  store: Store;
  /// The profiles of sessions with a process now (their load), `except`'s left out.
  running(except?: string): string[];
  /// Its time.
  clock: Clock.Clock;
  /// Whether session `key` may run on a profile: one allowed in its workspace (docs/multi-workspace.md); absent: any.
  allows?(key: string, profile: Profile): boolean;
};

export class Accounts {
  private deps: AccountsDeps;
  private health: (id: string) => ProfileHealth = () => ({});
  private checkAgain: (id: string) => Promise<unknown> = async () => {};
  private rechecking = new Map<string, Promise<void>>();
  private picked = new Map<string, number>();
  /// Accounts a turn ran into the allowance of, and when: passed over until their allowance is read again, or for
  /// SPENT_FOR_MS when it is not.
  private spent = new Map<string, number>();
  /// Where each model's context is compacted on this station, and when that was learnt.
  private compactions: [number, Map<string, number>] | null = null;

  constructor(deps: AccountsDeps) {
    this.deps = deps;
  }

  /// Lets the pool see profiles' checks and allowances.
  setHealth(health: (id: string) => ProfileHealth) {
    this.health = health;
  }

  /// Lets the pool have a profile checked again (accounts/index.ts `check`).
  setRecheck(recheck: (id: string) => Promise<unknown>) {
    this.checkAgain = recheck;
  }

  /// Profile `id` checked again, a runtime on it having failed to sign in (once at a time): one whose login is over is
  /// passed over from then on, and a session left to the station goes on on another (`runOn`).
  recheck(id: string): Promise<void> {
    const busy = this.rechecking.get(id);
    if (busy) return busy;
    const run = this.checkAgain(id)
      .then(
        () => {},
        () => {},
      )
      .finally(() => this.rechecking.delete(id));
    this.rechecking.set(id, run);
    return run;
  }

  /// Several profiles can spend the same account's allowance. An unknown account keeps its own profile's identity.
  private accountKey(id: string, health = this.health(id)): string {
    return typeof health.account === "string" && health.account !== "" ? `account:${health.account}` : `profile:${id}`;
  }

  healthOf(id: string): ProfileHealth {
    const health: ProfileHealth = { ...this.health(id) };
    const key = this.accountKey(id, health);
    // Another profile of the same account may have read its allowance more recently. A failed read does not replace a
    // successful one; sign-in checks remain specific to each profile.
    if (key.startsWith("account:")) {
      for (const other of this.deps.config().profiles) {
        if (other.id === id) continue;
        const candidate = this.health(other.id);
        if (this.accountKey(other.id, candidate) !== key || candidate.quota?.state !== "ok") continue;
        if (health.quota?.state !== "ok" || Number(candidate.quota.checkedAt ?? 0) > Number(health.quota.checkedAt ?? 0)) health.quota = candidate.quota;
      }
    }
    const at = this.spent.get(key);
    if (at !== undefined) {
      // Read again since: what it says now counts.
      const checked = health.quota?.checkedAt;
      if ((typeof checked === "number" && checked > at) || this.deps.clock.currentTimeMillisUnsafe() - at > SPENT_FOR_MS) this.spent.delete(key);
      else health.spent = true;
    }
    return health;
  }

  /// Chooses the profile a session runs on (pool.ts); `except`: the session it is chosen for, whose own process is not
  /// counted.
  pick(candidates: Profile[], model: string | null | undefined, strict: boolean, except?: string): Profile {
    const running = this.deps.running(except);
    const load = new Map<string, number>();
    for (const id of running) {
      const key = this.accountKey(id);
      load.set(key, (load.get(key) ?? 0) + 1);
    }
    const profile = pickProfile(candidates, model, { health: (id) => this.healthOf(id), load: (id) => load.get(this.accountKey(id)) ?? 0, lastPicked: (id) => this.picked.get(this.accountKey(id)) ?? 0, now: () => this.deps.clock.currentTimeMillisUnsafe() }, strict);
    this.picked.set(this.accountKey(profile.id), this.deps.clock.currentTimeMillisUnsafe());
    return profile;
  }

  /// Whether session `key` may run on `profile` (its workspace's, docs/multi-workspace.md).
  allows(key: string, profile: Profile): boolean {
    return this.deps.allows?.(key, profile) ?? true;
  }

  /// The profile a session's runtime starts on, asked again before each turn: its own while usable (on another it goes
  /// on afresh, afresh.ts), else the one the pool picks among those of its runtime allowed in its workspace. One billed
  /// per use it leaves for one paid for already that can run it, and one whose short window is nearly full for one paid
  /// for alike that is not, when that loses little (pool.ts `cheapToLeave`): its context was just compacted, or is about
  /// to be, and not while its process has work going in the background (`holding`: commands and subagents, which end
  /// with it).
  runOn(key: string, holding = false): RunOn {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const all = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime));
    const candidates = all.filter((p) => this.allows(key, p));
    // Profiles there are, none of them for its workspace: said so, for people to allow one.
    if (candidates.length === 0 && all.length > 0) throw new Error(tr(stationLang(), "station.session.noProfileHere", { runtime: runtimeTitle(runtime) }));
    // Kept to it by hand: that one, whatever it says. Otherwise its own while it can run it: usable, and with its model
    // enabled.
    const current = candidates.find((p) => p.id === row.profile);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const crowded = (p: Profile) => urgency(this.healthOf(p.id).quota, now).crowded;
    const keeps = current && (row.profilePinned || (usable(this.healthOf(current.id)) && serves(current, row.model)));
    let among = candidates;
    if (current && keeps) {
      if (row.profilePinned) return withSpelling(current);
      // It moves from one billed per use to one paid for already, and from one nearly full to one paid for alike that is
      // not (the pool puts those last), never from one paid for already to one billed per use; only when that loses
      // little.
      const paid = (p: Profile) => !billedPerUse(p);
      const better = (p: Profile) =>
        p.id !== current.id && serves(p, row.model) && usable(this.healthOf(p.id)) && (paid(p) === paid(current) ? crowded(current) && !crowded(p) : paid(p));
      among = candidates.filter(better);
      if (among.length === 0 || holding || !this.cheapToLeave(key)) return withSpelling(current);
    }
    if (candidates.length === 0) throw new Error(`session ${key}: no profile runs ${row.runtime}`);
    const next = this.pick(among, row.model, false);
    if (next.id !== row.profile) {
      store.setSessionProfile(key, next.id, false);
      log.info("hub", "session taken on by another profile", { session: key, from: row.profile, to: next.id });
    }
    return withSpelling(next);
  }

  /// Session `key`, left to the station, has its account picked again now, as a new session's would be: among those of
  /// its runtime allowed in its workspace, its own process not counted on the one it is on (pool.ts). The one it is on
  /// stays when it is still the pool's choice; on another it goes on afresh (afresh.ts).
  repick(key: string): void {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const candidates = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(key, p));
    if (candidates.length === 0) throw new Error(tr(stationLang(), "station.session.noProfileHere", { runtime: runtimeTitle(runtime) }));
    const next = this.pick(candidates, row.model, false, key);
    store.setSessionProfile(key, next.id, false);
    if (next.id !== row.profile) log.info("hub", "session's account picked again", { session: key, from: row.profile, to: next.id });
  }

  /// Whether session `key` loses little by going on afresh on another account (pool.ts `cheapToLeave`).
  private cheapToLeave(key: string): boolean {
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const { store } = this.deps;
    if (this.compactions === null || now - this.compactions[0] > COMPACTIONS_EVERY_MS) this.compactions = [now, store.compactionPoints(now - COMPACTIONS_OVER_MS)];
    return cheapToLeave(store.lastContexts(key, CALLS_LOOKED_AT), this.compactions[1]);
  }

  /// Profile `id` as a session's runtime runs on it; null when the station no longer has it.
  profile(id: string): RunOn | null {
    const profile = this.deps.config().profiles.find((p) => p.id === id);
    return profile ? withSpelling(profile) : null;
  }

  /// A turn of the session ran into the allowance of `ranOn`, the profile its process was started on (null: the
  /// session's own): that profile is passed over for now, and a session left to the station moves to another of its
  /// runtime's that can run it now; one moved off it while the turn ran (changed by hand, its profile deleted) goes on
  /// where it was moved. The names of the one left and the one taken when it moved; null when it is kept to its profile
  /// or none other can.
  spend(key: string, ranOn: string | null): [string, string] | null {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const left = ranOn ?? row.profile;
    this.spent.set(this.accountKey(left), this.deps.clock.currentTimeMillisUnsafe());
    const config = this.deps.config();
    const name = (id: string) => config.profiles.find((p) => p.id === id)?.name ?? id;
    if (row.profile !== left) return [name(left), name(row.profile)];
    if (row.profilePinned) return null;
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) return null;
    // As the pool: those with its model enabled, or, when none has (a connect's binding from before models were
    // enabled), all of its runtime's.
    const all = config.profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(key, p));
    const strict = all.some((p) => serves(p, row.model));
    const candidates = all.filter((p) => p.id !== left && (!strict || serves(p, row.model)) && usable(this.healthOf(p.id)));
    if (candidates.length === 0) return null;
    const next = this.pick(candidates, row.model, false);
    store.setSessionProfile(key, next.id, false);
    log.info("hub", "allowance ran out; session taken on by another profile", { session: key, from: left, to: next.id });
    return [name(left), next.name];
  }

  /// When the profile of session `key`, which ran into its allowance, is expected to run again: the last refill of its
  /// used-up windows, or, none known, when it stops being passed over.
  refillsAt(key: string): number {
    const row = this.deps.store.getSession(key);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    if (!row) return now + SPENT_FOR_MS;
    const full = windowsOf(this.healthOf(row.profile).quota).filter((w) => Number(w.usedPercent) >= 100 && typeof w.resetsAt === "number" && w.resetsAt > now);
    if (full.length > 0) return Math.max(...full.map((w) => w.resetsAt as number));
    return (this.spent.get(this.accountKey(row.profile)) ?? now) + SPENT_FOR_MS;
  }

  /// The reasoning levels every eligible account offers for a model (a pinned account may offer more): automatic
  /// selection must work on every one, quota failover included. `allowed`: the profiles of the workspace asked for.
  modelEfforts(runtime: RuntimeKind, model: string | null, pinned: string | null, allowed: (p: Profile) => boolean = () => true): string[] {
    const profiles = this.deps
      .config()
      .profiles.filter((p) => p.runtimes.includes(runtime) && allowed(p))
      .filter((p) => pinned === null || p.id === pinned)
      .filter((p) => model === null || runs(p, model));
    return commonEfforts(
      profiles.map((p) => availableEfforts(runtime, model ?? p.model ?? null, this.healthOf(p.id).check?.modelEfforts ?? null)),
      runtime,
    );
  }

  /// Checks a change (configure) and works out what it makes of the session: its profile (and whether kept to it), its
  /// model and effort. Throws what is wrong with it, in `lang`.
  change(key: string, change: SessionChange, lang: Lang = stationLang()) {
    const { store } = this.deps;
    const t = (k: string, args?: Record<string, unknown>) => tr(lang, k, args);
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const name = runtimeTitle(runtime);
    const config = this.deps.config();
    const nonEmpty = (v: string | null | undefined) => (v === undefined ? undefined : v === null || v === "" ? null : v);
    // A profile given keeps the session to it; null (or picked again) gives the choice back to the station.
    const wantedProfile = change.repick === true && (change.profile === undefined || change.profile === null) ? null : nonEmpty(change.profile);
    const newModel = nonEmpty(change.model);
    const newEffort = nonEmpty(change.effort);
    if (change.fast !== undefined && change.fast !== null && runtime !== "codex") throw new Error(t("station.session.fastOpenAiOnly"));
    const allowed = (p: Profile) => this.allows(key, p);
    if (typeof wantedProfile === "string") {
      const next = config.profiles.find((p) => p.id === wantedProfile);
      if (!next) throw new Error(`unknown profile ${wantedProfile}`);
      if (!next.runtimes.includes(runtime)) throw new Error(t("station.profile.cannotRun", { profile: next.name, runtime: name }));
      if (!allowed(next)) throw new Error(t("station.profile.notHere", { profile: next.name }));
      const model = newModel !== undefined ? newModel : row.model;
      if (model !== null && !runs(next, model)) throw new Error(t("station.session.modelOff", { profile: next.name, model }));
    }
    let model = newModel !== undefined ? newModel : row.model;
    // Another spelling of its model is its model.
    const remodel = model !== null && row.model !== null ? !sameModel(model, row.model) : model !== row.model;
    if (!remodel) model = row.model;
    const effort = newEffort !== undefined ? newEffort : remodel ? null : row.effort;
    // What changes is checked; what stays is as it was.
    if (typeof newModel === "string" && model !== null && !config.profiles.some((p) => p.runtimes.includes(runtime) && allowed(p) && runs(p, model!))) {
      throw new Error(t("station.session.noProfileForModel", { model, runtime: name }));
    }
    if (effort !== null && (newEffort !== undefined || wantedProfile !== undefined || remodel)) {
      const pinned = wantedProfile !== undefined ? wantedProfile : !remodel && row.profilePinned ? row.profile : null;
      const efforts = this.modelEfforts(runtime, model, pinned, allowed);
      if (!efforts.includes(effort)) throw new Error(t("station.profile.efforts", { runtime: name, efforts: efforts.join(t("station.list.separator")) }));
    }
    const profile = wantedProfile !== undefined ? wantedProfile : remodel ? null : undefined;
    return { row, model, effort, profile, repick: change.repick === true && profile === null };
  }
}
