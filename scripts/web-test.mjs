// Drives the browser build in Chromium: screenshots, a real input-method
// composition through CDP (Input.imeSetComposition), and the scroll bench.
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(path.resolve('out/node/node_modules/playwright'));

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
const shots = 'out/web-shots';
fs.mkdirSync(shots, { recursive: true });

const headed = !!process.env.HEADED;
const browser = await chromium.launch({ headless: !headed, args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const ctx = await browser.newContext({ viewport: { width: 900, height: 720 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();
const errors = [];
// the app settled: no frame asked for (motion over, what was typed drawn), nothing awaited of the host, no timer
// what is shown waits for (web/host.js __mbhost.settled; a caret's blink is a `later` one, not waited for)
const idle = (p = page) => p.waitForFunction(() => __mbhost.settled(), null, { timeout: 30000 })
  .catch(async (e) => { throw new Error(`not settled: ${JSON.stringify(await p.evaluate(() => __mbhost.unsettled()))}`); });
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

const t0 = Date.now();
await page.goto(base);
await page.waitForFunction(() => window.__mb !== undefined);
await idle();
console.log('first frames after', Date.now() - t0, 'ms');
await page.screenshot({ path: `${shots}/01-start.png` });

if (process.env.BENCH_ONLY) {
  await page.close();
} else {
// click the composer and type through a real composition
await page.mouse.click(120, 690);
await page.waitForFunction(() => document.activeElement === document.getElementById('ime'));
await idle();
const cdp = await ctx.newCDPSession(page);
await cdp.send('Input.imeSetComposition', { text: 'ni hao', selectionStart: 6, selectionEnd: 6 });
await idle();
await page.screenshot({ path: `${shots}/02-composing.png` });
await cdp.send('Input.insertText', { text: '你好' });
await page.keyboard.type('，MoonBit ');
await cdp.send('Input.imeSetComposition', { text: 'shi jie', selectionStart: 7, selectionEnd: 7 });
await cdp.send('Input.insertText', { text: '世界 👋' });
await idle();
await page.screenshot({ path: `${shots}/03-typed.png` });
await page.keyboard.press('Enter');
await idle();
await page.screenshot({ path: `${shots}/04-sent.png` });
for (let i = 0; i < 30; i++) await page.mouse.wheel(0, -120);
await idle();
await page.screenshot({ path: `${shots}/05-scrolled.png` });
}

// scroll bench in a fresh page
const b = await ctx.newPage();
await b.goto(base + '?bench=1');
await b.waitForFunction(() => window.__done !== undefined, null, { timeout: 60000 });
const logs = await b.evaluate(() => window.__logs);
console.log(logs.filter((l) => l.startsWith('BENCH')).join('\n'));
console.log('errors:', errors.length ? errors.join('\n') : 'none');
await browser.close();
server.close();
