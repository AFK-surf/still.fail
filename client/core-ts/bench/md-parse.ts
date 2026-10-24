// Markdown read in the engine the apps run (Hermes, no JIT): `parse` (markdown.ts) over agents' replies (replies.ts,
// given as TEXTS by whoever bundles it), timed, and markdown-it's part of it apart (mdRead.ts). Bundled as the core is
// and run by Hermes's own command: apps/mbui/scripts/core.sh md-parse.
import { parse } from "../src/markdown.ts";
import { read } from "../src/mdRead.ts";

declare const TEXTS: string[];
declare const print: (line: string) => void;

const chars = TEXTS.reduce((n, t) => n + t.length, 0);
/// `read` over every text, again and again for `ms`: characters read a second.
function rate(read: (text: string) => unknown, ms: number): number {
  for (const t of TEXTS) read(t);
  const t0 = Date.now();
  let rounds = 0;
  while (Date.now() - t0 < ms) {
    for (const t of TEXTS) read(t);
    rounds++;
  }
  return Math.round((chars * rounds) / ((Date.now() - t0) / 1000));
}

const nodes = rate(read, 4000);
const whole = rate(parse, 4000);
print(JSON.stringify({ texts: TEXTS.length, chars, readCharsPerS: nodes, parseCharsPerS: whole, pageMs: Math.round((80_000 / whole) * 1000) }));
