// Reading a call's params as serde reads them into the Rust core's structs: the same errors, in the same words
// ("missing field `return_to`", "invalid type: string \"x\", expected u64"), so a UI sees what it saw before.
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { isObject } from "../util.ts";

export type Kind = "string" | "u64" | "u32" | "u16" | "bool" | "f64" | "value" | "pairs" | "values" | "close" | "strings";
/// `req`: must be there; `default`: its default when absent; `opt`: an Option (null when absent or null).
export type Mode = "req" | "default" | "opt";
export type Spec = [string, Kind, Mode][];

function what(v: unknown): string {
  if (v === null) return "null";
  if (typeof v === "boolean") return `boolean \`${v}\``;
  if (typeof v === "number") return Number.isInteger(v) ? `integer \`${v}\`` : `floating point \`${v}\``;
  if (typeof v === "string") return `string ${JSON.stringify(v)}`;
  if (Array.isArray(v)) return "sequence";
  return "map";
}

const EXPECT: Record<Kind, string> = {
  string: "a string",
  u64: "u64",
  u32: "u32",
  u16: "u16",
  bool: "a boolean",
  f64: "f64",
  value: "any valid JSON value",
  pairs: "a sequence",
  values: "a sequence",
  close: "a tuple of size 2",
  strings: "a sequence",
};

class Bad extends Error {}

function check(v: unknown, kind: Kind): unknown {
  const wrong = () => new Bad(`invalid type: ${what(v)}, expected ${EXPECT[kind]}`);
  switch (kind) {
    case "value":
      return v;
    case "string":
      if (typeof v !== "string") throw wrong();
      return v;
    case "bool":
      if (typeof v !== "boolean") throw wrong();
      return v;
    case "f64":
      if (typeof v !== "number") throw wrong();
      return v;
    case "u64":
    case "u32":
    case "u16": {
      if (typeof v !== "number" || !Number.isInteger(v)) throw wrong();
      const max = kind === "u16" ? 65535 : kind === "u32" ? 2 ** 32 - 1 : 2 ** 64;
      if (v < 0 || v > max) throw new Bad(`invalid value: integer \`${v}\`, expected ${kind}`);
      return v;
    }
    case "values":
      if (!Array.isArray(v)) throw wrong();
      return v;
    case "strings":
      if (!Array.isArray(v)) throw wrong();
      return v.map((s) => check(s, "string"));
    case "pairs":
      if (!Array.isArray(v)) throw wrong();
      return v.map((pair) => {
        if (!Array.isArray(pair)) throw new Bad(`invalid type: ${what(pair)}, expected a tuple of size 2`);
        if (pair.length !== 2) throw new Bad(`invalid length ${pair.length}, expected a tuple of size 2`);
        return [check(pair[0], "string"), check(pair[1], "string")];
      });
    case "close": {
      if (!Array.isArray(v)) throw wrong();
      if (v.length !== 2) throw new Bad(`invalid length ${v.length}, expected a tuple of size 2`);
      return [check(v[0], "u16"), check(v[1], "string")];
    }
  }
}

function defaultOf(kind: Kind): unknown {
  switch (kind) {
    case "string":
      return "";
    case "bool":
      return false;
    case "u64":
    case "u32":
    case "u16":
    case "f64":
      return 0;
    case "pairs":
    case "values":
    case "strings":
      return [];
    default:
      return null;
  }
}

/// The params as `spec` reads them; missing params read as `{}`, so the error names the missing field.
export function read(params: unknown, spec: Spec, struct = "struct"): Record<string, unknown> {
  const p = params === null || params === undefined ? {} : params;
  try {
    if (!isObject(p)) throw new Bad(`invalid type: ${what(p)}, expected ${struct}`);
    const out: Record<string, unknown> = {};
    const fields = new Map(spec.map((s) => [s[0], s]));
    for (const key of Object.keys(p).sort()) {
      const s = fields.get(key);
      if (!s) continue;
      const [, kind, mode] = s;
      const v = p[key];
      out[key] = mode === "opt" && v === null ? null : check(v, kind);
    }
    for (const [name, kind, mode] of spec) {
      if (name in out) continue;
      if (mode === "req") {
        // serde reads a missing Value as null.
        if (kind === "value") throw new Bad(`missing field \`${name}\``);
        throw new Bad(`missing field \`${name}\``);
      }
      out[name] = mode === "opt" ? null : defaultOf(kind);
    }
    return out;
  } catch (e) {
    if (e instanceof Bad) throw CoreError.invalid(t("core-misc.params.invalid", { error: e.message }));
    throw e;
  }
}

/// Missing params read as `{}`.
export function orEmpty(params: unknown): unknown {
  return params === null || params === undefined ? {} : params;
}
