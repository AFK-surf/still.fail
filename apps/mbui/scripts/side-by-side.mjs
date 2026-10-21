// Pictures side by side, 16 apart on grey, for comparing (the web's and the app's at one size):
//   node scripts/side-by-side.mjs OUT.png A.png B.png [C.png …]   (from apps/mbui: pngjs in out/node, as shots.sh has it)
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
const { PNG } = createRequire(import.meta.url)(path.resolve('out/node/node_modules/pngjs'));
const [out, ...ins] = process.argv.slice(2);
const imgs = ins.map((p) => PNG.sync.read(readFileSync(p)));
const gap = 16;
const w = imgs.reduce((s, i) => s + i.width, 0) + gap * (imgs.length + 1);
const h = Math.max(...imgs.map((i) => i.height)) + gap * 2;
const o = new PNG({ width: w, height: h });
o.data.fill(0x99);
for (let k = 3; k < o.data.length; k += 4) o.data[k] = 255;
let x = gap;
for (const i of imgs) {
  PNG.bitblt(i, o, 0, 0, i.width, i.height, x, gap);
  x += i.width + gap;
}
writeFileSync(out, PNG.sync.write(o));
console.log(`${out}: ${w}x${h}`);
