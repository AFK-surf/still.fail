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

/// A value's version made of its content: its canonical JSON's length and its hash, `<length>:<hash>` in base 36. What
/// a topic's value that is no object goes by (`token`). The length beside the hash makes two values taken for one
/// (cyrb53 is 53 bits, not a cryptographic hash) the less likely still.
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

/// The version of a topic's value as it went to a subscriber (store.ts: an unsubscribe's `v`, a subscription's `have`):
/// a token of the value object itself, `<run>:<count>` in base 36, given it the first time one is asked, never of what it
/// holds. A topic's value is the same object for as long as it is unchanged (what is shared is never written: the
/// core's AGENTS.md), so the same token says the same value with nothing hashed: hashing the value whole was 5.9 ms of
/// every switch of workspace for the 55 KB `profiles` let go of (Hermes, Mac Studio, 2026-11-12). A value made again
/// equal (its topic evicted and opened again) is another object and another token: where the store remembers what the
/// client kept (`#kept`), what changed from that goes, empty; else the value whole. `<run>` is made at random once a
/// core starts, so a token kept from another run, or from before a restart, matches nothing. A value that is no object
/// (a number, a string, null) goes by its content (`version`).
export function token(v: unknown): string {
  if (v === null || typeof v !== "object") return version(v);
  let t = tokens.get(v);
  if (t === undefined) {
    t = `${run()}:${(given++).toString(36)}`;
    tokens.set(v, t);
  }
  return t;
}

/// The tokens given (token), by the value they were given.
const tokens = new WeakMap<object, string>();
let given = 0;
let runId: string | null = null;

/// This core run's own part of a token, made at random as the first is given.
function run(): string {
  runId ??= Array.from(crypto.getRandomValues(new Uint8Array(6)), (b) => b.toString(36).padStart(2, "0")).join("");
  return runId;
}

/// A short name for a long text that changes when it does (a picture's base64 or data: URL, peek-pictures.ts): its
/// cyrb53 and its length, in base 36.
export function textHash(s: string): string {
  return `${hash(s).toString(36)}-${s.length.toString(36)}`;
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
