// Writes src/cm/icons_made.mbt, the Central Icons Comma's parts draw (the same packages and glyphs as AFK-surf/Cue's
// clients/packages/ui/src/components/icons), from a Cue checkout with its packages installed:
//
//   node scripts/cm-icons.mjs <Cue checkout>
//
// In Node, not MoonBit (mbui's AGENTS.md, Tools): the icons are React components in Central's own npm packages (a
// licence of Comma's), drawn here once by react-dom/server into their SVG. Each icon's paths are read out of its mask
// (Central draws an icon as currentColor through a mask): what the mask lets through (white) is the icon, what it holds
// back (black) a cut. Run it again when the icons Comma uses change; the file it writes says which commit it came from.
import { execFileSync } from "node:child_process";
import { existsSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const cue = process.argv[2];
if (!cue) {
  console.error("usage: node scripts/cm-icons.mjs <Cue checkout>");
  process.exit(2);
}
const ui = resolve(cue, "clients/packages/ui/package.json");
if (!existsSync(ui)) {
  console.error(`cm-icons: no ${ui}`);
  process.exit(2);
}
const require = createRequire(ui);
const React = require("react");
const { renderToStaticMarkup } = require("react-dom/server");
let commit = process.env.CM_TOKENS_FROM ?? "unknown";
if (!process.env.CM_TOKENS_FROM) {
  try {
    commit = execFileSync("git", ["-C", cue, "rev-parse", "--short=10", "HEAD"], { encoding: "utf8" }).trim();
  } catch {}
}

// The icons the parts draw: their name here, Central's package (Comma's: round, radius 2, stroke 2) and glyph.
const outlined = "@central-icons-react/round-outlined-radius-2-stroke-2";
const filled = "@central-icons-react/round-filled-radius-2-stroke-2";
const icons = [
  ["check", outlined, "IconCheckmark1"],
  ["cross", outlined, "IconCrossSmall"],
  ["chevron_down_small", outlined, "IconChevronDownSmall"],
  ["minus", outlined, "IconMinusLarge"],
  ["loader", outlined, "IconLoader"],
  ["bubble_alert", outlined, "IconBubbleAlert"],
  ["circle_check", outlined, "IconCircleCheck"],
  ["circle_x", outlined, "IconCircleX"],
  ["circle_check_filled", filled, "IconCircleCheck"],
  ["circle_info_filled", filled, "IconCircleInfo"],
  ["circle_x_filled", filled, "IconCircleX"],
  ["exclamation_circle_filled", filled, "IconExclamationCircle"],
];

const attr = (tag, name) => {
  const m = new RegExp(`\\s${name}="([^"]*)"`).exec(tag);
  return m ? m[1] : null;
};

/** An icon's layers: each path's data, whether it is filled (else stroked, how wide), whether it is a cut. */
const layers = (svg) => {
  const mask = /<mask[^>]*>([\s\S]*?)<\/mask>/.exec(svg);
  const body = mask ? mask[1] : svg;
  const out = [];
  // (a group's colour says what its paths are: white the icon, black a cut; the mask's own black rect left out)
  const re = /<g([^>]*)>([\s\S]*?)<\/g>|<path([^>]*)\/?>(?:<\/path>)?/g;
  const push = (tag, cut) => {
    const d = attr(tag, "d");
    if (!d) return;
    const stroke = attr(tag, "stroke");
    const fill = attr(tag, "fill");
    const color = /color:\s*#000/.test(tag) || fill === "#000" || stroke === "#000";
    const stroked = stroke !== null && stroke !== "none";
    out.push({
      d,
      fill: !stroked,
      width: stroked ? Number(attr(tag, "stroke-width") ?? "2") : 0,
      cut: cut || color,
    });
  };
  let m;
  while ((m = re.exec(body))) {
    if (m[1] !== undefined) {
      const cut = /color:\s*#000/.test(m[1]) || attr(m[1], "fill") === "#000";
      for (const p of m[2].matchAll(/<path([^>]*)\/?>/g)) push(p[1], cut);
    } else {
      push(m[3], false);
    }
  }
  return out;
};

const lines = [];
const say = (s = "") => lines.push(s);
say(`// Made by scripts/cm-icons.mjs from Central Icons as AFK-surf/Cue ${commit} has them (@central-icons-react):`);
say("// do not edit, run it again when they change. How they are drawn: icon.mbt.");
for (const [name, pkg, glyph] of icons) {
  const mod = require(`${pkg}/${glyph}`);
  const Icon = mod[glyph] ?? mod.default;
  const svg = renderToStaticMarkup(React.createElement(Icon, { size: 24 }));
  const ls = layers(svg);
  if (ls.length === 0) throw new Error(`cm-icons: no paths in ${pkg}/${glyph}`);
  say();
  say("///|");
  say(`/// ${pkg.split("/")[1]} ${glyph}.`);
  say(`pub let icon_${name} : Array[IconLayer] = [`);
  for (const l of ls) {
    say(`  { d: ${JSON.stringify(l.d)}, fill: ${l.fill}, width: ${l.width.toFixed(2)}, cut: ${l.cut} },`);
  }
  say("]");
}
const out = resolve(dirname(fileURLToPath(import.meta.url)), "../src/cm/icons_made.mbt");
writeFileSync(out, lines.join("\n") + "\n");
console.log(`cm-icons: ${icons.length} icons, from ${commit}, to ${out}`);
