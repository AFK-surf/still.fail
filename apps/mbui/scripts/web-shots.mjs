// The browser build's screenshots, many in one browser: node web-shots.mjs list.txt, each line `<query>\t<out.png>`
// (the query: more of the page's, as mbui's scripts/web-shot.mjs takes it in QUERY; empty for none). What mbui's
// web-shot.mjs does for one, with one server and one Chromium for all of them and SHOT_JOBS (4) pages at a time, each
// in a fresh context: a browser's start (a second or two) once, not once a shot.
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(path.resolve('out/node/node_modules/playwright'));
const root = path.resolve('out/web');
const shots = fs.readFileSync(process.argv[2], 'utf8').split('\n').filter(Boolean).map((l) => l.split('\t'));
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
let next = 0, failed = 0;
async function worker() {
  while (next < shots.length) {
    const [query, out] = shots[next++];
    // (a machine this busy now and then keeps a page from loading in time: once more before it is a failure)
    for (let k = 1; k <= 2; k++) {
      const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
      try {
        const page = await ctx.newPage();
        await page.goto(`http://127.0.0.1:${server.address().port}/?bench=-1${query ? '&' + query : ''}`);
        await page.waitForFunction(() => window.__mb !== undefined);
        await page.waitForTimeout(Number(process.env.WAIT || 800));
        await page.screenshot({ path: out });
        break;
      } catch (e) {
        console.log(`${path.basename(out)}: not taken${k === 1 ? ', again' : ''} (${e.message.split('\n')[0]})`);
        if (k === 2) failed++;
      } finally {
        await ctx.close();
      }
    }
  }
}
await Promise.all(Array.from({ length: Math.min(Number(process.env.SHOT_JOBS || 4), shots.length) }, worker));
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
