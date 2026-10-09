// A list read again as what changed of it (POST /changed/<list>, with its GET's query): the client sends what it holds
// as each row's digest by its id, `{ held }` (src/read/digest.ts), and is answered `{ order, rows }`, the list's ids in
// order and the rows it does not hold as they are. A client whose events stream could not be resumed reads its lists
// so: most of each is as it holds it.
import { type Answer, type Request, error } from "../request.ts";
import type { Tools } from "../admin.ts";

export function changed(read: Tools["read"], r: Request, op: string, args: Record<string, unknown>, id: string): Promise<Answer> {
  if (r.body.length > 1_000_000) return Promise.resolve(error(413, "request too large"));
  let held: unknown;
  try {
    held = (JSON.parse(r.body.toString("utf8")) as { held?: unknown }).held;
  } catch {
    held = undefined;
  }
  if (held === null || typeof held !== "object" || Array.isArray(held)) return Promise.resolve(error(400, "held: each held row's digest by its id"));
  return read(r, "changed", { op, args, id, held });
}
