// The workspace lock as still.fail cloud keeps it (docs/workspace-lock.md): the cloud only stores the chain and carries
// it, to the stations (their presence sockets) and to members' devices. It checks that each entry follows the last, by
// its hash, so it keeps one chain; whether an entry is signed by whom it may be is for the stations, which trust
// nothing the cloud says of it. The hashing is the stations' (station/src/cloud/lock.ts), tested on the same values.

export type LockEntry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: unknown; sig: unknown };

/** JSON with object keys sorted, no space: what is hashed. Only integers, strings, booleans, null, arrays, objects. */
export function canonical(v: unknown): string {
  if (v === null || typeof v === "boolean" || typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number") {
    if (!Number.isSafeInteger(v)) throw new Error("lock entries hold integers only");
    return String(v);
  }
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (typeof v === "object") {
    const o = v as Record<string, unknown>;
    const keys = Object.keys(o).filter((k) => o[k] !== undefined).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(o[k])}`).join(",")}}`;
  }
  throw new Error("not a lock value");
}

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

/** An entry's hash (hex): of everything but its signature. */
export async function entryHash(e: LockEntry): Promise<string> {
  const { v, ws, seq, prev, at, kind, body } = e;
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`stillfail-lock/1\n${canonical({ v, ws, seq, prev, at, kind, body })}`)));
}

/** An entry as it came: its shape checked (not its signature), at most 64 KB of it. */
export function asEntry(v: unknown): LockEntry | null {
  const e = v as LockEntry;
  if (e === null || typeof e !== "object" || e.v !== 1 || typeof e.ws !== "string" || !Number.isSafeInteger(e.seq) || e.seq < 0) return null;
  if (!(e.prev === null || (typeof e.prev === "string" && /^[0-9a-f]{64}$/.test(e.prev))) || !Number.isSafeInteger(e.at) || typeof e.kind !== "string") return null;
  if (e.sig === null || typeof e.sig !== "object") return null;
  try {
    canonical(e.body ?? null);
    if (JSON.stringify(e).length > 65536) return null;
  } catch {
    return null;
  }
  return e;
}

/** A device's short code, as the device and whoever confirms it work it out (station/src/cloud/lock.ts shortCode). */
export async function shortCode(base: string): Promise<string> {
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`stillfail-lock-code/1\0${base}`)));
  let out = "";
  for (let i = 0; i < 6; i++) out += alphabet[h[i]! % 32];
  return `${out.slice(0, 3)}-${out.slice(3)}`;
}
