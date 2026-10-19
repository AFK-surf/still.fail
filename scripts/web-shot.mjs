// One screenshot of the browser build, in stable mode: [QUERY=k=v] node web-shot.mjs out.png
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(path.resolve('out/node/node_modules/playwright'));
const root = path.resolve('out/web');
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  const f = fs.existsSync(p) && fs.statSync(p).isFile() ? p : path.join(root, 'index.html');
  const type = f.endsWith('.js') ? 'text/javascript' : f.endsWith('.jpg') ? 'image/jpeg' : 'text/html';
  res.writeHead(200, { 'content-type': type });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => server.listen(0, r));
// a player plays when the app says so, as on the other hosts (Chromium's own rule wants a press on the page first)
const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
const page = await (await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })).newPage();
// QUERY: more of the page's query (MBUI_SCREEN=kit: the demo's kit screen)
fs.rmSync(process.argv[2], { force: true });
await page.goto(`http://127.0.0.1:${server.address().port}/?bench=-1${process.env.QUERY ? '&' + process.env.QUERY : ''}`);
await page.waitForFunction(() => window.__mb !== undefined);
// shot once the app is settled (web/host.js __mbhost.settled: as its last frame said, no frame asked for since);
// SETTLE_TIMEOUT (30000 ms) without is a failure, said with what it awaits, and no picture
const settled = await page.waitForFunction(() => window.__done !== undefined || __mbhost.settled(), null, { timeout: Number(process.env.SETTLE_TIMEOUT || 30000) })
  .then(() => page.evaluate(() => __mbhost.settled()), () => false);
if (settled) await page.screenshot({ path: process.argv[2] });
else console.log(`SETTLE FAIL ${process.argv[2]}: not settled:`, JSON.stringify(await page.evaluate(() => __mbhost.unsettled())));
await browser.close();
server.close();
process.exit(settled ? 0 : 1);
