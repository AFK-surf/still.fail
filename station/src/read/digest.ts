// What of a list a client does not hold as it is (POST /changed/<list>, api/routes/changed.ts): a client whose events
// stream could not be resumed reads its lists again, and most of each is as it holds it. It sends each held row's digest;
// the core makes them the same way (client/core-ts/src/digest.ts, tested on the same values): a row's JSON with its keys
// sorted (a client may hold a row's fields in another order), hashed (cyrb53, 53 bits), in base 36.

type Json = any;

/// A row's digest.
export function digest(v: unknown): string {
  return hash(canonical(v)).toString(36);
}

/// What of `list` a client holding `held` (each row's digest by its id, `id` the field that names a row) does not hold
/// as it is: the list's order by id, and its rows whose digest differs or that are not held, as a client reads them
/// (the list through JSON).
export function changedOf(list: unknown, id: string, held: unknown): { order: unknown[]; rows: Json[] } {
  const have = new Map<string, unknown>(held !== null && typeof held === "object" ? Object.entries(held) : []);
  const rows = JSON.parse(JSON.stringify(list ?? [])) as Json;
  const order: unknown[] = [];
  const out: Json[] = [];
  for (const row of Array.isArray(rows) ? rows : []) {
    const key = row !== null && typeof row === "object" && !Array.isArray(row) ? row[id] : undefined;
    order.push(key ?? null);
    if (key === undefined || key === null || have.get(String(key)) !== digest(row)) out.push(row);
  }
  return { order, rows: out };
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
