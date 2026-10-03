// stillfail_shapes::conform: a value put through its shape (client/shapes): what the shape does not declare is dropped,
// an absent option left out, a default filled in where the shape says so, and a value of the wrong type is an error
// naming the field ("items[0].since: invalid type: …"), as serde_path_to_error says it.
import { SHAPES } from "./shapes-schema.ts";

export type Ty = string | { opt: Ty } | { vec: Ty } | { map: Ty } | { tuple: Ty[] };
export type Field = { name: string; ty: Ty; default: boolean; skipNone: boolean };
export type Shape =
  | { kind: "struct"; fields: Field[]; default: boolean }
  | { kind: "enum"; values: string[]; default: string | null }
  | { kind: "tagged"; tag: string; content: string; variants: Record<string, Ty> };

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

function walk(v: unknown, ty: Ty, path: string): unknown {
  if (typeof ty === "object") {
    if ("opt" in ty) return v === null || v === undefined ? null : walk(v, ty.opt, path);
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

/// The value through the shape `ty`, or why not (`path: what`).
export function conform(ty: Ty, value: unknown): { ok: unknown } | { error: string } {
  try {
    return { ok: walk(value, ty, "") };
  } catch (e) {
    if (e instanceof Wrong) return { error: `${e.path === "" ? "." : e.path}: ${e.inner}` };
    throw e;
  }
}
