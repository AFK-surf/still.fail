// The workspaces in the phone's bottom bar's panel (web/src/mobile/Bar.tsx): with two, the panel's top row is them, the
// one in use ringed, the other's waiting count at its mark's corner; one stroke from the bar onto the other (the ball
// going with the finger) goes to the same place in it; tapped in the open panel, the same; the one in use tapped only
// closes the panel. The demo's core is given a second workspace (and what it has waiting) for it.
// PLAYWRIGHT_MODULE selects Playwright; SHOTS optionally keeps pictures.
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const fixture = new URL('../../web/bar-workspaces-check.tsx', import.meta.url);
const html = new URL('../../web/bar-workspaces-check.html', import.meta.url);

/** The demo with a second workspace, "Side", which has one chat gone wrong and one waiting; each path the router is sent to kept in window.__paths, as it is drawn (the demo's pages are its one workspace's and do not follow it to another: what is checked is where the bar sent it). */
const twoWorkspaces = {
  name: 'two-workspaces',
  enforce: 'pre',
  transform(code, id) {
    const swap = (from, to) => {
      if (!code.includes(from)) throw new Error(`bar-workspaces: ${id} no longer has ${from}`);
      code = code.replace(from, to);
    };
    if (id.endsWith('/src/demo/station.ts')) {
      swap('stations: 1, members: 4 }],', 'stations: 1, members: 4 }, { id: "side", name: "Side", role: "owner", created_at: at, stations: 1, members: 1, emoji: "🌊" }],');
      return code;
    }
    if (id.endsWith('/src/demo/mount.tsx')) {
      swap('case "workspaces": return station.workspaces();', `case "workspaces": return station.workspaces();
    case "workspaceMarks": return { workspaces: { demo: { alert: 0, unread: 0 }, side: { alert: 1, unread: 2, wait: 1, tone: "alert", label: "1 个出错了 · 1 个在等你" } }, others: "alert" };`);
      swap('<Director />', '<Director /><PathOnBody />');
      return code + '\nfunction PathOnBody() { const l = useLocation(); const p = (window.__paths ??= []); if (p.at(-1) !== l.pathname) p.push(l.pathname); return null; }\n';
    }
  },
};

let server, browser, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import './src/styles/index.ts';
import { DemoApp } from './src/demo/mount.tsx';
import { setPageRoot } from './src/brand.tsx';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
setPageRoot(root);
createRoot(root).render(<DemoApp phone />);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/bar-workspaces-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), plugins: [twoWorkspaces], server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch();
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' });

  const errors = [];
  /** A page on the demo's list, a place's top page. */
  const open = async () => {
    errors.length = 0;
    const page = await context.newPage();
    page.on('pageerror', (e) => { errors.push(e.message); console.error(e.message); });
    await page.goto(base + '/bar-workspaces-check.html');
    await page.locator('header').first().waitFor({ timeout: 30000 });
    await page.waitForTimeout(900);
    await page.getByRole('button', { name: /返回|会话/ }).first().tap();
    await page.waitForTimeout(900);
    await page.getByRole('tab', { name: '对话', exact: true }).waitFor({ timeout: 10000 });
    const cdp = await context.newCDPSession(page);
    const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
    return { page, touch };
  };
  const shot = async (page, name, dark = false) => {
    if (!out) return;
    await page.evaluate((theme) => { document.documentElement.dataset.theme = theme; }, dark ? 'dark' : 'light');
    await page.waitForTimeout(150);
    await page.screenshot({ path: `${out}/${name}.png` });
    await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
  };
  const paths = (page) => page.evaluate(() => window.__paths ?? []);
  const centre = (b) => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 });
  const ballCentre = (page) => page.locator('[data-bar=ball]').evaluate((e) => { const r = e.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });

  // ---- One stroke from 文件 up onto Side: the same place there.
  {
    const { page, touch } = await open();
    await page.getByRole('tab', { name: '文件', exact: true }).tap();
    await page.waitForTimeout(900);
    const from = centre(await page.getByRole('tab', { name: '文件', exact: true }).boundingBox());
    await touch('touchStart', from.x, from.y);
    for (let k = 1; k <= 14; k++) { await touch('touchMove', from.x, from.y - 10 * k); await page.waitForTimeout(16); }
    await page.waitForTimeout(700);
    const chips = page.locator('[data-bar=rows] [data-ws]');
    assert.equal(await chips.count(), 2, 'both workspaces in the panel\'s top row');
    assert.notEqual(await page.locator('[data-ws=demo]').getAttribute('data-here'), null, 'the one in use is marked');
    assert.equal(await page.locator('[data-ws=side] [data-tone=alert]').count(), 1, 'Side\'s dot says something went wrong there');
    // In the columns a bar's places are in (two: at its ends), a row as tall as a bar's.
    const ends = [await page.locator('[data-bar=rows] [data-place]').first().boundingBox(), await page.locator('[data-bar=rows] [data-place]').nth(3).boundingBox()];
    const ws = [await page.locator('[data-ws=demo]').boundingBox(), await page.locator('[data-ws=side]').boundingBox()];
    for (const k of [0, 1]) assert.ok(Math.abs(centre(ws[k]).x - centre(ends[k]).x) < 1, `workspace ${k} in the column of a bar's place ${k * 3}`);
    assert.ok(Math.abs(centre(ends[0]).y - centre(ws[0]).y - 56) < 1, 'a bar\'s row under the workspaces\'');
    // The workspaces' row is above the other bar's.
    const row = await page.locator('[data-ws=side]').boundingBox(), bar = await page.getByRole('button', { name: '连接', exact: true }).first().boundingBox();
    assert.ok(row.y + row.height <= bar.y + 1, 'the workspaces above the other bar');
    const side = centre(row);
    for (let k = 1; k <= 10; k++) { await touch('touchMove', from.x + (side.x - from.x) * k / 10, from.y - 140 + (side.y - from.y + 140) * k / 10); await page.waitForTimeout(16); }
    await page.waitForTimeout(600);
    const ball = await ballCentre(page);
    assert.ok(Math.abs(ball.x - side.x) < 12 && Math.abs(ball.y - side.y) < 12, `the ball is over Side (${JSON.stringify(ball)} vs ${JSON.stringify(side)})`);
    assert.notEqual(await page.locator('[data-ws=side]').getAttribute('data-on'), null, 'Side lit under the finger');
    await shot(page, 'ws-stroke');
    await shot(page, 'ws-stroke-dark', true);
    // (The demo's pages are its one workspace's: in another they go wrong, so what went wrong is looked at before.)
    assert.deepEqual(errors.splice(0), [], 'no errors on the page');
    await touch('touchEnd');
    await page.waitForTimeout(1200);
    assert.ok((await paths(page)).includes('/w/side/files'), `Side's 文件 (${await paths(page)})`);
    await page.close();
  }

  // ---- Tapped in the open panel, on the chats: Side's chats. The one in use tapped: closed, nowhere else.
  {
    const { page, touch } = await open();
    const from = centre(await page.getByRole('tab', { name: '对话', exact: true }).boundingBox());
    const swipeUp = async () => {
      await touch('touchStart', from.x, from.y);
      for (let k = 1; k <= 4; k++) { await touch('touchMove', from.x, from.y - 12 * k); await page.waitForTimeout(16); }
      await touch('touchEnd');
      await page.waitForTimeout(900);
    };
    await swipeUp();
    assert.ok(await page.locator('[data-bar=scrim]').count() > 0, 'the panel stays open');
    await shot(page, 'ws-panel');
    await page.locator('[data-ws=demo]').tap();
    await page.waitForTimeout(700);
    assert.equal(await page.locator('[data-bar=scrim]').count(), 0, 'the panel closed');
    assert.ok(!(await paths(page)).some((p) => p.startsWith('/w/side')), `still Acme's (${await paths(page)})`);
    await swipeUp();
    assert.deepEqual(errors.splice(0), [], 'no errors on the page');
    await page.locator('[data-ws=side]').tap();
    await page.waitForTimeout(1200);
    assert.ok((await paths(page)).includes('/w/side'), `Side's chats (${await paths(page)})`);
    await page.close();
  }
  console.log('bar-workspaces: ok');
} finally {
  await browser?.close();
  await server?.close();
  if (madeFixture) await rm(fixture, { force: true });
  if (madeHtml) await rm(html, { force: true });
}
