// The workspace lock's forms (docs/workspace-lock.md), one for the stations (station/src/cloud/lock.ts), the cloud
// (cloud/src/lock.ts, which takes the stations') and devices (lock.ts): what is hashed and how a short code is read off
// a hash. Pure: each side hashes with its own SHA-256 (node's, or @noble's where there is no node).

/// JSON with object keys sorted, no space: what is hashed. Only integers, strings, booleans, null, arrays, objects;
/// `invalid` makes the error for anything else (the core's own kind there).
export function canonical(v: unknown, invalid: (why: string) => Error = (why) => new Error(why)): string {
  if (v === null || typeof v === "boolean" || typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number") {
    if (!Number.isSafeInteger(v)) throw invalid("lock entries hold integers only");
    return String(v);
  }
  if (Array.isArray(v)) return `[${v.map((x) => canonical(x, invalid)).join(",")}]`;
  if (typeof v === "object") {
    const o = v as Record<string, unknown>;
    const keys = Object.keys(o).filter((k) => o[k] !== undefined).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(o[k], invalid)}`).join(",")}}`;
  }
  throw invalid("not a lock value");
}

/// What an entry's hash is of: everything but its signature.
export type Hashed = { v: number; ws: string; seq: number; prev: string | null; at: number; kind: string; body: unknown };
export function entryText(e: Hashed, invalid?: (why: string) => Error): string {
  const { v, ws, seq, prev, at, kind, body } = e;
  return `stillfail-lock/1\n${canonical({ v, ws, seq, prev, at, kind, body }, invalid)}`;
}

/// What a device's short code is the hash of: its base key, tagged.
export const codeText = (base: string) => `stillfail-lock-code/1\0${base}`;

/// A device's short code from the hash of `codeText`: what a person compares, on the new device and where it is
/// confirmed.
export function shortCodeOf(hash: Uint8Array): string {
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  let out = "";
  for (let i = 0; i < 6; i++) out += alphabet[hash[i]! % 32];
  return `${out.slice(0, 3)}-${out.slice(3)}`;
}
