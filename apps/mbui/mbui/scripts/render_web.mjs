// mbui-render in headless Chromium (web/render.html: web/host.js's WebGL2 renderer, on SwiftShader): the draw list
// given to the page (globalThis.__mbrender), the picture read back from the canvas and written as a PNG (pngjs).
// The page's own main draws it as it loads; nothing is waited for but the load.
//   node scripts/render_web.mjs SITE LIST.dl OUT.png      (SITE: render.html, host.js, render.js)
// prints the renderer's line, the browser's version and the GL renderer's name.
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const mods = path.resolve('out/node/node_modules');
const { chromium } = require(path.join(mods, 'playwright'));
const { PNG } = require(path.join(mods, 'pngjs'));
const [site, dlPath, outPath] = process.argv.slice(2);
const root = path.resolve(site);
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!fs.existsSync(p) || !fs.statSync(p).isFile()) {
    res.writeHead(404);
    res.end();
    return;
  }
  res.writeHead(200, { 'content-type': p.endsWith('.js') ? 'text/javascript' : 'text/html' });
  fs.createReadStream(p).pipe(res);
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
// WebGL on the CPU (SwiftShader through ANGLE): the same rasterizer on every machine, no GPU's
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await (await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 })).newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.addInitScript(({ dl, out }) => {
  const env = { MBUI_DL: 'list.dl', MBUI_DL_PNG: out };
  globalThis.__mbrender = {
    said: [],
    shots: {},
    arg: (n) => env[n] || '',
    readText: (p) => (p === 'list.dl' ? dl : ''),
    say(s) { this.said.push(s); },
    snapshot(p) { this.shots[p] = globalThis.__mbhost.renderPixels(); return true; },
  };
}, { dl: fs.readFileSync(dlPath, 'utf8'), out: path.basename(outPath) });
await page.goto(`http://127.0.0.1:${server.address().port}/render.html`);
const got = await page.evaluate((out) => {
  const r = globalThis.__mbrender;
  const shot = r.shots[out];
  let b64 = '';
  if (shot) {
    let bin = '';
    for (let i = 0; i < shot.px.length; i += 0x8000) bin += String.fromCharCode.apply(null, shot.px.subarray(i, i + 0x8000));
    b64 = btoa(bin);
  }
  return { said: r.said, w: shot ? shot.w : 0, h: shot ? shot.h : 0, b64, gl: globalThis.__mbhost.renderInfo ? globalThis.__mbhost.renderInfo() : '' };
}, path.basename(outPath));
console.log(got.said.join('\n'));
console.log(`browser chromium ${browser.version()}`);
console.log(`gl ${got.gl}`);
await browser.close();
server.close();
if (errors.length || !got.w) {
  console.log(`render_web: ${errors.length ? errors.join('\n') : 'no picture'}`);
  process.exit(1);
}
const png = new PNG({ width: got.w, height: got.h });
Buffer.from(got.b64, 'base64').copy(png.data);
fs.writeFileSync(outPath, PNG.sync.write(png, { colorType: 6 }));
