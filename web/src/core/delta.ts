// A topic's deltas applied (docs/client-core.md): the pages' (client.ts) and the desktop app's main process's.

/** One change in a delta (`Op` in client/core/src/delta.rs): the place, and what happens there. */
export type DeltaOp = { path: (string | number)[] } & ({ set: unknown } | { append: unknown[] } | { remove: true });

/**
 * A delta applied to a value without changing it: only the objects and arrays
 * along each op's path are copied, so unchanged parts keep their identity and
 * React skips them.
 */
export function applyDelta(value: unknown, ops: DeltaOp[]): unknown {
  return ops.reduce((current, op) => applyOp(current, op, 0), value);
}

function applyOp(node: unknown, op: DeltaOp, depth: number): unknown {
  if (depth === op.path.length) {
    if ("set" in op) return op.set;
    if ("append" in op) return Array.isArray(node) ? [...node, ...op.append] : node;
    return node;
  }
  const key = op.path[depth]!;
  if (Array.isArray(node)) {
    if (typeof key !== "number" || key >= node.length) return node;
    const copy = node.slice();
    copy[key] = applyOp(node[key], op, depth + 1);
    return copy;
  }
  if (typeof node !== "object" || node === null || typeof key !== "string") return node;
  const object = node as Record<string, unknown>;
  if ("remove" in op && depth === op.path.length - 1) {
    const rest = { ...object };
    delete rest[key];
    return rest;
  }
  return { ...object, [key]: applyOp(object[key], op, depth + 1) };
}
