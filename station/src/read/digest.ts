// What of a list a client does not hold as it is (POST /changed/<list>, api/routes/changed.ts): a client whose events
// stream could not be resumed reads its lists again, and most of each is as it holds it. It sends each held row's digest;
// made by the core's own function (client/core-ts/src/digest.ts): a row's JSON with its keys
// sorted (a client may hold a row's fields in another order), hashed (cyrb53, 53 bits), in base 36.

import { digest } from "../../../client/core-ts/src/digest.ts";

type Json = any;

/// A row's digest: the core's own (client/core-ts/src/digest.ts).
export { digest };

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
