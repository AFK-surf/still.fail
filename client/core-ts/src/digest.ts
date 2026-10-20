// A row's digest, as a station compares what the core holds of a list with the list as it is (POST /changed/<list>,
// station/src/read/digest.ts, the same, tested on the same values): the row's JSON with its keys sorted (the device
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
