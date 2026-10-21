// The workspace lock on this device (docs/workspace-lock.md): what the pages show of it and what a person does with
// it, so the pages only draw. The cloud keeps the chain and carries it; the stations check every entry and decide.
// An app signs (lock.ts `Signer`) and brings what it signed to the cloud and to each station it reaches.
//
// Topics:
//   lock {workspace}        how far the lock goes, this device's place in it, who waits, members, devices, stations
//   lockDraft {workspace}   what turning it on would sign: members, the devices that asked for credentials lately,
//                           the stations and whether each understands a lock; what is left out
//   lockPrompts             the new devices showing a code of this one's, met face to face (views/pair.ts)
// Calls (lock.<name> {workspace, …}):
//   open                    the owner turns it on, as the draft stands
//   toggle {id}             a device or station of the draft left out, or put back
//   request                 this device asks to be confirmed: by hand only, the person who will compare the codes
//   confirm {device, code}  a waiting device confirmed, its code compared on both screens
//   deny {device}           a waiting device turned down
//   addStation {station, code}  a station enrolled with the lock's hash, confirmed by the code it printed
//   joinStation {station}   a station of the workspace from before (offline or too old then, updated since) taken in
//   renew {device}          a web page's device for 30 days more
//   removeDevice {device}   a device taken out of the lock
//   disable                 the owner turns it off, once the system has asked them (Touch ID, the screen lock)
//   state                   the `lock` topic's value, as a call (tests, scripts)
//   pair                    this device asks a trusted device of its person's, met face to face, to approve it in every
//                           workspace it waits in (views/pair.ts); pairCode {code} the code that one shows, typed;
//                           pairCancel given up
// Calls (lockPrompt.<name> {device}), on a new device showing this one's code (views/pair.ts):
//   deny                    turned away
//
// A station that refuses this device for the lock (`lock_unconfirmed`) is not asked again until the lock moves on
// (someone confirmed something): what waits for it then is tried at once.
import { Effect, Schedule } from "effect";
import type { Inner } from "../core.ts";
import { handlers, hooks } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { type Entry, type Head, Signer, WEB_DEVICE_SECS, entryHash, next, readHead, shortCode } from "../lock.ts";
import * as prefs from "../prefs.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { Priority } from "../sync/scheduler.ts";
import type { SpanContext } from "../trace.ts";
import { get, isObject } from "../util.ts";
import { unsealOwn, writePlain } from "./vault.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Of = Extract<Call, { kind: "lock" }>;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

/// How soon before a web page's device runs out its person is reminded.
export const RENEW_SECS = 5 * 86400;
/// A call the cloud answers "too many requests" is asked again this often, this many times (its budget is a minute's).
const LIMITED_TRIES = 6;
const LIMITED_WAIT = "10 seconds";
/// How much of the lock a hello brings at most (a station reads its first line up to 16 KiB).
const CARRY_BYTES = 12 * 1024;
/// How soon a station that refused this device, though the lock as held here names it, is tried again.
export const BEHIND_MS = 3_000;
/// How many times it is, for one head of the lock.
export const BEHIND_TRIES = 5;
/// A device of the person's own added this recently is pointed out on their other devices.
const RECENT_SECS = 7 * 86400;

/// What the cloud keeps of a workspace's lock, as held here (the `lock` record of the workspace); `declined`, this
/// device's base key once its request went without it being let in (turned down, dropped by the cloud): it does not
/// ask by itself again, when the lock moves on or after a restart, only by hand.
type Held = { head: Head | null; entries: Entry[]; requests: J[]; declined?: string };

/// What this device keeps of a workspace's lock this run.
type Part = {
  /// Stations that refused this device for the lock, and the lock's head then.
  refused: Map<string, string | null>;
  /// Stations that refused this device though the lock as held names it, and how often this head.
  behind: Map<string, number>;
  /// Of the draft: what is left out; the devices that asked for credentials; each station's answer to GET /lock.
  excluded: Set<string>;
  devices: J[] | null;
  probes: Map<string, "ok" | "old" | "offline">;
  /// The base key of this device (the mesh's), once known.
  base: string | null;
  /// Why this device's request to be confirmed did not reach the cloud (its signing key could not be kept, the cloud
  /// refused it): said on its waiting page until a request goes.
  failed: CoreError | null;
};

/// What the signing key of this device is, as loaded (undefined: not loaded yet), per core.
const signers = new WeakMap<Inner, string | null>();

/// This device's base key (the mesh's, the same in every workspace), once known, per core.
const bases = new WeakMap<Inner, string>();

/// This device's signing key (`ed25519:<hex>`) and base key, as known now.
export const signerOf = (inner: Inner): string | null => signers.get(inner) ?? null;
export const baseOf = (inner: Inner): string | null => bases.get(inner) ?? null;

/// This device's signing key as known now (loaded, or made as it is put forward): what shows whether it signs told
/// (the lock's, and the vault's, whose page waits on it).
export function signerKnown(inner: Inner, id: string | null): void {
  signers.set(inner, id);
  inner.store.invalidateAll((t) => t.topic === "lock" || t.topic === "lockPrompts" || t.topic === "vaults" || t.topic === "vaultItems");
}

/// What each workspace's lock was read at (its head's hash and the waiting count the workspace view said), per core.
const readAt = new WeakMap<Inner, Map<string, string>>();

/// What is folded from the entries, unchecked (the stations check them): who and what is in the lock.
export type Folded = { members: Map<string, { email: string; role: string }>; devices: Map<string, J>; stations: Map<string, string>; disabled: boolean; added: Map<string, number> };

export function fold(entries: Entry[]): Folded {
  const f: Folded = { members: new Map(), devices: new Map(), stations: new Map(), disabled: false, added: new Map() };
  for (const e of entries) {
    const b = (e.body ?? {}) as J;
    switch (e.kind) {
      case "genesis":
        for (const m of arr(b.members)) f.members.set(m.sub, { email: m.email, role: m.role });
        for (const d of arr(b.devices)) f.devices.set(d.id, d);
        for (const s of arr(b.stations)) f.stations.set(s.key, s.name);
        break;
      case "member":
        f.members.set(b.sub, { email: b.email, role: b.role });
        break;
      case "member.remove":
        f.members.delete(b.sub);
        for (const [k, d] of f.devices) if (d.sub === b.sub) f.devices.delete(k);
        break;
      case "device":
        if (!f.devices.has(b.id)) f.added.set(b.id, e.at);
        f.devices.set(b.id, b);
        break;
      case "device.remove":
        f.devices.delete(b.id);
        break;
      case "station":
        f.stations.set(b.key, b.name);
        break;
      case "station.remove":
        f.stations.delete(b.key);
        break;
      case "disable":
        f.disabled = true;
        break;
    }
  }
  return f;
}

const part = (inner: Inner, ws: string): Part =>
  inner.workspaces.of(ws).part<Part>("lock", () => ({ refused: new Map(), behind: new Map(), excluded: new Set(), devices: null, probes: new Map(), base: bases.get(inner) ?? null, failed: null }));

/// This device's base key known: kept for every workspace.
const knowBase = (inner: Inner, ws: string, base: string) => {
  bases.set(inner, base);
  part(inner, ws).base = base;
};

/// A workspace's lock changed as this device sees it: its `lock` topic, and the prompts of every workspace.
const touch = (inner: Inner, ws: string) => inner.store.invalidateAll((t) => (t.topic === "lock" && t.workspace === ws) || t.topic === "lockPrompts");

export const held = (inner: Inner, ws: string): Held | null => {
  const h = inner.data.record("lock", ws);
  return isObject(h) && Array.isArray(h.entries) ? (h as unknown as Held) : null;
};

export const view = (inner: Inner, ws: string): J => inner.data.shared({ topic: "workspace", workspace: ws });

/// A workspace's name as the person knows it: as its view says, else as the account's list does.
export const nameOf = (inner: Inner, ws: string): string =>
  inner.cloudSync?.workspaceName(ws) ?? str(inner.data.mes().flatMap(([, me]) => arr(get(me, "workspaces"))).find((w) => get(w, "id") === ws)?.name) ?? ws;

/// What the workspace view says of the lock: its head and how many devices wait (undefined: a cloud from before).
const cloudSays = (v: J): string | undefined => (!isObject(v) || !("lock" in v) ? undefined : `${get(v.lock, "hash") ?? ""}/${get(v, "lock_requests") ?? 0}`);

const now = (inner: Inner) => Math.floor(inner.host.nowMs() / 1000);
const daysLeft = (secs: number) => Math.max(0, Math.ceil(secs / 86400));

export function install(inner: Inner): void {
  hooks.enrolled = enrolled;
  hooks.lockRefused = refused;
  hooks.lockWaiting = waiting;
  inner.cloudSync.carry = (ws) => carried(inner, ws);
  handlers.lock = (core, call, _progress, _at, ctx) => run(core, call as Of, ctx);
  handlers.lockPrompt = (core, call, _progress, _at, ctx) => runPrompt(core, (call as Extract<Call, { kind: "lockPrompt" }>).name, (call as Extract<Call, { kind: "lockPrompt" }>).params, ctx);
  // The signing key, once (it is the device's).
  inner.runner.fork(
    Effect.map(Effect.orElseSucceed(Signer.load(inner.host), () => null), (s) => signerKnown(inner, s?.id ?? null)),
  );
  // The workspace view says how far the cloud's lock goes and how many wait: read again when that changes.
  inner.data.onChange((topic) => {
    if (topic.topic !== "workspace" || inner.provider.kind !== "stillfail") return;
    const ws = topic.workspace as string;
    // The prompts name the workspaces, and follow the person's role in each.
    inner.store.invalidate({ topic: "lockPrompts" });
    const says = cloudSays(view(inner, ws));
    if (says === undefined) return;
    let at = readAt.get(inner);
    if (!at) readAt.set(inner, (at = new Map()));
    if (at.get(ws) === says && held(inner, ws) !== null) return;
    at.set(ws, says);
    inner.scheduler.enqueue("cloud", `lock/${ws}`, Priority.background, read(inner, ws));
  });
  inner.router.owners.push(owner(inner));
}

/// The lock and the waiting devices, read from the cloud and held; a lock that moved on lets the stations that refused
/// this device be tried again.
export function read(inner: Inner, ws: string): Effect.Effect<void, CoreError> {
  // What changed while it read (a request dropped just after an entry came) is read again: an ask made meanwhile
  // under the same key was folded into this one.
  return Effect.gen(function* () {
    for (let round = 0; round < 3; round++) {
      const before = cloudSays(view(inner, ws));
      yield* readOnce(inner, ws);
      if (cloudSays(view(inner, ws)) === before) return;
    }
  });
}

function readOnce(inner: Inner, ws: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const sub = inner.workspaces.owner(ws);
    if (sub === null) return;
    const was = held(inner, ws);
    const cloud = (path: string) => inner.provider.request(sub, "GET", `/v1/workspaces/${encodeURIComponent(ws)}${path}`, null);
    // What follows what is held, when it is the same lock; all of it otherwise.
    const said = yield* cloud(`/lock?after=${was?.head ? was.head.seq : -1}`);
    const head = readHead(get(said, "head"));
    const more = arr(get(said, "entries")) as Entry[];
    const same = was?.head && head && was.head.genesis === head.genesis;
    let entries = same ? [...was!.entries, ...more.filter((e) => e.seq > was!.head!.seq)] : more;
    if (!same && head && (more.length === 0 || more[0]!.seq !== 0)) entries = arr(get(yield* cloud("/lock"), "entries")) as Entry[];
    const requests = head === null ? [] : yield* Effect.orElseSucceed(Effect.map(cloud("/lock/requests"), (r) => arr(get(r, "requests"))), () => was?.requests ?? []);
    const asking = head !== null && inner.provider.kind === "stillfail";
    const base = asking ? yield* Effect.orElseSucceed(new Lock(inner, ws, sub, null).base(), () => null) : null;
    const f = fold(head === null ? [] : entries);
    // Its request gone while it is still not in the lock: turned down (or dropped by the cloud). Read between a confirm's
    // entry and its request's removal it looks the same, until the next read finds it in the lock.
    let declined = was?.declined;
    if (base !== null && (f.devices.has(base) || requests.some((r) => r.base === base))) declined = undefined;
    else if (base !== null && (was?.requests ?? []).some((r) => r.base === base)) declined = base;
    inner.data.put("lock", ws, { head, entries: head === null ? [] : entries, requests, ...(declined ? { declined } : {}) });
    // In the lock, or its request at the cloud: what kept it from asking is past.
    if (base !== null && (f.devices.has(base) || requests.some((r) => r.base === base))) part(inner, ws).failed = null;
    if ((was?.head?.hash ?? null) !== (head?.hash ?? null)) moved(inner, ws);
    // The vault's too: whether it is locked, this device confirmed in it, whose vaults are trusted (views/vault.ts).
    inner.store.invalidateAll((t) => ((t.topic === "lock" || t.topic === "lockDraft" || t.topic === "vaults" || t.topic === "vaultItems") && t.workspace === ws) || t.topic === "lockPrompts");
    // This device not in the lock: it waits, and asks to be confirmed only by hand (`lock.request`, its waiting page):
    // the person who will compare the codes is the one who asks (2026-10-19).
  });
}

/// The lock moved on: the stations that refused this device before are tried again now.
function moved(inner: Inner, ws: string): void {
  const p = part(inner, ws);
  p.behind.clear();
  for (const station of [...p.refused.keys()]) {
    p.refused.delete(station);
    inner.stations?.cameOnline(`${ws}/${station}`);
  }
}

/// A station refused this device for the lock: noted, not asked again until the lock moves on. What the refusal says
/// then: which workspace, and where to approve it.
function refused(inner: Inner, ws: string, station: string): CoreError | null {
  if (inner.provider.kind !== "stillfail") return null;
  const p = part(inner, ws);
  const h = held(inner, ws);
  const base = p.base ?? bases.get(inner) ?? null;
  const f = fold(h?.entries ?? []);
  // In the lock as this device holds it: the station has not heard of it yet (from the cloud, or the device that
  // signed it), and is tried again shortly rather than once the lock moves on, which it may not again for long.
  // A few times, each a little later (each try asks the station anew); after that, as any station not reached.
  if (base !== null && h?.head != null && !f.disabled && f.devices.has(base)) {
    const tries = p.behind.get(station) ?? 0;
    if (tries < BEHIND_TRIES) {
      p.behind.set(station, tries + 1);
      inner.runner.fork(Effect.andThen(Effect.sleep(BEHIND_MS * (tries + 1)), Effect.sync(() => inner.stations?.cameOnline(`${ws}/${station}`))));
    }
    return new CoreError("lock_unconfirmed", t("core-misc.lock.behind"));
  }
  p.refused.set(station, h?.head?.hash ?? null);
  touch(inner, ws);
  return unconfirmed(inner, ws);
}

/// Why a station is not asked now: it refused this device and the lock has not moved on since.
function waiting(inner: Inner, ws: string, station: string): CoreError | null {
  const p = inner.workspaces.get(ws)?.own.get("lock") as Part | undefined;
  if (!p || !p.refused.has(station)) return null;
  if (p.refused.get(station) !== (held(inner, ws)?.head?.hash ?? null)) {
    p.refused.delete(station);
    return null;
  }
  return unconfirmed(inner, ws);
}

/// A station of the workspace refused this device for its lock: which workspace, and where it is approved (another
/// trusted device of the person's there), with the code compared there.
function unconfirmed(inner: Inner, ws: string): CoreError {
  const base = part(inner, ws).base ?? bases.get(inner) ?? null;
  const name = nameOf(inner, ws);
  return new CoreError("lock_unconfirmed", base ? t("core-misc.lock.unconfirmed", { name, code: shortCode(base) }) : t("core-misc.lock.unconfirmedNoCode", { name }));
}

/// What this device brings a station of the workspace as it connects (its hello's `lock.entries`): the entries from the
/// one that put it in the lock on, as held here, while that was lately (RECENT_SECS): a station that has not heard of
/// them yet takes them and lets it in (docs/workspace-lock.md 新设备), the approval coming with the device that needs
/// it. None when it is not in the lock, was put there long ago or by the genesis, or they would not fit a first line.
function carried(inner: Inner, ws: string): Entry[] | null {
  const h = held(inner, ws);
  const base = part(inner, ws).base ?? bases.get(inner) ?? null;
  if (!h?.head || base === null) return null;
  const f = fold(h.entries);
  if (f.disabled || !f.devices.has(base)) return null;
  let at = h.entries.length - 1;
  while (at >= 0 && !(h.entries[at]!.kind === "device" && get(h.entries[at]!.body, "id") === base)) at--;
  if (at < 0 || now(inner) - h.entries[at]!.at > RECENT_SECS) return null;
  const tail = h.entries.slice(at);
  return JSON.stringify(tail).length <= CARRY_BYTES ? tail : null;
}

/// What a control plane that keeps no lock shows.
const NONE = { available: false, locked: false, notice: false, role: "member", manages: false, owner: false, canSign: false, signs: false, signers: 0, members: [], stations: [], protected: 0, requests: [], renew: [], attention: 0 };
const NO_PROMPTS = { waiting: [], prompt: null };
const NO_DRAFT = { available: false, loading: false, canSign: false, owner: false, ready: false, members: [], devices: [], stations: [] };

/// The topics.
function owner(inner: Inner): Owner {
  return {
    owns: (t: Topic) => t.topic === "lock" || t.topic === "lockDraft" || t.topic === "lockPrompts",
    start: (t: Topic) => {
      if (inner.provider.kind !== "stillfail") return;
      const ws = t.workspace as string;
      // The device's own key is the mesh's: brought up to know it.
      inner.runner.fork(
        Effect.ignore(
          Effect.map(inner.mesh(), (m) => {
            bases.set(inner, m.deviceId());
            if (t.topic !== "lockPrompts") part(inner, ws).base = m.deviceId();
            inner.store.invalidate(t);
          }),
        ),
      );
      // The prompts are of what each workspace's lock holds, read as their workspaces change.
      if (t.topic === "lockPrompts") return;
      if (t.topic === "lockDraft") inner.scheduler.enqueue("cloud", `lock/${ws}/draft`, Priority.shown, draft(inner, ws));
      // Shown: read again now, what is held showing meanwhile.
      else inner.scheduler.enqueue("cloud", `lock/${ws}`, Priority.shown, read(inner, ws));
    },
    compute: (t: Topic) => {
      const ws = typeof t.workspace === "string" ? t.workspace : "";
      if (inner.provider.kind !== "stillfail") return { ok: t.topic === "lock" ? NONE : t.topic === "lockPrompts" ? NO_PROMPTS : NO_DRAFT };
      return { ok: t.topic === "lock" ? lockView(inner, ws) : t.topic === "lockPrompts" ? promptsView(inner) : draftView(inner, ws) };
    },
  };
}

/// The person asked by the system before what they should mean (host.ts `secureAsk`): fails with the host's code
/// (`user_cancelled`, …) as the call's; a phone with no screen lock has nothing to ask with, and goes on.
function askPerson(inner: Inner, reason: string): Effect.Effect<void, CoreError> {
  const ask = inner.host.secureAsk;
  if (!ask) return Effect.void;
  return Effect.catch(ask.call(inner.host, reason), (e) =>
    e.message === "no_device_lock" ? Effect.void : Effect.fail(new CoreError(/^[a-z][a-z_]*$/.test(e.message) ? e.message : "lock_refused", e.message)));
}

/// The `lock` topic.
export function lockView(inner: Inner, ws: string): J {
  const p = part(inner, ws);
  // This device's base key: known in another workspace already, the same here.
  const base = p.base ?? bases.get(inner) ?? null;
  const h = held(inner, ws);
  const v = view(inner, ws);
  const f = fold(h?.entries ?? []);
  const locked = h?.head != null && !f.disabled;
  const sub = inner.workspaces.owner(ws);
  const t = now(inner);
  const signer = signers.get(inner) ?? null;
  const people = new Map<string, J>(arr(get(v, "members")).map((m) => [m.sub, m]));
  const mine = base ? f.devices.get(base) : undefined;
  const role = str(get(v, "role")) ?? "member";
  const manages = role === "owner" || role === "admin";
  const device = (d: J) => ({
    id: d.id, kind: d.kind === "web" ? "web" : "app", label: d.label || "", signs: typeof d.sign_key === "string", older: Array.isArray(d.endpoints),
    mine: d.id === base, daysLeft: typeof d.exp === "number" ? daysLeft(d.exp - t) : null,
    renewSoon: typeof d.exp === "number" && d.exp - t < RENEW_SECS,
    // A device of the viewer's own added lately, shown on their other devices.
    recent: d.sub === sub && d.id !== base && t - (f.added.get(d.id) ?? 0) < RECENT_SECS,
  });
  const stations = arr(get(v, "stations")).map((s) => ({
    id: s.id, name: s.name, version: s.version ?? null, online: s.online !== false, protected: f.stations.has(s.id),
  }));
  const members = [...f.members].map(([s, m]) => ({
    sub: s, email: m.email, name: str(get(people.get(s), "name")) ?? "", role: m.role, you: s === sub,
    devices: [...f.devices.values()].filter((d) => d.sub === s).map(device),
  }));
  const requests = (h?.requests ?? [])
    .map((r) => ({
      device: r.base, sub: r.sub, email: r.email, name: str(get(people.get(r.sub), "name")) ?? "", kind: r.kind === "app" ? "app" : "web",
      label: r.label || "", code: r.code ?? shortCode(r.base), created_at: r.created_at ?? 0, yours: r.sub === sub,
    }))
    .filter((r) => r.device !== base && (manages || r.yours));
  const renew = members.flatMap((m) => (m.you ? m.devices.filter((d) => d.renewSoon) : []));
  const dismissed = get(get(inner.data.shared({ topic: "prefs" }), "lockNotice"), ws) === true;
  const signs = mine !== undefined && typeof mine.sign_key === "string" && mine.sign_key === signer;
  // An app in the lock that does not sign with its key (let in before it kept one, as the devices there when the lock
  // was turned on were; or its key since lost): it may be made one that signs, approved face to face as a new one is.
  const unsigned = locked && mine !== undefined && mine.kind === "app" && inner.host.appKeys === true && signers.has(inner) && !signs;
  return {
    available: true,
    locked,
    // The one-line notice on the settings pages: the owner's, while it is off, until closed.
    notice: role === "owner" && !locked && !dismissed,
    role,
    manages,
    owner: role === "owner",
    // Whether this device signs (an app whose key the lock names), whether it could (an app).
    canSign: inner.host.appKeys === true,
    signs,
    me: {
      device: base, code: base ? shortCode(base) : null, kind: inner.host.appKeys ? "app" : "web",
      confirmed: mine !== undefined, daysLeft: typeof mine?.exp === "number" ? daysLeft(mine.exp - t) : null,
      // A station refused this device, or it asked, and the lock has not moved on since: it waits to be confirmed.
      // Its request waits at the cloud, or is on its way there; not when turned down (asked again by hand then).
      asked: (h?.requests ?? []).some((r) => r.base === base),
      // Its request did not reach the cloud: why (its key could not be kept, the cloud refused it); asked again by hand.
      failed: locked && mine === undefined ? (p.failed?.message ?? null) : null,
      // Not in the lock: it waits to be confirmed, and asks by hand.
      waiting: locked && base !== null && mine === undefined,
      ...(unsigned ? { unsigned: true } : {}),
      // Its try to be approved face to face (views/pair.ts), once it began.
      pair: locked && (mine === undefined || unsigned) ? pairs.mine(inner, ws) : null,
    },
    signers: [...f.devices.values()].filter((d) => typeof d.sign_key === "string").length,
    members,
    stations,
    protected: stations.filter((s) => s.protected).length,
    // What waits on the viewer: devices to confirm (their own, or anyone's for owners and admins), their own web
    // devices running out.
    requests,
    renew,
    attention: requests.length + renew.length,
  };
}

/// The `lockPrompts` topic: the new devices showing a code of this one's to type (views/pair.ts), wherever the person is.
export function promptsView(inner: Inner): J {
  return { pairing: pairs.shown(inner) };
}

/// A `lockPrompt.*` call: `deny {device}`, a new device showing this one's code turned away (views/pair.ts); `state`,
/// the topic's value (tests, scripts).
export function runPrompt(inner: Inner, name: string, params: Record<string, unknown>, _ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
  if (name === "state") return Effect.succeed(promptsView(inner));
  if (name !== "deny") return Effect.fail(CoreError.invalid(`no lockPrompt call ${name}`));
  pairs.deny(inner, str(params.device) ?? "");
  return Effect.succeed(null);
}

/// What approving face to face adds (views/pair.ts, installed with it): the new devices showing this one's code, this
/// device's own try to be approved, and the calls of that try.
export const pairs: {
  shown(inner: Inner): J[];
  mine(inner: Inner, ws: string): J | null;
  deny(inner: Inner, device: string): void;
  run(inner: Inner, name: string, ws: string, params: Record<string, unknown>): Effect.Effect<unknown, CoreError>;
} = { shown: () => [], mine: () => null, deny: () => {}, run: () => Effect.fail(CoreError.invalid("no face-to-face approval here")) };

/// The draft of turning it on: the devices that asked for credentials, the stations asked whether they understand a
/// lock (GET /lock: one from before answers 404).
function draft(inner: Inner, ws: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const sub = inner.workspaces.owner(ws);
    if (sub === null) return;
    const p = part(inner, ws);
    const answer = yield* Effect.result(inner.provider.request(sub, "GET", `/v1/workspaces/${encodeURIComponent(ws)}/devices`, null));
    p.devices = answer._tag === "Success" ? arr(get(answer.success, "devices")) : [];
    inner.store.invalidateAll((t) => t.topic === "lockDraft" && t.workspace === ws);
    yield* Effect.forEach(
      arr(get(view(inner, ws), "stations")),
      (s) =>
        Effect.map(Effect.result(inner.stations.requests.call(new StationAddr(ws, s.id), "GET", "/lock", null, { quiet: true })), (r) => {
          p.probes.set(s.id, r._tag === "Success" ? "ok" : r.failure.status === 404 || /404|no route/.test(r.failure.message) ? "old" : "offline");
          inner.store.invalidateAll((t) => t.topic === "lockDraft" && t.workspace === ws);
        }),
      { concurrency: 4, discard: true },
    );
  });
}

/// The devices the draft would sign: this one first, then the others that asked for credentials; older clients by
/// the endpoint they asked for.
function draftDevices(inner: Inner, ws: string): J[] {
  const p = part(inner, ws);
  const sub = inner.workspaces.owner(ws);
  const members = new Set<string>(arr(get(view(inner, ws), "members")).map((m) => m.sub));
  const out: J[] = [];
  if (p.base) out.push({ id: p.base, sub, kind: inner.host.appKeys ? "app" : "web", label: prefs.deviceName(inner.data) ?? "", seen: now(inner), this: true });
  for (const r of p.devices ?? []) {
    if (!members.has(r.sub)) continue;
    const id = typeof r.base === "string" ? r.base : r.device;
    if (out.some((d) => d.id === id)) continue;
    out.push({ id, sub: r.sub, kind: r.kind === "web" ? "web" : "app", label: str(r.label) ?? "", older: typeof r.base !== "string", endpoint: r.device, seen: r.last_seen ?? 0, this: false });
  }
  return out;
}

/// The `lockDraft` topic.
function draftView(inner: Inner, ws: string): J {
  const p = part(inner, ws);
  const v = view(inner, ws);
  const members = arr(get(v, "members")).map((m) => ({ sub: m.sub, email: m.email, name: m.name ?? "", role: m.role }));
  const bySub = new Map(members.map((m) => [m.sub, m]));
  const devices = draftDevices(inner, ws).map((d) => ({
    id: d.id, person: bySub.get(d.sub)?.name || bySub.get(d.sub)?.email || "", kind: d.kind, label: d.label, older: d.older === true, current: d.this,
    last_seen: d.seen, on: d.this || !p.excluded.has(d.id), fixed: d.this,
  }));
  const stations = arr(get(v, "stations")).map((s) => {
    const probe = p.probes.get(s.id) ?? null;
    return { id: s.id, name: s.name, version: s.version ?? null, state: probe ?? "asking", on: probe === "ok" && !p.excluded.has(s.id), fixed: probe !== "ok" };
  });
  return {
    available: true,
    loading: p.devices === null,
    canSign: inner.host.appKeys === true,
    owner: get(v, "role") === "owner",
    members,
    devices,
    stations,
    ready: p.base !== null && p.devices !== null && stations.every((s) => s.state !== "asking"),
  };
}

function run(inner: Inner, c: Of, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const sub = inner.workspaces.owner(c.workspace);
    if (sub === null) return yield* Effect.fail(CoreError.invalid("not a workspace of the signed-in accounts"));
    const lock = new Lock(inner, c.workspace, sub, ctx, true);
    const param = (k: string) => str(c.params[k]) ?? "";
    let result: unknown;
    switch (c.name) {
      case "state":
        yield* Effect.ignore(lock.base());
        yield* Effect.ignore(read(inner, c.workspace));
        return lockView(inner, c.workspace);
      // The notice that the lock is off, closed for good on this device (prefs `lockNotice`).
      case "dismiss":
        prefs.set(inner.data, { lockNotice: { [c.workspace]: true } }, false, inner.host.nowMs());
        inner.store.invalidate({ topic: "prefs" });
        touch(inner, c.workspace);
        return null;
      case "toggle": {
        const ex = part(inner, c.workspace).excluded;
        if (ex.has(param("id"))) ex.delete(param("id"));
        else ex.add(param("id"));
        inner.store.invalidateAll((t) => t.topic === "lockDraft" && t.workspace === c.workspace);
        return null;
      }
      case "open":
        result = yield* lock.open();
        break;
      // By hand: what kept it from asking before is said again if it is not past (`me.failed`).
      case "request": {
        const p = part(inner, c.workspace);
        result = yield* Effect.tapError(lock.request(), (e) => Effect.sync(() => {
          p.failed = e;
          touch(inner, c.workspace);
        }));
        p.failed = null;
        break;
      }
      case "confirm":
        result = yield* lock.confirm(param("device"), param("code"));
        break;
      // Approved face to face (views/pair.ts): asked, the code typed, given up.
      case "pair":
      case "pairCode":
      case "pairCancel":
        return yield* pairs.run(inner, c.name, c.workspace, c.params);
      case "deny":
        result = yield* lock.deny(param("device"));
        break;
      case "addStation":
        result = yield* lock.addStation(param("station"), param("code"));
        break;
      case "joinStation":
        result = yield* lock.joinStation(param("station"));
        break;
      case "renew":
        result = yield* lock.renew(param("device"));
        break;
      case "removeDevice":
        result = yield* lock.append("device.remove", { id: param("device") });
        break;
      case "disable": {
        // The person's own secrets opened while the lock still says whose they are (docs/vault.md 一个库): once it is
        // off they go into the plain library, as the dialog said. Turned down there, nothing is turned off.
        const secrets = yield* unsealOwn(inner, c.workspace);
        yield* askPerson(inner, t("core-misc.lock.reason.disable"));
        result = yield* lock.append("disable", {});
        if (secrets.length > 0) inner.runner.fork(writePlain(inner, c.workspace, secrets));
        break;
      }
      default:
        return yield* Effect.fail(CoreError.invalid(`no lock call ${c.name}`));
    }
    // What changed is read again before the call answers (the pages show it at once).
    yield* Effect.ignore(read(inner, c.workspace));
    return result;
  });
}

/// A station's enrollment in a locked workspace: its commands name the lock's head, which it pins (`--lock`), as the
/// stations this device reaches have it (the cloud's word only when none answers). A control plane that keeps no lock
/// (Comma, a cloud from before locks): the commands as they were.
export function enrolled(inner: Inner, sub: string, ws: string, made: unknown): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    if (inner.provider.kind !== "stillfail") return made;
    const lock = new Lock(inner, ws, sub, null);
    const head = yield* Effect.orElseSucceed(lock.head(), () => null);
    if (head === null || !isObject(made)) return made;
    const out: J = { ...made, lock: head.hash };
    if (typeof out.install === "string") out.install = `${out.install} ${head.hash}`;
    if (typeof out.installWindows === "string") out.installWindows = `${out.installWindows} ${head.hash}`;
    if (typeof out.command === "string") out.command = `${out.command} --lock ${head.hash}`;
    return out;
  });
}

/// A station that joined a locked workspace from its home (docs/multi-workspace.md) taken into that workspace's lock, as
/// one enrolled with its hash is, by this device's signature: its code is worked out here, the same person having asked
/// it to join.
export function takeInJoined(inner: Inner, sub: string, ws: string, station: string): Effect.Effect<unknown, CoreError> {
  return new Lock(inner, ws, sub, null).addStation(station, shortCode(station));
}

export class Lock {
  readonly #inner: Inner;
  readonly ws: string;
  readonly sub: string;
  readonly #ctx: SpanContext | null;
  /// What a person does (a call): the cloud's "too many requests" waited out (the account's devices share a budget a
  /// minute), not said at once as the call's failure.
  readonly #byHand: boolean;

  constructor(inner: Inner, ws: string, sub: string, ctx: SpanContext | null, byHand = false) {
    this.#inner = inner;
    this.ws = ws;
    this.sub = sub;
    this.#ctx = ctx;
    this.#byHand = byHand;
  }

  #cloud(method: string, path: string, body: unknown = null) {
    const asked = this.#inner.provider.request(this.sub, method, `/v1/workspaces/${encodeURIComponent(this.ws)}${path}`, body, this.#ctx);
    return this.#byHand ? Effect.retry(asked, { times: LIMITED_TRIES, schedule: Schedule.spaced(LIMITED_WAIT), while: (e) => e.code === "rate_limited" }) : asked;
  }

  #station(id: string, method: string, path: string, body: unknown = null) {
    return this.#inner.stations.requests.call(new StationAddr(this.ws, id), method, path, body, { ctx: this.#ctx });
  }

  /// This device's base key: the mesh's device key.
  base(): Effect.Effect<string, CoreError> {
    return this.#base();
  }

  #base(): Effect.Effect<string, CoreError> {
    return Effect.map(this.#inner.mesh(), (m) => {
      knowBase(this.#inner, this.ws, m.deviceId());
      return m.deviceId();
    });
  }

  #kind(): "app" | "web" {
    return this.#inner.host.appKeys ? "app" : "web";
  }

  /// The chain as the cloud keeps it.
  #chain(): Effect.Effect<{ head: Head | null; entries: Entry[] }, CoreError> {
    return Effect.map(this.#cloud("GET", "/lock"), (r) => ({ head: readHead(get(r, "head")), entries: arr(get(r, "entries")) as Entry[] }));
  }

  /// How far the lock goes, as a station of it this device reaches says (it checked every entry), else as the cloud
  /// does; null without a lock.
  head(): Effect.Effect<Head | null, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const { head, entries } = yield* self.#chain();
      if (head === null || fold(entries).disabled) return null;
      for (const id of fold(entries).stations.keys()) {
        const r = yield* Effect.result(self.#station(id, "GET", "/lock?after=999999999"));
        const theirs = r._tag === "Success" ? readHead(get(r.success, "head")) : null;
        if (theirs !== null) return theirs;
      }
      return head;
    });
  }

  /// The owner turns the lock on, as the draft stands: the workspace's members, the devices left in (this one always,
  /// as the first signer), and the stations that answered understanding a lock and are left in (an older one, or one
  /// offline, is never in: one the lock names that does not hold it could be used against the rest). The genesis
  /// goes to the cloud and to each of those stations.
  open(): Effect.Effect<unknown, CoreError> {
    const self = this;
    const inner = this.#inner;
    return Effect.gen(function* () {
      const v = view(inner, self.ws);
      if (get(v, "role") !== "owner") return yield* Effect.fail(new CoreError("forbidden", "only the workspace's owner turns its lock on"));
      const signer = yield* Signer.make(inner.host);
      signerKnown(inner, signer.id);
      const base = yield* self.#base();
      const p = part(inner, self.ws);
      if (p.devices === null || arr(get(v, "stations")).some((s) => !p.probes.has(s.id))) yield* draft(inner, self.ws);
      const origin = inner.host.cloudOrigin();
      const keysAnswer = yield* Effect.mapError(inner.host.fetch({ method: "GET", url: `${origin}/.well-known/stillfail-grant-keys`, headers: [], body: null }), (e) => new CoreError("network", e.message));
      const cloudKeys = JSON.parse(new TextDecoder().decode(keysAnswer.body));
      const members = arr(get(v, "members")).map((m) => ({ sub: m.sub, email: m.email, role: m.role }));
      const devices: J[] = [];
      for (const d of draftDevices(inner, self.ws)) {
        if (d.id === base) devices.push({ id: base, sub: self.sub, kind: self.#kind(), label: d.label, sign_key: signer.id });
        else if (!p.excluded.has(d.id)) devices.push({ id: d.id, sub: d.sub, kind: d.kind, label: d.label, ...(d.older ? { endpoints: [d.endpoint] } : {}) });
      }
      const stations = arr(get(v, "stations"))
        .filter((s) => p.probes.get(s.id) === "ok" && !p.excluded.has(s.id))
        .map((s) => ({ key: s.id as string, name: s.name as string }));
      const u = new URL(origin);
      const genesis = signer.sign(next(self.ws, null, inner.host.nowMs() / 1000, "genesis", {
        owner: self.sub, origins: [u.origin], rp_id: u.hostname, cloud_keys: cloudKeys, members, devices, passkeys: [], stations, gateways: [],
      }));
      yield* self.#cloud("POST", "/lock", { entries: [genesis] });
      const pinned = yield* self.#bring([genesis], stations.map((s) => s.key));
      p.excluded.clear();
      return { head: { seq: 0, hash: entryHash(genesis), genesis: entryHash(genesis) }, stations: stations.map((s) => ({ id: s.key, name: s.name, pinned: pinned[s.key] ?? null })), devices: devices.length, members: members.length };
    });
  }

  /// This device asks to be confirmed: its base key (and an app's signing key), told to the owners, admins and the
  /// member's own other devices through the cloud. The code it shows is the one they compare.
  request(): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const base = yield* self.#base();
      // An app's key it cannot keep (a host that cannot seal, the keychain refusing): its request does not go, and the
      // waiting page says so.
      const made = Effect.mapError(Signer.make(self.#inner.host), (e) => new CoreError("lock_key", t("core-misc.lock.keyNotKept", { error: e.message })));
      const signer = self.#inner.host.appKeys ? yield* made : null;
      if (signer) signerKnown(self.#inner, signer.id);
      yield* self.#cloud("POST", "/lock/requests", { base, kind: self.#kind(), label: prefs.deviceName(self.#inner.data) ?? "", sign_key: signer?.id ?? null });
      return { device: base, code: shortCode(base) };
    });
  }

  /// A waiting device confirmed, once its code was compared: a web page's for 30 days.
  confirm(device: string, code: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      if (shortCode(device) !== code.trim().toUpperCase()) return yield* Effect.fail(CoreError.invalid("the code does not match that device's"));
      const requests = arr(get(yield* self.#cloud("GET", "/lock/requests"), "requests"));
      const r = requests.find((x) => x.base === device);
      if (!r) return yield* Effect.fail(CoreError.invalid("no such device waits to be confirmed"));
      const body: J = { id: device, sub: r.sub, kind: r.kind === "app" ? "app" : "web", label: str(r.label) ?? "" };
      if (body.kind === "app" && typeof r.sign_key === "string") body.sign_key = r.sign_key;
      if (body.kind === "web") body.exp = now(self.#inner) + WEB_DEVICE_SECS;
      const done = yield* self.append("device", body);
      yield* Effect.ignore(self.#cloud("DELETE", `/lock/requests/${encodeURIComponent(device)}`));
      return done;
    });
  }

  /// A waiting device turned down: its request gone.
  deny(device: string): Effect.Effect<unknown, CoreError> {
    return this.#cloud("DELETE", `/lock/requests/${encodeURIComponent(device)}`);
  }

  /// A web page's device, 30 days more from now.
  renew(device: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const d = fold(held(self.#inner, self.ws)?.entries ?? []).devices.get(device);
      if (!d) return yield* Effect.fail(CoreError.invalid("no such device in the lock"));
      return yield* self.append("device", { ...d, exp: now(self.#inner) + WEB_DEVICE_SECS });
    });
  }

  /// A station enrolled with the lock's hash (`--lock`), confirmed by the code it printed.
  addStation(station: string, code: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      if (shortCode(station) !== code.trim().toUpperCase()) return yield* Effect.fail(CoreError.invalid("the code does not match that station's"));
      const s = arr(get(view(self.#inner, self.ws), "stations")).find((x) => x.id === station);
      return yield* self.append("station", { key: station, name: s?.name ?? "" }, [station]);
    });
  }

  /// A station the workspace already had, not in the lock (offline or too old when it was turned on, updated since):
  /// asked whether it understands a lock, signed in, and given the whole chain, which it pins (the owner brings it: a
  /// station without a lock pins only one its owner brings, on a device the genesis names).
  joinStation(station: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      // The workspace as the cloud has it now: the station may have come back to it a moment ago.
      const now = yield* self.#cloud("GET", "");
      const s = arr(get(now, "stations")).find((x) => x.id === station);
      if (!s) return yield* Effect.fail(CoreError.invalid("not a station of this workspace"));
      const asked = yield* Effect.result(self.#station(station, "GET", "/lock"));
      if (asked._tag === "Failure") {
        const old = asked.failure.status === 404 || /404|no route/.test(asked.failure.message);
        return yield* Effect.fail(new CoreError(old ? "lock_station_old" : "lock_station_offline", old ? t("core-misc.lock.stationOld", { name: s.name }) : t("core-misc.lock.stationOffline", { name: s.name })));
      }
      const done = yield* self.append("station", { key: station, name: s.name ?? "" }, [station]);
      const pinned = get(get(done, "stations"), station);
      if (isObject(pinned) && typeof pinned.error === "string") return yield* Effect.fail(new CoreError("lock_station_refused", pinned.error));
      return done;
    });
  }

  /// One more entry, signed by this app's key, after the chain as the cloud keeps it: to the cloud, which is when it is
  /// done (the cloud tells the stations at once, and one offline asks it once back), then to each station of the lock
  /// this device reaches, after the call answers: one offline held an approval up until asking it gave up, some ten
  /// seconds to minutes. `waitFor`: the stations whose answers the call waits for (one just taken in pins only what this
  /// device brings it).
  append(kind: string, body: unknown, waitFor: string[] = []): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const signer = yield* Signer.load(self.#inner.host);
      if (signer === null) return yield* Effect.fail(new CoreError("lock_no_signer", "this device signs nothing for the workspace lock"));
      const { head, entries } = yield* self.#chain();
      if (head === null) return yield* Effect.fail(new CoreError("lock_none", "the workspace has no lock"));
      const entry = signer.sign(next(self.ws, head, self.#inner.host.nowMs() / 1000, kind, body));
      yield* self.#cloud("POST", "/lock", { entries: [entry] });
      // The whole chain: a station that is behind takes what it lacks, and skips what it has.
      const chain = [...entries, entry];
      const stations = [...fold(chain).stations.keys()];
      const later = stations.filter((s) => !waitFor.includes(s));
      if (later.length > 0) self.#inner.runner.fork(Effect.ignore(self.#bring(chain, later)));
      const pinned = yield* self.#bring(chain, stations.filter((s) => waitFor.includes(s)));
      return { head: { seq: entry.seq, hash: entryHash(entry), genesis: head.genesis }, stations: pinned };
    });
  }

  /// Entries brought to stations (each one's answer, or why not: one offline hears of them later).
  #bring(entries: Entry[], stations: string[]): Effect.Effect<Record<string, unknown>, CoreError> {
    const self = this;
    return Effect.map(
      Effect.forEach(stations, (id) => Effect.map(Effect.result(self.#station(id, "POST", "/lock", { entries })), (r) => [id, r._tag === "Success" ? get(r.success, "head") : { error: r.failure.message }] as const), { concurrency: 4 }),
      (pairs) => Object.fromEntries(pairs),
    );
  }
}
