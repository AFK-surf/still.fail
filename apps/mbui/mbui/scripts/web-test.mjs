// Drives the browser build in Chromium: screenshots, a real input-method
// composition through CDP (Input.imeSetComposition), and the scroll bench.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
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
const browser = await chromium.launch({
  // MBUI_WEB_CHANNEL=chrome: the system's Google Chrome in place of Playwright's Chromium
  ...(process.env.MBUI_WEB_CHANNEL ? { channel: process.env.MBUI_WEB_CHANNEL } : {}),
  headless: !headed,
  args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'],
});
const ctx = await browser.newContext({ viewport: { width: 900, height: 720 }, deviceScaleFactor: 2 });
// Exercise the Apple text bindings even when the browser test runs on another system.
await ctx.addInitScript(() => {
  Object.defineProperty(navigator, 'platform', { value: 'MacIntel' });
  Object.defineProperty(navigator, 'userAgentData', { value: { platform: 'macOS' } });
});
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
// A second paragraph makes moving to its start distinguishable from selecting the whole field.
m = await mark();
await page.keyboard.press('Shift+Enter');
await drawn(m, { k: 'key' });
m = await mark();
await page.keyboard.type('abc');
await drawn(m, { k: 'text', s: 'c' });
// On a Mac Control-A moves the caret, while Command-A selects all. Read the app's selection back from the IME mirror
// after the frame, not just the key the browser host handed it.
const field = () => page.locator('#ime').evaluate((el) => ({ value: el.value, start: el.selectionStart, end: el.selectionEnd }));
const typed = await field();
const paragraph = typed.value.lastIndexOf('\n', typed.end - 1) + 1;
assert.ok(paragraph > 0, 'the field has two paragraphs');
const key = async (keys, n = 1) => { const from = await mark(); await page.keyboard.press(keys); await drawn(from, { k: 'key' }, n); };
const picked = async (start, end, why) => {
  const selection = await field();
  assert.deepEqual([selection.start, selection.end], [start, end], why);
};
await key('Control+a');
await picked(paragraph, paragraph, 'Control-A moves to the beginning of the paragraph');
await key('Control+e');
await picked(typed.end, typed.end, 'Control-E moves to the end of the paragraph');
await key('Control+b');
await picked(typed.end - 1, typed.end - 1, 'Control-B moves back');
await key('Control+f');
await picked(typed.end, typed.end, 'Control-F moves forward');
await key('Control+Alt+b');
await picked(paragraph, paragraph, 'Control-Option-B moves back a word');
await key('Control+Alt+f');
await picked(typed.end, typed.end, 'Control-Option-F moves forward a word');
await key('Control+ArrowLeft');
await picked(paragraph, paragraph, 'Control-Left moves to the line start');
await key('Control+ArrowRight');
await picked(typed.end, typed.end, 'Control-Right moves to the line end');
await key('Control+Shift+a');
await picked(paragraph, typed.end, 'Control-Shift-A selects back to the paragraph start');
await key('Control+x');
assert.equal((await field()).value, typed.value, 'Control-X does not cut on a Mac');
await key('Meta+a');
await picked(0, typed.value.length, 'Command-A selects all');
await key('Control+e');
await key('Control+b');
await key('Control+d');
assert.equal((await field()).value, typed.value.slice(0, -1), 'Control-D deletes forward');
await key('Control+h');
assert.equal((await field()).value, typed.value.slice(0, -2), 'Control-H deletes backward');
await key('Control+a');
await key('Control+k');
assert.equal((await field()).value, typed.value.slice(0, paragraph), 'Control-K deletes to the paragraph end');
await key('Control+o', 2);
const selection = await field();
assert.deepEqual([selection.value, selection.start, selection.end], [typed.value.slice(0, paragraph) + '\n', paragraph, paragraph], 'Control-O opens a line');
m = await mark();
await page.keyboard.press('Enter');
await drawn(m, { k: 'key' });
await page.screenshot({ path: `${shots}/04-sent.png` });
// Voice input writes a guess and replaces it as it hears more. iOS's dictation selects its last guess and inserts the
// next over it (WebPage::replaceDictatedText); a keyboard of another's deletes it key by key and types the next. Only
// the last guess is in the field either way.
const guess = (next, prev, keyByKey) => page.evaluate(([next, prev, keyByKey]) => {
  const ta = document.getElementById('ime');
  if (keyByKey) {
    for (let i = 0; i < prev.length; i++) document.execCommand('delete');
  } else if (prev) {
    ta.setSelectionRange(ta.selectionStart - prev.length, ta.selectionStart);
  }
  document.execCommand('insertText', false, next);
}, [next, prev, keyByKey]);
for (const keyByKey of [false, true]) {
  let prev = '';
  for (const next of ['今天', '今天天气', '今天天气真不错 👋']) {
    m = await mark();
    await guess(next, prev, keyByKey);
    // (what was put in, past what the guess before it and this one begin with)
    await drawn(m, { k: 'text', s: keyByKey ? next : next.slice(prev.length) });
    prev = next;
  }
  assert.equal((await field()).value, prev, `one sentence said is one sentence written (${keyByKey ? 'key by key' : 'replaced'})`);
  m = await mark();
  await page.keyboard.press('Enter');
  await drawn(m, { k: 'key' });
}
// A phone's soft keyboard changes no size of the page's, only the visual viewport's: the app laid out above it. Put
// away by the person (Safari's Done), the field lets go of the focus, and the keyboard does not come back.
await page.evaluate(() => {
  window.__frameHs = [];
  window.__frame = window.__mb.frame;
  window.__mb.frame = (w, h, s, t) => { window.__frameHs.push(h); window.__frame(w, h, s, t); };
  Object.defineProperty(window.visualViewport, 'height', { get: () => window.innerHeight - 300, configurable: true });
  window.visualViewport.dispatchEvent(new Event('resize'));
});
await page.waitForFunction(() => window.__frameHs.at(-1) === window.innerHeight - 300, null, { timeout: 30000 });
await page.waitForFunction(() => document.activeElement === document.getElementById('ime'));
m = await mark();
await page.evaluate(() => document.getElementById('ime').blur());
await drawn(m, { k: 'text', s: '' });
assert.notEqual(await page.evaluate(() => document.activeElement.id), 'ime', 'the keyboard put away stays away');
await page.evaluate(() => {
  delete window.visualViewport.height;
  window.visualViewport.dispatchEvent(new Event('resize'));
});
await page.waitForFunction(() => window.__frameHs.at(-1) === window.innerHeight, null, { timeout: 30000 });
await page.evaluate(() => { window.__mb.frame = window.__frame; });
// (pressed again, it takes the focus again)
await page.mouse.click(120, 690);
await page.waitForFunction(() => document.activeElement === document.getElementById('ime'));
m = await mark();
for (let i = 0; i < 30; i++) await page.mouse.wheel(0, -120);
await drawn(m, { k: 'wheel' }, 30);
await page.screenshot({ path: `${shots}/05-scrolled.png` });

// The same browser host must still use Control as the command key on Windows.
const win = await browser.newContext({ viewport: { width: 900, height: 720 }, deviceScaleFactor: 2 });
await win.addInitScript(() => {
  Object.defineProperty(navigator, 'platform', { value: 'Win32' });
  Object.defineProperty(navigator, 'userAgentData', { value: { platform: 'Windows' } });
});
const wp = await win.newPage();
await wp.goto(base + '?MBUI_DRAW_LOG=1');
await wp.waitForFunction(() => window.__logs.some((l) => l.startsWith('DRAWHASH ')), null, { timeout: 30000 });
await wp.mouse.click(120, 690);
await wp.waitForFunction(() => document.activeElement === document.getElementById('ime'));
m = await mark(wp);
await wp.keyboard.type('abc');
await drawn(m, { k: 'text', s: 'c' }, 1, wp);
m = await mark(wp);
await wp.keyboard.press('Control+a');
await drawn(m, { k: 'key' }, 1, wp);
const winField = await wp.locator('#ime').evaluate((el) => ({ value: el.value, start: el.selectionStart, end: el.selectionEnd }));
assert.deepEqual([winField.start, winField.end], [0, winField.value.length], 'Control-A selects all on Windows');
await win.close();
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
