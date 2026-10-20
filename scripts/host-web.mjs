// A run of the browser build (out/web, scripts/web.sh build) in headless Chromium for the host's and the text's
// contracts (scripts/host_contract.sh web): the page opened with QUERY (the app's environment: web/host.js reads it
// as its query), waited on until the app ends itself (@host.exit: window.__done, its named end), its log written to
// OUT a line each; the app's end code is this script's.
//   node scripts/host-web.mjs QUERY OUT [W H]
// MBUI_WEB_CHANNEL=chrome: the system's Google Chrome in place of Playwright's Chromium (whose build decodes no H.264).
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(path.resolve('out/node/node_modules/playwright'));

const [query, out, w = '960', h = '720'] = process.argv.slice(2);
const root = path.resolve('out/web');
const types = { '.html': 'text/html', '.js': 'text/javascript' };
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  const f = fs.existsSync(p) && fs.statSync(p).isFile() ? p : path.join(root, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}/`;
// WebGL2 without a GPU: SwiftShader's
const browser = await chromium.launch({
  ...(process.env.MBUI_WEB_CHANNEL ? { channel: process.env.MBUI_WEB_CHANNEL } : {}),
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const ctx = await browser.newContext({ viewport: { width: Number(w), height: Number(h) }, deviceScaleFactor: 1 });
const page = await ctx.newPage();
const errors = [];
const failed = new Promise((r) => page.on('pageerror', (e) => { errors.push(String(e)); r('error'); }));
await page.goto(base + '?' + query);
// the app's own end (DRIVE PASS then exit, TEXTCHECK done then exit), or a page error: nothing else is waited for
const ended = page.waitForFunction(() => window.__done !== undefined, null, { timeout: 0, polling: 'raf' });
const code = (await Promise.race([ended, failed])) === 'error' ? 2 : await page.evaluate(() => window.__done);
const logs = await page.evaluate(() => window.__logs);
fs.writeFileSync(out, logs.join('\n') + '\n');
if (errors.length) console.log('page errors:\n' + errors.join('\n'));
console.log(`host-web: ${logs.length} lines, the app's end ${code}`);
await browser.close();
server.close();
process.exit(code === 0 ? 0 : 1);
