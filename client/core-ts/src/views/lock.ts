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
import { Deferred, Effect, type Result, Schedule, Semaphore } from "effect";
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
import { get, hex, isObject, sha256, utf8 } from "../util.ts";
import { type Checked, checkLock, lockChain, signerIn } from "../vault/lock-check.ts";
import { AGAIN_MOST, againOf, hashOf, keep, links } from "../lock-keep.ts";
import { unsealOwn, vaultAsks, vaultCome, writePlain } from "./vault.ts";
import { laterSleep } from "../runtime.ts";
import { Marks } from "../reactive.ts";
import { ofAddress } from "../workspace.ts";
import { type Device as PersonDevice, type PersonalEnv, type Stated, personOf, personRules } from "../personal-lock.ts";
import { CHAIN_MOST, type Folded, type InForce, bodyHash, bodyRefused, fold, goodFor, inForce, movedRoot, wsTag } from "../lock-moved.ts";
import { type Said, bodiesOf, byHash, plan, prevOf } from "../lock-statements.ts";
import { type Act, CLOUD_WRITE_MS, PENDING_MOST, actText, cloudSilent, type Pending, type PendingRow, bounded, pastBound, pendingFields, pendingRow, repeats } from "../lock-pending.ts";

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
/// How long a call a person waits on waits on the workspace's stations alone for its lock, all told: the lock read
/// again before it is signed, a station taking what was signed, and the read after. Those are the lock's own calls
/// (`run`: a device taken out or renewed, the lock turned off, the page read; a device approved face to face,
/// views/pair.ts `approve`, its person made a member first where the lock has not heard of them) and the writes to the
/// cloud the lock has a part in (a member added, taken out or given a role, a station taken out or enrolled: `roster`,
/// `added`, `enrolled`); and a person's own lock's, each of their phases (personal-lock.ts `asked`: a device taken off
/// it or let in, the lock opened, joined or begun anew, a grant or a rig's call signed). Past it a read is not waited
/// for: the lock is signed as held here (the stations' events keep that level, and no read brings more of ones that do
/// not answer), and the reads go on behind. An entry signed that no station took nor refused by then is pending
/// (`Lock.append`), the call answered saying so, and the stations still listened to (TAKEN_MS from when they were
/// brought it), one taking it then holding it; the cloud's taking it never counts. 2026-11-11
/// a member added in a locked workspace whose stations were not reached turned its button for minutes; 2026-11-12, with
/// a workspace's one station asleep, 移除设备, turning safe mode off and approving a device each took 45 s, three waits of
/// TAKEN_MS, and with the cloud's reads unanswered too never answered; and the same day, the cloud frozen and the
/// station just started anew, its link back 10 s later, a device let in face to face was never answered: the call had
/// stopped listening to the stations at 3 s; and with the station asleep and the cloud up, a removal answered as done
/// though no station would act on it.
export const ASKED_MS = 3_000;
/// A device of the person's own added this recently is pointed out on their other devices.
const RECENT_SECS = 7 * 86400;
/// Once one station answered a read of the locks, how much longer the others are waited for.
export const OTHERS_MS = 2_000;
/// How lately a device came to the stations, or a station to the control plane, for it to be waited for before a
/// person's lock is begun with no one asked (station/src/mesh/seen-devices.ts SEEN_SECS, which its lists keep).
const SEEN_SECS = 31 * 86400;

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

/// One call's wait on the stations (ASKED_MS from its first `wait`): `first(work)` runs `work` to its end in a fiber of
/// the core's (what it reads is held when it comes, whoever still waits) and gives its answer if that came by then
/// (`now`), else the way to wait for it still (`later`); `wait(work)` gives the answer by then, else none. Its time
/// begins with the first wait, not with the call: the person asked first (turning the lock off: a fingerprint, seconds
/// of theirs) would have used it up, and stations that answer would not be waited on at all, the cloud alone taking the
/// entry (the root AGENTS.md, The cloud is the account system). Past it a read is not waited for (the call goes by
/// what is held), while an entry brought to the stations still is, beside the cloud (`Lock.append`).
/// `begin`: its time begun now, where it has not yet (a call's turn to sign waited for is its wait's too: `Lock.append`).
export type Asked = {
  first<A>(work: Effect.Effect<A>): Effect.Effect<{ now: A } | { later: Effect.Effect<A> }>;
  wait<A>(work: Effect.Effect<A>): Effect.Effect<A | undefined>;
  begin(): Effect.Effect<void>;
};
export function asked(inner: Inner): Asked {
  const late = Deferred.makeUnsafe<void>();
  let over = false;
  let begun = false;
  const begin = () => {
    if (begun) return;
    begun = true;
    inner.runner.fork(Effect.andThen(Effect.sleep(ASKED_MS), Effect.sync(() => { over = true; Deferred.doneUnsafe(late, Effect.void); }))); // timer: a deadline on what a call waits for
  };
  const first = <A>(work: Effect.Effect<A>) =>
    Effect.suspend((): Effect.Effect<{ now: A } | { later: Effect.Effect<A> }> => {
      begin();
      const done = Deferred.makeUnsafe<A>();
      inner.runner.fork(Effect.flatMap(work, (a) => Effect.sync(() => { Deferred.doneUnsafe(done, Effect.succeed(a)); })));
      const later = { later: Deferred.await(done) };
      if (over) return Effect.succeed(later);
      return Effect.raceFirst(Effect.map(Deferred.await(done), (a) => ({ now: a })), Effect.as(Deferred.await(late), later));
    });
  return {
    first,
    wait: <A>(work: Effect.Effect<A>) => Effect.map(first(work), (r): A | undefined => ("now" in r ? r.now : undefined)),
    begin: () => Effect.sync(begin),
  };
}

/// Of a station's answer to what is brought: done once one took it, the others waited for OTHERS_MS once one refused.
export const tookOrRefused = (r: Result.Result<unknown, unknown>): number => (r._tag === "Success" ? 0 : OTHERS_MS);

/// What the cloud keeps of a workspace's lock, as held here (the `lock` record of the workspace). `seen`: the devices
/// that asked the cloud for credentials in the last 31 days, as far as the viewer may see them (owners and admins all,
/// others their own; none from a cloud that would not say): when each was last used and what it calls itself now.
/// A device is approved only face to face (views/pair.ts): the cloud's requests of older clients, approved there with
/// a press, are neither read nor answered (2026-11-02 the user: a tap let a device in without its code typed on it).
/// `entries` is the chain gone by, from the genesis (what every reader reads, a core from before too); `aside`, absent
/// from records of before 2026-11-12 and while none is, the entries of this lock a station showed that are off it
/// (src/lock-keep.ts): the chain is the rules' choice among all of them (`hold`).
type Held = { head: Head | null; entries: Entry[]; aside?: Entry[]; seen?: J[] | null };

/// What this device keeps of a workspace's lock this run.
type Part = {
  /// The state in force of a moved chain as made last (`inForceOf`), with what it was made of, as the objects read: the
  /// chain held, the `lockLogs` and `lockBodies` records, the person's own pinned chain, the stations the workspace's
  /// view lists; and from when until when by this device's clock it stands (src/lock-moved.ts `goodFor`).
  force: { entries: readonly Entry[]; logs: unknown; bodies: unknown; own: readonly Entry[] | null; listed: unknown; from: number; until: number; made: InForce } | null;
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
  /// The read of every station of the workspace while none is held (readLockOf), while it runs: one at a time.
  reading: Deferred.Deferred<{ got: boolean; refused: boolean }, CoreError> | null;
  /// This device's turn to sign in the lock (`Lock.append`): one entry at a time, each after the head held as its turn
  /// begins, so no two of its entries are ever signed after the same parent.
  turn: ReturnType<typeof Semaphore.makeUnsafe>;
  /// The stations that said they keep what a device brings as another keeper's (`serves` `forks`): what this device
  /// keeps that one lacks is brought it (`carry`).
  forks: Set<string>;
  /// The entries of the lock a station showed this device or took from it this run, by hash: only those are carried.
  shown: Set<string>;
  /// What was carried to each station this run (`station/what is kept`): once each.
  carried: Set<string>;
  /// This device's entries that lost their place and were signed again or let be (`Lock.again`), by hash: once each.
  handled: Set<string>;
  /// Of an entry signed again, how many signings it is from the one first signed (AGAIN_MOST at most).
  tries: Map<string, number>;
  /// Of an entry signed again, the one it was signed again for (the lost one, or the pending one), by hash: what act
  /// each of this device's entries is (`actsOf`).
  again: Map<string, string>;
  /// Whether what is pending is being brought to the stations now (`deliver`), and asked again meanwhile.
  delivering: { running: boolean; again: boolean };
};

/// What this device signed in a workspace's lock that no station took yet (src/lock-pending.ts), kept on the device
/// beside the lock held (its own record, `lockPending`, which a core from before never reads: it knows none pending,
/// and leaves them as they are for this one), never on the chain held.
export const pendingHeld = (inner: Inner, ws: string): readonly Pending[] => {
  const r = inner.data.record("lockPending", ws);
  return isObject(r) && Array.isArray(r.items) ? (r.items as Pending[]) : [];
};
/// This device's entries that were pending and a station took since, each with when its pending act was made (`at`,
/// the queue's order; the last TOOK_MOST, kept with what is pending, `hold` the one place that notes them). What
/// `deliver` brings is decided as if made then: one of these made before it decided nothing against it (`againOf`'s
/// subject null for it); one made after it (or at the same ms) and taken first is the later act and wins, as an act
/// made and taken directly does (a stale pending one fails against them).
const TOOK_MOST = 32;
type Took = { hash: string; at: number };
const tookHeld = (inner: Inner, ws: string): readonly Took[] => {
  const r = inner.data.record("lockPending", ws);
  return isObject(r) && Array.isArray(r.took) ? (r.took as Took[]).filter((x) => isObject(x) && typeof x.hash === "string") : [];
};
function putPending(inner: Inner, ws: string, items: readonly Pending[], took: readonly Took[] = tookHeld(inner, ws)): void {
  const kept = bounded(items);
  inner.data.put("lockPending", ws, kept.length === 0 && took.length === 0 ? undefined : { items: kept, ...(took.length > 0 ? { took: took.slice(-TOOK_MOST) } : {}) });
  touch(inner, ws);
}

/// The names of the lock's stations, as the workspace's view (else the lock) names them: what a pending entry waits for
/// (`of`: but one it takes out, whose taking it does not wait for, `Lock.#signed`).
function stationNames(inner: Inner, ws: string, of?: Entry): string[] {
  const f = stateOf(inner, ws);
  const listed = arr(get(view(inner, ws), "stations"));
  const out = of?.kind === "station.remove" ? str(get(of.body, "key")) : null;
  return [...f.stations].filter(([key]) => key !== out).map(([key, name]) => str(listed.find((s) => s?.id === key)?.name) || name || key.slice(0, 8));
}

/// A pending entry's row in the `lock` topic.
export const pendingRowOf = (inner: Inner, ws: string, p: Pending) => pendingRow(p, stationNames(inner, ws, p.entry));

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

export { type Folded, fold } from "../lock-moved.ts";

/// A device of the lock as it stands at `at` (unix seconds): none once its approval ran out (a web page's, after
/// WEB_DEVICE_SECS). The stations let it in nowhere then (station/src/cloud/lock.ts `admit`): it waits and is approved
/// again face to face, as a new one is, rather than being told a station has not heard of it yet.
export function live<D extends { exp?: unknown }>(d: D | undefined, at: number): D | undefined {
  return d !== undefined && (typeof d.exp !== "number" || d.exp > at) ? d : undefined;
}

const part = (inner: Inner, ws: string): Part =>
  inner.workspaces.of(ws).part<Part>("lock", () => ({ force: null, refused: new Map(), behind: new Map(), excluded: new Set(), devices: null, probes: new Map(), heads: new Map(), serving: new Set(), base: bases.get(inner) ?? null, reading: null, turn: Semaphore.makeUnsafe(1), forks: new Set(), shown: new Set(), carried: new Set(), handled: new Set(), tries: new Map(), again: new Map(), delivering: { running: false, again: false } }));

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

/// The person logs a workspace's stations gave this device (GET /lock/logs, `serves` `logs`), kept beside its lock
/// (`lockLogs`, a record of its own in the workspace's, which a core from before never reads): each its chain gone by
/// and what is aside, by the person logs' rules and their fork choice, as personal-lock.ts keeps the person's own
/// (src/lock-keep.ts `keep`, `personRules`). The log of this device's own person is not kept here: it is the chain
/// personal-lock.ts pins (`pinnedOf`), joined to these as the state is made (`inForceOf`). At most LOGS_MOST logs, each
/// at most CHAIN_MOST entries: one past them is not taken.
type LogsHeld = { logs: { genesis: string; entries: Entry[]; aside?: Entry[] }[] };
const LOGS_MOST = 256;
const logsHeld = (inner: Inner, ws: string): LogsHeld["logs"] => {
  const r = inner.data.record("lockLogs", ws);
  return isObject(r) && Array.isArray(r.logs) ? (r.logs as LogsHeld["logs"]) : [];
};
/// The bodies of a workspace's statements this device took (GET /lock/bodies, `serves` `bodies`), kept beside its lock
/// (`lockBodies`): each only where an entry of a log kept here commits to it (src/lock-moved.ts `bodyRefused`), so they
/// are bounded by the entries kept, and none let go while the lock is held.
const bodiesHeld = (inner: Inner, ws: string): unknown[] => {
  const r = inner.data.record("lockBodies", ws);
  return isObject(r) && Array.isArray(r.bodies) ? (r.bodies as unknown[]) : [];
};

/// Each person log held of `ws` by its genesis hash, its own person's the chain personal-lock.ts pins: `stored`, all
/// that is kept of each (its chain and what is aside, what a body's commitments are looked for among), else its chain.
function logsOf(inner: Inner, ws: string, stored: boolean): Map<string, readonly Entry[]> {
  const out = new Map<string, readonly Entry[]>();
  for (const l of logsHeld(inner, ws)) out.set(l.genesis, stored ? [...l.entries, ...(l.aside ?? [])] : l.entries);
  const sub = inner.workspaces.owner(ws);
  const own = sub === null ? [] : inner.adb.personal().pinnedOf(sub);
  if (own.length > 0) out.set(hashOf(own[0]!), own);
  return out;
}

/// The person logs stations of `ws` gave (`chains`, `{genesis, entries}` each) kept: each entry the person logs'
/// rules take after a parent kept, the chain the rules' choice among all (none of its own person's: personal-lock.ts
/// reads that one of its stations itself). Whether any changed.
function keepLogs(inner: Inner, ws: string, chains: readonly J[]): boolean {
  const sub = inner.workspaces.owner(ws);
  const own = sub === null ? null : inner.adb.personal().root(sub);
  const logs = [...logsHeld(inner, ws)];
  let changed = false;
  for (const c of chains) {
    const genesis = get(c, "genesis"), entries = arr(get(c, "entries")) as Entry[];
    if (typeof genesis !== "string" || genesis === own || entries.length === 0 || entries.length > CHAIN_MOST) continue;
    const first = entries[0]!;
    const who = get(first.body, "sub");
    if (first.kind !== "genesis" || typeof who !== "string" || hashOf(first) !== genesis) continue;
    const at = logs.findIndex((l) => l.genesis === genesis);
    if (at < 0 && logs.length >= LOGS_MOST) continue;
    const was = at < 0 ? { entries: [], aside: [] } : { entries: logs[at]!.entries, aside: logs[at]!.aside ?? [] };
    let t: ReturnType<typeof keep>;
    try {
      t = keep(was, entries, personRules(who, genesis));
    } catch {
      continue;
    }
    if (!t.changed) continue;
    const l = { genesis, entries: t.kept.entries, ...(t.kept.aside.length > 0 ? { aside: t.kept.aside } : {}) };
    if (at < 0) logs.push(l);
    else logs[at] = l;
    changed = true;
  }
  if (changed) inner.data.put("lockLogs", ws, { logs });
  return changed;
}

/// The bodies stations of `ws` gave taken, each where an entry kept commits to it (`bodyRefused`); none let go.
/// Whether any was.
function keepBodies(inner: Inner, ws: string, given: readonly unknown[]): boolean {
  if (given.length === 0) return false;
  const kept = bodiesHeld(inner, ws);
  const have = new Set(kept.map((b) => bodyHash(b)));
  const stored = logsOf(inner, ws, true);
  const taken: unknown[] = [];
  for (const b of given) {
    const r = bodyRefused(ws, b, stored, hashOf);
    if (r.why !== null || r.hash === null || have.has(r.hash)) continue;
    have.add(r.hash);
    taken.push(b);
  }
  if (taken.length === 0) return false;
  inner.data.put("lockBodies", ws, { bodies: [...kept, ...taken] });
  return true;
}

/// Who and what is in the lock in force in `ws` (`inForceOf`): what every reader of the lock now reads, where the chain
/// held is read for itself (its own `disable`, its stations keeping it, its entries) by `fold`.
export const stateOf = (inner: Inner, ws: string, entries?: readonly Entry[]): Folded => inForceOf(inner, ws, entries).f;

/// Whether the chain held of `ws` moved to its people's logs: nothing is signed on it then (`lockMoved`).
export const movedHere = (inner: Inner, ws: string): boolean => movedRoot(held(inner, ws)?.entries ?? []) !== null;

/// What a writer onto a workspace's chain answers once it moved: nothing signed, nothing pending. Its words are the
/// core's own until statements in the person's own log replace it (no person meets it until a chain moves).
export const lockMoved = (): CoreError => new CoreError("lock_moved", "this workspace's lock is kept in its people's own logs now: nothing is signed on its chain", 409);

/// What is in force in `ws` by the chain held: folded where it moved nowhere (no other record read), else the rules'
/// state of the person logs and bodies held here, by this device's clock (src/lock-moved.ts `inForce`). A station's
/// name is the workspace's view's for its key (a `station` body has none).
///
/// The rules' state checks every entry of every log again: it is made once and kept in this core's memory for the
/// workspace (`part`'s `force`, never in the database), as a station keeps its own (station/src/cloud/state.ts
/// `forceOf`), and made again only where what it is made of is not the objects it was made of (each record read is
/// the object the database's cache holds until it is written: src/db/account.ts `#doc`) or this device's clock left
/// the span it stands for. Every reader reads what is given and none writes on it (src/lock-moved.ts `Folded`, read
/// only).
export function inForceOf(inner: Inner, ws: string, entries: readonly Entry[] = held(inner, ws)?.entries ?? []): InForce {
  if (movedRoot(entries) === null) return { said: "chain", root: null, f: fold(entries) };
  // (each read as a reader reads it, so a topic made of it is made again as one changes)
  const logs = inner.data.record("lockLogs", ws);
  const bodies = inner.data.record("lockBodies", ws);
  const sub = inner.workspaces.owner(ws);
  const pinned = sub === null ? [] : inner.adb.personal().pinnedOf(sub);
  const own = pinned.length > 0 ? pinned : null;
  const listed = get(view(inner, ws), "stations");
  const at = now(inner);
  const p = part(inner, ws);
  const was = p.force;
  if (was !== null && was.entries === entries && was.logs === logs && was.bodies === bodies && was.own === own && was.listed === listed && at >= was.from && at < was.until) return was.made;
  const chains = logsOf(inner, ws, false);
  const names = arr(listed);
  const made = inForce(ws, entries, chains, bodiesHeld(inner, ws), inner.host.nowMs(), (key) => str(names.find((s) => s?.id === key)?.name) || undefined);
  p.force = { entries, logs, bodies, own, listed, ...goodFor(chains.values(), at), made };
  return made;
}

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

/// Whether a station's lock, as it said (`theirs`), is the lock held here at all: of its genesis. One on another branch
/// of it (its head an entry kept aside here, or its chain parting from the one held) is behind or level-to-be, the
/// stations and this device coming to one chain by the rules' fork choice (src/lock-keep.ts, `carry`): never one to be
/// reset on its own machine. Only a lock of another genesis is another lock (`otherLock`).
function sameLock(h: Held | null, theirs: Head): boolean {
  return !h?.head || theirs.genesis === h.head.genesis;
}

/// Whether a station holds the lock as held here (behind on it, or on another branch of it): not when it said it keeps
/// none, or another.
function keeps(inner: Inner, ws: string, station: string): boolean {
  const p = part(inner, ws);
  if (!p.heads.has(station)) return true;
  const theirs = p.heads.get(station)!;
  return theirs !== null && sameLock(held(inner, ws), theirs);
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
  const f = stateOf(inner, ws, h?.entries ?? []);
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
  hooks.added = added;
  hooks.pendingDrop = (inner, ws, id) => {
    const items = pendingHeld(inner, ws);
    if (items.some((x) => x.id === id)) return putPending(inner, ws, items.filter((x) => x.id !== id));
    // (a moved workspace's: statements in the person's own log, their bodies kept here let go of too)
    const sub = inner.workspaces.owner(ws);
    const gone = new Set(sub === null ? [] : (inner.adb.personal().dropStated(sub, id) ?? []));
    if (gone.size === 0) return;
    inner.data.put("lockBodies", ws, { bodies: bodiesHeld(inner, ws).filter((b) => !gone.has(bodyHash(b) ?? "")) });
    touch(inner, ws);
  };
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
    // Its stations may have changed (one taken out): what is pending of its person's own lock is brought as their
    // stations stand now, the cloud's way where the last was taken out (personal-lock.ts `stationsChanged`).
    const owner = inner.workspaces.owner(ws);
    if (owner !== null) inner.adb.personal().stationsChanged(owner);
    const says = cloudSays(view(inner, ws));
    if (says === undefined) return;
    readSaid(inner, ws, says);
  });
  inner.router.owners.push(owner(inner));
  // The stations tell their locks' changes (station/src/mesh/lock-events.ts): the workspace's read of the one that told
  // (and of each as its link opens), the person's own of their stations.
  inner.stations.also.push({
    // (only where there is a lock: one turned on meanwhile is told by the cloud's view as before. Held here, or none
    // held and the cloud's view saying there is one: a device that let go of a lock its stations keep, #5540, or never
    // read it of them, has it of the first of them it reaches again, not only once the cloud's view next changes)
    read: (address) => {
      const ws = ofAddress(address);
      if (inner.provider.kind !== "stillfail" || !(held(inner, ws)?.head || cloudSays(view(inner, ws)))) return Effect.void;
      return Effect.asVoid(readLockOf(inner, ws, [address.slice(ws.length + 1)]));
    },
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
    // The cloud keeping none is not the end of a lock held here and not turned off: it only carries the lock (the root
    // AGENTS.md, The cloud is the account system), and its word alone, asked because no station answered just now,
    // would have this device take safe mode for off. The stations it names all keeping none is what ends it (readLockOf).
    if (head === null && was?.head && !fold(was.entries).disabled) return;
    const more = arr(get(said, "entries")) as Entry[];
    const same = was?.head && head && was.head.genesis === head.genesis;
    // Of the same lock, its entries are signed entries as a station's are (it only carries them): what goes on from the
    // head held is taken, one behind changes nothing, and a chain gone another way is read whole and kept with what is
    // held, the rules choosing (`hold`), as a station's is (readLockOnce).
    const how = same ? ahead(was!, head!, more, get(said, "after_hash")) : null;
    let entries = same ? (Array.isArray(how) ? [...was!.entries, ...how] : was!.entries) : more;
    let parted: Entry[] = [];
    if (how === "parts") parted = arr(get(yield* cloud("/lock"), "entries")) as Entry[];
    if (!same && head && (more.length === 0 || more[0]!.seq !== 0)) entries = arr(get(yield* cloud("/lock"), "entries")) as Entry[];
    const seen = head === null ? null : yield* Effect.orElseSucceed(Effect.map(cloud("/devices"), (r) => arr(get(r, "devices"))), () => was?.seen ?? null);
    yield* hold(inner, ws, sub, how === "behind" || how === "parts" ? was!.head : head, entries, seen, parted);
  });
}

/// How a keeper's chain of the lock held stands to it, by its head (`theirs`) and its entries after the head held
/// (`more`, as `GET /lock?after=` answers; `after_hash`, where it says one, the hash of its entry at the head held's
/// place): behind on it or level (its head the entry held at that place), going on from its head (the entries after,
/// each at its place and each `prev` the hash of the one before), or parted from it: another entry at a place held, an
/// `after_hash` that differs, a `prev` that does not hold. Only the second is put after what is held as it is; one that
/// parts is read whole and kept with it, the rules choosing (`hold`).
function ahead(was: Held, theirs: Head, more: Entry[], afterHash: unknown): Entry[] | "behind" | "parts" {
  const head = was.head!;
  const mine = was.entries[theirs.seq];
  if (theirs.seq <= head.seq) return mine !== undefined && hashOf(mine) === theirs.hash ? "behind" : "parts";
  if (typeof afterHash === "string" && afterHash !== head.hash) return "parts";
  const after = more.filter((e) => e.seq > head.seq);
  const chain = [...was.entries, ...after];
  return after.length > 0 && links(chain, head.seq + 1) && hashOf(chain[chain.length - 1]!) === theirs.hash ? after : "parts";
}

/// The stations a lock is read of: those it names, then the workspace's others.
function lockStations(inner: Inner, ws: string): string[] {
  const h = held(inner, ws);
  const f = stateOf(inner, ws, h?.entries ?? []);
  const named = h?.head && !f.disabled ? [...f.stations.keys()] : [];
  const all = arr(get(view(inner, ws), "stations")).map((s) => s?.id).filter((id): id is string => typeof id === "string");
  return [...new Set([...named, ...all])];
}

/// The lock read of `stations` (each one's GET /lock, and the devices that came to it): held when one of them answered,
/// as the longest chain that goes on from the one held (one that keeps another lock or none says so, and is not taken);
/// false when none did (nothing held then; `said.refused`: one refused this device for the lock).
/// None held (or the one held turned off): every station of the workspace is read, whichever was to be (one told, one
/// whose link opened), since which lock to take is chosen among all their answers (readLockOnce); one read alone would
/// have its lock taken, whatever the others keep. One such read at a time: another asked meanwhile (each link opening
/// again at once, after the network came back) waits for its answer and asks nothing itself.
function readLockOf(inner: Inner, ws: string, stations: string[], said?: { refused: boolean }): Effect.Effect<boolean, CoreError> {
  return Effect.suspend(() => {
    const was = held(inner, ws);
    if (was?.head && !fold(was.entries).disabled) return readLockOnce(inner, ws, stations, said);
    const p = part(inner, ws);
    const tell = (r: { got: boolean; refused: boolean }) => {
      if (r.refused && said) said.refused = true;
      return r.got;
    };
    if (p.reading !== null) return Effect.map(Deferred.await(p.reading), tell);
    const flight = Deferred.makeUnsafe<{ got: boolean; refused: boolean }, CoreError>();
    p.reading = flight;
    const all = lockStations(inner, ws);
    const mine = { refused: false };
    // A fiber of the core's, not of whoever asked first: that one going away (its link closed again as it read) does
    // not end the read for the others waiting on it, who would be left with none held and nothing to read it again.
    inner.runner.fork(
      readLockOnce(inner, ws, all.every((id) => stations.includes(id)) ? stations : all, mine).pipe(
        Effect.map((got) => ({ got, refused: mine.refused })),
        Effect.onExit((exit) => Effect.sync(() => {
          if (p.reading === flight) p.reading = null;
          Deferred.doneUnsafe(flight, exit);
        })),
        Effect.exit,
      ),
    );
    return Effect.map(Deferred.await(flight), tell);
  });
}

function readLockOnce(inner: Inner, ws: string, stations: string[], said?: { refused: boolean }): Effect.Effect<boolean, CoreError> {
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
          if (r._tag === "Success" && arr(get(r.success, "serves")).includes("forks")) p.forks.add(id);
          else p.forks.delete(id);
          if (r._tag !== "Success" || !p.serving.has(id)) return null;
          const head = readHead(get(r.success, "head"));
          p.heads.set(id, head);
          const more = arr(get(r.success, "entries")) as Entry[];
          let entries: Entry[] | null = null;
          // (of the lock held and on: whether its chain parts from the one held, read whole then, its entries kept with
          // what is held and the rules choosing, `hold`)
          let parts = false;
          const how = was?.head && !off && head !== null && head.genesis === was.head.genesis ? ahead(was, head, more, get(r.success, "after_hash")) : null;
          if (head === null) entries = [];
          else if (how === "behind") entries = null;
          else if (Array.isArray(how)) entries = [...was!.entries, ...how];
          else if (how === null && more[0]?.seq === 0) entries = more;
          else {
            const all = yield* ask(id, "/lock");
            entries = all._tag === "Success" ? (arr(get(all.success, "entries")) as Entry[]) : null;
            parts = how === "parts";
          }
          // What it keeps, as far as this read shows it (its chain gone by): what it lacks of what this device keeps is
          // carried to it (`carry`).
          const known = head === null ? [] : how === "behind" ? was!.entries.slice(0, head.seq + 1) : entries;
          // What it shows counts as far as the lock names it: its own removal, and what follows, is not taken of it (whose
          // taking counts are the stations the lock names after an entry, `Lock.#signed`; one taken out is brought it
          // behind, and takes it, but its removal waits for those left).
          const out = entries === null ? -1 : entries.findIndex((e) => e.kind === "station.remove" && get(e.body, "key") === id);
          const shown = out > 0 ? entries!.slice(0, out) : entries;
          const named = out > 0 ? { seq: out - 1, hash: entryHash(shown![out - 1]!), genesis: head!.genesis } : head;
          const devices = yield* ask(id, "/lock/devices");
          // What a workspace said in its people's logs is made of (`serves` `bodies`, `logs`): read where its chain moved,
          // and before that where a station keeps any body (the owner's device states the workspace before it signs
          // `moved`): the bodies first, the logs only where they hold any, so that a station with none is asked once.
          const serves = arr(get(r.success, "serves"));
          const moves = movedRoot(entries ?? was?.entries ?? []) !== null;
          let bodies: J[] = [], lacking: string[] = [], logs: J[] = [];
          if (serves.includes("bodies")) {
            const b = yield* ask(id, "/lock/bodies");
            if (b._tag === "Success") {
              bodies = arr(get(b.success, "bodies"));
              lacking = arr(get(b.success, "lacking")).filter((x): x is string => typeof x === "string");
            }
          }
          if (serves.includes("logs") && (moves || bodies.length > 0 || lacking.length > 0)) {
            const l = yield* ask(id, "/lock/logs");
            if (l._tag === "Success") logs = arr(get(l.success, "chains"));
          }
          return { id, head: named, entries: shown, parts, known, seen: devices._tag === "Success" ? arr(get(devices.success, "devices")) : [], bodies, lacking, logs };
        }),
      ),
      () => OTHERS_MS,
      stations.map((id) => `${ws}/${id}`),
    );
    const served = answers.flatMap((r) => (r._tag === "Success" && r.success !== null ? [r.success] : []));
    if (served.length === 0) return false;
    // Of the lock held: the longest chain that goes on from the one held, where all that do agree as far as they go and
    // none parts from it; else every entry they showed is kept with what is held and the rules choose (`hold`). Never
    // spliced: an entry is put after one only where it says that one's hash. Another lock's is not taken; none longer
    // and none parting, what is held stays.
    let head = was?.head ?? null;
    let entries = was?.entries ?? [];
    const parted: Entry[] = [];
    if (!off) {
      const on: { head: Head; entries: Entry[] }[] = [];
      for (const a of served) {
        if (a.head === null || a.entries === null || a.head.genesis !== head!.genesis) continue;
        if (a.parts) parted.push(...a.entries);
        else if (a.entries.length === a.head.seq + 1 && a.head.seq > head!.seq) on.push({ head: a.head, entries: a.entries });
      }
      on.sort((x, y) => y.entries.length - x.entries.length);
      for (const a of on) {
        if (head!.seq < a.head.seq) {
          head = a.head;
          entries = a.entries;
        } else if (hashOf(entries[a.head.seq]!) !== a.head.hash) parted.push(...a.entries.slice(was!.head!.seq + 1));
      }
    } else {
      // None held (or the one held turned off, whose own chain is not taken again): which lock of those the stations
      // keep. The workspace's view names the one its stations keep (the cloud is sent every entry), and is preferred:
      // where a station keeps that lock, the others' locks are not considered, and of its chains, those holding the
      // entry the view names come first, so that of two that went their own way after some entry the one the view is
      // on is taken. Only a preference, never a refusal: where no station keeps the lock it names (or it names none),
      // what they keep is taken still, so the cloud's word cannot keep a device from the lock honest stations keep (the
      // root AGENTS.md, The cloud is the account system). Nor does it give the cloud more than it had: the order of the
      // stations in its view was what chose before (the first lock, then any other replacing it).
      const says = readHead(get(view(inner, ws), "lock"));
      const whole = served.flatMap((a) =>
        a.head !== null && a.entries !== null && a.entries.length === a.head.seq + 1 && !(was?.head && a.head.genesis === was.head.genesis) ? [{ head: a.head, entries: a.entries }] : [],
      );
      const ofSays = says?.genesis ? whole.filter((a) => a.head.genesis === says.genesis) : [];
      const considered = ofSays.length > 0 ? ofSays : whole;
      const onSays = (a: { head: Head; entries: Entry[] }) => !!says?.genesis && a.head.genesis === says.genesis && a.head.seq >= says.seq && entryHash(a.entries[says.seq]!) === says.hash;
      // (where they keep locks of several genesis and the view names none of them, nothing tells them apart: the first
      // in the stations' order is taken)
      const ordered = [...considered.filter(onSays), ...considered.filter((a) => !onSays(a))];
      if (ordered.length > 0) {
        head = ordered[0]!.head;
        entries = ordered[0]!.entries;
        // Then the longest that goes on from it: of one lock, one station behind another is not what is taken.
        for (const a of ordered) {
          if (a.head.genesis !== head.genesis || a.head.seq <= head.seq || entryHash(a.entries[head.seq]!) !== head.hash) continue;
          head = a.head;
          entries = a.entries;
        }
      }
    }
    // None keeps a lock: none, where none was held, or where every station the held one names says so. A station the
    // held lock does not name (added to the workspace and not protected yet: it goes by the cloud's word, lets the
    // members in and answers that it keeps none) says nothing of it: asked alone as its link opened, its answer was
    // every station's asked, and the device forgot a lock the others kept, with nothing to read it again (#5540).
    const none = new Set(served.filter((a) => a.head === null).map((a) => a.id));
    const named = was?.head ? [...fold(was.entries).stations.keys()] : [];
    if (served.every((a) => a.head === null) && (was?.head == null || (named.length > 0 && named.every((id) => none.has(id))))) {
      head = null;
      entries = [];
    } else if (!off && named.some((id) => none.has(id)) && named.some((id) => !stations.includes(id))) {
      // One the held lock names keeps none, and not all it names were asked (it told so, or its link opened): they
      // are, now. Each of them reset on its own machine tells it alone, and no such read by itself is the lock's end.
      // (Only of a lock held and on: one turned off was read of every station already, readLockOf, and would wait on
      // itself.)
      return yield* readLockOf(inner, ws, lockStations(inner, ws), said);
    }
    // The devices that came, as those read say: with what was held where not every station of the lock answered this
    // read (one read alone as its link opened told only who came to it, and the others' devices lost their last use
    // on 设置 › 安全 until all were read again).
    const whole = lockStations(inner, ws).every((id) => served.some((a) => a.id === id));
    // What the state in force is made of, as these stations of the workspace gave it: the logs first, whose entries
    // the bodies are taken against (a lock held, its own or none); then told as the lock is.
    const logsKept = head === null ? false : keepLogs(inner, ws, served.flatMap((a) => a.logs));
    const bodiesKept = head === null ? false : keepBodies(inner, ws, served.flatMap((a) => a.bodies));
    yield* hold(inner, ws, sub, head, entries, mergeSeen([...(whole ? [] : [(was?.seen ?? []) as J[]]), ...served.map((a) => a.seen)]), head === null ? [] : parted, logsKept || bodiesKept);
    carry(inner, ws, served);
    carryBodies(inner, ws, served);
    // A station of the lock answered: what is pending here is brought to them now.
    deliver(inner, ws);
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

/// What is pending in a workspace's lock (`pendingHeld`) brought to its stations, one of them having just answered a
/// read (its link opened, its `lock` event, a read): in the turn to sign (`Lock.deliver`), one run at a time, a run
/// asked for meanwhile made after it. Never on a timer: a station that did not answer is brought it as it is next read.
export function deliver(inner: Inner, ws: string): void {
  if (!pendingHeld(inner, ws).some((x) => x.state === "waiting")) return;
  const sub = inner.workspaces.owner(ws);
  if (sub === null) return;
  const d = part(inner, ws).delivering;
  if (d.running) return void (d.again = true);
  d.running = true;
  inner.runner.fork(Effect.ensuring(
    Effect.gen(function* () {
      do {
        d.again = false;
        yield* Effect.ignore(new Lock(inner, ws, sub, null).deliver(), { log: "Unhandled", message: "pending lock entries brought" });
      } while (d.again);
    }),
    Effect.sync(() => void (d.running = false)),
  ));
}

/// What a pending entry does, in words (src/lock-pending.ts `Act`), as the lock held says it: shown only where a person
/// asked for it (`shown`: a call they wait on), else the core's own.
function actOf(inner: Inner, ws: string, e: Entry, shown: boolean): { act: Act | null; name: string; role?: string } {
  const name = whatOf(inner, ws, e);
  if (!shown) return { act: null, name };
  const b = (e.body ?? {}) as J;
  const f = stateOf(inner, ws);
  switch (e.kind) {
    case "device.remove":
      return { act: "removeDevice", name };
    case "device":
      return { act: typeof b.exp === "number" && f.devices.has(b.id) ? "renew" : "approve", name };
    case "member":
      return f.members.has(b.sub) ? { act: "setRole", name, role: roleText(str(b.role) ?? "") } : { act: "addMember", name };
    case "member.remove":
      return { act: "removeMember", name };
    case "station":
      return { act: "protectStation", name };
    case "station.remove":
      return { act: "removeStation", name };
    case "disable":
      return { act: "disable", name };
  }
  return { act: null, name };
}

/// What this device keeps of the lock (the chain gone by, then what is aside), each entry a station showed it or took
/// from it this run (`shown`; never one only this device signed and no station took: a station keeps a fresh entry only
/// where it goes on from its head, and `keep` says another keeper took it), brought to each station just read that
/// keeps what a device brings as another keeper's (`serves` `forks`) and lacks some of it, with `keep`: so two stations
/// that cannot reach each other come level, by this device. Once for each station and what is kept, this run; forked,
/// waited on by no one, never tried again on a timer (the next read tries again). Only to a station keeping this lock
/// (its genesis): one that keeps none (reset on its own machine, or the lock turned off there) or another is not given
/// it back so, which would pin it there again.
function carry(inner: Inner, ws: string, served: readonly { id: string; head: Head | null; known: Entry[] | null }[]): void {
  const h = held(inner, ws);
  if (!h?.head || fold(h.entries).disabled) return;
  const p = part(inner, ws);
  for (const a of served) for (const e of a.known ?? []) p.shown.add(hashOf(e));
  const kept = [...h.entries, ...(h.aside ?? [])].filter((e) => p.shown.has(hashOf(e)));
  if (kept.length === 0) return;
  const what = hex(sha256(utf8(kept.map(hashOf).join(","))));
  for (const a of served) {
    if (!p.forks.has(a.id) || a.known === null || a.head?.genesis !== h.head.genesis) continue;
    const has = new Set(a.known.map(hashOf));
    if (kept.every((e) => has.has(hashOf(e)))) continue;
    const at = `${a.id}/${what}`;
    if (p.carried.has(at)) continue;
    p.carried.add(at);
    inner.runner.fork(Effect.ignore(inner.stations.requests.call(new StationAddr(ws, a.id), "POST", "/lock", { entries: kept, keep: true }, { quiet: true }), { log: "Unhandled", message: "lock entries carried to a station" }));
  }
}

/// The bodies a station just read named as lacking (its GET /lock/bodies `lacking`, by hash) that this device keeps,
/// brought to it (POST /lock/bodies): once each read, forked, waited on by no one, never tried again on a timer (the
/// next read tries again). Only to the stations of the workspace read now; it takes each only against an entry it keeps.
function carryBodies(inner: Inner, ws: string, served: readonly { id: string; lacking: readonly string[] }[]): void {
  if (!served.some((a) => a.lacking.length > 0)) return;
  const by = new Map(bodiesHeld(inner, ws).map((b) => [bodyHash(b), b] as const));
  for (const a of served) {
    const bodies = [...new Set(a.lacking)].flatMap((hb) => (by.has(hb) ? [by.get(hb)] : []));
    if (bodies.length === 0) continue;
    inner.runner.fork(Effect.ignore(inner.stations.requests.call(new StationAddr(ws, a.id), "POST", "/lock/bodies", { bodies }, { quiet: true }), { log: "Unhandled", message: "statements' bodies carried to a station" }));
  }
}

/// The lock as read (of the cloud or the stations) held, and what follows from it. What is held may have moved on
/// while it was read (another read landed first: a station asked alone as its link opened, on a slow line, answers
/// what it kept as it was asked): a chain that goes only as far as some entry of the one held now is behind it, and
/// the one held stays. Held as read, it took the entries since back off this device until the lock next moved.
/// Of the lock held and on, what does not go on from its head (a chain read that parts from it, `parted` the entries of
/// those that do) is kept with it, and the chain gone by is the rules' choice among all (`chosen`).
function hold(inner: Inner, ws: string, sub: string, said: Head | null, entries: Entry[], seen: J[] | null, parted: Entry[] = [], made = false): Effect.Effect<void> {
  return Effect.gen(function* () {
    if (said !== null && inner.provider.kind === "stillfail") yield* Effect.ignore(new Lock(inner, ws, sub, null).base());
    // (as held now, not as it was when the read began)
    const was = held(inner, ws);
    const now = chosen(was, said, entries, parted);
    const head = now.head;
    inner.data.put("lock", ws, { head, entries: now.entries, ...(now.aside.length > 0 ? { aside: now.aside } : {}), ...(seen ? { seen } : {}) });
    // What was pending and is on the chain now (a station took it, from this device or from another that carried it):
    // pending no more, and the cloud sent it now, as what a station took is (`Lock.append`).
    const pending = pendingHeld(inner, ws);
    if (pending.length > 0) {
      const on = new Set(now.entries.map(hashOf));
      const left = pending.filter((x) => !on.has(hashOf(x.entry)));
      if (left.length !== pending.length) {
        putPending(inner, ws, left, [...tookHeld(inner, ws), ...pending.filter((x) => on.has(hashOf(x.entry))).map((x) => ({ hash: hashOf(x.entry), at: x.at }))]);
        // (not one the cloud was sent as it was signed, `viaCloud`: read of it, perhaps, which put it on)
        const taken = pending.filter((x) => on.has(hashOf(x.entry)) && x.sent !== true).map((x) => x.entry);
        if (taken.length > 0) inner.runner.fork(Effect.ignore(inner.provider.request(sub, "POST", `/v1/workspaces/${encodeURIComponent(ws)}/lock`, { entries: taken }, null), { log: "Unhandled", message: "lock entries a station took sent to the cloud" }));
      }
    }
    // The lock held names no station (the last taken out): no station's read will ever bring what is pending, so it is
    // brought now, the cloud's way (`Lock.deliver`).
    if (head !== null && fold(now.entries).stations.size === 0 && !fold(now.entries).disabled) deliver(inner, ws);
    // checked as it comes, in a turn of its own (views/vault.ts vaultCome)
    inner.runner.fork(laterSleep(0).pipe(Effect.andThen(Effect.sync(() => vaultCome(inner, ws)))));
    // (where the chain moved, what is in force changes with the logs and bodies too, its head as it was)
    if ((was?.head?.hash ?? null) !== (head?.hash ?? null) || (made && movedRoot(now.entries) !== null)) moved(inner, ws);
    // This device's own entries the chain held went off (kept aside, a read having moved it to another branch): each
    // signed again after the head, once, where that still says what was meant (`Lock.again`), in its turn, in the order
    // made: each as if made then, what it signed again of those before it no decision against it.
    const mine = signerOf(inner);
    const p = part(inner, ws);
    const lost = mine === null || head === null ? [] : [...now.aside].sort((a, b) => a.seq - b.seq).filter((e) => e.sig?.key === mine && !p.handled.has(hashOf(e)));
    if (lost.length > 0) {
      for (const e of lost) p.handled.add(hashOf(e));
      const lock = new Lock(inner, ws, sub, null);
      inner.runner.fork(Effect.forEach(lost, (e, i) => Effect.ignore(lock.again(e, new Set(lost.slice(0, i).map(hashOf))), { log: "Unhandled", message: "an entry that lost its place signed again" }), { discard: true }));
    }
    inner.runner.fork(bindPerson(inner, ws));
    inner.runner.fork(keepToPerson(inner, ws));
    inner.runner.fork(ownLockFor(inner, ws));
    // The vault's too: whether it is locked, this device confirmed in it, whose vaults are trusted (views/vault.ts).
    lockSeen(inner).touch(`lock ${ws}`, `draft ${ws}`, "prompts");
    inner.views?.vaultChanged(ws);
    // This device not in the lock: it waits, and asks to be approved only by hand (`lock.pair`, its waiting page):
    // the person who will type the code is the one who asks (2026-10-19).
  });
}

/// What `hold` writes of a read (`said`, `entries`, `parted`) with what is held now (`was`): a chain read that goes only
/// as far as some entry of the one held, the one held; none read, none; another lock's, or one read where the lock held
/// is off or none is, as read. Of the lock held and on: a chain that goes on from its head, taken as it is; else all of
/// it kept with what is held (and kept aside), the chain gone by the rules' choice among them (src/lock-keep.ts), what
/// is held staying where the rules find none (what was read does not hold by them).
function chosen(was: Held | null, said: Head | null, entries: Entry[], parted: Entry[]): { head: Head | null; entries: Entry[]; aside: Entry[] } {
  const aside = was?.aside ?? [];
  if (said !== null && was?.head != null && parted.length === 0 && said.seq < was.head.seq && onChain(was, said)) return { head: was.head, entries: was.entries, aside };
  if (said === null) return { head: null, entries: [], aside: [] };
  if (was?.head == null || said.genesis !== was.head.genesis || fold(was.entries).disabled) return { head: said, entries, aside: [] };
  const at = entries[was.head.seq];
  if (parted.length === 0 && at !== undefined && hashOf(at) === was.head.hash && links(entries, was.head.seq + 1)) {
    const on = new Set(entries.map(hashOf));
    return { head: said, entries, aside: aside.filter((e) => !on.has(hashOf(e))) };
  }
  const genesis = was.head.genesis;
  const ws = was.entries[0]?.ws;
  try {
    const t = keep({ entries: was.entries, aside }, [...entries, ...parted], { chain: (all) => lockChain(all, genesis), pre: (e) => (e?.ws !== ws ? "an entry of another lock" : null) });
    if (!t.changed) return { head: was.head, entries: was.entries, aside };
    const es = t.kept.entries;
    return { head: { seq: es.length - 1, hash: hashOf(es[es.length - 1]!), genesis }, entries: es, aside: t.kept.aside };
  } catch {
    return { head: was.head, entries: was.entries, aside };
  }
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
  const f = stateOf(inner, ws, h?.entries ?? []);
  // Its own lock is another (another genesis: another branch of this one is not): no approval in this one lets this
  // device in there, however often it is tried.
  const said = readHead(theirs);
  if (said !== null) p.heads.set(station, said);
  if (said !== null && !sameLock(h, said)) {
    p.refused.set(station, h?.head?.hash ?? null);
    touch(inner, ws);
    return otherLock(inner, ws, station);
  }
  // In the lock as this device holds it: the station has not heard of it yet (from the cloud, or the device that
  // signed it), and is tried again shortly rather than once the lock moves on, which it may not again for long.
  // A few times, each a little later (each try asks the station anew); after that, as any station not reached.
  // Refused for its person's own lock too (off it, as far as it knows): the station may hold an entry that changes
  // what the workspace's lock says of it which came just after it refused, and each try's refusal tells it
  // (`heardTail`); else, nobody telling a device it refuses, it never heard (2026-11-12: the entry taking it out landed
  // 5 ms after the refusal, the cloud frozen). Tried as long as the lock held names it, then held as before.
  if (base !== null && h?.head != null && !f.disabled && live(f.devices.get(base), now(inner)) !== undefined) {
    const tries = p.behind.get(station) ?? 0;
    const off = offOwnLock(inner, ws);
    if (tries < BEHIND_TRIES) {
      p.behind.set(station, tries + 1);
      inner.runner.fork(Effect.andThen(Effect.sleep(BEHIND_MS * (tries + 1)), Effect.sync(() => inner.stations?.cameOnline(`${ws}/${station}`)))); // timer: a retry after a failure (a refusal), BEHIND_TRIES at most
      if (off) {
        touch(inner, ws);
        return unconfirmed(inner, ws);
      }
    }
    if (!off) return new CoreError("lock_unconfirmed", t("core-misc.lock.behind"));
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
  if (!h?.head || base === null || movedHere(inner, ws)) return null;
  const f = fold(h.entries);
  if (f.disabled || !f.devices.has(base)) return null;
  let at = h.entries.length - 1;
  // (not one it signed itself, saying itself again (ownLockFor): a station that has not heard of it takes none of its)
  const putIn = (e: Entry) => e.kind === "device" && get(e.body, "id") === base && e.sig?.key !== get(e.body, "sign_key");
  while (at >= 0 && !putIn(h.entries[at]!)) at--;
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
  return personal.standing(sub) === "member" && personal.root(sub) === stateOf(inner, ws, h.entries).persons.get(sub);
}

/// An app device of this person's in the workspace's lock that is on the lock of their own they bound there, as this
/// device (on it too) has it: whose, and its key on that lock. None otherwise.
function onOwnLock(inner: Inner, ws: string, id: string): { sub: string; key: string } | null {
  const sub = inner.workspaces.owner(ws);
  const h = held(inner, ws);
  if (sub === null || !h?.head || !onBoundPerson(inner, ws)) return null;
  const d = stateOf(inner, ws, h.entries).devices.get(id);
  if (d === undefined || d.sub !== sub || d.kind !== "app") return null;
  const on = [...(inner.adb.personal().chain(sub)?.devices.values() ?? [])].find((x) => x.id === id);
  return on === undefined ? null : { sub, key: on.key };
}

/// How this device signs for its person in workspace `ws` now, where that is in security mode (`locked`): with this
/// app's lock key where it is one of their own devices that signs in the workspace's lock (`lock`), with a key on
/// their own lock where they are bound to it there and this device is on it (`person`); null where it signs nothing
/// there (a web page, a device not confirmed yet). What a rig's person signs to take it into the workspace (rigs.ts).
export function signsAs(inner: Inner, ws: string): { locked: boolean; as: "lock" | "person" | null } {
  const h = held(inner, ws);
  const f = stateOf(inner, ws, h?.entries ?? []);
  const locked = h?.head != null && !f.disabled;
  if (!locked || !inner.host.appKeys) return { locked, as: null };
  if (onBoundPerson(inner, ws)) return { locked, as: "person" };
  const sub = inner.workspaces.owner(ws);
  const base = bases.get(inner) ?? null;
  const signer = signerOf(inner);
  const mine = base === null ? undefined : f.devices.get(base);
  return { locked, as: mine !== undefined && mine.sub === sub && signer !== null && mine.sign_key === signer && mine.own !== false ? "lock" : null };
}

/// Whether this app device's person bound a lock of their own in the workspace's, and this device is not on it.
export function offOwnLock(inner: Inner, ws: string): boolean {
  const sub = inner.workspaces.owner(ws);
  const h = held(inner, ws);
  if (sub === null || !h?.head || !inner.host.appKeys) return false;
  return stateOf(inner, ws, h.entries).persons.has(sub) && !onBoundPerson(inner, ws);
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
    if (sub === null || !h?.head || signer === null || !inner.host.appKeys || movedHere(inner, ws)) return;
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
  if (sub === null || !h?.head || signer === null || !inner.host.appKeys || movedHere(inner, ws) || !onBoundPerson(inner, ws)) return null;
  const base = part(inner, ws).base ?? bases.get(inner) ?? null;
  const me = base === null ? undefined : live(fold(h.entries).devices.get(base), now(inner));
  return base !== null && me !== undefined && me.sub === sub && me.sign_key === signer ? { sub, base, h } : null;
}

/// A device just put on its person's own lock here (face to face, views/pair.ts `approve`): put in each workspace's
/// lock where the person bound it and this device signs for them, with the key it signs with, so it signs there and its
/// vault's box is taken as theirs. The person who typed the code waits on it: one ASKED_MS for all of it, past which
/// what no station took by then pending (see `ASKED_MS`; 2026-11-12: with the one station asleep, 45 s more, three waits of TAKEN_MS;
/// with the cloud's reads unanswered too, no answer).
export function putOnBound(inner: Inner, sub: string, device: { id: string; label: string; signKey: string | null }): Effect.Effect<void> {
  return Effect.gen(function* () {
    if (device.signKey === null) return;
    const within = asked(inner);
    for (const [ws, owner] of inner.workspaces.owned()) {
      const at = owner === sub ? signsBound(inner, ws) : null;
      // (one there already that signs with this key: nothing; one there that does not, put in as the lock was turned
      // on, before it signed: put in again with it)
      if (at === null || live(fold(at.h.entries).devices.get(device.id), now(inner))?.sign_key === device.signKey) continue;
      yield* Effect.ignore(new Lock(inner, ws, sub, null, { within }).append("device", { id: device.id, sub, kind: "app", label: device.label, sign_key: device.signKey }), { log: "Unhandled", message: "put on a bound lock" });
      yield* within.wait(Effect.ignore(read(inner, ws), { log: "Unhandled", message: "bound lock read" }));
    }
  });
}

/// A device this one just took off its person's own lock (`run`'s removeDevice, adb.ts `personalRemove`, within
/// `withBound`): taken out of each workspace's lock where the person bound it and this device signs for them, so it is
/// let in there no more and no longer listed. `keepToPerson` would get there too, but only once it has read their lock,
/// which it must not decide on unread; what this device itself signed off it needs no reading to know, and the person
/// waits on it: one ASKED_MS for all of it, what no station took by then pending (see `ASKED_MS`; 2026-11-12: with the one
/// station asleep, 设置 › 安全 listed the device for
/// 75 s after it was taken off, and for good with the cloud's reads unanswered). An entry refused (another device's got
/// there first, or what is held here is behind) is let be: the read after says how the lock stands, and `keepToPerson`,
/// run once `withBound` is over, catches up by reading.
export function takeOffBound(inner: Inner, sub: string, id: string): Effect.Effect<void> {
  return Effect.gen(function* () {
    const within = asked(inner);
    for (const [ws, owner] of inner.workspaces.owned()) {
      const at = owner === sub ? signsBound(inner, ws) : null;
      const d = at === null ? undefined : live(fold(at.h.entries).devices.get(id), now(inner));
      if (at === null || d === undefined || d.sub !== sub || d.kind !== "app" || id === at.base) continue;
      yield* Effect.ignore(new Lock(inner, ws, sub, null, { within }).append("device.remove", { id }), { log: "Unhandled", message: "taken off a bound lock" });
      yield* within.wait(Effect.ignore(read(inner, ws), { log: "Unhandled", message: "bound lock read" }));
    }
  });
}

/// This device doing the workspaces' half of a change to its person's lock itself (`takeOffBound`, `putOnBound`), by
/// person: `keepToPerson` does nothing for them meanwhile, and runs once for each of their workspaces after the last
/// such ends, to catch up what came meanwhile by reading. Both would sign the same entry at one place of the
/// workspace's lock: the one the stations refused then is signed again or let be (`Lock.append`, `#lost`).
const boundBy = new WeakMap<Inner, Map<string, number>>();
export function withBound<A, E>(inner: Inner, sub: string, work: Effect.Effect<A, E>): Effect.Effect<A, E> {
  return Effect.suspend(() => {
    let counts = boundBy.get(inner);
    if (counts === undefined) boundBy.set(inner, (counts = new Map()));
    const by = counts;
    by.set(sub, (by.get(sub) ?? 0) + 1);
    return Effect.ensuring(work, Effect.sync(() => {
      const left = (by.get(sub) ?? 1) - 1;
      if (left > 0) return void by.set(sub, left);
      by.delete(sub);
      for (const [ws, owner] of inner.workspaces.owned()) if (owner === sub) inner.runner.fork(keepToPerson(inner, ws));
    }));
  });
}

/// The person's app devices in the workspace's lock kept to the ones on their own lock, where they bound it: one taken
/// off their lock, or there from before the binding and never put on it, is taken out of the workspace's lock, so it
/// neither signs there nor has its vault's box taken as theirs (a web page holds no key of their lock: kept); one on
/// their lock that this one lacks, or holds as not signing, is put in with the key it signs with in another workspace
/// of theirs bound to it (`signKeysElsewhere`), or else with the one their lock's chain records for it (each device
/// says it there as it is put on, and says it again when it signs there next: `PersonalLock.signKeys`), so it signs
/// here too: one no workspace's lock ever held with its key (approved where the person had bound none, or before this
/// workspace bound it) is not left signing nothing. Their lock is read first, so a device just put on it is not taken
/// for gone. Done by a device on it that signs for them; tried as bindPerson is, no timer of its own. It is for what
/// this device learns by reading; a device it takes off their lock itself is `takeOffBound`'s, done at once, and while
/// it does (`withBound`) this waits.
const keeping = new WeakMap<Inner, Set<string>>();
export function keepToPerson(inner: Inner, ws: string): Effect.Effect<void> {
  return Effect.gen(function* () {
    // (this device doing it itself: run again once it is done, `withBound`)
    const sub = inner.workspaces.owner(ws);
    if (sub !== null && (boundBy.get(inner)?.get(sub) ?? 0) > 0) return;
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
        // (what their chain records, only for a device this lock lacks or holds as not signing: a key it holds may be
        // newer than the chain's, said there since and not yet said again on the chain, and is not written over)
        const keys = signKeysElsewhere(inner, ws, at.sub);
        for (const [id, d] of personal.signKeys(at.sub)) {
          if (!keys.has(id) && typeof live(inLock.get(id), now(inner))?.sign_key !== "string") keys.set(id, d);
        }
        let put = 0;
        for (const [id, d] of keys) {
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
/// Taken before what the person's own chain records (keepToPerson): a workspace's lock is what its stations go by.
function signKeysElsewhere(inner: Inner, ws: string, sub: string): Map<string, { sign_key: string; label: string }> {
  const keys = new Map<string, { sign_key: string; label: string }>();
  const at = now(inner);
  for (const [other, owner] of inner.workspaces.owned()) {
    const h = held(inner, other);
    if (other === ws || owner !== sub || !h?.head || !stateOf(inner, other, h.entries).persons.has(sub)) continue;
    let lock: Checked;
    try {
      lock = checkLock(h.entries, at);
    } catch {
      continue;
    }
    const labels = stateOf(inner, other, h.entries).devices;
    for (const d of lock.devices.values()) {
      if (d.sub !== sub || d.kind !== "app" || !d.own || typeof d.sign_key !== "string" || live(d, at) === undefined) continue;
      keys.set(d.id, { sign_key: d.sign_key, label: str(get(labels.get(d.id), "label")) ?? "" });
    }
  }
  return keys;
}

/// A person's app device in a workspace's lock, as that lock (checked here) has it: theirs, their own, live, signing
/// there with `sign_key`. `by`: the device whose key signed the entry that gave it that key (it approved it face to face),
/// `bySub` whose that is, `byKey` the key it signed with; none for the genesis's signer, one a passkey put in, or where
/// it is not plain which device signed (two held the key) or that one does not stand as it did then (taken out, put in
/// again by someone else, signing with another key now: what the rules would not take from it now is not taken as its
/// word). The genesis's other devices of the person's whose signer is theirs are put in by it. `since`: the entry its
/// standing began at. `said`: the key it would be on the person's own lock with, as it last said itself there
/// (`person_key` in an entry of its own, signed with its key; the rules read no more of a device than they know, and
/// `fold` drops it), said since its standing began.
export type OwnDevice = { id: string; label: string; sign_key: string; by: string | null; bySub: string | null; byKey: string | null; since: number; said: string | null };
export type OwnStandings = { devices: ReadonlyMap<string, OwnDevice> };
const PERSON_KEY = /^ed25519:[0-9a-f]{64}$/;

/// The person `sub`'s devices in a workspace's lock (`entries`) at `at` (unix seconds), by id. None where the lock does
/// not check out or is turned off.
export function ownStandings(entries: readonly Entry[], sub: string, at: number): OwnStandings {
  // (a lock held is replaced whole, never changed in place: what it said of a person at a second it says again, read
  // only; each read of a lock, and each of its hooks, asks)
  const was = standingsOf.get(entries);
  if (was !== undefined && was.sub === sub && was.at === at) return was.out;
  const out = standingsAt(entries, sub, at);
  standingsOf.set(entries, { sub, at, out });
  return out;
}
const standingsOf = new WeakMap<readonly Entry[], { sub: string; at: number; out: OwnStandings }>();

function standingsAt(entries: readonly Entry[], sub: string, at: number): OwnStandings {
  const devices = new Map<string, OwnDevice>();
  let lock: Checked;
  try {
    lock = checkLock([...entries], at);
  } catch {
    return { devices };
  }
  if (lock.disabled) return { devices };
  // Each device's key as the entries set it, in order: who gave it the one it has, and what it said of itself since.
  const keys = new Map<string, { sub: unknown; kind: unknown; sign_key: string | null }>();
  const put = new Map<string, { by: string | null; byKey: string | null; since: number }>();
  const said = new Map<string, string>();
  const holder = (key: unknown): string | null => {
    const ids = [...keys].filter(([, d]) => d.kind === "app" && d.sign_key === key).map(([id]) => id);
    return ids.length === 1 ? ids[0]! : null;
  };
  const gone = (id: string) => {
    keys.delete(id);
    put.delete(id);
    said.delete(id);
  };
  entries.forEach((e, i) => {
    const b = (e.body ?? {}) as J;
    if (e.kind === "genesis") {
      // The device whose key signed it (none where a passkey did): its person's other devices it names put in by it.
      const signedWith = str(e.sig?.key);
      const signer = arr(b.devices).find((d) => typeof d?.id === "string" && d.kind === "app" && signedWith !== null && str(d.sign_key) === signedWith);
      for (const d of arr(b.devices)) {
        if (typeof d?.id !== "string") continue;
        keys.set(d.id, { sub: d.sub, kind: d.kind, sign_key: str(d.sign_key) });
        if (str(d.sign_key) === null) continue;
        const bySigner = signer !== undefined && d.sub === signer.sub && d.id !== signer.id;
        put.set(d.id, { by: bySigner ? signer.id : null, byKey: bySigner ? signedWith : null, since: 0 });
      }
    } else if (e.kind === "device" && typeof b.id === "string") {
      const was = keys.get(b.id)?.sign_key ?? null;
      const key = str(b.sign_key);
      // (itself, keeping its key: what it says of itself, its standing as it was)
      if (key !== null && key === was && e.sig?.key === was) {
        if (typeof b.person_key === "string" && PERSON_KEY.test(b.person_key)) said.set(b.id, b.person_key);
      } else if (key !== was) {
        put.delete(b.id);
        said.delete(b.id);
        if (key !== null) put.set(b.id, { by: holder(e.sig?.key), byKey: str(e.sig?.key), since: i });
      }
      keys.set(b.id, { sub: b.sub, kind: b.kind, sign_key: key });
    } else if (e.kind === "device.remove" && typeof b.id === "string") gone(b.id);
    else if (e.kind === "member.remove") for (const [id, d] of [...keys]) if (d.sub === b.sub) gone(id);
  });
  const labels = fold([...entries]).devices;
  for (const d of lock.devices.values()) {
    const p = put.get(d.id);
    if (d.sub !== sub || d.kind !== "app" || !d.own || typeof d.sign_key !== "string" || live(d, at) === undefined || p === undefined || keys.get(d.id)?.sign_key !== d.sign_key) continue;
    // (the device that signed, as the lock stands: its own, with the key it signed with)
    const by = p.by === null ? undefined : lock.devices.get(p.by);
    const vouched = by !== undefined && by.own && by.kind === "app" && by.sign_key === p.byKey;
    devices.set(d.id, { id: d.id, label: str(get(labels.get(d.id), "label")) ?? "", sign_key: d.sign_key, by: vouched ? by.id : null, bySub: vouched ? by.sub : null, byKey: vouched ? p.byKey : null, since: p.since, said: said.get(d.id) ?? null });
  }
  return { devices };
}

/// The devices up the `by` links from `id` in what a workspace's lock says of a person's (ownStandings), nearest first,
/// each the person's own; none past one that is not among them, or once one comes round again.
export function ancestors(own: OwnStandings, id: string): OwnDevice[] {
  const out: OwnDevice[] = [];
  const passed = new Set([id]);
  let d = own.devices.get(id);
  while (d !== undefined && d.by !== null && !passed.has(d.by)) {
    passed.add(d.by);
    d = own.devices.get(d.by);
    if (d !== undefined) out.push(d);
  }
  return out;
}

/// The workspaces' locks in safe mode this device holds for `sub`, each with what it says of their devices.
function ownLocks(inner: Inner, sub: string): { ws: string; h: Held; f: Folded; own: OwnStandings }[] {
  const out: { ws: string; h: Held; f: Folded; own: OwnStandings }[] = [];
  for (const [ws, owner] of inner.workspaces.owned()) {
    const h = held(inner, ws);
    // (a chain that moved vouches for nothing more: what its entries said is no longer in force)
    if (owner !== sub || !h?.head || movedHere(inner, ws)) continue;
    const f = fold(h.entries);
    if (!f.disabled) out.push({ ws, h, f, own: ownStandings(h.entries, sub, now(inner)) });
  }
  return out;
}

/// What a person's own lock reads of the workspaces' locks (personal-lock.ts `approved`, `vouchers`): the devices to
/// put on it as it stands (`approvedIn`), this device's own id and signing key telling which is this one; the keys said
/// up this device's lineages (`vouchersIn`).
export function ownLockEnv(inner: Inner): Pick<PersonalEnv, "approved" | "vouchers"> {
  return {
    approved: (sub, chain) => approvedIn(ownLocks(inner, sub).map((l) => l.own), sub, { id: bases.get(inner) ?? null, signKey: signerOf(inner) }, chain),
    vouchers: (sub) => {
      const base = bases.get(inner) ?? null;
      return base === null ? new Set<string>() : vouchersIn(ownLocks(inner, sub).map((l) => l.own), sub, base);
    },
  };
}

/// Of what workspaces' locks say of `sub`'s devices (ownStandings): those to put on their own lock as it stands
/// (`chain`), each once (by id and by key). Each said the key it would be on it with; was put in by a device whose
/// signing key, as it signed, is one the chain records for a device on it (`signers`: only that device's holder signs
/// with it, while a device id is anyone's to write under a key of their own); and will take the chain once on it, as
/// `vouchersIn` has it there: up its lineage is this device (`me`, by its id and the key it signs with) or one whose
/// said key signed an entry of the chain (`signed`). One put on that would not take it would be let in by the stations
/// once the lock is bound, yet hold itself as not let in. None whose id or key was `ever` on it.
export function approvedIn(
  locks: readonly OwnStandings[],
  sub: string,
  me: { id: string | null; signKey: string | null },
  chain: { signers: ReadonlySet<string>; signed: ReadonlySet<string>; ever: { ids: ReadonlySet<string>; keys: ReadonlySet<string> } },
): PersonDevice[] {
  const out = new Map<string, PersonDevice>();
  const keys = new Set<string>();
  const takes = (a: OwnDevice) => (me.id !== null && me.signKey !== null && a.id === me.id && a.sign_key === me.signKey) || (a.said !== null && chain.signed.has(a.said));
  for (const own of locks) {
    for (const d of own.devices.values()) {
      if (d.said === null || d.by === null || d.bySub !== sub || d.byKey === null || !chain.signers.has(d.byKey)) continue;
      if (chain.ever.ids.has(d.id) || chain.ever.keys.has(d.said) || out.has(d.id) || keys.has(d.said)) continue;
      if (!ancestors(own, d.id).some(takes)) continue;
      out.set(d.id, { key: d.said, id: d.id, label: d.label, sign_key: d.sign_key });
      keys.add(d.said);
    }
  }
  return [...out.values()];
}

/// Of what workspaces' locks say of a person's devices (ownStandings, of `sub`'s): the keys said by the devices up
/// `base`'s lineage in each (the one that put it in, the one that put that one in, and so on, each theirs). Every
/// lineage of a person's own devices is taken as theirs, a member's too, so that nobody approves their devices again
/// (the user, 2026-11-10). What that costs: a workspace's owner or admin who rewrites its lock (takes a member out and
/// makes them one again, which clears the member's `signed` in rules/src/lock/lock.mbt, puts a device of their own in
/// as the member's first and the member's real devices back in under it: their signing keys are public) gets that
/// device taken as the member's by the member's devices that have no lock pinned yet; the entries that did it stay in
/// the workspace's lock.
export function vouchersIn(locks: readonly OwnStandings[], _sub: string, base: string): Set<string> {
  const out = new Set<string>();
  for (const own of locks) for (const a of ancestors(own, base)) if (a.said !== null) out.add(a.said);
  return out;
}

/// Whether the stations of a workspace listed a device of `sub`'s as come to them lately (GET /lock/devices: the last
/// SEEN_SECS, station/src/mesh/seen-devices.ts); not knowing (no list held) is as seen.
const seenThere = (h: Held, sub: string, id: string): boolean => h.seen == null || h.seen.some((r) => r?.sub === sub && (r.base === id || r.device === id));

/// The one of `sub`'s devices to begin their lock, of the workspaces' locks that hold devices of theirs (`relevant`), as
/// this device (`base`) sees them: of the devices whose standing began first in one of them (since, then id; one that
/// has not come to the stations in SEEN_SECS passed over: an old machine never taken out would keep the person from ever
/// having a lock) that stand in every one, the one with the smallest id. Two devices, each first in a workspace of its
/// own, would each begin a chain; every one counted holds the same locks, so they agree on one. None where no such
/// device stands in them all: nobody begins then (a device approved into the others' workspaces later may).
function firstToBegin(relevant: readonly { h: Held; own: OwnStandings }[], sub: string, base: string): string | null {
  const tops = new Set<string>();
  for (const l of relevant) {
    let top: OwnDevice | null = null;
    for (const d of l.own.devices.values()) {
      if (d.id !== base && !seenThere(l.h, sub, d.id)) continue;
      if (top === null || d.since < top.since || (d.since === top.since && d.id < top.id)) top = d;
    }
    if (top !== null) tops.add(top.id);
  }
  let first: string | null = null;
  for (const id of tops) if (relevant.every((l) => l.own.devices.has(id)) && (first === null || id < first)) first = id;
  return first;
}

/// Every person in safe mode comes to have a lock of their own holding their trusted app devices, nobody asked, and
/// then bindPerson binds it by itself (people are never asked to tell the two apart: the root AGENTS.md, To people there
/// is one safe mode). This device, one of the person's in a workspace's lock that signs for them there, on the
/// still.fail cloud's account system, once every workspace of theirs has its lock read (one not read may hold a device
/// of theirs that comes first, or a lock bound): where they have no lock of their own and none is bound in any of their
/// workspaces, the one of their devices to begin it (`firstToBegin`) begins one (personal-lock.ts `beginQuietly`), its
/// key made now and its seed in hand, once each other device of theirs in those locks said the key it would be on it
/// with or has not come to the stations lately (one that has come and not said would be left off, and keep it from
/// being bound), and once every station of theirs seen lately answered a read of their lock (`personalStations`
/// `answered`). Every device, the one that began once it did too, says there the key it is or would be on that lock
/// with (a device entry of its own, signed with the key the workspace's lock knows it by, `person_key`): the devices on
/// the lock put on those below them in their lineage as they next hold their seed (personal-lock.ts `#addApproved`,
/// `approvedIn`), and each takes the lock as it hears it where a device up its lineage signed an entry of it,
/// knowing their keys by what they said here (`#putOnBy`, `vouchersIn`; a chain's own ids prove nothing). The one to
/// begin says nothing while it waits to: its key made, it could not begin without asking; nor does anyone where they
/// have no lock and no device of theirs is the one to begin, or the one to begin cannot with no one asked. The one that
/// began says its key in each lock where another device of theirs stands, the devices it put on knowing its key only
/// by that; once on the lock, others say it only where another device of theirs said its key, which may take the lock
/// from it. A device not on their lock says nothing where the
/// person bound a lock of their own already: its stations go by that lock for their app devices, and an entry this
/// device signed there since would keep keepToPerson from taking it out. Per person, once for each head of their locks
/// and what holds the first back; one at a time, what asks meanwhile done after. No timer of its own.
const owning = new WeakMap<Inner, Map<string, { again: boolean }>>();
const ownTried = new WeakMap<Inner, Set<string>>();
export function ownLockFor(inner: Inner, ws: string): Effect.Effect<void> {
  return Effect.suspend(() => {
    const sub = inner.workspaces.owner(ws);
    // (a host that seals nothing keeps no key of a person's lock: personal-lock.ts `#madeKey`)
    if (inner.provider.kind !== "stillfail" || sub === null || !inner.host.appKeys || !inner.host.secureSet) return Effect.void;
    let running = owning.get(inner);
    if (running === undefined) owning.set(inner, (running = new Map()));
    const was = running.get(sub);
    if (was !== undefined) {
      was.again = true;
      return Effect.void;
    }
    const state = { again: true };
    const all = running;
    all.set(sub, state);
    return Effect.ensuring(
      Effect.gen(function* () {
        while (state.again) {
          state.again = false;
          yield* Effect.ignore(ownLockOnce(inner, sub), { log: "Unhandled", message: "own lock for a person in safe mode" });
        }
      }),
      Effect.sync(() => void all.delete(sub)),
    );
  });
}

function ownLockOnce(inner: Inner, sub: string): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const signer = signerOf(inner);
    const base = bases.get(inner) ?? null;
    const personal = inner.adb.personal();
    if (signer === null || base === null) return;
    // (a workspace of theirs with no lock record is not known, not without a lock: read, it asks again, `hold`)
    if (inner.workspaces.owned().some(([ws, owner]) => owner === sub && held(inner, ws) === null)) return;
    const locks = ownLocks(inner, sub);
    const mine = locks.filter((l) => l.own.devices.get(base)?.sign_key === signer);
    if (mine.length === 0) return;
    const relevant = locks.filter((l) => l.own.devices.size > 0);
    // (on the lock already, with nothing to say where no other device of theirs said its key: nothing to do, nothing read)
    const othersSaid = (l: (typeof locks)[number]) => [...l.own.devices.values()].some((d) => d.id !== base && d.said !== null);
    if (personal.standing(sub) === "member" && !mine.some(othersSaid)) return;
    // (once for each head of the locks, the person's own as read, and of the devices not said that came lately)
    let tried = ownTried.get(inner);
    if (tried === undefined) ownTried.set(inner, (tried = new Set()));
    const waiting = (l: (typeof locks)[number]) => [...l.own.devices.values()].filter((d) => d.id !== base && d.said === null && seenThere(l.h, sub, d.id)).map((d) => d.id);
    const key = [sub, personal.entries(sub).length, ...locks.map((l) => `${l.ws}:${l.h.head!.hash}:${waiting(l).join(",")}`)].join("/");
    if (tried.has(key)) return;
    tried.add(key);
    const done = tried;
    yield* Effect.tapError(
      Effect.gen(function* () {
        yield* personal.refresh(sub);
        const bound = locks.some((l) => l.f.persons.has(sub));
        let began = false;
        const first = firstToBegin(relevant, sub, base);
        const none = !bound && personal.standing(sub) === "none";
        // (no lock of theirs and no one to begin it: nothing is said, as a key made to say it could begin none later,
        // and no device would put this one on anything)
        if (none && first === null) return;
        if (none && first === base) {
          // (the one to begin, unable to with no one asked, its key made before or the lock naming it by another: it
          // begins as its person is next asked for something, personal-lock.ts `signGrant`; said meanwhile, its key
          // would be read by no one)
          if (mine.length !== relevant.length || !personal.mayBeginQuietly(sub)) return;
          if (relevant.some((l) => waiting(l).length > 0)) return;
          // (its stations not all answering yet, a lock of theirs not known to be none: tried again as a lock is next read)
          if (!(yield* personal.beginQuietly(sub))) {
            done.delete(key);
            return;
          }
          began = true;
        }
        const said = yield* personal.makeKey();
        const member = personal.standing(sub) === "member";
        let failed: CoreError | null = null;
        for (const l of mine) {
          const me = l.own.devices.get(base)!;
          // (having begun: said wherever another device of theirs stands, those it put on knowing its key only by that.
          // Off their lock, nothing said where it is bound: as said above. On it, said there too: bound before the one
          // that began had said its key (the entry that binds taken first, this one refused for it), the devices it put
          // on never knew the chain theirs, and held themselves as not let in.)
          if (me.said === said || (!member && l.f.persons.has(sub)) || (member && !(began ? l.own.devices.size > 1 : othersSaid(l)))) continue;
          const put = new Lock(inner, l.ws, sub, null).append("device", { id: base, sub, kind: "app", label: me.label, sign_key: me.sign_key, person_key: said });
          const r = yield* Effect.result(Effect.andThen(put, read(inner, l.ws)));
          if (r._tag === "Failure") failed = r.failure;
        }
        if (failed !== null) return yield* Effect.fail(failed);
      }),
      () => Effect.sync(() => void done.delete(key)),
    );
  });
}

/// A person's own lock moved on (a device taken off): each station where it is bound told as it stands.
export function tellStations(inner: Inner, sub: string, chain: Entry[]): void {
  for (const [ws, owner] of inner.workspaces.owned()) {
    const h = held(inner, ws);
    if (owner !== sub || !h?.head) continue;
    const f = stateOf(inner, ws, h.entries);
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

/// The last entries of the lock a station refusing this device told, as they go on from an entry of the lock held here
/// (the station took each), so a device taken out hears so with no cloud to read it of: held where they go on from its
/// head, else kept with it, the rules choosing (`hold`), as a read's are.
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
  const known = new Set([...was.entries, ...(was.aside ?? [])].map(hashOf));
  if (tail.every((e) => known.has(hashOf(e))) || entryHash(entries[0]!) !== was.head.genesis) return;
  const last = entries[entries.length - 1]!;
  inner.runner.fork(hold(inner, ws, sub, { seq: last.seq, hash: entryHash(last), genesis: was.head.genesis }, entries, was.seen ?? null));
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

/// The body of a statement `e` of a person's own log kept here, and its workspace: one of the workspaces that person
/// is signed in to here.
function bodyOfEntry(inner: Inner, e: Entry): { ws: string; body: unknown } | null {
  const h = get(e.body, "h");
  const sub = e.ws.startsWith("person:") ? e.ws.slice(7) : null;
  for (const [ws, owner] of inner.workspaces.owned()) {
    if (owner !== sub) continue;
    const b = bodiesHeld(inner, ws).find((x) => bodyHash(x) === h);
    if (b !== undefined) return { ws, body: b };
  }
  return null;
}

/// 16 random bytes, hex: a statement's salt.
function saltHex(inner: Inner): string {
  const b = new Uint8Array(16);
  inner.host.randomBytes(b);
  return hex(b);
}

/// The stations of `ws` a statement's body goes to (the root AGENTS.md, The cloud is the account system: a body is only
/// its workspace's): those the list in force here names, and one a `station` body among `bodies` takes in, each one the
/// workspace's view lists (what reaches it). Never one the view alone names: the cloud saying a station is the
/// workspace's gives it no statement.
function bodyStations(inner: Inner, ws: string, bodies: readonly unknown[]): string[] {
  const named = new Set(stateOf(inner, ws).stations.keys());
  for (const b of bodies) if (get(b, "kind") === "station" && typeof get(b, "key") === "string") named.add(get(b, "key") as string);
  return arr(get(view(inner, ws), "stations")).flatMap((s) => (typeof s?.id === "string" && named.has(s.id) ? [s.id as string] : []));
}

/// The bodies of statements this device signed in `ws`, kept beside its lock as they are signed (`lockBodies`): it
/// keeps what it said, so the state made here counts each as soon as its entry is on the chain pinned.
function keepMine(inner: Inner, ws: string, bodies: readonly unknown[]): void {
  const kept = bodiesHeld(inner, ws);
  const have = new Set(kept.map((b) => bodyHash(b)));
  const taken = bodies.filter((b) => {
    const h = bodyHash(b);
    if (h === null || have.has(h)) return false;
    have.add(h);
    return true;
  });
  if (taken.length > 0) inner.data.put("lockBodies", ws, { bodies: [...kept, ...taken] });
}

/// A person's own lock with statements of `ws` on it brought (personal-lock.ts `say`, `#deliver`): the chain and their
/// bodies to the stations of `ws` (`bodyStations`), each asked on that workspace's address, as only a connection of the
/// workspace is given or takes its bodies; the chain alone to their other stations, not waited on. How many of the
/// workspace's stations took the chain and every body (a body refused there, or a station of another workspace taking
/// the chain, is no taking: pending); 0 where none could be asked, never the cloud's.
function bringStated(inner: Inner, sub: string, chain: Entry[], within: Asked | undefined, stated: Stated): Effect.Effect<number | null | { later: Effect.Effect<number | null, CoreError> }, CoreError> {
  const ids = bodyStations(inner, stated.ws, stated.bodies);
  const at = ids.map((id) => new StationAddr(stated.ws, id));
  const mine = new Set(ids);
  for (const other of personStations(inner, sub)) {
    if (other.workspace === stated.ws && mine.has(other.station)) continue;
    inner.runner.fork(Effect.ignore(inner.stations.requests.call(other, "POST", "/lock/person", { chain }, { quiet: true }), { log: "Unhandled", message: "personal lock brought to a station of another workspace" }));
  }
  const hashes = new Set(stated.bodies.map((b) => bodyHash(b)));
  const answering = answersOf(inner, at.map((a) => inner.stations.requests.call(a, "POST", "/lock/person", { chain, bodies: stated.bodies }, { quiet: true })), tookOrRefused, at.map(String));
  const decide = (answers: Result.Result<unknown, CoreError>[]): Effect.Effect<number | null, CoreError> => {
    const took = answers.filter((r) => r._tag === "Success" && !arr(get(r.success, "refused")).some((x) => hashes.has(get(x, "hash") as string))).length;
    if (took > 0) {
      const shown = personShownOf(inner).shown.get(sub) ?? new Set<string>();
      personShownOf(inner).shown.set(sub, shown);
      for (const e of chain) shown.add(hashOf(e));
      return Effect.succeed(took);
    }
    const refused = answers.find((r) => r._tag === "Failure" && r.failure.status === 409);
    return refused !== undefined && refused._tag === "Failure" ? Effect.fail(new CoreError("lock_refused", refused.failure.message, 409)) : Effect.succeed(0);
  };
  if (within === undefined) return Effect.flatMap(answering, decide);
  return Effect.flatMap(within.first(answering), (r): Effect.Effect<number | null | { later: Effect.Effect<number | null, CoreError> }, CoreError> =>
    "now" in r ? decide(r.now) : Effect.succeed({ later: Effect.flatMap(r.later, decide) }));
}

/// The stations that answered a read of each person's own lock this run (`personalStations`), by id, per core.
const answeredOf = new WeakMap<Inner, Map<string, Set<string>>>();
/// Of each person's own lock, per core (`personalStations` `carry`): what each station showed at its last read (by its
/// address, the hashes of the chains it keeps), the entries a station showed or took this run, what was carried where.
const personShown = new WeakMap<Inner, { last: Map<string, Map<string, Set<string>>>; shown: Map<string, Set<string>>; carried: Set<string> }>();
function personShownOf(inner: Inner) {
  let m = personShown.get(inner);
  if (m === undefined) personShown.set(inner, (m = { last: new Map(), shown: new Map(), carried: new Set() }));
  return m;
}

/// A person's own lock as their stations keep it (personal-lock.ts `stations`), not the cloud: read of each station of
/// their workspaces this device reaches, and brought to each. Each station that answers a read is noted (an answer, or
/// a refusal of this device, `lock_unconfirmed`: a station recent enough to keep such chains tells them as it refuses),
/// as it comes, a late one too: `answered` is whether every station of theirs the control plane saw in SEEN_SECS did,
/// and one at least. A lock of theirs kept only by a station that did not answer would get a second one begun beside
/// it; one the control plane has not seen for a month is not waited for.
export function personalStations(inner: Inner): NonNullable<PersonalEnv["stations"]> {
  const heardOf = (sub: string): Set<string> => {
    let m = answeredOf.get(inner);
    if (m === undefined) answeredOf.set(inner, (m = new Map()));
    let heard = m.get(sub);
    if (heard === undefined) m.set(sub, (heard = new Set()));
    return heard;
  };
  const answered = (sub: string): boolean => {
    const heard = answeredOf.get(inner)?.get(sub);
    if (heard === undefined || heard.size === 0) return false;
    const at = now(inner);
    for (const [ws, owner] of inner.workspaces.owned()) {
      if (owner !== sub) continue;
      for (const s of arr(get(view(inner, ws), "stations"))) {
        if (typeof s?.id === "string" && typeof s.last_seen === "number" && at - s.last_seen <= SEEN_SECS && !heard.has(s.id)) return false;
      }
    }
    return true;
  };
  return {
    names: (sub) => personStations(inner, sub).map((at) => str(arr(get(view(inner, at.workspace), "stations")).find((s) => s?.id === at.station)?.name) || at.station.slice(0, 8)),
    read: (sub, only) => {
      const asked = personStations(inner, sub).filter((at) => only === undefined || at.toString() === only);
      const heard = heardOf(sub);
      const m = personShownOf(inner);
      const last = m.last.get(sub) ?? new Map<string, Set<string>>();
      m.last.set(sub, last);
      const shown = m.shown.get(sub) ?? new Set<string>();
      m.shown.set(sub, shown);
      // (what it keeps, for `carry`: the entries of every chain it answered with)
      const kept = (at: StationAddr, answer: unknown) => Effect.sync(() => {
        const has = new Set<string>();
        for (const c of arr(get(answer, "chains"))) for (const e of arr(get(c, "entries"))) {
          try {
            has.add(hashOf(e as Entry));
          } catch {
            // (not an entry: nothing of it is kept)
          }
        }
        last.set(at.toString(), has);
        for (const h of has) shown.add(h);
      });
      const ask = (at: StationAddr) => {
        const noted = Effect.sync(() => {
          if (heard.has(at.station)) return;
          const before = answered(sub);
          heard.add(at.station);
          // The last of them to answer (a machine that was asleep, reached again): the one to begin their lock, held
          // back for it alone, is asked again now. Nothing else would ask it until a lock of theirs next moved.
          if (!before && answered(sub)) inner.runner.fork(ownLockFor(inner, at.workspace));
        });
        return Effect.tapError(Effect.tap(inner.stations.requests.call(at, "GET", "/lock/person", null, { quiet: true }), (answer) => Effect.andThen(noted, kept(at, answer))), (e) => (e.code === "lock_unconfirmed" ? noted : Effect.void));
      };
      return Effect.map(answersOf(inner, asked.map(ask), () => OTHERS_MS, asked.map(String)), (answers) => {
        const ok = answers.filter((r) => r._tag === "Success");
        const refused = answers.some((r) => r._tag === "Failure" && r.failure.code === "lock_unconfirmed");
        // What the refusals told of it (this device not let in there yet), not the cloud's: alone where all refused, else
        // beside what the others kept, so a chain told only in a refusal is taken now.
        const told = refused ? refusedChains.get(inner)?.get(sub) : undefined;
        if (ok.length === 0) return told ?? null;
        const kept = ok.flatMap((r) => arr(get(r.success, "chains")).map((c) => arr(get(c, "entries")) as Entry[]));
        return told === undefined ? kept : [...kept, ...told];
      });
    },
    answered,
    bring: (sub, chain, within, stated) => {
      if (stated !== undefined) return bringStated(inner, sub, chain, within, stated);
      const asked = personStations(inner, sub);
      // (done once one took it: the others are brought it all the same, and keep each other level)
      const answering = answersOf(inner, asked.map((at) => inner.stations.requests.call(at, "POST", "/lock/person", { chain }, { quiet: true })), tookOrRefused, asked.map(String));
      const decide = (answers: Result.Result<unknown, CoreError>[]): Effect.Effect<number | null, CoreError> => {
        const took = answers.filter((r) => r._tag === "Success").length;
        if (took > 0) {
          const shown = personShownOf(inner).shown.get(sub) ?? new Set<string>();
          personShownOf(inner).shown.set(sub, shown);
          for (const e of chain) shown.add(hashOf(e));
          return Effect.succeed(took);
        }
        // Refused where it was heard (another device's entry got there first): said so, as the cloud's refusal was.
        // Else none took it (0), or none could be asked (null: they are none, a person's lock no station keeps).
        const refused = answers.find((r) => r._tag === "Failure" && r.failure.status === 409);
        return refused !== undefined && refused._tag === "Failure" ? Effect.fail(new CoreError("lock_refused", refused.failure.message, 409)) : Effect.succeed(asked.length === 0 ? null : 0);
      };
      if (within === undefined) return Effect.flatMap(answering, decide);
      // A call a person waits on: as the stations stand at its wait's end, else the way to hear them still, the cloud
      // asked meanwhile (personal-lock.ts `#append`, see ASKED_MS).
      return Effect.flatMap(within.first(answering), (r): Effect.Effect<number | null | { later: Effect.Effect<number | null, CoreError> }, CoreError> =>
        "now" in r ? decide(r.now) : Effect.succeed({ later: Effect.flatMap(r.later, decide) }));
    },
    kept: (ws, bodies) => keepMine(inner, ws, bodies),
    // (the model's `resign` with `reuse`: the same body where its `prev` is a statement of its tag before it on `after`;
    // else what it said, its cancels as signed, with `prev` as `make` names it now and a salt anew)
    restated: (e, after) => {
      const of = bodyOfEntry(inner, e);
      if (of === null || after.length === 0) return null;
      const prev = get(of.body, "prev");
      const t = wsTag(of.ws, entryHash(after[0]!));
      if (prev === null || after.some((x) => x.kind === "ws" && get(x.body, "t") === t && get(x.body, "h") === prev)) return of;
      const { prev: _p, salt: _s, ...said } = of.body as Record<string, unknown>;
      const fresh = { ...said, prev: prevOf(of.ws, after, byHash(bodiesHeld(inner, of.ws))), salt: saltHex(inner) };
      keepMine(inner, of.ws, [fresh]);
      return { ws: of.ws, body: fresh };
    },
    bodyOf: (e) => bodyOfEntry(inner, e),
    wsNames: (ws) => {
      const names = arr(get(view(inner, ws), "stations"));
      return bodyStations(inner, ws, []).map((id) => str(names.find((s) => s?.id === id)?.name) || id.slice(0, 8));
    },
    // The chain pinned, as far as each entry of it a station showed or took this run (never one only this device signed
    // and no station took), brought with `keep` to each station of theirs read last that lacks some of it and keeps what
    // a device brings as another keeper's (its GET /lock's `serves` `forks`, `Part.forks`): so the stations of
    // workspaces that do not know each other come to one chain of the person's lock, by this device. Once for each
    // station and chain this run, forked, never tried again on a timer.
    carry: (sub, chain) => {
      const m = personShownOf(inner);
      const shown = m.shown.get(sub);
      const last = m.last.get(sub);
      if (shown === undefined || last === undefined) return;
      let n = 0;
      while (n < chain.length && shown.has(hashOf(chain[n]!))) n++;
      const kept = chain.slice(0, n);
      if (kept.length === 0) return;
      const head = hashOf(kept[kept.length - 1]!);
      for (const at of personStations(inner, sub)) {
        const has = last.get(at.toString());
        if (has === undefined || !part(inner, at.workspace).forks.has(at.station) || kept.every((e) => has.has(hashOf(e)))) continue;
        const what = `${sub}/${at.toString()}/${head}`;
        if (m.carried.has(what)) continue;
        m.carried.add(what);
        inner.runner.fork(Effect.ignore(inner.stations.requests.call(at, "POST", "/lock/person", { chain: kept, keep: true }, { quiet: true }), { log: "Unhandled", message: "personal lock carried to a station" }));
      }
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
  const force = inForceOf(inner, ws, h?.entries ?? []);
  const f = force.f;
  const locked = h?.head != null && !f.disabled;
  // Moved, and its settings not here yet (`waiting`): on, nobody and nothing listed, nothing asked of this device (no
  // pairing: it is not known to be left out). The nearest the topic has to "not read yet": no words of its own.
  const waits = force.said === "waiting";
  const sub = inner.workspaces.owner(ws);
  const at = now(inner);
  const signer = signers.get(inner) ?? null;
  const people = new Map<string, J>(arr(get(v, "members")).map((m) => [m.sub, m]));
  // Its person bound a lock of their own here, and this app is not on it as far as it knows (`own`): what it asks to
  // join is that lock (`run`'s pair). Known to be off it (`off`: their lock read, this device not on it; not merely not
  // read yet, as an app just started is), it waits here whatever this lock names: the stations let it in on that alone.
  const own = base !== null && locked && !waits && offOwnLock(inner, ws);
  const off = own && sub !== null && inner.adb.personal().standing(sub) === "outside";
  const mine = off ? undefined : base ? (live(f.devices.get(base), at) ?? (onBoundPerson(inner, ws) ? { id: base, sub: inner.workspaces.owner(ws), kind: "app" } : undefined)) : undefined;
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
      // taken out by this device, where it signs: the viewer's own others. Someone else's is theirs alone to take out
      // (owners and admins take the member out; the user, 2026-11-10: a person's devices are their own lock's, which
      // no one else changes, and 移除 beside another's did nothing where they had bound it)
      removable: signs && !mine && d.sub === sub,
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
  // (those added who have not signed in yet are the workspace page's, `added`: no one here to show devices of)
  const members = [...f.members].filter(([s]) => !isPending(s)).map(([s, m]) => ({
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
  const pair = locked && !waits && (mine === undefined || unsigned) ? pairs.mine(inner, own && sub !== null ? personOf(sub) : ws) : null;
  // The devices its try dials here, as people know them (which machine, a phone or a computer), the most lately used
  // first, those showing a code before them: the person opens still.fail on one of those (2026-11-05: "到底是哪个设备会
  // 弹出来呀？", a web page of theirs, or an app not approved, shows nothing). Each a row of the page's list, its name
  // alone (the user, #4213: joined into a sentence, a narrow page broke a name in two; with its app and when it was
  // used under each, 字还是很多).
  if (pair !== null && Array.isArray(pair.approvers)) {
    pair.approvers = pair.approvers
      .map((a: J) => {
        const d = f.devices.get(a.id);
        const v = d === undefined ? null : device(d);
        const { group } = prefs.deviceParts(v?.label ?? "");
        return {
          id: a.id, showing: a.showing === true,
          kind: group !== null && /^(android|ios) /.test(group) ? "phone" : "computer",
          nameText: v?.nameText ?? t("web-pages.security.appDevice"),
          lastSeen: v?.lastSeen ?? null,
        };
      })
      .sort((a: J, b: J) => Number(b.showing) - Number(a.showing) || (b.lastSeen ?? -1) - (a.lastSeen ?? -1));
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
      waiting: locked && !waits && base !== null && mine === undefined,
      ...(unsigned ? { unsigned: true } : {}),
      // (its person's own lock is what it joins: the pair below is that one's)
      ...(own && (mine === undefined || unsigned) ? { ownLock: true } : {}),
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
    // What this device did that no station took yet: not in effect, and nothing above shows it as if it were.
    // (and of their own lock: to people there is one safe mode, and this is the page that says what is not in effect)
    ...pendingFields(pendingRows(inner, ws)),
  };
}

/// A workspace's `lock` topic's `pending`: what this device did in the workspace's lock that no station took yet, then
/// what it did in its person's own lock (`ownPendingRows`).
function pendingRows(inner: Inner, ws: string): PendingRow[] {
  const mine = pendingHeld(inner, ws).filter((x) => x.act !== null);
  return [...mine.map((x) => pendingRowOf(inner, ws, x)), ...ownPendingRows(inner, ws, mine)];
}

/// Of a row of the person's own lock in a workspace's `lock` topic, what its id begins with: `lock.pendingDismiss`
/// drops it of that lock.
const OWN_PENDING = "own:";

/// What is pending of the signed-in person's own lock (the one they bound here; where this lock is off, still theirs),
/// as rows of a workspace's `lock` topic, its id saying whose (`OWN_PENDING`). To people there is one safe mode (the
/// root AGENTS.md): an own device taken off on 设置 › 安全 is taken off that lock first, and that removal pending there
/// alone was said nowhere the person looks. One done in both (`mine`: the same kind on the same device, as taking an
/// own device off signs it in both) is one row, the workspace's.
function ownPendingRows(inner: Inner, ws: string, mine: readonly Pending[]): PendingRow[] {
  const sub = inner.workspaces.owner(ws);
  if (sub === null) return [];
  const personal = inner.adb.personal();
  const shown = personal.pendingShown(sub);
  if (shown.length === 0) return [];
  const ids = new Map([...(personal.chain(sub)?.devices.values() ?? [])].map((d) => [d.key, d.id]));
  const idOf = (e: Entry) => str(get(e.body, "id")) ?? ids.get(str(get(e.body, "key")) ?? "") ?? null;
  return shown
    .filter(({ item }) => {
      // (a statement on its own workspace's topic alone, as a chain entry is; one whose body is not kept here on none)
      if (item.entry.kind === "ws") return bodyOfEntry(inner, item.entry)?.ws === ws;
      const id = idOf(item.entry);
      return id === null || !mine.some((w) => w.entry.kind === item.entry.kind && get(w.entry.body, "id") === id);
    })
    .map(({ row }) => ({ ...row, id: `${OWN_PENDING}${row.id}` }));
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
    // None held here while the cloud's view says the workspace has a lock: this device is behind, not the workspace
    // unlocked. The lock is read first, and held, this is no draft's page any more: it showed the stations keeping the
    // workspace's own lock as keeping another, to be reset on their machines (#5540).
    if (!held(inner, ws)?.head && cloudSays(view(inner, ws))) yield* Effect.ignore(read(inner, ws));
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

/// A `lock.*` call. One ASKED_MS for the call on the stations alone, what none took by then pending (see `ASKED_MS`), but
/// where it names a station (`addStation`, `joinStation`: that one's answer is what it is for).
function run(inner: Inner, c: Of, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const sub = inner.workspaces.owner(c.workspace);
    if (sub === null) return yield* Effect.fail(CoreError.invalid("not a workspace of the signed-in accounts"));
    const within = asked(inner);
    const lock = new Lock(inner, c.workspace, sub, ctx, { byHand: true, within });
    const param = (k: string) => str(c.params[k]) ?? "";
    let result: unknown;
    switch (c.name) {
      // The page: as held once its wait is over; what the read brings later is held and tells the topic (`hold`).
      case "state":
        yield* Effect.ignore(lock.base(), { log: "Unhandled", message: "lock base read" });
        yield* within.wait(Effect.ignore(read(inner, c.workspace), { log: "Unhandled", message: "lock read" }));
        return lockView(inner, c.workspace);
      // The notice that the lock is off, closed for good on this device (prefs `lockNotice`).
      case "dismiss":
        prefs.set(inner.data, { lockNotice: { [c.workspace]: true } }, false, inner.host.nowMs());
        touch(inner, c.workspace);
        return null;
      // A failed pending change, read: dropped (a waiting one stays: it is still to take effect).
      case "pendingDismiss": {
        // (one of the person's own lock, as this topic shows it: dropped of that lock)
        if (param("id").startsWith(OWN_PENDING)) {
          inner.adb.personal().dismissPending(sub, param("id").slice(OWN_PENDING.length));
          return null;
        }
        const items = pendingHeld(inner, c.workspace);
        if (items.some((x) => x.id === param("id") && x.state === "failed")) putPending(inner, c.workspace, items.filter((x) => x.id !== param("id")));
        return null;
      }
      case "toggle": {
        const ex = part(inner, c.workspace).excluded;
        if (ex.has(param("id"))) ex.delete(param("id"));
        else ex.add(param("id"));
        lockSeen(inner).touch(`draft ${c.workspace}`);
        return null;
      }
      case "open":
        result = movedHere(inner, c.workspace) ? yield* onOffMoved(inner, sub, c.workspace, true) : yield* lock.open();
        break;
      // Approved face to face (views/pair.ts): asked, the code typed, given up.
      case "pair":
        // Its person bound a lock of their own here that this device is not on: approved into this one it would still be
        // refused (the stations let their app devices in on that lock alone), so it asks to join that one instead, the
        // same code shown on a device on it (2026-11-10: a new phone approved here went on being refused, 「已经批过了啊」).
        if (offOwnLock(inner, c.workspace)) {
          const sub = inner.workspaces.owner(c.workspace);
          if (sub !== null) return yield* inner.adb.run({ kind: "personalJoin", sub });
        }
        return yield* pairs.run(inner, c.name, c.workspace, c.params);
      case "pairCode":
      case "pairCancel":
        return yield* pairs.run(inner, c.name, c.workspace, c.params);
      case "addStation":
        result = yield* lock.addStation(param("station"), param("code"));
        break;
      case "joinStation":
        result = movedHere(inner, c.workspace) ? yield* stationMoved(inner, sub, c.workspace, param("station")) : yield* lock.joinStation(param("station"));
        break;
      case "renew":
        result = yield* lock.renew(param("device"));
        break;
      case "removeDevice": {
        // Their own app device, where they bound a lock of their own: that lock is what lets it in, so it is taken off
        // that one, and out of this one after it (`takeOffBound`, which reads this lock after: not read again here).
        // Taken out of this lock alone it was let in still, and put back from another workspace's (2026-11-10: 移除 on
        // 设置 › 安全 did nothing that lasted).
        const own = onOwnLock(inner, c.workspace, param("device"));
        if (own !== null) {
          const off = yield* withBound(inner, own.sub, Effect.tap(inner.adb.personal().removeDevice(own.sub, own.key, t("core-misc.personal.reason.remove")), () => takeOffBound(inner, own.sub, param("device"))));
          // (pending on their own lock, or, taken there by a station of another workspace of theirs, in this one's:
          // said so either way, as this workspace's page shows it)
          const here = pendingHeld(inner, c.workspace).find((x) => x.state === "waiting" && x.entry.kind === "device.remove" && get(x.entry.body, "id") === param("device"));
          if (here !== undefined) return { pending: pendingRowOf(inner, c.workspace, here) };
          // (pending on their own lock alone: its row as this workspace's topic shows it, `ownPendingRows`)
          return off === null ? null : { pending: { ...off.pending, id: `${OWN_PENDING}${off.pending.id}` } };
        }
        result = yield* lock.append("device.remove", { id: param("device") });
        break;
      }
      case "disable": {
        // (where the chain moved: an `off` in the root's own log, by its person alone)
        if (movedHere(inner, c.workspace)) {
          result = yield* onOffMoved(inner, sub, c.workspace, false);
          break;
        }
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
    // What changed is read again before the call answers (the pages show it at once), within the call's wait: what it
    // signed is held already (`append`), and a read that comes later tells the pages as it lands.
    yield* within.wait(Effect.ignore(read(inner, c.workspace), { log: "Unhandled", message: "lock read" }));
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

/// Whether a workspace has a lock to read again: one held on here, or the workspace's view naming one (a lock turned
/// on meanwhile is told by it), as `install`'s `stations.also.read` asks. Neither: there is nothing to read, and a
/// person's write is not held up asking the stations for it.
function lockToRead(inner: Inner, ws: string): boolean {
  const was = held(inner, ws);
  return (!!was?.head && !fold(was.entries).disabled) || !!cloudSays(view(inner, ws));
}

/// A station's enrollment in a locked workspace: its commands name the lock's head, which it pins (`--lock`), as the
/// stations this device reaches said it, the lock read again for ASKED_MS at most (see `ASKED_MS`), and as held here
/// past that or where none said it (as the workspace's view says it where none is held). A head a little behind does
/// as well: a station pins any entry of the chain (station/src/cloud/presence.ts checks the hash against every entry).
/// A control plane that keeps no lock (Comma, a cloud from before locks): the commands as they were.
export function enrolled(inner: Inner, _sub: string, ws: string, made: unknown): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    if (inner.provider.kind !== "stillfail" || !lockToRead(inner, ws)) return made;
    yield* asked(inner).wait(Effect.ignore(read(inner, ws), { log: "Unhandled", message: "lock read for an enrollment" }));
    if (movedHere(inner, ws)) return yield* Effect.fail(lockMoved());
    const h = held(inner, ws);
    const on = !!h?.head && !fold(h.entries).disabled;
    // None held on here (a device that has not read it yet, and did not just now) and the workspace's view saying it is
    // locked: its head as the view says it, the cloud's word as where no station answered. Never the commands without
    // it there: they would enroll a station the lock does not protect (#5540).
    const v = view(inner, ws);
    let head = on ? h!.head : get(v, "locked") === true ? readHead(get(v, "lock")) : null;
    if (head === null || !isObject(made)) return made;
    // Held: as a station of the lock last said it this run (part(inner, ws).heads, which the read just made sets for
    // each that answered), where that is on the chain held.
    for (const id of on ? fold(h!.entries).stations.keys() : []) {
      const theirs = part(inner, ws).heads.get(id);
      if (theirs != null && onChain(h, theirs)) {
        head = theirs;
        break;
      }
    }
    const out: J = { ...made, lock: head.hash };
    if (typeof out.install === "string") out.install = `${out.install} ${head.hash}`;
    if (typeof out.installWindows === "string") out.installWindows = `${out.installWindows} ${head.hash}`;
    if (typeof out.command === "string") out.command = `${out.command} --lock ${head.hash}`;
    return out;
  });
}

/// Someone added by email who has not signed in yet is held in the lock under this name, with the role the one who
/// added them signed (`added`); it is made theirs as their first device is approved (`Lock.admit`). No account has it
/// (a sub is the cloud's id). The email is in the name alone and the entry's own `email` left empty: a station finds a
/// member by email (station/src/cloud/lock.ts `memberWithEmail`), and would take this name for the person. Kept as
/// `member` and `member.remove` entries, which every station folds already, those from before as well.
const PENDING = "pending:";
export function pendingOf(email: string): string | null {
  const name = PENDING + email.trim().toLowerCase();
  // (a member's sub is 200 long at most: rules/src/lock/lock.mbt `member`)
  return name.length <= 200 ? name : null;
}
export const isPending = (sub: string): boolean => sub.startsWith(PENDING);

/// This device's role in the lock `entries` make, as it signs there with its own key; null where it signs nothing.
function signerRole(inner: Inner, sub: string, entries: Entry[]): string | null {
  const key = signerOf(inner);
  if (key === null || !inner.host.appKeys) return null;
  try {
    const by = signerIn(checkLock(entries, now(inner)), key, now(inner));
    return by !== null && by.sub === sub && by.own ? by.role : null;
  } catch {
    return null;
  }
}

/// The workspace's lock, read again for ASKED_MS at most (`within`, the call's) and what is held here taken past that,
/// where this device signs it for an owner or an admin of it; null otherwise (a web page, one not let in, no lock or
/// one turned off): the cloud's word is all there is there, as before.
function managed(inner: Inner, sub: string, ws: string, within: Asked): Effect.Effect<{ entries: Entry[]; role: string } | null> {
  return Effect.gen(function* () {
    if (inner.provider.kind !== "stillfail" || inner.workspaces.owner(ws) !== sub) return null;
    // No lock held on here and the workspace's view naming none: nothing to read, and none to sign.
    if (!lockToRead(inner, ws)) return null;
    yield* within.wait(Effect.ignore(read(inner, ws), { log: "Unhandled", message: "lock read before a roster change" }));
    const h = held(inner, ws);
    if (!h?.head || fold(h.entries).disabled || movedHere(inner, ws)) return null;
    const role = signerRole(inner, sub, h.entries);
    return role === "owner" || role === "admin" ? { entries: h.entries, role } : null;
  });
}

/// A member or a station taken out of a locked workspace by this account, or a member given another role: so in its
/// lock first, by this device, where it signs there for an owner or an admin (`member.remove` takes their devices with
/// them; `member` with the role, which the lock's rules decide who may give). The cloud's word alone is not the lock's:
/// it could hold back the end of a member's credential or let a station back in, and the stations would take them as
/// the lock still says; an admin made a member there would still sign as an admin. A role given to someone the lock
/// has not heard of yet (their first device not approved) puts them in it with that role: else the lock made them a
/// member as their device was approved, whatever they had been given (2026-11-11: made an owner, they were one in the
/// cloud alone). Where this device signs nothing there, the cloud's word is all there is, as before; once the lock is
/// to say it, a failure here is the call's, and the cloud is not asked. One ASKED_MS on the stations alone, the lock's
/// cloud asked too past it (see `ASKED_MS`).
export function roster(inner: Inner, sub: string, ws: string, what: Roster): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    if (movedHere(inner, ws)) return yield* rosterMoved(inner, sub, ws, what);
    const within = asked(inner);
    const m = yield* managed(inner, sub, ws, within);
    if (m === null) return null;
    const f = fold(m.entries);
    const lock = new Lock(inner, ws, sub, null, { within, read: true });
    if ("station" in what) return f.stations.has(what.station) ? yield* lock.append("station.remove", { key: what.station }) : null;
    const member = f.members.get(what.member);
    if ("gone" in what) {
      if (member !== undefined) return yield* lock.append("member.remove", { sub: what.member });
      // Only pending (added here while no station was up): that adding dropped, never having taken effect; signed after
      // it, a removal would mean nothing, and the adding would take effect once a station is next up.
      const items = pendingHeld(inner, ws);
      const left = items.filter((x) => !(x.state === "waiting" && x.entry.kind === "member" && get(x.entry.body, "sub") === what.member));
      if (left.length !== items.length) putPending(inner, ws, left);
      return null;
    }
    if (member?.role === what.role) return null;
    const email = member?.email ?? str(get(arr(get(view(inner, ws), "members")).find((x) => x?.sub === what.member), "email"));
    if (email === null) return null;
    return yield* lock.append("member", { sub: what.member, email, role: what.role });
  });
}

/// A change of a moved workspace's list that needs nothing of another device (`roster`'s, `disable`, `open`, a station
/// taken in): said as statements in this person's own log (src/lock-statements.ts, personal-lock.ts `say`), the person
/// asked once. What is to be signed is worked out first, nobody asked yet: `meant`, with those it would take out besides
/// said again first (`plan`, the model's `adopt`); one that would not do what it means, or would take out someone it
/// cannot say again, is refused in the words of a change not allowed, nothing asked or signed. Taken, the state made
/// here is to show what was meant; where it does not (someone decided otherwise meanwhile), it is told as a change that
/// did not take effect (`notInEffect`). `{pending}` its row where no station of the workspace took it.
function sayMoved(inner: Inner, sub: string, ws: string, meant: Said[], shown: { act: Act | null; name: string; role?: string }, reason: string): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const personal = inner.adb.personal();
    const own = personal.root(sub), key = personal.keyId();
    const root = inForceOf(inner, ws).root;
    const notAllowed = () => new CoreError("forbidden", t("core-misc.lock.notAllowed"));
    if (own === null || key === null || root === null || personal.standing(sub) !== "member") return yield* Effect.fail(lockMoved());
    // (on and off are said in the root's log alone: the rules count them nowhere else)
    if (meant.some((m) => m.kind === "open" || m.kind === "off") && own !== root) return yield* Effect.fail(new CoreError("lock_root_only", "only the person who turned safe mode on turns it off or on again"));
    const worked = (after: readonly Entry[]) => {
      const chains = new Map(logsOf(inner, ws, false));
      chains.set(own, after);
      return plan(ws, root, chains, bodiesHeld(inner, ws), { genesis: own, sub, key }, meant, now(inner));
    };
    const first = worked(personal.entries(sub));
    if ("why" in first) return yield* Effect.fail(notAllowed());
    const salt = () => saltHex(inner);
    const r = yield* personal.say(sub, ws, (after) => {
      const p = worked(after);
      if ("why" in p) return notAllowed();
      const bodies = bodiesOf(ws, p.says, after, byHash(bodiesHeld(inner, ws)), salt);
      return { bodies, shown: p.says.map((_, i) => (i === p.says.length - 1 ? shown : { act: null, name: shown.name })) };
    }, reason);
    touch(inner, ws);
    if (r !== null) return r;
    // (taken: what is in force here now is what it is made of, this device's bodies and log among it)
    const f = stateOf(inner, ws);
    const last = meant[meant.length - 1]!;
    const done = last.kind === "member" ? f.members.get(last.sub)?.role === last.role
      : last.kind === "member.remove" ? !f.members.has(last.sub)
      : last.kind === "station" ? f.stations.has(last.key)
      : last.kind === "station.remove" ? !f.stations.has(last.key)
      : last.kind === "off" ? inForceOf(inner, ws).said === "off"
      : inForceOf(inner, ws).said === "on";
    const e = personal.entries(sub).at(-1);
    if (!done && e !== undefined && shown.act !== null) personal.notInEffect(sub, e, { ...shown, act: shown.act });
    return null;
  });
}

/// Whether this device can say a statement of a moved workspace: on its person's own lock, pinned here. Else nothing
/// is signed there, as before statements (`lockMoved`), whatever the change.
function saysHere(inner: Inner, sub: string): boolean {
  const personal = inner.adb.personal();
  return personal.root(sub) !== null && personal.keyId() !== null && personal.standing(sub) === "member";
}

/// `roster`'s change where the chain moved: a member out (`member.remove`), a member's role (`member.remove`, then
/// `member` with the log that binds them now: the highest admit in force binds, so a lower role given later changes
/// nothing without the removal; raising too), a station out (`station.remove`). Someone the list has not heard of is
/// added only with their device (the next step): `lock_moved` still.
function rosterMoved(inner: Inner, sub: string, ws: string, what: Roster): Effect.Effect<unknown, CoreError> {
  return Effect.suspend(() => {
    if (!saysHere(inner, sub)) return Effect.fail(lockMoved());
    const f = stateOf(inner, ws);
    const name = (e: Entry) => whatOf(inner, ws, e);
    const as = (kind: string, body: unknown) => name({ v: 1, ws, seq: 0, prev: null, at: 0, kind, body, sig: { key: "", alg: "Ed25519", sig: "" } });
    if ("station" in what) {
      if (!f.stations.has(what.station)) return Effect.succeed(null);
      const n = as("station", { key: what.station });
      return sayMoved(inner, sub, ws, [{ kind: "station.remove", key: what.station }], { act: "removeStation", name: n }, actText({ act: "removeStation", name: n }));
    }
    const m = f.members.get(what.member);
    const lock = f.persons.get(what.member);
    const n = as("member", { sub: what.member });
    if ("gone" in what) return m === undefined ? Effect.succeed(null) : sayMoved(inner, sub, ws, [{ kind: "member.remove", sub: what.member }], { act: "removeMember", name: n }, actText({ act: "removeMember", name: n }));
    if (m?.role === what.role) return Effect.succeed(null);
    if (m === undefined || lock === undefined) return Effect.fail(lockMoved());
    const shown = { act: "setRole" as const, name: n, role: roleText(what.role) };
    return sayMoved(inner, sub, ws, [{ kind: "member.remove", sub: what.member }, { kind: "member", sub: what.member, email: m.email, lock, role: what.role }], shown, actText(shown));
  });
}

/// A moved workspace turned off (`off`) or on again (`open`, with the settings in force and the root's person's email),
/// by the root's person alone.
function onOffMoved(inner: Inner, sub: string, ws: string, on: boolean): Effect.Effect<unknown, CoreError> {
  return Effect.suspend(() => {
    if (!saysHere(inner, sub)) return Effect.fail(lockMoved());
    const force = inForceOf(inner, ws);
    const name = nameOf(inner, ws);
    if (!on) return sayMoved(inner, sub, ws, [{ kind: "off" }], { act: "disable", name }, t("core-misc.lock.reason.disable"));
    const st = force.settings;
    const email = force.f.members.get(sub)?.email;
    if (st === undefined || email === undefined) return Effect.fail(new CoreError("forbidden", t("core-misc.lock.notAllowed")));
    // (no words of its own yet for turning it on again, nor a pending row's: the core's, and none shown)
    return sayMoved(inner, sub, ws, [{ kind: "open", origins: st.origins, rp_id: st.rp_id, cloud_keys: st.cloud_keys, email }], { act: null, name }, "Turn security mode on again");
  });
}

/// A station of the workspace taken in where the chain moved (`station {key}`): one the workspace's view lists and the
/// list in force does not.
function stationMoved(inner: Inner, sub: string, ws: string, station: string): Effect.Effect<unknown, CoreError> {
  return Effect.suspend(() => {
    if (!saysHere(inner, sub)) return Effect.fail(lockMoved());
    if (stateOf(inner, ws).stations.has(station)) return Effect.succeed(null);
    const s = arr(get(view(inner, ws), "stations")).find((x) => x?.id === station);
    if (!s) return Effect.fail(CoreError.invalid("not a station of this workspace"));
    const name = str(s.name) || station.slice(0, 8);
    return sayMoved(inner, sub, ws, [{ kind: "station", key: station }], { act: "protectStation", name }, actText({ act: "protectStation", name }));
  });
}

/// People added to a locked workspace (`workspace.addMembers`, `role`; `answer` the cloud's): in its lock as well, with
/// that role, by this device's signature where it signs there for an owner or an admin. One with an account under their
/// sub, as the answer's view names them; one who has not signed in yet under `pendingOf` their email. One the cloud
/// had already is left as the lock has them, unless it has not heard of them. As `roster`, a failure is the call's (the
/// cloud has them then: added again, the lock is asked again). One ASKED_MS on the stations alone, the lock's cloud
/// asked too past it (see `ASKED_MS`).
export function added(inner: Inner, sub: string, ws: string, role: string, answer: unknown): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    // (where the chain moved, as `roster` answers; the cloud has added them by now, as an enrollment it made, `enrolled`)
    if (movedHere(inner, ws)) return yield* Effect.fail(lockMoved());
    const within = asked(inner);
    const m = yield* managed(inner, sub, ws, within);
    if (m === null || (role === "owner" && m.role !== "owner")) return null;
    const members = arr(get(get(answer, "view"), "members"));
    const emails = (k: string) => arr(get(answer, k)).flatMap((e) => (typeof e === "string" ? [e.toLowerCase()] : []));
    const subsOf = (email: string) => members.filter((x) => typeof x?.sub === "string" && str(x.email)?.toLowerCase() === email).map((x) => ({ sub: x.sub as string, email: x.email as string }));
    const known = fold(m.entries).members;
    const wanted = [
      ...emails("joined").flatMap(subsOf),
      ...emails("already").flatMap(subsOf).filter((x) => !known.has(x.sub)),
      // (a member needs no name held: their first device approved makes them one)
      ...emails("added").flatMap((email) => {
        const name = role === "member" ? null : pendingOf(email);
        return name === null ? [] : [{ sub: name, email: "" }];
      }),
    ];
    const lock = new Lock(inner, ws, sub, null, { within, read: true });
    // (the first of them pending, if any: `{pending}`, its row, which the call's answer carries; the page lists them all)
    let first: unknown = null;
    for (const w of wanted) {
      const has = fold(held(inner, ws)?.entries ?? m.entries).members.get(w.sub);
      if (has?.role === role) continue;
      const said = yield* lock.append("member", { sub: w.sub, email: w.email, role });
      if (first === null && isObject(said) && isObject(said.pending)) first = { pending: said.pending };
    }
    return first;
  });
}

/// A station that joined a locked workspace from its home taken into that workspace's lock, as
/// one enrolled with its hash is, by this device's signature: its code is worked out here, the same person having asked
/// it to join.
export function takeInJoined(inner: Inner, sub: string, ws: string, station: string): Effect.Effect<unknown, CoreError> {
  return new Lock(inner, ws, sub, null).addStation(station, shortCode(station));
}

/// Whether a station's answer to `entries` brought it says it took the last, a `disable`, and so let go of the lock: it
/// keeps none after it (its head none, station/src/mesh/serve.ts: `taken` and no head), so no head of it can say so by
/// hash. Taken all the same: without this, a lock turned off with its stations up was held pending, and brought again
/// refused ("turned off by its owner here"), the lock on here for good (2026-11-12, found by the lock world's model).
function letGo(entries: readonly Entry[], answer: unknown): boolean {
  return entries[entries.length - 1]?.kind === "disable" && readHead(get(answer, "head")) === null && Number(get(answer, "taken") ?? 0) > 0;
}

/// What the stations brought an entry did: one took it, or none did (`refused`: one that keeps this lock refused it,
/// and which).
type Brought = { took: boolean; refused: Refused | null };
type Refused = { error: CoreError; station: string };

/// A station that refused an entry on the lock it keeps, read again (in the turn to sign, `Lock.#lost`): once for each
/// head held here, so a refusal the read brings nothing for (the lock's rules, not another entry) is not read again and
/// again by what tries again as the lock is held (`bindPerson`, `keepToPerson`, `ownLockFor`, each forked by `hold`).
const refusingRead = new WeakMap<Inner, Set<string>>();
function readRefusing(inner: Inner, ws: string, station: string): Effect.Effect<void> {
  return Effect.suspend(() => {
    let once = refusingRead.get(inner);
    if (once === undefined) refusingRead.set(inner, (once = new Set()));
    const at = `${ws}/${station}/${held(inner, ws)?.head?.hash ?? ""}`;
    if (once.has(at)) return Effect.void;
    once.add(at);
    return Effect.ignore(readLockOf(inner, ws, [station]), { log: "Unhandled", message: "lock read of a station that refused an entry" });
  });
}

/// This device's entries signed in a call a person waited on (`#within`), or signed again for one that was, by hash,
/// the last ASKED_KEPT: one of these that lost its place and is not signed again is told them (`#letBe`); the core's own
/// entries are not (a person's lock bound, their devices kept to it).
const ASKED_KEPT = 64;
const askedHeld = (inner: Inner, ws: string): readonly string[] => {
  const r = inner.data.record("lockAsked", ws);
  return Array.isArray(r) ? r.filter((x): x is string => typeof x === "string") : [];
};
function noteAsked(inner: Inner, ws: string, hash: string): void {
  const was = askedHeld(inner, ws);
  if (!was.includes(hash)) inner.data.put("lockAsked", ws, [...was, hash].slice(-ASKED_KEPT));
}

/// The acts an entry of this device's is, by hash: itself, and each it was signed again for (`Part.again`), back to
/// the first signed.
function actsOf(p: Part, e: Entry): string[] {
  const out = [hashOf(e)];
  for (let up = p.again.get(out[0]!); up !== undefined && !out.includes(up); up = p.again.get(up)) out.push(up);
  return out;
}

/// What an entry of a workspace's lock is about, for one that lost its place (src/lock-keep.ts `againOf`): the device
/// of `device` and `device.remove` (its base key), the member of `member`, `member.remove` and `person` (their sub), the
/// station of `station` and `station.remove` (its key), the lock itself of `disable`.
function subjectOf(e: Entry): string | null {
  const b = (e.body ?? {}) as J;
  switch (e.kind) {
    case "device":
    case "device.remove":
      return typeof b.id === "string" ? `device ${b.id}` : null;
    case "member":
    case "member.remove":
    case "person":
      return typeof b.sub === "string" ? `member ${b.sub}` : null;
    case "station":
    case "station.remove":
      return typeof b.key === "string" ? `station ${b.key}` : null;
    case "disable":
      return "lock";
  }
  return null;
}

/// What an entry is about, as the person knows it (the words of `core-misc.lock.changedMeanwhile`): a device by its name
/// (`deviceText`), a member by theirs or their email, a station by its name, the lock by its workspace's name.
function whatOf(inner: Inner, ws: string, e: Entry): string {
  const b = (e.body ?? {}) as J;
  const f = stateOf(inner, ws);
  const v = view(inner, ws);
  switch (subjectOf(e)?.split(" ")[0]) {
    case "device": {
      const d = f.devices.get(b.id) ?? b;
      return deviceText({ kind: d.kind === "web" ? "web" : "app", label: str(d.label) ?? "", older: Array.isArray(d.endpoints) });
    }
    case "member": {
      const m = arr(get(v, "members")).find((x) => x?.sub === b.sub);
      // (one added who has not signed in yet: held under their email, `pendingOf`)
      if (typeof b.sub === "string" && isPending(b.sub)) return b.sub.slice(PENDING.length);
      return str(get(m, "name")) || str(get(m, "email")) || f.members.get(b.sub)?.email || str(b.email) || t("web-pages.security.members");
    }
    case "station":
      return str(arr(get(v, "stations")).find((x) => x?.id === b.key)?.name) || f.stations.get(b.key) || str(b.name) || b.key.slice(0, 8);
  }
  return nameOf(inner, ws);
}

export class Lock {
  readonly #inner: Inner;
  readonly ws: string;
  readonly sub: string;
  readonly #ctx: SpanContext | null;
  /// What a person does (a call): the cloud's "too many requests" waited out (the account's devices share a budget a
  /// minute), not said at once as the call's failure.
  readonly #byHand: boolean;
  /// A call a person waits on (`run`, a device approved face to face in views/pair.ts `approve`, `roster`, `added`):
  /// its reads end with that call's ASKED_MS, what no station took by then is pending (see `ASKED_MS`) and shown as
  /// what the person did (`actOf`). None: a change no one waits on (a person's own lock bound, their devices kept to
  /// it), which waits for the stations by TAKEN_MS (pending past it, not shown) and reads the cloud as long as it takes
  /// where no station answers.
  readonly #within: Asked | null;
  /// Whether the lock is still to be read before the first entry signed (within that wait): not where the call that
  /// made it read it already (`managed`).
  #toRead: boolean;
  /// The chain with this maker's last entry on, where that is pending (`#pend`): the next it signs goes on from it, as
  /// one call signs one entry after another reading nothing between (`added` one for each person, `admit` a member
  /// before their device), the second meaning nothing without the first.
  #mine: { head: Head; entries: Entry[] } | null = null;

  /// `read`: the maker read the lock already, within `within`.
  constructor(inner: Inner, ws: string, sub: string, ctx: SpanContext | null, how: { byHand?: boolean; within?: Asked; read?: boolean } = {}) {
    this.#inner = inner;
    this.ws = ws;
    this.sub = sub;
    this.#ctx = ctx;
    this.#byHand = how.byHand === true;
    this.#within = how.within ?? null;
    this.#toRead = this.#within !== null && how.read !== true;
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

  /// What is read before an entry is signed, outside the turn to sign (`append`): for a call a person waits on (`within`),
  /// the lock read once within its wait (or by its maker), and after that nothing (what is held is what it signs after,
  /// each entry it signs held); else the chain as the stations keep it (the longest that goes on from the one held), read
  /// now, or as the cloud does where none of them answers. Null: what is held as the turn begins is what it signs after.
  #before(): Effect.Effect<{ head: Head | null; entries: Entry[] } | null, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      if (self.#within !== null) {
        if (self.#toRead) {
          self.#toRead = false;
          yield* self.#within.wait(Effect.ignore(read(self.#inner, self.ws), { log: "Unhandled", message: "lock read before an entry is signed" }));
        }
        return null;
      }
      if (yield* readLockOf(self.#inner, self.ws, lockStations(self.#inner, self.ws))) return null;
      const r = yield* self.#cloud("GET", "/lock");
      return { head: readHead(get(r, "head")), entries: arr(get(r, "entries")) as Entry[] };
    });
  }

  /// The chain an entry would be signed after now (`#before`, or what is held).
  #chain(): Effect.Effect<{ head: Head | null; entries: Entry[] }, CoreError> {
    return Effect.map(this.#before(), (c) => {
      if (c !== null) return c;
      const h = held(this.#inner, this.ws);
      return { head: h?.head ?? null, entries: h?.entries ?? [] };
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

  /// Someone the cloud has made a member, in the lock now, as a person approves their first device: a member, whatever
  /// the cloud calls them (it lowers roles and raises none; a role above that takes someone's signature saying so, as
  /// the one who added them signed it under their email, `added`). One the lock has heard of since (another device got
  /// there first) is left as they are.
  admit(sub: string, email: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      const { entries } = yield* self.#chain();
      const f = fold(entries);
      if (f.members.has(sub)) return null;
      // Added by email before they had an account (`added`): the role the one who added them signed, the name it was
      // held under taken out. An admin makes no owner: a member then, the name left for an owner's device to make theirs.
      const name = pendingOf(email);
      const pending = name === null ? undefined : f.members.get(name);
      // (held under that name only pending here, no station up as they were added: that adding dropped, and the role it
      // gave theirs, the name never taking effect)
      const added = pending !== undefined || name === null ? undefined : pendingHeld(self.#inner, self.ws).find((x) => x.state === "waiting" && x.entry.kind === "member" && get(x.entry.body, "sub") === name);
      const role = pending?.role ?? str(get(added?.entry.body, "role")) ?? "member";
      const gives = (pending !== undefined || added !== undefined) && (role !== "owner" || signerRole(self.#inner, self.sub, entries) === "owner");
      if (added !== undefined) putPending(self.#inner, self.ws, pendingHeld(self.#inner, self.ws).filter((x) => x.id !== added.id));
      yield* self.append("member", { sub, email, role: gives ? role : "member" });
      return gives && pending !== undefined ? yield* self.append("member.remove", { sub: name }) : null;
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
      // (in the turn to sign, as every entry of this device's is: `append`)
      return yield* p.turn.withPermits(1)(Effect.gen(function* () {
        const genesis = signer.sign(next(self.ws, null, inner.host.nowMs() / 1000, "genesis", {
          owner: self.sub, origins: [u.origin], rp_id: u.hostname, cloud_keys: cloudKeys, members, devices, passkeys: [], stations, gateways: [],
        }));
        const pinned = yield* self.#bring([genesis], stations.map((s) => s.key));
        yield* self.#toCloud([genesis], Object.values(pinned).some((h) => readHead(h) !== null));
        p.excluded.clear();
        return { head: { seq: 0, hash: entryHash(genesis), genesis: entryHash(genesis) }, stations: stations.map((s) => ({ id: s.key, name: s.name, pinned: pinned[s.key] ?? null })), devices: devices.length, members: members.length };
      }));
    });
  }

  /// A web page's device, 30 days more from now.
  renew(device: string): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      // (where the chain moved its devices are not the chain's: nothing signed there, whichever is named)
      if (movedHere(self.#inner, self.ws)) return yield* Effect.fail(lockMoved());
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
          // (the cloud is that station's only way to it: pending until it shows it took it, and sent to the cloud too)
          const f = fold(held(self.#inner, self.ws)?.entries ?? []);
          return f.stations.has(station) ? { head: null, stations: {} } : yield* self.append("station", { key: station, name: s.name ?? "" }, [], true);
        }
        // It takes none of them for another reason (its own workspace locked and this one not): why, as it said.
        if (asked.failure.code === "lock_station") return yield* Effect.fail(asked.failure);
        const old = asked.failure.status === 404 || /404|no route/.test(asked.failure.message);
        return yield* Effect.fail(new CoreError(old ? "lock_station_old" : "lock_station_offline", old ? t("core-misc.lock.stationOld", { name: s.name }) : t("core-misc.lock.stationOffline", { name: s.name })));
      }
      // It keeps another lock (another genesis): none of this one's entries would follow its own.
      const theirs = readHead(get(asked.success, "head"));
      part(self.#inner, self.ws).heads.set(station, theirs);
      if (theirs !== null && !sameLock(held(self.#inner, self.ws), theirs)) return yield* Effect.fail(otherLock(self.#inner, self.ws, station));
      const done = yield* self.append("station", { key: station, name: s.name ?? "" }, [station]);
      const pinned = get(get(done, "stations"), station);
      if (isObject(pinned) && typeof pinned.error === "string") return yield* Effect.fail(new CoreError("lock_station_refused", pinned.error));
      part(self.#inner, self.ws).heads.set(station, readHead(pinned));
      return done;
    });
  }

  /// One more entry, signed by this app's key, after the chain as the stations keep it: to each station of the lock,
  /// done once one of them took it (they bring each other level, lock-sync.ts), the call not waiting on the rest: one
  /// offline held an approval up until asking it gave up, some ten seconds to minutes. Sent to the cloud once a station
  /// took it, for the stations and devices from before that read it there, never waited on. Taken by none and refused by
  /// none by the call's ASKED_MS (`within`; a background signer's: TAKEN_MS), it is pending (`#pend`): the call answers
  /// at once with its row (`{pending}`), and it is brought to the stations as one is next read (`deliver`). The cloud's
  /// taking an entry never counts, but where the lock names no station at all (`#cloudOnly`). `waitFor`: the stations
  /// whose answers the call waits for, however long (one just taken in pins only what this device brings it); taken
  /// by none of them, the call fails.
  ///
  /// One entry at a time (the lock's `turn`, its part's, a Semaphore of one): whoever signs here (a person's call, and
  /// the background's `bindPerson`, `keepToPerson`, `ownLockFor`, `again`) reads first, outside the turn (`#before`),
  /// then takes its turn, signs after the head held as it begins (or the cloud's, where no station answered the read),
  /// brings it, and gives the turn up once it is on the chain held (a station took it: held then, `#taken`), refused, or
  /// pending: so no two entries of this device are ever signed after the same parent while a station may still take the
  /// first but one pending (which `deliver` signs again where it lost its place) and one signed after a pending one of
  /// the same call (`#mine`). The worst a call waits for its turn is another's bring: TAKEN_MS behind a background
  /// signer or a delivery, ASKED_MS behind another call, and a station named in `waitFor`
  /// as long as it takes to answer (an enrollment's, pressed by hand); that wait counts against the call's ASKED_MS
  /// (`within.begin`). The turn of a person's own lock (personal-lock.ts `#append`) is never held while this one is
  /// waited for, nor this one while that one is: neither is taken inside the other (what one does inside its turn forks
  /// what signs in the other); were one ever to be, it is the person's lock's first.
  ///
  /// An entry a station that keeps this lock refused (its 409: not on its head, beaten, below; or the rules), taken by
  /// none, is the turn's still (`#lost`): that station read, it is done where the chain held has it or the same said
  /// since its parent; refused where its subject was decided otherwise since, or the rules take it no more after the head
  /// (`core-misc.lock.changedMeanwhile`); else signed again after the head, AGAIN_MOST times at most; where the read
  /// moved nothing (its parent the head still), refused in the station's words, as before.
  append(kind: string, body: unknown, waitFor: string[] = [], viaCloud = false): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      // (where the chain moved nothing follows it: nothing signed, nothing pending)
      if (movedHere(self.#inner, self.ws)) return yield* Effect.fail(lockMoved());
      const signer = yield* Signer.load(self.#inner.host);
      if (signer === null) return yield* Effect.fail(new CoreError("lock_no_signer", "this device signs nothing for the workspace lock"));
      const after = yield* self.#before();
      if (self.#within !== null) yield* self.#within.begin();
      const rest = yield* part(self.#inner, self.ws).turn.withPermits(1)(Effect.suspend(() => self.#ahead(kind, body) ?? self.#signed(signer, kind, body, waitFor, after ?? self.#mine, 0, null, viaCloud)));
      return yield* rest;
    });
  }

  /// In the turn, before an entry is signed: one that would only say again what a pending one says answers as that one
  /// (pending, nothing signed twice); past PENDING_MOST pending, none more is signed, and the call is told to wait for
  /// the stations. Null: signed.
  #ahead(kind: string, body: unknown): Effect.Effect<Effect.Effect<unknown, CoreError>, CoreError> | null {
    const waiting = pendingHeld(this.#inner, this.ws).filter((x) => x.state === "waiting");
    const same = waiting.find((x) => repeats(x, kind, body));
    if (same !== undefined) return Effect.succeed(Effect.succeed({ pending: pendingRowOf(this.#inner, this.ws, same) }));
    if (waiting.length >= PENDING_MOST) return Effect.fail(new CoreError("lock_pending_full", pastBound(stationNames(this.#inner, this.ws))));
    return null;
  }

  /// An entry of this device's the chain held went off (a read moved it to another branch, `hold`): signed again after
  /// the head, in the turn, as `#lost` does for one a station refused, by the same rules, nothing said to anyone (no one
  /// waits on it; one let be just stops). Each entry once (`hold` notes it, `handled`). `earlier`: those of this
  /// device's that lost their place with it and were made before it (`hold`'s, by hash): what it signed again of them
  /// is looked past (`againOf`'s `before`), never another entry of its own (a later act, taken directly, decides).
  again(lost: Entry, earlier: ReadonlySet<string> = new Set()): Effect.Effect<unknown, CoreError> {
    const self = this;
    return Effect.gen(function* () {
      if (movedHere(self.#inner, self.ws)) return null;
      const signer = yield* Signer.load(self.#inner.host);
      if (signer === null || lost.sig?.key !== signer.id) return null;
      const p = part(self.#inner, self.ws);
      const inTurn: Effect.Effect<Effect.Effect<unknown, CoreError>, CoreError> = Effect.suspend(() => {
        const h = held(self.#inner, self.ws);
        const tries = p.tries.get(hashOf(lost)) ?? 0;
        const before = (e: Entry) => actsOf(p, e).some((x) => earlier.has(x));
        const none = Effect.succeed(Effect.succeed(null));
        if (!h?.head || fold(h.entries).disabled) return none;
        const how = againOf(h.entries, h.aside ?? [], lost, subjectOf, before);
        // (decided otherwise since by this device's own later acts alone: what the person did last stands, nothing to tell)
        const others = () => againOf(h.entries, h.aside ?? [], lost, (e) => (e !== lost && e.sig?.key === signer.id ? null : subjectOf(e)), before) === "otherwise";
        if (how === "otherwise") return Effect.as(Effect.sync(() => others() && self.#letBe(lost, {})), Effect.succeed(null));
        if (how !== "sign") return none;
        if (tries >= AGAIN_MOST) return Effect.as(Effect.sync(() => self.#letBe(lost, {})), Effect.succeed(null));
        // (signed again and refused: decided otherwise or the rules take it no more after the head, `#changed`; else in a
        // station's words, the last of AGAIN_MOST)
        return Effect.catch(self.#signed(signer, lost.kind, lost.body, [], null, tries + 1, hashOf(lost)), (err) =>
          Effect.as(Effect.sync(() => self.#letBe(lost, err.message === self.#changed(lost).message ? {} : { why: err.message })), Effect.succeed(null)));
      });
      const rest = yield* p.turn.withPermits(1)(inTurn);
      return yield* rest;
    });
  }

  /// In the turn: an entry of this device's that lost its place, taken before (the person answered it was done), not
  /// signed again: decided otherwise since by someone else, signed again AGAIN_MOST times, or refused as it was signed
  /// again (`how`: `why` a station's words). Told as a pending one that failed is (`deliver`'s `failed`: what changed
  /// meanwhile, or why), where a person asked for it (`askedHeld`); the core's own are not. Its row's id the entry as
  /// first signed; failed ones count apart from those waiting (`bounded`), so it never holds a new change back.
  #letBe(lost: Entry, how: { why?: string }): void {
    const inner = this.#inner;
    const acts = actsOf(part(inner, this.ws), lost);
    const mine = askedHeld(inner, this.ws);
    if (!acts.some((x) => mine.includes(x))) return;
    const id = acts[acts.length - 1]!;
    const items = pendingHeld(inner, this.ws);
    const row: Pending = { id, entry: lost, ...actOf(inner, this.ws, lost, true), at: lost.at * 1000, state: "failed", ...(how.why !== undefined ? { why: how.why } : { what: whatOf(inner, this.ws, lost) }) };
    putPending(inner, this.ws, items.some((x) => x.id === id) ? items.map((x) => (x.id === id ? row : x)) : [...items, row]);
  }

  /// In the turn: `kind` and `body` signed after `after` (null: what is held now), brought, and what is left of it once
  /// the turn is given up (a lock that names no station: the cloud's taking, waited on by the caller). `tries`: how many signings again of one that
  /// lost its place this is (0: the first signing).
  #signed(signer: Signer, kind: string, body: unknown, waitFor: string[], after: { head: Head | null; entries: Entry[] } | null, tries: number, of: string | null, viaCloud = false): Effect.Effect<Effect.Effect<unknown, CoreError>, CoreError> {
    const self = this;
    const inner = this.#inner;
    return Effect.gen(function* () {
      const h = held(inner, self.ws);
      const { head, entries } = after ?? { head: h?.head ?? null, entries: h?.entries ?? [] };
      if (head === null) return yield* Effect.fail(new CoreError("lock_none", "the workspace has no lock"));
      const entry = signer.sign(next(self.ws, head, inner.host.nowMs() / 1000, kind, body));
      const hash = entryHash(entry);
      // The whole chain: a station that is behind takes what it lacks, and skips what it has.
      const chain = [...entries, entry];
      // Checked as the stations check it before it goes: one they refuse, kept at the cloud, leaves every entry after
      // it refused there too (2026-10-28: a device the lock names without its key approved one, and a station kept
      // turning the devices approved after it away for days). Signed again, one the rules take no more after the head
      // is not: the lock changed meanwhile.
      const checked = checkSigned(entries, chain, signer.id, now(inner));
      yield* tries === 0 ? checked : Effect.mapError(checked, () => self.#changed(entry));
      const p = part(inner, self.ws);
      if (tries > 0) p.tries.set(hash, tries);
      if (tries > 0 && of !== null) p.again.set(hash, of);
      // (signed for a person, or again for one that was: theirs to be told of if it is undone, `#letBe`)
      if (self.#within !== null || (of !== null && askedHeld(inner, self.ws).includes(of))) noteAsked(inner, self.ws, hash);
      // (the stations of the lock before it and after it: one it takes out is brought it too, and one it takes in; whose
      // taking counts are those it names after it, `named`: a station taken out is brought it behind, as one gone for
      // good never would take it, and its removal would wait for it for ever)
      const named = [...fold(chain).stations.keys()];
      const stations = [...new Set([...fold(entries).stations.keys(), ...named])];
      const behind = stations.filter((s) => !named.includes(s));
      const signed: Head = { seq: entry.seq, hash, genesis: head.genesis };
      const takenBy = (id: string, said: unknown) => self.#takenBy(id, said, entry);
      // A lock that names no station (turned on with none up, or the last taken out by this entry): nothing but the
      // cloud keeps it, and what is signed is the cloud's to keep, as before there were stations to keep a lock;
      // nothing here protects anything yet.
      if (named.length === 0) {
        if (behind.length > 0) inner.runner.fork(Effect.ignore(self.#bring(chain, behind), { log: "Unhandled", message: "lock chain brought to a station taken out" }));
        return yield* self.#cloudOnly(entry, head, signed, chain);
      }
      // A station named (`waitFor`: one being taken in pins only what this device brings it) is brought it first, and
      // waited on: its taking is what the call is for. Taken by none of them, nothing is brought anywhere else and the
      // call fails in the station's words, or as not reached: never pending, as nothing could take it but that one.
      if (waitFor.length > 0) {
        const pinned = yield* self.#bring(chain, stations.filter((s) => waitFor.includes(s)));
        const took = (yield* Effect.forEach(Object.entries(pinned), ([id, said]) => takenBy(id, said))).some((x) => x);
        if (!took) {
          const said = Object.values(pinned).map((x) => str(get(x, "error"))).find((x) => x !== null);
          const name = str(arr(get(view(inner, self.ws), "stations")).find((s) => waitFor.includes(s?.id))?.name) ?? waitFor[0]!.slice(0, 8);
          return yield* Effect.fail(new CoreError("lock_station_refused", said ?? t("core-misc.lock.stationOffline", { name })));
        }
        yield* self.#taken(signed, chain);
        const others = stations.filter((s) => !waitFor.includes(s));
        if (others.length > 0) inner.runner.fork(Effect.ignore(self.#bring(chain, others), { log: "Unhandled", message: "lock chain brought" }));
        return Effect.as(self.#toCloud([entry], true), { head: signed, stations: pinned });
      }
      // (waited on only of those that serve it: one from before, or not answering, hears of it in the background, and
      // its taking it is held as it comes)
      const serving = p.serving;
      if (behind.length > 0) inner.runner.fork(Effect.ignore(self.#bring(chain, behind), { log: "Unhandled", message: "lock chain brought to a station taken out" }));
      const later = named.filter((s) => !serving.has(s));
      if (later.length > 0) inner.runner.fork(Effect.ignore(Effect.flatMap(self.#bring(chain, later), (said) => self.#tookLate(said, takenBy, signed, chain, entry)), { log: "Unhandled", message: "lock chain brought" }));
      const first = yield* self.#firstTaken(chain, named.filter((s) => serving.has(s)), takenBy, head.genesis);
      const answer: unknown = { head: signed, stations: {} };
      // Refused by a station that keeps this lock (another entry at its place, or the lock's rules) and taken by none:
      // what becomes of it is `#lost`'s, in the turn.
      const refused = "now" in first ? first.now.refused : first.refused();
      if (refused !== null) return yield* self.#lost(signer, entry, refused, waitFor, tries, {}, of);
      if ("now" in first && first.now.took) {
        yield* self.#taken(signed, chain);
        return Effect.as(self.#toCloud([entry], true), answer);
      }
      // None took it nor refused it by the call's wait (ASKED_MS; a background signer's: TAKEN_MS): pending, kept here
      // beside the lock held and not on it, the turn given up, the call answered at once saying so. The cloud is not
      // sent it: only a station's taking makes it the lock's (the root AGENTS.md, The cloud is the account system), and
      // the stations and devices from before, which go by the cloud's, would take it as the lock where no station has it.
      // The stations still answering are listened to: one taking it then, it is held (and pending no more); one refusing
      // it, that station is read and what is pending decided again (`deliver`). (2026-11-12: with the one station asleep
      // and the cloud up, 移除设备 answered as done though no station would act on it; with both silent, never.)
      const row = self.#pend(entry, chain, tries, of, head.genesis, viaCloud);
      // (`viaCloud`: a station that pins what the lock says of it from the cloud alone, which no device reaches,
      // `joinStation`: the cloud carries it there, its taking it still counting for nothing here)
      if (viaCloud) yield* self.#toCloud([entry], true);
      if ("later" in first) {
        inner.runner.fork(Effect.flatMap(first.later, (b): Effect.Effect<void> => {
          if (b.took) return Effect.ignore(self.#tookLate({ any: signed }, () => Effect.succeed(true), signed, chain, entry));
          if (b.refused !== null) return Effect.andThen(readRefusing(inner, self.ws, b.refused.station), Effect.sync(() => deliver(inner, self.ws)));
          return Effect.void;
        }));
      }
      return Effect.succeed({ pending: row });
    });
  }

  /// A lock that names no station (`#signed`): sent to the cloud and waited on, as before there were stations. Not taken
  /// as far as this device heard: the cloud may have kept it all the same, its answer lost on the way back (a gateway's
  /// 502, the line gone); then it is done (a call a person waits on waits ASKED_MS on that read).
  #cloudOnly(entry: Entry, head: Head, signed: Head, chain: Entry[]): Effect.Effect<Effect.Effect<unknown, CoreError>> {
    const cloudTakes = Effect.catch(this.#toCloud([entry], false), (e) => {
      const reread = Effect.orElseSucceed(Effect.map(this.#cloud("GET", "/lock"), (r) => arr(get(r, "entries")) as Entry[]), () => null);
      const known = Effect.map(Effect.timeoutOption(reread, ASKED_MS), (o) => (o._tag === "Some" ? o.value : null)); // timer: a deadline
      return Effect.flatMap(this.#within === null ? reread : known, (kept): Effect.Effect<void, CoreError> => {
        const there = kept?.find((x) => x.seq === entry.seq);
        return there !== undefined && entryHash(there) === signed.hash ? Effect.void : Effect.fail(e);
      });
    });
    // (a call a person waits on: by CLOUD_WRITE_MS, else it fails saying nothing was saved, nothing held or pending)
    const inTime = this.#within === null ? cloudTakes : Effect.flatMap(Effect.timeoutOption(cloudTakes, CLOUD_WRITE_MS), (o) => (o._tag === "Some" ? Effect.void : Effect.fail(cloudSilent()))); // timer: a deadline on what a call waits for
    return Effect.succeed(Effect.as(Effect.andThen(inTime, this.#cloudTook(head, signed, chain)), { head: signed, stations: {} }));
  }

  /// In the turn: `entry` (of `chain`) kept pending (`pendingHeld`), or, signed again (`of` the id of the one first
  /// signed), in that one's place; its row of the `lock` topic, which the call answers with. `sent`: the cloud is sent
  /// it now (`viaCloud`), and not again as it is held (`hold`).
  #pend(entry: Entry, chain: Entry[], tries: number, of: string | null, genesis: string, sent = false) {
    const inner = this.#inner;
    const items = pendingHeld(inner, this.ws);
    const id = of ?? entryHash(entry);
    const had = items.find((x) => x.id === id);
    const made: Pending = had !== undefined
      ? { ...had, entry, state: "waiting", ...(tries > 0 ? { tries } : {}), ...(sent ? { sent } : {}) }
      : { id, entry, ...actOf(inner, this.ws, entry, this.#within !== null), at: inner.host.nowMs(), state: "waiting", ...(tries > 0 ? { tries } : {}), ...(sent ? { sent } : {}) };
    putPending(inner, this.ws, had !== undefined ? items.map((x) => (x.id === id ? made : x)) : [...items, made]);
    this.#mine = { head: { seq: entry.seq, hash: entryHash(entry), genesis }, entries: chain };
    return pendingRowOf(inner, this.ws, made);
  }

  /// Stations' answers to what was brought them past waiting (`said`, by station): one that took `entry` (`takenBy`),
  /// it is held (pending no more and the cloud sent it, `hold`); nothing where it is on the chain held already.
  #tookLate(said: Record<string, unknown>, takenBy: (id: string, said: unknown) => Effect.Effect<boolean>, signed: Head, chain: Entry[], entry: Entry): Effect.Effect<void> {
    const self = this;
    return Effect.gen(function* () {
      const took = (yield* Effect.forEach(Object.entries(said), ([id, s]) => takenBy(id, s))).some((x) => x);
      if (!took || held(self.#inner, self.ws)?.entries.some((e) => hashOf(e) === signed.hash)) return;
      // (pending no more as it is held, and the cloud sent it then: `hold`)
      yield* self.#taken(signed, chain);
    });
  }

  /// In the turn: what is pending brought to the lock's stations, oldest first (`deliver`, a station having answered a
  /// read). One whose parent is the head held still is brought as it is; else it is decided by the chain held
  /// (src/lock-keep.ts `againOf`): done, dropped; about what was decided otherwise since, no longer taken by the rules
  /// after the head, or signed again AGAIN_MOST times: `failed`, the person told (`core-misc.lock.pending.failed`); else
  /// signed again after the head and brought. Taken: held, and pending no more. Refused by a station that keeps this
  /// lock: that station read, and decided again (once more); refused with its parent the head still (the rules, as that
  /// station says them): `failed` with its words. None answering: left waiting, and nothing more brought this time
  /// (they are brought it as one is next read).
  deliver(): Effect.Effect<void, CoreError> {
    const self = this;
    const inner = this.#inner;
    const ws = this.ws;
    const once = Effect.gen(function* () {
      // Where the chain moved, nothing pending will be taken after it: each a person asked for is told them as one that
      // did not take effect, in the words of one let be (`#letBe`), the core's own dropped, none waiting for ever.
      if (movedHere(inner, ws)) {
        const items = pendingHeld(inner, ws);
        if (items.some((x) => x.state === "waiting")) {
          putPending(inner, ws, items.flatMap((x) => (x.state !== "waiting" ? [x] : x.act === null ? [] : [{ ...x, state: "failed" as const, what: whatOf(inner, ws, x.entry) }])));
        }
        return;
      }
      const signer = yield* Signer.load(inner.host);
      const passes = new Map<string, number>();
      for (;;) {
        const h = held(inner, ws);
        const item = pendingHeld(inner, ws).find((x) => x.state === "waiting" && (passes.get(x.id) ?? 0) < 2);
        if (item === undefined || !h?.head) return;
        passes.set(item.id, (passes.get(item.id) ?? 0) + 1);
        const fail = (how: { what?: string; why?: string; as?: "off" }) => Effect.sync(() => putPending(inner, ws, pendingHeld(inner, ws).map((x) => (x.id === item.id ? { ...x, state: "failed" as const, ...how } : x))));
        const drop = Effect.sync(() => putPending(inner, ws, pendingHeld(inner, ws).filter((x) => x.id !== item.id)));
        if (h.entries.some((e) => hashOf(e) === hashOf(item.entry))) {
          yield* drop;
          continue;
        }
        if (fold(h.entries).disabled) {
          yield* fail({ as: "off" });
          continue;
        }
        let entry = item.entry;
        if (entry.prev !== h.head.hash) {
          // (what this device had pending, made before it and taken since, is no decision against it: made in that
          // order; made after it, it is the later act; at the same ms, taken as the later act, the side where nothing
          // made after it is undone)
          // (one of these lost its place since and signed again, `again`, is still that act)
          const took = new Set(tookHeld(inner, ws).filter((x) => x.at < item.at).map((x) => x.hash));
          const p = part(inner, ws);
          const how = againOf(h.entries, h.aside ?? [], entry, (e) => (actsOf(p, e).some((x) => took.has(x)) ? null : subjectOf(e)));
          if (how === "done") {
            yield* drop;
            continue;
          }
          const tries = item.tries ?? 0;
          const again = how === "sign" && tries < AGAIN_MOST && signer !== null && entry.sig?.key === signer.id ? signer.sign(next(ws, h.head, inner.host.nowMs() / 1000, entry.kind, entry.body)) : null;
          const ok = again === null ? null : yield* Effect.result(checkSigned(h.entries, [...h.entries, again], signer!.id, now(inner)));
          if (again === null || ok?._tag !== "Success") {
            yield* fail({ what: whatOf(inner, ws, entry) });
            continue;
          }
          p.again.set(entryHash(again), hashOf(entry));
          if (item.act !== null) noteAsked(inner, ws, entryHash(again));
          entry = again;
          // (a new entry: the cloud not sent it, `sent` no more)
          putPending(inner, ws, pendingHeld(inner, ws).map((x) => {
            if (x.id !== item.id) return x;
            const { sent: _sent, ...rest } = x;
            return { ...rest, entry: again, tries: tries + 1 };
          }));
        }
        const chain = [...h.entries, entry];
        const signed: Head = { seq: entry.seq, hash: entryHash(entry), genesis: h.head.genesis };
        const takenBy = (id: string, said: unknown) => self.#takenBy(id, said, entry);
        // (whose taking counts: the stations it names after it, as `#signed` goes; one taken out is brought it behind)
        const named = [...fold(chain).stations.keys()];
        const behind = [...fold(h.entries).stations.keys()].filter((s) => !named.includes(s));
        if (behind.length > 0) inner.runner.fork(Effect.ignore(self.#bring(chain, behind), { log: "Unhandled", message: "pending lock entry brought to a station taken out" }));
        // The lock names no station after it (the last taken out): the cloud's to keep, as `#cloudOnly`'s. Taken there,
        // it is held and pending no more; not, it waits for the next time this runs.
        if (named.length === 0) {
          const kept = yield* Effect.timeoutOption(Effect.result(self.#toCloud([entry], false)), CLOUD_WRITE_MS); // timer: a deadline (the turn is held meanwhile)
          if (kept._tag !== "Some" || kept.value._tag !== "Success") return;
          // (held as a station's taking is, so noted as this device's taken in turn, `took`; the cloud not sent it again)
          putPending(inner, ws, pendingHeld(inner, ws).map((x) => (x.id === item.id ? { ...x, entry, sent: true } : x)));
          yield* self.#taken(signed, chain);
          continue;
        }
        const serving = part(inner, ws).serving;
        const later = named.filter((s) => !serving.has(s));
        if (later.length > 0) inner.runner.fork(Effect.ignore(Effect.flatMap(self.#bring(chain, later), (said) => self.#tookLate(said, takenBy, signed, chain, entry)), { log: "Unhandled", message: "pending lock entry brought" }));
        const first = yield* self.#firstTaken(chain, named.filter((s) => serving.has(s)), takenBy, h.head.genesis);
        const b: Brought = "now" in first ? first.now : { took: false, refused: first.refused() };
        if (b.took) {
          // (held, pending no more, the cloud sent it: `hold`)
          yield* self.#taken(signed, chain);
          continue;
        }
        if (b.refused !== null) {
          const refusal = b.refused;
          yield* readRefusing(inner, ws, refusal.station);
          if (entry.prev === held(inner, ws)?.head?.hash) yield* fail({ why: refusal.error.message });
          continue;
        }
        return;
      }
    });
    return part(inner, ws).turn.withPermits(1)(once);
  }

  /// What a station took (`#signed`), held here and known shown (`carry`): the next entry signed in the turn goes on
  /// from it. Where what is held moved on meanwhile, it is kept with that, the rules choosing (`hold`).
  #taken(signed: Head, chain: Entry[]): Effect.Effect<void> {
    return Effect.suspend(() => {
      part(this.#inner, this.ws).shown.add(signed.hash);
      this.#mine = null;
      return hold(this.#inner, this.ws, this.sub, signed, chain, held(this.#inner, this.ws)?.seen ?? null);
    });
  }

  /// What the cloud took, for a call a person waits on: it reads nothing between the entries it signs one after another
  /// (`added` signs one for each person, `admit` a member before their device), so the chain is held here with it on,
  /// the next following it, and the pages show it though no station answered. Where what is held moved on meanwhile
  /// (from `head`, what it was signed after), a read brought more already, and it is left as it is.
  #cloudTook(head: Head, signed: Head, chain: Entry[]): Effect.Effect<void> {
    return Effect.suspend(() => {
      if (this.#within === null) return Effect.void;
      const was = held(this.#inner, this.ws);
      return was?.head?.hash === head.hash ? hold(this.#inner, this.ws, this.sub, signed, chain, was.seen ?? null) : Effect.void;
    });
  }

  /// In the turn: `entry`, refused by a station that keeps this lock (`refused`) and taken by none. That station read
  /// (the chain held follows it by the rules' fork choice), it is decided by the chain held now (src/lock-keep.ts
  /// `againOf`, the entry's subject `subjectOf`): done (on the chain, or the same said since its parent: someone did it),
  /// refused in words that say what to do (its subject decided otherwise since, the rules taking it no more: `#changed`;
  /// a background signer just stops), refused in the station's words (the read moved nothing: what refused it was the
  /// rules, or another branch this device does not go by; and once signed again AGAIN_MOST times), else signed again
  /// after the head (same kind and body, a new `at`), brought, in the same turn.
  #lost(signer: Signer, entry: Entry, refused: Refused, waitFor: string[], tries: number, pinned: Record<string, unknown>, of: string | null): Effect.Effect<Effect.Effect<unknown, CoreError>, CoreError> {
    const self = this;
    const inner = this.#inner;
    return Effect.flatMap(Effect.andThen(Effect.sync(() => void part(inner, self.ws).handled.add(entryHash(entry))), readRefusing(inner, self.ws, refused.station)), (): Effect.Effect<Effect.Effect<unknown, CoreError>, CoreError> => {
      const h = held(inner, self.ws);
      const how = h?.head ? againOf(h.entries, h.aside ?? [], entry, subjectOf) : "unmoved";
      if (how === "done") return Effect.succeed(Effect.succeed({ head: h!.head, stations: pinned }));
      if (how === "otherwise") return Effect.fail(self.#changed(entry));
      if (how === "unmoved" || tries >= AGAIN_MOST) return Effect.fail(refused.error);
      return self.#signed(signer, entry.kind, entry.body, waitFor, null, tries + 1, of);
    });
  }

  /// An entry that lost its place not signed again, the lock having changed meanwhile: what the person is told, what
  /// to do (look how it stands, do it again if still wanted), as `lock_refused`.
  #changed(entry: Entry): CoreError {
    return new CoreError("lock_refused", t("core-misc.lock.changedMeanwhile", { what: whatOf(this.#inner, this.ws, entry) }), 409);
  }

  /// Whether a station took `entry`, by its answer's head (`said`): by hash, that head the entry itself, or one after it
  /// on a chain that holds it at its place (the station's chain after the entry's parent read then). A head as far on
  /// another entry took none of it (an older station's answer says only how far its chain goes).
  #takenBy(id: string, said: unknown, entry: Entry): Effect.Effect<boolean> {
    const h = readHead(said);
    const hash = entryHash(entry);
    if (h === null || h.seq < entry.seq || (h.seq === entry.seq && h.hash !== hash)) return Effect.succeed(false);
    if (h.hash === hash) return Effect.succeed(true);
    return Effect.map(Effect.result(this.#station(id, "GET", `/lock?after=${entry.seq - 1}`)), (r) => {
      if (r._tag !== "Success") return false;
      return arr(get(r.success, "entries")).some((e) => {
        try {
          return e?.seq === entry.seq && entryHash(e as Entry) === hash;
        } catch {
          return false;
        }
      });
    });
  }

  /// Entries brought to each of `stations`, each on its own (one offline hears of them later): whether one of them
  /// took them (`taken`, by its answer, `#takenBy`), as soon as one did; not once none did, there are none, or none
  /// answered by TAKEN_MS. `refused`, where none took them: the refusal of one that keeps this lock (`#refusedBy`),
  /// seen once all answered or the wait ended. One refusal does not end the wait: another station may take the entry a
  /// moment after, and a taking wins. For a call a person waits on (`within`): as it stands at the end of its ASKED_MS
  /// (`now`), else the way to wait for the stations still (`later`, by TAKEN_MS from when they were brought it) and
  /// the refusal seen so far, the cloud being asked too meanwhile (`append`).
  #firstTaken(entries: Entry[], stations: string[], taken: (id: string, head: unknown) => Effect.Effect<boolean>, genesis: string): Effect.Effect<{ now: Brought } | { later: Effect.Effect<Brought>; refused: () => Refused | null }> {
    const self = this;
    return Effect.gen(function* () {
      if (stations.length === 0) return { now: { took: false, refused: null } };
      const done = Deferred.makeUnsafe<boolean>();
      let left = stations.length;
      let refused: Refused | null = null;
      for (const id of stations)
        self.#inner.runner.fork(Effect.flatMap(Effect.result(self.#station(id, "POST", "/lock", { entries })), (r) =>
          Effect.flatMap(r._tag === "Success" ? (letGo(entries, r.success) ? Effect.succeed(true) : taken(id, get(r.success, "head"))) : Effect.succeed(false), (took) => Effect.sync(() => {
            if (took) return void Deferred.doneUnsafe(done, Effect.succeed(true));
            refused ??= self.#refusedBy(id, r, genesis);
            if (--left === 0) Deferred.doneUnsafe(done, Effect.succeed(false));
          }))));
      // (the stations are brought it still, each in a fiber of its own)
      const brought = Effect.map(Effect.timeoutOption(Deferred.await(done), TAKEN_MS), (o): Brought => { // timer: a deadline
        const took = o._tag === "Some" && o.value;
        return { took, refused: took ? null : refused };
      });
      if (self.#within === null) return { now: yield* brought };
      const r = yield* self.#within.first(brought);
      return "now" in r ? r : { later: r.later, refused: () => refused };
    });
  }

  /// A station's answer to entries brought to it, where it refused them on this lock (`genesis`, the chain signed on):
  /// its 409 (another entry at their place, or the lock's rules: station/src/mesh/serve.ts), as `lock_refused` with
  /// its words, as the person's own lock says it (`personalStations.bring`); null for anything else: one keeping
  /// another lock or none, one refusing this device (`lock_unconfirmed`) or the station (`lock_station`), one from
  /// before (404), the network. Which lock it keeps is as it last said this run (`part.heads`, its GET /lock): its 409
  /// carries its head, but a station's refusal reaches the core as its code, words and status alone
  /// (station/requests.ts `httpError`). What becomes of the entry then is `#lost`'s.
  #refusedBy(id: string, r: Result.Result<unknown, CoreError>, genesis: string): Refused | null {
    if (r._tag !== "Failure" || r.failure.status !== 409) return null;
    const theirs = part(this.#inner, this.ws).heads.get(id);
    if (theirs == null || theirs.genesis !== genesis) return null;
    return { error: new CoreError("lock_refused", r.failure.message, 409), station: id };
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
