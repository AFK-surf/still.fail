// A workspace's rigs (a station that only runs tasks, 2026-11-10): machines someone added that run no agents and only take tasks from the
// workspace's stations, each its person's (station/src/rig/, station/src/rigs/). The `rigs` topic and the `rig.*`
// calls. A device never links to a rig: how each is (reached, 免批准, the chats granted it, the requests waiting) is
// what the workspace's stations say of it (`GET /rigs`, the `rigs` event), beside what the cloud lists (whose it is).
//
// What changes who may use a rig is its person's alone, signed here with a key on their own lock (personal-lock.ts
// `signRig`, rig-form.ts) and carried by a station to the rig, which checks it itself: a chat's grant
// (`rig.decide`), one taken back (`rig.revoke`), 免批准 (`rig.setOpen`). A rig is added by a command its person
// runs on the machine (`rig.add`), which names their own lock for the rig to pin; in a workspace in security mode
// they then compare the rig's code and sign for it (`rig.vouch`).
import { Effect, type Result } from "effect";
import { CoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import { shortCode } from "./lock.ts";
import type { PersonalLock } from "./personal-lock.ts";
import { type AddBody, type Device, type DeviceBody, type FullBody, type GrantBody, type RevokeBody, type SettingsBody, type Signed, type Timeout, TIMEOUT_DEFAULT, latest, signedBytes, timeoutRefusal } from "./rig-form.ts";
import { StationAddr } from "./station/addr.ts";
import type { Store } from "./store.ts";
import { get } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

export type RigCall =
  /// A rig added to `workspace`, named `name`: the commands to run on the machine (as `workspace.enroll` answers them).
  | { kind: "add"; workspace: string; name: string }
  /// A chat's request decided by the rig's person, as its card says it (`ask`: the card's `rigAsk`): `timeout` grants
  /// it for that long, null refuses it.
  | { kind: "decide"; station: string; request: string; timeout: Timeout | null; ask: J }
  /// A grant (or a request still asked) of a rig taken back by its person. `station`: the chat's.
  | { kind: "revoke"; workspace: string; rig: string; request: string; station: string }
  /// 免批准 on or off.
  | { kind: "setOpen"; workspace: string; rig: string; open: boolean }
  /// What a station is: `tasks`, a whole one made one that only runs tasks (a rig, this person's); `full`, a rig made
  /// a whole station again.
  | { kind: "setMode"; workspace: string; station: string; mode: "full" | "tasks" }
  /// Security mode: the rig's code compared, and the rig signed for.
  | { kind: "vouch"; workspace: string; rig: string; code: string }
  /// What the rig was last told to run.
  | { kind: "log"; workspace: string; rig: string };

export function parseRig(name: string, params: unknown): RigCall | null {
  const text = (field: string) => {
    const v = get(params, field);
    return typeof v === "string" ? v : "";
  };
  const need = (field: string) => {
    const v = text(field);
    if (v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
    return v;
  };
  switch (name) {
    case "rig.add":
      return { kind: "add", workspace: need("workspace"), name: need("name") };
    case "rig.decide": {
      const station = need("station");
      try {
        StationAddr.parse(station);
      } catch {
        throw CoreError.invalid(t("core-misc.params.missing", { field: "station" }));
      }
      const allow = get(params, "allow") === true;
      const kind = get(params, "timeoutKind");
      const seconds = get(params, "timeoutSeconds");
      const timeout: Timeout = kind === "idle" || kind === "fixed" ? { kind, seconds: typeof seconds === "number" ? seconds : 0 } : TIMEOUT_DEFAULT;
      const why = allow ? timeoutRefusal(timeout) : null;
      if (why !== null) throw CoreError.invalid(why);
      return { kind: "decide", station, request: need("request"), timeout: allow ? timeout : null, ask: get(params, "ask") ?? {} };
    }
    case "rig.revoke":
      return { kind: "revoke", workspace: need("workspace"), rig: need("rig"), request: need("request"), station: text("station") };
    case "rig.setOpen": {
      const open = get(params, "open");
      if (typeof open !== "boolean") throw CoreError.invalid(t("core-misc.params.missing", { field: "open" }));
      return { kind: "setOpen", workspace: need("workspace"), rig: need("rig"), open };
    }
    case "rig.vouch":
      return { kind: "vouch", workspace: need("workspace"), rig: need("rig"), code: need("code") };
    case "rig.log":
      return { kind: "log", workspace: need("workspace"), rig: need("rig") };
    case "rig.setMode": {
      const mode = get(params, "mode");
      if (mode !== "full" && mode !== "tasks") throw CoreError.invalid(t("core-misc.params.missing", { field: "mode" }));
      return { kind: "setMode", workspace: need("workspace"), station: need("station"), mode };
    }
    default:
      return null;
  }
}

export type RigsEnv = {
  host: Host;
  store: Store;
  personal: () => PersonalLock;
  /// The account a workspace is signed in as here.
  subOf: (workspace: string) => string | null;
  /// The workspace as the cloud lists it (its `rigs`, `stations`), as held here.
  view: (workspace: string) => J;
  /// A request to a station (its admin API), and to the cloud as an account.
  call: (station: StationAddr, method: string, path: string, body: unknown) => Effect.Effect<unknown, CoreError>;
  cloud: (sub: string, method: string, path: string, body: unknown) => Effect.Effect<unknown, CoreError>;
  /// Several stations asked at once: what each answered once one took it (views/lock.ts `answersOf`, `tookOrRefused`).
  first: <A>(asks: Effect.Effect<A, CoreError>[], at: string[]) => Effect.Effect<Result.Result<A, CoreError>[]>;
  /// The workspace's lock here: whether it is in security mode, a station's commands with its head to pin
  /// (views/lock.ts `enrolled`), and how this device signs for its person there (`signsAs`), with the key that does.
  lock: {
    locked(workspace: string): boolean;
    enrolled(sub: string, workspace: string, made: unknown): Effect.Effect<unknown, CoreError>;
    signsAs(workspace: string): "lock" | "person" | null;
    signAdd(workspace: string, bytes: Uint8Array): Effect.Effect<{ key: string; sig: string }, CoreError>;
  };
  sha256: (bytes: Uint8Array) => Uint8Array;
};

const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string => (typeof v === "string" ? v : "");

/// A chat's grant in force as a rig says it, as the app is given it (`RigGrant`).
function grantRow(g: J, stationNames: Map<string, string>): J {
  return {
    request: str(g?.request), station: str(g?.station), stationName: str(g?.stationName) || stationNames.get(str(g?.station)) || str(g?.station).slice(0, 12),
    session: str(g?.session), chat: str(g?.chat), title: str(g?.title), by: str(g?.by),
    timeoutKind: str(g?.timeout?.kind), timeoutSeconds: Number(g?.timeout?.seconds ?? 0), exp: Number(g?.exp ?? 0), until: Number(g?.until ?? 0),
  };
}

export class Rigs {
  readonly #env: RigsEnv;
  /// What each station last said of its workspace's rigs (`GET /rigs`, the `rigs` event), by the station's address.
  readonly #said = new Map<string, { workspace: string; rigs: J[] }>();
  /// The number of the settings signed here last, by rig.
  readonly #numbered = new Map<string, number>();

  constructor(env: RigsEnv) {
    this.#env = env;
  }

  // ── what the stations say ──

  /// A station's rigs read whole, as it is reached (one from before rigs has no such route: it says nothing).
  read(station: string): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const at = StationAddr.parse(station);
      return Effect.map(Effect.orElseSucceed(this.#env.call(at, "GET", "/rigs", null), () => null), (r) => {
        if (r !== null) this.#take(station, at.workspace, r);
      });
    });
  }

  /// A station's event: `rigs`, the workspace's rigs as it has them now.
  heard(station: string, name: string, data: unknown): void {
    if (name !== "rigs") return;
    let workspace: string;
    try {
      workspace = StationAddr.parse(station).workspace;
    } catch {
      return;
    }
    this.#take(station, workspace, data);
  }

  #take(station: string, workspace: string, data: unknown): void {
    if (str(get(data, "workspace")) !== workspace) return;
    this.#said.set(station, { workspace, rigs: arr(get(data, "rigs")) });
    this.#env.store.invalidate({ topic: "rigs", workspace });
    // (their devices are the `devices` topic's too: devices.ts)
    this.#env.store.invalidate({ topic: "devices", workspace });
  }

  /// The person's own lock moved on (this device let in on it, or taken off): what each workspace's topic says of it too.
  touched(): void {
    for (const workspace of new Set([...this.#said.values()].map((s) => s.workspace))) this.#env.store.invalidate({ topic: "rigs", workspace });
  }

  // ── the topic ──

  /// The `rigs` topic of a workspace (shapes `RigsView`).
  value(workspace: string): J {
    const env = this.#env;
    const sub = env.subOf(workspace);
    const view = env.view(workspace);
    const locked = env.lock.locked(workspace);
    const stationNames = new Map<string, string>(arr(get(view, "stations")).map((s) => [str(s?.id), str(s?.name)]));
    // (a station taken out of the workspace says nothing more of its rigs)
    const said = [...this.#said].filter(([station, s]) => s.workspace === workspace && stationNames.has(StationAddr.parse(station).station));
    const standing = sub === null ? "none" : env.personal().standing(sub);
    const rigs = arr(get(view, "rigs")).map((listed) => {
      const id = str(listed?.id);
      // The station that heard the rig last says how it is; each says the requests of its own chats.
      const told = said.flatMap(([station, s]) => s.rigs.filter((r) => r?.id === id).map((r) => ({ station, r })));
      const latest = told.reduce<J | null>((best, x) => (best === null || (x.r.at ?? 0) > (best.at ?? 0) ? x.r : best), null);
      const mine = sub !== null && listed.owner === sub;
      return {
        id,
        name: str(listed?.name),
        owner: str(listed?.owner),
        ownerEmail: str(listed?.owner_email),
        ownerName: str(listed?.owner_name),
        mine,
        code: shortCode(id),
        // Taken into the workspace: always outside security mode; there, once a station this device reaches says so.
        vouched: !locked || told.some((x) => x.r.vouched === true),
        reached: latest === null ? null : latest.reached === null || latest.reached === undefined ? null : latest.reached === true,
        open: latest !== null && latest.open === true,
        known: latest !== null && typeof latest.open === "boolean",
        // (a grant of, or a request for, one of its devices is the `devices` topic's: devices.ts)
        grants: arr(latest?.grants).filter((g) => g?.device === undefined).map((g) => grantRow(g, stationNames)),
        requests: told.flatMap((x) => arr(x.r.requests).filter((q) => q?.device === undefined).map((q) => ({
          id: str(q?.id), station: x.station, session: str(q?.session), chat: str(q?.chat), title: str(q?.title), by: str(q?.by), reason: str(q?.reason),
          timeoutKind: str(q?.timeout?.kind), timeoutSeconds: Number(q?.timeout?.seconds ?? 0), at: Number(q?.at ?? 0), status: str(q?.status),
        }))),
      };
    });
    return {
      locked,
      // Whether this device signs as its person: an app's (a web page keeps no key of their own lock), on that lock.
      app: env.host.appKeys === true,
      personal: standing,
      rigs,
    };
  }

  /// The devices attached to a workspace's rigs, as the station that heard each rig last says them, with the chats'
  /// grants and requests of each (a grant of the rig itself counts for its devices: `whole`). For devices.ts.
  devices(workspace: string): J[] {
    const view = this.value(workspace);
    const stationNames = new Map<string, string>(arr(get(this.#env.view(workspace), "stations")).map((s) => [str(s?.id), str(s?.name)]));
    return arr(view.rigs).flatMap((rig: J) => {
      const latest = [...this.#said].filter(([, s]) => s.workspace === workspace).flatMap(([, s]) => s.rigs.filter((r) => r?.id === rig.id))
        .reduce<J | null>((best, r) => (best === null || (r.at ?? 0) > (best.at ?? 0) ? r : best), null);
      return arr(latest?.devices).map((d) => ({
        id: str(d?.id), name: str(d?.name), kind: str(d?.kind), target: str(d?.target), ...(typeof d?.baud === "number" ? { baud: d.baud } : {}),
        via: "rig", station: rig.id, stationName: rig.name, owner: rig.owner, ownerEmail: rig.ownerEmail, ownerName: rig.ownerName, mine: rig.mine,
        online: rig.reached, open: rig.open || d?.open === true, ownOpen: d?.open === true, settings: Number(d?.settings ?? 0),
        grants: arr(latest?.grants).filter((g) => g?.device === undefined || g?.device === d?.id).map((g) => ({ ...grantRow(g, stationNames), whole: g?.device === undefined })),
        requests: [...this.#said].filter(([, s]) => s.workspace === workspace).flatMap(([station, s]) => s.rigs.filter((r) => r?.id === rig.id)
          .flatMap((r) => arr(r.requests).filter((q) => q?.device === d?.id).map((q) => ({
            id: str(q?.id), station, session: str(q?.session), chat: str(q?.chat), title: str(q?.title), by: str(q?.by), reason: str(q?.reason),
            timeoutKind: str(q?.timeout?.kind), timeoutSeconds: Number(q?.timeout?.seconds ?? 0), at: Number(q?.at ?? 0), status: str(q?.status),
          })))),
      }));
    });
  }

  /// A device attached to a rig of this person's, or taken off it, as they sign it (rig-form.ts `DeviceBody`),
  /// carried to the rig by a station.
  device(workspace: string, rig: string, device: Device, removed: boolean): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const { sub, name } = yield* this.#mine(workspace, rig);
      const body: DeviceBody = { v: 1, sub, ws: workspace, rig, device, removed, at: this.#now() };
      const signed: Signed<DeviceBody> = yield* env.personal().signRig(sub, "device", body, t(removed ? "core-misc.device.reason.remove" : "core-misc.device.reason.add", { name: device.name, station: name }));
      yield* this.#viaStation(workspace, (at) => env.call(at, "POST", `/rigs/${rig}/devices`, { signed, chain: env.personal().entries(sub) }));
      return { device: { ...device, station: rig } };
    });
  }

  /// 免批准 on one device of a rig of this person's.
  setDeviceOpen(workspace: string, rig: string, device: string, open: boolean): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const { sub } = yield* this.#mine(workspace, rig);
      const known = [...this.#said.values()].filter((s) => s.workspace === workspace).flatMap((s) => s.rigs.filter((r) => r?.id === rig))
        .flatMap((r) => arr(r?.devices).filter((d) => d?.id === device)).reduce((m, d) => Math.max(m, Number(d?.settings ?? 0)), 0);
      const now = this.#now();
      const k = `${rig}\0${device}`;
      const seq = Math.max(known + 1, (this.#numbered.get(k) ?? 0) + 1, now);
      this.#numbered.set(k, seq);
      const dev = this.devices(workspace).find((d) => d.station === rig && d.id === device);
      const body: SettingsBody = { v: 1, sub, ws: workspace, rig, seq, open, at: now, device };
      const signed: Signed<SettingsBody> = yield* env.personal().signRig(sub, "settings", body, t("core-misc.device.reason.settings", { name: str(dev?.name) }));
      return yield* this.#viaStation(workspace, (at) => env.call(at, "POST", `/rigs/${rig}/settings`, { signed, chain: env.personal().entries(sub) }));
    });
  }

  // ── the calls ──

  run(call: RigCall): Effect.Effect<unknown, CoreError> {
    switch (call.kind) {
      case "add":
        return this.#add(call.workspace, call.name);
      case "decide":
        return this.#decide(call);
      case "revoke":
        return this.#revoke(call);
      case "setOpen":
        return this.#setOpen(call.workspace, call.rig, call.open);
      case "vouch":
        return this.#vouch(call.workspace, call.rig, call.code);
      case "log":
        return this.#viaStation(call.workspace, (at) => this.#env.call(at, "GET", `/rigs/${call.rig}/log?limit=100`, null));
      case "setMode":
        return call.mode === "tasks" ? this.#toTasks(call.workspace, call.station) : this.#toFull(call.workspace, call.station);
    }
  }

  #sub(workspace: string): Effect.Effect<string, CoreError> {
    const sub = this.#env.subOf(workspace);
    return sub === null ? Effect.fail(new CoreError("rig_unknown", t("core-misc.rig.unknown"))) : Effect.succeed(sub);
  }

  /// The rig as listed, which must be this person's.
  #mine(workspace: string, rig: string): Effect.Effect<{ sub: string; name: string }, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const sub = yield* this.#sub(workspace);
      const listed = arr(get(this.#env.view(workspace), "rigs")).find((r) => r?.id === rig);
      if (listed === undefined) return yield* Effect.fail(new CoreError("rig_unknown", t("core-misc.rig.unknown")));
      if (listed.owner !== sub) return yield* Effect.fail(new CoreError("rig_not_owner", t("core-misc.rig.notOwner")));
      return { sub, name: str(listed.name) };
    });
  }

  /// The workspace's stations, those that told of its rigs (so are reached, and know them) first.
  #stations(workspace: string): StationAddr[] {
    const all = arr(get(this.#env.view(workspace), "stations")).flatMap((s) => (typeof s?.id === "string" ? [new StationAddr(workspace, s.id)] : []));
    const told = (at: StationAddr) => (this.#said.has(at.toString()) ? 0 : 1);
    return all.sort((a, b) => told(a) - told(b));
  }

  /// `ask` of the workspace's stations at once, done once one took it: what it answered.
  #viaStation(workspace: string, ask: (at: StationAddr) => Effect.Effect<unknown, CoreError>): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const stations = this.#stations(workspace);
      if (stations.length === 0) return yield* Effect.fail(new CoreError("rig_no_station", t("core-misc.rig.noStation")));
      const answers = yield* this.#env.first(stations.map(ask), stations.map(String));
      const ok = answers.find((r) => r._tag === "Success");
      if (ok !== undefined && ok._tag === "Success") return ok.success;
      // Refused where it was heard: its words; reached by none: said so.
      const refused = answers.find((r) => r._tag === "Failure" && r.failure.status !== undefined && r.failure.status >= 400 && r.failure.status < 500);
      if (refused !== undefined && refused._tag === "Failure") return yield* Effect.fail(refused.failure);
      return yield* Effect.fail(new CoreError("rig_no_station", t("core-misc.rig.noStation")));
    });
  }

  #now(): number {
    return Math.floor(this.#env.host.nowMs() / 1000);
  }

  /// The hash of `sub`'s own lock, which a rig of theirs pins: begun here where they have none yet, and this device
  /// (an app's) on it.
  #person(sub: string): Effect.Effect<string, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      if (env.host.appKeys !== true) return yield* Effect.fail(new CoreError("rig_app_only", t("core-misc.rig.appOnly")));
      const personal = env.personal();
      const read = yield* Effect.result(personal.refresh(sub, undefined, personal.asked()));
      const standing = personal.standing(sub);
      // Not heard from the cloud, no lock known here is not no lock: one begun now would take its place.
      if (read._tag === "Failure" && standing === "none") return yield* Effect.fail(read.failure);
      if (standing === "outside") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (standing === "replaced") return yield* Effect.fail(new CoreError("personal_replaced", t("core-misc.personal.replaced")));
      // (none yet is no step of its own, as a phone's first grant: it is begun here, this device its first)
      if (standing === "none") yield* personal.begin(sub, t("core-misc.personal.reason.open"));
      const root = personal.root(sub);
      if (root === null) return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      return root;
    });
  }

  /// A whole station made one that only runs tasks by its owner, who added it (the cloud says who may: StationView
  /// `mine`; the user, 2026-11-10): the station is asked first, by this device itself, and told their own lock to pin;
  /// then the cloud lists it so, at which the station becomes one. Asked again, both are again: neither half alone
  /// changes what it is.
  #toTasks(workspace: string, station: string): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const sub = yield* this.#sub(workspace);
      const person = yield* this.#person(sub);
      yield* env.call(new StationAddr(workspace, station), "POST", "/mode", { mode: "tasks", person });
      return yield* env.cloud(sub, "PATCH", `/v1/workspaces/${encodeURIComponent(workspace)}/stations/${encodeURIComponent(station)}`, { mode: "tasks" });
    });
  }

  /// A rig made a whole station again by its person, one of the workspace's managers: what they sign is carried to it
  /// by a station, then the cloud lists it as a station, at which it becomes one.
  #toFull(workspace: string, rig: string): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const { sub, name } = yield* this.#mine(workspace, rig);
      const body: FullBody = { v: 1, sub, ws: workspace, rig, at: this.#now() };
      const signed: Signed<FullBody> = yield* env.personal().signRig(sub, "full", body, t("core-misc.rig.reason.full", { name }));
      yield* this.#viaStation(workspace, (at) => env.call(at, "POST", `/rigs/${rig}/full`, { signed, chain: env.personal().entries(sub) }));
      return yield* env.cloud(sub, "PATCH", `/v1/workspaces/${encodeURIComponent(workspace)}/stations/${encodeURIComponent(rig)}`, { mode: "full" });
    });
  }

  #add(workspace: string, name: string): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const sub = yield* this.#sub(workspace);
      const root = yield* this.#person(sub);
      const made = (yield* env.lock.enrolled(sub, workspace, yield* env.cloud(sub, "POST", `/v1/workspaces/${encodeURIComponent(workspace)}/rigs/enrollments`, { name }))) as J;
      const out: J = { ...made, person: root };
      if (typeof out.install === "string") out.install = `${out.install} rig:${root}`;
      if (typeof out.installWindows === "string") out.installWindows = `${out.installWindows} rig:${root}`;
      if (typeof out.command === "string") out.command = `${out.command} --rig ${root}`;
      return out;
    });
  }

  #decide(call: Extract<RigCall, { kind: "decide" }>): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const at = StationAddr.parse(call.station);
      const path = `/rigs/requests/${encodeURIComponent(call.request)}/decide`;
      if (call.timeout === null) return yield* env.call(at, "POST", path, { allow: false });
      const ask = call.ask;
      const rig = str(get(ask, "rig"));
      const { sub, name } = yield* this.#mine(at.workspace, rig);
      const now = this.#now();
      const body: GrantBody = {
        v: 1, sub, ws: at.workspace, rig, station: at.station, session: str(get(ask, "session")), chat: str(get(ask, "chat")), request: call.request,
        title: str(get(ask, "title")), by: str(get(ask, "by")), timeout: call.timeout, at: now, exp: latest(now, call.timeout),
        ...(str(get(ask, "device")) !== "" ? { device: str(get(ask, "device")) } : {}),
      };
      const signed = yield* env.personal().signRig(sub, "grant", body, t("core-misc.rig.reason.grant", { name }), call.station);
      return yield* env.call(at, "POST", path, { allow: true, signed, chain: env.personal().entries(sub) });
    });
  }

  #revoke(call: Extract<RigCall, { kind: "revoke" }>): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const { sub, name } = yield* this.#mine(call.workspace, call.rig);
      const path = `/rigs/requests/${encodeURIComponent(call.request)}/revoke`;
      // A request still asked is refused with no signature; a grant is taken back on what is signed.
      const pending = [...this.#said.values()].some((s) => s.workspace === call.workspace && s.rigs.some((r) => r?.id === call.rig && arr(r.requests).some((q) => q?.id === call.request && q?.status === "pending")));
      let said: J = { rig: call.rig };
      if (!pending) {
        const body: RevokeBody = { v: 1, sub, ws: call.workspace, rig: call.rig, request: call.request, at: this.#now() };
        const signed: Signed<RevokeBody> = yield* env.personal().signRig(sub, "revoke", body, t("core-misc.rig.reason.revoke", { name }));
        said = { rig: call.rig, signed, chain: env.personal().entries(sub) };
      }
      // Its chat's own station ends it there at once; with that one away, any station carries it to the rig.
      let own: StationAddr | null = null;
      try {
        own = call.station === "" ? null : StationAddr.parse(call.station.includes("/") ? call.station : new StationAddr(call.workspace, call.station).toString());
      } catch {
        own = null;
      }
      if (own !== null) {
        const direct = yield* Effect.result(env.call(own, "POST", path, said));
        if (direct._tag === "Success") return direct.success;
        if (direct.failure.status !== undefined && direct.failure.status >= 400 && direct.failure.status < 500) return yield* Effect.fail(direct.failure);
      }
      if (pending) return yield* Effect.fail(new CoreError("rig_no_station", t("core-misc.rig.noStation")));
      return yield* this.#viaStation(call.workspace, (at) => env.call(at, "POST", path, said));
    });
  }

  #setOpen(workspace: string, rig: string, open: boolean): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const { sub, name } = yield* this.#mine(workspace, rig);
      // Numbered after the settings the rig has, as far as a station said, after those signed here last (two in one
      // second), and never behind this device's clock: a rig takes only settings newer than its own.
      const known = [...this.#said.values()].filter((s) => s.workspace === workspace).flatMap((s) => s.rigs.filter((r) => r?.id === rig)).reduce((m, r) => Math.max(m, Number(r?.settings ?? 0)), 0);
      const now = this.#now();
      const seq = Math.max(known + 1, (this.#numbered.get(rig) ?? 0) + 1, now);
      this.#numbered.set(rig, seq);
      const body: SettingsBody = { v: 1, sub, ws: workspace, rig, seq, open, at: now };
      const signed: Signed<SettingsBody> = yield* env.personal().signRig(sub, "settings", body, t("core-misc.rig.reason.settings", { name }));
      return yield* this.#viaStation(workspace, (at) => env.call(at, "POST", `/rigs/${rig}/settings`, { signed, chain: env.personal().entries(sub) }));
    });
  }

  #vouch(workspace: string, rig: string, code: string): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const env = this.#env;
      const { sub, name } = yield* this.#mine(workspace, rig);
      if (shortCode(rig) !== code.trim().toUpperCase()) return yield* Effect.fail(new CoreError("rig_wrong_code", t("core-misc.rig.wrongCode")));
      const body: AddBody = { v: 1, sub, ws: workspace, rig, at: this.#now() };
      const how = env.lock.signsAs(workspace);
      if (how === null) return yield* Effect.fail(new CoreError("lock_no_signer", t("core-misc.rig.notSigner")));
      let signed: Signed<AddBody>;
      if (how === "person") signed = yield* env.personal().signRig(sub, "add", body, t("core-misc.rig.reason.add", { name }));
      else signed = { body, sig: yield* env.lock.signAdd(workspace, signedBytes("add", body, env.sha256)) };
      // To every station at once: each checks it against the lock it pinned, and takes the rig from then on.
      return yield* this.#viaStation(workspace, (at) => env.call(at, "POST", `/rigs/${rig}/add`, { signed }));
    });
  }
}
