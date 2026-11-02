// The workspace lock as still.fail cloud keeps it (docs/workspace-lock.md): the cloud stores the chain and carries it,
// to the stations (their presence sockets) and to members' devices. It keeps one chain, each entry following the last,
// and only entries a station takes: checked by the stations' own rules (station/src/cloud/lock.ts `genesis`/`apply`),
// as one it kept that they refuse leaves every entry after it refused too. The stations trust nothing the cloud says
// of it all the same. The hashing is the stations' own (their lock.ts).
export { apply, canonical, genesis, shortCode, type Entry, type LockState } from "../../station/src/cloud/lock.ts";
import { asEntry as stationAsEntry, entryHash as stationEntryHash, type Entry } from "../../station/src/cloud/lock.ts";

export type LockEntry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: unknown; sig: unknown };

/** An entry's hash (hex): of everything but its signature, as the stations hash it. */
export const entryHash = (e: LockEntry): string => stationEntryHash(e as unknown as Entry);

/** An entry as it came: its shape checked as the stations check it (not its signature), at most 64 KB of it. */
export function asEntry(v: unknown): LockEntry | null {
  if (stationAsEntry(v) === null || JSON.stringify(v).length > 65536) return null;
  return v as LockEntry;
}

