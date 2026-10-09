// What the core keeps in sync with still.fail cloud (or the account provider in its place: account-provider.ts), by
// itself, whatever the UI shows (docs/core-ts.md, rule 6): each signed-in account's `/v1/events` socket, held for as long as the account is signed in; its `/v1/me` (whom it
// reaches), each workspace it reaches, its signed-in devices, and an operator's lists. The topics that show them only
// read the records (data.ts). Every time a socket opens, the account is read again (nothing is replayed); its events
// say what changed. A write to still.fail cloud answers once what it changed is read again.
import { Effect, Exit, Fiber, Scope } from "effect";
import type { AccountView } from "../accounts.ts";
import { NOT_BETA, notBetaText, readCredential, type Credential } from "../cloud.ts";
import { CREDENTIAL_FOR_S, CREDENTIAL_KEY, CREDENTIAL_OTHERS, CREDENTIAL_OTHERS_KEPT, entriesOf, PUSH_KEY, relaysOf, type Inner } from "../core.ts";
import { CoreError, asCoreError } from "../error.ts";
import type { Pull } from "../host.ts";
import { current, t } from "../i18n.ts";
import { encode } from "../ops.ts";
import { topicKey, type Topic } from "../protocol.ts";
import { CLOUD } from "../status.ts";
import { GONE, NETWORK } from "../wake.ts";
import { isObject, parseJson, pointer, toJsonBytes } from "../util.ts";
import { Priority } from "./scheduler.ts";

/// The first wait before an events socket is opened again; it doubles up to a minute, back to the first after one
/// held a minute.
export const SOCKET_RETRY_MS = 1_000;
export const SOCKET_RETRY_MAX_MS = 60_000;
/// An events socket that answered a ping before and then heard nothing this long is opened again.
export const SOCKET_IDLE_MS = 2 * 25_000 + 10_000;
export { EVENTS_PROTOCOL } from "../account-provider.ts";
/// still.fail cloud's operator lists.
export const ADMIN_LISTS = ["users", "workspaces", "invite-codes", "feedback"];

export class CloudSync {
  readonly #core: Inner;
  /// Whether each account's latest `/v1/me` answered this run (null), or why it failed.
  readonly mes = new Map<string, CoreError | null>();
  /// Told each time an account's events socket opens (what else is read again then).
  onOpen: () => void = () => {};
  /// What a workspace read last failed with, while nothing is held of it.
  readonly errors = new Map<string, CoreError>();
  /// Each account's socket, while it is signed in.
  readonly #sockets = new Map<string, Fiber.Fiber<void, never>>();
  /// The relays the mesh uses, as the first `/v1/me` of this run or the kept one said.
  relays: string[] | null = null;
  /// Told the relays and entries the first `/v1/me` of this run names (the mesh may be up on those kept from the last).
  onRelays: ((relays: string[], entries: string[]) => void) | null = null;
  /// Told when the stations each account reaches may have changed (the station sync follows).
  onReach: (() => void) | null = null;
  /// Whose operator lists are synced (as `admin.me` answered).
  readonly #admins = new Set<string>();

  constructor(core: Inner) {
    this.#core = core;
  }

  /// Starts keeping still.fail cloud's data current: whom each account reaches, from what is held first.
  start(): void {
    this.recomputeOwners();
    // Each account's socket reads the account as it opens (or, failing its first try, at once).
    this.syncSockets();
  }

  // ── what the topics read ──

  /// A station's name by its address, as its workspace is held.
  nameOf(address: string): string | null {
    const at = address.indexOf("/");
    if (at < 0) return null;
    const workspace = this.#core.data.shared({ topic: "workspace", workspace: address.slice(0, at) });
    const id = address.slice(at + 1);
    const stations = isObject(workspace) && Array.isArray(workspace.stations) ? workspace.stations : [];
    const station = stations.find((s) => isObject(s) && s.id === id);
    return isObject(station) && typeof station.name === "string" ? station.name : null;
  }

  /// Every account with what its `/v1/me` said. `loaded` only once it answered this run.
  workspacesValue(): unknown {
    const core = this.#core;
    return core.accounts.list().map((account) => {
      const record = core.data.record("me", account.sub);
      const me = isObject(record) ? record : {};
      const entry: Record<string, unknown> = {
        account,
        workspaces: me.workspaces === undefined ? [] : me.workspaces,
        invitations: me.invitations === undefined ? [] : me.invitations,
        relay_url: me.relay_url === undefined ? null : me.relay_url,
        loaded: this.mes.has(account.sub) && this.mes.get(account.sub) === null,
      };
      if (pointer(record, "/user/beta") === true) entry.beta = true;
      const error = this.mes.get(account.sub);
      if (error) {
        entry.error = error;
        if (error.code === NOT_BETA) entry.blocked = notBetaText();
      }
      return entry;
    });
  }

  /// A workspace topic with nothing held: why, once it is known no account reaches it (or its read failed).
  workspaceError(workspace: string): CoreError | null {
    const failed = this.errors.get(workspace);
    if (failed) return failed;
    const accounts = this.#core.accounts.list();
    // Not known yet while an account has not answered.
    if (accounts.some((a) => !this.mes.has(a.sub))) return null;
    if (this.#core.workspaces.owner(workspace) !== null) return null;
    return new CoreError("not_found", t("core-misc.account.no_access"), 404);
  }

  /// A topic of an account's that failed while nothing is held of it.
  topicError(topic: Topic): CoreError | null {
    return this.errors.get(topicKey(topic)) ?? null;
  }

  // ── reading still.fail cloud ──

  /// An account's `/v1/me`, then what it reaches: its workspaces, its devices, an operator's lists.
  #account(sub: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.#me(sub);
      const me = this.#core.data.record("me", sub);
      const ids = (isObject(me) && Array.isArray(me.workspaces) ? me.workspaces : []).flatMap((w) => (isObject(w) && typeof w.id === "string" ? [w.id] : []));
      const scheduler = this.#core.scheduler;
      for (const id of ids) if (this.#core.workspaces.owner(id) === sub) scheduler.enqueue("cloud", `workspace/${id}`, Priority.background, this.#workspace(id));
      // What only some providers have: login sessions, an operator's lists.
      if (this.#core.provider.supports("loginSessions")) scheduler.enqueue("cloud", `sessions/${sub}`, Priority.background, this.#loginSessions(sub));
      if (this.#core.provider.supports("admin")) scheduler.enqueue("cloud", `admin/${sub}`, Priority.background, this.#admin(sub));
    });
  }

  /// Every account read again, waited on (after a write to still.fail cloud: the call answers once it is; a write by
  /// one account may change what another sees, an invitation to it).
  refreshAll(): Effect.Effect<void> {
    return Effect.all(
      this.#core.accounts.list().map((a) => this.refreshAccount(a.sub)),
      { concurrency: "unbounded", discard: true },
    );
  }

  /// Everything of an account read again, waited on.
  refreshAccount(sub: string): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const scheduler = this.#core.scheduler;
      yield* Effect.ignore(scheduler.ask("cloud", `me/${sub}`, Priority.asked, this.#me(sub)));
      const me = this.#core.data.record("me", sub);
      const ids = (isObject(me) && Array.isArray(me.workspaces) ? me.workspaces : []).flatMap((w) => (isObject(w) && typeof w.id === "string" ? [w.id] : []));
      const reads = ids.filter((id) => this.#core.workspaces.owner(id) === sub).map((id) => Effect.ignore(scheduler.ask("cloud", `workspace/${id}`, Priority.asked, this.#workspace(id))));
      if (this.#core.provider.supports("loginSessions")) reads.push(Effect.ignore(scheduler.ask("cloud", `sessions/${sub}`, Priority.asked, this.#loginSessions(sub))));
      if (this.#admins.has(sub)) reads.push(Effect.ignore(scheduler.ask("cloud", `admin/${sub}`, Priority.asked, this.#admin(sub))));
      yield* Effect.all(reads, { concurrency: "unbounded" });
    });
  }

  #me(sub: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const core = this.#core;
      if (!core.accounts.list().some((a) => a.sub === sub)) return;
      const answer = yield* Effect.result(core.provider.me(sub));
      if (!core.accounts.list().some((a) => a.sub === sub)) return;
      if (answer._tag === "Success") {
        const relays = relaysOf(answer.success);
        const first = relays !== null && this.relays === null;
        if (first) this.relays = relays;
        core.data.put("me", sub, answer.success);
        if (first) this.onRelays?.(relays, entriesOf(answer.success));
        this.mes.set(sub, null);
      } else {
        // A beta app the account may not use: what it reached is not reached through this app.
        if (answer.failure.code === NOT_BETA) core.data.forgetRecord("me", sub);
        this.mes.set(sub, answer.failure);
      }
      this.recomputeOwners();
      this.forgetUnreachable();
      core.store.invalidate({ topic: "workspaces" });
      core.store.invalidateAll((t) => t.topic === "workspace");
    });
  }

  #workspace(id: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const core = this.#core;
      const sub = core.workspaces.owner(id);
      if (sub === null) return;
      const topic: Topic = { topic: "workspace", workspace: id };
      const answer = yield* Effect.result(core.provider.request(sub, "GET", `/v1/workspaces/${encode(id)}`, null));
      if (answer._tag === "Success") {
        this.errors.delete(id);
        this.forgetGoneStations(id, answer.success);
        core.data.set(topic, answer.success);
        this.onReach?.();
      } else {
        const error = answer.failure;
        // Gone (deleted, or the account left it): what is held of it goes.
        if (error.status === 404 || error.status === 403) {
          core.data.dropWorkspace(id);
          this.errors.set(id, error);
        } else if (core.data.get(topic) === undefined) this.errors.set(id, error);
        core.store.invalidate(topic);
      }
    });
  }

  #loginSessions(sub: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const core = this.#core;
      const topic: Topic = { topic: "loginSessions", account: sub };
      const answer = yield* Effect.result(core.provider.request(sub, "GET", "/v1/auth/sessions", null));
      if (answer._tag === "Success") {
        const sessions = isObject(answer.success) ? answer.success.sessions : undefined;
        this.errors.delete(topicKey(topic));
        core.data.set(topic, sessions === undefined ? [] : sessions);
      } else if (core.data.get(topic) === undefined) {
        this.errors.set(topicKey(topic), answer.failure);
        core.store.invalidate(topic);
      }
    });
  }

  /// An operator's lists, for an account still.fail cloud says is one (`/v1/admin/me`).
  #admin(sub: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const core = this.#core;
      const me = yield* Effect.result(core.provider.request(sub, "GET", "/v1/admin/me", null));
      if (me._tag === "Failure") {
        this.#admins.delete(sub);
        return;
      }
      this.#admins.add(sub);
      yield* Effect.all(
        ADMIN_LISTS.map((list) =>
          Effect.gen({ self: this }, function* () {
            const topic: Topic = { topic: "admin", account: sub, list };
            const answer = yield* Effect.result(core.provider.request(sub, "GET", `/v1/admin/${list}`, null));
            if (answer._tag === "Success") {
              this.errors.delete(topicKey(topic));
              core.data.set(topic, answer.success);
            } else if (core.data.get(topic) === undefined) {
              this.errors.set(topicKey(topic), answer.failure);
              core.store.invalidate(topic);
            }
          }),
        ),
        { concurrency: "unbounded" },
      );
    });
  }

  /// Which account reaches each workspace: the first (in sign-in order) whose last `/v1/me` lists it. An account
  /// signed out: what it reached goes, with its credentials.
  recomputeOwners(): void {
    const core = this.#core;
    const accounts = core.accounts.list();
    for (const sub of [...this.mes.keys()]) if (!accounts.some((a) => a.sub === sub)) this.mes.delete(sub);
    const owners = new Map<string, string>();
    for (const account of accounts) {
      const me = core.data.record("me", account.sub);
      for (const w of isObject(me) && Array.isArray(me.workspaces) ? me.workspaces : []) {
        if (isObject(w) && typeof w.id === "string" && !owners.has(w.id)) owners.set(w.id, account.sub);
      }
    }
    core.workspaces.setOwners(owners);
    core.store.invalidateAll((t) => t.topic === "status" && typeof t.workspace === "string");
    this.onReach?.();
  }

  /// An account signed out (its database goes with all it held): the credentials it had for its workspaces go too.
  signedOut(sub: string, me: unknown): void {
    const core = this.#core;
    for (const w of isObject(me) && Array.isArray(me.workspaces) ? me.workspaces : []) {
      if (!isObject(w) || typeof w.id !== "string") continue;
      const key = `${CREDENTIAL_KEY}/${sub}/${w.id}`;
      core.runner.fork(Effect.all([Effect.ignore(core.host.storageDelete(`${key}/${CREDENTIAL_OTHERS}`)), Effect.ignore(core.host.storageDelete(key))]));
    }
  }

  /// What is held of stations no signed-in account reaches any more goes — decided only once every account's
  /// `/v1/me` is known, since one not heard from may reach them.
  forgetUnreachable(): void {
    const core = this.#core;
    if (core.accounts.list().some((a) => core.data.record("me", a.sub) === undefined)) return;
    const workspaces = new Set(core.workspaces.owned().map(([id]) => id));
    core.data.retain((station) => {
      const at = station.indexOf("/");
      return at >= 0 && workspaces.has(station.slice(0, at));
    }, workspaces);
  }

  /// A workspace's stations as it lists them now: what is held of the others in it goes.
  forgetGoneStations(workspace: string, view: unknown): void {
    const stations = isObject(view) && Array.isArray(view.stations) ? view.stations : [];
    const ids = new Set(stations.flatMap((s) => (isObject(s) && typeof s.id === "string" ? [s.id] : [])));
    this.#core.data.retain((station) => {
      const at = station.indexOf("/");
      return at < 0 || station.slice(0, at) !== workspace || ids.has(station.slice(at + 1));
    }, null);
  }

  /// The signed-in account that reaches `workspace`, reading every account's `/v1/me` if it is not known yet.
  owner(workspace: string): Effect.Effect<string, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const core = this.#core;
      const known = () => {
        const sub = core.workspaces.owner(workspace);
        return sub !== null && core.accounts.list().some((a) => a.sub === sub) ? sub : null;
      };
      const first = known();
      if (first !== null) return first;
      yield* Effect.all(
        core.accounts.list().map((a) => Effect.ignore(core.scheduler.ask("cloud", `me/${a.sub}`, Priority.asked, this.#me(a.sub)))),
        { concurrency: "unbounded" },
      );
      const after = known();
      if (after === null) return yield* Effect.fail(new CoreError("not_found", t("core-misc.account.no_access"), 404));
      return after;
    });
  }

  /// The relays the mesh uses, from any account's `/v1/me`.
  relaysNow(): Effect.Effect<string[], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.relays) return this.relays;
      const core = this.#core;
      for (const account of core.accounts.list()) {
        const r = relaysOf(core.data.record("me", account.sub));
        if (r) return r;
      }
      let last = CoreError.signedOut(t("core-misc.account.none"));
      for (const account of core.accounts.list()) {
        yield* Effect.ignore(core.scheduler.ask("cloud", `me/${account.sub}`, Priority.asked, this.#me(account.sub)));
        const r = relaysOf(core.data.record("me", account.sub));
        if (r) return r;
        last = this.mes.get(account.sub) ?? last;
      }
      return yield* Effect.fail(last);
    });
  }

  /// The relay entries any account's `/v1/me` named, as held now (`entriesOf`); none from a cloud from before them.
  entriesNow(): string[] {
    for (const account of this.#core.accounts.list()) {
      const entries = entriesOf(this.#core.data.record("me", account.sub));
      if (entries.length > 0) return entries;
    }
    return [];
  }

  /// A workspace's own relays, as its members' `/v1/me` name them: used besides still.fail's for its stations alone.
  workspaceRelays(workspace: string): string[] {
    for (const account of this.#core.accounts.list()) {
      const me = this.#core.data.record("me", account.sub);
      const found = (isObject(me) && Array.isArray(me.workspaces) ? me.workspaces : []).find((w) => isObject(w) && w.id === workspace);
      if (isObject(found) && Array.isArray(found.relays)) return found.relays.filter((u): u is string => typeof u === "string");
    }
    return [];
  }

  /// This device's member credential for a workspace, kept on the device: what gets it into the workspace's stations
  /// with no still.fail cloud on the way. Kept, it serves for a day; then, or when a station refused it (`fresh`), a
  /// new one is asked for — and if still.fail cloud cannot be reached, the kept one serves until it runs out. `main`:
  /// the mesh's device key, when the mesh is up (another key's are kept apart).
  credential(workspace: string, device: string, fresh: boolean, main: string | null): Effect.Effect<Credential, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const core = this.#core;
      const sub = yield* this.owner(workspace);
      const key = `${CREDENTIAL_KEY}/${sub}/${workspace}`;
      const othersKey = `${key}/${CREDENTIAL_OTHERS}`;
      const other = main !== null && main !== device;
      const now = core.host.nowMs() / 1000;
      const read = (k: string) => Effect.map(Effect.orElseSucceed(core.host.storageGet(k), () => null), parseJson);
      let others: KeptCredential[] = [];
      if (other) {
        const raw = yield* read(othersKey);
        if (Array.isArray(raw)) {
          const parsed = raw.map(readKept);
          others = parsed.every((k) => k !== null) ? (parsed as KeptCredential[]) : [];
        }
      }
      let keptOne: KeptCredential | null;
      if (other) keptOne = others.find((k) => k.device === device) ?? null;
      else {
        const k = readKept(yield* read(key));
        keptOne = k && k.device === device ? k : null;
      }
      const kept: Credential | null = keptOne && keptOne.expires_at > now + 60 && !fresh ? strip(keptOne) : null;
      if (kept && now - kept.issued_at < CREDENTIAL_FOR_S) return kept;
      const asked = yield* Effect.result(core.provider.credential(sub, workspace, device));
      if (asked._tag === "Failure") {
        if (kept) return kept;
        return yield* Effect.fail(asked.failure);
      }
      const c = asked.success;
      const k: KeptCredential = { device, ...c };
      if (other) {
        others = [k, ...others.filter((o) => o.device !== device)].slice(0, CREDENTIAL_OTHERS_KEPT);
        yield* Effect.ignore(core.host.storageSet(othersKey, toJsonBytes(others)));
      } else yield* Effect.ignore(core.host.storageSet(key, toJsonBytes(k)));
      return c;
    });
  }

  /// Gives this device's push registration (as kept) to the signed-in accounts that do not have it yet.
  pushRegistered(): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const core = this.#core;
      // A provider that delivers pushes its own way (Comma: its app's) is given none.
      if (!core.provider.supports("push")) return null;
      const raw = parseJson(yield* Effect.orElseSucceed(core.host.storageGet(PUSH_KEY), () => null));
      if (!isObject(raw) || !("registration" in raw)) return null;
      const accounts = core.accounts.list();
      let withSubs = (Array.isArray(raw.with) ? raw.with : []).filter((s): s is string => typeof s === "string" && accounts.some((a) => a.sub === s));
      let lang = typeof raw.lang === "string" ? raw.lang : null;
      const code = current();
      if (lang !== code) {
        withSubs = [];
        lang = code;
      }
      const registration = raw.registration;
      if (isObject(registration)) registration.lang = code;
      let failed: CoreError | null = null;
      for (const account of accounts.filter((a) => !withSubs.includes(a.sub))) {
        const sent = yield* Effect.result(core.provider.request(account.sub, "POST", "/v1/push", registration));
        if (sent._tag === "Success") withSubs.push(account.sub);
        else failed = sent.failure;
      }
      yield* Effect.ignore(core.host.storageSet(PUSH_KEY, toJsonBytes({ registration, with: withSubs, lang })));
      if (failed) return yield* Effect.fail(failed);
      return null;
    });
  }

  /// The accounts as UIs see them changed (a token refresh alone changes nothing here).
  accountsChanged(): void {
    const core = this.#core;
    const list = core.accounts.list();
    if (JSON.stringify(core.shownAccounts) === JSON.stringify(list)) return;
    const before = new Set(core.shownAccounts.map((a) => a.sub));
    core.shownAccounts = list;
    this.recomputeOwners();
    this.forgetUnreachable();
    core.store.invalidate({ topic: "accounts" });
    core.store.invalidate({ topic: "workspaces" });
    core.store.invalidateAll((t) => t.topic === "workspace");
    this.syncSockets();
    void before;
    // Someone signed in: their devices hear pushes too.
    core.runner.fork(Effect.ignore(this.pushRegistered()));
  }

  // ── still.fail cloud's events ──

  /// One socket per signed-in account, for as long as it is signed in.
  syncSockets(): void {
    const core = this.#core;
    if (core.runner.closed) return;
    const wanted = core.accounts.list().map((a: AccountView) => a.sub);
    for (const [sub, fiber] of [...this.#sockets]) {
      if (wanted.includes(sub)) continue;
      core.runner.interrupt(fiber as Fiber.Fiber<unknown, unknown>);
      this.#sockets.delete(sub);
      core.status.socketUp(sub);
    }
    for (const sub of wanted) if (!this.#sockets.has(sub)) this.#sockets.set(sub, core.runner.fork(this.#follow(sub)));
  }

  /// Opens an account's events (still.fail cloud's socket, with a token good now), in the caller's scope.
  #open(sub: string) {
    return this.#core.provider.events(sub);
  }

  #onEvent(sub: string, text: string): void {
    const core = this.#core;
    const event = parseJson(text);
    if (!isObject(event)) return;
    if (event.type === "workspaces") core.scheduler.enqueue("cloud", `me/${sub}`, Priority.shown, this.#account(sub));
    else if (event.type === "workspace" && typeof event.id === "string") {
      if (core.workspaces.owner(event.id) !== null) core.scheduler.enqueue("cloud", `workspace/${event.id}`, Priority.shown, this.#workspace(event.id));
    } else if (event.type === "station" && typeof event.workspace === "string" && typeof event.id === "string" && typeof event.online === "boolean") {
      // A station came online or went: in place, no request (docs/client-core.md).
      const online = event.online;
      const id = event.id;
      core.data.update({ topic: "workspace", workspace: event.workspace }, (w) => {
        const station = isObject(w) && Array.isArray(w.stations) ? w.stations.find((s) => isObject(s) && s.id === id) : undefined;
        if (isObject(station)) {
          station.online = online;
          station.last_seen = Math.floor(core.host.nowMs() / 1000);
        }
        return w;
      });
      // Back: tried now rather than when its wait ends (station/sync.ts OFFLINE_RETRY_MS).
      if (online) core.stations?.cameOnline(`${event.workspace}/${id}`);
      this.onReach?.();
    }
  }

  /// Holds an account's `/v1/events` socket open, reconnecting with backoff, until the account signs out (the fiber
  /// is interrupted). Each open reads the account again; a socket that answered pings and went silent is opened anew;
  /// one suspected as the UI comes back has another opened beside it, which takes its place once open.
  #follow(sub: string): Effect.Effect<void, never> {
    const core = this.#core;
    const self = this;
    type Opened = { frames: Pull<string>; scope: Scope.Closeable };
    type Ev = { frame: string | null } | { broke: CoreError } | { idle: true } | { suspect: true } | { beside: Opened };
    // A socket in a scope of its own inside `scope`: one replaced by another is closed alone.
    const openIn = (scope: Scope.Scope) =>
      Effect.gen(function* () {
        const own = yield* Scope.fork(scope);
        const frames = yield* Effect.provideService(self.#open(sub), Scope.Scope, own).pipe(Effect.onError(() => Scope.close(own, Exit.void)));
        return { frames, scope: own } as Opened;
      });
    // One connection of the socket: open, read until it ends; what it ends as.
    type Ended = { failed: CoreError } | { ended: string; again: boolean };
    const connection = (wait: { ms: number }): Effect.Effect<Ended> =>
      Effect.scoped(
        Effect.gen(function* () {
          const scope = yield* Effect.scope;
          const waiting = core.status.begin(CLOUD, t("core-misc.status.connect"), true);
          const opened = yield* Effect.result(openIn(scope).pipe(Effect.ensuring(Effect.sync(() => waiting.end()))));
          if (opened._tag === "Failure") return { failed: opened.failure } as Ended;
          let socket = opened.success;
          let frames = socket.frames;
          const openedAt = core.host.nowMs();
          self.onOpen();
          core.status.socketUp(sub);
          // Nothing is replayed: what changed while it was closed is read now.
          core.scheduler.enqueue("cloud", `me/${sub}`, Priority.shown, self.#account(sub));
          let answers = false;
          let woke = false;
          let idle = false;
          let beside: Effect.Effect<Ev> | null = null;
          for (;;) {
            const racers: Effect.Effect<Ev>[] = [
              frames.take.pipe(
                Effect.map((frame): Ev => ({ frame })),
                Effect.catch((e) => Effect.succeed<Ev>({ broke: asCoreError(e) })),
              ),
            ];
            if (answers) racers.push(Effect.sleep(SOCKET_IDLE_MS).pipe(Effect.as<Ev>({ idle: true })));
            racers.push(beside ?? core.wakes.until((w) => w.suspectsConnections()).pipe(Effect.as<Ev>({ suspect: true })));
            const ev = yield* Effect.raceAllFirst(racers);
            if ("frame" in ev) {
              if (ev.frame === null) break;
              if (ev.frame === "pong") answers = true;
              else self.#onEvent(sub, ev.frame);
            } else if ("broke" in ev) {
              const m = ev.broke.message;
              woke = m === GONE || m === NETWORK || m === t("core-misc.wake.gone") || m === t("core-misc.wake.network");
              break;
            } else if ("idle" in ev) {
              idle = true;
              break;
            } else if ("suspect" in ev) {
              // Another opened beside it; the old one stays watched meanwhile.
              const opening = yield* Effect.forkIn(
                openIn(scope).pipe(
                  Effect.map((f): Ev => ({ beside: f })),
                  Effect.catch(() => Effect.never as Effect.Effect<Ev>),
                ),
                scope,
              );
              beside = Fiber.join(opening);
            } else {
              beside = null;
              yield* Scope.close(socket.scope, Exit.void);
              socket = ev.beside;
              frames = socket.frames;
              answers = false;
              core.scheduler.enqueue("cloud", `me/${sub}`, Priority.shown, self.#account(sub));
            }
          }
          if (woke || idle || core.host.nowMs() - openedAt >= 60_000) wait.ms = SOCKET_RETRY_MS;
          return { ended: idle ? t("core-misc.socket.silent") : t("core-misc.socket.dropped"), again: woke || idle } as Ended;
        }),
      );
    return Effect.gen(function* () {
      const wait = { ms: SOCKET_RETRY_MS };
      let first = true;
      for (;;) {
        const ended = yield* connection(wait);
        let down: string;
        if ("failed" in ended && first) {
          // Its first try failed: the account is read anyway, so what can be shown is.
          core.scheduler.enqueue("cloud", `me/${sub}`, Priority.shown, self.#account(sub));
        }
        first = false;
        if ("failed" in ended) {
          if (ended.failed.code === "signed_out") {
            self.#sockets.delete(sub);
            core.status.socketUp(sub);
            return;
          }
          down = ended.failed.message;
        } else {
          down = ended.ended;
          // Taken for gone as the UI came back, or silent: opened again at once.
          if (ended.again) continue;
        }
        core.status.socketDown(sub, down, core.host.nowMs() + wait.ms);
        // A UI back after being away wants it now: the wait starts over.
        const woken = yield* Effect.raceFirst(Effect.sleep(wait.ms).pipe(Effect.as(false)), core.wakes.next.pipe(Effect.as(true)));
        wait.ms = woken ? SOCKET_RETRY_MS : Math.min(wait.ms * 2, SOCKET_RETRY_MAX_MS);
      }
    });
  }
}

type KeptCredential = Credential & { device: string };

function readKept(v: unknown): KeptCredential | null {
  if (!isObject(v) || typeof v.device !== "string") return null;
  const c = readCredential(v);
  return typeof c === "string" ? null : { ...c, device: v.device };
}

function strip(k: KeptCredential): Credential {
  return { credential: k.credential, issued_at: k.issued_at, expires_at: k.expires_at, relay_url: k.relay_url };
}

