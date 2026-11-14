// The workspace lock as still.fail cloud keeps it: the cloud stores the chain and carries it,
// to the stations (their presence sockets) and to members' devices. Only entries a station takes: checked by the
// stations' own rules (station/src/cloud/lock.ts `genesis`/`apply`), as one it kept that they refuse leaves every
// entry after it refused too. The stations trust nothing the cloud says of it all the same. The hashing is the
// stations' own (their lock.ts).
//
// As a station keeps a lock (station/src/cloud/log-keep.ts, the same code and rules: 2026-11-12): what a device brings
// itself goes on from the head or is refused (`extendLock`), and what another keeper took (a station of the lock over
// its presence socket, a device saying `keep`) is kept by the rules' fork choice among all it keeps (`keepLockAt`),
// the chain gone by being their active chain and the rest kept aside, at most ASIDE_MOST. So where two stations took
// different entries at one place while the cloud took the one that lost, the cloud follows them once one of them gives
// it theirs: its head is theirs again, and what comes after it is taken (before, it refused every entry after their
// head for good, and the core, which reads a lock again as the cloud's view of it moves, never did).
export { apply, canonical, genesis, shortCode, type Entry, type LockState } from "../../station/src/cloud/lock.ts";
import { apply, asEntry as stationAsEntry, entryHash as stationEntryHash, genesis, lockChain, signer, type Entry, type LockState } from "../../station/src/cloud/lock.ts";
import { type Kept, type LogRules, keep } from "../../station/src/cloud/log-keep.ts";
export { ASIDE_MOST } from "../../station/src/cloud/log-keep.ts";

export type LockEntry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: unknown; sig: unknown };

/** An entry's hash (hex): of everything but its signature, as the stations hash it. */
export const entryHash = (e: LockEntry): string => stationEntryHash(e as unknown as Entry);

/** An entry as it came: its shape checked as the stations check it (not its signature), at most 64 KB of it. */
export function asEntry(v: unknown): LockEntry | null {
  if (stationAsEntry(v) === null || JSON.stringify(v).length > 65536) return null;
  return v as LockEntry;
}


/** Why entries brought to the kept chain are refused: the status and code the cloud answers with. */
export class LockAppendRefused extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/**
 * Which of `incoming` the kept chain `kept` (from its genesis, as it checks out) takes: those it has are skipped; one
 * that disagrees is refused, with the rest. A genesis starts a chain where there is none, or where the last one was
 * turned off (`restart`: the kept one goes). Each is checked as a station checks it (signed by whom it may be), and
 * one a station would refuse is refused here, with the rest: kept, it would leave every entry after it refused at the
 * stations. `now`: the cloud's time (unix seconds). Throws LockAppendRefused.
 */
export function extendLock(kept: LockEntry[], incoming: LockEntry[], now: number): { restart: boolean; adding: { e: LockEntry; hash: string }[] } {
  const refuse = (status: number, code: string): never => {
    throw new LockAppendRefused(status, code);
  };
  const last = kept.at(-1);
  let head = last === undefined ? null : { seq: last.seq, hash: entryHash(last), genesis: entryHash(kept[0]!) };
  let lastKind = last?.kind ?? null;
  let restart = false;
  const adding: { e: LockEntry; hash: string }[] = [];
  for (const e of incoming) {
    const hash = entryHash(e);
    if (e.kind === "genesis" && e.seq === 0 && e.prev === null) {
      if (head?.genesis === hash) continue;
      if (head && lastKind !== "disable") refuse(409, "lock_exists");
      restart = true;
      adding.length = 0;
    } else if (head && e.seq <= head.seq) {
      const had = adding.find((a) => a.e.seq === e.seq)?.hash ?? (restart ? undefined : kept[e.seq] && entryHash(kept[e.seq]!));
      if (had !== hash) refuse(409, "lock_fork");
      continue;
    } else if (!head || e.seq !== head.seq + 1 || e.prev !== head.hash) refuse(409, "lock_does_not_follow");
    adding.push({ e, hash });
    head = { seq: e.seq, hash, genesis: e.seq === 0 ? hash : head!.genesis };
    lastKind = e.kind;
  }
  if (adding.length > 0) {
    let state: LockState | null = null;
    if (!restart) for (const e of kept) state = state === null ? genesis(e as Entry) : apply(state, e as Entry, null);
    for (const { e } of adding) {
      // A new entry signed with a device or passkey someone else put in under the signer's name: a station would fold
      // it and let it change nothing (one from before keeps a chain whole); none is kept from now on.
      if (state !== null && signer(state, (e as Entry).sig, now)?.own === false) refuse(409, "lock_refused");
      try {
        state = state === null ? genesis(e as Entry) : apply(state, e as Entry, now);
      } catch {
        refuse(409, "lock_refused");
      }
    }
  }
  return { restart, adding };
}

/** A lock as the cloud keeps it: its chain gone by from the genesis (what every reader of it reads), the entries off it. */
export type KeptLock = { entries: LockEntry[]; aside: LockEntry[] };

/**
 * `kept` with `incoming` taken: what it is now, whether it began anew (`restart`), whether anything kept changed, and
 * whether the chain's head is another. `fork`: brought as what another keeper took (a station of the lock, a device
 * saying `keep`), every entry the rules take after a parent kept, the chain the rules' fork choice among all of them
 * (station/src/cloud/log-keep.ts `keep`): one that loses is kept aside, one that wins moves the chain to its branch.
 * Else, and for a genesis, a lock turned off or none kept, as `extendLock`: only what goes on from the head. `now`: the
 * cloud's time (unix seconds). Throws LockAppendRefused.
 */
export function keepLockAt(kept: KeptLock, incoming: LockEntry[], now: number, fork: boolean): { kept: KeptLock; restart: boolean; changed: boolean; moved: boolean } {
  const first = kept.entries[0];
  const last = kept.entries.at(-1);
  if (!fork || first === undefined || last!.kind === "disable" || incoming.some((e) => e.seq === 0 && entryHash(e) !== entryHash(first))) {
    const { restart, adding } = extendLock(kept.entries, incoming, now);
    if (adding.length === 0) return { kept, restart: false, changed: false, moved: false };
    const entries = [...(restart ? [] : kept.entries), ...adding.map((a) => a.e)];
    return { kept: { entries, aside: restart ? [] : kept.aside }, restart, changed: true, moved: true };
  }
  const root = entryHash(first);
  const states = new Map<string, LockState>();
  const rules: LogRules = {
    chain: (all) => lockChain(all, root),
    pre: (e) => (e.ws !== first.ws ? "an entry of another workspace's lock" : null),
    // (as extendLock checks one: after its parent, with the cloud's time; signed with a key put in under someone
    // else's name, not kept)
    now: (parent, e, find) => {
      const at = stateAt(parent, find, states);
      if (at === null) return null;
      if (signer(at, e.sig, now)?.own === false) return "signed with a key put in under another's name";
      try {
        apply(at, e, now);
        return null;
      } catch (error) {
        return (error as Error).message;
      }
    },
  };
  let t: ReturnType<typeof keep>;
  try {
    t = keep(kept as unknown as Kept, incoming as unknown as Entry[], rules);
  } catch {
    throw new LockAppendRefused(409, "lock_refused");
  }
  return { kept: t.kept as unknown as KeptLock, restart: false, changed: t.changed, moved: t.moved };
}

/** The lock's state after the entry of hash `h`, along its parents from the nearest state made (`states`); null where they do not go back to the genesis. */
function stateAt(h: string, find: (hash: string) => Entry | undefined, states: Map<string, LockState>): LockState | null {
  const path: Entry[] = [];
  let at: string | null = h;
  while (at !== null && !states.has(at)) {
    const e = find(at);
    if (e === undefined) return null;
    path.push(e);
    at = e.prev;
  }
  let s: LockState | null = at === null ? null : states.get(at)!;
  for (const e of path.reverse()) {
    try {
      s = s === null ? genesis(e) : apply(s, e, null);
    } catch {
      return null;
    }
    states.set(stationEntryHash(e), s);
  }
  return s;
}
