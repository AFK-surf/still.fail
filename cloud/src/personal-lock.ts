// A person's own lock as still.fail cloud keeps it (docs/personal-lock.md): one chain per account, of the devices that
// person signs with. The cloud stores it and carries it to their devices, and takes only entries that follow the kept
// chain and are signed by a device on it, so a stolen login cannot write into a lock; it may start one anew (all of a
// person's devices lost), which the devices that pinned the old one do not follow by themselves. Devices trust nothing
// the cloud says of it.
import { entryHash, signatureOk, signedBytes, type Entry, type Sig } from "../../station/src/cloud/lock.ts";

export type PersonalEntry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: unknown; sig: Sig };

/** At most this many entries in a lock: a person's devices, added and removed. */
export const MAX_ENTRIES = 1024;

const isHex = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]+$/.test(v);

/** An entry as it came, its shape checked; at most 4 KB of it. */
export function asPersonalEntry(v: unknown): PersonalEntry | null {
  const e = v as PersonalEntry | null;
  if (e === null || typeof e !== "object" || e.v !== 1 || typeof e.ws !== "string" || !Number.isSafeInteger(e.seq) || e.seq < 0) return null;
  if (e.prev !== null && !isHex(e.prev)) return null;
  if (!Number.isSafeInteger(e.at) || typeof e.kind !== "string" || typeof e.body !== "object" || e.body === null) return null;
  if (typeof e.sig?.key !== "string" || !e.sig.key.startsWith("ed25519:") || e.sig.alg !== "Ed25519" || !isHex(e.sig.sig)) return null;
  return JSON.stringify(v).length > 4096 ? null : e;
}

const body = (e: PersonalEntry) => e.body as { sub?: unknown; key?: unknown; device?: { key?: unknown } };

/** The keys the chain up to here signs with, and its last hash; throws the code it is refused with. */
export function walk(sub: string, entries: PersonalEntry[]): { keys: Set<string>; hash: string | null } {
  const keys = new Set<string>();
  let hash: string | null = null;
  for (const [i, e] of entries.entries()) {
    if (e.ws !== `person:${sub}` || e.seq !== i || e.prev !== hash) throw new Error("lock_does_not_follow");
    const b = body(e);
    if (i === 0) {
      if (e.kind !== "genesis" || b.sub !== sub || typeof b.device?.key !== "string" || b.device.key !== e.sig.key) throw new Error("lock_refused");
      keys.add(b.device.key);
    } else if (!keys.has(e.sig.key)) throw new Error("lock_refused");
    else if (e.kind === "device" && typeof b.key === "string") keys.add(b.key);
    else if (e.kind === "device.remove" && typeof b.key === "string" && keys.size > 1) keys.delete(b.key);
    else throw new Error("lock_refused");
    hash = entryHash(e as unknown as Entry);
    if (!signatureOk(e.sig.key, Buffer.from(e.sig.sig, "hex"), signedBytes(hash))) throw new Error("lock_refused");
  }
  return { keys, hash };
}

/** What is kept once `adding` comes: a lock begun anew when it starts at its genesis; else the kept one, longer. */
export function extendPersonal(sub: string, kept: PersonalEntry[], raw: unknown): PersonalEntry[] {
  const adding = (Array.isArray(raw) ? raw : []).map(asPersonalEntry);
  if (adding.length === 0 || adding.some((e) => e === null)) throw new Error("invalid_lock_entries");
  const entries = adding as PersonalEntry[];
  const next = entries[0]!.seq === 0 ? entries : [...kept.slice(0, entries[0]!.seq), ...entries];
  if (next.length > MAX_ENTRIES) throw new Error("invalid_lock_entries");
  walk(sub, next);
  return next;
}
