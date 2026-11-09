// The workspace lock as still.fail cloud keeps it: the cloud stores the chain and carries it,
// to the stations (their presence sockets) and to members' devices. It keeps one chain, each entry following the last,
// and only entries a station takes: checked by the stations' own rules (station/src/cloud/lock.ts `genesis`/`apply`),
// as one it kept that they refuse leaves every entry after it refused too. The stations trust nothing the cloud says
// of it all the same. The hashing is the stations' own (their lock.ts).
export { apply, canonical, genesis, shortCode, type Entry, type LockState } from "../../station/src/cloud/lock.ts";
import { apply, asEntry as stationAsEntry, entryHash as stationEntryHash, genesis, signer, type Entry, type LockState } from "../../station/src/cloud/lock.ts";

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
