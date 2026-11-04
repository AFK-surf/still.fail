// A topic's deltas applied (docs/client-core.md): the pages' (client.ts) and the desktop app's main process's.

import { type AnyOp, applyKeyed } from "../../../client/core-ts/src/collections.ts";

type Path = (string | number)[];

/**
 * One change in a delta (`Op` in client/core-ts/src/delta.ts, keyed ones in client/core-ts/src/collections.ts): the
 * place, and what happens there. Keyed ops change one item of a list found by its key (`key`: the fields it is made
 * of; a key is the one field's value, or the fields' values in order): `put` (a new item before the one keyed
 * `before`, null at the end; without `before`, in place of the one with its key), `patch` (that item's own ops),
 * `drop`, `move` (before `before`). They come only to a subscription made with `keyed: true`.
 */
export type DeltaOp = { path: Path } & (
  | { set: unknown }
  | { append: unknown[] }
  | { remove: true }
  | { key: string[]; put: unknown; before?: unknown }
  | { key: string[]; patch: unknown; ops: DeltaOp[] }
  | { key: string[]; drop: unknown }
  | { key: string[]; move: unknown; before: unknown }
);

/**
 * A delta applied to a value without changing it: only the objects and arrays along each op's path are copied, so
 * unchanged parts keep their identity and React skips them (a keyed op copies its list, never the items it does not
 * change). The core's own applier (client/core-ts/src/collections.ts `applyKeyed`).
 */
export function applyDelta(value: unknown, ops: DeltaOp[]): unknown {
  return applyKeyed(value, ops as AnyOp[]);
}
