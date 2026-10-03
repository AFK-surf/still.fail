// The shapes the core's values go out through (client/shapes, `conform`), read from its Rust source into a table the TS
// core's conform.ts walks: each struct's fields as they go on the wire (renamed, defaulted, left out when none), each
// enum's words. `node scripts/shapes-schema.ts` writes src/shapes-schema.ts; `--check` fails when it is not what the
// shapes make.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export type Ty = string | { opt: Ty } | { vec: Ty } | { map: Ty } | { tuple: Ty[] };
export type Field = { name: string; ty: Ty; default: boolean; skipNone: boolean };
export type Shape =
  | { kind: "struct"; fields: Field[]; default: boolean }
  | { kind: "enum"; values: string[]; default: string | null }
  | { kind: "tagged"; tag: string; content: string; variants: Record<string, Ty> };

const root = fileURLToPath(new URL("../../shapes/src/", import.meta.url));
const sources = ["lib.rs", "providers.rs"].map((f) => readFileSync(root + f, "utf8"));

function camel(name: string): string {
  return name.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}
function renamed(name: string, rule: string | null): string {
  switch (rule) {
    case "camelCase":
      return camel(name);
    case "lowercase":
      return name.toLowerCase();
    case "kebab-case":
      return name.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
    case "snake_case":
      return name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();
    default:
      return name;
  }
}

function parseTy(text: string): Ty {
  text = text.trim().replace(/^&'static /, "");
  if (text.startsWith("[") && text.endsWith("]")) return { vec: parseTy(text.slice(1, -1)) };
  if (text.startsWith("(")) return { tuple: split(text.slice(1, -1)).map(parseTy) };
  const m = /^([A-Za-z0-9_:]+)\s*<(.*)>$/s.exec(text);
  if (!m) return text.replace(/^.*::/, "");
  const [, head, inner] = m;
  const args = split(inner);
  const name = head.replace(/^.*::/, "");
  if (name === "Option") return { opt: parseTy(args[0]) };
  if (name === "Vec") return { vec: parseTy(args[0]) };
  if (name === "HashMap" || name === "BTreeMap") return { map: parseTy(args[1]) };
  if (name === "Box") return parseTy(args[0]);
  throw new Error(`unknown type ${text}`);
}

/// Splits on top-level commas.
function split(text: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === "<" || c === "(" || c === "[") depth++;
    else if (c === ">" || c === ")" || c === "]") depth--;
    else if (c === "," && depth === 0) {
      out.push(text.slice(start, i));
      start = i + 1;
    }
  }
  if (text.slice(start).trim()) out.push(text.slice(start));
  return out.map((s) => s.trim()).filter(Boolean);
}

/// The text between the brace at `open` and its match.
function block(text: string, open: number): string {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth === 0) return text.slice(open + 1, i);
  }
  throw new Error("unbalanced");
}

function stripComments(text: string): string {
  return text.replace(/\/\/[^\n]*/g, "");
}

const shapes: Record<string, Shape> = {};
for (const source of sources) {
  const text = stripComments(source);
  const re = /((?:#\[[^\]]*(?:\[[^\]]*\][^\]]*)*\]\s*)*)pub (struct|enum) (\w+)\s*\{/g;
  for (let m; (m = re.exec(text)); ) {
    const [whole, attrs, kind, name] = m;
    if (!/derive\([^)]*Serialize/.test(attrs)) continue;
    const body = block(text, m.index + whole.length - 1);
    const serde = [...attrs.matchAll(/#\[serde\(([^)]*)\)\]/g)].map((a) => a[1]).join(", ");
    const rule = /rename_all = "([^"]+)"/.exec(serde)?.[1] ?? null;
    if (kind === "struct") {
      const skipNone = /skip_serializing_none/.test(attrs);
      const fields: Field[] = [];
      const fre = /((?:#\[[^\]]*\]\s*)*)pub (\w+)\s*:\s*/g;
      const parts: { attrs: string; name: string; start: number; tyStart: number }[] = [];
      for (let f; (f = fre.exec(body)); ) parts.push({ attrs: f[1], name: f[2], start: f.index, tyStart: f.index + f[0].length });
      for (let i = 0; i < parts.length; i++) {
        const end = i + 1 < parts.length ? parts[i + 1].start : body.length;
        let tyText = body.slice(parts[i].tyStart, end).trim();
        tyText = tyText.replace(/,\s*$/, "");
        const fserde = [...parts[i].attrs.matchAll(/#\[serde\(([^)]*)\)\]/g)].map((a) => a[1]).join(", ");
        const ty = parseTy(tyText);
        const wire = /rename = "([^"]+)"/.exec(fserde)?.[1] ?? renamed(parts[i].name, rule);
        const isOpt = typeof ty === "object" && "opt" in ty;
        fields.push({
          name: wire,
          ty,
          default: /\bdefault\b/.test(fserde),
          skipNone: isOpt && (skipNone || /skip_serializing_if = "Option::is_none"/.test(fserde)),
        });
      }
      shapes[name] = { kind: "struct", fields, default: /(^|[ ,])default($|[ ,])/.test(serde) };
    } else {
      const variants = split(body.replace(/#\[default\]\s*/g, "#DEFAULT "));
      const tag = /tag = "([^"]+)"/.exec(serde)?.[1];
      if (tag) {
        const content = /content = "([^"]+)"/.exec(serde)![1];
        const out: Record<string, Ty> = {};
        for (const v of variants) {
          const vm = /^(\w+)\((.*)\)$/s.exec(v.replace("#DEFAULT ", ""));
          if (!vm) throw new Error(`variant ${v}`);
          out[renamed(vm[1], rule)] = parseTy(vm[2]);
        }
        shapes[name] = { kind: "tagged", tag, content, variants: out };
      } else {
        let def: string | null = null;
        const values = variants.map((v) => {
          const isDefault = v.startsWith("#DEFAULT ");
          const clean = v.replace("#DEFAULT ", "").replace(/#\[[^\]]*\]\s*/g, "").trim();
          const wire = renamed(clean, rule);
          if (isDefault) def = wire;
          return wire;
        });
        shapes[name] = { kind: "enum", values, default: def };
      }
    }
  }
}

const out = `// Generated by scripts/shapes-schema.ts from client/shapes (do not edit): the shapes values go out through.
import type { Shape } from "./conform.ts";

export const SHAPES: Record<string, Shape> = ${JSON.stringify(shapes, null, 1)};
`;
const target = fileURLToPath(new URL("../src/shapes-schema.ts", import.meta.url));
if (process.argv.includes("--check")) {
  if (readFileSync(target, "utf8") !== out) {
    console.error("src/shapes-schema.ts is not what client/shapes makes: run node scripts/shapes-schema.ts");
    process.exit(1);
  }
} else {
  writeFileSync(target, out);
  console.log(`${Object.keys(shapes).length} shapes`);
}
