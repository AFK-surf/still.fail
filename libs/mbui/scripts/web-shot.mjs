// One screenshot of the browser build, at a declared moment of its run: [QUERY=k=v] node web-shot.mjs out.png MS
// (MS: the time on the run's own clock the picture is of, web/host.js's shot_at: frames 1/60 s apart from 0)
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
const at = Number(process.argv[3]);
if (!(at >= 0)) { console.log('web-shot: the moment the picture is of (ms on the run\'s clock) is its second argument'); process.exit(2); }
await page.goto(`http://127.0.0.1:${server.address().port}/?bench=-1&shot_at=${at}${process.env.QUERY ? '&' + process.env.QUERY : ''}`);
// the frame at that moment drawn (window.__shot, web/host.js), or the app ended before it (window.__done: a run that
// fails ends itself, its words on the log); SHOT_DEADLINE (60000 ms) is what a run that hangs is given, not a wait
const shot = await page.waitForFunction(() => window.__shot || (window.__done !== undefined && { done: window.__done }),
  null, { timeout: Number(process.env.SHOT_DEADLINE || 60000) }).then((h) => h.jsonValue(), () => null);
const ok = !!(shot && shot.frame && !shot.fail);
if (ok) await page.screenshot({ path: process.argv[2] });
else console.log(`SHOT FAIL ${process.argv[2]}: no frame at ${at} ms:`, JSON.stringify(shot),
  JSON.stringify(await page.evaluate(() => window.__logs.slice(-5))));
await browser.close();
server.close();
process.exit(ok ? 0 : 1);
