// Compares a screenshot with its golden: node imgdiff.mjs golden.png new.png review.png
// Prints the share of differing pixels and writes golden | new | diff side by side.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { PNG } = require(path.resolve('out/node/node_modules/pngjs'));
const pixelmatch = require(path.resolve('out/node/node_modules/pixelmatch')).default
  ?? require(path.resolve('out/node/node_modules/pixelmatch'));
const [goldenPath, newPath, reviewPath] = process.argv.slice(2);
const a = PNG.sync.read(fs.readFileSync(goldenPath));
const b = PNG.sync.read(fs.readFileSync(newPath));
const w = Math.max(a.width, b.width), h = Math.max(a.height, b.height);
const pad = (img) => {
  if (img.width === w && img.height === h) return img;
  const out = new PNG({ width: w, height: h });
  PNG.bitblt(img, out, 0, 0, img.width, img.height, 0, 0);
  return out;
};
const A = pad(a), B = pad(b);
const diff = new PNG({ width: w, height: h });
const n = pixelmatch(A.data, B.data, diff.data, w, h, { threshold: 0.12 });
const review = new PNG({ width: w * 3, height: h });
PNG.bitblt(A, review, 0, 0, w, h, 0, 0);
PNG.bitblt(B, review, 0, 0, w, h, w, 0);
PNG.bitblt(diff, review, 0, 0, w, h, w * 2, 0);
fs.writeFileSync(reviewPath, PNG.sync.write(review));
const share = n / (w * h);
console.log(`${path.basename(newPath)}: ${n} px differ (${(share * 100).toFixed(3)}%)${a.width !== b.width || a.height !== b.height ? ' size changed' : ''}`);
process.exit(share > 0.001 ? 1 : 0);
