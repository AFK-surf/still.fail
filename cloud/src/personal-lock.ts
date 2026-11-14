// A person's own lock as still.fail cloud keeps it: one chain per account, of the devices that
// person signs with. The cloud stores it and carries it to their devices, and takes only entries that follow the kept
// chain and are signed by a device on it (the rules' own check, station/src/cloud/lock.ts `personFold`), so a stolen
// login cannot write into a lock; it may start one anew (all of a person's devices lost), which the devices that pinned
// the old one do not follow by themselves. Devices trust nothing the cloud says of it. What a device brings saying
// `keep` (what a station took) is kept as a station keeps a person's lock (station/src/mesh/person-chains.ts): every
// entry the rules take after a parent kept, the chain the rules' fork choice among them, the rest kept aside
// (`extendPersonalKept`); what it brings without it, as before.
import { type Entry, entryHash, personChain, personFold } from "../../station/src/cloud/lock.ts";
import { type Kept, keep } from "../../station/src/cloud/log-keep.ts";

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

/** A person's lock as kept: its chain gone by (what every reader reads), and the entries off it. */
export type PersonalKept = { entries: PersonalEntry[]; aside: PersonalEntry[] };

/** Round three's statements of a workspace in the clear, refused as personFold refuses them (station/src/mesh/person-chains.ts). */
const STATEMENTS = new Set(["ws.member", "ws.member.remove", "ws.station", "ws.station.remove"]);

/**
 * What is kept once `raw` comes saying another keeper took it (`keep`): every entry the rules take after a parent kept,
 * the chain the rules' fork choice among all (station/src/cloud/log-keep.ts), at most ASIDE_MOST aside. Where none is
 * kept, or it brings another genesis, as `extendPersonal`. Throws the code it is refused with.
 */
export function extendPersonalKept(sub: string, kept: PersonalKept, raw: unknown): PersonalKept {
  const adding = Array.isArray(raw) ? (raw as PersonalEntry[]) : [];
  const first = kept.entries[0];
  const root = first === undefined ? null : entryHash(first as unknown as Entry);
  if (root === null || adding.some((e) => e?.seq === 0 && entryHash(e as unknown as Entry) !== root)) {
    const entries = extendPersonal(sub, kept.entries, raw);
    return { entries, aside: entries[0] === first ? kept.aside : [] };
  }
  const shaped = (e: PersonalEntry) => e !== null && typeof e === "object" && Number.isSafeInteger(e.seq) && e.seq >= 0 && JSON.stringify(e).length <= MAX_ENTRY;
  if (adding.length === 0 || adding.length > MAX_ENTRIES || !adding.every(shaped)) throw new Error("invalid_lock_entries");
  const ws = `person:${sub}`;
  let next: Kept;
  try {
    next = keep(kept as unknown as Kept, adding as unknown as Entry[], {
      chain: (all) => personChain(all, root),
      pre: (e) => (e.ws !== ws ? "an entry of another lock" : STATEMENTS.has(e.kind) ? `unknown entry kind ${e.kind}` : null),
    }).kept;
    if (next.entries.length > MAX_ENTRIES) throw new Error("too long");
    personFold(next.entries, sub);
  } catch {
    throw new Error("lock_refused");
  }
  return next as unknown as PersonalKept;
}
