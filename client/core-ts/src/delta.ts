// What changed between two values of a topic, as a few ops (delta.rs), so a long transcript that grew by one message
// goes out as one `append`. Objects are compared key by key (in the order serde_json keeps them: sorted), an array
// that only grew is an `append`, one of the same length is compared item by item, anything else is `set` whole.
import { compareKeys, equal, isObject } from "./util.ts";

export type Segment = string | number;
export type Op = { path: Segment[]; set: unknown } | { path: Segment[]; append: unknown[] } | { path: Segment[]; remove: true };

/// The ops that turn `old` into `next`; empty when they are equal.
export function diff(old: unknown, next: unknown): Op[] {
  const ops: Op[] = [];
  diffAt([], old, next, ops);
  return ops;
}

function diffAt(path: Segment[], old: unknown, next: unknown, ops: Op[]): void {
  if (old === next) return;
  if (isObject(old) && isObject(next)) {
    for (const key of Object.keys(next).sort(compareKeys)) {
      path.push(key);
      if (Object.prototype.hasOwnProperty.call(old, key)) diffAt(path, old[key], next[key], ops);
      else ops.push({ path: [...path], set: next[key] });
      path.pop();
    }
    for (const key of Object.keys(old).sort(compareKeys)) {
      if (!Object.prototype.hasOwnProperty.call(next, key)) ops.push({ path: [...path, key], remove: true });
    }
    return;
  }
  if (Array.isArray(old) && Array.isArray(next)) {
    if (old.length === next.length) {
      for (let i = 0; i < old.length; i++) {
        path.push(i);
        diffAt(path, old[i], next[i], ops);
        path.pop();
      }
      return;
    }
    if (old.length < next.length && old.every((v, i) => equal(v, next[i]))) {
      ops.push({ path: [...path], append: next.slice(old.length) });
      return;
    }
  }
  if (equal(old, next)) return;
  ops.push({ path: [...path], set: next });
}

/// Applies ops made by `diff`; an op whose path does not fit the value is skipped. Returns the new value (the root
/// may be replaced).
export function apply(value: unknown, ops: Op[]): unknown {
  const root = { v: value };
  for (const op of ops) {
    const path: Segment[] = ["v", ...op.path];
    if ("remove" in op) {
      const key = path[path.length - 1];
      if (typeof key !== "string" || path.length < 2) continue;
      const parent = place(root, path.slice(0, -1), false);
      if (parent && isObject(parent.holder[parent.key])) delete (parent.holder[parent.key] as Record<string, unknown>)[key];
      continue;
    }
    const at = place(root, path, true);
    if (!at) continue;
    if ("set" in op) at.holder[at.key] = op.set;
    else if (Array.isArray(at.holder[at.key])) (at.holder[at.key] as unknown[]).push(...op.append);
  }
  return root.v;
}

/// Where `path` is: its holder and key; a missing last key is made in its object.
function place(root: Record<string, unknown>, path: Segment[], make: boolean): { holder: Record<string | number, unknown>; key: string | number } | null {
  let holder: Record<string | number, unknown> = root;
  for (let i = 0; i < path.length; i++) {
    const key = path[i];
    if (i === path.length - 1) {
      if (typeof key === "number") return Array.isArray(holder) && key < holder.length ? { holder, key } : null;
      if (!(key in holder) && make) holder[key] = null;
      return { holder, key };
    }
    const next = holder[key];
    const nk = path[i + 1];
    if (typeof nk === "number" ? !Array.isArray(next) : !isObject(next)) return null;
    holder = next as Record<string | number, unknown>;
  }
  return null;
}

/// Whether `ops` take more bytes as JSON than `value` itself: then the value is sent whole. Counted, not written out:
/// writing the whole value as sorted JSON and encoding it, on every change of a topic, was much of what the core did on
/// a phone (2026-10-19); the value is counted only as far as the ops' size.
export function largerThan(ops: Op[], value: unknown): boolean {
  const size = jsonLength(ops);
  return jsonLength(value, size) <= size;
}

const PAST = Symbol("past");

/// How many bytes `v` takes as JSON in UTF-8 (`utf8(toJson(v)).length`: the order of its keys changes nothing), or
/// some number above `limit` once it is past it.
export function jsonLength(v: unknown, limit = Number.POSITIVE_INFINITY): number {
  let n = 0;
  const add = (k: number): void => {
    n += k;
    if (n > limit) throw PAST;
  };
  const go = (x: unknown, inList: boolean): void => {
    if (x === null) return add(4);
    switch (typeof x) {
      case "string":
        return add(utf8Length(JSON.stringify(x)));
      case "number":
        return add(JSON.stringify(x).length);
      case "boolean":
        return add(x ? 4 : 5);
      case "object":
        break;
      default:
        // undefined, a function: null in a list, left out of an object (JSON.stringify's rules).
        if (inList) add(4);
        return;
    }
    const o = x as { toJSON?: () => unknown };
    if (typeof o.toJSON === "function") return go(o.toJSON(), inList);
    if (Array.isArray(x)) {
      add(2 + Math.max(0, x.length - 1));
      for (const item of x) go(item, true);
      return;
    }
    add(2);
    let first = true;
    for (const k of Object.keys(x)) {
      const item = (x as Record<string, unknown>)[k];
      if (item === undefined || typeof item === "function" || typeof item === "symbol") continue;
      add((first ? 0 : 1) + utf8Length(JSON.stringify(k)) + 1);
      first = false;
      go(item, false);
    }
  };
  try {
    go(v, false);
  } catch (e) {
    if (e === PAST) return n;
    throw e;
  }
  return n;
}

/// A string's length in UTF-8, as TextEncoder makes it (a lone surrogate is U+FFFD, three bytes).
function utf8Length(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) n += 1;
    else if (c < 0x800) n += 2;
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length && (s.charCodeAt(i + 1) & 0xfc00) === 0xdc00) {
      n += 4;
      i++;
    } else n += 3;
  }
  return n;
}
