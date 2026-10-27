// What is in each model of assets/ (record.mjs assets): its meshes by node, their materials and sizes, to find each
// one's screen. `node web/film/inspect.mjs <assets dir>`.
import { readFile, readdir, stat } from 'node:fs/promises';
import { join } from 'node:path';

const dir = process.argv[2];
async function gltfOf(path) {
  const buf = await readFile(path);
  if (path.endsWith('.gltf')) return JSON.parse(buf.toString());
  const len = buf.readUInt32LE(12);
  return JSON.parse(buf.subarray(20, 20 + len).toString());
}
const files = [];
for (const n of await readdir(dir)) {
  const p = join(dir, n);
  if ((await stat(p)).isDirectory()) { for (const m of await readdir(p)) if (/\.(gltf|glb)$/.test(m)) files.push(join(p, m)); }
  else if (/\.(gltf|glb)$/.test(n)) files.push(p);
}
for (const f of files) {
  const g = await gltfOf(f);
  console.log(`\n=== ${f}  extensions: ${(g.extensionsUsed ?? []).join(',')}  extras: ${JSON.stringify(g.asset?.extras ?? {}).slice(0, 200)}`);
  const mats = g.materials ?? [];
  const rows = [];
  for (const [i, n] of (g.nodes ?? []).entries()) {
    if (n.mesh === undefined) continue;
    const m = g.meshes[n.mesh];
    for (const p of m.primitives) {
      const acc = g.accessors[p.attributes.POSITION];
      const size = acc.max && acc.min ? acc.max.map((x, k) => (x - acc.min[k]).toFixed(3)).join('×') : '?';
      const mat = mats[p.material] ?? {};
      const tex = mat.pbrMetallicRoughness?.baseColorTexture ? 'tex' : '';
      const col = mat.pbrMetallicRoughness?.baseColorFactor?.map((x) => x.toFixed(2)).join(',') ?? '';
      const d = acc.max && acc.min ? acc.max.map((x, k) => x - acc.min[k]).sort((a, b) => b - a) : [0, 0, 0];
      rows.push({ flat: d[2] < d[1] * 0.03, area: d[0] * d[1], line: `node ${i} "${n.name}" mesh "${m.name}" mat "${mat.name}" ${tex} [${col}] em=${JSON.stringify(mat.emissiveFactor ?? '')} size ${size} verts ${acc.count}` });
    }
  }
  console.log(`${rows.length} primitives; the flat ones, largest first:`);
  for (const r of rows.filter((r) => r.flat).sort((a, b) => b.area - a.area).slice(0, 10)) console.log('  ' + r.line);
  console.log(`material names: ${mats.map((m) => m.name).filter((n) => /screen|display|glass|lcd|panel|emiss/i.test(n)).join(', ')}`);
  console.log(`node names: ${(g.nodes ?? []).map((n) => n.name).filter((n) => n && /screen|display|glass|lcd|panel/i.test(n)).slice(0, 20).join(', ')}`);
}
