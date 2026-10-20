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
// What the app took and drew, as its tape says (?MBUI_DRAW_LOG=1: an INPUT line for each input it was handed, as it
// was handed, a DRAWHASH line for each frame drawn; src/ui/inputrec.mbt): an input is drawn once the frame that took
// it and the one after it (inputs_since: for what was changed late in that frame) are on the log. `drawn(from, want,
// n)`: the n-th INPUT since log line `from` that `want` matches (k, the input's kind; s, its text), then those two
// frames. A run that hangs fails at 30 s, saying what came.
const mark = (p = page) => p.evaluate(() => window.__logs.length);
const drawn = (from, want, n = 1, p = page) => p.waitForFunction(([from, want, n]) => {
  const l = window.__logs.slice(from);
  let seen = 0, last = -1;
  l.forEach((x, i) => {
    if (!x.startsWith('INPUT ')) return;
    const j = JSON.parse(x.slice(6));
    if (j.k === want.k && (want.s === undefined || j.s === want.s)) { seen++; last = i; }
  });
  return seen >= n && l.slice(last + 1).filter((x) => x.startsWith('DRAWHASH ')).length >= 2;
}, [from, want, n], { timeout: 30000 }).catch(async () => {
  const came = await p.evaluate((f) => window.__logs.slice(f).filter((x) => x.startsWith('INPUT ')).slice(-5), from);
  throw new Error(`not drawn: ${JSON.stringify(want)} x${n}; the last inputs taken: ${JSON.stringify(came)}`);
});
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

const t0 = Date.now();
await page.goto(base + '?MBUI_DRAW_LOG=1');
// its first frame drawn
await page.waitForFunction(() => window.__logs.some((l) => l.startsWith('DRAWHASH ')), null, { timeout: 30000 });
console.log('first frames after', Date.now() - t0, 'ms');
await page.screenshot({ path: `${shots}/01-start.png` });

if (process.env.BENCH_ONLY) {
  await page.close();
} else {
// click the composer and type through a real composition
// (the input method's textarea focused: the app said its editor has the focus, web/host.js setIme)
await page.mouse.click(120, 690);
await page.waitForFunction(() => document.activeElement === document.getElementById('ime'));
const cdp = await ctx.newCDPSession(page);
let m = await mark();
await cdp.send('Input.imeSetComposition', { text: 'ni hao', selectionStart: 6, selectionEnd: 6 });
await drawn(m, { k: 'text', s: 'ni hao' });
await page.screenshot({ path: `${shots}/02-composing.png` });
m = await mark();
await cdp.send('Input.insertText', { text: '你好' });
await page.keyboard.type('，MoonBit ');
await cdp.send('Input.imeSetComposition', { text: 'shi jie', selectionStart: 7, selectionEnd: 7 });
await cdp.send('Input.insertText', { text: '世界 👋' });
await drawn(m, { k: 'text', s: '世界 👋' });
await page.screenshot({ path: `${shots}/03-typed.png` });
m = await mark();
await page.keyboard.press('Enter');
await drawn(m, { k: 'key' });
await page.screenshot({ path: `${shots}/04-sent.png` });
m = await mark();
for (let i = 0; i < 30; i++) await page.mouse.wheel(0, -120);
await drawn(m, { k: 'wheel' }, 30);
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
