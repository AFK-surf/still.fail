// A station's screen driven from the page (web/src/screen/ScreenViewer.tsx, input.ts): in the stories' live view (its
// made-up station draws real JPEG frames: web/stories/screens.ts, which keeps what the view was told in
// `window.screenInputs`), the picture letterboxed in a window of another shape, then a mouse (a click at the picture's
// middle is 0.5, 0.5; one in the letterbox says nothing), the wheel, keys, an IME's and a paste's text, 只看 (nothing
// goes), and on a phone a finger: as a trackpad (it moves the pointer, a tap clicks where it points, two tapped
// right-click), the keys row's modifiers held for the next key; then directly, a tap clicks, a drag holds the button,
// two fingers scroll. Builds the stories and serves the build, as stories.mjs does. PLAYWRIGHT_MODULE selects Playwright;
// SHOTS keeps a picture of each.
// The page's time is the test's (Playwright's clock, held still): its timers (a finger held as long as a press, the
// station's word on the pointer taken again, its pauses between frames) and its frames run only as far as the test says,
// and a finger's events say when they happen (their timeStamp: a double tap, a two-finger tap, how fast a finger moved
// the pointer), never what real time took between them. What comes in real time (a frame encoded, decoded, drawn) is
// waited for by what it does.
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
/** The page's clock from a moment of its own, held there: on only as far as `run` says. */
const T0 = new Date('2026-10-24T08:00:00Z');
const held = async (page) => { await page.clock.install({ time: T0 }); await page.clock.pauseAt(new Date(T0.getTime() + 1000)); };
const run = (page, ms) => page.clock.runFor(ms);
/** Until `fn` holds in the page, its time run on a little at a time meanwhile (what the station times by it: its pauses
 *  between frames), what comes in real time let in between (a frame encoded, decoded). Then the station's frames all
 *  sent (three, a quarter of a second apart), so that what follows starts from the same place every time. */
const opened = async (page, fn, arg) => {
  for (const end = Date.now() + 20000; !(await page.evaluate(fn, arg));) {
    assert.ok(Date.now() < end, `never came: ${fn}`);
    await run(page, 50);
  }
  await run(page, 1000);
};
const liveAt = (w) => !!document.querySelector('[data-phase="live"]') && document.querySelector('canvas')?.width === w;
try {
  const configFile = fileURLToPath(new URL('../../web/vite.stories.config.ts', import.meta.url));
  dist = await mkdtemp(join(tmpdir(), 'screen-input-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  // ── a mouse and keys ──
  // 1280×700: the bar along the top (always there, ViewerBar.tsx), the 1600×1000 picture fitted whole under it, in the
  // middle of what is left (under a bar 45 high: 1048×655, 116 in from either side).
  const page = await browser.newPage({ viewport: { width: 1280, height: 700 }, deviceScaleFactor: 1, locale: 'zh-CN' });
  await held(page);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`${base}?story=screen-live&theme=light`);
  await opened(page, liveAt, 1600);
  const heard = () => page.evaluate(() => window.screenInputs.splice(0));
  const { box, under } = await page.evaluate(() => {
    const rect = (el) => { const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; };
    const bar = rect(document.querySelector('[data-phase="live"] header'));
    return { box: rect(document.querySelector('canvas')), under: bar.y + bar.h };
  });
  assert.ok(under > 0, 'the bar along the top');
  const scale = Math.min(1280 / 1600, (700 - under) / 1000);
  assert.deepEqual(box, { x: (1280 - 1600 * scale) / 2, y: under, w: 1600 * scale, h: 1000 * scale }, 'the picture fitted whole under the bar, in the middle');
  /** A point of the picture (0 to 1 across and down it) in the window. */
  const on = (x, y) => [box.x + box.w * x, box.y + box.h * y];
  await heard();

  await page.mouse.move(...on(0.5, 0.5));
  await page.mouse.down();
  await page.mouse.up();
  let got = await heard();
  const presses = got.filter((i) => i.t === 'pointer' && i.kind !== 'move');
  assert.deepEqual(presses.map((i) => [i.kind, i.buttons]), [['down', 1], ['up', 0]], 'a click: down with the button, up without');
  near(presses[0].x, 0.5, 'x'); near(presses[0].y, 0.5, 'y');

  // In the letterbox: nothing.
  await page.mouse.move(box.x / 2, box.y + box.h / 2);
  await page.mouse.down();
  await page.mouse.up();
  got = await heard();
  assert.deepEqual(got.filter((i) => i.t === 'pointer' && i.kind !== 'move'), [], 'a click beside the picture says nothing');

  // A drag: moves with the button held, once a frame (the frame's on the page's clock).
  await page.mouse.move(...on(0.25, 0.25));
  await page.mouse.down();
  await page.mouse.move(...on(0.5, 0.5), { steps: 4 });
  await run(page, 20);
  await page.mouse.move(...on(0.75, 0.75), { steps: 4 });
  await run(page, 20);
  await page.mouse.up();
  got = await heard();
  const moves = got.filter((i) => i.t === 'pointer' && i.kind === 'move' && i.buttons === 1);
  assert.ok(moves.length >= 1, 'moves while dragging, with the button');
  near(moves.at(-1).x, 0.75, 'dragged to x'); near(moves.at(-1).y, 0.75, 'dragged to y');
  assert.equal(got.at(-1).kind, 'up');

  // The wheel, at the pointer.
  await page.mouse.move(...on(0.5, 0.5));
  await page.mouse.wheel(0, 120);
  await run(page, 20);
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
  await page.mouse.move(...on(0.5, 0.5));
  await page.mouse.down();
  await page.mouse.up();
  await page.keyboard.press('b');
  assert.deepEqual(await heard(), [], 'only looking: nothing said');
  assert.deepEqual(errors, []);
  await page.close();

  // ── a finger ──
  const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' });
  const p = await phone.newPage();
  await held(p);
  p.on('pageerror', (e) => errors.push(e.message));
  await p.goto(`${base}?story=screen-phone&theme=light`);
  await opened(p, liveAt, 1600);
  const pic = await p.evaluate(() => { const r = document.querySelector('canvas').getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
  const at = (x, y) => ({ x: pic.x + pic.w * x, y: pic.y + pic.h * y });
  const fingers = await p.context().newCDPSession(p);
  // A finger's events at the page's time: each says when it happened (`timestamp`, the event's timeStamp), the time
  // the test has run the page's clock on by since it began (`pass`).
  let now = Date.now() / 1000;
  const pass = async (ms) => { now += ms / 1000; await run(p, ms); };
  const touch = (type, points) => fingers.send('Input.dispatchTouchEvent', { type, timestamp: now, touchPoints: points.map((q, id) => ({ ...q, id })) });
  /** A finger along `points`, 20 ms between each (its frames taken in as it goes), lifted at the last. */
  const along = async (...points) => {
    await touch('touchStart', points[0]);
    for (const q of points.slice(1)) { await pass(20); await touch('touchMove', q); }
    await pass(20);
    await touch('touchEnd', []);
    await pass(20);
  };
  const tap = async (q) => { await touch('touchStart', [q]); await pass(50); await touch('touchEnd', []); await pass(20); };
  const said = () => p.evaluate(() => window.screenInputs.splice(0));
  await said();
  // ── as a trackpad (unless the device keeps `direct`) ──
  // A tap anywhere: a click where the pointer is (where the station says it is: the demo's 0.5, 0.565).
  await tap(at(0.1, 0.1));
  got = (await said()).filter((i) => i.t === 'pointer');
  assert.deepEqual(got.map((i) => [i.kind, i.buttons]), [['down', 1], ['up', 0]], 'a tap on the trackpad clicks');
  near(got[0].x, 0.5, 'trackpad tap x'); near(got[0].y, 0.565, 'trackpad tap y');
  await pass(400);
  // A finger moved right: the pointer goes right, no button held.
  await along(...Array.from({ length: 7 }, (_, i) => [at(0.2 + i * 0.03, 0.3)]));
  got = (await said()).filter((i) => i.t === 'pointer');
  assert.ok(got.length > 0 && got.every((i) => i.kind === 'move' && i.buttons === 0), `the trackpad moves the pointer: ${JSON.stringify(got)}`);
  const padX = got.at(-1).x;
  assert.ok(padX > 0.55 && padX <= 1, `moved right: ${padX}`);
  near(got.at(-1).y, 0.565, 'moved along');
  // Two fingers tapped: the right button where it points.
  await pass(400);
  await touch('touchStart', [at(0.3, 0.5), at(0.6, 0.5)]);
  await pass(60);
  await touch('touchEnd', []);
  await pass(20);
  got = (await said()).filter((i) => i.t === 'pointer');
  assert.deepEqual(got.map((i) => [i.kind, i.buttons]), [['down', 2], ['up', 0]], 'two fingers tapped right-click');
  near(got[0].x, padX, 'right click where it points');
  // ⌘ held on the keys row, then Tab: ⌘Tab; Tab again goes alone.
  await p.getByRole('button', { name: 'Command' }).click();
  await p.getByRole('button', { name: 'Tab' }).click();
  await p.getByRole('button', { name: 'Tab' }).click();
  got = await said();
  assert.deepEqual(got.map((i) => [i.kind, i.code, i.mods]), [['down', 'Tab', 4], ['up', 'Tab', 4], ['down', 'Tab', 0], ['up', 'Tab', 0]], 'a modifier held for the next key');
  // ── directly ──
  await p.getByRole('button', { name: '触控板' }).click();
  await p.waitForFunction(() => document.querySelector('button[aria-label="触控板"]')?.getAttribute('aria-pressed') === 'false');
  await pass(400);
  // A tap: a click where it is.
  await tap(at(0.5, 0.5));
  got = (await said()).filter((i) => i.t === 'pointer');
  assert.deepEqual(got.map((i) => [i.kind, i.buttons]), [['down', 1], ['up', 0]], 'a tap clicks');
  near(got[0].x, 0.5, 'tap x'); near(got[0].y, 0.5, 'tap y');
  // A drag: down where it began, moves holding the button, up where it ended.
  await along(...Array.from({ length: 7 }, (_, i) => [at(0.2 + i * 0.1, 0.5)]));
  got = (await said()).filter((i) => i.t === 'pointer');
  assert.equal(got[0].kind, 'down'); near(got[0].x, 0.2, 'drag from');
  assert.ok(got.some((i) => i.kind === 'move' && i.buttons === 1), 'moves holding the button');
  assert.equal(got.at(-1).kind, 'up'); near(got.at(-1).x, 0.8, 'drag to');
  // Two fingers up the picture: the page under them scrolls on down (the wheel, down), no click.
  await along(...Array.from({ length: 6 }, (_, i) => [at(0.4, 0.7 - i * 0.05), at(0.6, 0.7 - i * 0.05)]));
  got = await said();
  assert.deepEqual(got.filter((i) => i.t === 'pointer'), [], 'two fingers click nothing');
  const down = got.filter((i) => i.t === 'wheel').reduce((n, i) => n + i.dy, 0);
  assert.ok(Math.abs(down - pic.h * 0.25) < 2, `two fingers scroll as far as they went (${down})`);
  // The keyboard: its field focused, what is typed on it goes as text, Enter as a key. (What 触控板 said, over the keys
  // row, gone first: a toast's 2.6 s.)
  await pass(3000);
  await p.getByRole('button', { name: '键盘' }).click();
  assert.ok(await p.evaluate(() => document.activeElement?.tagName === 'TEXTAREA'), 'the keyboard\'s field focused');
  await (await p.context().newCDPSession(p)).send('Input.insertText', { text: 'ok' });
  await p.keyboard.press('Enter');
  got = await said();
  assert.deepEqual(got.map((i) => i.t === 'text' ? i.text : `${i.kind} ${i.key}`), ['ok', 'down Enter', 'up Enter'], 'typed on the phone');
  if (out) await p.screenshot({ path: `${out}/screen-input-phone.png` });
  // 全屏: the picture's stage the whole window, the bars away, the tools folded into the corner's button.
  await p.getByRole('button', { name: '全屏' }).click();
  const whole = await p.evaluate(() => { const r = document.querySelector('[data-full] [data-driving]')?.getBoundingClientRect(); return r && [r.left, r.top, r.width, r.height]; });
  assert.deepEqual(whole, [0, 0, 390, 844], 'full: the stage is the window');
  assert.equal(await p.getByRole('button', { name: '键盘' }).count(), 0, 'full: the bars folded away');
  await p.getByRole('button', { name: '工具' }).click();
  await p.getByRole('button', { name: '退出全屏' }).click();
  assert.equal(await p.locator('[data-full]').count(), 0, 'out of full');
  await phone.close();

  // ── an agent driving it: opened to look (nothing goes), 接管 makes it this view's ──
  const g = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1, locale: 'zh-CN' });
  g.on('pageerror', (e) => errors.push(e.message));
  await held(g);
  await g.goto(`${base}?story=screen-agent-driving&theme=light`);
  await opened(g, liveAt, 1600);
  const told = () => g.evaluate(() => window.screenInputs.splice(0));
  await told();
  await g.mouse.click(640, 400);
  await g.keyboard.press('a');
  assert.deepEqual(await told(), [], 'while the agent drives, opening it takes nothing over');
  await run(g, 2600);
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
  await held(h);
  await h.goto(`${base}?story=screen-live-h264&theme=light`);
  await opened(h, () => !!window.screenSeen?.codec && window.screenSeen.acks.length >= 3);
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
