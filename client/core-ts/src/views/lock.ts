// The workspace lock on this device: what the pages show of it and what a person does with
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
//   hide                    its prompt closed: no longer shown, the code still good
//
// A station that refuses this device for the lock (`lock_unconfirmed`) is not asked again until the lock moves on
// (someone confirmed something): what waits for it then is tried at once.
import { Deferred, Effect, type Result, Schedule } from "effect";
import type { Inner } from "../core.ts";
import { type Roster, handlers, hooks } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { CARRY_BYTES, type Entry, type Head, Signer, WEB_DEVICE_SECS, entryHash, next, readHead, shortCode } from "../lock.ts";
import * as prefs from "../prefs.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { Priority } from "../sync/scheduler.ts";
import type { SpanContext } from "../trace.ts";
import { get, isObject } from "../util.ts";
import { type Checked, checkLock, signerIn } from "../vault/lock-check.ts";
import { unsealOwn, vaultAsks, vaultCome, writePlain } from "./vault.ts";
import { laterSleep } from "../runtime.ts";
import { Marks } from "../reactive.ts";
import { ofAddress } from "../workspace.ts";
import type { PersonalEnv } from "../personal-lock.ts";

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
/// How soon a station that refused this device, though the lock as held here names it, is tried again.
export const BEHIND_MS = 3_000;
/// How many times it is, for one head of the lock.
export const BEHIND_TRIES = 5;
/// How long what is signed waits for one of the stations serving the lock to take it, before the cloud is what does.
export const TAKEN_MS = 15_000;
/// A device of the person's own added this recently is pointed out on their other devices.
const RECENT_SECS = 7 * 86400;
/// Once one station answered a read of the locks, how much longer the others are waited for.
export const OTHERS_MS = 2_000;

/// Each of `asks` (one a station) at once, and what they answered once all have; or once one answered and the rest
/// had what `after` says of that answer more (null: as if none came); or by TAKEN_MS whatever came. A station gone
/// silent (its machine asleep, its network gone: no answer, no close, until its link gives up) is not waited on; nor
/// is the person, who would wait with it to be let in, to approve a device, to see one taken off. A refusal is an
/// answer too: a device the others refuse waits no longer on the silent one. What it says later it tells as it comes
/// back. `at`: the stations asked (`ws/id`, each ask's): one that did not answer in time is not waited for again, the
/// others' answers taken as they all came, until it answers something (an asleep machine's every read waited
/// OTHERS_MS more, twice for each device approved).
export function answersOf<A, E>(inner: Inner, asks: Effect.Effect<A, E>[], after: (r: Result.Result<A, E>) => number | null, at?: string[]): Effect.Effect<Result.Result<A, E>[]> {
  return Effect.gen(function* () {
    if (asks.length === 0) return [];
    const got: (Result.Result<A, E> | undefined)[] = asks.map(() => undefined);
    const all = Deferred.makeUnsafe<void>();
    const enough = Deferred.makeUnsafe<void>();
    let silent = silentOf.get(inner);
    if (silent === undefined) silentOf.set(inner, (silent = new Set()));
    const quiet = silent;
    // Those not gone silent, all answered: done (all of them, when every one asked is).
    const skipped = asks.map((_, i) => at !== undefined && quiet.has(at[i]!));
    if (skipped.every((s) => s)) skipped.fill(false);
    let left = asks.length;
    let waited = skipped.filter((s) => !s).length;
    asks.forEach((ask, i) =>
      inner.runner.fork(Effect.flatMap(Effect.result(ask), (r) => Effect.gen(function* () {
        got[i] = r;
        if (at !== undefined) quiet.delete(at[i]!);
        if (--left === 0 || (!skipped[i] && --waited === 0)) Deferred.doneUnsafe(all, Effect.void);
        const more = after(r);
        if (more === null) return;
        if (more > 0) yield* Effect.sleep(more); // timer: a deadline
        Deferred.doneUnsafe(enough, Effect.void);
      }))),
    );
    yield* Effect.raceAllFirst([
      Deferred.await(all),
      Deferred.await(enough),
      Effect.sleep(TAKEN_MS), // timer: a deadline
    ]);
    if (at !== undefined) got.forEach((r, i) => r === undefined && quiet.add(at[i]!));
    return got.filter((r): r is Result.Result<A, E> => r !== undefined);
  });
}
/// The stations that did not answer a read in time (answersOf `at`), until they answer one.
const silentOf = new WeakMap<Inner, Set<string>>();

/// Of a station's answer to what is brought: done once one took it, the others waited for OTHERS_MS once one refused.
export const tookOrRefused = (r: Result.Result<unknown, unknown>): number => (r._tag === "Success" ? 0 : OTHERS_MS);

/// What the cloud keeps of a workspace's lock, as held here (the `lock` record of the workspace). `seen`: the devices
/// that asked the cloud for credentials in the last 31 days, as far as the viewer may see them (owners and admins all,
/// others their own; none from a cloud that would not say): when each was last used and what it calls itself now.
/// A device is approved only face to face (views/pair.ts): the cloud's requests of older clients, approved there with
/// a press, are neither read nor answered (2026-11-02 the user: a tap let a device in without its code typed on it).
type Held = { head: Head | null; entries: Entry[]; seen?: J[] | null };

/// What this device keeps of a workspace's lock this run.
type Part = {
  /// Stations that refused this device for the lock, and the lock's head then.
  refused: Map<string, string | null>;
  /// Stations that refused this device though the lock as held names it, and how often this head.
  behind: Map<string, number>;
  /// Of the draft: what is left out; the devices that asked for credentials; each station's answer to GET /lock.
  excluded: Set<string>;
  devices: J[] | null;
  probes: Map<string, "ok" | "old" | "offline" | "other">;
  /// How far each station's own lock goes, as it last said this run (its GET /lock, or its refusal of this device);
  /// null: it keeps none.
  heads: Map<string, Head | null>;
  /// The stations that said they serve the lock to devices (`serves`): what is signed waits on one of them taking it.
  serving: Set<string>;
  /// The base key of this device (the mesh's), once known.
  base: string | null;
};

/// What the signing key of this device is, as loaded (undefined: not loaded yet), per core.
const signers = new WeakMap<Inner, string | null>();
/// The initial read of the kept signing key, while it is still in flight.
const signerLoads = new WeakMap<Inner, Deferred.Deferred<void>>();

/// This device's base key (the mesh's, the same in every workspace), once known, per core.
const bases = new WeakMap<Inner, string>();

/// This device's signing key (`ed25519:<hex>`) and base key, as known now.
export const signerOf = (inner: Inner): string | null => signers.get(inner) ?? null;
export const baseOf = (inner: Inner): string | null => bases.get(inner) ?? null;

/// Await the initial read only while it has not answered yet. Once read (even as absent), no request waits on it.
export function signerLoading(inner: Inner): Effect.Effect<void> | null {
  const pending = signerLoads.get(inner);
  return pending === undefined || signers.has(inner) ? null : Deferred.await(pending);
}

/// What the lock's, the vault's and the pairing's pages read of what this core holds of them beside its records (each
/// read there is made again as it changes, reactive.ts): `lock <ws>`, a workspace's lock as this device sees it; `draft
/// <ws>`, its draft; `vault <ws>`, its vaults; `prompts`, the devices waiting on this one; `self`, this device's own keys.
const seens = new WeakMap<Inner, Marks>();
export function lockSeen(inner: Inner): Marks {
  let seen = seens.get(inner);
  if (!seen) seens.set(inner, (seen = new Marks()));
  return seen;
}

/// This device's signing key as known now (loaded, or made as it is put forward): what shows whether it signs told
/// (the lock's, and the vault's, whose page waits on it).
export function signerKnown(inner: Inner, id: string | null): void {
  signers.set(inner, id);
  lockSeen(inner).touch("self");
  inner.views?.vaultChanged(null);
}

/// The signing keys the lock names as this device's, looked for among what earlier installs kept (`Signer.recover`):
/// each once a run, per core.
const recovering = new WeakMap<Inner, Set<string>>();

/// The lock names `id` as this device's signing key and this one keeps another (or none): an iOS update moved the
/// app's home, which the Keychain items were named by, so it is kept still where an earlier install was. Kept as this
/// one's again, it signs as before, with no other device to approve it.
function recover(inner: Inner, id: string): void {
  const tried = recovering.get(inner) ?? new Set<string>();
  recovering.set(inner, tried);
  if (tried.has(id)) return;
  tried.add(id);
  inner.runner.fork(
    Effect.map(Effect.orElseSucceed(Signer.recover(inner.host, id), () => null), (s) => {
      if (s) signerKnown(inner, s.id);
    }),
  );
}

/// What each workspace's lock was read at (its head's hash and the waiting count the workspace view said), per core.
const readAt = new WeakMap<Inner, Map<string, string>>();

/// What is folded from the entries, unchecked (the stations check them): who and what is in the lock.
export type Folded = { members: Map<string, { email: string; role: string }>; devices: Map<string, J>; stations: Map<string, string>; disabled: boolean; added: Map<string, number>; persons: Map<string, string> };

/// A device of the lock as it stands at `at` (unix seconds): none once its approval ran out (a web page's, after
/// WEB_DEVICE_SECS). The stations let it in nowhere then (station/src/cloud/lock.ts `admit`): it waits and is approved
/// again face to face, as a new one is, rather than being told a station has not heard of it yet.
export function live<D extends { exp?: unknown }>(d: D | undefined, at: number): D | undefined {
  return d !== undefined && (typeof d.exp !== "number" || d.exp > at) ? d : undefined;
}

export function fold(entries: Entry[]): Folded {
  const f: Folded = { members: new Map(), devices: new Map(), stations: new Map(), disabled: false, added: new Map(), persons: new Map() };
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
        f.persons.delete(b.sub);
        break;
      case "person":
        f.persons.set(b.sub, b.person);
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
  inner.workspaces.of(ws).part<Part>("lock", () => ({ refused: new Map(), behind: new Map(), excluded: new Set(), devices: null, probes: new Map(), heads: new Map(), serving: new Set(), base: bases.get(inner) ?? null }));

/// This device's base key known: kept for every workspace.
const knowBase = (inner: Inner, ws: string, base: string) => {
  bases.set(inner, base);
  part(inner, ws).base = base;
};

/// A workspace's lock changed as this device sees it: what shows it, and the prompts of every workspace.
const touch = (inner: Inner, ws: string) => lockSeen(inner).touch(`lock ${ws}`, "prompts");

export const held = (inner: Inner, ws: string): Held | null => {
  const h = inner.data.record("lock", ws);
  return isObject(h) && Array.isArray(h.entries) ? (h as unknown as Held) : null;
};

export const view = (inner: Inner, ws: string): J => inner.data.shared({ topic: "workspace", workspace: ws });

/// A workspace's name as the person knows it: as its view says, else as the account's list does.
export const nameOf = (inner: Inner, ws: string): string =>
  inner.cloudSync?.workspaceName(ws) ?? str(inner.data.mes().flatMap(([, me]) => arr(get(me, "workspaces"))).find((w) => get(w, "id") === ws)?.name) ?? ws;

/// What the workspace view says of the lock: its head (undefined: a cloud from before).
const cloudSays = (v: J): string | undefined => (!isObject(v) || !("lock" in v) ? undefined : `${get(v.lock, "hash") ?? ""}`);

const now = (inner: Inner) => Math.floor(inner.host.nowMs() / 1000);

/// Whether a station's lock, as it said (`theirs`), is the one held here, as far as it goes: not another lock, nor one
/// that went another way after some entry. One ahead of what is held may be (the cloud is read again for it).
function onChain(h: Held | null, theirs: Head): boolean {
  if (!h?.head) return true;
  if (theirs.genesis !== h.head.genesis) return false;
  const e = h.entries.find((x) => x.seq === theirs.seq);
  return e === undefined ? theirs.seq > h.head.seq : entryHash(e) === theirs.hash;
}

/// Whether a station holds the lock as held here (or is behind on it): not when it said it keeps none, or another.
function keeps(inner: Inner, ws: string, station: string): boolean {
  const p = part(inner, ws);
  if (!p.heads.has(station)) return true;
  const theirs = p.heads.get(station)!;
  return theirs !== null && onChain(held(inner, ws), theirs);
}

/// A station keeping another lock than the workspace's (a lock turned on again while it was not reached, an entry it
/// refused kept at the cloud before the cloud checked them): it takes no approval, nor anything else of this one,
/// until it is reset on its own machine and protected again.
function otherLock(inner: Inner, ws: string, station: string): CoreError {
  const name = str(arr(get(view(inner, ws), "stations")).find((s) => s.id === station)?.name) || station.slice(0, 8);
  return new CoreError("lock_other", t("core-misc.lock.otherLock", { name }));
}

/// How far the lock goes on each station of it this device reaches, asked as its lock is shown: one that keeps none or
/// another is not shown protected.
function readStations(inner: Inner, ws: string): Effect.Effect<void> {
  const p = part(inner, ws);
  const h = held(inner, ws);
  const f = fold(h?.entries ?? []);
  const base = p.base ?? bases.get(inner) ?? null;
  if (!h?.head || f.disabled || base === null || !f.devices.has(base)) return Effect.void;
  return Effect.forEach(
    [...f.stations.keys()],
    (id) =>
      Effect.map(Effect.result(inner.stations.requests.call(new StationAddr(ws, id), "GET", "/lock?after=999999999", null, { quiet: true })), (r) => {
        if (r._tag !== "Success") return;
        p.heads.set(id, readHead(get(r.success, "head")));
        touch(inner, ws);
      }),
    { concurrency: 4, discard: true },
  );
}
const daysLeft = (secs: number) => Math.max(0, Math.ceil(secs / 86400));

export function install(inner: Inner): void {
  hooks.enrolled = enrolled;
  hooks.roster = roster;
  hooks.lockRefused = refused;
  hooks.lockWaiting = waiting;
  inner.cloudSync.carry = (ws) => carried(inner, ws);
  inner.cloudSync.carryPerson = (ws) => carriedPerson(inner, ws);
  handlers.lock = (core, call, _progress, _at, ctx) => run(core, call as Of, ctx);
  handlers.lockPrompt = (core, call, _progress, _at, ctx) => runPrompt(core, (call as Extract<Call, { kind: "lockPrompt" }>).name, (call as Extract<Call, { kind: "lockPrompt" }>).params, ctx);
  // The signing key, once (it is the device's).
  const loaded = Deferred.makeUnsafe<void>();
  signerLoads.set(inner, loaded);
  inner.runner.fork(Effect.ensuring(
    Effect.map(Effect.orElseSucceed(Signer.load(inner.host), () => null), (s) => signerKnown(inner, s?.id ?? null)),
    Effect.sync(() => { Deferred.doneUnsafe(loaded, Effect.void); }),
  ));
  // The workspace view says how far the cloud's lock goes and how many wait: read again when that changes.
  inner.data.onChange((topic) => {
    if (topic.topic !== "workspace" || inner.provider.kind !== "stillfail") return;
    const ws = topic.workspace as string;
    // The prompts name the workspaces, and follow the person's role in each.
    lockSeen(inner).touch("prompts");
    const says = cloudSays(view(inner, ws));
    if (says === undefined) return;
    readSaid(inner, ws, says);
  });
  inner.router.owners.push(owner(inner));
  // The stations tell their locks' changes (station/src/mesh/lock-events.ts): the workspace's read of the one that told
  // (and of each as its link opens), the person's own of their stations.
  inner.stations.also.push({
    // (only where there is a lock: one turned on meanwhile is told by the cloud's view as before)
    read: (address) => (inner.provider.kind === "stillfail" && held(inner, ofAddress(address))?.head ? Effect.asVoid(readLockOf(inner, ofAddress(address), [address.slice(ofAddress(address).length + 1)])) : Effect.void),
    event: (address, name, data) => {
      if (inner.provider.kind !== "stillfail") return;
      const ws = ofAddress(address);
      if (name === "lock" && get(data, "workspace") === ws) {
        const station = address.slice(ws.length + 1);
        inner.scheduler.enqueue(address, `lock/${ws}/${station}`, Priority.background, Effect.ignore(readLockOf(inner, ws, [station])));
      } else if (name === "person") {
        const sub = inner.workspaces.owner(ws);
        if (sub !== null) inner.scheduler.enqueue(address, `personal/${sub}`, Priority.background, Effect.ignore(inner.adb.personal().refresh(sub, address)));
      }
    },
    resume: true,
  });
}

/// The lock read as the workspace view says it moved on (`says`, how far): once for each. One the cloud turned away for
/// too many asks is not taken as read: it is read again a little later, else it stayed behind until the lock moved on
/// again (a device put in the lock while its person's devices asked a lot was not let in for minutes).
function readSaid(inner: Inner, ws: string, says: string): void {
  let at = readAt.get(inner);
  if (!at) readAt.set(inner, (at = new Map()));
  if (at.get(ws) === says && held(inner, ws) !== null) return;
  // Held as far already (a station told it first).
  if (says !== "" && held(inner, ws)?.head?.hash === says) return;
  at.set(ws, says);
  const forget = () => Effect.sync(() => void (at.get(ws) === says && at.delete(ws)));
  const again = Effect.andThen(Effect.sleep(LIMITED_WAIT), Effect.sync(() => { const now = cloudSays(view(inner, ws)); if (now !== undefined) readSaid(inner, ws, now); })); // timer: a retry after a failure (429)
  inner.scheduler.enqueue("cloud", `lock/${ws}`, Priority.background, Effect.tapError(read(inner, ws), (e) => Effect.andThen(forget(), e.code === "rate_limited" ? Effect.sync(() => void inner.runner.fork(again)) : Effect.void)));
  pairs.reading(inner, ws);
}

/// The lock and the devices that came, read from the workspace's stations and held (from the cloud only when none of
/// them answers: older ones, offline, or refusing this device; the root AGENTS.md, The cloud is the account system); a
/// lock that moved on lets the stations that refused this device be tried again.
export function read(inner: Inner, ws: string): Effect.Effect<void, CoreError> {
  // What changed while it read is read again: an ask made meanwhile under the same key was folded into this one.
  return Effect.gen(function* () {
    if (inner.provider.kind === "stillfail") {
      const said = { refused: false };
      if (yield* readLockOf(inner, ws, lockStations(inner, ws), said)) return;
      // Refused by the stations it reached, a lock held: each refusal tells the lock's last entries (refusedFor), so
      // it is not read of the cloud (each of a person's refused devices did, as each entry was signed, and used up the
      // account's budget: enrolling a station was turned away). They are asked again instead, which tells it again.
      if (said.refused && held(inner, ws)?.head) {
        refusedAgain(inner, ws);
        return;
      }
    }
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
    const seen = head === null ? null : yield* Effect.orElseSucceed(Effect.map(cloud("/devices"), (r) => arr(get(r, "devices"))), () => was?.seen ?? null);
    yield* hold(inner, ws, sub, was, head, entries, seen);
  });
}

/// The stations a lock is read of: those it names, then the workspace's others.
function lockStations(inner: Inner, ws: string): string[] {
  const h = held(inner, ws);
  const f = fold(h?.entries ?? []);
  const named = h?.head && !f.disabled ? [...f.stations.keys()] : [];
  const all = arr(get(view(inner, ws), "stations")).map((s) => s?.id).filter((id): id is string => typeof id === "string");
  return [...new Set([...named, ...all])];
}

/// The lock read of `stations` (each one's GET /lock, and the devices that came to it): held when one of them answered,
/// as the longest chain that goes on from the one held (one that keeps another lock or none says so, and is not taken);
/// false when none did (nothing held then; `said.refused`: one refused this device for the lock).
function readLockOf(inner: Inner, ws: string, stations: string[], said?: { refused: boolean }): Effect.Effect<boolean, CoreError> {
  return Effect.gen(function* () {
    const sub = inner.workspaces.owner(ws);
    if (sub === null || stations.length === 0) return false;
    const p = part(inner, ws);
    const was = held(inner, ws);
    const off = was?.head ? fold(was.entries).disabled : true;
    const ask = (id: string, path: string) => Effect.result(inner.stations.requests.call(new StationAddr(ws, id), "GET", path, null, { quiet: true }));
    const answers = yield* answersOf(
      inner,
      stations.map((id) =>
        Effect.gen(function* () {
          const r = yield* ask(id, `/lock?after=${was?.head && !off ? was.head.seq : -1}`);
          if (r._tag === "Failure" && r.failure.code === "lock_unconfirmed" && said) said.refused = true;
          // One from before this was read of serves none of it (its devices read the cloud).
          if (r._tag === "Success" && arr(get(r.success, "serves")).includes("told")) p.serving.add(id);
          else p.serving.delete(id);
          if (r._tag !== "Success" || !p.serving.has(id)) return null;
          const head = readHead(get(r.success, "head"));
          p.heads.set(id, head);
          const more = arr(get(r.success, "entries")) as Entry[];
          let entries: Entry[] | null = null;
          if (head === null) entries = [];
          else if (was?.head && !off && head.genesis === was.head.genesis) entries = head.seq <= was.head.seq ? null : [...was.entries, ...more.filter((e) => e.seq > was.head!.seq)];
          else if (more[0]?.seq === 0) entries = more;
          else {
            const all = yield* ask(id, "/lock");
            entries = all._tag === "Success" ? (arr(get(all.success, "entries")) as Entry[]) : null;
          }
          const devices = yield* ask(id, "/lock/devices");
          return { head, entries, seen: devices._tag === "Success" ? arr(get(devices.success, "devices")) : [] };
        }),
      ),
      () => OTHERS_MS,
      stations.map((id) => `${ws}/${id}`),
    );
    const served = answers.flatMap((r) => (r._tag === "Success" && r.success !== null ? [r.success] : []));
    if (served.length === 0) return false;
    // The longest chain that goes on from the one held (all of them agree on it as far as they go, or it is another
    // lock); none longer, what is held stays.
    let head = was?.head ?? null;
    let entries = was?.entries ?? [];
    for (const a of served) {
      if (a.head === null || a.entries === null || a.entries.length !== a.head.seq + 1) continue;
      if (head !== null && !off && (a.head.genesis !== head.genesis || a.head.seq <= head.seq || entryHash(a.entries[head.seq]!) !== head.hash)) continue;
      if (head !== null && off && a.head.genesis === head.genesis) continue;
      head = a.head;
      entries = a.entries;
    }
    // None keeps a lock (and none was held, or every one says so): none.
    if (served.every((a) => a.head === null) && (was?.head == null || served.length === stations.length)) {
      head = null;
      entries = [];
    }
    yield* hold(inner, ws, sub, was, head, entries, mergeSeen(served.map((a) => a.seen)));
    return true;
  });
}

/// The devices each station said came to it, as one list: each device once, as it was last seen.
function mergeSeen(lists: J[][]): J[] {
  const by = new Map<string, J>();
  for (const r of lists.flat()) {
    const k = `${r?.sub}\0${r?.device}`;
    const had = by.get(k);
    if (had === undefined) by.set(k, r);
    else by.set(k, { ...had, ...r, base: r.base ?? had.base, kind: r.kind ?? had.kind, label: r.label ?? had.label, first_seen: Math.min(had.first_seen ?? Infinity, r.first_seen ?? Infinity), last_seen: Math.max(had.last_seen ?? 0, r.last_seen ?? 0) });
  }
  return [...by.values()];
}

/// The lock as read (of the cloud or the stations) held, and what follows from it.
function hold(inner: Inner, ws: string, sub: string, was: Held | null, head: Head | null, entries: Entry[], seen: J[] | null): Effect.Effect<void> {
  return Effect.gen(function* () {
    if (head !== null && inner.provider.kind === "stillfail") yield* Effect.ignore(new Lock(inner, ws, sub, null).base());
    inner.data.put("lock", ws, { head, entries: head === null ? [] : entries, ...(seen ? { seen } : {}) });
    // checked as it comes, in a turn of its own (views/vault.ts vaultCome)
    inner.runner.fork(laterSleep(0).pipe(Effect.andThen(Effect.sync(() => vaultCome(inner, ws)))));
    if ((was?.head?.hash ?? null) !== (head?.hash ?? null)) moved(inner, ws);
    inner.runner.fork(bindPerson(inner, ws));
    inner.runner.fork(keepToPerson(inner, ws));
    // The vault's too: whether it is locked, this device confirmed in it, whose vaults are trusted (views/vault.ts).
    lockSeen(inner).touch(`lock ${ws}`, `draft ${ws}`, "prompts");
    inner.views?.vaultChanged(ws);
    // This device not in the lock: it waits, and asks to be approved only by hand (`lock.pair`, its waiting page):
    // the person who will type the code is the one who asks (2026-10-19).
  });
}

/// The lock moved on: the stations that refused this device before are tried again now.
function moved(inner: Inner, ws: string): void {
  const p = part(inner, ws);
  p.behind.clear();
  refusedAgain(inner, ws);
  pairs.moved(inner, ws);
}

/// The stations of the workspace that refused this device tried again now: the lock moved on, or the person's own lock
/// did (this device put on it, which the stations of a lock bound to it go by).
export function refusedAgain(inner: Inner, ws: string): void {
  const p = inner.workspaces.get(ws)?.own.get("lock") as Part | undefined;
  if (!p) return;
  for (const station of [...p.refused.keys()]) {
    p.refused.delete(station);
    inner.stations?.cameOnline(`${ws}/${station}`);
  }
}

/// A station refused this device for the lock: noted, not asked again until the lock moves on. What the refusal says
/// then: which workspace, and where to approve it.
function refused(inner: Inner, ws: string, station: string, theirs: unknown, told?: { person?: unknown; entries?: unknown }): CoreError | null {
  if (inner.provider.kind !== "stillfail") return null;
  const p = part(inner, ws);
  heardRefused(inner, ws, told?.person);
  heardTail(inner, ws, told?.entries);
  const h = held(inner, ws);
  const base = p.base ?? bases.get(inner) ?? null;
  const f = fold(h?.entries ?? []);
  // Its own lock is another: no approval in this one lets this device in there, however often it is tried.
  const said = readHead(theirs);
  if (said !== null) p.heads.set(station, said);
  if (said !== null && !onChain(h, said)) {
    p.refused.set(station, h?.head?.hash ?? null);
    touch(inner, ws);
    return otherLock(inner, ws, station);
  }
  // In the lock as this device holds it: the station has not heard of it yet (from the cloud, or the device that
  // signed it), and is tried again shortly rather than once the lock moves on, which it may not again for long.
  // A few times, each a little later (each try asks the station anew); after that, as any station not reached.
  if (base !== null && h?.head != null && !f.disabled && live(f.devices.get(base), now(inner)) !== undefined && !offOwnLock(inner, ws)) {
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
  return keeps(inner, ws, station) ? unconfirmed(inner, ws) : otherLock(inner, ws, station);
}

/// A station of the workspace refused this device for its lock: which workspace, and where it is approved (another
/// trusted device of the person's there), with the code compared there.
function unconfirmed(inner: Inner, ws: string): CoreError {
  const base = part(inner, ws).base ?? bases.get(inner) ?? null;
  const name = nameOf(inner, ws);
  // Its person bound a lock of their own here, which this device is not on: the stations let their app devices in on
  // that alone, so no approval in this one helps; it is put on their own lock, face to face.
  if (offOwnLock(inner, ws)) return new CoreError("lock_unconfirmed", t("core-misc.lock.offOwnLock", { name }));
  return new CoreError("lock_unconfirmed", base ? t("core-misc.lock.unconfirmed", { name, code: shortCode(base) }) : t("core-misc.lock.unconfirmedNoCode", { name }));
}

/// What this device brings a station of the workspace as it connects (its hello's `lock.entries`): the entries from the
/// one that put it in the lock on (from the one that made its person a member, lately too: a station takes no device of
/// someone it has not heard of), as held here, while that was lately (RECENT_SECS): a station that has not heard of
/// them yet takes them and lets it in ( 新设备), the approval coming with the device that needs
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
  const sub = get(h.entries[at]!.body, "sub");
  for (let i = at - 1; i >= 0 && now(inner) - h.entries[i]!.at <= RECENT_SECS; i--) {
    if (h.entries[i]!.kind === "member" && get(h.entries[i]!.body, "sub") === sub) {
      at = i;
      break;
    }
  }
  const tail = h.entries.slice(at);
  return JSON.stringify(tail).length <= CARRY_BYTES ? tail : null;
}

/// Whether this device is let in here by its person's own lock: it is on the one its member bound in this workspace's.
export function onBoundPerson(inner: Inner, ws: string): boolean {
  const sub = inner.workspaces.owner(ws);
  const h = held(inner, ws);
  if (sub === null || !h?.head) return false;
  const personal = inner.adb.personal();
  return personal.standing(sub) === "member" && personal.root(sub) === fold(h.entries).persons.get(sub);
}

/// Whether this app device's person bound a lock of their own in the workspace's, and this device is not on it.
function offOwnLock(inner: Inner, ws: string): boolean {
  const sub = inner.workspaces.owner(ws);
  const h = held(inner, ws);
  if (sub === null || !h?.head || !inner.host.appKeys) return false;
  return fold(h.entries).persons.has(sub) && !onBoundPerson(inner, ws);
}

/// What a hello brings of the person's own lock: its chain, wherever its member bound it here, this device in the
/// workspace's lock as well or not: a station that goes by the person's own lock alone for them lets it in on that.
function carriedPerson(inner: Inner, ws: string): Entry[] | null {
  const sub = inner.workspaces.owner(ws);
  if (sub === null || !onBoundPerson(inner, ws)) return null;
  const chain = inner.adb.personal().entries(sub);
  return JSON.stringify(chain).length <= CARRY_BYTES ? chain : null;
}

/// This device, one of the workspace's lock that signs for its person, says which lock of their own is theirs, once
/// every station of the lock has said it knows such an entry: one that does not would refuse it, and every entry after.
/// Nothing here asks the person: it writes with the lock's own key. Tried again whenever the lock is read or the person's
/// own lock is: no timer of its own.
const binding = new WeakMap<Inner, Set<string>>();
export function bindPerson(inner: Inner, ws: string): Effect.Effect<void> {
  return Effect.gen(function* () {
    const sub = inner.workspaces.owner(ws);
    const h = held(inner, ws);
    const signer = signerOf(inner);
    if (sub === null || !h?.head || signer === null || !inner.host.appKeys) return;
    const personal = inner.adb.personal();
    const root = personal.root(sub);
    const f = fold(h.entries);
    if (root === null || personal.standing(sub) !== "member" || f.disabled || f.persons.get(sub) === root) return;
    const base = part(inner, ws).base ?? bases.get(inner) ?? null;
    const me = base === null ? undefined : live(f.devices.get(base), now(inner));
    if (me === undefined || me.sub !== sub || me.sign_key !== signer) return;
    // Not while an app device of theirs here is off their own lock: bound, the stations would let it in no more (the
    // user, 2026-11-09: a Mac left off a lock opened for debugging a phone was shut out of every station).
    const on = new Set([...(personal.chain(sub)?.devices.values() ?? [])].map((d) => d.id));
    for (const d of f.devices.values()) if (d.sub === sub && d.kind === "app" && !on.has(d.id) && live(d, now(inner)) !== undefined) return;
    // Once at a time.
    let tried = binding.get(inner);
    if (tried === undefined) binding.set(inner, (tried = new Set()));
    const at = `${ws}/${h.head.hash}/${root}`;
    if (tried.has(at)) return;
    tried.add(at);
    yield* Effect.ensuring(
      Effect.gen(function* () {
        for (const id of f.stations.keys()) {
          const r = yield* Effect.result(inner.stations.requests.call(new StationAddr(ws, id), "GET", "/lock?after=999999999", null, { quiet: true }));
          if (r._tag !== "Success" || !arr(get(r.success, "takes")).includes("person")) return;
        }
        yield* new Lock(inner, ws, sub, null).append("person", { sub, person: root });
      }),
      Effect.sync(() => tried.delete(at)),
    );
  }).pipe(Effect.ignore);
}

/// The base keys a person's own lock names: on it now, and ever (taken off since too).
function personIds(chain: readonly Entry[], on: Iterable<{ id: string }>): { on: Set<string>; ever: Set<string> } {
  const ever = new Set<string>();
  for (const e of chain) {
    const id = e.kind === "genesis" ? get(get(e.body, "device"), "id") : e.kind === "device" ? get(e.body, "id") : null;
    if (typeof id === "string") ever.add(id);
  }
  return { on: new Set([...on].map((d) => d.id)), ever };
}

/// This device of the workspace's lock signs for its person there, and is on the person's own lock they bound there:
/// the person, and the lock's head; none otherwise.
function signsBound(inner: Inner, ws: string): { sub: string; base: string; h: Held } | null {
  const sub = inner.workspaces.owner(ws);
  const h = held(inner, ws);
  const signer = signerOf(inner);
  if (sub === null || !h?.head || signer === null || !inner.host.appKeys || !onBoundPerson(inner, ws)) return null;
  const base = part(inner, ws).base ?? bases.get(inner) ?? null;
  const me = base === null ? undefined : live(fold(h.entries).devices.get(base), now(inner));
  return base !== null && me !== undefined && me.sub === sub && me.sign_key === signer ? { sub, base, h } : null;
}

/// A device just put on its person's own lock here (face to face, views/pair.ts `approve`): put in each workspace's
/// lock where the person bound it and this device signs for them, with the key it signs with, so it signs there and its
/// vault's box is taken as theirs.
export function putOnBound(inner: Inner, sub: string, device: { id: string; label: string; signKey: string | null }): Effect.Effect<void> {
  return Effect.gen(function* () {
    if (device.signKey === null) return;
    for (const [ws, owner] of inner.workspaces.owned()) {
      const at = owner === sub ? signsBound(inner, ws) : null;
      // (one there already that signs with this key: nothing; one there that does not, put in as the lock was turned
      // on, before it signed: put in again with it)
      if (at === null || live(fold(at.h.entries).devices.get(device.id), now(inner))?.sign_key === device.signKey) continue;
      yield* Effect.ignore(new Lock(inner, ws, sub, null).append("device", { id: device.id, sub, kind: "app", label: device.label, sign_key: device.signKey }), { log: "Unhandled", message: "put on a bound lock" });
      yield* Effect.ignore(read(inner, ws), { log: "Unhandled", message: "bound lock read" });
    }
  });
}

/// The person's app devices in the workspace's lock kept to the ones on their own lock, where they bound it: one taken
/// off their lock, or there from before the binding and never put on it, is taken out of the workspace's lock, so it
/// neither signs there nor has its vault's box taken as theirs (a web page holds no key of their lock: kept); one on
/// their lock that this one lacks, or holds as not signing, is put in with the key it signs with in another workspace
/// of theirs bound to it (`signKeysElsewhere`), so it signs here too. Their lock is read first, so a device just put on
/// it is not taken for gone. Done by a device on it that signs for them; tried as bindPerson is, no timer of its own.
const keeping = new WeakMap<Inner, Set<string>>();
export function keepToPerson(inner: Inner, ws: string): Effect.Effect<void> {
  return Effect.gen(function* () {
    const before = signsBound(inner, ws);
    if (before === null) return;
    let tried = keeping.get(inner);
    if (tried === undefined) keeping.set(inner, (tried = new Set()));
    // (once for each head of the two locks: reading the person's lock tells of it, which would ask again)
    const key = `${ws}/${before.h.head!.hash}/${inner.adb.personal().entries(before.sub).length}`;
    if (tried.has(key)) return;
    tried.add(key);
    yield* Effect.tapError(
      Effect.gen(function* () {
        const personal = inner.adb.personal();
        yield* personal.refresh(before.sub);
        const at = signsBound(inner, ws);
        const chain = personal.chain(before.sub);
        if (at === null || chain === null || personal.standing(at.sub) !== "member") return;
        const { on, ever } = personIds(personal.entries(at.sub), chain.devices.values());
        const entries = at.h.entries;
        const lastAt = (f: (e: Entry) => boolean) => {
          for (let i = entries.length - 1; i >= 0; i--) if (f(entries[i]!)) return i;
          return -1;
        };
        const bound = lastAt((e) => e.kind === "person" && get(e.body, "sub") === at.sub);
        const gone = [...fold(entries).devices.values()].filter((d) => {
          if (d.sub !== at.sub || d.kind !== "app" || d.id === at.base || on.has(d.id)) return false;
          return ever.has(d.id) || lastAt((e) => e.kind === "device" && get(e.body, "id") === d.id) < bound;
        });
        for (const d of gone) yield* new Lock(inner, ws, at.sub, null).append("device.remove", { id: d.id });
        // (a second workspace bound to the lock: its devices there as the lock was turned on signed nothing, nor did a
        // device one of those approved since; the locks' end to end, round 9, 2026-11-10)
        const inLock = fold(entries).devices;
        let put = 0;
        for (const [id, d] of signKeysElsewhere(inner, ws, at.sub)) {
          if (!on.has(id) || live(inLock.get(id), now(inner))?.sign_key === d.sign_key) continue;
          yield* new Lock(inner, ws, at.sub, null).append("device", { id, sub: at.sub, kind: "app", label: d.label, sign_key: d.sign_key });
          put++;
        }
        if (gone.length + put > 0) yield* read(inner, ws);
      }),
      () => Effect.sync(() => tried.delete(key)),
    );
  }).pipe(Effect.ignore);
}

/// The keys the person's app devices sign with in the locks of their other workspaces bound to their own lock, as those
/// locks (checked here) took them, by device: theirs and signing for themselves, put in face to face or by one of theirs.
function signKeysElsewhere(inner: Inner, ws: string, sub: string): Map<string, { sign_key: string; label: string }> {
  const keys = new Map<string, { sign_key: string; label: string }>();
  const at = now(inner);
  for (const [other, owner] of inner.workspaces.owned()) {
    const h = held(inner, other);
    if (other === ws || owner !== sub || !h?.head || !fold(h.entries).persons.has(sub)) continue;
    let lock: Checked;
    try {
      lock = checkLock(h.entries, at);
    } catch {
      continue;
    }
    const labels = fold(h.entries).devices;
    for (const d of lock.devices.values()) {
      if (d.sub !== sub || d.kind !== "app" || !d.own || typeof d.sign_key !== "string" || live(d, at) === undefined) continue;
      keys.set(d.id, { sign_key: d.sign_key, label: str(get(labels.get(d.id), "label")) ?? "" });
    }
  }
  return keys;
}

/// A person's own lock moved on (a device taken off): each station where it is bound told as it stands.
export function tellStations(inner: Inner, sub: string, chain: Entry[]): void {
  for (const [ws, owner] of inner.workspaces.owned()) {
    const h = held(inner, ws);
    if (owner !== sub || !h?.head) continue;
    const f = fold(h.entries);
    if (!f.persons.has(sub)) continue;
    for (const id of f.stations.keys())
      inner.runner.fork(Effect.ignore(inner.stations.requests.call(new StationAddr(ws, id), "POST", "/lock", { person: chain }, { quiet: true }), { log: "Unhandled", message: "personal lock told" }));
  }
}

/// The chains of each person's own lock the stations that refused this device told (`person`), the latest: what a
/// device not let in anywhere knows of its person's lock with no cloud (who may let it in face to face).
const refusedChains = new WeakMap<Inner, Map<string, Entry[][]>>();
function heardRefused(inner: Inner, ws: string, person: unknown): void {
  const sub = inner.workspaces.owner(ws);
  if (sub === null || !Array.isArray(person)) return;
  const chains = person.map((c) => arr(get(c, "entries")) as Entry[]).filter((c) => c.length > 0);
  let m = refusedChains.get(inner);
  if (!m) refusedChains.set(inner, (m = new Map()));
  m.set(sub, chains);
  inner.runner.fork(Effect.ignore(inner.adb.personal().heardFrom(sub, chains), { log: "Unhandled", message: "personal lock heard of a refusal" }));
}

/// The last entries of the lock a station refusing this device told: held, as they go on from the lock held here (the
/// station took each), so a device taken out hears so with no cloud to read it of.
function heardTail(inner: Inner, ws: string, raw: unknown): void {
  const sub = inner.workspaces.owner(ws);
  const was = held(inner, ws);
  const tail = arr(raw) as Entry[];
  if (sub === null || !was?.head || tail.length === 0) return;
  const first = tail[0]!.seq;
  if (!Number.isSafeInteger(first) || first < 0 || first > was.head.seq + 1) return;
  for (let i = 0; i < tail.length; i++) {
    const prev = i === 0 ? (first === 0 ? undefined : was.entries[first - 1]) : tail[i - 1];
    if (tail[i]!.seq !== first + i || (prev !== undefined && tail[i]!.prev !== entryHash(prev))) return;
  }
  const entries = [...was.entries.slice(0, first), ...tail];
  if (entries.length <= was.entries.length || entryHash(entries[0]!) !== was.head.genesis) return;
  const last = entries[entries.length - 1]!;
  inner.runner.fork(hold(inner, ws, sub, was, { seq: last.seq, hash: entryHash(last), genesis: was.head.genesis }, entries, was.seen ?? null));
}

/// The stations of `sub`'s workspaces here, each once (one in two of them is asked in the first).
function personStations(inner: Inner, sub: string): StationAddr[] {
  const out = new Map<string, StationAddr>();
  for (const [ws, owner] of inner.workspaces.owned()) {
    if (owner !== sub) continue;
    for (const s of arr(get(view(inner, ws), "stations"))) if (typeof s?.id === "string" && !out.has(s.id)) out.set(s.id, new StationAddr(ws, s.id));
  }
  return [...out.values()];
}

/// A person's own lock as their stations keep it (personal-lock.ts `stations`), not the cloud: read of each station of
/// their workspaces this device reaches, and brought to each.
export function personalStations(inner: Inner): NonNullable<PersonalEnv["stations"]> {
  return {
    read: (sub, only) => {
      const asked = personStations(inner, sub).filter((at) => only === undefined || at.toString() === only);
      return Effect.map(
        answersOf(inner, asked.map((at) => inner.stations.requests.call(at, "GET", "/lock/person", null, { quiet: true })), () => OTHERS_MS, asked.map(String)),
        (answers) => {
          const ok = answers.filter((r) => r._tag === "Success");
          // Refused by them all (this device not let in yet): what their refusals told of it, not the cloud's.
          const told = refusedChains.get(inner)?.get(sub);
          if (ok.length === 0) return told !== undefined && answers.some((r) => r._tag === "Failure" && r.failure.code === "lock_unconfirmed") ? told : null;
          return ok.flatMap((r) => arr(get(r.success, "chains")).map((c) => arr(get(c, "entries")) as Entry[]));
        },
      );
    },
    bring: (sub, chain) => {
      const asked = personStations(inner, sub);
      return Effect.flatMap(
        // (done once one took it: the others are brought it all the same, and keep each other level)
        answersOf(inner, asked.map((at) => inner.stations.requests.call(at, "POST", "/lock/person", { chain }, { quiet: true })), tookOrRefused, asked.map(String)),
        (answers) => {
          const took = answers.filter((r) => r._tag === "Success").length;
          if (took > 0) return Effect.succeed(took);
          // Refused where it was heard (another device's entry got there first): said so, as the cloud's refusal was.
          const refused = answers.find((r) => r._tag === "Failure" && r.failure.status === 409);
          return refused !== undefined && refused._tag === "Failure" ? Effect.fail(new CoreError("lock_refused", refused.failure.message, 409)) : Effect.succeed(null);
        },
      );
    },
  };
}

/// What a control plane that keeps no lock shows.
const NONE = { available: false, locked: false, notice: false, role: "member", manages: false, owner: false, canSign: false, signs: false, signers: 0, members: [], stations: [], protected: 0, renew: [], attention: 0 };
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
            lockSeen(inner).touch("self");
          }),
          { log: "Unhandled", message: "mesh brought up" },
        ),
      );
      // The prompts are of what each workspace's lock holds, read as their workspaces change.
      if (t.topic === "lockPrompts") return;
      if (t.topic === "lockDraft") inner.scheduler.enqueue("cloud", `lock/${ws}/draft`, Priority.shown, draft(inner, ws));
      // Shown: read again now, what is held showing meanwhile; then what its stations keep.
      else inner.scheduler.enqueue("cloud", `lock/${ws}`, Priority.shown, Effect.tap(read(inner, ws), () => Effect.sync(() => inner.runner.fork(readStations(inner, ws)))));
    },
    compute: (t: Topic) => {
      const ws = typeof t.workspace === "string" ? t.workspace : "";
      const seen = lockSeen(inner);
      seen.read("self");
      if (t.topic === "lockPrompts") seen.read("prompts");
      else seen.read(`lock ${ws}`);
      if (t.topic === "lockDraft") seen.read(`draft ${ws}`);
      if (inner.provider.kind !== "stillfail") return { ok: t.topic === "lock" ? NONE : t.topic === "lockPrompts" ? NO_PROMPTS : NO_DRAFT };
      return { ok: t.topic === "lock" ? lockView(inner, ws) : t.topic === "lockPrompts" ? promptsView(inner) : draftView(inner, ws) };
    },
  };
}

/// The person asked by the system before what they should mean (host.ts `secureAsk`): fails with the host's code
/// (`user_cancelled`, …) as the call's (else `code`); a phone with no screen lock has nothing to ask with, and goes on.
export function askPerson(inner: Inner, reason: string, code = "lock_refused"): Effect.Effect<void, CoreError> {
  const ask = inner.host.secureAsk;
  if (!ask) return Effect.void;
  return Effect.catch(ask.call(inner.host, reason), (e) =>
    e.message === "no_device_lock" ? Effect.void : Effect.fail(CoreError.refused(e, code)));
}

/// A device's name as people know it, in a line of its own: which machine it is, then which app (左子健的 MacBook Air ·
/// still.fail 桌面版); a name of its own as it is; else what kind of client it is (an older client's, said so).
export function deviceText(d: { kind: string; label: string; older?: boolean }): string {
  const { app } = prefs.deviceParts(d.label);
  return app === null ? machineText(d) : `${machineText(d)} · ${app}`;
}

/// Which machine a device is, where its app is said beside it (a member's devices, grouped by app): the machine its
/// name says, else its name, else what kind of client it is.
function machineText(d: { kind: string; label: string; older?: boolean }): string {
  const { app, machine } = prefs.deviceParts(d.label);
  if (app !== null) return machine || t("web-pages.security.unnamed");
  if (d.older) return d.label || t("web-pages.security.olderClient");
  return d.label || (d.kind === "web" ? t("web-pages.security.webDevice") : t("web-pages.security.appDevice"));
}

/// When a device was last used, `secs` ago, as near as its credentials tell (a day).
function usedText(secs: number): string {
  const days = Math.floor(secs / 86400);
  return days <= 0 ? t("web-pages.security.usedLately") : t("web-pages.security.usedDaysAgo", { n: days });
}

/// A line's first letter capital (a line of the device's said parts, any may lead it: "This device · trusted").
const upperFirst = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/// A member's role as the security pages name it.
export function roleText(role: string): string {
  const key = ({ owner: "web-pages.roles.owner", admin: "web-pages.roles.admin", member: "web-pages.roles.member", viewer: "web-pages.security.viewer" } as Record<string, string>)[role];
  return key ? t(key) : role;
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
  const at = now(inner);
  const signer = signers.get(inner) ?? null;
  const people = new Map<string, J>(arr(get(v, "members")).map((m) => [m.sub, m]));
  const mine = base ? (live(f.devices.get(base), at) ?? (onBoundPerson(inner, ws) ? { id: base, sub: inner.workspaces.owner(ws), kind: "app" } : undefined)) : undefined;
  const role = str(get(v, "role")) ?? "member";
  const manages = role === "owner" || role === "admin";
  const signs = mine !== undefined && typeof mine.sign_key === "string" && mine.sign_key === signer;
  // What each device last told the cloud of itself (the latest of its endpoints'): by its base key, or an older
  // client's by the endpoints it used.
  const seen = h?.seen ?? null;
  const told = (d: J): J | undefined => {
    let latest: J | undefined;
    for (const r of seen ?? []) {
      if (r.base !== d.id && !(Array.isArray(d.endpoints) && d.endpoints.includes(r.device))) continue;
      if (latest === undefined || (r.last_seen ?? 0) > (latest.last_seen ?? 0)) latest = r;
    }
    return latest;
  };
  const device = (d: J) => {
    const kind = d.kind === "web" ? "web" : "app";
    const older = Array.isArray(d.endpoints);
    const trusted = typeof d.sign_key === "string";
    const mine = d.id === base;
    const left = typeof d.exp === "number" ? daysLeft(d.exp - at) : null;
    // A device of the viewer's own added lately, shown on their other devices.
    const recent = d.sub === sub && d.id !== base && at - (f.added.get(d.id) ?? 0) < RECENT_SECS;
    // Which one it is, as people tell their devices apart: what it calls itself now (the machine, in its language
    // now; else as when it was approved), and when it was last used: it asks the cloud for a credential at most once a
    // day, on its way to a station; one the cloud would say of and has not in 31 days, not since.
    const said = told(d);
    const lastSeen = typeof said?.last_seen === "number" ? said.last_seen : null;
    const label = str(said?.label) || d.label || "";
    const used = mine ? t("web-pages.security.thisDevice")
      : lastSeen !== null ? usedText(at - lastSeen)
      : seen !== null && (manages || d.sub === sub) ? t("web-pages.security.unused")
      : null;
    return {
      id: d.id, kind, label, signs: trusted, older, mine, daysLeft: left,
      renewSoon: typeof d.exp === "number" && d.exp - at < RENEW_SECS,
      recent, lastSeen, usedText: used,
      // taken out of the lock by this device, where it signs and may (owners and admins any but this one, members
      // their own others)
      removable: signs && !mine && (manages || d.sub === sub),
      // which machine (its group says the app), and both in a line (asked about it)
      nameText: machineText({ kind, label, older }),
      fullText: deviceText({ kind, label, older }),
      // the rest in a line: this device or when it was last used, whether it signs, the days a web page has left, new
      // (whether it is a web page or an app its mark says, and its name)
      metaText: upperFirst([
        used,
        trusted ? t("web-pages.security.signs") : null,
        left !== null ? t("web-pages.security.daysLeft", { n: left }) : null,
        recent ? t("web-pages.security.recent") : null,
      ].filter((x) => x !== null).join(" · ")),
    };
  };
  // this device first, then the most lately used
  const byUse = (a: J, b: J) => Number(b.mine) - Number(a.mine) || (b.lastSeen ?? -1) - (a.lastSeen ?? -1);
  // A member's devices by the app each is (still.fail 桌面版, still.fail 网页版, those whose name says none together),
  // the group with this device first, then the one used most lately; in each the same.
  const byApp = (devices: J[]) => {
    const groups = new Map<string, { appText: string; devices: J[] }>();
    for (const d of devices.sort(byUse)) {
      const { group, app } = prefs.deviceParts(d.label);
      const key = group ?? "";
      const g = groups.get(key) ?? { appText: app ?? t("web-pages.security.otherApps"), devices: [] };
      g.devices.push(d);
      groups.set(key, g);
    }
    return [...groups.values()];
  };
  const stations = arr(get(v, "stations")).map((s) => ({
    id: s.id, name: s.name, version: s.version ?? null, online: s.online !== false, protected: f.stations.has(s.id) && keeps(inner, ws, s.id),
  }));
  const members = [...f.members].map(([s, m]) => ({
    sub: s, email: m.email, name: str(get(people.get(s), "name")) ?? "", role: m.role, you: s === sub,
    nameText: str(get(people.get(s), "name")) || m.email, roleText: roleText(m.role),
    groups: byApp([...f.devices.values()].filter((d) => d.sub === s).map(device)),
  }));
  const renew = members.flatMap((m) => (m.you ? m.groups.flatMap((g) => g.devices).filter((d) => d.renewSoon) : []));
  const dismissed = get(get(inner.data.shared({ topic: "prefs" }), "lockNotice"), ws) === true;
  // An app in the lock that does not sign with its key (let in before it kept one, as the devices there when the lock
  // was turned on were; or its key since lost): it may be made one that signs, approved face to face as a new one is.
  const unsigned = locked && mine !== undefined && mine.kind === "app" && inner.host.appKeys === true && signers.has(inner) && !signs;
  if (unsigned && typeof mine.sign_key === "string") recover(inner, mine.sign_key);
  const pair = locked && (mine === undefined || unsigned) ? pairs.mine(inner, ws) : null;
  // The devices its try dials here, as people know them (which machine, its app and when it was last used), the most
  // lately used first, those showing a code before them: the person opens still.fail on one of those (2026-11-05:
  // "到底是哪个设备会弹出来呀？", a web page of theirs, or an app not approved, shows nothing). Each a row of the
  // page's list (the user, #4213: joined into the words over them, a narrow page broke a name in two).
  if (pair !== null && Array.isArray(pair.approvers)) {
    pair.approvers = pair.approvers
      .map((a: J) => {
        const d = f.devices.get(a.id);
        const v = d === undefined ? null : device(d);
        const { group, app } = prefs.deviceParts(v?.label ?? "");
        // (its app without the brand, the group's after its first word: the words over the card say still.fail already;
        // the user, 2026-11-10: 字太多了不好读)
        const words = group === null || app === null ? null : app.slice(group.length - group.indexOf(" ") - 1).trim() || null;
        const showing = a.showing === true;
        return {
          id: a.id, showing,
          kind: group !== null && /^(android|ios) /.test(group) ? "phone" : "computer",
          nameText: v?.nameText ?? t("web-pages.security.appDevice"),
          noteText: [words, showing ? t("core-misc.lock.pairShowing") : (v?.usedText ?? null)].filter((x) => x !== null).join(" · "),
          lastSeen: v?.lastSeen ?? null,
        };
      })
      .sort((a: J, b: J) => Number(b.showing) - Number(a.showing) || (b.lastSeen ?? -1) - (a.lastSeen ?? -1));
    if (pair.approvers.length > 0) pair.approversText = t("core-misc.lock.pairApprovers", { n: pair.approvers.length });
  }
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
      confirmed: mine !== undefined, daysLeft: typeof mine?.exp === "number" ? daysLeft(mine.exp - at) : null,
      // Not in the lock: it waits to be confirmed, and asks by hand.
      waiting: locked && base !== null && mine === undefined,
      ...(unsigned ? { unsigned: true } : {}),
      // Its try to be approved face to face (views/pair.ts), once it began.
      pair,
    },
    signers: [...f.devices.values()].filter((d) => typeof d.sign_key === "string").length,
    members,
    stations,
    protected: stations.filter((s) => s.protected).length,
    // What waits on the viewer: their own web devices running out.
    renew,
    attention: renew.length,
  };
}

/// The `lockPrompts` topic: the new devices showing a code of this one's to type (views/pair.ts), and the members'
/// devices waiting on this one for a vault's key (views/vault.ts `vaultAsks`), wherever the person is.
export function promptsView(inner: Inner): J {
  return { pairing: pairs.shown(inner), asks: vaultAsks(inner) };
}

/// A `lockPrompt.*` call: `deny {device}`, a new device showing this one's code turned away (views/pair.ts); `hide
/// {device}`, its prompt closed; `state`, the topic's value (tests, scripts).
export function runPrompt(inner: Inner, name: string, params: Record<string, unknown>, _ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
  if (name === "state") return Effect.succeed(promptsView(inner));
  if (name === "deny") pairs.deny(inner, str(params.device) ?? "");
  else if (name === "hide") pairs.hide(inner, str(params.device) ?? "");
  else return Effect.fail(CoreError.invalid(`no lockPrompt call ${name}`));
  return Effect.succeed(null);
}

/// What approving face to face adds (views/pair.ts, installed with it): the new devices showing this one's code, this
/// device's own try to be approved, and the calls of that try.
export const pairs: {
  shown(inner: Inner): J[];
  mine(inner: Inner, ws: string): J | null;
  deny(inner: Inner, device: string): void;
  hide(inner: Inner, device: string): void;
  moved(inner: Inner, ws: string): void;
  reading(inner: Inner, ws: string): void;
  run(inner: Inner, name: string, ws: string, params: Record<string, unknown>): Effect.Effect<unknown, CoreError>;
} = { shown: () => [], mine: () => null, deny: () => {}, hide: () => {}, moved: () => {}, reading: () => {}, run: () => Effect.fail(CoreError.invalid("no face-to-face approval here")) };

/// The draft of turning it on: the devices that came to the stations (that asked the cloud for credentials, where no
/// station says), the stations asked whether they understand a lock (GET /lock: one from before answers 404).
function draft(inner: Inner, ws: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const sub = inner.workspaces.owner(ws);
    if (sub === null) return;
    const p = part(inner, ws);
    // The devices that came to the stations (each says those that came to it); of the cloud only when none says.
    const came: J[][] = [];
    yield* Effect.forEach(
      arr(get(view(inner, ws), "stations")),
      (s) =>
        Effect.gen(function* () {
          const r = yield* Effect.result(inner.stations.requests.call(new StationAddr(ws, s.id), "GET", "/lock", null, { quiet: true }));
          // One that answers with a lock of its own keeps another (turned on before, not off there): reset first.
          p.probes.set(s.id, r._tag === "Success" ? (readHead(get(r.success, "head")) === null ? "ok" : "other") : r.failure.status === 404 || /404|no route/.test(r.failure.message) ? "old" : "offline");
          lockSeen(inner).touch(`draft ${ws}`);
          if (r._tag !== "Success" || !arr(get(r.success, "serves")).includes("devices")) return;
          const d = yield* Effect.result(inner.stations.requests.call(new StationAddr(ws, s.id), "GET", "/lock/devices", null, { quiet: true }));
          if (d._tag === "Success") came.push(arr(get(d.success, "devices")));
        }),
      { concurrency: 4, discard: true },
    );
    if (came.length > 0) p.devices = mergeSeen(came);
    else {
      const answer = yield* Effect.result(inner.provider.request(sub, "GET", `/v1/workspaces/${encodeURIComponent(ws)}/devices`, null));
      p.devices = answer._tag === "Success" ? arr(get(answer.success, "devices")) : [];
    }
    lockSeen(inner).touch(`draft ${ws}`);
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
  const members = arr(get(v, "members")).map((m) => ({ sub: m.sub, email: m.email, name: m.name ?? "", role: m.role, nameText: m.name || m.email, roleText: roleText(m.role) }));
  const bySub = new Map(members.map((m) => [m.sub, m]));
  const devices = draftDevices(inner, ws).map((d) => {
    const person = bySub.get(d.sub)?.name || bySub.get(d.sub)?.email || "";
    const older = d.older === true;
    return {
      id: d.id, person, kind: d.kind, label: d.label, older, current: d.this,
      last_seen: d.seen, on: d.this || !p.excluded.has(d.id), fixed: d.this,
      // whose and which (this one said so), then what it is: an older client's way in, a web page or an app (this app signs)
      nameText: `${person} · ${d.this ? t("web-pages.security.thisDevice") : deviceText({ kind: d.kind, label: d.label, older })}`,
      howText: (older ? t("web-pages.security.olderHow") : t(d.kind === "web" ? "web-pages.security.web" : "web-pages.security.app")) +
        (d.this && d.kind === "app" ? ` · ${t("web-pages.security.signs")}` : ""),
    };
  });
  const stations = arr(get(v, "stations")).map((s) => {
    const probe = p.probes.get(s.id) ?? null;
    const state = probe ?? "asking";
    return {
      id: s.id, name: s.name, version: s.version ?? null, state, on: probe === "ok" && !p.excluded.has(s.id), fixed: probe !== "ok",
      // why it cannot be signed yet (none when it can)
      stateText: state === "ok" ? null : t(state === "asking" ? "web-pages.security.asking" : state === "old" ? "web-pages.security.tooOld" : state === "other" ? "core-misc.lock.stationOtherLock" : "web-pages.security.offline"),
    };
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
        yield* Effect.ignore(lock.base(), { log: "Unhandled", message: "lock base read" });
        yield* Effect.ignore(read(inner, c.workspace), { log: "Unhandled", message: "lock read" });
        return lockView(inner, c.workspace);
      // The notice that the lock is off, closed for good on this device (prefs `lockNotice`).
      case "dismiss":
        prefs.set(inner.data, { lockNotice: { [c.workspace]: true } }, false, inner.host.nowMs());
        touch(inner, c.workspace);
        return null;
      case "toggle": {
        const ex = part(inner, c.workspace).excluded;
        if (ex.has(param("id"))) ex.delete(param("id"));
        else ex.add(param("id"));
        lockSeen(inner).touch(`draft ${c.workspace}`);
        return null;
      }
      case "open":
        result = yield* lock.open();
        break;
      // Approved face to face (views/pair.ts): asked, the code typed, given up.
      case "pair":
      case "pairCode":
      case "pairCancel":
        return yield* pairs.run(inner, c.name, c.workspace, c.params);
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
        // The person's own secrets opened while the lock still says whose they are ( 一个库): once it is
        // off they go into the plain library, as the dialog said. Turned down there, nothing is turned off.
        // (the person asked once, for this: the box key's prompt says it, the vaults' keys unsealed with it; asked by
        // itself only where none was needed. Two prompts in a row for one tap: found on Android, 2026-11-05)
        let asked = false;
        const secrets = yield* unsealOwn(inner, c.workspace, t("core-misc.lock.reason.disable"), () => (asked = true));
        if (!asked) yield* askPerson(inner, t("core-misc.lock.reason.disable"));
        result = yield* lock.append("disable", {});
        if (secrets.length > 0) inner.runner.fork(writePlain(inner, c.workspace, secrets));
        break;
      }
      default:
        return yield* Effect.fail(CoreError.invalid(`no lock call ${c.name}`));
    }
    // What changed is read again before the call answers (the pages show it at once).
    yield* Effect.ignore(read(inner, c.workspace), { log: "Unhandled", message: "lock read" });
    return result;
  });
}

/// Whether `chain` (`entries` and one more, signed with `key`) is one the stations take: why not, said to the person.
function checkSigned(entries: Entry[], chain: Entry[], key: string, at: number): Effect.Effect<void, CoreError> {
  return Effect.try({
    try: () => {
      let kept: Checked;
      try {
        kept = checkLock(entries, at);
      } catch {
        throw new CoreError("lock_invalid", t("core-misc.lock.chainInvalid"));
      }
      const by = signerIn(kept, key, at);
      if (by === null) throw new CoreError("lock_no_signer", t("core-misc.lock.notSigner"));
      // (put in under this person's name by someone else: what it signs changes nothing at a station)
      if (!by.own) throw new CoreError("lock_not_own", t("core-misc.lock.notOwn"));
      try {
        checkLock(chain, at);
      } catch {
        throw new CoreError("forbidden", t("core-misc.lock.notAllowed"));
      }
    },
    catch: (e) => (e instanceof CoreError ? e : new CoreError("lock_invalid", String(e))),
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

/// A member or a station taken out of a locked workspace by this account, or a member given another role: so in its
/// lock first, by this device, where it signs there for an owner or an admin (`member.remove` takes their devices with
/// them; `member` with the role, which the lock's rules decide who may give). The cloud's word alone is not the lock's:
/// it could hold back the end of a member's credential or let a station back in, and the stations would take them as
/// the lock still says; an admin made a member there would still sign as an admin. Where this device signs nothing there
/// (a web page, one not let in), or the lock does not name them, the cloud's word is all there is, as before; once the
/// lock is to say it, a failure here is the call's, and the cloud is not asked.
export function roster(inner: Inner, sub: string, ws: string, what: Roster): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    if (inner.provider.kind !== "stillfail" || inner.workspaces.owner(ws) !== sub) return null;
    yield* Effect.ignore(read(inner, ws), { log: "Unhandled", message: "lock read before a roster change" });
    const h = held(inner, ws);
    const key = signerOf(inner);
    if (!h?.head || key === null || !inner.host.appKeys) return null;
    const f = fold(h.entries);
    const member = "member" in what ? f.members.get(what.member) : undefined;
    if (f.disabled || ("member" in what ? member === undefined || ("role" in what && member.role === what.role) : !f.stations.has(what.station))) return null;
    let by: ReturnType<typeof signerIn> = null;
    try {
      by = signerIn(checkLock(h.entries, now(inner)), key, now(inner));
    } catch {
      return null;
    }
    if (by === null || by.sub !== sub || !by.own || (by.role !== "owner" && by.role !== "admin")) return null;
    const lock = new Lock(inner, ws, sub, null);
    if ("station" in what) return yield* lock.append("station.remove", { key: what.station });
    if ("role" in what) return yield* lock.append("member", { sub: what.member, email: member!.email, role: what.role });
    return yield* lock.append("member.remove", { sub: what.member });
  });
}

/// A station that joined a locked workspace from its home taken into that workspace's lock, as
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

  /// The chain as the stations keep it (the longest that goes on from the one held), read now; as the cloud does when
  /// none of them answers.
  #chain(): Effect.Effect<{ head: Head | null; entries: Entry[] }, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      if (yield* readLockOf(self.#inner, self.ws, lockStations(self.#inner, self.ws))) {
        const h = held(self.#inner, self.ws);
        return { head: h?.head ?? null, entries: h?.entries ?? [] };
      }
      const r = yield* self.#cloud("GET", "/lock");
      return { head: readHead(get(r, "head")), entries: arr(get(r, "entries")) as Entry[] };
    });
  }

  /// Entries brought to the cloud, for the stations and devices from before that read the lock there: waited on only
  /// when no station took them (`took`), else not (a failure there is no failure of this).
  #toCloud(entries: Entry[], took: boolean): Effect.Effect<void, CoreError> {
    const asked = Effect.asVoid(this.#cloud("POST", "/lock", { entries }));
    if (!took) return asked;
    this.#inner.runner.fork(Effect.ignore(asked));
    return Effect.void;
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

  /// Someone the cloud has made a member, in the lock now, as a person approves their first device: a member, whatever
  /// the cloud calls them (it lowers roles and raises none; a role above that takes someone's signature saying so). One
  /// the lock has heard of since (another device got there first) is left as they are.
  admit(sub: string, email: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const { entries } = yield* self.#chain();
      return fold(entries).members.has(sub) ? null : yield* self.append("member", { sub, email, role: "member" });
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
      const keysAnswer = yield* Effect.mapError(inner.host.fetch({ method: "GET", url: `${origin}/.well-known/stillfail-grant-keys`, headers: [], body: null }), (e) => CoreError.plainly("network", e));
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
      const pinned = yield* self.#bring([genesis], stations.map((s) => s.key));
      yield* self.#toCloud([genesis], Object.values(pinned).some((h) => readHead(h) !== null));
      p.excluded.clear();
      return { head: { seq: 0, hash: entryHash(genesis), genesis: entryHash(genesis) }, stations: stations.map((s) => ({ id: s.key, name: s.name, pinned: pinned[s.key] ?? null })), devices: devices.length, members: members.length };
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
        // It takes none of this workspace's members, the lock turned on after it joined (and it not in it then): it
        // pins the lock itself once the lock names it, from the cloud (station/src/cloud/presence.ts takeFromPlane), as
        // no device of this workspace may reach it to bring it.
        if (asked.failure.code === "lock_station" && asked.failure.message === t("core-logic.mesh.lock_station.unpinned")) {
          const f = fold(held(self.#inner, self.ws)?.entries ?? []);
          return f.stations.has(station) ? { head: null, stations: {} } : yield* self.append("station", { key: station, name: s.name ?? "" });
        }
        // It takes none of them for another reason (its own workspace locked and this one not): why, as it said.
        if (asked.failure.code === "lock_station") return yield* Effect.fail(asked.failure);
        const old = asked.failure.status === 404 || /404|no route/.test(asked.failure.message);
        return yield* Effect.fail(new CoreError(old ? "lock_station_old" : "lock_station_offline", old ? t("core-misc.lock.stationOld", { name: s.name }) : t("core-misc.lock.stationOffline", { name: s.name })));
      }
      // It keeps another lock: none of this one's entries would follow its own.
      const theirs = readHead(get(asked.success, "head"));
      part(self.#inner, self.ws).heads.set(station, theirs);
      if (theirs !== null && !onChain(held(self.#inner, self.ws), theirs)) return yield* Effect.fail(otherLock(self.#inner, self.ws, station));
      const done = yield* self.append("station", { key: station, name: s.name ?? "" }, [station]);
      const pinned = get(get(done, "stations"), station);
      if (isObject(pinned) && typeof pinned.error === "string") return yield* Effect.fail(new CoreError("lock_station_refused", pinned.error));
      part(self.#inner, self.ws).heads.set(station, readHead(pinned));
      return done;
    });
  }

  /// One more entry, signed by this app's key, after the chain as the stations keep it: to each station of the lock,
  /// done once one of them took it (they bring each other level, lock-sync.ts), the call not waiting on the rest: one
  /// offline held an approval up until asking it gave up, some ten seconds to minutes. To the cloud too, for the stations
  /// and devices from before that read it there, waited on only when no station took it. `waitFor`: the stations whose
  /// answers the call waits for (one just taken in pins only what this device brings it).
  append(kind: string, body: unknown, waitFor: string[] = []): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const signer = yield* Signer.load(self.#inner.host);
      if (signer === null) return yield* Effect.fail(new CoreError("lock_no_signer", "this device signs nothing for the workspace lock"));
      const { head, entries } = yield* self.#chain();
      if (head === null) return yield* Effect.fail(new CoreError("lock_none", "the workspace has no lock"));
      const entry = signer.sign(next(self.ws, head, self.#inner.host.nowMs() / 1000, kind, body));
      // The whole chain: a station that is behind takes what it lacks, and skips what it has.
      const chain = [...entries, entry];
      // Checked as the stations check it before it goes: one they refuse, kept at the cloud, leaves every entry after
      // it refused there too (2026-10-28: a device the lock names without its key approved one, and a station kept
      // turning the devices approved after it away for days).
      yield* checkSigned(entries, chain, signer.id, now(self.#inner));
      const stations = [...fold(chain).stations.keys()];
      const pinned = yield* self.#bring(chain, stations.filter((s) => waitFor.includes(s)));
      const taken = (h: unknown) => (readHead(h)?.seq ?? -1) >= entry.seq;
      // (waited on only of those that serve it: one from before, or not answering, hears of it in the background)
      const serving = part(self.#inner, self.ws).serving;
      const others = stations.filter((s) => !waitFor.includes(s));
      const later = others.filter((s) => !serving.has(s));
      if (later.length > 0) self.#inner.runner.fork(Effect.ignore(self.#bring(chain, later), { log: "Unhandled", message: "lock chain brought" }));
      const took = Object.values(pinned).some(taken) || (yield* self.#firstTaken(chain, others.filter((s) => serving.has(s)), taken));
      // Not taken as far as this device heard: the cloud may have kept it all the same, its answer lost on the way
      // back (a gateway's 502, the line gone). Then it is done: asked again, it would say it failed while it went.
      yield* Effect.catch(self.#toCloud([entry], took), (e) =>
        Effect.flatMap(Effect.orElseSucceed(Effect.map(self.#cloud("GET", "/lock"), (r) => arr(get(r, "entries")) as Entry[]), () => null), (kept) => {
          const there = kept?.find((x) => x.seq === entry.seq);
          return there !== undefined && entryHash(there) === entryHash(entry) ? Effect.void : Effect.fail(e);
        }),
      );
      return { head: { seq: entry.seq, hash: entryHash(entry), genesis: head.genesis }, stations: pinned };
    });
  }

  /// Entries brought to each of `stations`, each on its own (one offline hears of them later): whether one of them
  /// took them (`taken`, as its answer says), as soon as one did; false once none did, there are none, or none
  /// answered by TAKEN_MS (the cloud then is what takes them, as before).
  #firstTaken(entries: Entry[], stations: string[], taken: (head: unknown) => boolean): Effect.Effect<boolean> {
    const self = this;
    return Effect.gen(function* () {
      if (stations.length === 0) return false;
      const done = Deferred.makeUnsafe<boolean>();
      let left = stations.length;
      for (const id of stations)
        self.#inner.runner.fork(Effect.flatMap(Effect.result(self.#station(id, "POST", "/lock", { entries })), (r) => Effect.sync(() => {
          if (r._tag === "Success" && taken(get(r.success, "head"))) Deferred.doneUnsafe(done, Effect.succeed(true));
          else if (--left === 0) Deferred.doneUnsafe(done, Effect.succeed(false));
        })));
      return yield* Effect.map(Effect.timeoutOption(Deferred.await(done), TAKEN_MS), (o) => o._tag === "Some" && o.value); // timer: a deadline
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
