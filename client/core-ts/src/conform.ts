// A value put through its shape (src/shapes/schema.ts): what the shape does not declare is dropped,
// an absent option left out, a default filled in where the shape says so, and a value of the wrong type is an error
// naming the field ("items[0].since: invalid type: …"), as serde_path_to_error says it.
import { SHAPES } from "./shapes/schema.ts";
import type { Ty } from "./shapes/dsl.ts";
import { shaped, shapedAs } from "./util.ts";
import { walked } from "./work.ts";

export type { Field, Shape, Ty } from "./shapes/dsl.ts";

class Wrong extends Error {
  readonly path: string;
  readonly inner: string;
  constructor(path: string, inner: string) {
    super(inner);
    this.path = path;
    this.inner = inner;
  }
}

const INTS: Record<string, [number, number]> = {
  i64: [-(2 ** 63), 2 ** 63],
  i32: [-(2 ** 31), 2 ** 31 - 1],
  u64: [0, 2 ** 64],
  u32: [0, 2 ** 32 - 1],
  u16: [0, 65535],
  u8: [0, 255],
  usize: [0, 2 ** 64],
};

/// serde's words for what a value is ("invalid type: string \"a\", expected …").
function unexpected(v: unknown): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "boolean") return `boolean \`${v}\``;
  if (typeof v === "number") return Number.isInteger(v) ? `integer \`${v}\`` : `floating point \`${float(v)}\``;
  if (typeof v === "string") return `string ${JSON.stringify(v)}`;
  if (Array.isArray(v)) return "sequence";
  return "map";
}

/// serde's `OneOf`: what an unknown variant was expected to be.
function oneOf(names: string[]): string {
  const q = names.map((x) => `\`${x}\``);
  if (q.length === 0) return "there are no variants";
  if (q.length === 1) return `expected ${q[0]}`;
  if (q.length === 2) return `expected ${q[0]} or ${q[1]}`;
  return `expected one of ${q.join(", ")}`;
}

function float(v: number): string {
  return Number.isInteger(v) ? `${v}.0` : String(v);
}

function expecting(ty: Ty): string {
  if (typeof ty === "string") {
    if (ty === "String") return "a string";
    if (ty === "bool") return "a boolean";
    if (ty in INTS) return ty;
    if (ty === "f64" || ty === "f32") return ty;
    const shape = SHAPES[ty];
    if (shape?.kind === "struct") return `struct ${ty}`;
    if (shape?.kind === "enum") return `variant identifier`;
    return ty;
  }
  if ("opt" in ty) return expecting(ty.opt);
  if ("vec" in ty || "tuple" in ty) return "a sequence";
  return "a map";
}

function at(path: string, key: string | number): string {
  if (typeof key === "number") return `${path}[${key}]`;
  return path === "" ? key : `${path}.${key}`;
}

export function defaultOf(ty: Ty): unknown {
  if (typeof ty === "string") {
    if (ty === "String") return "";
    if (ty === "bool") return false;
    if (ty in INTS || ty === "f64" || ty === "f32") return 0;
    if (ty === "Value") return null;
    const shape = SHAPES[ty];
    if (shape?.kind === "struct") {
      const out: Record<string, unknown> = {};
      for (const f of shape.fields) {
        const d = defaultOf(f.ty);
        if (d === null && f.skipNone) continue;
        out[f.name] = d;
      }
      return out;
    }
    if (shape?.kind === "enum") return shape.default ?? shape.values[0];
    return null;
  }
  if ("opt" in ty) return null;
  if ("vec" in ty) return [];
  if ("tuple" in ty) return ty.tuple.map(defaultOf);
  return {};
}

/// Whether `v` already went out as `ty` (output.ts, views.ts `asShaped`), to go as it went: not one a view shaped as
/// another struct (`shapedAs`), which is shaped as this one.
function wentOut(v: unknown, ty: Ty): boolean {
  if (v === null || typeof v !== "object" || !shaped.has(v)) return false;
  const as = shapedAs.get(v);
  return as === undefined || as === ty;
}

/// What a value a view shaped as one struct was made as another, by that one (`fit`): made once while it is the same.
const reshaped = new WeakMap<object, Map<string, unknown>>();

/// What `v` goes out as through struct `ty`, made beside it once and kept with it (`shapedBeside`), else undefined.
export function keptShape(v: unknown, ty: Ty): unknown {
  return v !== null && typeof v === "object" && typeof ty === "string" ? beside.get(v)?.get(ty) : undefined;
}

/// `out`, what `v` goes out as through struct `ty`, made beside it (views.ts: a chat list's row, as it was kept beside
/// its record, db/kept.ts KEPT.listRow): taken as it is where `v` goes out as `ty` (output.ts), neither shaped nor
/// walked again, and marked as gone out. `v` itself is not marked: it goes out otherwise elsewhere (a search's ChatItem).
export function shapedBeside(v: object, ty: string, out: object): void {
  let by = beside.get(v);
  if (by === undefined) beside.set(v, (by = new Map()));
  by.set(ty, out);
  shaped.add(out);
  shapedAs.set(out, ty);
}
const beside = new WeakMap<object, Map<string, unknown>>();

function walk(v: unknown, ty: Ty, path: string): unknown {
  if (typeof ty === "object" && "opt" in ty) return v === null || v === undefined ? null : walk(v, ty.opt, path);
  // What already went out through its shape (output.ts) is as it went.
  if (wentOut(v, ty)) return v;
  if (typeof ty === "object") {
    if ("vec" in ty) {
      if (!Array.isArray(v)) throw new Wrong(path, `invalid type: ${unexpected(v)}, expected a sequence`);
      return v.map((item, i) => walk(item, ty.vec, at(path, i)));
    }
    if ("tuple" in ty) {
      if (!Array.isArray(v)) throw new Wrong(path, `invalid type: ${unexpected(v)}, expected a tuple of size ${ty.tuple.length}`);
      if (v.length !== ty.tuple.length) throw new Wrong(path, `invalid length ${v.length}, expected a tuple of size ${ty.tuple.length}`);
      return ty.tuple.map((t, i) => walk(v[i], t, at(path, i)));
    }
    if (v === null || typeof v !== "object" || Array.isArray(v)) throw new Wrong(path, `invalid type: ${unexpected(v)}, expected a map`);
    const out: Record<string, unknown> = {};
    for (const [k, item] of Object.entries(v)) out[k] = walk(item, ty.map, at(path, k));
    return out;
  }
  switch (ty) {
    case "Value":
      return v === undefined ? null : v;
    case "String":
      if (typeof v !== "string") throw new Wrong(path, `invalid type: ${unexpected(v)}, expected a string`);
      return v;
    case "bool":
      if (typeof v !== "boolean") throw new Wrong(path, `invalid type: ${unexpected(v)}, expected a boolean`);
      return v;
    case "f64":
    case "f32":
      if (typeof v !== "number") throw new Wrong(path, `invalid type: ${unexpected(v)}, expected ${ty}`);
      return v;
  }
  if (ty in INTS) {
    if (typeof v !== "number" || !Number.isInteger(v)) throw new Wrong(path, `invalid type: ${unexpected(v)}, expected ${ty}`);
    const [lo, hi] = INTS[ty];
    if (v < lo || v > hi) throw new Wrong(path, `invalid value: ${unexpected(v)}, expected ${ty}`);
    return v;
  }
  const shape = SHAPES[ty];
  if (!shape) throw new Error(`no shape ${ty}`);
  if (shape.kind === "enum") {
    if (typeof v !== "string") throw new Wrong(path, `invalid type: ${unexpected(v)}, expected variant identifier`);
    if (!shape.values.includes(v)) throw new Wrong(path, `unknown variant \`${v}\`, ${oneOf(shape.values)}`);
    return v;
  }
  if (v === null || typeof v !== "object" || Array.isArray(v)) throw new Wrong(path, `invalid type: ${unexpected(v)}, expected ${expecting(ty)}`);
  const obj = v as Record<string, unknown>;
  if (shape.kind === "tagged") {
    const tag = obj[shape.tag];
    if (tag === undefined) throw new Wrong(path, `missing field \`${shape.tag}\``);
    if (typeof tag !== "string" || !(tag in shape.variants)) throw new Wrong(path, `unknown variant \`${String(tag)}\`, ${oneOf(Object.keys(shape.variants))}`);
    if (!(shape.content in obj)) throw new Wrong(path, `missing field \`${shape.content}\``);
    return { [shape.tag]: tag, [shape.content]: walk(obj[shape.content], shape.variants[tag], at(path, shape.content)) };
  }
  const out: Record<string, unknown> = {};
  // serde reads the fields as the object has them (a wrong one is said before a missing one).
  const fields = new Map(shape.fields.map((f) => [f.name, f]));
  const read = new Map<string, unknown>();
  for (const key of Object.keys(obj).sort()) {
    const f = fields.get(key);
    if (!f) continue;
    read.set(key, walk(obj[key], f.ty, at(path, key)));
  }
  for (const f of shape.fields) {
    let value: unknown;
    if (read.has(f.name)) value = read.get(f.name);
    else if (f.default || shape.default) value = defaultOf(f.ty);
    else if (typeof f.ty === "object" && "opt" in f.ty) value = null;
    else throw new Wrong(path, `missing field \`${f.name}\``);
    if (value === null && f.skipNone) continue;
    out[f.name] = value;
  }
  return out;
}

/// What a value is put through as shape `ty` is, as a key (its length and two FNV-1a hashes): of every shape it
/// reaches, as declared (src/shapes/schema.ts) of what conform reads (not their words for people or the clients'
/// types), so another whenever one of them is declared otherwise. What a verdict on whether a value fits is kept by
/// (views.ts OVERVIEW_FIT).
export function shapeKey(ty: Ty): string {
  const reached = new Map<string, unknown>();
  const reach = (t: Ty): void => {
    if (typeof t !== "string") {
      if ("opt" in t) reach(t.opt);
      else if ("vec" in t) reach(t.vec);
      else if ("map" in t) reach(t.map);
      else for (const x of t.tuple) reach(x);
      return;
    }
    const shape = SHAPES[t];
    if (shape === undefined || reached.has(t)) return;
    if (shape.kind === "struct") {
      reached.set(t, [shape.default, shape.fields.map((f) => [f.name, f.ty, f.default, f.skipNone])]);
      for (const f of shape.fields) reach(f.ty);
    } else if (shape.kind === "enum") reached.set(t, [shape.values, shape.default]);
    else {
      reached.set(t, [shape.tag, shape.content, shape.variants]);
      for (const v of Object.values(shape.variants)) reach(v);
    }
  };
  reach(ty);
  return textKey(JSON.stringify([ty, [...reached]]));
}

/// A text as a short key: its length and two FNV-1a hashes of it.
export function textKey(text: string): string {
  let a = 0x811c9dc5;
  let b = 0x01000193 ^ text.length;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    a = Math.imul(a ^ c, 0x01000193);
    b = Math.imul(b ^ c, 0x0100019d);
  }
  return `${text.length}.${(a >>> 0).toString(36)}.${(b >>> 0).toString(36)}`;
}

/// The value through the shape `ty`, or why not (`path: what`).
export function conform(ty: Ty, value: unknown): { ok: unknown } | { error: string } {
  return conformTy(ty, value);
}

/// `conform` of a value found at `at` (its errors say where in the whole it is). Most values fit: they go through
/// `fit`, which keeps no path and sorts no keys; only one that does not is walked again to say where and why.
export function conformTy(ty: Ty, value: unknown, at = ""): { ok: unknown } | { error: string } {
  try {
    return { ok: fit(value, ty) };
  } catch (e) {
    if (e !== MISFIT) throw e;
  }
  try {
    return { ok: walk(value, ty, at) };
  } catch (e) {
    if (e instanceof Wrong) return { error: `${e.path === "" ? "." : e.path}: ${e.inner}` };
    throw e;
  }
}

const MISFIT = Symbol("misfit");
const has = Object.prototype.hasOwnProperty;

/// `walk` for a value that fits, making the same value: every topic's every change goes through it whole, and walking
/// it (a path written for every field, every object's keys sorted) was much of what the core did on a phone
/// (2026-10-19). Anything that does not fit is MISFIT, for `walk` to say.
function fit(v: unknown, ty: Ty): unknown {
  walked.fitted++;
  if (typeof ty === "object" && "opt" in ty) return v === null || v === undefined ? null : fit(v, ty.opt);
  if (wentOut(v, ty)) return v;
  if (typeof ty === "object") {
    if ("vec" in ty) {
      if (!Array.isArray(v)) throw MISFIT;
      const out = new Array(v.length);
      for (let i = 0; i < v.length; i++) out[i] = fit(v[i], ty.vec);
      return out;
    }
    if ("tuple" in ty) {
      if (!Array.isArray(v) || v.length !== ty.tuple.length) throw MISFIT;
      return ty.tuple.map((t, i) => fit(v[i], t));
    }
    if (v === null || typeof v !== "object" || Array.isArray(v)) throw MISFIT;
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(v)) out[k] = fit((v as Record<string, unknown>)[k], ty.map);
    return out;
  }
  switch (ty) {
    case "Value":
      return v === undefined ? null : v;
    case "String":
      if (typeof v !== "string") throw MISFIT;
      return v;
    case "bool":
      if (typeof v !== "boolean") throw MISFIT;
      return v;
    case "f64":
    case "f32":
      if (typeof v !== "number") throw MISFIT;
      return v;
  }
  const ints = INTS[ty];
  if (ints) {
    if (typeof v !== "number" || !Number.isInteger(v) || v < ints[0] || v > ints[1]) throw MISFIT;
    return v;
  }
  const shape = SHAPES[ty];
  if (!shape) throw new Error(`no shape ${ty}`);
  if (shape.kind === "enum") {
    if (typeof v !== "string" || !shape.values.includes(v)) throw MISFIT;
    return v;
  }
  if (v === null || typeof v !== "object" || Array.isArray(v)) throw MISFIT;
  const obj = v as Record<string, unknown>;
  if (shape.kind === "tagged") {
    const tag = obj[shape.tag];
    if (typeof tag !== "string" || !has.call(shape.variants, tag) || !(shape.content in obj)) throw MISFIT;
    return { [shape.tag]: tag, [shape.content]: fit(obj[shape.content], shape.variants[tag]) };
  }
  // (one with what it goes out as made beside it: as it was made)
  const made = beside.get(obj)?.get(ty);
  if (made !== undefined) return made;
  // (one a view shaped as another struct: as this one once, kept as it went out)
  const other = shaped.has(obj);
  if (other) {
    const kept = reshaped.get(obj)?.get(ty);
    if (kept !== undefined) return kept;
  }
  const out: Record<string, unknown> = {};
  for (const f of shape.fields) {
    let value: unknown;
    if (has.call(obj, f.name)) value = fit(obj[f.name], f.ty);
    else if (f.default || shape.default) value = defaultOf(f.ty);
    else if (typeof f.ty === "object" && "opt" in f.ty) value = null;
    else throw MISFIT;
    if (value === null && f.skipNone) continue;
    out[f.name] = value;
  }
  if (other) {
    let by = reshaped.get(obj);
    if (by === undefined) reshaped.set(obj, (by = new Map()));
    by.set(ty, out);
    shaped.add(out);
    shapedAs.set(out, ty);
  }
  return out;
}
