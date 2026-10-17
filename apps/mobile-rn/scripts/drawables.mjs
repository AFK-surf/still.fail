// The Android app's drawings (its res/drawable vectors: illustrations, buddies, makers' marks, still.fail's mark) as
// SVG for react-native-svg, by the same names (R.drawable.illus_sign_in → Drawables.illus_sign_in), written to
// src/ui/Drawables.ts. Vector drawables are paths in groups with translate and scale: an SVG says that directly.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const app = join(dirname(fileURLToPath(import.meta.url)), "..");
const dirs = ["../android/shared/src/main/res/drawable", "../android/app/src/main/res/drawable"].map((d) => join(app, d));
const attr = (tag, name) => tag.match(new RegExp(`android:${name}="([^"]*)"`))?.[1];
const num = (v) => (v === undefined ? undefined : parseFloat(v));
const color = (v) => {
  if (!v) return undefined;
  if (v.length === 9) return { c: `#${v.slice(3)}`, a: parseInt(v.slice(1, 3), 16) / 255 };
  return { c: v, a: 1 };
};

function svgOf(xml) {
  const vector = xml.match(/<vector[^>]*>/)?.[0];
  if (!vector) return null;
  const [w, h, vw, vh] = ["width", "height", "viewportWidth", "viewportHeight"].map((k) => num(attr(vector, k)));
  let out = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${vw} ${vh}">`;
  for (const m of xml.matchAll(/<(group|path)\b([^>]*?)(\/?)>|<\/group>/g)) {
    if (m[0] === "</group>") { out += "</g>"; continue; }
    const tag = m[2];
    if (m[1] === "group") {
      const t = [];
      const tx = num(attr(tag, "translateX")) ?? 0, ty = num(attr(tag, "translateY")) ?? 0;
      if (tx || ty) t.push(`translate(${tx} ${ty})`);
      const sx = num(attr(tag, "scaleX")), sy = num(attr(tag, "scaleY"));
      if (sx !== undefined || sy !== undefined) t.push(`scale(${sx ?? 1} ${sy ?? sx ?? 1})`);
      out += `<g${t.length ? ` transform="${t.join(" ")}"` : ""}>`;
      if (m[3] === "/") out += "</g>";
      continue;
    }
    const fill = color(attr(tag, "fillColor"));
    const stroke = color(attr(tag, "strokeColor"));
    const a = [`d="${attr(tag, "pathData")}"`, `fill="${fill ? fill.c : "none"}"`];
    if (fill && fill.a < 1) a.push(`fill-opacity="${fill.a.toFixed(3)}"`);
    if (attr(tag, "fillType") === "evenOdd") a.push(`fill-rule="evenodd"`);
    if (stroke) {
      a.push(`stroke="${stroke.c}"`, `stroke-width="${attr(tag, "strokeWidth") ?? 1}"`);
      const sa = (num(attr(tag, "strokeAlpha")) ?? 1) * stroke.a;
      if (sa < 1) a.push(`stroke-opacity="${sa.toFixed(3)}"`);
      const cap = attr(tag, "strokeLineCap"), join = attr(tag, "strokeLineJoin");
      if (cap) a.push(`stroke-linecap="${cap}"`);
      if (join) a.push(`stroke-linejoin="${join}"`);
    }
    out += `<path ${a.join(" ")}/>`;
  }
  return { svg: out + "</svg>", width: w, height: h };
}

const entries = [];
for (const dir of dirs) {
  for (const f of readdirSync(dir).filter((f) => f.endsWith(".xml")).sort()) {
    const got = svgOf(readFileSync(join(dir, f), "utf8"));
    if (got) entries.push(`  ${f.replace(/\.xml$/, "")}: { width: ${got.width}, height: ${got.height}, svg: ${JSON.stringify(got.svg)} },`);
  }
}
writeFileSync(join(app, "src/ui/Drawables.ts"), `// Made by scripts/drawables.mjs from the Android app's res/drawable: do not edit.
export interface Drawing { width: number; height: number; svg: string }

export const Drawables = {
${entries.join("\n")}
} satisfies Record<string, Drawing>;

export type DrawableName = keyof typeof Drawables;
`);
console.log(`${entries.length} drawings`);
