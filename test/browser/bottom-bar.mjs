// The phone's bottom bar (web/src/mobile/Bar.tsx): on a place's top page, the ball 6 past the bar on every side over
// the place in view; a tap goes to another place (in place, no page pushed, its scroll kept), the page's primary
// action (令 on the chats' pages, a ＋) in the notch; one stroke up from the bar opens the panel and lets go on a place
// of the other bar (that bar, and that place: its page at once, under the glass closing); a page pushed over a place
// sends the bar away; Settings · 下方栏 lists the bars. Runs its own Vite fixture with the demo core.
// PLAYWRIGHT_MODULE selects Playwright; SHOTS optionally keeps pictures.
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const fixture = new URL('../../web/bottom-bar-check.tsx', import.meta.url);
const html = new URL('../../web/bottom-bar-check.html', import.meta.url);
let server, browser, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import './src/styles/index.ts';
import { DemoApp } from './src/demo/mount.tsx';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
createRoot(root).render(<DemoApp phone />);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/bottom-bar-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)),
    plugins: [{ name: 'bar-history-check', enforce: 'pre', transform(code, id) {
      if (!id.split('?')[0].endsWith('/demo/mount.tsx')) return;
      return code.replace('const go = useNavigate();', 'const go = useNavigate(); (window as any).barHistoryGo = go;')
        .replace('const here = useLocation().pathname;', 'const here = useLocation().pathname; (window as any).barHistoryPath = here;');
    } }], server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch({ executablePath: process.env.CHROMIUM });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' });
  const page = await context.newPage();
  await page.clock.install();
  const errors = [];
  page.on('pageerror', (e) => { errors.push(e.message); console.error(e.message); });
  await page.goto(base + '/bottom-bar-check.html');
  const rest = () => page.waitForTimeout(900);
  const shot = async (name, dark = false) => {
    if (!out) return;
    await page.evaluate((theme) => { document.documentElement.dataset.theme = theme; }, dark ? 'dark' : 'light');
    await page.waitForTimeout(150);
    await page.screenshot({ path: `${out}/${name}.png` });
    await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
  };
  const cdp = await context.newCDPSession(page);
  let controlled = null;
  const touch = (type, x, y) => {
    if (!controlled) return cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
    if (type !== 'touchEnd') Object.assign(controlled, { x, y });
    return controlled.target.dispatchEvent(type === 'touchStart' ? 'pointerdown' : type === 'touchEnd' ? 'pointerup' : 'pointermove',
      { pointerId: 1, pointerType: 'touch', buttons: type === 'touchEnd' ? 0 : 1, clientX: controlled.x, clientY: controlled.y });
  };
  const tab = (name) => page.getByRole('tab', { name, exact: true });
  const NEW_CHAT = '新建对话';
  const bar = () => page.evaluate(() => {
    const host = document.querySelector('[role=tablist]')?.closest('[class]')?.parentElement?.parentElement;
    const row = document.querySelector('[role=tablist]').getBoundingClientRect();
    const ball = [...document.querySelectorAll('[role=tablist] ~ div')].map((e) => e.getBoundingClientRect()).find((r) => Math.round(r.width) === 68);
    const away = !!document.querySelector('[data-away]');
    return { row: { top: row.top, bottom: row.bottom, left: row.left, right: row.right }, ball: ball && { top: ball.top, bottom: ball.bottom, left: ball.left, right: ball.right }, away, host: !!host };
  });

  // The demo opens on a chat: back to the list, a place's top page.
  await page.locator('header').first().waitFor({ timeout: 30000 });
  await rest();
  const chatPath = await page.evaluate(() => window.barHistoryPath);
  await page.getByRole('button', { name: /返回|会话/ }).first().tap();
  await rest();
  await tab('对话').waitFor({ timeout: 10000 });
  let b = await bar();
  assert.ok(!b.away, 'the bar is up on the list');
  assert.ok(b.ball, 'the ball is drawn');
  // 6 past the bar on every side, over 对话 (the first place).
  for (const [side, d] of [['top', b.row.top - b.ball.top], ['bottom', b.ball.bottom - b.row.bottom], ['left', b.row.left - b.ball.left]]) {
    assert.ok(Math.abs(d - 6) < 1, `the ball is 6 past the bar's ${side} (${d.toFixed(1)})`);
  }
  assert.equal(await page.getByRole('button', { name: '返回' }).count(), 0, 'no back on a place\'s top page');
  await shot('home');
  await shot('home-dark', true);

  // The initial chat was replaced with Home by its back button. The older Home entry
  // predates the shell's page stack: browser back must still land on a root with its bar.
  await page.evaluate(() => window.barHistoryGo(-1));
  await rest();
  await shot('home-after-browser-back');
  assert.equal(await page.locator('[data-bar=host][data-away]').count(), 0, 'browser back to an older home restores the bar');
  await tab('对话').tap();
  await rest();
  assert.equal(await page.locator('[data-role=top]').count(), 1, 'the returned home is the active root');
  await page.evaluate((path) => window.barHistoryGo(path), chatPath);
  await rest();
  assert.equal(await page.locator('[data-bar=host][data-away]').count(), 1, 'opening a chat hides the bar');
  await page.getByRole('button', { name: /返回|会话/ }).first().tap();
  await rest();
  assert.equal(await page.locator('[data-bar=host][data-away]').count(), 0, 'returning from that chat restores the bar again');

  // The panel snaps as the ball does (one other bar: 56 of travel): held a little way above the bar, it opens of itself
  // (but for a quarter's lean toward the finger) and stays so while held; back down below the line, it closes while
  // still held; let go, it is as the line left it, never resting between.
  const openness = () => page.evaluate(() => {
    const g = document.querySelector('[data-bar=glass]').getBoundingClientRect(), r = document.querySelector('[role=tablist]').getBoundingClientRect();
    return (r.top - g.top) / 56;
  });
  const c0 = await tab('对话').boundingBox(), px = c0.x + c0.width / 2, top = c0.y;
  // Advance every animation frame: a loaded browser may deliver too few real frames before a wall-clock sleep ends.
  // The held panel must reach and keep its target regardless of how quickly this machine draws those frames.
  await page.clock.pauseAt(await page.evaluate(() => Date.now()));
  // Native touch delivery follows the compositor's real clock; feed pointer events directly during this clocked part.
  const heldTarget = page.locator('[data-bar=glass]').locator('..');
  await heldTarget.evaluate(el => { window.savedCapture = el.setPointerCapture; el.setPointerCapture = () => {}; });
  controlled = { target: heldTarget, x: px, y: top + 28 };
  const frames = async (ms) => { for (let at = 0; at < ms; at += 16) await page.clock.runFor(Math.min(16, ms - at)); };
  const fingerTo = async (y) => { await touch('touchMove', px, y); await frames(16); };
  await touch('touchStart', px, top + 28);
  for (let k = 1; k <= 8; k++) await fingerTo(top + 28 - (28 + 30) * k / 8); // 30 over the bar's top: over the line
  await frames(700);
  const up1 = await openness();
  await frames(300);
  assert.ok(up1 > 0.95 && Math.abs(await openness() - up1) < 0.01, `over the line, held: open, and stays (${up1.toFixed(2)})`);
  for (let k = 1; k <= 6; k++) await fingerTo(top - 30 + 30 * k / 6); // back down to the bar's top: under the line
  await frames(700);
  const down1 = await openness();
  assert.ok(down1 < 0.2, `back under the line, still held: closed but for the lean (${down1.toFixed(2)})`);
  await touch('touchEnd');
  await frames(700);
  assert.ok(await openness() < 0.02, 'let go under the line: closed');
  await touch('touchStart', px, top + 28);
  for (let k = 1; k <= 8; k++) await fingerTo(top + 28 - 58 * k / 8);
  await touch('touchEnd');
  await frames(900);
  assert.ok(await openness() > 0.97 && await page.locator('[data-bar=scrim]').count(), 'let go over the line: open');
  await page.locator('[data-bar=scrim]').dispatchEvent('pointerdown');
  await frames(900);
  controlled = null;
  await heldTarget.evaluate(el => { el.setPointerCapture = window.savedCapture; });
  await page.clock.resume();

  // The list scrolled a little (on a shorter screen, for the demo's few chats to run past it), to be found so again.
  await page.setViewportSize({ width: 390, height: 520 });
  await page.waitForTimeout(300);
  const scrolled = () => page.evaluate(() => Math.max(...[...document.querySelectorAll('[data-role=top] *')].map((e) => e.scrollTop)));
  await page.evaluate(() => { for (const e of document.querySelectorAll('[data-role=top] *')) if (e.scrollHeight > e.clientHeight + 40 && getComputedStyle(e).overflowY === 'auto') e.scrollTop = 120; });
  await page.waitForTimeout(200);
  const at = await scrolled();
  assert.ok(at > 0, 'the list scrolls');

  // A tap on 文件: its page in place, a place's own (its head the gear and its name, no back), its primary action (the
  // demo's viewer is an admin: lend a folder) in the notch where 令 was, the ball over 文件.
  await tab('文件').tap();
  await rest();
  assert.ok(await page.locator('[data-role=top] h1', { hasText: '文件' }).isVisible(), 'the files\' page, its name in its head');
  assert.equal(await page.locator('[data-role=top]').getByRole('button', { name: '返回' }).count(), 0, 'no back on a place\'s own page');
  const action = await page.locator('[data-action]').evaluate((e) => ({ label: e.getAttribute('aria-label'), key: e.dataset.action, opacity: +getComputedStyle(e).opacity }));
  assert.deepEqual([action.key, action.opacity > 0.9], ['folder', true], `the notch holds the folder action (${JSON.stringify(action)})`);
  assert.match(action.label, /文件夹/, 'the folder action has its accessible label');
  b = await bar();
  const files = await tab('文件').boundingBox();
  assert.ok(Math.abs((b.ball.left + b.ball.right) / 2 - (files.x + files.width / 2)) < 2, 'the ball is over 文件');
  await shot('files');

  // Back on 对话: the list where it was left, 令 in the notch again.
  await tab('对话').tap();
  await rest();
  assert.equal(await scrolled(), at, 'the list as it was scrolled');
  assert.equal(await page.locator('[data-action]').getAttribute('aria-label'), NEW_CHAT, '令 in the notch');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(300);

  // One stroke: from 对话 up into the panel, onto 连接 in the other bar, let go: that bar, and 连接's page.
  const from = await tab('文件').boundingBox();
  const sx = from.x + from.width / 2, sy = from.y + from.height / 2;
  await touch('touchStart', sx, sy);
  for (let k = 1; k <= 10; k++) { await touch('touchMove', sx, sy - 9 * k); await page.waitForTimeout(16); }
  await page.waitForTimeout(700);
  await shot('panel');
  const target = await page.getByRole('button', { name: '连接', exact: true }).first().boundingBox();
  assert.ok(target, 'the other bar\'s places are in the panel');
  const tx = target.x + target.width / 2, ty = target.y + target.height / 2;
  for (let k = 1; k <= 10; k++) { await touch('touchMove', sx + (tx - sx) * k / 10, sy - 90 + (ty - sy + 90) * k / 10); await page.waitForTimeout(16); }
  await page.waitForTimeout(400);
  await touch('touchEnd');
  // A finger on the bar as the switch lands: it lands untouched (closing all the way, never back up or held).
  await page.waitForTimeout(30);
  const glassW = () => page.evaluate(() => document.querySelector('[data-bar=glass]').getBoundingClientRect().width);
  const wide = await glassW(), widths = [];
  const landing = [await openness()];
  await touch('touchStart', sx, sy);
  for (let k = 0; k < 8; k++) { await page.waitForTimeout(25); landing.push(await openness()); widths.push(await glassW()); }
  assert.ok(widths.every((v) => Math.abs(v - wide) < 1), `the glass keeps its width as it closes (${wide}: ${widths.map(Math.round).join(' ')})`);
  await touch('touchEnd');
  assert.ok(landing.every((v, k) => k === 0 || v <= landing[k - 1] + 0.01) && landing.at(-1) < landing[0] - 0.5, `a touch does not stop the landing (${landing.map((v) => v.toFixed(2)).join(' ')})`);
  await page.waitForTimeout(1500);
  assert.ok(await tab('连接').count() > 0 && await tab('连接').isVisible(), 'the bar is now the other bar');
  assert.ok(page.url().includes('/connects') || await page.getByText('连接', { exact: true }).count() > 0, '连接\'s page');
  await shot('switched');

  // Settings · 下方栏: its bars as cards.
  await page.evaluate(() => history.length);
  await tab('用量').tap();
  await rest();
  // Back to the chats' bar from the panel, then settings (a page pushed: the bar goes away).
  const p0 = await tab('用量').boundingBox();
  await touch('touchStart', p0.x + p0.width / 2, p0.y + p0.height / 2);
  for (let k = 1; k <= 12; k++) { await touch('touchMove', p0.x + p0.width / 2, p0.y - 8 * k); await page.waitForTimeout(16); }
  await page.waitForTimeout(600);
  const chatsThere = await page.getByRole('button', { name: '对话', exact: true }).first().boundingBox();
  await touch('touchMove', chatsThere.x + chatsThere.width / 2, chatsThere.y + chatsThere.height / 2);
  await page.waitForTimeout(300);
  await touch('touchEnd');
  await page.waitForTimeout(1500);
  await tab('对话').waitFor();

  // Another bar's place chosen: its page at once, under the glass still closing over it (not once that has landed).
  const stroke = async (from, to) => {
    const r = await tab(from).boundingBox(), x = r.x + r.width / 2, y = r.y + r.height / 2;
    await touch('touchStart', x, y);
    for (let k = 1; k <= 12; k++) { await touch('touchMove', x, y - 8 * k); await page.waitForTimeout(16); }
    await page.waitForTimeout(700);
    const t = await page.locator(`[data-bar=rows] [data-place=${to}]`).boundingBox();
    await touch('touchMove', t.x + t.width / 2, t.y + t.height / 2);
    await page.waitForTimeout(300);
    await touch('touchEnd');
  };
  await stroke('对话', 'connects');
  await page.waitForTimeout(60);
  assert.ok(await page.locator('[data-bar=stack]').count() > 0, 'the bar still being chosen');
  assert.ok(await page.locator('[data-role=top]').getByText('连接', { exact: true }).first().isVisible(), '连接\'s page already in view');
  await page.waitForTimeout(1500);
  assert.ok(await tab('连接').isVisible(), 'the bar switched');
  // To the chats in the bar it is now, then settings.
  await stroke('用量', 'chats');
  await page.waitForTimeout(1500);
  await tab('对话').waitFor();
  await page.getByRole('button', { name: '设置' }).first().tap();
  await rest();
  assert.ok((await bar()).away, 'the bar is away over a pushed page');
  await page.getByText('下方栏', { exact: true }).tap();
  await rest();
  assert.ok(await page.getByText('第 1 栏', { exact: true }).isVisible(), 'the bars are listed');
  assert.ok(await page.getByText('第 2 栏', { exact: true }).isVisible());
  await shot('settings');

  assert.deepEqual(errors, [], 'no errors on the page');
  console.log('bottom bar: ok');
} finally {
  await browser?.close();
  await server?.close();
  if (madeFixture) await rm(fixture);
  if (madeHtml) await rm(html);
}
