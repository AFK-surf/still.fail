// The workspace lock's calls (docs/workspace-lock.md): what a person does with it, done here so the pages only draw.
// The cloud keeps the chain and carries it; the stations check every entry and decide. Here an app signs (lock.ts
// `Signer`) and brings what it signed to the cloud and to each station it reaches.
//
//   lock.state {workspace}                       how far the lock goes, this device's place in it, who waits
//   lock.open {workspace, exclude?}              the owner turns it on: everyone and everything listed now, signed at once
//   lock.request {workspace}                     this device asks to be confirmed (its short code is shown)
//   lock.confirm {workspace, device, code}       a waiting device confirmed (the code compared on both screens)
//   lock.addStation {workspace, station, code}   a station joined with the lock confirmed
//   lock.disable {workspace}                     the owner turns it off
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { handlers, hooks } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import { CoreError } from "../error.ts";
import { type Entry, type Head, Signer, WEB_DEVICE_SECS, entryHash, next, readHead, shortCode } from "../lock.ts";
import * as prefs from "../prefs.ts";
import { StationAddr } from "../station/addr.ts";
import type { SpanContext } from "../trace.ts";
import { get, isObject } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Of = Extract<Call, { kind: "lock" }>;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const strs = (v: unknown): string[] => arr(v).filter((x): x is string => typeof x === "string");

/// What the entries say, unchecked (the stations check them): who and what is in the lock.
export type Folded = { members: Map<string, { email: string; role: string }>; devices: Map<string, J>; stations: Map<string, string>; disabled: boolean };

export function fold(entries: Entry[]): Folded {
  const f: Folded = { members: new Map(), devices: new Map(), stations: new Map(), disabled: false };
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

/// A station's enrollment in a locked workspace: its commands name the lock's head, which it pins (`--lock`), as the
/// stations this device reaches have it (the cloud's word only when none answers).
export function enrolled(inner: Inner, sub: string, ws: string, made: unknown): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const lock = new Lock(inner, ws, sub, null);
    const head = yield* lock.head();
    if (head === null || !isObject(made)) return made;
    const out: J = { ...made, lock: head.hash };
    if (typeof out.install === "string") out.install = `${out.install} ${head.hash}`;
    if (typeof out.installWindows === "string") out.installWindows = `${out.installWindows} ${head.hash}`;
    if (typeof out.command === "string") out.command = `${out.command} --lock ${head.hash}`;
    return out;
  });
}

export function install(inner: Inner): void {
  hooks.enrolled = enrolled;
  handlers.lock = (_inner, call, _progress, _at, ctx) => {
    const c = call as Of;
    return Effect.gen(function* () {
      const sub = inner.workspaces.owner(c.workspace);
      if (sub === null) return yield* Effect.fail(CoreError.invalid("not a workspace of the signed-in accounts"));
      const lock = new Lock(inner, c.workspace, sub, ctx);
      switch (c.name) {
        case "state":
          return yield* lock.state();
        case "open":
          return yield* lock.open(strs(get(c.params.exclude, "devices")), strs(get(c.params.exclude, "stations")));
        case "request":
          return yield* lock.request();
        case "confirm":
          return yield* lock.confirm(str(c.params.device) ?? "", str(c.params.code) ?? "");
        case "addStation":
          return yield* lock.addStation(str(c.params.station) ?? "", str(c.params.code) ?? "");
        case "disable":
          return yield* lock.append("disable", {});
      }
      return yield* Effect.fail(CoreError.invalid(`no lock call ${c.name}`));
    });
  };
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
  #base(): Effect.Effect<string, CoreError> {
    return Effect.map(this.#inner.mesh(), (m) => m.deviceId());
  }

  #kind(): "app" | "web" {
    return this.#inner.host.appKeys ? "app" : "web";
  }

  #label(): string {
    return prefs.deviceName(this.#inner.data) ?? "";
  }

  /// The chain as the cloud keeps it.
  #chain(): Effect.Effect<{ head: Head | null; entries: Entry[] }, CoreError> {
    return Effect.map(this.#cloud("GET", "/lock"), (r) => ({ head: readHead(get(r, "head")), entries: arr(get(r, "entries")) as Entry[] }));
  }

  /// The workspace as the cloud says it: its members and stations.
  #workspace(): Effect.Effect<J, CoreError> {
    return this.#cloud("GET", "");
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

  state(): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const [{ head, entries }, base, signer] = yield* Effect.all([self.#chain(), self.#base(), Signer.load(self.#inner.host)]);
      const f = fold(entries);
      const requests = yield* Effect.orElseSucceed(Effect.map(self.#cloud("GET", "/lock/requests"), (r) => arr(get(r, "requests"))), () => [] as J[]);
      const mine = f.devices.get(base);
      return {
        locked: head !== null && !f.disabled,
        head,
        me: { device: base, code: shortCode(base), kind: self.#kind(), signer: signer?.id ?? null, confirmed: mine !== undefined, signs: mine?.sign_key !== undefined && mine.sign_key === signer?.id, expires: mine?.exp ?? null },
        members: [...f.members].map(([sub, m]) => ({ sub, ...m, devices: [...f.devices.values()].filter((d) => d.sub === sub).map((d) => ({ id: d.id, kind: d.kind, label: d.label, signs: d.sign_key !== undefined, expires: d.exp ?? null, older: d.endpoints !== undefined })) })),
        stations: [...f.stations].map(([id, name]) => ({ id, name })),
        requests,
      };
    });
  }

  /// The owner turns the lock on: the workspace's members, the devices that asked for credentials lately (but those
  /// left out), this device as the first signer, and the stations that answer and understand a lock (an older one, or
  /// one offline, is left out: one the lock names but that does not hold it could be used against the rest). The
  /// genesis goes to the cloud and to each of those stations.
  open(excludeDevices: string[], excludeStations: string[]): Effect.Effect<unknown, CoreError> {
    const self = this;
    const inner = this.#inner;
    return Effect.gen(function* () {
      const view = yield* self.#workspace();
      if (get(view, "role") !== "owner") return yield* Effect.fail(new CoreError("forbidden", "only the workspace's owner turns its lock on"));
      const signer = yield* Signer.make(inner.host);
      const base = yield* self.#base();
      const registered = arr(get(yield* self.#cloud("GET", "/devices"), "devices"));
      const origin = inner.host.cloudOrigin();
      const keysAnswer = yield* Effect.mapError(inner.host.fetch({ method: "GET", url: `${origin}/.well-known/stillfail-grant-keys`, headers: [], body: null }), (e) => new CoreError("network", e.message));
      const cloudKeys = JSON.parse(new TextDecoder().decode(keysAnswer.body));
      const members = arr(get(view, "members")).map((m) => ({ sub: m.sub, email: m.email, role: m.role }));
      const devices: J[] = [{ id: base, sub: self.sub, kind: self.#kind(), label: self.#label(), sign_key: signer.id }];
      for (const r of registered) {
        if (!members.some((m) => m.sub === r.sub)) continue;
        // A newer client: its base key, which proves each endpoint. An older one: the endpoint it asked for.
        const id = typeof r.base === "string" ? r.base : r.device;
        if (excludeDevices.includes(id) || devices.some((d) => d.id === id)) continue;
        const d: J = { id, sub: r.sub, kind: r.kind === "web" ? "web" : "app", label: typeof r.label === "string" ? r.label : "" };
        if (typeof r.base !== "string") d.endpoints = [r.device];
        devices.push(d);
      }
      const answering: { id: string; name: string }[] = [];
      const left: { id: string; name: string; why: string }[] = [];
      for (const s of arr(get(view, "stations"))) {
        if (excludeStations.includes(s.id)) continue;
        // A station that understands a lock answers GET /lock; one before it answers 404.
        const r = yield* Effect.result(self.#station(s.id, "GET", "/lock"));
        if (r._tag === "Success") answering.push({ id: s.id, name: s.name });
        else left.push({ id: s.id, name: s.name, why: r.failure.code === "http_404" || /404|no route/.test(r.failure.message) ? "upgrade" : "offline" });
      }
      const u = new URL(origin);
      const genesis = signer.sign(next(self.ws, null, inner.host.nowMs() / 1000, "genesis", {
        owner: self.sub, origins: [u.origin], rp_id: u.hostname, cloud_keys: cloudKeys, members, devices, passkeys: [],
        stations: answering.map((s) => ({ key: s.id, name: s.name })), gateways: [],
      }));
      yield* self.#cloud("POST", "/lock", { entries: [genesis] });
      const pinned = yield* self.#bring([genesis], answering.map((s) => s.id));
      return { head: { seq: 0, hash: entryHash(genesis), genesis: entryHash(genesis) }, stations: answering.map((s) => ({ ...s, pinned: pinned[s.id] ?? null })), left, devices: devices.length, members: members.length };
    });
  }

  /// This device asks to be confirmed: its base key (and an app's signing key), told to the owners, admins and the
  /// member's own other devices through the cloud. The code it shows is the one they compare.
  request(): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const base = yield* self.#base();
      const signer = self.#inner.host.appKeys ? yield* Signer.make(self.#inner.host) : null;
      yield* self.#cloud("POST", "/lock/requests", { base, kind: self.#kind(), label: self.#label(), sign_key: signer?.id ?? null });
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
      if (body.kind === "web") body.exp = Math.floor(self.#inner.host.nowMs() / 1000) + WEB_DEVICE_SECS;
      const done = yield* self.append("device", body);
      yield* Effect.ignore(self.#cloud("DELETE", `/lock/requests/${device}`));
      return done;
    });
  }

  /// A station enrolled with the lock's hash (`--lock`), confirmed by the code it printed.
  addStation(station: string, code: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      if (shortCode(station) !== code.trim().toUpperCase()) return yield* Effect.fail(CoreError.invalid("the code does not match that station's"));
      const view = yield* self.#workspace();
      const s = arr(get(view, "stations")).find((x) => x.id === station);
      return yield* self.append("station", { key: station, name: s?.name ?? "" });
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
