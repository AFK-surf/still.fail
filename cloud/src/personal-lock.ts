// A person's own lock as still.fail cloud keeps it (docs/personal-lock.md): one chain per account, of the devices that
// person signs with. The cloud stores it and carries it to their devices, and takes only entries that follow the kept
// chain and are signed by a device on it (the rules' own check, station/src/cloud/lock.ts `personFold`), so a stolen
// login cannot write into a lock; it may start one anew (all of a person's devices lost), which the devices that pinned
// the old one do not follow by themselves. Devices trust nothing the cloud says of it.
import { entryHash, personFold, type Entry } from "../../station/src/cloud/lock.ts";

// Only the fields the rules use cross the account object's typed RPC boundary. The rules validate their values;
// additional JSON fields in an entry are preserved when the entry is stored and sent on.
export type PersonalBody = { sub?: string; device?: { key: string; id: string; label: string }; key?: string; id?: string; label?: string };
export type PersonalEntry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: PersonalBody; sig: { key: string; alg: string; sig: string } };

/** At most this many entries in a lock: a person's devices, added and removed. */
export const MAX_ENTRIES = 1024;
/** At most this much of one entry. */
const MAX_ENTRY = 4096;

/** The same genesis keeps its entire accepted prefix; a distinct genesis starts a new lock. */
export function extendPersonal(sub: string, kept: PersonalEntry[], raw: unknown): PersonalEntry[] {
  const adding = Array.isArray(raw) ? (raw as PersonalEntry[]) : [];
  const shaped = (e: PersonalEntry) => e !== null && typeof e === "object" && Number.isSafeInteger(e.seq) && e.seq >= 0 && JSON.stringify(e).length <= MAX_ENTRY;
  if (adding.length === 0 || !adding.every(shaped)) throw new Error("invalid_lock_entries");
  if (adding.length > MAX_ENTRIES) throw new Error("invalid_lock_entries");
  let next: PersonalEntry[];
  try {
    const hash = (e: PersonalEntry) => entryHash(e as unknown as Entry);
    const start = adding[0]!.seq;
    if (start === 0 && (kept.length === 0 || hash(adding[0]!) !== hash(kept[0]!))) {
      next = adding;
    } else {
      if (start > kept.length) throw new Error("not following the kept chain");
      const overlap = Math.min(adding.length, kept.length - start);
      for (let i = 0; i < overlap; i++) {
        if (hash(adding[i]!) !== hash(kept[start + i]!)) throw new Error("a different accepted entry");
      }
      // A retry may overlap the accepted chain, but may neither replace nor shorten it.
      next = [...kept, ...adding.slice(overlap)];
    }
  } catch {
    throw new Error("lock_refused");
  }
  if (next.length > MAX_ENTRIES) throw new Error("invalid_lock_entries");
  try {
    personFold(next, sub);
  } catch {
    throw new Error("lock_refused");
  }
  return next;
}
