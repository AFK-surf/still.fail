// A row's digest, as a station compares what the core holds of a list with the list as it is (POST /changed/<list>,
// station/src/read/digest.ts uses this one): the row's JSON with its keys sorted (the device
// keeps some of a row's fields apart and puts them back last), hashed (cyrb53, 53 bits), in base 36.

/// The digests of rows that cannot change (frozen, as the device's records hold them): made once.
const made = new WeakMap<object, string>();

export function digest(v: unknown): string {
  if (v === null || typeof v !== "object" || !Object.isFrozen(v)) return hash(canonical(v)).toString(36);
  let d = made.get(v);
  if (d === undefined) {
    d = hash(canonical(v)).toString(36);
    made.set(v, d);
  }
  return d;
}

/// The version of a topic's value as it went to a subscriber (store.ts: a subscription's `have`, an unsubscribe's
/// `v`): its canonical JSON's length and its hash, `<length>:<hash>` in base 36. Made of the value alone, so a topic
/// evicted and made again still answers `same` to a version a client kept, and nothing of it is kept to answer that
/// (what the store remembers for a client, `#kept`, is only to send what changed where it is not the same). The
/// length beside the hash makes two values taken for one (cyrb53 is 53 bits, not a cryptographic hash) the less likely
/// still; were the way it is made ever changed, a version kept from before would match nothing, and the value would
/// only go whole again.
export function version(v: unknown): string {
  if (v === null || typeof v !== "object" || !Object.isFrozen(v)) return versionOf(canonical(v));
  let d = versions.get(v);
  if (d === undefined) {
    d = versionOf(canonical(v));
    versions.set(v, d);
  }
  return d;
}

/// The versions of values that cannot change (frozen): made once.
const versions = new WeakMap<object, string>();

function versionOf(c: string): string {
  return `${c.length.toString(36)}:${hash(c).toString(36)}`;
}

/// JSON with every object's keys sorted.
function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map((x) => (x === undefined ? "null" : canonical(x))).join(",")}]`;
  if (v !== null && typeof v === "object") {
    const o = v as Record<string, unknown>;
    const keys = Object.keys(o).filter((k) => o[k] !== undefined).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(v) ?? "null";
}

/// cyrb53: 53 bits of a string's UTF-16 units.
function hash(s: string): number {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 2654435761);
    h2 = Math.imul(h2 ^ c, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
  h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
  h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return 4294967296 * (2097151 & h2) + (h1 >>> 0);
}
