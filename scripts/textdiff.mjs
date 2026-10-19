// Compares mbui's text with the platform's own, string by string (src/textdiff draws both; scripts/textdiff.sh runs
// it):  node scripts/textdiff.mjs DIR [HOST]
// DIR holds pN-mbui.png and pN-native.png for each page and log.txt with the app's "TXD {…}" lines. For each string:
//   advance  the width mbui lays it out in against the platform's own (Core Text's line, Android's StaticLayout, …)
//   ink box  the box of its ink in each picture, edge by edge, in device pixels
//   pixels   the share of its ink that has nothing like it in the other picture within a pixel either way (so
//            antialiasing and the half pixel mbui rounds each glyph to are not counted)
// Writes DIR/report.html (the worst side by side: mbui, the platform, where they differ), DIR/summary.json and
// DIR/rows/*.png. With EXPECT=file (src/text/testdata/textdiff-HOST.json): exits 1 when a string differs that the
// file does not list as known to; UPDATE=1 writes that file from this run instead.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { PNG } = require(path.resolve('out/node/node_modules/pngjs'));

const dir = process.argv[2];
const host = process.argv[3] || path.basename(dir);
// how far apart the two may be and still count as the same
const ADV_TOL = (w) => 0.3 + 0.004 * w; // points
const EDGE_TOL = 2; // device pixels, each edge of the ink box
const PIX_TOL = 0.04; // share of the ink
const INK = 0.2; // what counts as ink: this far from the white ground
const CH_TOL = 64; // how far a channel may differ at a pixel, softened

const rows = [];
for (const line of fs.readFileSync(path.join(dir, 'log.txt'), 'utf8').split('\n')) {
  const i = line.indexOf('TXD {');
  if (i >= 0) rows.push(JSON.parse(line.slice(i + 4)));
}
if (!rows.length) {
  console.error(`textdiff: no rows in ${dir}/log.txt`);
  process.exit(2);
}
const pics = new Map();
const pic = (name) => {
  if (!pics.has(name)) {
    const f = path.join(dir, name + '.png');
    pics.set(name, fs.existsSync(f) ? PNG.sync.read(fs.readFileSync(f)) : null);
  }
  return pics.get(name);
};

// a band of a picture, as RGB on the white ground (alpha flattened)
function band(img, y0, y1, w) {
  const h = y1 - y0;
  const out = new Uint8Array(w * h * 3);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const yy = y0 + y;
      const o = (y * w + x) * 3;
      if (x >= img.width || yy < 0 || yy >= img.height) {
        out[o] = out[o + 1] = out[o + 2] = 255;
        continue;
      }
      const s = (yy * img.width + x) * 4;
      const a = img.data[s + 3] / 255;
      for (let k = 0; k < 3; k++) out[o + k] = Math.round(img.data[s + k] * a + 255 * (1 - a));
    }
  }
  return { w, h, px: out };
}
const ink = (b, x, y) => {
  const o = (y * b.w + x) * 3;
  return (255 - Math.min(b.px[o], b.px[o + 1], b.px[o + 2])) / 255;
};
function box(b) {
  let l = Infinity, t = Infinity, r = -Infinity, btm = -Infinity, n = 0;
  for (let y = 0; y < b.h; y++)
    for (let x = 0; x < b.w; x++)
      if (ink(b, x, y) > INK) {
        n++;
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > btm) btm = y;
      }
  return n ? { l, t, r: r + 1, b: btm + 1, n } : null;
}
// a band softened by a [1 2 1] kernel each way, so that ink half a pixel off (mbui puts each glyph on whole pixels,
// the platform where its advances fall) reads as nearly the same
function blur(b) {
  const tmp = new Float32Array(b.w * b.h * 3), out = new Float32Array(b.w * b.h * 3);
  const at = (arr, x, y, k, w, h) => arr[(Math.min(h - 1, Math.max(0, y)) * w + Math.min(w - 1, Math.max(0, x))) * 3 + k];
  for (let y = 0; y < b.h; y++)
    for (let x = 0; x < b.w; x++)
      for (let k = 0; k < 3; k++)
        tmp[(y * b.w + x) * 3 + k] = (at(b.px, x - 1, y, k, b.w, b.h) + 2 * at(b.px, x, y, k, b.w, b.h) + at(b.px, x + 1, y, k, b.w, b.h)) / 4;
  for (let y = 0; y < b.h; y++)
    for (let x = 0; x < b.w; x++)
      for (let k = 0; k < 3; k++)
        out[(y * b.w + x) * 3 + k] = (at(tmp, x, y - 1, k, b.w, b.h) + 2 * at(tmp, x, y, k, b.w, b.h) + at(tmp, x, y + 1, k, b.w, b.h)) / 4;
  return { w: b.w, h: b.h, px: out };
}
// the ink of a (softened) with nothing like it in b within a pixel either way; marks them in m
function unmatched(a, b, m, bit) {
  let n = 0;
  for (let y = 0; y < a.h; y++)
    for (let x = 0; x < a.w; x++) {
      if (ink(a, x, y) <= 0.1) continue;
      const o = (y * a.w + x) * 3;
      let ok = false;
      for (let dy = -1; dy <= 1 && !ok; dy++)
        for (let dx = -1; dx <= 1 && !ok; dx++) {
          const xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= b.w || yy >= b.h) continue;
          const q = (yy * b.w + xx) * 3;
          ok = Math.abs(a.px[o] - b.px[q]) <= CH_TOL && Math.abs(a.px[o + 1] - b.px[q + 1]) <= CH_TOL &&
            Math.abs(a.px[o + 2] - b.px[q + 2]) <= CH_TOL;
        }
      if (!ok) {
        n++;
        m[y * a.w + x] |= bit;
      }
    }
  return n;
}
function inkCount(b) {
  let n = 0;
  for (let y = 0; y < b.h; y++) for (let x = 0; x < b.w; x++) if (ink(b, x, y) > 0.1) n++;
  return n;
}
function crop(b, l, r, m) {
  const w = Math.max(1, r - l);
  const png = new PNG({ width: w, height: b.h });
  for (let y = 0; y < b.h; y++)
    for (let x = 0; x < w; x++) {
      const o = (y * b.w + x + l) * 3, d = (y * w + x) * 4;
      if (m) {
        // where they differ: red only mbui's ink, blue only the platform's, grey both alike
        const v = m[y * b.w + x + l];
        const g = 255 - Math.round(ink(b, x + l, y) * 120);
        png.data.set(v & 1 && v & 2 ? [200, 0, 200, 255] : v & 1 ? [230, 0, 0, 255] : v & 2 ? [0, 60, 230, 255] : [g, g, g, 255], d);
      } else {
        png.data.set([b.px[o], b.px[o + 1], b.px[o + 2], 255], d);
      }
    }
  return PNG.sync.write(png);
}

const outRows = path.join(dir, 'rows');
fs.rmSync(outRows, { recursive: true, force: true });
fs.mkdirSync(outRows, { recursive: true });
const results = [];
for (const r of rows) {
  const A = pic(`p${r.page}-mbui`), B = pic(`p${r.page}-native`);
  if (!A || !B) {
    results.push({ ...r, missing: true, bad: ['missing'] });
    continue;
  }
  const sc = r.scale;
  const y0 = Math.round(r.top * sc), y1 = Math.round((r.top + r.h) * sc);
  const w = Math.min(A.width, B.width);
  const a = band(A, y0, y1, w), b = band(B, y0, y1, w);
  const ba = box(a), bb = box(b);
  const m = new Uint8Array(w * a.h);
  const sa = blur(a), sb = blur(b);
  const ua = unmatched(sa, sb, m, 1), ub = unmatched(sb, sa, m, 2);
  const inkN = Math.max(inkCount(sa), inkCount(sb), 1);
  const pix = Math.max(ua, ub) / inkN;
  const dAdv = r.mbui - r.native;
  const edges = ba && bb ? [ba.l - bb.l, ba.t - bb.t, ba.r - bb.r, ba.b - bb.b] : null;
  const bad = [];
  if (Math.abs(dAdv) > ADV_TOL(Math.abs(r.native))) bad.push('advance');
  if ((ba === null) !== (bb === null)) bad.push('ink');
  else if (edges && Math.max(...edges.map(Math.abs)) > EDGE_TOL) bad.push('box');
  if (pix > PIX_TOL) bad.push('pixels');
  const res = { ...r, dAdv, boxMbui: ba, boxNative: bb, edges, pix, bad };
  const key = `${String(r.row).padStart(4, '0')}`;
  const l = Math.max(0, Math.min(ba ? ba.l : w, bb ? bb.l : w) - 4);
  const rr = Math.min(w, Math.max(ba ? ba.r : 0, bb ? bb.r : 0, l + 8) + 4);
  if (bad.length) {
    fs.writeFileSync(path.join(outRows, key + '-mbui.png'), crop(a, l, rr));
    fs.writeFileSync(path.join(outRows, key + '-native.png'), crop(b, l, rr));
    fs.writeFileSync(path.join(outRows, key + '-diff.png'), crop(a, l, rr, m));
    res.crops = key;
  }
  results.push(res);
}

const font = (r) => `${r.size}${r.weight >= 600 ? ' bold' : ''}${r.style & 1 ? ' italic' : ''}${r.style & 2 ? ' mono' : ''}`;
const score = (r) => (r.missing ? 1e9 : r.pix * 100 + Math.abs(r.dAdv) / Math.max(1, r.size) * 50 + (r.edges ? Math.max(...r.edges.map(Math.abs)) : 20));
const bad = results.filter((r) => r.bad.length);
bad.sort((x, y) => score(y) - score(x));
const count = (k) => results.filter((r) => r.bad.includes(k)).length;
const summary = {
  host,
  rows: results.length,
  differ: bad.length,
  advance: count('advance'),
  box: count('box') + count('ink'),
  pixels: count('pixels'),
  ids: [...new Set(bad.map((r) => r.id))].sort(),
  worst: bad.slice(0, 15).map((r) => ({ id: r.id, font: font(r), bad: r.bad, dAdv: +(r.dAdv ?? 0).toFixed(2), pix: +(r.pix ?? 0).toFixed(3), edges: r.edges })),
};
fs.writeFileSync(path.join(dir, 'summary.json'), JSON.stringify({ ...summary, results: results.map(({ boxMbui, boxNative, ...r }) => r) }, null, 1));

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\t/g, '⇥');
let html = `<!doctype html><meta charset="utf-8"><title>textdiff ${host}</title>
<style>body{font:13px system-ui;margin:16px}table{border-collapse:collapse}td,th{padding:3px 8px;border-bottom:1px solid #ddd;text-align:left;vertical-align:top}
img{image-rendering:pixelated;max-width:900px;border:1px solid #ccc;display:block;margin:2px 0}.bad{color:#c00}.k{color:#888}</style>
<h1>mbui against ${esc(host)}'s own text drawing</h1>
<p>${results.length} strings in their fonts; <b>${bad.length}</b> differ: advance ${summary.advance}, ink box ${summary.box}, pixels ${summary.pixels}.
Tolerances: advance 0.3 pt + 0.4%, each ink edge ${EDGE_TOL} px, unmatched ink ${PIX_TOL * 100}% (both pictures softened by a [1 2 1] kernel; a pixel's ink matches when the other has ink like it, each channel within ${CH_TOL}, within a pixel).
In the third picture red is ink only mbui drew, blue ink only the platform drew.</p>
<table><tr><th>string</th><th>font</th><th>what differs</th><th>advance mbui / native (Δ)</th><th>ink edges Δ px (l t r b)</th><th>unmatched ink</th><th>mbui · native · differences</th></tr>`;
for (const r of bad) {
  html += `<tr><td><b>${esc(r.id)}</b><br><span class="k">${esc(r.text)}</span></td><td>${font(r)}</td><td class="bad">${r.bad.join(', ')}</td>
<td>${r.missing ? '' : `${r.mbui.toFixed(2)} / ${r.native.toFixed(2)} (${r.dAdv >= 0 ? '+' : ''}${r.dAdv.toFixed(2)})`}</td><td>${r.edges ? r.edges.join(' ') : '—'}</td><td>${r.missing ? '' : (r.pix * 100).toFixed(1) + '%'}</td>
<td>${r.crops ? ['mbui', 'native', 'diff'].map((k) => `<img src="rows/${r.crops}-${k}.png">`).join('') : ''}</td></tr>`;
}
html += `</table><h2>All strings</h2><table><tr><th>string</th><th>font</th><th>Δ advance</th><th>edges</th><th>unmatched</th></tr>`;
for (const r of results)
  html += `<tr><td>${esc(r.id)}</td><td>${font(r)}</td><td>${r.missing ? '' : r.dAdv.toFixed(2)}</td><td>${r.edges ? r.edges.join(' ') : '—'}</td><td class="${r.bad.length ? 'bad' : ''}">${r.missing ? 'missing' : (r.pix * 100).toFixed(1) + '%'}</td></tr>`;
html += '</table>';
fs.writeFileSync(path.join(dir, 'report.html'), html);

console.log(`textdiff ${host}: ${results.length} strings, ${bad.length} differ (advance ${summary.advance}, ink box ${summary.box}, pixels ${summary.pixels})`);
for (const w of summary.worst) console.log(`  ${w.id} [${w.font}] ${w.bad.join(',')} Δadv ${w.dAdv} unmatched ${(w.pix * 100).toFixed(1)}% edges ${w.edges ? w.edges.join(' ') : '-'}`);
console.log(`report: ${path.join(dir, 'report.html')}`);

// what this platform is known to differ in, by string id: a row of another id that differs fails the run
const expect = process.env.EXPECT;
if (expect && process.env.UPDATE === '1') {
  fs.writeFileSync(expect, JSON.stringify({ host, known: summary.ids }, null, 1) + '\n');
  console.log(`wrote ${expect}`);
} else if (expect && fs.existsSync(expect)) {
  const known = new Set(JSON.parse(fs.readFileSync(expect, 'utf8')).known);
  const fresh = summary.ids.filter((id) => !known.has(id));
  const fixed = [...known].filter((id) => !summary.ids.includes(id) && results.some((r) => r.id === id));
  if (fixed.length) console.log(`no longer differ (UPDATE=1 to drop them from ${expect}): ${fixed.join(' ')}`);
  if (fresh.length) {
    console.log(`FAIL differ now, not before: ${fresh.join(' ')}`);
    process.exit(1);
  }
  console.log('ok: nothing differs that did not before');
}
