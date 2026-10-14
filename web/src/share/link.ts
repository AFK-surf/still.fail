// A published chat's link (docs/public-share.md): https://share.still.fail/#<station>.<id>.<key>, all of it after the
// `#`, so the browser never sends it anywhere. `station` is the station's iroh key in base64url (43 characters), which
// iroh dials by in hex; `id` the snapshot's (12 bytes, 16 characters); `key` what reads it (32 bytes, 43 characters).

export type ShareLink = { station: string; id: string; key: string };

const LINK = /^#?([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{16})\.([A-Za-z0-9_-]{43})$/;

/** Bytes from base64url (no padding); null for what is not (a last character with bits to spare is not). */
export function fromBase64url(text: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/.test(text) || text.length % 4 === 1) return null;
  const standard = text.replace(/-/g, "+").replace(/_/g, "/");
  const bytes = Uint8Array.from(atob(standard + "=".repeat((4 - (standard.length % 4)) % 4)), (c) => c.charCodeAt(0));
  return toBase64url(bytes) === text ? bytes : null;
}

export function toBase64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

/** The link a page was opened at (its hash), or null when it is not one: cut short, mangled, not one at all. */
export function parseLink(hash: string): ShareLink | null {
  const found = LINK.exec(hash.trim());
  if (!found) return null;
  const station = fromBase64url(found[1]!);
  if (station === null || station.length !== 32) return null;
  return { station: hex(station), id: found[2]!, key: found[3]! };
}

/** The link's hash for a station's key (hex), a snapshot's id and its key: what the station hands out. */
export function linkHash(station: string, id: string, key: string): string {
  const bytes = Uint8Array.from(station.match(/../g) ?? [], (h) => parseInt(h, 16));
  return `#${toBase64url(bytes)}.${id}.${key}`;
}
