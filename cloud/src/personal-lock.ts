// A person's own lock as still.fail cloud keeps it: one chain per account, of the devices that
// person signs with. The cloud stores it and carries it to their devices, and takes only entries that follow the kept
// chain and are signed by a device on it (the rules' own check, station/src/cloud/lock.ts `personFold`), so a stolen
// login cannot write into a lock; it may start one anew (all of a person's devices lost), which the devices that pinned
// the old one do not follow by themselves. Devices trust nothing the cloud says of it.
import { personFold } from "../../station/src/cloud/lock.ts";

export type PersonalEntry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: unknown; sig: unknown };

/** At most this many entries in a lock: a person's devices, added and removed. */
export const MAX_ENTRIES = 1024;
/** At most this much of one entry. */
const MAX_ENTRY = 4096;

/** What is kept once `raw` comes: a lock begun anew when it starts at its genesis; else the kept one, longer. Throws the code it is refused with. */
export function extendPersonal(sub: string, kept: PersonalEntry[], raw: unknown): PersonalEntry[] {
  const adding = Array.isArray(raw) ? (raw as PersonalEntry[]) : [];
  const shaped = (e: PersonalEntry) => e !== null && typeof e === "object" && Number.isSafeInteger(e.seq) && e.seq >= 0 && JSON.stringify(e).length <= MAX_ENTRY;
  if (adding.length === 0 || !adding.every(shaped)) throw new Error("invalid_lock_entries");
  const next = adding[0]!.seq === 0 ? adding : [...kept.slice(0, adding[0]!.seq), ...adding];
  if (next.length > MAX_ENTRIES) throw new Error("invalid_lock_entries");
  try {
    personFold(next, sub);
  } catch {
    throw new Error("lock_refused");
  }
  return next;
}
