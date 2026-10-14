// The workspace lock on this device (docs/workspace-lock.md): what the pages show of it and what a person does with
// it, so the pages only draw. The cloud keeps the chain and carries it; the stations check every entry and decide.
// An app signs (lock.ts `Signer`) and brings what it signed to the cloud and to each station it reaches.
//
// Topics:
//   lock {workspace}        how far the lock goes, this device's place in it, who waits, members, devices, stations
//   lockDraft {workspace}   what turning it on would sign: members, the devices that asked for credentials lately,
//                           the stations and whether each understands a lock; what is left out
// Calls (lock.<name> {workspace, …}):
//   open                    the owner turns it on, as the draft stands
//   toggle {id}             a device or station of the draft left out, or put back
//   request                 this device asks to be confirmed (done by itself when a station refuses it)
//   confirm {device, code}  a waiting device confirmed, its code compared on both screens
//   deny {device}           a waiting device turned down
//   addStation {station, code}  a station enrolled with the lock's hash, confirmed by the code it printed
//   joinStation {station}   a station of the workspace from before (offline or too old then, updated since) taken in
//   renew {device}          a web page's device for 30 days more
//   removeDevice {device}   a device taken out of the lock
//   disable                 the owner turns it off
//   state                   the `lock` topic's value, as a call (tests, scripts)
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

// deno-lint-ignore no-explicit-any
type J = any;
type Of = Extract<Call, { kind: "lock" }>;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

/// How soon before a web page's device runs out its person is reminded.
export const RENEW_SECS = 5 * 86400;
/// A device of the person's own added this recently is pointed out on their other devices.
const RECENT_SECS = 7 * 86400;

/// What the cloud keeps of a workspace's lock, as held here (the `lock` record of the workspace).
type Held = { head: Head | null; entries: Entry[]; requests: J[] };

/// What this device keeps of a workspace's lock this run.
type Part = {
  /// Stations that refused this device for the lock, and the lock's head then.
  refused: Map<string, string | null>;
  /// This device asked to be confirmed (at that head).
  requested: string | null | undefined;
  /// Of the draft: what is left out; the devices that asked for credentials; each station's answer to GET /lock.
  excluded: Set<string>;
  devices: J[] | null;
  probes: Map<string, "ok" | "old" | "offline">;
  /// The base key of this device (the mesh's), once known.
  base: string | null;
};

/// What the signing key of this device is, as loaded (undefined: not loaded yet), per core.
const signers = new WeakMap<Inner, string | null>();

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
  inner.workspaces.of(ws).part<Part>("lock", () => ({ refused: new Map(), requested: undefined, excluded: new Set(), devices: null, probes: new Map(), base: null }));

const held = (inner: Inner, ws: string): Held | null => {
  const h = inner.data.record("lock", ws);
  return isObject(h) && Array.isArray(h.entries) ? (h as unknown as Held) : null;
};

const view = (inner: Inner, ws: string): J => inner.data.shared({ topic: "workspace", workspace: ws });

/// What the workspace view says of the lock: its head and how many devices wait (undefined: a cloud from before).
const cloudSays = (v: J): string | undefined => (!isObject(v) || !("lock" in v) ? undefined : `${get(v.lock, "hash") ?? ""}/${get(v, "lock_requests") ?? 0}`);

const now = (inner: Inner) => Math.floor(inner.host.nowMs() / 1000);
const daysLeft = (secs: number) => Math.max(0, Math.ceil(secs / 86400));

export function install(inner: Inner): void {
  hooks.enrolled = enrolled;
  hooks.lockRefused = refused;
  hooks.lockWaiting = waiting;
  handlers.lock = (core, call, _progress, _at, ctx) => run(core, call as Of, ctx);
  // The signing key, once (it is the device's).
  inner.runner.fork(
    Effect.map(Effect.orElseSucceed(Signer.load(inner.host), () => null), (s) => {
      signers.set(inner, s?.id ?? null);
      inner.store.invalidateAll((t) => t.topic === "lock");
    }),
  );
  // The workspace view says how far the cloud's lock goes and how many wait: read again when that changes.
  inner.data.onChange((topic) => {
    if (topic.topic !== "workspace" || inner.provider.kind !== "stillfail") return;
    const ws = topic.workspace as string;
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
function read(inner: Inner, ws: string): Effect.Effect<void, CoreError> {
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
    inner.data.put("lock", ws, { head, entries: head === null ? [] : entries, requests });
    if ((was?.head?.hash ?? null) !== (head?.hash ?? null)) moved(inner, ws);
    inner.store.invalidateAll((t) => (t.topic === "lock" || t.topic === "lockDraft") && t.workspace === ws);
  });
}

/// The lock moved on: the stations that refused this device before are tried again now.
function moved(inner: Inner, ws: string): void {
  const p = part(inner, ws);
  for (const station of [...p.refused.keys()]) {
    p.refused.delete(station);
    inner.stations?.cameOnline(`${ws}/${station}`);
  }
}

/// A station refused this device for the lock: noted, and (once a head) this device asks to be confirmed.
function refused(inner: Inner, ws: string, station: string): void {
  if (inner.provider.kind !== "stillfail") return;
  const p = part(inner, ws);
  const head = held(inner, ws)?.head?.hash ?? null;
  p.refused.set(station, head);
  inner.store.invalidateAll((t) => t.topic === "lock" && t.workspace === ws);
  if (p.requested === head) return;
  p.requested = head;
  const sub = inner.workspaces.owner(ws);
  if (sub === null) return;
  // Asked again a few times if the cloud did not take it (the page says the others were told); after that, the next
  // refusal asks anew.
  const ask = Effect.retry(new Lock(inner, ws, sub, null).request(), { times: 5, schedule: Schedule.spaced("2 seconds") });
  inner.scheduler.enqueue("cloud", `lock/${ws}/request`, Priority.background, Effect.asVoid(Effect.tapError(ask, () => Effect.sync(() => (p.requested = undefined)))));
}

/// Why a station is not asked now: it refused this device and the lock has not moved on since.
function waiting(inner: Inner, ws: string, station: string): CoreError | null {
  const p = inner.workspaces.get(ws)?.own.get("lock") as Part | undefined;
  if (!p || !p.refused.has(station)) return null;
  if (p.refused.get(station) !== (held(inner, ws)?.head?.hash ?? null)) {
    p.refused.delete(station);
    return null;
  }
  return new CoreError("lock_unconfirmed", "this device waits to be confirmed in the workspace's security mode");
}

/// What a control plane that keeps no lock shows.
const NONE = { available: false, locked: false, notice: false, role: "member", manages: false, owner: false, canSign: false, signs: false, signers: 0, members: [], stations: [], protected: 0, requests: [], renew: [], attention: 0 };
const NO_DRAFT = { available: false, loading: false, canSign: false, owner: false, ready: false, members: [], devices: [], stations: [] };

/// The topics.
function owner(inner: Inner): Owner {
  return {
    owns: (t: Topic) => t.topic === "lock" || t.topic === "lockDraft",
    start: (t: Topic) => {
      const ws = t.workspace as string;
      if (inner.provider.kind !== "stillfail") return;
      // The device's own key is the mesh's: brought up to know it.
      inner.runner.fork(
        Effect.ignore(
          Effect.map(inner.mesh(), (m) => {
            part(inner, ws).base = m.deviceId();
            inner.store.invalidate(t);
          }),
        ),
      );
      if (t.topic === "lockDraft") inner.scheduler.enqueue("cloud", `lock/${ws}/draft`, Priority.shown, draft(inner, ws));
      // Shown: read again now, what is held showing meanwhile.
      else inner.scheduler.enqueue("cloud", `lock/${ws}`, Priority.shown, read(inner, ws));
    },
    compute: (t: Topic) => {
      const ws = typeof t.workspace === "string" ? t.workspace : "";
      if (inner.provider.kind !== "stillfail") return { ok: t.topic === "lock" ? NONE : NO_DRAFT };
      return { ok: t.topic === "lock" ? lockView(inner, ws) : draftView(inner, ws) };
    },
  };
}

/// The `lock` topic.
export function lockView(inner: Inner, ws: string): J {
  const p = part(inner, ws);
  const h = held(inner, ws);
  const v = view(inner, ws);
  const f = fold(h?.entries ?? []);
  const locked = h?.head != null && !f.disabled;
  const sub = inner.workspaces.owner(ws);
  const t = now(inner);
  const signer = signers.get(inner) ?? null;
  const people = new Map<string, J>(arr(get(v, "members")).map((m) => [m.sub, m]));
  const mine = p.base ? f.devices.get(p.base) : undefined;
  const role = str(get(v, "role")) ?? "member";
  const manages = role === "owner" || role === "admin";
  const device = (d: J) => ({
    id: d.id, kind: d.kind === "web" ? "web" : "app", label: d.label || "", signs: typeof d.sign_key === "string", older: Array.isArray(d.endpoints),
    mine: d.id === p.base, daysLeft: typeof d.exp === "number" ? daysLeft(d.exp - t) : null,
    renewSoon: typeof d.exp === "number" && d.exp - t < RENEW_SECS,
    // A device of the viewer's own added lately, shown on their other devices.
    recent: d.sub === sub && d.id !== p.base && t - (f.added.get(d.id) ?? 0) < RECENT_SECS,
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
    .filter((r) => r.device !== p.base && (manages || r.yours));
  const renew = members.flatMap((m) => (m.you ? m.devices.filter((d) => d.renewSoon) : []));
  const dismissed = get(get(inner.data.shared({ topic: "prefs" }), "lockNotice"), ws) === true;
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
    signs: mine !== undefined && typeof mine.sign_key === "string" && mine.sign_key === signer,
    me: {
      device: p.base, code: p.base ? shortCode(p.base) : null, kind: inner.host.appKeys ? "app" : "web",
      confirmed: mine !== undefined, daysLeft: typeof mine?.exp === "number" ? daysLeft(mine.exp - t) : null,
      // A station refused this device and the lock has not moved on since: it waits to be confirmed.
      waiting: locked && mine === undefined && p.refused.size > 0,
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
    const lock = new Lock(inner, c.workspace, sub, ctx);
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
        inner.store.invalidateAll((t) => t.topic === "lock" && t.workspace === c.workspace);
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
      case "request":
        result = yield* lock.request();
        break;
      case "confirm":
        result = yield* lock.confirm(param("device"), param("code"));
        break;
      case "deny":
        result = yield* inner.provider.request(sub, "DELETE", `/v1/workspaces/${encodeURIComponent(c.workspace)}/lock/requests/${encodeURIComponent(param("device"))}`, null, ctx);
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
      case "disable":
        result = yield* lock.append("disable", {});
        break;
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

class Lock {
  readonly #inner: Inner;
  readonly ws: string;
  readonly sub: string;
  readonly #ctx: SpanContext | null;

  constructor(inner: Inner, ws: string, sub: string, ctx: SpanContext | null) {
    this.#inner = inner;
    this.ws = ws;
    this.sub = sub;
    this.#ctx = ctx;
  }

  #cloud(method: string, path: string, body: unknown = null) {
    return this.#inner.provider.request(this.sub, method, `/v1/workspaces/${encodeURIComponent(this.ws)}${path}`, body, this.#ctx);
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
      part(this.#inner, this.ws).base = m.deviceId();
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
      signers.set(inner, signer.id);
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
      const signer = self.#inner.host.appKeys ? yield* Signer.make(self.#inner.host) : null;
      if (signer) signers.set(self.#inner, signer.id);
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
      yield* Effect.ignore(self.#cloud("DELETE", `/lock/requests/${device}`));
      return done;
    });
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
      return yield* self.append("station", { key: station, name: s?.name ?? "" });
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
      const done = yield* self.append("station", { key: station, name: s.name ?? "" });
      const pinned = get(get(done, "stations"), station);
      if (isObject(pinned) && typeof pinned.error === "string") return yield* Effect.fail(new CoreError("lock_station_refused", pinned.error));
      return done;
    });
  }

  /// One more entry, signed by this app's key, after the chain as the cloud keeps it: to the cloud, then to each
  /// station of the lock this device reaches (they also bring each other level, and ask the cloud).
  append(kind: string, body: unknown): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const signer = yield* Signer.load(self.#inner.host);
      if (signer === null) return yield* Effect.fail(new CoreError("lock_no_signer", "this device signs nothing for the workspace lock"));
      const { head, entries } = yield* self.#chain();
      if (head === null) return yield* Effect.fail(new CoreError("lock_none", "the workspace has no lock"));
      const entry = signer.sign(next(self.ws, head, self.#inner.host.nowMs() / 1000, kind, body));
      yield* self.#cloud("POST", "/lock", { entries: [entry] });
      // The whole chain: a station that is behind takes what it lacks, and skips what it has.
      const pinned = yield* self.#bring([...entries, entry], [...fold([...entries, entry]).stations.keys()]);
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
