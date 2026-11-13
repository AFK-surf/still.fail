// Writes src/cm/tokens_made.mbt, Comma's design tokens for mbui, from the place they are said: AFK-surf/Cue's
// clients/packages/ui/src/tokens (TypeScript, the same modules Comma's theme.css is generated from).
//
//   node scripts/cm-tokens.mjs <Cue checkout>
//
// (CM_TOKENS_FROM: the Cue commit to name, where the checkout is no git one: an archive of it)
//
// In Node, not MoonBit (mbui's AGENTS.md, Tools): what it reads is TypeScript modules that only run in Node; a hook
// below resolves their extensionless imports and their JSON. Run it again when Comma's tokens change; the file it
// writes says which Cue commit it came from.
import { execFileSync } from "node:child_process";
import { existsSync, writeFileSync } from "node:fs";
import { register } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

register(
  "data:text/javascript," +
    encodeURIComponent(`
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
export async function resolve(s, c, next) {
  if ((s.startsWith("./") || s.startsWith("../")) && !/\\.[cm]?[jt]s(on)?$/.test(s)) {
    for (const ext of [".ts", "/index.ts"]) {
      const u = new URL(s + ext, c.parentURL);
      if (existsSync(fileURLToPath(u))) return next(u.href, c);
    }
  }
  return next(s, c);
}
export async function load(u, c, next) {
  return next(u, u.endsWith(".json") ? { ...c, importAttributes: { type: "json" } } : c);
}`),
);

const cue = process.argv[2];
if (!cue) {
  console.error("usage: node scripts/cm-tokens.mjs <Cue checkout>");
  process.exit(2);
}
const dir = resolve(cue, "clients/packages/ui/src/tokens");
if (!existsSync(dir)) {
  console.error(`cm-tokens: no tokens at ${dir}`);
  process.exit(2);
}
const at = (f) => import(pathToFileURL(resolve(dir, f)).href);
const colors = await at("colors/index.ts");
const type = await at("typography.ts");
const space = await at("spacing.ts");
const round = await at("radius.ts");
const effects = await at("effects.ts");
const motion = await at("motion.ts");
let commit = process.env.CM_TOKENS_FROM ?? "unknown";
if (!process.env.CM_TOKENS_FROM) try {
  commit = execFileSync("git", ["-C", cue, "rev-parse", "--short=10", "HEAD"], { encoding: "utf8" }).trim();
} catch {}

const snake = (k) =>
  k
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/[^A-Za-z0-9]+/g, "_")
    .toLowerCase();
// (a field's name: one that starts with a digit gets the group's name before it)
const ident = (parts) => parts.map(snake).join("_").replace(/__+/g, "_");

/** #rrggbb or #rrggbbaa as mbui's 0xRRGGBBAA. */
const rgba = (hex) => {
  const m = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(hex);
  if (!m) throw new Error(`cm-tokens: not a colour: ${hex}`);
  return `0x${(m[1] + (m[2] ?? "ff")).toUpperCase()}L`;
};
const css_rgba = (s) => {
  const m = /rgba\(\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\s*\)/.exec(s);
  if (!m) throw new Error(`cm-tokens: not an rgba(): ${s}`);
  const h = (n) => Number(n).toString(16).padStart(2, "0");
  return `0x${(h(m[1]) + h(m[2]) + h(m[3]) + h(Math.round(Number(m[4]) * 255))).toUpperCase()}L`;
};

/** The colours of one appearance, flattened: semantic's groups by their short names, the components' by theirs. */
const flat = (semantic, components) => {
  const out = new Map();
  const walk = (o, path) => {
    for (const [k, v] of Object.entries(o)) {
      if (typeof v === "string") out.set(ident([...path, k]), rgba(v));
      else if (v && typeof v === "object") walk(v, [...path, k]);
    }
  };
  const short = { text: "text", border: "border", foreground: "fg", background: "bg" };
  for (const [g, o] of Object.entries(semantic)) walk(o, [short[g] ?? g]);
  walk(components, []);
  return out;
};
const light = flat(colors.semantic, colors.components);
const dark = flat(colors.semanticDark, colors.componentsDark);
const keys = [...light.keys()].filter((k) => dark.has(k));
const only = [...light.keys(), ...dark.keys()].filter((k) => !(light.has(k) && dark.has(k)));
if (only.length > 0) {
  // (one appearance alone says it: no field, as Comma's own CSS falls back to the other's there)
  console.error(`cm-tokens: said in one appearance only, left out: ${[...new Set(only)].join(", ")}`);
}

/** CSS shadow layers ("0 1px 2px 0 rgba(...)", ...): the largest one, as mbui casts one (blur's sigma, dy, ink). */
const cast = (s) => {
  const layers = s.split(/,(?![^(]*\))/).map((l) => l.trim());
  let best = null;
  for (const l of layers) {
    const m = /^(-?[\d.]+)(?:px)?\s+(-?[\d.]+)(?:px)?\s+(-?[\d.]+)(?:px)?\s+(-?[\d.]+)(?:px)?\s+(rgba\(.*\))$/.exec(l);
    if (!m) throw new Error(`cm-tokens: not a shadow: ${l}`);
    const blur = Number(m[3]);
    if (!best || blur > best.blur) best = { blur, dy: Number(m[2]), ink: css_rgba(m[5]) };
  }
  return `(${(best.blur / 2).toFixed(1)}, ${best.dy.toFixed(1)}, ${best.ink})`;
};
/** A focus ring ("0 0 0 4px rgba(...)"[, a shadow]): its width and ink. */
const ring = (s) => {
  const m = /^0 0 0 ([\d.]+)px (rgba\([^)]*\))/.exec(s);
  if (!m) throw new Error(`cm-tokens: not a ring: ${s}`);
  return `(${Number(m[1]).toFixed(1)}, ${css_rgba(m[2])})`;
};
/** A CSS easing as a cubic Bézier's (x1, y1, x2, y2). */
const bezier = (s) => {
  const named = { ease: [0.25, 0.1, 0.25, 1], "ease-in": [0.42, 0, 1, 1], "ease-out": [0, 0, 0.58, 1], "ease-in-out": [0.42, 0, 0.58, 1], linear: [0, 0, 1, 1] };
  const m = /^cubic-bezier\(([^)]*)\)$/.exec(s);
  const v = m ? m[1].split(",").map(Number) : named[s];
  if (!v || v.length !== 4 || v.some(Number.isNaN)) throw new Error(`cm-tokens: not an easing: ${s}`);
  return `(${v.map((x) => x.toFixed(3)).join(", ")})`;
};
const num = (n) => (Number.isInteger(n) ? `${n}.0` : `${n}`);
const ems = (s) => {
  const m = /^(-?[\d.]+)em$/.exec(s);
  if (!m) throw new Error(`cm-tokens: not ems: ${s}`);
  return num(Number(m[1]));
};

const lines = [];
const say = (s = "") => lines.push(s);
say(`// Made by scripts/cm-tokens.mjs from Comma's design tokens (AFK-surf/Cue ${commit},`);
say("// clients/packages/ui/src/tokens): do not edit, run it again when they change. What each is: tokens.mbt.");
say();
say("///|");
say("/// Comma's colours in one appearance (semantic's text_, border_, fg_, bg_; the components' by their names), each");
say("/// 0xRRGGBBAA: `light` and `dark`.");
say("pub(all) struct Colors {");
for (const k of keys) say(`  ${k} : Int64`);
say("}");
for (const [name, m] of [["light", light], ["dark", dark]]) {
  say();
  say("///|");
  say(`/// Comma's colours, ${name}.`);
  say(`pub let ${name} : Colors = {`);
  for (const k of keys) say(`  ${k}: ${m.get(k)},`);
  say("}");
}
say();
say("///|");
say("/// A role of type: its size and line in points, and how far apart its letters are set (ems).");
say("pub(all) struct TypeRole {");
say("  size : Double");
say("  line : Double");
say("  tracking : Double");
say("}");
for (const [k, v] of Object.entries(type.compactTypeScale)) {
  say();
  say("///|");
  say(`pub let type_${snake(k)} : TypeRole = { size: ${num(v.fontSize)}, line: ${num(v.lineHeight)}, tracking: ${ems(v.letterSpacing)} }`);
}
for (const [k, v] of Object.entries(type.fontWeight)) {
  say();
  say("///|");
  say(`pub let weight_${snake(k)} : Int = ${v}`);
}
for (const [k, v] of Object.entries(space.spacing)) {
  say();
  say("///|");
  say(`pub let space_${snake(k)} : Double = ${num(v)}`);
}
for (const [k, v] of Object.entries(round.radius)) {
  say();
  say("///|");
  say(`pub let radius_${snake(k)} : Double = ${num(v)}`);
}
for (const [name, set] of [["shadow", effects.shadow], ["shadow_dark", effects.shadowDark]]) {
  for (const [k, v] of Object.entries(set)) {
    say();
    say("///|");
    say(`pub let ${name}_${snake(k)} : (Double, Double, Int64) = ${cast(v)}`);
  }
}
for (const k of ["brand", "gray", "error"]) {
  say();
  say("///|");
  say(`pub let focus_${k} : (Double, Int64) = ${ring(effects.focusRing[k])}`);
}
for (const [k, v] of Object.entries(motion.motionDuration)) {
  if (typeof v !== "number") continue;
  say();
  say("///|");
  say(`pub let ms_${snake(k)} : Double = ${num(v)}`);
}
for (const [k, v] of Object.entries(motion.motionEasing)) {
  say();
  say("///|");
  say(`pub let ease_${snake(k)} : (Double, Double, Double, Double) = ${bezier(v)}`);
}

const out = resolve(dirname(fileURLToPath(import.meta.url)), "../src/cm/tokens_made.mbt");
writeFileSync(out, lines.join("\n") + "\n");
console.log(`cm-tokens: ${keys.length} colours, from ${commit}, to ${out}`);
