// The differential text test in the browser (src/textdiff built for the web into out/web): runs it in headless
// Chromium and saves what it made (window.__mbref: each page's WebGL picture and its canvas fillText twin) and its
// log into DIR:  node scripts/textdiff-web.mjs DIR   (QUERY=k=v: more of the page's query)
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(path.resolve('out/node/node_modules/playwright'));
const dir = process.argv[2];
fs.mkdirSync(dir, { recursive: true });
const root = path.resolve('out/web');
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  const f = fs.existsSync(p) && fs.statSync(p).isFile() ? p : path.join(root, 'index.html');
  res.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : 'text/html' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const browser = await chromium.launch();
const [w, h] = (process.env.WIN || '900x800').split('x').map(Number);
const page = await (await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 2 })).newPage();
await page.goto(`http://127.0.0.1:${server.address().port}/?bench=-1${process.env.QUERY ? '&' + process.env.QUERY : ''}`);
await page.waitForFunction(() => window.__done !== undefined, null, { timeout: 300000 });
const { refs, logs } = await page.evaluate(() => ({ refs: window.__mbref, logs: window.__logs }));
for (const [name, url] of Object.entries(refs)) fs.writeFileSync(path.join(dir, name + '.png'), Buffer.from(url.split(',')[1], 'base64'));
fs.writeFileSync(path.join(dir, 'log.txt'), logs.join('\n') + '\n');
console.log(`${Object.keys(refs).length} pictures, ${logs.length} log lines into ${dir}`);
await browser.close();
server.close();
