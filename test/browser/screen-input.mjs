// A station's screen driven from the page (web/src/screen/ScreenViewer.tsx, input.ts): in the stories' live view (its
// made-up station draws real JPEG frames: web/stories/screens.ts, which keeps what the view was told in
// `window.screenInputs`), the picture letterboxed in a window of another shape, then a mouse (a click at the picture's
// middle is 0.5, 0.5; one in the letterbox says nothing), the wheel, keys, an IME's and a paste's text, 只看 (nothing
// goes), and on a phone a finger: a tap clicks, a drag holds the button, two fingers scroll. Builds the stories and serves
// the build, as stories.mjs does. PLAYWRIGHT_MODULE selects Playwright; SHOTS keeps a picture of each.
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
let server, browser, dist;
const near = (a, b, why) => assert.ok(Math.abs(a - b) < 0.01, `${why}: ${a} is not ${b}`);
try {
  const configFile = fileURLToPath(new URL('../../web/vite.stories.config.ts', import.meta.url));
  dist = await mkdtemp(join(tmpdir(), 'screen-input-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  // ── a mouse and keys ──
  // 1280×700: the 1600×1000 picture is 1120×700, 80 in from either side.
  const page = await browser.newPage({ viewport: { width: 1280, height: 700 }, deviceScaleFactor: 1, locale: 'zh-CN' });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`${base}?story=screen-live&theme=light`);
  await page.waitForFunction(() => document.querySelector('[data-phase="live"]') && document.querySelector('canvas')?.width === 1600);
  const heard = () => page.evaluate(() => window.screenInputs.splice(0));
  const box = await page.evaluate(() => { const r = document.querySelector('canvas').getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
  assert.deepEqual(box, { x: 80, y: 0, w: 1120, h: 700 }, 'the picture fitted whole, in the middle');
  await heard();

  await page.mouse.move(640, 350);
  await page.mouse.down();
  await page.mouse.up();
  let got = await heard();
  const presses = got.filter((i) => i.t === 'pointer' && i.kind !== 'move');
  assert.deepEqual(presses.map((i) => [i.kind, i.buttons]), [['down', 1], ['up', 0]], 'a click: down with the button, up without');
  near(presses[0].x, 0.5, 'x'); near(presses[0].y, 0.5, 'y');

  // In the letterbox: nothing.
  await page.mouse.move(40, 350);
  await page.mouse.down();
  await page.mouse.up();
  got = await heard();
  assert.deepEqual(got.filter((i) => i.t === 'pointer' && i.kind !== 'move'), [], 'a click beside the picture says nothing');

  // A drag: moves with the button held, once a frame.
  await page.mouse.move(80 + 1120 * 0.25, 700 * 0.25);
  await page.mouse.down();
  await page.mouse.move(80 + 1120 * 0.75, 700 * 0.75, { steps: 8 });
  await page.mouse.up();
  got = await heard();
  const moves = got.filter((i) => i.t === 'pointer' && i.kind === 'move' && i.buttons === 1);
  assert.ok(moves.length >= 1, 'moves while dragging, with the button');
  near(moves.at(-1).x, 0.75, 'dragged to x'); near(moves.at(-1).y, 0.75, 'dragged to y');
  assert.equal(got.at(-1).kind, 'up');

  // The wheel, at the pointer.
  await page.mouse.move(640, 350);
  await page.mouse.wheel(0, 120);
  await page.waitForTimeout(100);
  got = (await heard()).filter((i) => i.t === 'wheel');
  assert.equal(got.reduce((n, i) => n + i.dy, 0), 120, 'the wheel, in pixels');

  // Keys: the picture was clicked, so they are the station's (not the app's shortcuts).
  await page.keyboard.press('a');
  await page.keyboard.press('Shift+Enter');
  await page.keyboard.press('Backspace');
  got = (await heard()).filter((i) => i.t === 'key');
  assert.deepEqual(got.map((i) => [i.kind, i.key, i.code, i.mods]), [
    ['down', 'a', 'KeyA', 0], ['up', 'a', 'KeyA', 0],
    ['down', 'Shift', 'ShiftLeft', 8], ['down', 'Enter', 'Enter', 8], ['up', 'Enter', 'Enter', 8], ['up', 'Shift', 'ShiftLeft', 0],
    ['down', 'Backspace', 'Backspace', 0], ['up', 'Backspace', 'Backspace', 0],
  ], 'keys as pressed');
  // An IME's text, as it commits; a paste's.
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.imeSetComposition', { text: 'ni', selectionStart: 2, selectionEnd: 2 });
  await cdp.send('Input.insertText', { text: '你好' });
  await page.evaluate(() => {
    const data = new DataTransfer();
    data.setData('text/plain', 'hunter2');
    document.activeElement.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
  });
  got = (await heard()).filter((i) => i.t === 'text');
  assert.deepEqual(got.map((i) => i.text), ['你好', 'hunter2'], 'text: an IME\'s, a paste\'s');
  if (out) await page.screenshot({ path: `${out}/screen-input-mouse.png` });

  // 只看: nothing goes.
  await page.mouse.move(640, 10);
  await page.getByRole('radio', { name: '只看' }).click();
  await page.waitForFunction(() => document.querySelector('[data-phase="live"] [data-driving]') === null);
  await heard();
  await page.mouse.move(640, 350);
  await page.mouse.down();
  await page.mouse.up();
  await page.keyboard.press('b');
  assert.deepEqual(await heard(), [], 'only looking: nothing said');
  assert.deepEqual(errors, []);
  await page.close();

  // ── a finger ──
  const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' });
  const p = await phone.newPage();
  p.on('pageerror', (e) => errors.push(e.message));
  await p.goto(`${base}?story=screen-phone&theme=light`);
  await p.waitForFunction(() => document.querySelector('[data-phase="live"]') && document.querySelector('canvas')?.width === 1600);
  const pic = await p.evaluate(() => { const r = document.querySelector('canvas').getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
  const at = (x, y) => ({ x: pic.x + pic.w * x, y: pic.y + pic.h * y });
  const fingers = await p.context().newCDPSession(p);
  const touch = (type, points) => fingers.send('Input.dispatchTouchEvent', { type, touchPoints: points.map((q, id) => ({ ...q, id })) });
  const said = () => p.evaluate(() => window.screenInputs.splice(0));
  await said();
  // A tap: a click where it is.
  await p.touchscreen.tap(at(0.5, 0.5).x, at(0.5, 0.5).y);
  got = (await said()).filter((i) => i.t === 'pointer');
  assert.deepEqual(got.map((i) => [i.kind, i.buttons]), [['down', 1], ['up', 0]], 'a tap clicks');
  near(got[0].x, 0.5, 'tap x'); near(got[0].y, 0.5, 'tap y');
  // A drag: down where it began, moves holding the button, up where it ended.
  await touch('touchStart', [at(0.2, 0.5)]);
  for (let i = 1; i <= 6; i++) { await touch('touchMove', [at(0.2 + i * 0.1, 0.5)]); await p.waitForTimeout(20); }
  await touch('touchEnd', []);
  got = (await said()).filter((i) => i.t === 'pointer');
  assert.equal(got[0].kind, 'down'); near(got[0].x, 0.2, 'drag from');
  assert.ok(got.some((i) => i.kind === 'move' && i.buttons === 1), 'moves holding the button');
  assert.equal(got.at(-1).kind, 'up'); near(got.at(-1).x, 0.8, 'drag to');
  // Two fingers up the picture: the page under them scrolls on down (the wheel, down), no click.
  await touch('touchStart', [at(0.4, 0.7), at(0.6, 0.7)]);
  for (let i = 1; i <= 5; i++) { await touch('touchMove', [at(0.4, 0.7 - i * 0.05), at(0.6, 0.7 - i * 0.05)]); await p.waitForTimeout(20); }
  await touch('touchEnd', []);
  got = await said();
  assert.deepEqual(got.filter((i) => i.t === 'pointer'), [], 'two fingers click nothing');
  const down = got.filter((i) => i.t === 'wheel').reduce((n, i) => n + i.dy, 0);
  assert.ok(Math.abs(down - pic.h * 0.25) < 2, `two fingers scroll as far as they went (${down})`);
  // The keyboard: its field focused, what is typed on it goes as text, Enter as a key.
  await p.getByRole('button', { name: '键盘' }).click();
  assert.ok(await p.evaluate(() => document.activeElement?.tagName === 'TEXTAREA'), 'the keyboard\'s field focused');
  await (await p.context().newCDPSession(p)).send('Input.insertText', { text: 'ok' });
  await p.keyboard.press('Enter');
  got = await said();
  assert.deepEqual(got.map((i) => i.t === 'text' ? i.text : `${i.kind} ${i.key}`), ['ok', 'down Enter', 'up Enter'], 'typed on the phone');
  if (out) await p.screenshot({ path: `${out}/screen-input-phone.png` });
  await phone.close();

  // ── an agent driving it: opened to look (nothing goes), 接管 makes it this view's ──
  const g = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1, locale: 'zh-CN' });
  g.on('pageerror', (e) => errors.push(e.message));
  await g.goto(`${base}?story=screen-agent-driving&theme=light`);
  await g.waitForFunction(() => document.querySelector('[data-phase="live"]') && document.querySelector('canvas')?.width === 1600);
  const told = () => g.evaluate(() => window.screenInputs.splice(0));
  await told();
  await g.mouse.click(640, 400);
  await g.keyboard.press('a');
  assert.deepEqual(await told(), [], 'while the agent drives, opening it takes nothing over');
  await g.waitForTimeout(2600);
  assert.ok(await g.getByText('Agent「修登录」 正在控制', { exact: true }).isVisible(), 'who drives it, still in sight after a rest');
  await g.getByRole('button', { name: '接管' }).click();
  await g.waitForFunction(() => document.querySelector('[data-driving]'));
  assert.ok(await g.getByText(/控制 · Agent「修登录」 已暂停/).isVisible(), 'taken over: the agent paused');
  await g.mouse.click(640, 400);
  got = (await told()).filter((i) => i.t === 'pointer' && i.kind !== 'move');
  assert.deepEqual(got.map((i) => i.kind), ['down', 'up'], 'taken over: the click goes');
  await g.close();

  // ── H.264, where the browser has it (Chrome; not Playwright's own Chromium): decoded, drawn, every frame acknowledged ──
  const h = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1, locale: 'zh-CN' });
  h.on('pageerror', (e) => errors.push(e.message));
  await h.goto(`${base}?story=screen-live-h264&theme=light`);
  await h.waitForFunction(() => window.screenSeen?.codec && window.screenSeen.acks.length >= 3, null, { timeout: 15000 });
  const seen = await h.evaluate(() => {
    const c = document.querySelector('canvas');
    // The page's ground under the form, and the green of its button (scene() in web/stories/screens.ts).
    const pixel = (x, y) => [...c.getContext('2d').getImageData(x, y, 1, 1).data.slice(0, 3)];
    return { codec: window.screenSeen.codec, acks: window.screenSeen.acks, size: [c.width, c.height], ground: pixel(800, 700), button: pixel(700, 560) };
  });
  assert.deepEqual(seen.size, [1600, 1000]);
  assert.deepEqual(seen.acks, [0, 400_000, 800_000], 'each frame acknowledged once drawn');
  const close = (a, b) => a.every((v, i) => Math.abs(v - b[i]) < 24);
  assert.ok(close(seen.ground, [0xf6, 0xf8, 0xfa]), `drawn: the page's ground (${seen.ground})`);
  assert.ok(close(seen.button, [0x1f, 0x88, 0x3d]), `drawn: the button (${seen.button})`);
  console.log(seen.codec === 'h264' ? 'H.264: decoded and drawn' : 'H.264: not in this browser, JPEG drawn instead');
  if (out) await h.screenshot({ path: `${out}/screen-input-h264.png` });
  assert.deepEqual(errors, []);
  console.log('ok: a screen driven by a mouse, keys, an IME, a paste and fingers; nothing while only looking');
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
