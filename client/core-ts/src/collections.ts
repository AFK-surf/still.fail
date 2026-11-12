// Keyed collections (rule 7 and 按 key 的增量): where a topic's value holds lists of items with a
// stable id, and the delta that changes them item by item. A row that changed is one `patch` of that row, wherever it
// is; a row that moved is a `move`; a new one a `put` before its neighbour; one gone a `drop`. The rest of the value
// changes by the old ops (delta.ts). A list whose keys are not each once there (or not all there) goes the old way.
import { type Op, type Segment, diffAt, jsonLength, largerThan } from "./delta.ts";
import type { Topic } from "./protocol.ts";
import { compareKeys, equal, isObject } from "./util.ts";
import { walked, work } from "./work.ts";

/// Where the keyed lists of a value are: `key` (the fields an item's key is made of) says the value at this place is
/// one; `item` where the keyed lists of each item are; `fields` those of an object's fields.
export type Spec = { key?: string[]; item?: Spec; fields?: Record<string, Spec> };

/// A key as it goes out: the one field's value, or the fields' values in order.
export type Key = unknown;

export type KeyedOp =
  | { path: Segment[]; key: string[]; put: unknown; before?: Key | null }
  | { path: Segment[]; key: string[]; patch: Key; ops: AnyOp[] }
  | { path: Segment[]; key: string[]; drop: Key }
  | { path: Segment[]; key: string[]; move: Key; before: Key | null };

export type AnyOp = Op | KeyedOp;

const items = (key: string): Spec => ({ key: [key] });
const rows: Spec = { key: ["station", "id"] };

/// Each topic's keyed lists.
const SPECS: Record<string, Spec> = {
  chats: { fields: { days: { key: ["daysAgo"], item: { fields: { items: rows } } } } },
  chatSearch: { fields: { items: rows, messages: { key: ["station", "thread", "seq"] } } },
  search: { fields: { items: rows, messages: { key: ["station", "thread", "seq"] }, groups: { key: ["kind"], item: { fields: { items: items("key") } } } } },
  chat: { fields: { messages: { key: ["seq", "outgoing"] }, outbox: items("id") } },
  archive: { fields: { days: { key: ["label"], item: { fields: { items: rows } } } } },
  chatRows: items("id"),
  archivedRows: items("id"),
  threads: items("id"),
  sessions: items("key"),
  jobs: items("id"),
  history: { fields: { items: items("key") } },
  // (by the date: a heading changing at midnight patches it, its seqs not sent again)
  chatOutline: { fields: { days: { key: ["date"] } } },
  // (a page more of a tab: its new days and changes alone, a day it ends in patched)
  changelog: { fields: { tabs: { key: ["part"], item: { fields: { days: { key: ["day"], item: { fields: { entries: items("version") } } } } } } } },
  vaults: { fields: { vaults: items("id"), requests: items("id") } },
  vaultItems: { fields: { items: items("id") } },
  driveTransfers: { fields: { transfers: { key: ["station", "id"] } } },
  downloads: { fields: { downloads: items("id") } },
  // (a job's log's lines by their numbers, log-lines.ts: a line more put, the first gone dropped, the last rewritten patched)
  jobLog: { fields: { lines: items("n") } },
  // (a station's item changes as it says something new, each a few seconds: the others go out as they went)
  stations: items("station"),
  newChat: { fields: { stations: items("station") } },
};

export function specOf(topic: Topic): Spec | null {
  return SPECS[topic.topic] ?? MODULES.get(topic.topic) ?? null;
}

/// Modules' topics' keyed lists (module.ts), by topic name: each under its module's name, so none is the core's.
const MODULES = new Map<string, Spec>();

export function addSpec(topic: string, spec: Spec): void {
  if (topic in SPECS) throw new Error(`the core's own topic: ${topic}`);
  MODULES.set(topic, spec);
}

/// An item's key: the fields' values (a field missing is null).
export function keyOf(item: unknown, fields: string[]): Key {
  const v = (f: string) => (isObject(item) && item[f] !== undefined ? item[f] : null);
  return fields.length === 1 ? v(fields[0]!) : fields.map(v);
}

const text = (k: Key) => JSON.stringify(k);

/// The ops (keyed where `spec` says) that turn `old` into `next`; empty when they are equal.
export function diffKeyed(old: unknown, next: unknown, spec: Spec | null): AnyOp[] {
  const ops: AnyOp[] = [];
  at([], old, next, spec, ops);
  return ops;
}

function at(path: Segment[], old: unknown, next: unknown, spec: Spec | null, ops: AnyOp[]): void {
  if (old === next) return;
  // Nothing keyed below: delta.ts's own.
  if (spec === null) return diffAt([...path], old, next, ops as Op[]);
  if (spec?.key && Array.isArray(old) && Array.isArray(next) && list(path, old, next, spec, ops)) return;
  if (isObject(old) && isObject(next)) {
    // Only the keys that may differ are put in order, as delta.ts diffAt.
    const has = Object.prototype.hasOwnProperty;
    const changed: string[] = [];
    for (const key of Object.keys(next)) if (!has.call(old, key) || old[key] !== next[key]) changed.push(key);
    if (changed.length > 1) changed.sort(compareKeys);
    for (const key of changed) {
      if (has.call(old, key)) at([...path, key], old[key], next[key], spec?.fields?.[key] ?? null, ops);
      else ops.push({ path: [...path, key], set: next[key] });
    }
    const gone: string[] = [];
    for (const key of Object.keys(old)) if (!has.call(next, key)) gone.push(key);
    if (gone.length > 1) gone.sort(compareKeys);
    for (const key of gone) ops.push({ path: [...path, key], remove: true });
    return;
  }
  if (Array.isArray(old) && Array.isArray(next)) {
    if (old.length === next.length) {
      for (let i = 0; i < old.length; i++) at([...path, i], old[i], next[i], spec?.item ?? null, ops);
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

/// `next`, with each part of it equal to the same part of `prev` (a field's value; the item with the same key of a keyed
/// list, else the one at the same place) taken from `prev`, and `prev` itself where all of it is equal. The store keeps
/// a topic's new value so (store.ts): what did not change is the object that went out before, so what follows (the
/// diff, the weighing, the items' shaping) steps over it, and a source that made all of it again costs one comparison.
export function share<T>(prev: unknown, next: T, spec: Spec | null): T {
  return shareAt(prev, next, spec) as T;
}
function shareAt(prev: unknown, next: unknown, spec: Spec | null): unknown {
  if (prev === next || typeof next !== "object" || next === null || typeof prev !== "object" || prev === null) return next;
  work.compared++;
  walked.shared++;
  let out: unknown;
  if (Array.isArray(next)) {
    if (!Array.isArray(prev)) return next;
    const fields = spec?.key;
    // (each item mapped, and a keyed list's last items each put in its map)
    const looked = next.length + (fields ? prev.length : 0);
    walked.shared += looked;
    let byKey: Map<string, unknown> | null = null;
    if (fields) {
      byKey = new Map();
      for (const item of prev) byKey.set(textOf(item, fields), item);
    }
    let all = prev.length === next.length;
    const items = next.map((item, i) => {
      const kept = shareAt(byKey ? byKey.get(textOf(item, fields!)) : prev[i], item, spec?.item ?? null);
      if (kept !== prev[i]) all = false;
      return kept;
    });
    out = all ? prev : items;
  } else {
    if (!isObject(prev) || !isObject(next)) return next;
    const keys = Object.keys(next);
    let all = keys.length === Object.keys(prev).length;
    const fields: Record<string, unknown> = {};
    for (const key of keys) {
      const kept = shareAt(prev[key], next[key], spec?.fields?.[key] ?? null);
      if (kept !== prev[key] || !(key in prev)) all = false;
      fields[key] = kept;
    }
    out = all ? prev : fields;
  }
  if (out === prev) work.remade++;
  return out;
}

/// An item's key as text, kept with the item (an object kept from one value to the next is not written out again).
const texts = new WeakMap<string[], WeakMap<object, string>>();
export function textOf(item: unknown, fields: string[]): string {
  if (item === null || typeof item !== "object") return text(keyOf(item, fields));
  let byItem = texts.get(fields);
  if (!byItem) texts.set(fields, (byItem = new WeakMap()));
  let t = byItem.get(item);
  if (t === undefined) {
    work.keyed++;
    byItem.set(item, (t = text(keyOf(item, fields))));
  }
  return t;
}

/// Keys of a list, each once; null when one is there twice.
function keysOf(list: unknown[], fields: string[]): string[] | null {
  const out = list.map((item) => textOf(item, fields));
  return new Set(out).size === out.length ? out : null;
}

/// A keyed list's ops: drops, then from the last item on, each new one put and each moved one moved before the one
/// after it (those in the longest run kept in order stay), and each changed one patched. False: not keyed (a key twice).
/// The same objects at its start and its end stay as they are: only what is between them is matched, so a message
/// added to a chat costs that message.
function list(path: Segment[], old: unknown[], next: unknown[], spec: Spec, ops: AnyOp[]): boolean {
  const fields = spec.key!;
  // (the old list walked to its first item not the same; its keys and the new one's taken whole, below)
  const same = old.length === next.length && old.every((item, i) => item === next[i]);
  const looked = same ? old.length : old.length + next.length;
  walked.diffed += looked;
  if (same) return true;
  const allOld = keysOf(old, fields);
  const allNext = keysOf(next, fields);
  if (!allOld || !allNext) return false;
  let start = 0;
  while (start < old.length && start < next.length && old[start] === next[start]) start++;
  let oldEnd = old.length;
  let nextEnd = next.length;
  while (oldEnd > start && nextEnd > start && old[oldEnd - 1] === next[nextEnd - 1]) {
    oldEnd--;
    nextEnd--;
  }
  const oldKeys = allOld.slice(start, oldEnd);
  const nextKeys = allNext.slice(start, nextEnd);
  const was = new Map(oldKeys.map((k, i) => [k, start + i]));
  const now = new Set(nextKeys);
  const out: AnyOp[] = [];
  for (let i = start; i < oldEnd; i++) {
    if (!now.has(allOld[i]!)) out.push({ path: [...path], key: fields, drop: keyOf(old[i], fields) });
  }
  // Where each kept one was among the kept (in the new order), and which of them stay.
  const positions = nextKeys.map((k) => was.get(k) ?? -1);
  // Mostly new (a list loaded after its first screen): it goes whole, not item by item.
  const fresh = positions.reduce((n, p) => n + (p < 0 ? 1 : 0), 0);
  if (fresh > LONG && fresh * 2 > next.length) {
    ops.push({ path: [...path], set: next });
    return true;
  }
  const stay = longestRun(positions);
  for (let j = positions.length - 1; j >= 0; j--) {
    const i = start + j;
    const before = i + 1 < next.length ? keyOf(next[i + 1], fields) : null;
    const from = positions[j]!;
    if (from < 0) {
      out.push({ path: [...path], key: fields, put: next[i], before });
      continue;
    }
    if (!stay.has(j)) out.push({ path: [...path], key: fields, move: keyOf(next[i], fields), before });
    const changes = diffKeyed(old[from], next[i], spec.item ?? null);
    if (changes.length === 0) continue;
    const key = keyOf(next[i], fields);
    const put = !setsLongList(changes) && largerThan(changes as Op[], next[i]);
    out.push(put ? { path: [...path], key: fields, put: next[i] } : { path: [...path], key: fields, patch: key, ops: changes });
  }
  // A list that changed all through goes whole.
  if (out.length > 0 && heavier(out, next)) ops.push({ path: [...path], set: next });
  else ops.push(...out);
  return true;
}

/// Whether ops take as many bytes as the value they make: then it goes whole. Ops of a few KB are taken as lighter
/// without writing out the value (a list of 2000 rows is 100 KB: weighing it on every change is the cost saved).
export function heavier(ops: AnyOp[], value: unknown): boolean {
  // One value set whole: as heavy as the value where it is all of it, lighter where it is a part.
  if (ops.length === 1 && "set" in ops[0]!) return ops[0]!.path.length === 0;
  // Ops that set a long list whole (one loaded after its first screen) are about as heavy as the value: not weighed.
  if (setsLongList(ops)) return false;
  const size = jsonLength(ops);
  work.weighed += size;
  // (the value counted only as far as the ops' size: a chat's 50 messages written out on each new one was what its
  // change cost most of, 2026-11-08)
  if (size <= 4096) return false;
  const whole = jsonLength(value, size);
  work.weighed += Math.min(whole, size + 1);
  return whole <= size;
}

/// Whether ops set a list of more than LONG items whole, anywhere in them.
const LONG = 256;
function setsLongList(ops: AnyOp[]): boolean {
  for (const op of ops) {
    if ("set" in op && Array.isArray(op.set) && op.set.length > LONG) return true;
    if ("patch" in op && setsLongList(op.ops)) return true;
  }
  return false;
}

/// The indexes (into `positions`) of a longest increasing run of its non-negative values.
function longestRun(positions: number[]): Set<number> {
  const tails: number[] = []; // index into positions of the smallest tail of each run length
  const prev = new Array<number>(positions.length).fill(-1);
  for (let i = 0; i < positions.length; i++) {
    const p = positions[i]!;
    if (p < 0) continue;
    let lo = 0;
    let hi = tails.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (positions[tails[mid]!]! < p) lo = mid + 1;
      else hi = mid;
    }
    if (lo > 0) prev[i] = tails[lo - 1]!;
    tails[lo] = i;
  }
  const out = new Set<number>();
  for (let i = tails.length > 0 ? tails[tails.length - 1]! : -1; i >= 0; i = prev[i]!) out.add(i);
  return out;
}

/// Applies ops, keyed or not, to a value without changing it: only what is along each op's path is copied, so items
/// that did not change stay the same objects (as the UIs' appliers do). An op that does not fit is skipped.
export function applyKeyed(value: unknown, ops: AnyOp[]): unknown {
  return ops.reduce((v, op) => applyOne(v, op, 0), value);
}

function applyOne(node: unknown, op: AnyOp, depth: number): unknown {
  if (depth === op.path.length) {
    if ("key" in op) return Array.isArray(node) ? applyList(node, op) : node;
    if ("set" in op) return op.set;
    if ("append" in op) return Array.isArray(node) ? [...node, ...op.append] : node;
    return node;
  }
  const key = op.path[depth];
  if (Array.isArray(node)) {
    if (typeof key !== "number" || key >= node.length) return node;
    const copy = node.slice();
    copy[key] = applyOne(node[key], op, depth + 1);
    return copy;
  }
  if (!isObject(node) || typeof key !== "string") return node;
  if ("remove" in op && depth === op.path.length - 1) {
    const rest = { ...node };
    delete rest[key];
    return rest;
  }
  if (!(key in node) && !("set" in op && depth === op.path.length - 1)) return node;
  return { ...node, [key]: applyOne(node[key], op, depth + 1) };
}

function applyList(list: unknown[], op: KeyedOp): unknown[] {
  const find = (k: Key) => {
    const want = text(k);
    return list.findIndex((item) => text(keyOf(item, op.key)) === want);
  };
  const out = list.slice();
  const place = (item: unknown, before: Key | null) => {
    const at = before === null ? -1 : out.findIndex((x) => text(keyOf(x, op.key)) === text(before));
    if (at < 0) out.push(item);
    else out.splice(at, 0, item);
  };
  if ("drop" in op) {
    const i = find(op.drop);
    if (i >= 0) out.splice(i, 1);
  } else if ("patch" in op) {
    const i = find(op.patch);
    if (i >= 0) out[i] = applyKeyed(out[i], op.ops);
  } else if ("move" in op) {
    const i = find(op.move);
    if (i < 0) return list;
    const [item] = out.splice(i, 1);
    place(item, op.before);
  } else {
    const i = find(keyOf(op.put, op.key));
    if (i >= 0 && op.before === undefined) out[i] = op.put;
    else {
      if (i >= 0) out.splice(i, 1);
      place(op.put, op.before ?? null);
    }
  }
  return out;
}
