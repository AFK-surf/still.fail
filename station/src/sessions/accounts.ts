// Which account a session runs on (spend, pick, health_of, model_efforts, configure): the
// pool's choice among the station's profiles, kept while usable, moved off one whose allowance ran out, and changed by
// hand (profile, model, effort, fast). How profiles are doing comes from outside (the accounts module's checks and
// allowances: `setHealth`); which ran into their allowance lately is kept here.
import type { Clock } from "effect";
import { log } from "../ops/log.ts";
import { tr, type Lang, stationLang } from "../ops/i18n.ts";
import { checkContext } from "./context-cap.ts";
import type { Store } from "../store/store.ts";
import type { SessionRow } from "../store/rows.ts";
import { type HubConfig, type Profile, runs, runtimeNamed, runtimeTitle, sameModel, spelling } from "./config.ts";
import { modelKey } from "../read/usage.ts";
import { availableEfforts, cheapToLeave, commonEfforts, type ProfileHealth, pickProfile, reportedEfforts, serves, signsIn, urgency, usable, windowsOf } from "./pool.ts";
import { agyScopeForModel } from "../accounts/agy-quota.ts";
import type { RuntimeKind } from "../agents/runtime.ts";
import { billedPerUse, FAST_RUNTIMES } from "../agents/profiles.ts";

/// How long a profile a turn ran into the allowance of is passed over when its allowance is not read again.
const SPENT_FOR_MS = 60 * 60 * 1000;
/// Where models are compacted is learnt from the calls of this long, and learnt again this often.
const COMPACTIONS_OVER_MS = 7 * 24 * 60 * 60 * 1000;
const COMPACTIONS_EVERY_MS = 60 * 60 * 1000;
/// How many of a session's last calls say whether it compacted lately.
const CALLS_LOOKED_AT = 200;

/// How a session runs from its next turn on. A field left out: unchanged; null: back to the default. `profiles`: the set
/// of profiles it may run on (one keeps it to that one; null: all of them). `repick`: its account picked again now, as a
/// new session's would be (`Accounts.repick`).
export type SessionChange = { runtime?: string; profile?: string | null; profiles?: string[] | null; model?: string | null; effort?: string | null; fast?: boolean | null; context?: number | null; repick?: boolean; afresh?: boolean | null };

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
  /// Whether session `key` may run on a profile: one allowed in its workspace; absent: any.
  allows?(key: string, profile: Profile): boolean;
  /// Session `key`, left to the station, was moved to another profile by it (`runOn`, `spend`): `was` how it ran before.
  moved?(key: string, was: SessionRow): void;
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
  /// Models that ran into their own limit on an account (Claude Code's "You've reached your Fable limit."), by account:
  /// the model as the runtime named it, as the session ran it (null: its profile's default) and when. That model alone
  /// is passed over there, for SPENT_FOR_MS (the runtime says no refill time); the account's others run on (#4643).
  private modelSpent = new Map<string, { named: string; ran: string | null; at: number }[]>();
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

  /// Profiles can be different logins to the same account, whose allowance they share.
  sameAccount(a: string, b: string): boolean {
    return this.accountKey(a) === this.accountKey(b);
  }

  /// An explicit reset supersedes the failure which made this account unavailable to the pool.
  resetAllowance(id: string): void {
    this.spent.delete(this.accountKey(id));
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

  /// How profile `id` is doing for running `model` (null: its own default): spent as well while that model is passed
  /// over on its account, having run into its own limit there; where windows are split by model group (Antigravity's
  /// Gemini vs Claude / GPT), only that group's windows weigh on `model`.
  private healthFor(id: string, model: string | null | undefined): ProfileHealth {
    const health = this.healthOf(id);
    const quota = this.quotaForModel(id, health.quota, model);
    const scoped = quota !== health.quota ? { ...health, quota } : health;
    return this.modelSpentAt(id, model) !== undefined ? { ...scoped, spent: true } : scoped;
  }

  private quotaForModel(id: string, quota: any, model: string | null | undefined): any {
    const wins = windowsOf(quota);
    if (wins.length === 0 || !wins.some((w) => w?.scope === "gemini" || w?.scope === "3p")) return quota;
    const chosen = model ?? this.deps.config().profiles.find((p) => p.id === id)?.model ?? null;
    const want = agyScopeForModel(chosen);
    const filtered = wins.filter((w) => w?.scope === undefined || w.scope === want);
    return filtered.length > 0 && filtered.length !== wins.length ? { ...quota, windows: filtered } : quota;
  }

  /// Whether profile `id` can run `model` now (pool.ts `usable`).
  private can(id: string, model: string | null | undefined): boolean {
    return usable(this.healthFor(id, model), this.deps.clock.currentTimeMillisUnsafe());
  }

  /// Which of `candidates` session `row` may use: its chosen subset while at least one of them is still configured and
  /// allowed here, else all of `candidates`.
  private poolFor(row: SessionRow, candidates: Profile[]): [Profile[], string[] | null] {
    if (!row.profiles || row.profiles.length === 0) return [candidates, null];
    const kept = new Set(row.profiles);
    const subset = candidates.filter((p) => kept.has(p.id));
    return subset.length > 0 ? [subset, row.profiles] : [candidates, null];
  }

  /// The profiles session `row` could go on on other than its own, left to the station: those of its runtime allowed in
  /// its workspace (and in its chosen set, when kept to several) that run its model, or, when none does, all of them (as
  /// `runOn` and `spend`). Kept to one: none.
  private others(row: SessionRow): Profile[] {
    const runtime = runtimeNamed(row.runtime);
    if (!runtime || row.profilePinned) return [];
    const workspaceAll = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(row.key, p));
    const [all] = this.poolFor(row, workspaceAll);
    const strict = all.some((p) => serves(p, row.model));
    return all.filter((p) => p.id !== row.profile && (!strict || serves(p, row.model)));
  }

  /// When `model` (null: profile `id`'s default) ran into its own limit on `id`'s account, while it is passed over.
  private modelSpentAt(id: string, model: string | null | undefined): number | undefined {
    const key = this.accountKey(id);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const kept = (this.modelSpent.get(key) ?? []).filter((s) => now - s.at <= SPENT_FOR_MS);
    if (kept.length > 0) this.modelSpent.set(key, kept);
    else this.modelSpent.delete(key);
    const runs = model ?? this.deps.config().profiles.find((p) => p.id === id)?.model ?? null;
    const words = (m: string) => m.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w !== "");
    // The runtime names it in words ("Fable" for claude-fable-5-1); one run by its default, unknown, is the same default.
    const named = (s: { named: string; ran: string | null }) =>
      runs === null ? s.ran === null : (s.ran !== null && sameModel(runs, s.ran)) || words(s.named).every((w) => words(modelKey(runs)).includes(w));
    return kept.filter(named).at(-1)?.at;
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
    const profile = pickProfile(candidates, model, { health: (id) => this.healthFor(id, model), load: (id) => load.get(this.accountKey(id)) ?? 0, lastPicked: (id) => this.picked.get(this.accountKey(id)) ?? 0, now: () => this.deps.clock.currentTimeMillisUnsafe() }, strict);
    this.picked.set(this.accountKey(profile.id), this.deps.clock.currentTimeMillisUnsafe());
    return profile;
  }

  /// Whether session `key` may run on `profile` (its workspace's).
  allows(key: string, profile: Profile): boolean {
    return profile.enabled !== false && (this.deps.allows?.(key, profile) ?? true);
  }

  /// The profile a session's runtime starts on, asked again before each turn: its own while usable (on another it goes
  /// on afresh, afresh.ts), else the one the pool picks among those of its runtime allowed in its workspace. One billed
  /// per use it leaves for one paid for already that can run it, and one whose short window is nearly full for one paid
  /// for alike that is not, when that loses little (pool.ts `cheapToLeave`): its context was just compacted, or is about
  /// to be, and not while its process has work going in the background (`holding`: commands and subagents, which end
  /// with it). Its own unable to run it and no other able either (every allowance used up), it stays where it is and
  /// waits there (`refillsAt`); its own unable even to sign in, it moves once to one that signs in. A move is told
  /// (`moved`, said in its chat) unless `quiet`: a change by hand says its own.
  runOn(key: string, holding = false, quiet = false): RunOn {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const all = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime));
    const workspaceCandidates = all.filter((p) => this.allows(key, p));
    // Profiles there are, none of them for its workspace: said so, for people to allow one.
    if (workspaceCandidates.length === 0 && all.length > 0) throw new Error(tr(stationLang(), "station.session.noProfileHere", { runtime: runtimeTitle(runtime) }));
    const [candidates, keptProfiles] = this.poolFor(row, workspaceCandidates);
    // Kept to it by hand: that one, whatever it says. Otherwise its own while it can run it: usable, and with its model
    // enabled.
    const current = candidates.find((p) => p.id === row.profile);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const crowded = (p: Profile) => urgency(this.healthOf(p.id).quota, now).crowded;
    // (Its model counts only where one of them has it enabled, as in `spend` and the pool: else each call would move it
    // to the least loaded, its own process counted where it is, back and forth.)
    const strict = candidates.some((p) => serves(p, row.model));
    const fits = (p: Profile) => !strict || serves(p, row.model);
    const keeps = current && (row.profilePinned || (this.can(current.id, row.model) && fits(current)));
    let among = candidates;
    if (current && keeps) {
      if (row.profilePinned) return withSpelling(current);
      // It moves from one billed per use to one paid for already, and from one nearly full to one paid for alike that is
      // not (the pool puts those last), never from one paid for already to one billed per use; only when that loses
      // little.
      const paid = (p: Profile) => !billedPerUse(p);
      const better = (p: Profile) =>
        p.id !== current.id && fits(p) && this.can(p.id, row.model) && (paid(p) === paid(current) ? crowded(current) && !crowded(p) : paid(p));
      among = candidates.filter(better);
      if (among.length === 0 || holding || !this.cheapToLeave(key)) return withSpelling(current);
    } else {
      // It goes to those that can run it now; none can: to those that at least sign in (it waits for their refill).
      // When its own is as good as any, it stays. The pool, given none that can run, picks the one picked least
      // recently, so each asking moved it on to the next spent account (2026-11-10: asked three times before a turn,
      // a session was moved three times in a second, each a notice in its chat, and waited for the refill of the
      // account it ended on, days away, while another's five hours refilled).
      const standing = (p: Profile) => (this.can(p.id, row.model) ? 2 : signsIn(this.healthOf(p.id)) ? 1 : 0);
      const fit = candidates.filter(fits);
      const best = Math.max(...fit.map(standing));
      if (current && fits(current) && standing(current) >= best) return withSpelling(current);
      if (fit.length > 0) among = fit.filter((p) => standing(p) === best);
    }
    if (candidates.length === 0) throw new Error(`session ${key}: no profile runs ${row.runtime}`);
    const next = this.pick(among, row.model, false);
    if (next.id !== row.profile || keptProfiles !== (row.profiles ?? null)) {
      store.setSessionProfile(key, next.id, false, keptProfiles);
      if (next.id !== row.profile) {
        log.info("hub", "session taken on by another profile", { session: key, from: row.profile, to: next.id });
        if (!quiet) this.deps.moved?.(key, row);
      }
    }
    return withSpelling(next);
  }

  /// Session `key`, left to the station (or kept to several accounts), has its account picked again now, as a new
  /// session's would be: among those of its runtime allowed in its workspace (and in its chosen set), its own process not
  /// counted on the one it is on (pool.ts). The one it is on stays when it is still the pool's choice; on another it goes
  /// on afresh (afresh.ts).
  repick(key: string): void {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    const workspaceCandidates = this.deps.config().profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(key, p));
    if (workspaceCandidates.length === 0) throw new Error(tr(stationLang(), "station.session.noProfileHere", { runtime: runtimeTitle(runtime) }));
    const [candidates, keptProfiles] = row.profilePinned ? [workspaceCandidates, null] : this.poolFor(row, workspaceCandidates);
    const next = this.pick(candidates, row.model, false, key);
    store.setSessionProfile(key, next.id, false, keptProfiles);
    if (next.id !== row.profile) log.info("hub", "session's account picked again", { session: key, from: row.profile, to: next.id });
  }

  /// Whether session `key` loses little by going on afresh on another account (pool.ts `cheapToLeave`).
  private cheapToLeave(key: string): boolean {
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const { store } = this.deps;
    if (store.recentlyCompacted(key)) return true;
    if (!store.compactionsReady()) return cheapToLeave(store.lastContexts(key, CALLS_LOOKED_AT), new Map());
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
  /// where it was moved. `model`: the model whose own limit it was, as the runtime named it (runtime.ts `modelLimitOf`),
  /// which alone is passed over on that account, its other models still run there (#4643). The names of the one left and
  /// the one taken when it moved; null when it is kept to its profile or none other can.
  spend(key: string, ranOn: string | null, model: string | null = null): [string, string] | null {
    const { store } = this.deps;
    const row = store.getSession(key);
    if (!row) throw new Error(`unknown session ${key}`);
    const left = ranOn ?? row.profile;
    const config = this.deps.config();
    const now = this.deps.clock.currentTimeMillisUnsafe();
    if (model === null) this.spent.set(this.accountKey(left), now);
    else {
      const ran = row.model ?? config.profiles.find((p) => p.id === left)?.model ?? null;
      this.modelSpent.set(this.accountKey(left), [...(this.modelSpent.get(this.accountKey(left)) ?? []), { named: model, ran, at: now }]);
    }
    const name = (id: string) => config.profiles.find((p) => p.id === id)?.name ?? id;
    if (row.profile !== left) return [name(left), name(row.profile)];
    if (row.profilePinned) return null;
    const runtime = runtimeNamed(row.runtime);
    if (!runtime) return null;
    // As the pool: those that run its model, or, when none does (a connect's binding from before models were
    // enabled), all of its runtime's.
    const workspaceAll = config.profiles.filter((p) => p.runtimes.includes(runtime) && this.allows(key, p));
    const [all, keptProfiles] = this.poolFor(row, workspaceAll);
    const strict = all.some((p) => serves(p, row.model));
    const candidates = all.filter((p) => p.id !== left && (!strict || serves(p, row.model)) && this.can(p.id, row.model));
    if (candidates.length === 0) return null;
    const next = this.pick(candidates, row.model, false);
    store.setSessionProfile(key, next.id, false, keptProfiles);
    log.info("hub", "allowance ran out; session taken on by another profile", { session: key, from: left, to: next.id });
    this.deps.moved?.(key, row);
    return [name(left), next.name];
  }

  /// When session `key`, which ran into its allowance (or its model into its own limit), is expected to run again: when
  /// its own profile is (`refillOf`), or, left to the station, the first of those it could go on on (`runOn` moves it
  /// there as it wakes): one that can run it now at once, one that cannot sign in never.
  refillsAt(key: string): number {
    const row = this.deps.store.getSession(key);
    const now = this.deps.clock.currentTimeMillisUnsafe();
    if (!row) return now + SPENT_FOR_MS;
    const own = this.refillOf(row.profile, row.model, this.deps.store.lastTurn(key)?.endedAt ?? now);
    const others = this.others(row).filter((p) => signsIn(this.healthOf(p.id)));
    return Math.min(own, ...others.map((p) => (this.can(p.id, row.model) ? now : this.refillOf(p.id, row.model, now))));
  }

  /// When profile `id`, unable to run `model` now, is expected to: the last refill of its used-up windows, or, none
  /// known, when it stops being passed over (`since`: when it ran into its allowance, where that is not kept).
  private refillOf(id: string, model: string | null, since: number): number {
    const now = this.deps.clock.currentTimeMillisUnsafe();
    const quota = this.quotaForModel(id, this.healthOf(id).quota, model);
    const full = windowsOf(quota).filter((w) => Number(w.usedPercent) >= 100 && typeof w.resetsAt === "number" && w.resetsAt > now);
    if (full.length > 0) return Math.max(...full.map((w) => w.resetsAt as number));
    return (this.spent.get(this.accountKey(id)) ?? this.modelSpentAt(id, model) ?? since) + SPENT_FOR_MS;
  }

  /// Whether session `row`, waiting for an allowance, could go on once profile `id`'s is reset: on its own account, or,
  /// left to the station, on one it could move to.
  goesOnWith(row: SessionRow, id: string): boolean {
    return this.sameAccount(id, row.profile) || this.others(row).some((p) => this.sameAccount(id, p.id));
  }

  /// The reasoning levels every eligible account that has said offers for a model (a pinned account or chosen subset may
  /// offer more): automatic selection must work on every one, quota failover included. `allowed`: the profiles of the
  /// workspace asked for.
  modelEfforts(runtime: RuntimeKind, model: string | null, pinned: string | readonly string[] | null, allowed: (p: Profile) => boolean = () => true): string[] {
    const kept = typeof pinned === "string" ? new Set([pinned]) : Array.isArray(pinned) && pinned.length > 0 ? new Set(pinned) : null;
    const profiles = this.deps
      .config()
      .profiles.filter((p) => p.enabled !== false && p.runtimes.includes(runtime) && allowed(p))
      .filter((p) => kept === null || kept.has(p.id))
      .filter((p) => model === null || runs(p, model));
    // One that has reported no levels (its check not done, or failed) is not known to lack any: it does not hold back
    // those that have.
    const catalog = (p: Profile) => this.healthOf(p.id).check?.modelEfforts ?? null;
    const said = profiles.map((p) => reportedEfforts(runtime, model ?? p.model ?? null, catalog(p))).filter((levels) => levels !== null);
    return commonEfforts(said.length > 0 ? said : profiles.map((p) => availableEfforts(runtime, model ?? p.model ?? null, catalog(p))), runtime);
  }

  /// Checks a change (configure) and works out what it makes of the session: its profile(s) (and whether kept to one),
  /// its model and effort. Throws what is wrong with it, in `lang`.
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
    const normList = change.profiles === undefined
      ? undefined
      : change.profiles === null
        ? null
        : (() => {
            const list = [...new Set(change.profiles.map((x) => x.trim()).filter((x) => x !== ""))];
            return list.length > 0 ? list : null;
          })();
    // Profiles given keep the session to them (one: pinned); null gives the choice back to the station.
    const wantedSingle = change.repick === true && (change.profile === undefined || change.profile === null) && normList === undefined
      ? (row.profilePinned || change.profile === null ? null : undefined)
      : nonEmpty(change.profile);
    const wantedProfiles: string[] | null | undefined =
      normList !== undefined ? normList : wantedSingle !== undefined ? (wantedSingle === null ? null : [wantedSingle]) : undefined;
    const newModel = nonEmpty(change.model);
    const newEffort = nonEmpty(change.effort);
    const allowed = (p: Profile) => this.allows(key, p);
    if (change.runtime !== undefined && change.runtime !== row.runtime) {
      const target = runtimeNamed(change.runtime);
      if (!target) throw new Error(`unknown runtime ${change.runtime}`);
      const model = newModel ?? null;
      const candidates = config.profiles.filter((p) => p.runtimes.includes(target) && this.allows(key, p));
      if (candidates.length === 0) throw new Error(t("station.session.noProfileHere", { runtime: runtimeTitle(target) }));
      if (model !== null && !candidates.some((p) => runs(p, model))) throw new Error(t("station.session.noProfileForModel", { model, runtime: runtimeTitle(target) }));
      let picked: Profile | undefined;
      const nextProfiles = Array.isArray(wantedProfiles) ? wantedProfiles : null;
      if (nextProfiles !== null) {
        const subset: Profile[] = [];
        for (const id of nextProfiles) {
          const found = candidates.find((p) => p.id === id);
          if (!found) throw new Error(`unknown profile ${id}`);
          if (model !== null && !runs(found, model)) throw new Error(t("station.session.modelOff", { profile: found.name, model }));
          subset.push(found);
        }
        picked = subset.length === 1 ? subset[0] : this.pick(subset, model, true, key);
      } else {
        picked = this.pick(candidates, model, true, key);
      }
      if (!picked) throw new Error(`unknown profile ${nextProfiles?.[0] ?? ""}`);
      const effort = newEffort ?? null;
      if (effort !== null) {
        const efforts = this.modelEfforts(target, model, nextProfiles, allowed);
        if (!efforts.includes(effort)) throw new Error(t("station.profile.efforts", { runtime: runtimeTitle(target), efforts: efforts.join(t("station.list.separator")) }));
      }
      if (change.fast != null && !FAST_RUNTIMES.includes(target)) throw new Error(t("station.session.fastOpenAiOnly"));
      checkContext(target, change.context, lang);
      return { row, runtime: target, model, effort, profile: picked.id, profiles: nextProfiles, pinned: nextProfiles?.length === 1, repick: false };
    }
    if (change.fast !== undefined && change.fast !== null && !FAST_RUNTIMES.includes(runtime)) throw new Error(t("station.session.fastOpenAiOnly"));
    checkContext(runtime, change.context, lang);
    if (Array.isArray(wantedProfiles)) {
      const model = newModel !== undefined ? newModel : row.model;
      for (const id of wantedProfiles) {
        const next = config.profiles.find((p) => p.id === id);
        if (!next) throw new Error(`unknown profile ${id}`);
        if (next.enabled === false) throw new Error(t("station.profile.disabled", { profile: next.name }));
        if (!next.runtimes.includes(runtime)) throw new Error(t("station.profile.cannotRun", { profile: next.name, runtime: name }));
        if (!allowed(next)) throw new Error(t("station.profile.notHere", { profile: next.name }));
        if (model !== null && !runs(next, model)) throw new Error(t("station.session.modelOff", { profile: next.name, model }));
      }
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
    const remodelProfiles = () => {
      if (row.profilePinned || !row.profiles || row.profiles.length === 0) return null;
      const kept = row.profiles.filter((id) => {
        const p = config.profiles.find((x) => x.id === id);
        return p !== undefined && p.runtimes.includes(runtime) && allowed(p) && (model === null || runs(p, model));
      });
      return kept.length > 0 ? kept : null;
    };
    const nextProfiles: string[] | null | undefined = wantedProfiles !== undefined ? wantedProfiles : remodel ? remodelProfiles() : undefined;
    if (effort !== null && (newEffort !== undefined || wantedProfiles !== undefined || remodel)) {
      const effectiveProfiles = nextProfiles !== undefined ? nextProfiles : (row.profiles ?? (row.profilePinned ? [row.profile] : null));
      const efforts = this.modelEfforts(runtime, model, effectiveProfiles, allowed);
      if (!efforts.includes(effort)) throw new Error(t("station.profile.efforts", { runtime: name, efforts: efforts.join(t("station.list.separator")) }));
    }
    const profile = nextProfiles === undefined ? undefined : nextProfiles !== null && nextProfiles.length === 1 ? nextProfiles[0]! : null;
    const canRepick = change.repick === true && (nextProfiles === undefined ? !row.profilePinned : nextProfiles === null || nextProfiles.length > 1);
    return { row, runtime, model, effort, profile, profiles: nextProfiles, pinned: undefined, repick: canRepick };
  }
}
