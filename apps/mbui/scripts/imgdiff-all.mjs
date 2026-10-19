// Screenshots compared with their goldens, all in one node: node imgdiff-all.mjs list.txt, each line
// `<golden.png>\t<new.png>\t<review.png>`. Each as mbui's scripts/imgdiff.mjs compares one (its line; its review,
// golden | new | differences, where any pixel is not the golden's); fails when any differs in more than 0.1% of its
// pixels. `identical` where every byte of every pixel is the golden's; else what pixelmatch counts (0.12 of colour,
// anti-aliased edges left out) and how many pixels are not exactly the golden's.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { PNG } = require(path.resolve('out/node/node_modules/pngjs'));
const pixelmatch = require(path.resolve('out/node/node_modules/pixelmatch')).default
  ?? require(path.resolve('out/node/node_modules/pixelmatch'));
const pad = (img, w, h) => {
  if (img.width === w && img.height === h) return img;
  const out = new PNG({ width: w, height: h });
  PNG.bitblt(img, out, 0, 0, img.width, img.height, 0, 0);
  return out;
};
let fail = 0;
for (const line of fs.readFileSync(process.argv[2], 'utf8').split('\n').filter(Boolean)) {
  const [goldenPath, newPath, reviewPath] = line.split('\t');
  if (!fs.existsSync(newPath)) {
    console.log(`${path.basename(newPath)}: not made`);
    fail = 1;
    continue;
  }
  const a = PNG.sync.read(fs.readFileSync(goldenPath));
  const b = PNG.sync.read(fs.readFileSync(newPath));
  const w = Math.max(a.width, b.width), h = Math.max(a.height, b.height);
  const A = pad(a, w, h), B = pad(b, w, h);
  if (a.width === b.width && a.height === b.height && A.data.equals(B.data)) {
    console.log(`${path.basename(newPath)}: identical`);
    continue;
  }
  let exact = 0;
  for (let i = 0; i < A.data.length; i += 4)
    if (A.data.readUInt32LE(i) !== B.data.readUInt32LE(i)) exact++;
  const diff = new PNG({ width: w, height: h });
  const n = pixelmatch(A.data, B.data, diff.data, w, h, { threshold: 0.12 });
  const review = new PNG({ width: w * 3, height: h });
  PNG.bitblt(A, review, 0, 0, w, h, 0, 0);
  PNG.bitblt(B, review, 0, 0, w, h, w, 0);
  PNG.bitblt(diff, review, 0, 0, w, h, w * 2, 0);
  fs.writeFileSync(reviewPath, PNG.sync.write(review));
  const share = n / (w * h);
  console.log(`${path.basename(newPath)}: ${n} px differ (${(share * 100).toFixed(3)}%), ${exact} not exact${a.width !== b.width || a.height !== b.height ? ', size changed' : ''}`);
  if (share > 0.001) fail = 1;
}
process.exit(fail);
