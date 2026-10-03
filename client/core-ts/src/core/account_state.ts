// Accounts, workspace ownership, credentials and cloud topic refresh (core/account_state.rs), and still.fail cloud's
// events sockets (core.rs `follow_socket`).
import { Effect } from "effect";
import { readCredential, NOT_BETA, notBetaText, type Credential } from "../cloud.ts";
import { CREDENTIAL_FOR_S, CREDENTIAL_KEY, CREDENTIAL_OTHERS, CREDENTIAL_OTHERS_KEPT, EVENTS_PROTOCOL, PUSH_KEY, SOCKET_IDLE_MS, SOCKET_RETRY_MAX_MS, SOCKET_RETRY_MS, relaysOf, type Inner, type SocketState } from "../core.ts";
import { holds } from "../data.ts";
import { CoreError, asCoreError } from "../error.ts";
import type { SocketFrames } from "../host.ts";
import { current, t } from "../i18n.ts";
import { encode } from "../ops.ts";
import { topicKey, type Topic } from "../protocol.ts";
import { CLOUD } from "../status.ts";
import { GONE, NETWORK, wokenFor } from "../wake.ts";
import { isObject, parseJson, pointer, toJsonBytes } from "../util.ts";

/// A station's name by its address, as its workspace was last read (for what the status says).
export function nameOf(inner: Inner, address: string): string | null {
  const at = address.indexOf("/");
  if (at < 0) return null;
  const workspace = inner.store.get({ topic: "workspace", workspace: address.slice(0, at) });
  const id = address.slice(at + 1);
  const stations = isObject(workspace) && Array.isArray(workspace.stations) ? workspace.stations : [];
  const station = stations.find((s) => isObject(s) && s.id === id);
  return isObject(station) && typeof station.name === "string" ? station.name : null;
}

/// Where what is read or pushed goes: the data center's topics to the data center, the rest to the store. A failed
/// read shows only while nothing is known.
export function centerSet(inner: Inner, topic: Topic, value: { ok: unknown } | { err: CoreError }): void {
  if (!holds(topic)) return inner.store.set(topic, value);
  if ("ok" in value) {
    const shown = inner.store.value(topic);
    if (shown && "err" in shown) inner.store.set(topic, { ok: value.ok });
    inner.data.set(topic, value.ok);
  } else if (inner.data.get(topic) === undefined) inner.store.set(topic, value);
}

type KeptCredential = Credential & { device: string };

function readKept(v: unknown): KeptCredential | null {
  if (!isObject(v) || typeof v.device !== "string") return null;
  const c = readCredential(v);
  return typeof c === "string" ? null : { ...c, device: v.device };
}

/// This device's member credential for a workspace, kept on the device: what gets it into the workspace's stations
/// with no still.fail cloud on the way. Kept, it serves for a day; then, or when a station refused it (`fresh`), a new
/// one is asked for — and if still.fail cloud cannot be reached, the kept one goes on serving until it runs out.
/// `main`: the mesh's device key, when the mesh is up (another key's are kept apart).
export async function credential(inner: Inner, workspace: string, device: string, fresh: boolean, main: string | null): Promise<Credential> {
  const sub = await owner(inner, workspace);
  const key = `${CREDENTIAL_KEY}/${sub}/${workspace}`;
  const othersKey = `${key}/${CREDENTIAL_OTHERS}`;
  const other = main !== null && main !== device;
  const now = inner.host.nowMs() / 1000;
  let others: KeptCredential[] = [];
  if (other) {
    const raw = parseJson(await inner.host.storageGet(othersKey).catch(() => null));
    if (Array.isArray(raw)) {
      const read = raw.map(readKept);
      others = read.every((k) => k !== null) ? (read as KeptCredential[]) : [];
    }
  }
  let keptOne: KeptCredential | null;
  if (other) keptOne = others.find((k) => k.device === device) ?? null;
  else {
    const k = readKept(parseJson(await inner.host.storageGet(key).catch(() => null)));
    keptOne = k && k.device === device ? k : null;
  }
  const keptCred: Credential | null = keptOne && keptOne.expires_at > now + 60 && !fresh ? strip(keptOne) : null;
  if (keptCred && now - keptCred.issued_at < CREDENTIAL_FOR_S) return keptCred;
  try {
    const c = await inner.cloud.credential(sub, workspace, device);
    const k: KeptCredential = { device, ...c };
    if (other) {
      others = others.filter((o) => o.device !== device);
      others.unshift(k);
      others = others.slice(0, CREDENTIAL_OTHERS_KEPT);
      await inner.host.storageSet(othersKey, toJsonBytes(others)).catch(() => undefined);
    } else await inner.host.storageSet(key, toJsonBytes(k)).catch(() => undefined);
    return c;
  } catch (e) {
    if (keptCred) return keptCred;
    throw asCoreError(e);
  }
}

function strip(k: KeptCredential): Credential {
  return { credential: k.credential, issued_at: k.issued_at, expires_at: k.expires_at, relay_url: k.relay_url };
}

/// The relays the mesh uses, from any account's `/v1/me`.
export async function relays(inner: Inner): Promise<string[]> {
  if (inner.relays) return inner.relays;
  for (const account of inner.accounts.list()) {
    const r = relaysOf(inner.data.record("me", account.sub));
    if (r) return r;
  }
  let last = CoreError.signedOut(t("core-misc.account.none"));
  for (const [, me] of await loadMe(inner)) {
    if ("ok" in me) {
      const r = relaysOf(me.ok);
      if (r) return r;
    } else last = me.err;
  }
  throw last;
}

/// The signed-in account that reaches `workspace`, asking every account's `/v1/me` if it is not known yet.
export async function owner(inner: Inner, workspace: string): Promise<string> {
  const known = () => {
    const sub = inner.workspaces.owner(workspace);
    return sub !== null && inner.accounts.list().some((a) => a.sub === sub) ? sub : null;
  };
  const first = known();
  if (first !== null) return first;
  await loadMe(inner);
  const after = known();
  if (after === null) throw new CoreError("not_found", t("core-misc.account.no_access"), 404);
  return after;
}

/// Every account's `/v1/me`, noting who reaches which workspace and the relay url on the way. One at a time.
export async function loadMe(inner: Inner): Promise<[import("../accounts.ts").AccountView, { ok: unknown } | { err: CoreError }][]> {
  if (!inner.meLoading) {
    inner.meLoading = (async () => {
      try {
        await loadMeOf(inner, inner.accounts.list());
      } finally {
        inner.meLoading = null;
      }
    })();
  }
  await inner.meLoading;
  return inner.accounts.list().map((a) => {
    const m = inner.mes.get(a.sub);
    if (m === undefined) return [a, { err: CoreError.signedOut(t("core-misc.account.signed_out")) }];
    if (m !== null) return [a, { err: m }];
    const record = inner.data.record("me", a.sub);
    return [a, record === undefined ? { err: CoreError.signedOut(t("core-misc.account.signed_out")) } : { ok: record }];
  });
}

/// These accounts' `/v1/me`, kept per account; an answer overtaken by a newer request is dropped.
export async function loadMeOf(inner: Inner, accounts: import("../accounts.ts").AccountView[]): Promise<void> {
  const asked = accounts.map((a) => {
    const n = (inner.meFetches.get(a.sub) ?? 0) + 1;
    inner.meFetches.set(a.sub, n);
    return n;
  });
  const answers = await Promise.all(
    accounts.map((a) =>
      inner.cloud.me(a.sub).then(
        (ok) => ({ ok }),
        (e) => ({ err: asCoreError(e) }),
      ),
    ),
  );
  accounts.forEach((account, i) => {
    if (inner.meFetches.get(account.sub) !== asked[i]) return;
    const me = answers[i];
    if ("ok" in me) {
      const r = relaysOf(me.ok);
      if (r) {
        const first = inner.relays === null;
        if (inner.relays === null) inner.relays = r;
        // The relay is known: bring the device endpoint up now (station links, station.ts).
        if (first) inner.meshWarm?.();
      }
      inner.data.put("me", account.sub, me.ok);
    } else if (me.err.code === NOT_BETA) {
      // A beta app the account may not use: what it reached is not reached through this app.
      inner.data.forgetRecord("me", account.sub);
    }
    inner.mes.set(account.sub, "ok" in me ? null : me.err);
  });
  recomputeOwners(inner);
  forgetUnreachable(inner);
}

/// Which account reaches each workspace: the first (in sign-in order) whose last `/v1/me` answer lists it.
export function recomputeOwners(inner: Inner): void {
  const accounts = inner.accounts.list();
  for (const sub of [...inner.mes.keys()]) if (!accounts.some((a) => a.sub === sub)) inner.mes.delete(sub);
  for (const [sub, me] of inner.data.records("me")) {
    if (accounts.some((a) => a.sub === sub)) continue;
    // Signed out: its credentials go too (a station would take them for 30 days).
    const workspaces = isObject(me) && Array.isArray(me.workspaces) ? me.workspaces : [];
    for (const w of workspaces) {
      if (isObject(w) && typeof w.id === "string") {
        const key = `${CREDENTIAL_KEY}/${sub}/${w.id}`;
        inner.runner.spawn(async () => {
          await inner.host.storageDelete(`${key}/${CREDENTIAL_OTHERS}`).catch(() => undefined);
          await inner.host.storageDelete(key).catch(() => undefined);
        });
      }
    }
    inner.data.forgetRecord("me", sub);
  }
  const owners = new Map<string, string>();
  for (const account of accounts) {
    const me = inner.data.record("me", account.sub);
    const workspaces = isObject(me) && Array.isArray(me.workspaces) ? me.workspaces : [];
    for (const w of workspaces) if (isObject(w) && typeof w.id === "string" && !owners.has(w.id)) owners.set(w.id, account.sub);
  }
  inner.workspaces.setOwners(owners);
  // A workspace's status shows its account's socket.
  inner.store.invalidateAll((t) => t.topic === "status" && typeof t.workspace === "string");
}

/// Hooks for what is kept of stations beyond the data center (kept.ts): set by the station module.
export const keptRetain: { retain: ((keep: (station: string) => boolean) => Promise<void>) | null } = { retain: null };

/// What is kept on the device of stations no signed-in account reaches any more goes — decided only when every
/// account's `/v1/me` has answered once.
export function forgetUnreachable(inner: Inner): void {
  if (inner.accounts.list().some((a) => inner.data.record("me", a.sub) === undefined)) return;
  const workspaces = new Set(inner.workspaces.owned().map(([id]) => id));
  const reached = (station: string) => {
    const at = station.indexOf("/");
    return at >= 0 && workspaces.has(station.slice(0, at));
  };
  inner.data.retain(reached, workspaces);
  const retain = keptRetain.retain;
  if (retain) inner.runner.spawn(() => retain(reached));
}

/// A workspace's stations as it lists them now: what is kept of the others in it goes.
export function forgetGoneStations(inner: Inner, workspace: string, view: unknown): void {
  const stations = isObject(view) && Array.isArray(view.stations) ? view.stations : [];
  const ids = new Set(stations.flatMap((s) => (isObject(s) && typeof s.id === "string" ? [s.id] : [])));
  const keep = (station: string) => {
    const at = station.indexOf("/");
    if (at < 0) return true;
    return station.slice(0, at) !== workspace || ids.has(station.slice(at + 1));
  };
  inner.data.retain(keep, null);
  const retain = keptRetain.retain;
  if (retain) inner.runner.spawn(() => retain(keep));
}

export function accountsValue(inner: Inner): unknown {
  return inner.accounts.list();
}

/// Every account with what its `/v1/me` said, as the data center has it. `loaded` is true only once it answered
/// this run.
export function workspacesValue(inner: Inner): unknown {
  return inner.accounts.list().map((account) => {
    const record = inner.data.record("me", account.sub);
    const me = isObject(record) ? record : {};
    const entry: Record<string, unknown> = {
      account,
      workspaces: me.workspaces === undefined ? [] : me.workspaces,
      invitations: me.invitations === undefined ? [] : me.invitations,
      relay_url: me.relay_url === undefined ? null : me.relay_url,
      loaded: inner.mes.has(account.sub) && inner.mes.get(account.sub) === null,
    };
    if (pointer(record, "/user/beta") === true) entry.beta = true;
    const error = inner.mes.get(account.sub);
    if (error) {
      entry.error = error;
      if (error.code === NOT_BETA) entry.blocked = notBetaText();
    }
    return entry;
  });
}

export async function workspaceValue(inner: Inner, workspace: string): Promise<unknown> {
  const sub = await owner(inner, workspace);
  return inner.cloud.request(sub, "GET", `/v1/workspaces/${encode(workspace)}`, null);
}

export function startTopic(inner: Inner, topic: Topic): void {
  if (topic.topic === "accounts") {
    inner.store.set(topic, { ok: accountsValue(inner) });
    return;
  }
  inner.live.set(topicKey(topic), { topic, fetch: 0 });
  // What the accounts' `/v1/me` said last time is shown at once (not `loaded`); reading it again follows.
  if (topic.topic === "workspaces" && inner.accounts.list().some((a) => inner.data.record("me", a.sub) !== undefined)) {
    inner.store.set(topic, { ok: workspacesValue(inner) });
  }
  syncSockets(inner);
  // A socket on its first try reads the topics when it opens; otherwise they are read now.
  if (![...inner.sockets.values()].some((s) => s.state === "connecting")) spawnRefresh(inner, topic);
}

export function stopTopic(inner: Inner, topic: Topic): void {
  inner.live.delete(topicKey(topic));
  syncSockets(inner);
}

export function spawnRefresh(inner: Inner, topic: Topic): void {
  inner.runner.spawn(() => refresh(inner, topic));
}

export function refresh(inner: Inner, topic: Topic): Promise<void> {
  return refreshWith(inner, topic, false);
}

/// Reads one account topic again; an answer overtaken by a newer fetch is dropped. `meRead`: every account's
/// `/v1/me` was just read.
export async function refreshWith(inner: Inner, topic: Topic, meRead: boolean): Promise<void> {
  const key = topicKey(topic);
  const live = inner.live.get(key);
  if (!live) return;
  const fetch = ++live.fetch;
  let value: { ok: unknown } | { err: CoreError };
  const settle = async (p: Promise<unknown>) => {
    try {
      return { ok: await p };
    } catch (e) {
      return { err: asCoreError(e) };
    }
  };
  switch (topic.topic) {
    case "workspaces":
      if (!meRead) await loadMe(inner);
      value = { ok: workspacesValue(inner) };
      break;
    case "workspace":
      value = await settle(workspaceValue(inner, topic.workspace as string));
      break;
    case "loginSessions":
      value = await settle(
        inner.cloud.request(topic.account as string, "GET", "/v1/auth/sessions", null).then((v) => {
          const sessions = isObject(v) ? v.sessions : undefined;
          return sessions === undefined ? [] : sessions;
        }),
      );
      break;
    case "admin": {
      const list = topic.list as string;
      value = ["users", "workspaces", "invite-codes", "feedback"].includes(list)
        ? await settle(inner.cloud.request(topic.account as string, "GET", `/v1/admin/${list}`, null))
        : { err: CoreError.invalid(t("core-misc.account.no_list")) };
      break;
    }
    default:
      return;
  }
  if (topic.topic === "workspace" && "ok" in value) forgetGoneStations(inner, topic.workspace as string, value.ok);
  if (inner.live.get(key)?.fetch === fetch) inner.centerSet(topic, value);
}

/// Gives this device's push registration (as kept) to the signed-in accounts that do not have it yet.
export async function pushRegistered(inner: Inner): Promise<null> {
  const raw = parseJson(await inner.host.storageGet(PUSH_KEY).catch(() => null));
  if (!isObject(raw) || !("registration" in raw)) return null;
  const accounts = inner.accounts.list();
  let withSubs = Array.isArray(raw.with) ? raw.with.filter((s): s is string => typeof s === "string") : [];
  withSubs = withSubs.filter((sub) => accounts.some((a) => a.sub === sub));
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
    try {
      await inner.cloud.request(account.sub, "POST", "/v1/push", registration);
      withSubs.push(account.sub);
    } catch (e) {
      failed = asCoreError(e);
    }
  }
  await inner.host.storageSet(PUSH_KEY, toJsonBytes({ registration, with: withSubs, lang })).catch(() => undefined);
  if (failed) throw failed;
  return null;
}

/// Told when the accounts change (after the core's own reaction): the modules that care (attend's pushes).
export const accountHooks: { changed: ((inner: Inner) => void)[] } = { changed: [] };

/// The accounts as UIs see them changed (a token refresh alone changes nothing here).
export function accountsChanged(inner: Inner): void {
  const list = inner.accounts.list();
  if (JSON.stringify(inner.shownAccounts) === JSON.stringify(list)) return;
  inner.shownAccounts = list;
  // Signed out: what only that account reached goes now, whether or not anything is shown.
  recomputeOwners(inner);
  forgetUnreachable(inner);
  inner.store.set({ topic: "accounts" }, { ok: accountsValue(inner) });
  syncSockets(inner);
  inner.runner.spawn(async () => {
    // Someone signed in: their devices hear pushes too.
    await pushRegistered(inner).catch(() => undefined);
    await refreshAll(inner);
  });
}

/// Reads every live account topic again: `/v1/me` once, then each.
export async function refreshAll(inner: Inner): Promise<void> {
  const topics = [...inner.live.values()].map((l) => l.topic);
  if (topics.length === 0) return;
  await loadMe(inner);
  await Promise.all(topics.map((topic) => refreshWith(inner, topic, true)));
}

// ── still.fail cloud's events ──

/// One socket per signed-in account while any account topic is live; none otherwise.
export function syncSockets(inner: Inner): void {
  if (inner.closed) return;
  const wanted = inner.live.size === 0 ? [] : inner.accounts.list().map((a) => a.sub);
  for (const [sub, socket] of [...inner.sockets]) {
    if (wanted.includes(sub)) continue;
    inner.runner.interrupt(socket.fiber);
    inner.sockets.delete(sub);
    inner.status.socketUp(sub);
  }
  for (const sub of wanted) {
    if (inner.sockets.has(sub)) continue;
    const entry = { fiber: null as never, state: "connecting" as SocketState };
    inner.sockets.set(sub, entry);
    entry.fiber = inner.runner.fork(followSocket(inner, sub)) as never;
  }
}

/// Notes a socket's state; answers the one before.
export function socketState(inner: Inner, sub: string, state: SocketState): SocketState | undefined {
  const s = inner.sockets.get(sub);
  if (!s) return undefined;
  const before = s.state;
  s.state = state;
  return before;
}

/// Opens an account's events socket with a token good now (refreshed when it is about to expire).
export async function openSocket(inner: Inner, sub: string): Promise<SocketFrames> {
  const token = await inner.accounts.accessToken(sub);
  const origin = inner.host.cloudOrigin();
  const url = origin.startsWith("https://") ? `wss://${origin.slice(8)}/v1/events` : `ws://${origin.startsWith("http://") ? origin.slice(7) : origin}/v1/events`;
  try {
    return await inner.host.websocket(url, [EVENTS_PROTOCOL, `stillfail-token.${token}`]);
  } catch (e) {
    throw asCoreError(e);
  }
}

export function onCloudEvent(inner: Inner, sub: string, text: string): void {
  const event = parseJson(text);
  if (!isObject(event)) return;
  if (event.type === "workspaces") {
    inner.runner.spawn(async () => {
      const account = inner.accounts.list().find((a) => a.sub === sub);
      if (!account) return;
      await loadMeOf(inner, [account]);
      if (inner.live.has(topicKey({ topic: "workspaces" }))) inner.store.set({ topic: "workspaces" }, { ok: workspacesValue(inner) });
    });
  } else if (event.type === "workspace") {
    if (typeof event.id !== "string") return;
    const topic: Topic = { topic: "workspace", workspace: event.id };
    if (inner.live.has(topicKey(topic))) spawnRefresh(inner, topic);
  }
}

type Settled<T> = { ok: T } | { err: CoreError };

function settle<T>(p: Promise<T>): Effect.Effect<Settled<T>> {
  return Effect.promise(() =>
    p.then(
      (ok) => ({ ok }),
      (e) => ({ err: asCoreError(e) }),
    ),
  );
}

type Ev = { frame: string | null } | { frameError: CoreError } | { idle: true } | { suspect: true } | { beside: Settled<SocketFrames> };

/// Holds an account's `/v1/events` socket open, reconnecting with backoff (1 s doubling to a minute, back to 1 s
/// after one held a minute), until it is no longer wanted (the fiber is interrupted) or the account is signed out.
export function followSocket(inner: Inner, sub: string): Effect.Effect<void> {
  // What is open, closed however the fiber ends (interrupted when no longer wanted).
  const held: { frames: SocketFrames | null; beside: SocketFrames | null } = { frames: null, beside: null };
  return Effect.gen(function* () {
    let wait = SOCKET_RETRY_MS;
    let frames: SocketFrames | null = null;
    {
      for (;;) {
        const waiting = inner.status.begin(CLOUD, t("core-misc.status.connect"), true);
        const opened = yield* settle(openSocket(inner, sub));
        waiting.end();
        let down: string;
        if ("ok" in opened) {
          frames = opened.ok;
          held.frames = frames;
          const openedAt = inner.host.nowMs();
          socketState(inner, sub, "open");
          inner.status.socketUp(sub);
          // Nothing is replayed: what changed while it was closed is read now.
          yield* Effect.promise(() => refreshAll(inner));
          let woke = false;
          let answers = false;
          let idle = false;
          // What is pending across turns of the loop: the next frame, a wake, another socket opening beside it.
          let nextFrame: Promise<Ev> | null = null;
          let suspect: Promise<Ev> | null = null;
          let beside: Promise<Ev> | null = null;
          for (;;) {
            if (!nextFrame) {
              const f = frames;
              nextFrame = f.next().then(
                (frame) => ({ frame }),
                (e) => ({ frameError: asCoreError(e) }),
              );
            }
            const racers: Effect.Effect<Ev>[] = [Effect.promise(() => nextFrame!)];
            if (answers) racers.push(Effect.sleep(SOCKET_IDLE_MS).pipe(Effect.as({ idle: true } as Ev)));
            if (beside) racers.push(Effect.promise(() => beside!));
            else {
              if (!suspect) suspect = wokenFor(inner.host, (w) => w.suspectsConnections()).then(() => ({ suspect: true }) as Ev);
              racers.push(Effect.promise(() => suspect!));
            }
            const ev: Ev = yield* Effect.raceAllFirst(racers);
            if ("frame" in ev || "frameError" in ev) nextFrame = null;
            if ("frame" in ev) {
              if (ev.frame === null) break;
              if (ev.frame === "pong") answers = true;
              else onCloudEvent(inner, sub, ev.frame);
            } else if ("frameError" in ev) {
              woke = ev.frameError.message === t("core-misc.wake.gone") || ev.frameError.message === t("core-misc.wake.network") || ev.frameError.message === GONE || ev.frameError.message === NETWORK;
              break;
            } else if ("idle" in ev) {
              idle = true;
              break;
            } else if ("suspect" in ev) {
              suspect = null;
              beside = openSocket(inner, sub).then(
                (f) => {
                  held.beside = f;
                  return { beside: { ok: f } } as Ev;
                },
                (e) => ({ beside: { err: asCoreError(e) } }) as Ev,
              );
            } else {
              beside = null;
              if ("ok" in ev.beside) {
                // The new one takes the old one's place; the old one may have missed something: read now.
                frames.close();
                frames = ev.beside.ok;
                held.frames = frames;
                held.beside = null;
                nextFrame = null;
                answers = false;
                yield* Effect.promise(() => refreshAll(inner));
              }
            }
          }
          frames.close();
          frames = null;
          held.frames = null;
          if (woke || idle || inner.host.nowMs() - openedAt >= 60_000) wait = SOCKET_RETRY_MS;
          socketState(inner, sub, "retrying");
          down = idle ? t("core-misc.socket.silent") : t("core-misc.socket.dropped");
          if (woke || idle) continue;
        } else {
          const error = opened.err;
          if (error.code === "signed_out") {
            inner.sockets.delete(sub);
            inner.status.socketUp(sub);
            return;
          }
          down = error.message;
          // Its first try failed: the topics are read anyway, so they show what can be shown.
          if (socketState(inner, sub, "retrying") === "connecting") yield* Effect.promise(() => refreshAll(inner));
        }
        inner.status.socketDown(sub, down, inner.host.nowMs() + wait);
        // A UI back after being away wants it now: the wait starts over.
        const woken = yield* Effect.raceAllFirst([Effect.sleep(wait).pipe(Effect.as(false)), Effect.promise(() => inner.host.woken()).pipe(Effect.as(true))]);
        wait = woken ? SOCKET_RETRY_MS : Math.min(wait * 2, SOCKET_RETRY_MAX_MS);
      }
    }
  }).pipe(
    Effect.ensuring(
      Effect.sync(() => {
        held.frames?.close();
        held.beside?.close();
      }),
    ),
  );
}
